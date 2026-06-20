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
        versionCode = 7
        versionName = "1.2.7"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }



// Only define signingConfigs if we are NOT on F-Droid
    if (System.getenv("FDROID") == null) {
        signingConfigs {
            create("release") {
                val keyFile = System.getenv("SIGNING_KEY_FILE")
                storeFile = if (!keyFile.isNullOrEmpty()) file(keyFile) else null
                storePassword = System.getenv("KEY_STORE_PASSWORD")
                keyAlias = System.getenv("ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            // Only attach signing config if it exists (meaning we are NOT on F-Droid)
            if (System.getenv("FDROID") == null) {
                signingConfig = signingConfigs.getByName("release")
            }
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
	implementation("androidx.core:core-splashscreen:1.0.1")
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