plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "com.enclavd.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.enclavd.app"
        minSdk = 24
        targetSdk = 36
        versionCode = 32
        versionName = "1.3.2"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        // Create the configuration conditionally
        if (System.getenv("IS_GITHUB_ACTION") == "true") {
            create("release") {
                storeFile = file(System.getenv("SIGNING_KEY_FILE") ?: "")
                storePassword = System.getenv("KEY_STORE_PASSWORD")
                keyAlias = System.getenv("ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            
            // USE THIS: findByName returns null if it doesn't exist,
            // which the Android plugin accepts as "build unsigned".
            // getByName crashes if it's missing.
            signingConfig = signingConfigs.findByName("release")
            
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
	
    dependenciesInfo {

            includeInApk = false
            includeInBundle = false

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
    implementation("androidx.work:work-runtime-ktx:2.9.0")
}
