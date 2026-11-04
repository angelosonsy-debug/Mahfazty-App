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
- **هل تُشارَك؟** لا — محلية فقط (إلا عند تفعيل النسخ الاحتياطي السحابي، انظر #4)
- **Data Safety category:** Financial info → Other financial info

### 4. النسخ الاحتياطي السحابي (اختياري — Google Drive)
- **ما يُجمَّع:** نفس بيانات #3 (معاملات، أرصدة، محافظ) في ملف JSON واحد.
- **المصدر:** `GoogleDriveBackupService.dart` + `BackupService.exportBackup()`
- **أين يُخزَّن؟** في مساحة `appDataFolder` الخاصة بالتطبيق داخل حساب
  Google Drive **الخاص بالمستخدم نفسه** — ليست مساحة عامة ولا يمكن لأي
  تطبيق آخر أو حتى واجهة Drive العادية رؤيتها أو الوصول إليها.
- **هل تُشارَك مع سيرفرات التطبيق؟** لا — لا يوجد سيرفر للتطبيق أصلًا؛
  الاتصال مباشر بين جهاز المستخدم و Google Drive API فقط.
- **النطاق (OAuth scope) المطلوب:** `drive.appdata` فقط — لا نطلب الوصول
  لباقي ملفات المستخدم على Drive.
- **هل الميزة إجبارية؟** لا — معطّلة افتراضيًا، تتطلب تسجيل دخول صريح
  بحساب Google من المستخدم.
- **هل يمكن للمستخدم حذفها؟** نعم — تسجيل الخروج من داخل التطبيق لا يحذف
  الملف تلقائيًا، لكن حذف حساب Google نفسه أو حذف الملف يدويًا من Drive
  (عبر أدوات إدارة بيانات التطبيقات في إعدادات حساب Google) يحذفه نهائيًا.
- **Data Safety category:** Financial info → Other financial info (نفس
  تصنيف #3، فقط موقع التخزين يتغيّر من الجهاز إلى Drive الخاص بالمستخدم)

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
| Google (Google Mobile Ads SDK) | معرّف الإعلان، بيانات استخدام قياسية لعرض الإعلانات (راجع [سياسة بيانات AdMob](https://support.google.com/admob/answer/6128543)) | عرض إعلانات بانر/بينية داخل التطبيق | دائمًا (ما عدا مستخدمي Premium — بدون إعلانات) |
| Google Drive API (appDataFolder) | نسخة من بيانات #3/#4 أعلاه (معاملات، أرصدة) | نسخ احتياطي سحابي اختياري في مساحة المستخدم الخاصة | تسجيل دخول صريح بـ Google من المستخدم |

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
3. **هل تُستخدَم للإعلانات؟** بيانات SMS/الإشعارات المالية نفسها لا — لكن
   التطبيق يعرض إعلانات AdMob عامة (غير مبنية على محتوى الرسائل) لغير
   مشتركي Premium.
4. **هل تُشارَك مع أطراف ثالثة؟** Anthropic عند تفعيل AI، وGoogle (AdMob
   + Drive عند تفعيل النسخ السحابي) — وليس بيع البيانات في أي من الحالتين.

---

## مراجع الكود (للتحقق)

| الادعاء | الملف |
|--------|------|
| SMS filtered by sender | `lib/financial_engine/policy/source_policy.dart` |
| Notification filtered by package | `lib/financial_engine/ai/ai_assisted_ingestion.dart:ingestNotification()` |
| Data stored locally only | `lib/financial_engine/engine/local_store.dart` |
| AI sends text+sender only | `lib/financial_engine/ai/ai_backend_client.dart:analyze()` |
| AI is optional toggle | `lib/financial_engine/ai/ai_settings_store.dart` |
| Cloud backup uses user's own Drive (appdata scope) | `lib/financial_engine/engine/google_drive_backup_service.dart` |
| Cloud backup is optional (off by default) | `lib/features/settings/settings_screen.dart:_CloudBackupSection` |
