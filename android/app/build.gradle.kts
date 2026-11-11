import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    namespace = "com.mahfazty.mahfazty"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mahfazty.mahfazty"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
// mahfazty: flutter_local_notifications requires core library desugaring
// ─────────────────────────────────────────────────────────────────────
// من v13+ (نحن على ^18.0.1)، flutter_local_notifications بيستخدم APIs
// من java.time عبر desugaring، فـ AGP بيرفض الـ build لو مش مفعّل في
// :app. ده مش خطأ في المكتبة ولا في إعداداتنا — متطلّب رسمي موثّق في
// توثيق flutter_local_notifications نفسها.
//
// استدعاء android { } ودdependencies { } تاني في نفس الملف آمن تمامًا
// في Gradle Kotlin DSL — كل استدعاء بـ"يضيف" إعدادات على الـ extension
// الموجود، مش بيستبدله. فده أسلوب إضافة (append) بحت، من غير ما نلمس
// أو نحلّل محتوى الملف الموجود فعلاً (اللي شكله بيختلف حسب نسخة قالب
// Flutter).
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

