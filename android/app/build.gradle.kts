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
    // Firebase's google-services plugin (FCM push): declared here so the
    // version is pinned, but APPLIED below only when a real
    // google-services.json exists. The Play build's Firebase project is
    // configured there; builds without the file (local, F-Droid, or any
    // checkout that drops it) skip the plugin cleanly — the app then falls
    // back to Unified Push / 15-minute polling at runtime.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// Apply Firebase's resource generator only when its config exists.
// google-services.json is NOT required to build: FCM simply won't
// initialize (the Dart side catches and falls through to the next
// transport). See lib/services/push/.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.enclavd.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // AGP 9.x new-DSL naming: the boolean getter is
        // isCoreLibraryDesugaringEnabled() — the old property name without
        // the 'is' prefix only existed on the legacy internal class and no
        // longer resolves (CI: "Unresolved reference").
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        // Upload key, exactly like the wrapper (main branch): created only
        // when the CI workflow sets IS_GITHUB_ACTION=true and provides the
        // signing env vars (secrets SIGNING_KEY / KEY_STORE_PASSWORD /
        // ALIAS / KEY_PASSWORD). Absent → release builds are UNSIGNED
        // (findByName returns null), like the wrapper's fdroid flow.
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

    // Product flavors mirror the CI --dart-define flavors (play/fdroid/dev).
    // The dart-define drives the APP's compile-time config; the gradle
    // flavor drives the NATIVE dependency set. The one that matters here:
    // the fdroid flavor must not ship ANY Google code (F-Droid
    // acceptance) — see the configuration exclusions below.
    flavorDimensions += "app"
    productFlavors {
        create("play") { dimension = "app" }
        create("fdroid") { dimension = "app" }
        create("dev") { dimension = "app" }
    }

    buildTypes {
        release {
            // findByName → null when the upload key isn't configured, which
            // the Android plugin accepts as "build unsigned" (the wrapper's
            // fdroid-style flow) instead of falling back to the debug key.
            signingConfig = signingConfigs.findByName("release")
        }
    }

    // The generated GeneratedPluginRegistrant (src/main/java/io/flutter/
    // plugins/) references EVERY plugin, including the firebase ones the
    // fdroid flavor excludes — that file would fail to compile there.
    // The committed firebase-free copy in src/fdroid/java compiles instead.
    // Flutter (flutter_tools injectPlugins) writes the generated file into
    // src/main BEFORE Gradle runs, and CI's fdroid job is the only one that
    // must drop it — so delete it here, at configuration time, for fdroid
    // invocations only. (AGP 9 killed every source-exclusion path: the
    // Variant API is add-only; the public DSL AndroidSourceDirectorySet has
    // no exclude(); and even the legacy gradle.api.AndroidSourceDirectorySet
    // overrides include/exclude with @Deprecated(level=HIDDEN, b/368609737)
    // so Kotlin cannot reference them — verified locally. A path-based
    // javac exclude would also match the fdroid copy, and java files do not
    // shadow across source sets.)
    if (project.gradle.startParameter.taskNames.any { it.contains("Fdroid", ignoreCase = true) }) {
        project.file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java").delete()
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// ── F-Droid: no Google code in the binary ──────────────────────────────
// The fdroid flavor must not ship ANY Firebase / play-services classes
// (F-Droid acceptance; their scanner flags GMS class presence). The
// Flutter gradle plugin wires plugin dependencies into per-variant
// configurations (${variant}Api) — exclude the firebase plugins and their
// play-services transitives from every fdroid variant here. The Dart side
// already guards FCM behind AppConfig.enableFcm (compile-time false on
// fdroid), and the src/fdroid manifest overlay + registrant handle the
// merged components. CI verifies the APK is GMS-free after the build.
configurations.configureEach {
    if (name.contains("fdroid", ignoreCase = true)) {
        exclude(group = "com.google.firebase")
        exclude(group = "com.google.android.gms")
        // play-core (com.google.android.play) sneaks into the fdroid APK via
        // AGP's dependency-metadata wiring; the F-Droid scanner flags its
        // splitinstall/splitcompat classes as Google code. Exclude the whole
        // play group so the fdroid binary stays Google-free.
        exclude(group = "com.google.android.play")
        exclude(module = "firebase_core")
        exclude(module = "firebase_messaging")
    }
}

// ── F-Droid pipe: mirror the fdroid release APK where fdroidserver looks ──
// fdroidserver runs gradle from the subdir (android/) and searches for the
// built APK under <subdir>/build/outputs/apk/<flavor>/release/ — but Flutter
// emits it under android/app/build/outputs/... Without the mirror a successful
// build ends in "Failed to find any output apks". The original stays in
// app/build/outputs for the CI/Play pipeline.
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
    // flutter_local_notifications requires core library desugaring; the
    // window libs are the documented guard against the desugaring crash on
    // Android 12L+ (plugin README, Flutter issue #110658).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")
}

flutter {
    source = "../.."
}

// ── F-Droid: strip the engine's Play Store integration ──────────────────
// The Flutter embedding ships PlayStoreDeferredComponentManager, whose
// field/method signatures reference the com.google.android.play:core API.
// play-core is never a dependency here (the fdroid flavor excludes the whole
// play group), so the APK carries only dangling TYPE references — but the
// F-Droid pipe's binary check flags those class names. Nothing in the app
// uses the class (verified: zero references in the dex), so empty it on the
// fdroid variant: the play-core types become unreferenced and D8 drops them
// from the dex entirely. Same repo on CI and on the pipe → same output →
// the byte comparison stays green.
abstract class StripPlayStoreDeferredManager : AsmClassVisitorFactory<StripPlayStoreDeferredManager.Parameters> {
    interface Parameters : InstrumentationParameters

    override fun isInstrumentable(classData: ClassData): Boolean = true

    override fun createClassVisitor(context: ClassContext, nextClassVisitor: ClassVisitor): ClassVisitor {
        val name = context.currentClassData.className.replace('.', '/')
        // The full phantom set: the manager class, its lambda/inner classes
        // (implement play-core listeners) and the Play Store split
        // Application (extends SplitCompatApplication). All dormant — nothing
        // in the app references them (verified in the dex).
        val isTarget =
            name == "io/flutter/embedding/android/FlutterPlayStoreSplitApplication" ||
            name.startsWith("io/flutter/embedding/engine/deferredcomponents/PlayStoreDeferredComponentManager")
        return if (isTarget) {
            // Drop every member AND repoint the superclass/interfaces at
            // plain java/lang/Object: a class definition keeps its
            // superclass/interface types alive even with no members, so
            // emptying alone would leave the play-core types referenced.
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

// ── F-Droid ABI splits: per-ABI version codes (their required scheme) ──
// F-Droid builds split-per-abi APKs and requires each to carry a UNIQUE
// version code derived from the base: versionCode * 10 + abiIndex
// (armeabi-v7a=1, arm64-v8a=2, x86_64=3 — their snippet). Flutter's own
// split scheme would be base * 1000 + abi (1/2/4, x86 reserved slot 3) —
// disabled via force-version-code-ignoring-abi in gradle.properties so THIS
// block is the single writer. Uses the new Variant API (AGP 9 removed
// android.applicationVariants / ApkVariantOutputImpl; the supported way is
// androidComponents.onVariants + output.versionCode Property). The F-Droid
// snippet's `variant.versionCode` (legacy base) equals flutter.versionCode
// here — same value, sourced from the extension instead of a dead API.
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
