import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key. `android/key.properties` exists locally and is written by CI from
// secrets; both it and the keystore are gitignored. Every release must be signed with the same
// key, or Android refuses to install it over the previous version.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keyProperties.getProperty("storeFile") != null

android {
    // Code namespace (R class, MainActivity package). Separate from the app ID below.
    namespace = "com.cypher.cypher"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The permanent app ID: changing it makes Android treat the app as a different one,
        // and existing installs (and their vaults) are not upgraded.
        applicationId = "com.ruizchristian.cypherauth"
        minSdk = 30 // Android 11: needed for auth-bound Keystore keys (docs/system-plan.md D9)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (!hasReleaseKey) {
                logger.warn(
                    "android/key.properties not found: this release APK is debug-signed and " +
                        "cannot update a properly signed install. See docs/release.md.",
                )
            }
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
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
