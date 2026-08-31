import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.tasks.compile.JavaCompile

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
    // Use Chrome's isolated Custom Tab for GPT OAuth when the device supports
    // it. This keeps an OAuth attempt out of the user's normal browser
    // cookies, so another ChatGPT/Google account can be selected reliably.
    implementation("androidx.browser:browser:1.9.0")
    // Chinese OCR must be part of the app dependency graph. Do not inject this
    // from a machine-level Gradle init script: local and CI builds must match.
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// Flutter still wires a few legacy Kotlin-Gradle plugins into the generated
// Java registrant.  AGP 9 can otherwise schedule the app Java compile before
// those plugin release jars are materialized, even though the jars are on the
// resolved classpath.  Keep the compatibility edge explicit and local to the
// app; the generated registrant itself must remain untouched.
tasks.configureEach {
    if (name == "compileReleaseJavaWithJavac") {
        dependsOn(
            ":charset_converter:compileReleaseKotlin",
            ":share_plus:compileReleaseKotlin",
            ":workmanager_android:compileReleaseKotlin",
        )
    }
}

// With the current AGP/KGP combination those legacy library modules publish
// their Kotlin classes in the runtime-to-jar artifact, while the compile-to-
// jar artifact contains only R classes.  The generated registrant is Java and
// must see the actual plugin classes during release compilation.  Keep these
// jars compile-only here; the normal Flutter plugin dependencies still own
// the runtime packaging.
val legacyPluginRuntimeJars = listOf(
    project(":charset_converter").layout.buildDirectory.file(
        "intermediates/runtime_library_classes_jar/release/bundleLibRuntimeToJarRelease/classes.jar",
    ),
    project(":share_plus").layout.buildDirectory.file(
        "intermediates/runtime_library_classes_jar/release/bundleLibRuntimeToJarRelease/classes.jar",
    ),
    project(":workmanager_android").layout.buildDirectory.file(
        "intermediates/runtime_library_classes_jar/release/bundleLibRuntimeToJarRelease/classes.jar",
    ),
)
tasks.withType<JavaCompile>().configureEach {
    if (name == "compileReleaseJavaWithJavac") {
        doFirst {
            classpath = (classpath ?: project.files()).plus(project.files(legacyPluginRuntimeJars))
        }
    }
}

flutter {
    source = "../.."
}
