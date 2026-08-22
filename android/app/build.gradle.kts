import java.io.FileInputStream
import java.util.Properties

// Upload signing key. Sources, in order: CI env vars (GitHub Actions
// secrets, set by build.yml) → android/key.properties (local builds).
// When neither provides a key the release build falls back to the debug
// keystore, so unconfigured builds still produce installable APKs — but
// only the real upload key produces an AAB/APK Play Store accepts.
val uploadKey = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}
fun uploadSecret(name: String): String? =
    System.getenv(name) ?: uploadKey.getProperty(name)

val hasUploadKey =
    listOf(
        "ANDROID_KEYSTORE_PATH",
        "ANDROID_KEYSTORE_PASSWORD",
        "ANDROID_KEY_ALIAS",
        "ANDROID_KEY_PASSWORD",
    ).all { !uploadSecret(it).isNullOrBlank() }

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
        if (hasUploadKey) {
            create("release") {
                storeFile = file(uploadSecret("ANDROID_KEYSTORE_PATH")!!)
                storePassword = uploadSecret("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = uploadSecret("ANDROID_KEY_ALIAS")
                keyPassword = uploadSecret("ANDROID_KEY_PASSWORD")
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
            // Upload key when configured (CI secrets / key.properties);
            // debug keystore otherwise (unconfigured local/PR builds).
            signingConfig =
                if (hasUploadKey) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
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
