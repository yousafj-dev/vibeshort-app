pluginManagement {
    val flutterSdkPath =
        run {
            // 1) local.properties (local dev machines)
            val fromProps = try {
                val properties = java.util.Properties()
                file("local.properties").inputStream().use { properties.load(it) }
                properties.getProperty("flutter.sdk")
            } catch (e: Exception) { null }
            // 2) FLUTTER_ROOT env (GitHub Actions via subosito/flutter-action)
            // 3) Common CI install locations as last resort
            val flutterSdkPath = fromProps
                ?: System.getenv("FLUTTER_ROOT")?.takeIf { it.isNotEmpty() }
                ?: listOf("/opt/flutter", "/usr/local/flutter", System.getenv("HOME") + "/flutter")
                    .firstOrNull { file("$it/packages/flutter_tools/gradle").exists() }
            require(!flutterSdkPath.isNullOrEmpty()) {
                "flutter.sdk not set in local.properties and FLUTTER_ROOT env not set"
            }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
