plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "com.enclavd.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.enclavd.app"
        minSdk = 24
        targetSdk = 35
        versionCode = 3
        versionName = "1.2.3"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        release {
            // Reads the environment variables generated during your GitHub Actions run
            storeFile = System.getenv("SIGNING_KEY_FILE") ? file(System.getenv("SIGNING_KEY_FILE")) : null
            storePassword = System.getenv("KEY_STORE_PASSWORD")
            keyAlias = System.getenv("ALIAS")
            keyPassword = System.getenv("KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.release // Injects the signing keys into the release build
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.constraintlayout)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}