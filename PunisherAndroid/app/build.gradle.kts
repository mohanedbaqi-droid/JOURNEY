plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.abuseif.punisherdrive"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.abuseif.punisherdrive"
        minSdk = 23
        targetSdk = 35
        versionCode = 5
        versionName = "0.3.1"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
        debug {
            applicationIdSuffix = ""
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
}
