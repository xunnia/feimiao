import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 固定 release 签名：读 android/key.properties（已在 .gitignore，不会进仓库）。
// 文件不存在时仅为本地开发/非发布校验回落到 debug 签名；CI push 发布
// 会强制要求固定密钥并在上传前核对证书 SHA-256。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun keystoreProperty(name: String): String? {
    keystoreProperties.getProperty(name)?.let { return it }
    return keystoreProperties.entries.firstOrNull { (key, _) ->
        key.toString()
            .replace("\uFEFF", "")
            .replace("ï»¿", "")
            .trim() == name
    }?.value?.toString()
}

val hasReleaseKeystore = keystorePropertiesFile.exists() &&
    listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
        .all { !keystoreProperty(it).isNullOrBlank() }

android {
    namespace = "com.qingji.qingji"
    // Keep the app build reproducible outside CI. Some Flutter plugins still
    // need the repository init script to raise their own subproject SDK.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.qingji.qingji.codex"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperty("keyAlias")!!
                keyPassword = keystoreProperty("keyPassword")!!
                storeFile = file(keystoreProperty("storeFile")!!)
                storePassword = keystoreProperty("storePassword")!!
            }
        }
    }

    buildTypes {
        release {
            // 有 key.properties 用固定 release 签名（覆盖升级不用卸载）；
            // 没有就用 debug 签名，保证 `flutter run --release` 与他人 clone 可编译。
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 关掉 R8 代码裁剪/混淆：ML Kit 靠反射加载中文模型，被裁会崩
            // （NPE: getClass() on null）。侧载不在乎包大小，关掉最稳，
            // 且崩溃堆栈不再被混淆成 d2.na，方便定位。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Chinese OCR must be part of the app dependency graph. Do not inject this
    // from a machine-level Gradle init script: local and CI builds must match.
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
