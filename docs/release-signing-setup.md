# محفظتي — Release Signing Setup

## 1) نظام الترقيم (Versioning)

المصدر الوحيد للإصدار هو سطر واحد في `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

`1.0.0` = `versionName` (المعروض للمستخدم على Play)
`1` (بعد الـ `+`) = `versionCode` (رقم داخلي، **لازم يزيد** مع كل رفعة جديدة على Play، حتى لو `versionName` نفسه ما اتغيرش)

`android/app/build.gradle` بيقرأ الاتنين تلقائيًا من `pubspec.yaml` (عبر `flutter.versionName` و`flutter.versionCode`) — **مفيش أي مكان تاني في المشروع فيه رقم إصدار hardcoded.**

### قواعد الترقيم المقترحة (إرشادية، مش إلزامية بالحرف)

| مثال | نوع التغيير |
|---|---|
| `1.0.0+1` | أول إصدار على Play |
| `1.0.1+2` | إصلاح بسيط (bug fix)، مفيش ميزات جديدة |
| `1.1.0+3` | ميزة جديدة، النظام لسه متوافق مع القديم |
| `2.0.0+4` | تغيير جوهري (مثلاً migration بيانات كبيرة) |

**القاعدة الوحيدة الملزمة فعليًا:** رقم `versionCode` (اللي بعد `+`) لازم يكون أكبر من أي رقم اترفع على Play قبل كده — Play بيرفض أي رفعة برقم مساوي أو أقل.

---

## 2) GitHub Secrets المطلوبة

قبل أي تشغيل لـ **"Release Build (signed AAB)"**، لازم تضيف 4 secrets في:
`Settings → Secrets and variables → Actions → New repository secret`

| اسم الـ Secret | القيمة |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | ملف الـ keystore بتاعك (`.keystore` أو `.jks`) بعد تحويله لـ base64 (شرح تحت) |
| `KEYSTORE_PASSWORD` | باسورد الـ keystore نفسه |
| `KEY_ALIAS` | الـ alias بتاع المفتاح جوه الـ keystore |
| `KEY_PASSWORD` | باسورد المفتاح (ممكن يكون نفس `KEYSTORE_PASSWORD` حسب إزاي أنشأته) |

الـ workflow بيقرأهم من `secrets.*` مباشرة — **القيم الحقيقية مش موجودة في أي ملف بالريبو، ومبتظهرش في أي log** (فك التشفير بيحصل في نفس الخطوة وبيتمسح آخر الـ run).

---

## 3) إزاي تنشئ الـ keystore الحقيقي (خطوة يدوية منك — مرة واحدة بس)

لو معندكش keystore بالفعل، على أي جهاز عندك فيه Java (`keytool` بييجي مع أي JDK):

```bash
keytool -genkey -v -keystore mahfazty-release.keystore \
  -alias mahfazty -keyalg RSA -keysize 2048 -validity 10000
```

هيطلب منك باسورد للـ keystore واسم/تفاصيل (اسمك، بلدك، إلخ — مش مهمة فعليًا، بس لازم تدخل حاجة).

بعد ما يتولد الملف، حوّله لـ base64 عشان تحطه في `ANDROID_KEYSTORE_BASE64`:

```bash
base64 -w0 mahfazty-release.keystore > mahfazty-release.keystore.b64
# انسخ محتوى الملف ده وحطه كقيمة الـ secret
```

(على Mac: `base64 -i mahfazty-release.keystore | pbcopy` بينسخه مباشرة للـ clipboard).

---

## 4) ⚠️ حماية الـ keystore من الضياع — أهم خطوة في المرحلة دي كلها

**لو ضاع ملف الـ keystore ده، مش هتقدر ترفع أي تحديث تاني لنفس التطبيق على Google Play أبدًا** — هتضطر تنشر التطبيق كتطبيق جديد بالكامل (identity/reviews/installs كلها بتضيع، Play مش بيسمح بتغيير مفتاح التوقيع لتطبيق منشور من غيره).

**لازم تعمل الآتي فورًا بعد إنشاء الـ keystore، قبل ما تحطه في GitHub Secrets حتى:**

1. **الملف اللي تحتفظ بيه:** `mahfazty-release.keystore` نفسه (مش الـ base64، الملف الأصلي).
2. **المعلومات اللي لازم تسجلها في مكان آمن منفصل** (مدير باسورد، ورقة فعلية في مكان آمن، إلخ):
   - باسورد الـ keystore (`KEYSTORE_PASSWORD`)
   - الـ alias (`KEY_ALIAS`)
   - باسورد المفتاح (`KEY_PASSWORD`)
3. **مكان النسخة الاحتياطية Offline:** أي مكان **مش** GitHub، **مش** أي خدمة سحابية عامة بدون تشفير. أفضل خيارات:
   - USB منفصل تحتفظ بيه فعليًا (مش متوصل بالنت باستمرار)
   - مدير باسورد بيدعم إرفاق ملفات (1Password/Bitwarden وغيرهم) — بيشفّر الملف تلقائيًا
   - لو حبيت سحابة، اعمل ده في مجلد مشفّر (zip بباسورد قوي مثلاً) مش ملف عادي
4. **ما لا يجب رفعه لـ GitHub أبدًا:** الملف نفسه (`.keystore`/`.jks`)، ولا الباسوردات كنص صريح في أي ملف — الـ `.gitignore` المضاف في المرحلة دي بيمنع رفع `android/key.properties` و`*.keystore`/`*.jks` بالغلط، لكن ده حماية إضافية مش بديل عن انتباهك.

**لن أنتقل لأي خطوة نشر فعلي على Google Play قبل ما تأكدلي إن النسخة الاحتياطية دي محفوظة فعليًا.**

---

## 5) الفرق بين الـ workflows التلاتة دلوقتي

| Workflow | يتشغل | بيلمس secrets حساسة؟ | الناتج |
|---|---|---|---|
| `build-apk.yml` | تلقائي مع كل push على main | ❌ لا | APK **debug** (للاختبار السريع بس) |
| `bootstrap-android.yml` | يدوي، مرة واحدة (أو نادرًا) | ❌ لا | مشروع Android حقيقي + إعدادات signing (بدون مفاتيح حقيقية) |
| `release-build.yml` | يدوي، أو تلقائي مع git tag بشكل `v*` | ✅ نعم (الـ 4 secrets) | **AAB موقّع Release حقيقي** — الناتج النهائي المُعد للنشر |

القرار ده مقصود: الـ push العادي على `main` (اللي بيحصل كتير أثناء التطوير) **ما بيلمسش** الـ keystore أو الأسرار خالص — الـ release build مفعّل يدويًا بس أو لما تعمل tag رسمي، فأقل احتمال لاستخدام غير مقصود للتوقيع.
