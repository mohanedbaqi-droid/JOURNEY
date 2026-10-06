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
        versionCode = 1
        versionName = "0.1.0"
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
}
