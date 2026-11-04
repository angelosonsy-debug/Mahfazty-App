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

