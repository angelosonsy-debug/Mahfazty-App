# Data Safety — إجابات Google Play Console

> هذا الملف يحتوي إجابات مستخلصة من الكود الفعلي (مش تخمين).
> مصدر كل إجابة موضح بجانبها.

---

## هل التطبيق يجمع بيانات مستخدم؟ → نعم

---

## البيانات المجمَّعة

### 1. رسائل SMS
- **ما يُجمَّع:** محتوى رسائل SMS من مرسلين محددين يختارهم المستخدم.
- **المصدر:** `SmsReceiver.kt` + `AiAssistedIngestion.ingestSms()`
- **هل تُشارَك؟** اختياريًا مع Anthropic (AI) عند تفعيل "الفهم الذكي"
- **هل مشفرة أثناء الإرسال؟** نعم (HTTPS)
- **هل يمكن للمستخدم حذفها؟** نعم (حذف التطبيق أو مسح البيانات)
- **لماذا تُجمَّع؟** استخراج بيانات المعاملات المالية تلقائيًا (core functionality)
- **Data Safety category:** Messages → SMS or MMS

### 2. إشعارات التطبيقات
- **ما يُجمَّع:** محتوى إشعارات تطبيقات الدفع المحددة.
- **المصدر:** `MahfaztyNotificationListener.kt`
- **هل تُشارَك؟** اختياريًا مع Anthropic عند تفعيل AI
- **Data Safety category:** Messages → In-app messages (أو Other in-app messages)

### 3. البيانات المالية
- **ما يُجمَّع:** مبالغ المعاملات، أرصدة المحافظ، أنواع المعاملات.
- **المصدر:** `LocalStore.dart` → SharedPreferences
- **هل تُشارَك؟** لا — محلية فقط
- **Data Safety category:** Financial info → Other financial info

---

## البيانات التي لا تُجمَّع

| البيانات | السبب |
|---------|------|
| الموقع الجغرافي | لا يوجد `ACCESS_FINE_LOCATION` في Manifest |
| جهات الاتصال | لا يوجد `READ_CONTACTS` |
| معرّفات الجهاز (IMEI) | لا يوجد في الكود |
| الكاميرا / الميكروفون | لا يوجد |
| تاريخ المتصفح | لا يوجد |
| بيانات التطبيقات الأخرى | الـ NotificationListener مُقيَّد بالتطبيقات التي يختارها المستخدم |

---

## مشاركة البيانات مع أطراف ثالثة

| الجهة | البيانات | الغرض | مشروط بـ |
|-------|---------|--------|---------|
| Anthropic Claude API (عبر Cloudflare Worker) | نص الرسالة + المرسل | تحليل رسالة مالية غير مؤكدة | تفعيل "الفهم الذكي" فقط |

---

## الأمان

- **البيانات مشفرة أثناء الإرسال:** نعم (HTTPS/TLS)
- **البيانات مشفرة على الجهاز:** تعتمد على SharedPreferences القياسي (مشفر بتشفير Android الافتراضي)
- **المستخدم يتحكم في بياناته:** نعم (مسح البيانات داخل التطبيق)

---

## تنبيه مهم لـ Play Console

تطبيقات SMS تتطلب إكمال **Permissions Declaration Form** في Play Console، وتوضيح:

1. **الغرض من READ_SMS/RECEIVE_SMS:** قراءة رسائل البنوك والمحافظ الإلكترونية لاستخراج بيانات المعاملات المالية تلقائيًا.
2. **هل البيانات تُشارَك؟** اختياريًا مع AI فقط لتحليل الرسائل غير المؤكدة.
3. **هل تُستخدَم للإعلانات؟** لا.
4. **هل تُشارَك مع أطراف ثالثة؟** فقط Anthropic عند تفعيل AI (وليس بيع البيانات).

---

## مراجع الكود (للتحقق)

| الادعاء | الملف |
|--------|------|
| SMS filtered by sender | `lib/financial_engine/policy/source_policy.dart` |
| Notification filtered by package | `lib/financial_engine/ai/ai_assisted_ingestion.dart:ingestNotification()` |
| Data stored locally only | `lib/financial_engine/engine/local_store.dart` |
| AI sends text+sender only | `lib/financial_engine/ai/ai_backend_client.dart:analyze()` |
| AI is optional toggle | `lib/financial_engine/ai/ai_settings_store.dart` |
| No ad use | (لا يوجد أي SDK إعلانات في pubspec.yaml) |
