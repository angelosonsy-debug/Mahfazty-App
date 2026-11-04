# محفظتي — AI Backend

## Architecture

```
Flutter App
    ↓  POST /parse  (HTTPS)
Cloudflare Worker (mahfazty-ai-proxy)
    ↓  API call
Anthropic API  (claude-haiku-4-5-20251001)
```

**المبدأ الأساسي:**  
Rule Engine يعمل أولًا دايمًا. الـ AI يُستدعى فقط لو الـ Rule Engine أنتج ثقة < 85. المستخدم لا يرى API key ولا يتفاعل معه.

---

## Endpoint Contract

### Request

```
POST /parse
Content-Type: application/json
```

```json
{
  "source": "AhlyBank",
  "text": "تم تنفيذ تحويل لحظي بمبلغ 720.00 جم ...",
  "context": {
    "sourceType": "sms"
  }
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `source` | string | ✅ | sender name أو package name |
| `text`   | string | ✅ | النص المُجمَّع (بعد Reassembly) — max 5KB |
| `context.sourceType` | `"sms"` \| `"notification"` | ✅ | |

### Response (200 OK)

```json
{
  "isFinancial": true,
  "direction": "DEBIT",
  "amount": 720.0,
  "confidence": 0.95,
  "explanation": "تم التعرف على عملية خصم من عبارة تم تنفيذ تحويل"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `isFinancial` | boolean | false = ليست معاملة مالية |
| `direction` | `"DEBIT"` \| `"CREDIT"` \| `"UNKNOWN"` | |
| `amount` | number \| null | موجب دائمًا إذا موجود |
| `confidence` | number [0..1] | < 0.6 = يروح للـ Review |
| `explanation` | string \| null | شرح مختصر بالعربي |

### Error Responses

```json
{ "error": "Request too large", "code": "REQUEST_TOO_LARGE" }
```

| Status | Code | Meaning |
|--------|------|---------|
| 400 | `INVALID_JSON` / `MISSING_TEXT` | طلب غير صالح |
| 404 | `NOT_FOUND` | مسار غير موجود |
| 405 | `METHOD_NOT_ALLOWED` | مش POST |
| 413 | `REQUEST_TOO_LARGE` | النص أكبر من 5KB |
| 503 | `AI_UNAVAILABLE` / `NOT_CONFIGURED` | الخدمة مش متاحة |

---

## Deployment (خطوات يدوية مطلوبة منك)

### 1. Cloudflare Account
- سجّل على [cloudflare.com](https://cloudflare.com) لو مش عندك حساب (مجاني)
- روح Workers & Pages

### 2. Install Wrangler CLI
```bash
npm install -g wrangler
wrangler login
```

### 3. Deploy the Worker
```bash
cd mahfazty-ai-proxy
npm install
wrangler deploy
```

سيعطيك URL شكله:
```
https://mahfazty-ai-proxy.<your-subdomain>.workers.dev
```

### 4. Set the Anthropic API Key as a Secret
```bash
wrangler secret put ANTHROPIC_API_KEY
```
(ستُطلب منك القيمة تفاعليًا — لا تكتبها في أي ملف)

### 5. Configure Rate Limiting (Cloudflare Dashboard)
الـ Worker نفسه لا يحتوي كود rate limiting — Cloudflare بيديك هذه الميزة في الـ dashboard:

1. روح Cloudflare Dashboard → Your Zone (أو Workers Routes)
2. Security → WAF → Rate Limiting Rules
3. أنشئ Rule:
   - Match: `http.request.uri.path eq "/parse"`
   - Rate: 30 requests per 1 minute per IP
   - Action: Block (403)

على الخطة المجانية: Rate Limiting Rules متاحة على مستوى الـ account.

### 6. Update Flutter App Endpoint URL
في `lib/financial_engine/ai/ai_backend_client.dart`، الـ URL بيُقرأ من compile-time environment variable:
```dart
const _endpointUrl = String.fromEnvironment(
  'MAHFAZTY_AI_PROXY_URL',
  defaultValue: 'https://mahfazty-ai-proxy.your-subdomain.workers.dev/parse',
);
```

غيّر الـ `defaultValue` لـ URL الحقيقي، أو مرّره وقت البناء:
```bash
flutter build appbundle --release \
  --dart-define=MAHFAZTY_AI_PROXY_URL=https://mahfazty-ai-proxy.YOUR.workers.dev/parse
```

---

## Secrets

| Secret | مكان التخزين | ملاحظة |
|--------|------------|--------|
| `ANTHROPIC_API_KEY` | Cloudflare Worker Secret (via `wrangler secret put`) | لا يظهر في أي كود أو ملف config |

### ما لا يجب فعله:
- ❌ وضع API key في `wrangler.toml`
- ❌ وضع API key في `.env` المرفوع لـ GitHub
- ❌ تضمين API key في Flutter code أو APK
- ❌ طباعة API key في logs

---

## Rate Limits

| Limit | القيمة | مكان الضبط |
|-------|--------|-----------|
| Requests/IP/minute | 30 | Cloudflare WAF Rate Limiting |
| Request body size | 5KB | Worker code (hardcoded) |
| Anthropic timeout | 8 ثواني | Worker code (hardcoded) |
| Flutter client timeout | 10 ثواني | `AiBackendClient` (hardcoded) |
| Cloudflare Free tier | 100K requests/day | تلقائي |

**ملاحظة:** الـ 100K request/day تشمل كل طلبات الـ Worker — مش كل طلب SMS يصل للـ AI، بل فقط الرسائل ذات الثقة المنخفضة من Rule Engine.

---

## Cost Protection (تكلفة Anthropic API)

الـ Worker يستخدم `claude-haiku-4-5-20251001` — أرخص وأسرع نموذج:
- تكلفة تقريبية: ~$0.0008 لكل 1000 tokens
- رسالة SMS عادية: ~150-300 tokens (input + output)
- تكلفة لكل SMS يصل للـ AI: < $0.001 (أقل من مليم)

الحماية من الإسراف:
1. Rule Engine threshold 85: الغالبية العظمى من الرسائل المعروفة لا تصل للـ AI
2. Rate limiting: 30 req/min per IP يمنع abuse
3. Request size 5KB: يمنع إرسال نص ضخم
4. لو احتجت ceiling يومي: Anthropic Usage Limits في dashboard بتاعك

---

## Failure Behavior

| الحالة | السلوك |
|-------|--------|
| Worker مش متاح | Flutter timeout → null → Rule Engine result أو Review |
| Anthropic API 429 | Worker يرجع 503 → Flutter null → Review |
| Anthropic API 500 | نفس الفوق |
| Worker timeout (8s) | Flutter timeout (10s) → null → Review |
| Malformed AI response | Worker validation → null → Flutter null → Review |
| AI disabled (المستخدم) | `_tryAiBackend` مرجع null فورًا — لا HTTP request |
| Offline (no internet) | `SocketException` → null → Review |

**الضمان:** التطبيق يعمل 100% بدون AI. كل حالات الفشل → Review/Unknown، مش crash.

---

## Local Testing

```bash
cd mahfazty-ai-proxy
npm install

# تشغيل محلي (بدون API key حقيقي — للاختبار البنيوي فقط)
wrangler dev

# Test the endpoint locally:
curl -X POST http://localhost:8787/parse \
  -H "Content-Type: application/json" \
  -d '{"source":"AhlyBank","text":"تم تنفيذ تحويل بمبلغ 720 جم","context":{"sourceType":"sms"}}'
```

للاختبار الحقيقي مع Anthropic API:
```bash
wrangler dev --env production
```

---

## Changing AI Provider

مستقبلًا لو أردت تغيير من Anthropic لـ OpenAI أو غيره:
1. عدّل `callAnthropic()` في `src/index.ts` — مكان واحد فقط
2. عدّل `ANTHROPIC_API_KEY` → `OPENAI_API_KEY` في Worker Secrets
3. عدّل اسم الـ model في `ANTHROPIC_MODEL` constant
4. Flutter code لا يتغير إطلاقًا — هو فقط يتكلم مع `POST /parse`

---

## Privacy Notes

- لا تُخزَّن الرسائل في Worker logs
- `console.error()` يسجّل الـ status code فقط، مش محتوى الرسالة
- الـ Anthropic API لا تحتفظ بالبيانات للتدريب (وفق سياستهم الحالية — تحقق منها قبل النشر)
- وضّح للمستخدم في privacy policy إن "بعض الرسائل غير المؤكدة تُحلَّل عبر خدمة AI خارجية"

---

## Known Status

**C3 Status: `Prepared — awaiting deployment`**

- Worker code: ✅ جاهز
- Flutter client: ✅ جاهز  
- Deployment on Cloudflare: ❌ لم يتم بعد (يحتاج خطواتك اليدوية فوق)
- Real API key configured: ❌ لم يتم
- `flutter test` on GitHub Actions: ⏳ pending CI run
