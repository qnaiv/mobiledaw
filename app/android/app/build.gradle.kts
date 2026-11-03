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

    // リリース用の署名鍵。CI が GitHub のシークレットから鍵を取り出し、環境変数で場所とパスワードを渡す。
    // 毎回同じ鍵で署名するので、新しい APK をアンインストールせずに上書きでインストールできる。
    // 鍵が渡されないとき（手元のビルド）はデバッグ鍵で署名する。
    val releaseKeystore = System.getenv("MDAW_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("MDAW_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("MDAW_KEY_ALIAS")
                keyPassword = System.getenv("MDAW_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (releaseKeystore != null) "release" else "debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // アップデートの APK をインストーラーへ渡す FileProvider
    implementation("androidx.core:core:1.13.1")
}
