plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            // findByName → null when the upload key isn't configured, which
            // the Android plugin accepts as "build unsigned" (the wrapper's
            // fdroid-style flow) instead of falling back to the debug key.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
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
