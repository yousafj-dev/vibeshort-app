plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // NOTE: no google-services plugin — VibeShort configures Firebase
    // with explicit FirebaseOptions in Dart (no google-services.json).
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vibeshort.app"
    compileSdk = flutter.compileSdkVersion
    // NDK not required: pure-Dart app with no native code.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("vibeshort") {
            storeFile = file("vibeshort-test.keystore")
            storePassword = "vibeshort123"
            keyAlias = "vibeshort"
            keyPassword = "vibeshort123"
        }
    }

    defaultConfig {
        applicationId = "com.vibeshort.app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // No abiFilters: ship native libs for ALL ABIs (arm64-v8a,
        // armeabi-v7a, x86_64) in one universal APK. Restricting to
        // arm64-v8a only made the app uninstallable on 32-bit phones
        // ("App isn't compatible with your phone").
    }

    buildTypes {
        release {
            // Signed with the persistent test keystore so updates install
            // cleanly over previous builds (same signature every time).
            // (Final Play Store key will replace this before launch.)
            signingConfig = signingConfigs.getByName("vibeshort")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
