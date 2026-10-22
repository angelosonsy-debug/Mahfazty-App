# Google Play Pre-Launch Checklist — محفظتي

> **الحالة العامة:** 🟡 READY AFTER MANUAL ACTIONS
>
> الكود مكتمل وتم مراجعته. المتبقي هو خطوات deployment وتوثيق يدوية على GitHub / Cloudflare / Google Play Console.

---

## الجدول الكامل

| البند | الحالة | الدليل | الخطوة اليدوية المطلوبة |
|-------|--------|--------|------------------------|
| **C4: Flutter version** | 🟡 | `build-apk.yml`: FLUTTER_VERSION='3.44.7' | تشغيل bootstrap-android.yml على GitHub |
| **C4: pubspec.yaml** | ✅ | موجود في الريبو، version محدد | — |
| **C4: pubspec.lock** | 🟡 | يتولّد من bootstrap-android.yml | تشغيل bootstrap-android.yml |
| **C4: android/ project** | 🟡 | android_overrides موجود، bootstrap ينقله | تشغيل bootstrap-android.yml |
| **C4: CI no flutter create** | ✅ | build-apk.yml: `flutter pub get` فقط | — |
| **C4: compileSdk=36** | 🟡 | في bootstrap script (apply_release_signing.py) | تشغيل bootstrap |
| **C4: targetSdk=36** | 🟡 | نفسه | نفسه |
| **C4: minSdk=23** | 🟡 | نفسه | نفسه |
| **C2: release signing** | 🔴 | apply_release_signing.py جاهز | إنشاء keystore + إضافة 4 GitHub Secrets |
| **C2: versionName=1.0.0** | ✅ | `pubspec.yaml: version: 1.0.0+1` | — |
| **C2: versionCode=1** | ✅ | نفسه | — |
| **C2: AAB signed** | 🔴 | release-build.yml جاهز | يحتاج keystore + GitHub Secrets |
| **C2: keystore backup** | 🔴 | docs/release-signing-setup.md موجود | حفظ نسخة offline بعد الإنشاء |
| **C1: Reassembly** | ✅ | 25 test في message_reassembler_test.dart | — |
| **I3: Amount extraction** | ✅ | 37 test في i3_i5_test.dart | — |
| **I5: VF Cash rules** | ✅ | نفسه | — |
| **I1: Wallet separation** | ✅ | 25 test في wallet_i1i2_test.dart | — |
| **I2: Source catalog** | ✅ | موجود في source_catalog.dart | — |
| **I4: Wallet transfers** | ✅ | 27 test في i4_i6_i8_test.dart | — |
| **I6: Candidate filter** | ✅ | نفسه | — |
| **I8: Source Test UI** | ✅ | source_test_screen.dart موجود | — |
| **C3: AI Worker** | 🔴 | src/index.ts جاهز + مُقوّى | deploy على Cloudflare + ANTHROPIC_API_KEY secret |
| **C3: No key in APK** | ✅ | `String.fromEnvironment(...)` فقط — مش embedded key | — |
| **C3: AI optional toggle** | ✅ | AiSettingsStore + SettingsScreen | — |
| **C3: Old key migration** | ✅ | runC3Migration() في main.dart | — |
| **C3: Rate limiting** | 🟡 | موجود في Worker code جزئيًا | ضبط WAF Rate Limiting في Cloudflare Dashboard |
| **C3: Anthropic billing cap** | 🔴 | — | تفعيل Usage Limit في Anthropic Dashboard |
| **flutter analyze** | ⏳ | لم يُشغَّل (لا Flutter في البيئة) | تشغيل `flutter analyze` على CI |
| **flutter test** | ⏳ | 230 test موجودة، Python logic verified | تشغيل `flutter test` على GitHub Actions |
| **Release AAB** | 🔴 | workflow جاهز | يحتاج keystore + تشغيل release-build.yml |
| **Privacy Policy URL** | 🔴 | docs/privacy-policy.md جاهز | استضافة الصفحة (GitHub Pages أو غيره) |
| **Data Safety form** | 🟡 | docs/data-safety.md جاهز | إكمال في Play Console |
| **Permissions Declaration** | 🟡 | docs/permissions-audit.md جاهز | إكمال نموذج SMS في Play Console |
| **Financial Declaration** | 🟡 | docs/google-play-financial-features.md جاهز | إكمال في Play Console |
| **Store Listing** | 🟡 | docs/store-listing.md جاهز | رفع الوصف + screenshots + icon في Play Console |
| **App icon** | 🔴 | غير موجود | تصميم أيقونة 512×512 |
| **Screenshots** | 🔴 | غير موجودة | تصوير 5+ screenshots من التطبيق |
| **Prominent Disclosure** | 🟡 | موثق في permissions-audit.md | تأكيد تطبيقه في onboarding screen |
| **Debug config in release** | ✅ | Release workflow منفصل عن Debug | — |
| **No secrets in repo** | ✅ | تم مراجعة الكود كاملًا | — |
| **Prompt injection guard** | ✅ | Worker: system message + anti-injection + text truncation | — |
| **AI response validation** | ✅ | Worker: validates direction/amount/confidence/types | — |

