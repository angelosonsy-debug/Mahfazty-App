# ملاحظات توافق Gradle — محفظتي (Mahfazty)

ملف توثيقي بيشرح المشاكل اللي اتصلّحت فعليًا، وبيعمل فحص استباقي
للمكتبات التانية المستخدمة في المشروع، عشان لو حصل مشابه بمكتبة
تانية مستقبلاً (أو بعد تحديث Flutter/Gradle)، يكون في نقطة بداية
واضحة بدل ما نبدأ من الصفر.

## المشكلة اللي اتصلّحت: google_mobile_ads + Gradle 8.11+

**الأعراض:** `Could not get unknown property 'all' for configuration
container ... DefaultConfigurationContainer`

**السبب الجذري:** `ConfigurationContainer` (API داخلي في Gradle)
كان بيدعم شكلين قديمين:
- `configurations.all` — property access بترجع كل الـ configurations
  (موروثة من `NamedDomainObjectCollection.all()` بدون args)
- `configurations.all { closure }` — method بتطبّق closure على كل
  configuration حالي ومستقبلي

الاتنين اتشالوا من Gradle 8.11+ (البديل الرسمي: `configureEach {}`).
مكتبة `google_mobile_ads` (حتى نسخة 5.2.0 وقت كتابة هذا الملف)
بتستخدم الصيغة القديمة دي، فأي build بـ Gradle 8.11+ بيفشل فورًا وقت
configuration لمشروع `:google_mobile_ads`.

**الحل المُطبَّق:** `gradle_patches/configurations_all_shim.gradle`
بيرجّع الـ API المفقودة تاني (كـ Groovy metaClass shim) على
`ConfigurationContainer` نفسه — فكود المكتبة يشتغل زي ما هو، من غير
ما نلمس ملفاتها أو نخمّن شكل الكود بالظبط. بيتطبّق تلقائيًا من أول
سطر في `android/build.gradle.kts` (عبر `apply(from = "mahfazty_gma_shim.gradle")`)
في كل build.

**ليه مش عملنا text-patching لملف المكتبة نفسه؟** جرّبنا ده الأول —
فشل مرتين: مرة لأن `pub` بيكتشف إن الملف المُستخرَج اتغيّر عن الهاش
بتاعه وبيرجّعه تلقائيًا لحالته الأصلية أول ما أي أمر `flutter`/`dart`
تاني يتنفذ (حتى لو الباتش بعد آخر أمر مباشرة — `flutter build apk`
نفسه بيعمل pub resolution داخلي قبل ما يستدعي Gradle). ومرة لأن
شكل الكود الفعلي (مسافات/أسطر) كان مختلف عن افتراضنا. الـ metaClass
shim محصّن من المشكلتين: بيتنفّذ جوه نفس عملية Gradle (مش عرضة لـ
pub self-healing)، ومش محتاج يعرف شكل الكود بالظبط (بيرجّع الـ API
نفسها، مش بيدوّر على نص معيّن).

---

## فحص استباقي: باقي المكتبات المستخدمة في المشروع

| المكتبة | كود Android أصلي؟ | خطر مشابه؟ |
|---|---|---|
| `shared_preferences` | نعم (بسيط) | ضعيف جدًا — API مستقرة، مفيش استخدام معروف لـ configurations.all |
| `http` | لا (Dart بحت) | معدوم |
| `provider` | لا (Dart بحت) | معدوم |
| `flutter_local_notifications` | نعم | **تم التعامل معه** — محتاجة Core Library Desugaring (الشرح تحت) |
| `timezone` | لا (Dart بحت) | معدوم |
| `url_launcher` | نعم (بسيط) | ضعيف جدًا |
| `google_mobile_ads` | نعم | **تم التعامل معه** (الشرح فوق) |

لو ظهر خطأ مشابه (`Could not get unknown property` أو
`Could not find method` بتاع `configurations.XXX`) من مكتبة تانية
مستقبلاً، الحل: انسخ نفس نمط `configurations_all_shim.gradle` واستبدل
اسم المكتبة في الـ glob، أو — لو كان API داخلي مختلف تمامًا — ابحث
عن اسم الـ method/property بالظبط من رسالة الخطأ (بالذات الفرق بين
"property" و"method" في نص الخطأ، زي ما حصل هنا بالظبط — فرق حرفي
واحد في الرسالة كان كافي يوجّهنا للحل الصح).

## نقاط ضعف تانية محتملة (مش أخطاء فعلية — مجرد احتياطات)

1. **تثبيت نسخة `google_mobile_ads`:** كان مثبت على `5.2.0` بالظبط
   (`dependency_overrides`) زمن محاولات الـ text-patching. اتشال
   الآن لأن الـ shim مستقل عن نسخة المكتبة — لو جوجل أصدرت إصلاح
   رسمي في نسخة أحدث، `pub` هياخده تلقائيًا، والـ shim هيفضل شغّال
   جنب أي حل رسمي من غير تعارض (لأنه بس بيضيف method مش موجودة،
   مش بيستبدل حاجة شغّالة).

