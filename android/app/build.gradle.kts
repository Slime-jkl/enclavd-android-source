import com.android.build.api.instrumentation.AsmClassVisitorFactory
import com.android.build.api.instrumentation.ClassContext
import com.android.build.api.instrumentation.ClassData
import com.android.build.api.instrumentation.InstrumentationParameters
import com.android.build.api.instrumentation.InstrumentationScope
import com.android.build.api.variant.FilterConfiguration
import org.objectweb.asm.AnnotationVisitor
import org.objectweb.asm.Attribute
import org.objectweb.asm.ClassVisitor
import org.objectweb.asm.FieldVisitor
import org.objectweb.asm.MethodVisitor
import org.objectweb.asm.Opcodes

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Applied below only when google-services.json exists; without it the app
    // falls back to Unified Push.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// FCM config is optional: builds without google-services.json just skip Firebase.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.enclavd.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // AGP 9: the getter is isCoreLibraryDesugaringEnabled().
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        // CI-only upload key; without it release builds are unsigned.
        if (System.getenv("IS_GITHUB_ACTION") == "true") {
            create("release") {
                storeFile = file(System.getenv("SIGNING_KEY_FILE") ?: "")
                storePassword = System.getenv("KEY_STORE_PASSWORD")
                keyAlias = System.getenv("ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.enclavd.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Flavors mirror CI's --dart-define flavors; fdroid must stay free of Google code.
    flavorDimensions += "app"
    productFlavors {
        create("play") { dimension = "app" }
        create("fdroid") { dimension = "app" }
        create("dev") { dimension = "app" }
    }

    buildTypes {
        release {
            // findByName returns null when unconfigured: unsigned build, not debug-signed.
            signingConfig = signingConfigs.findByName("release")
        }
    }

    // The generated registrant references firebase plugins the fdroid flavor
    // excludes; the committed src/fdroid copy replaces it, so drop it here.
    if (project.gradle.startParameter.taskNames.any { it.contains("Fdroid", ignoreCase = true) }) {
        project.file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java").delete()
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// F-Droid: the binary must not ship Google classes; exclude firebase and
// play-services from every fdroid variant.
configurations.configureEach {
    if (name.contains("fdroid", ignoreCase = true)) {
        exclude(group = "com.google.firebase")
        exclude(group = "com.google.android.gms")
        // play-core sneaks in via AGP dependency wiring; exclude the whole group.
        exclude(group = "com.google.android.play")
        exclude(module = "firebase_core")
        exclude(module = "firebase_messaging")
    }
}

// Mirror the fdroid release APK where fdroidserver looks for it: it searches
// under <subdir>/build/outputs/apk/..., Flutter emits elsewhere.
val mirrorFdroidApk by tasks.registering(Copy::class) {
    from(layout.buildDirectory.dir("outputs/apk/fdroid/release"))
    into(rootProject.layout.buildDirectory.dir("outputs/apk/fdroid/release"))
}
tasks.whenTaskAdded {
    if (name == "assembleFdroidRelease") {
        finalizedBy(mirrorFdroidApk)
    }
}

dependencies {
    // Desugaring (required by flutter_local_notifications); window libs avoid the Android 12L+ crash.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")
}

flutter {
    source = "../.."
}

// F-Droid: empty PlayStoreDeferredComponentManager and friends so the
// play-core types they reference drop out of the dex.
abstract class StripPlayStoreDeferredManager : AsmClassVisitorFactory<StripPlayStoreDeferredManager.Parameters> {
    interface Parameters : InstrumentationParameters

    override fun isInstrumentable(classData: ClassData): Boolean = true

    override fun createClassVisitor(context: ClassContext, nextClassVisitor: ClassVisitor): ClassVisitor {
        val name = context.currentClassData.className.replace('.', '/')
        // The manager class, its lambda/inner classes, and the split Application.
        val isTarget =
            name == "io/flutter/embedding/android/FlutterPlayStoreSplitApplication" ||
            name.startsWith("io/flutter/embedding/engine/deferredcomponents/PlayStoreDeferredComponentManager")
        return if (isTarget) {
            // Empty the class and repoint superclass/interfaces at Object,
            // or the play-core types stay referenced.
            object : ClassVisitor(Opcodes.ASM9, nextClassVisitor) {
                override fun visit(
                    version: Int, access: Int, name: String?, signature: String?,
                    superName: String?, interfaces: Array<out String>?
                ) {
                    super.visit(version, access, name, null, "java/lang/Object", arrayOf())
                }
                override fun visitField(access: Int, name: String?, descriptor: String?, signature: String?, value: Any?): FieldVisitor? = null
                override fun visitMethod(access: Int, name: String?, descriptor: String?, signature: String?, exceptions: Array<out String>?): MethodVisitor? = null
                override fun visitAnnotation(descriptor: String?, visible: Boolean): AnnotationVisitor? = null
                override fun visitInnerClass(name: String?, outerName: String?, innerName: String?, access: Int) {}
                override fun visitOuterClass(owner: String?, name: String?, descriptor: String?) {}
                override fun visitNestMember(nestMember: String?) {}
                override fun visitPermittedSubclass(permittedSubclass: String?) {}
                override fun visitAttribute(attribute: Attribute?) {}
                override fun visitSource(source: String?, debug: String?) {}
            }
        } else {
            nextClassVisitor
        }
    }
}

// F-Droid per-ABI version codes (base * 10 + abiIndex, their required scheme);
// Flutter's own split scheme is disabled in gradle.properties.
val abiVersionCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
androidComponents {
    onVariants { variant ->
        variant.outputs.forEach { output ->
            val abiVersionCode = abiVersionCodes[
                output.filters.find { it.filterType == FilterConfiguration.FilterType.ABI }?.identifier
            ]
            if (abiVersionCode != null) {
                output.versionCode.set(flutter.versionCode * 10 + abiVersionCode)
            }
        }
    }
}

androidComponents {
    onVariants { variant ->
        if (variant.flavorName == "fdroid") {
            variant.instrumentation.transformClassesWith(
                StripPlayStoreDeferredManager::class.java,
                InstrumentationScope.ALL
            ) {}
        }
    }
}
