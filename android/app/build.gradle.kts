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
    // fdroid variant excludes — that file would fail to compile there.
    // Drop it for the fdroid variant only; src/fdroid/java provides its
    // own copy without the firebase plugins.
    androidComponents {
        onVariants(selector().withFlavor("fdroid")) { variant ->
            variant.sources.java?.all { sourceSet ->
                sourceSet.exclude("io/flutter/plugins/GeneratedPluginRegistrant.java")
            }
        }
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
        exclude(module = "firebase_core")
        exclude(module = "firebase_messaging")
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