2. **NDK auto-install:** الـ build بيحمّل NDK 28.2.13676358 تلقائيًا
   (مش مُثبَّت مسبقًا على الـ runner) — ده بياخد وقت لكن مش خطأ. لو
   حبينا نسرّع الـ CI مستقبلاً، نقدر نضيف `ndk.dir`/cache step، لكن
   مش أولوية دلوقتي.

3. **`flutter_launcher_icons` كـ dev dependency:** بيشتغل على مستوى
   Dart بس (مولّد أيقونات)، مش بيلمس Android Gradle، فمش معرّض لنفس
   فئة المشاكل دي.

---

## المشكلة التانية اللي اتصلّحت: flutter_local_notifications + Core Library Desugaring

**الأعراض:** `Execution failed for task ':app:checkDebugAarMetadata'`
مع رسالة `Dependency ':flutter_local_notifications' requires core
library desugaring to be enabled for :app`.

**السبب:** من إصدار 13+ (إحنا على `^18.0.1`)، المكتبة بتستخدم APIs
من `java.time` بتحتاج "desugaring" (تحويل bytecode يخلي APIs حديثة
شغالة على أجهزة Android قديمة). AGP بيرفض الـ build لو المتطلب ده
مش مفعّل صراحة في موديول `:app` — ده مش باغ، متطلّب رسمي موثّق في
صفحة المكتبة نفسها.

**الحل المُطبَّق:** `gradle_patches/app_build_gradle_suffix.kts`
بيضيف (append، مش prepend زي حالة google_mobile_ads) في آخر
`android/app/build.gradle.kts`:
```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```
استدعاء `android { }` و`dependencies { }` تاني في نفس الملف آمن في
Gradle Kotlin DSL — بـ"يضيف" إعدادات على الـ extension الموجود، مش
بيستبدله. فده append بحت، من غير ما نحتاج نحلّل أو نلمس محتوى الملف
الموجود أصلاً.

**درس مستفاد:** التقييم الأول في الجدول فوق كان بيقول "ضعيف" على
المكتبة دي — وطلع فعليًا أول مشكلة ظهرت بعد ما حلينا google_mobile_ads.
يعني التقييم الاستباقي مفيد كنقطة بداية، لكن مش بديل عن تشغيل الـ
build فعليًا؛ المشاكل دي بتتكشف تراكميًا (مشكلة، نصلّحها، تظهر التانية)
مش كلها دفعة واحدة من غير تشغيل حقيقي.

---

## المشكلة التالتة اللي اتصلّحت: compileSdk mismatch بين موديولات فرعية

**الأعراض:** `Execution failed for task
':google_mobile_ads:checkDebugAarMetadata'` مع رسالة إن
`webview_flutter_android` بتطلب compileSdk 36+ بينما
`:google_mobile_ads` نفسها متبنية ضد `android-34`.

**السبب:** كل موديول Android فرعي (plugin) في مشروع Gradle متعدد
الموديولات بيعلن `compileSdk` بتاعه بنفسه، **مستقل تمامًا** عن
`compileSdk` بتاع تطبيقنا الرئيسي `:app` (اللي إحنا ثبّتناه على 36
في خطوة "Pin compileSdk..."). يعني رفع compileSdk بتاعنا احنا مش
كافي — لازم أي موديول فرعي قديم (زي google_mobile_ads نفسها، اللي
لسه متبنية بـ compileSdk 34 من وقت إصدارها) يترفع هو كمان، لأنه
بيعتمد (transitively) على موديول تاني (`webview_flutter_android`)
بيطلب نسخة أحدث.

**الحل المُطبَّق:** `gradle_patches/compile_sdk_enforcement.gradle`
— بدل ما نستهدف `google_mobile_ads` بس، عمّمنا الحل على **كل**
موديول Android فرعي في المشروع عبر:
```groovy
subprojects {
    afterEvaluate { proj ->
        // لو compileSdk بتاع الموديول ده أقل من 36، ارفعه لـ 36
    }
}
```
ده تحصين استباقي حقيقي: أي plugin تاني (دلوقتي أو بعد تحديث
مستقبلي) يقع في نفس المشكلة دي بالظبط هيتصلّح تلقائيًا من غير ما
نحتاج نكتشفه بالتجربة والخطأ تاني.

**ليه `subprojects { afterEvaluate { } }` مش `gradle.beforeProject`؟**
لازم الـ `android { }` extension بتاع الموديول يكون موجود خالص
(يعني الـ plugin اتطبّق فعلاً) قبل ما نقدر نقرأ/نغيّر compileSdkVersion
بتاعه — وده بيحصل بس بعد ما سكريبت الموديول يتنفذ. استخدام
`subprojects { }` (بدل `gradle.beforeProject`) بيضمن إن الـ
`afterEvaluate` بتاعنا يتسجّل *قبل* أي afterEvaluate داخلي تسجّله
AGP نفسها (ترتيب التسجيل بيحدد ترتيب التنفيذ في Gradle)، فالتغيير
بتاعنا يسبق أي إعداد داخلي يعتمد على القيمة القديمة.
