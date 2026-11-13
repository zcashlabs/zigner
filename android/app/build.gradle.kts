plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.zcash.airgap.airgapped_zcash_signer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.zcash.airgap.airgapped_zcash_signer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Per-operation CryptoObject authentication with device-credential fallback.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // Exercise real authenticated crypto without touching the user's app data.
            if (providers.gradleProperty("zignerVaultSelfTest").orNull == "true") {
                applicationIdSuffix = ".vault_test"
                manifestPlaceholders["appLabel"] = "Zigner vault self-test"
            }
        }
        release {
            // Production signing must be configured explicitly; never ship a debug-signed release.
            signingConfig = null
        }
    }

    defaultConfig.manifestPlaceholders["appLabel"] = "Zigner"

    sourceSets.getByName("test").resources.srcDir("src/main/res/raw")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