---

## Legend
| الرمز | المعنى |
|-------|--------|
| ✅ | مكتمل — لا يحتاج شيء |
| 🟡 | يحتاج خطوة يدوية أو تحقق CI |
| 🔴 | يمنع النشر إذا لم يُكتمَل |
| ⏳ | ينتظر تشغيل CI حقيقي |

---

## الخطوات اليدوية المرتبة حسب الأولوية

### 🔴 حرج (بدونها لا يمكن النشر)
1. **إنشاء Keystore**: `keytool -genkey -v -keystore mahfazty-release.keystore -alias mahfazty -keyalg RSA -keysize 2048 -validity 10000`
2. **حفظ نسخة backup offline** من الـ keystore فورًا (USB منفصل + مدير كلمات سر)
3. **إضافة 4 GitHub Secrets**: `ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`
4. **تشغيل bootstrap-android.yml** (GitHub Actions → Bootstrap → Run workflow)
5. **تشغيل release-build.yml** بعد نجاح bootstrap
6. **تحقق من AAB**: يجب أن تظهر "Signing verification PASSED" في الـ log
7. **Deploy Cloudflare Worker**: `cd mahfazty-ai-proxy && npm install && wrangler deploy`
8. **إضافة API Key**: `wrangler secret put ANTHROPIC_API_KEY`
9. **تصميم App icon**: 512×512px PNG
10. **استضافة Privacy Policy**: GitHub Pages من docs/privacy-policy.md
11. **تحديث URL في AiBackendClient**: غيّر defaultValue لـ Workers URL الحقيقي

### 🟡 مهم قبل النشر
12. **Cloudflare WAF Rate Limiting**: 30 req/min على `/parse`
13. **Anthropic billing cap**: حد يومي/شهري في dashboard
14. **تشغيل `flutter test` على CI**: 230 test — تأكيد 0 failures
15. **تشغيل `flutter analyze`**: تأكيد 0 errors
16. **تصوير Screenshots**: 5+ screenshots من التطبيق الحقيقي
17. **إكمال Data Safety في Play Console**: من docs/data-safety.md
18. **إكمال Permissions Declaration**: من docs/permissions-audit.md
19. **إكمال Financial Features Declaration**: من docs/google-play-financial-features.md
20. **رفع Store Listing**: اسم + وصف + screenshots + icon
21. **التأكد من Prominent Disclosure** يظهر في onboarding قبل طلب الأذونات

---

## تقدير الوقت المطلوب
| المجموعة | التقدير |
|---------|--------|
| Keystore + GitHub Secrets + Bootstrap | 30 دقيقة |
| Cloudflare Deploy + Secret + Rate Limit | 20 دقيقة |
| Privacy Policy hosting | 15 دقيقة |
| CI verification (flutter test + analyze) | 10 دقيقة (وقت انتظار CI) |
| App icon design | 1-2 ساعة (أو استخدام أداة مثل Figma/Canva) |
| Screenshots | 30 دقيقة |
| Play Console forms | 1 ساعة |
| **الإجمالي** | ~4-5 ساعات |
