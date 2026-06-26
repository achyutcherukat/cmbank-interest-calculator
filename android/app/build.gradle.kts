plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cmbank.app"
    // Pinned to 36: some plugins (flutter_plugin_android_lifecycle) require it.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    // Required for the per-flavor resValue("string", "app_name", ...) entries.
    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (and other plugins) on
        // older Android API levels.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Base/default applicationId. Per-flavor overrides are set in productFlavors below.
        applicationId = "com.cmbank.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_local_notifications + secure storage need minSdk >= 23.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // Two flavors from one shared codebase. The ONLY differences are
    // applicationId, app display name (app_name string resource), and the
    // launcher icon (provided per-flavor under src/<flavor>/res/). All Dart
    // business logic, DB schema and UI are 100% shared.
    flavorDimensions += "app"
    productFlavors {
        create("cmb") {
            dimension = "app"
            applicationId = "com.cmbank.app"
            resValue("string", "app_name", "CMB")
        }
        create("gmc") {
            dimension = "app"
            applicationId = "com.cmbank.gmc"
            resValue("string", "app_name", "GMC")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
