plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.qnaiv.mobiledaw"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.qnaiv.mobiledaw"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // 実機（arm64）とエミュレーター（x86_64）だけビルドする
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_ARM_NEON=ON")
                cppFlags += listOf("-O2")
            }
        }
    }

    // core/（C++のエンジン）を libmdaw.so としてビルドしてAPKに入れる
    externalNativeBuild {
        cmake {
            path = file("../../../core/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            // 自分用なのでデバッグ鍵で署名する
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
