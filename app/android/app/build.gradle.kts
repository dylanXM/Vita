plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val vitaApplicationId = System.getenv("VITA_ANDROID_APPLICATION_ID") ?: "com.example.vita"
val vitaReleaseKeystore = System.getenv("VITA_ANDROID_KEYSTORE")

android {
    namespace = "com.example.vita"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = vitaApplicationId
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

    signingConfigs {
        create("release") {
            if (!vitaReleaseKeystore.isNullOrBlank()) {
                storeFile = file(vitaReleaseKeystore)
            }
            storePassword = System.getenv("VITA_ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("VITA_ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("VITA_ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.name.contains("Release", ignoreCase = true) }
    val signingValues = listOf(
        vitaReleaseKeystore,
        System.getenv("VITA_ANDROID_KEYSTORE_PASSWORD"),
        System.getenv("VITA_ANDROID_KEY_ALIAS"),
        System.getenv("VITA_ANDROID_KEY_PASSWORD"),
    )
    if (buildsRelease && signingValues.any { it.isNullOrBlank() }) {
        throw GradleException(
            "Release signing requires VITA_ANDROID_KEYSTORE, " +
                "VITA_ANDROID_KEYSTORE_PASSWORD, VITA_ANDROID_KEY_ALIAS and VITA_ANDROID_KEY_PASSWORD",
        )
    }
    if (buildsRelease && vitaApplicationId == "com.example.vita") {
        throw GradleException("Release builds require VITA_ANDROID_APPLICATION_ID")
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
