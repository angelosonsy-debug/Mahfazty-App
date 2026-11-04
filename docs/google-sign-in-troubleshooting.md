# إصلاح تسجيل الدخول بـ Google — خطأ ApiException: 10

## التشخيص

الخطأ `PlatformException(sign_in_failed, ApiException: 10)` يعني غالبًا `DEVELOPER_ERROR` من Google Play services. هذا خطأ إعداد OAuth، وليس خطأ في بيانات النسخة الاحتياطية أو اتصال Google Drive نفسه. لا يمكن إصلاحه بتغيير رسالة الخطأ في Dart فقط؛ يجب أن تتطابق هوية التطبيق وبصمة شهادة التوقيع مع عميل OAuth من نوع Android.

## إعدادات هذا المشروع

وفق أمر إنشاء مشروع Android في `.github/workflows/bootstrap-android.yml`:

- Android applicationId المتوقع: `com.mahfazty.mahfazty` (تحقق من `applicationId` داخل `android/app/build.gradle` بعد تشغيل bootstrap).
- مكتبة الدخول: `google_sign_in`، وتطلب صلاحية Google Drive `drive.appdata` فقط.
- Google Sign-In على Android يعتمد على عميل OAuth من نوع Android مرتبط باسم الحزمة وSHA-1؛ إضافة `serverClientId` عشوائي أو نسخ Web Client ID إلى إعداد Android ليس حلًا.
- `google-services.json` ليس بديلًا عن تسجيل Android OAuth client، وليس مطلوبًا لمجرد استخدام `google_sign_in` مباشرة. لا تضف ملفًا من مشروع Firebase آخر.

## خطوات الإصلاح

1. افتح Google Cloud Console واختر المشروع الصحيح.
2. من APIs & Services فعّل **Google Drive API**.
3. من Google Auth Platform / Credentials أنشئ أو راجع OAuth Client ID من نوع **Android**.
4. أدخل package name الفعلي `com.mahfazty.mahfazty`، ثم بصمة SHA-1 لشهادة التوقيع التي بُنيت بها النسخة المثبتة على الهاتف.
5. سجّل بصمة Debug وبصمة Release كلتيهما إذا كنت تختبر النوعين. بصمة كل شهادة مختلفة.
6. تأكد من إعداد شاشة موافقة OAuth، وإضافة حساب الاختبار إذا كان التطبيق في وضع Testing.
7. انتظر انتشار الإعداد، ثم أعد بناء APK وثبّته وجرب تسجيل الدخول.

## استخراج SHA-1

من مشروع Android بعد إنشائه، شغّل:

```bash
cd android
./gradlew signingReport
```

على Windows:

```powershell
cd android
.\gradlew signingReport
```

استخدم SHA-1 الظاهر تحت `Variant: debug` لنسخة Debug، وتحت `Variant: release` لشهادة Release الفعلية. إذا كان APK منشأً في GitHub Actions، لا تفترض أن SHA-1 الخاص بتوقيع Debug ثابت بين عمليات البناء؛ بيئة GitHub المستضافة مؤقتة وقد تولّد debug keystore جديدًا في كل تشغيل. الأفضل اختبار Debug محليًا بمفتاح ثابت، أو استخدام شهادة Release المعتمدة في OAuth لاختبار نسخة Release. لا ترفع keystore أو كلمات مروره إلى Git.

## تحقق بعد الإصلاح

- الضغط على «تسجيل الدخول بـ Google» يفتح اختيار الحساب.
- إتمام الاختيار يعيد الحساب والبريد الإلكتروني داخل التطبيق.
- رفع نسخة احتياطية صغيرة إلى `appDataFolder` ينجح.
- إغلاق التطبيق وفتحه لا يعيد محاولة تسجيل دخول صامتة متكررة عند فشل الإعداد.
- اختبار نسخة Debug وRelease كلٌ ببصمة SHA-1 المطابقة له.

## التغيير البرمجي المضاف

تم تعديل معالجة الاستثناء في `settings_screen.dart`: لم يعد التطبيق يصنّف الخطأ اعتمادًا على وجود الرقم `10` في أي نص (وهو فحص قد يعطي نتيجة خاطئة). أصبح يميز مؤشرات `ApiException: 10` / `DEVELOPER_ERROR` ويعرض للمستخدم تعليمات مفهومة دون كشف تفاصيل تقنية خام. هذا يحسّن التشخيص وتجربة المستخدم، لكنه لا يغني عن تسجيل SHA-1 واسم الحزمة في Google Cloud Console.
