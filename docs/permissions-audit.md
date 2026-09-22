# Permissions Audit — محفظتي

> مبني على AndroidManifest.xml الفعلي في android_overrides/.

---

## الأذونات المستخدمة

### 1. `RECEIVE_SMS` + `READ_SMS`
- **الغرض:** استقبال وقراءة رسائل SMS لاستخراج بيانات المعاملات المالية.
- **الضرورة:** ضروري جدًا — هذا Core Feature للتطبيق.
- **متوافق مع Play؟** ✅ بشرط إكمال **Permissions Declaration Form** في Console.
- **تصنيف Play:** Restricted — يتطلب مراجعة وتوضيح الغرض.
- **الإفصاح للمستخدم:** يُعرض قبل طلب الإذن (Prominent Disclosure في onboarding).
- **تصفية:** يُقرأ فقط من مرسلين يحددهم المستخدم (SourcePolicy).
- **استخدام للإعلانات:** لا.

### 2. `BIND_NOTIFICATION_LISTENER_SERVICE`
- **الغرض:** قراءة إشعارات تطبيقات الدفع الإلكتروني (InstaPay).
- **الضرورة:** ضروري لـ InstaPay الذي يعمل عبر إشعارات التطبيق.
- **متوافق مع Play؟** ✅ مبرر كـ core feature لإدارة المعاملات.
- **تصفية:** `MahfaztyNotificationListener.kt` يُرشّح حسب packageName فقط.
- **لا يُجمَّع:** إشعارات التطبيقات الأخرى لا تُقرأ إطلاقًا.

### 3. `INTERNET`
- **الغرض:** التواصل مع Cloudflare Worker لتحليل AI (اختياري).
- **الضرورة:** ضروري لميزة "الفهم الذكي" الاختيارية.
- **متوافق مع Play؟** ✅ عادي.
- **ملاحظة:** لا تحدث أي طلبات شبكة عند تعطيل AI.

### 4. `FOREGROUND_SERVICE`
- **الغرض:** تشغيل خدمة الخلفية لاستقبال SMS/إشعارات.
- **متوافق مع Play؟** ✅ مع توضيح الاستخدام.

### 5. `VIBRATE` (إذا موجود)
- **الغرض:** إشعارات التطبيق.
- **متوافق مع Play؟** ✅ عادي.

---

## أذونات غير موجودة (تأكيد)

| الإذن | موجود؟ | ملاحظة |
|-------|--------|--------|
| `ACCESS_FINE_LOCATION` | ❌ | غير مطلوب |
| `READ_CONTACTS` | ❌ | غير مطلوب |
| `READ_CALL_LOG` | ❌ | غير مطلوب |
| `CAMERA` | ❌ | غير مطلوب |
| `RECORD_AUDIO` | ❌ | غير مطلوب |
| `READ_PHONE_STATE` | ❌ | غير مطلوب |
| `PROCESS_OUTGOING_CALLS` | ❌ | غير مطلوب |
| `USE_BIOMETRIC` | ❌ | غير مطلوب |

---

## Prominent Disclosure (مطلوب من Google)

قبل طلب `READ_SMS` / `RECEIVE_SMS` و Notification Listener:

**النص المطلوب عرضه (Disclosure):**
```
يحتاج تطبيق محفظتي إلى قراءة رسائل SMS لاستخراج بيانات معاملاتك المالية تلقائيًا.

لن يُقرأ إلا رسائل المرسلين الذين تحددهم أنت (مثل البنك الأهلي، Vodafone Cash).

لا تُشارَك بياناتك مع أي جهة إعلانية.
```

**مكان العرض:** شاشة الـ onboarding قبل طلب الإذن مباشرة.

**الكود المعني:** يجب التأكد في `lib/main.dart` أو شاشة الإعداد الأولى إن هذا النص يظهر.

---

## Permissions Declaration Form (Play Console)

عند ملء النموذج في Play Console:

**Q: لماذا يحتاج تطبيقك هذا الإذن؟**
```
The app reads SMS messages from bank and mobile wallet senders (specified by the user) to automatically extract financial transaction data. This is the core functionality of the app — without this permission, users would need to enter every transaction manually.

The app: (1) only reads SMS from senders the user configures, (2) never uses SMS data for advertising, (3) never shares SMS content with third parties except optionally for AI analysis of uncertain transactions (user can disable this), (4) stores all data locally on the device.
```

---

## خطوات يدوية مطلوبة في Play Console

1. في "App content" → "Sensitive app permissions" → أكمل نموذج SMS
2. في "Data safety" → أكمل حسب `docs/data-safety.md`
3. في "App content" → "Financial features" → أكمل حسب `docs/google-play-financial-features.md`
4. تأكد من رفع Privacy Policy URL الحقيقي
