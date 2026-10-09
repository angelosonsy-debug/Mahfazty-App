import '../../core/utils/text_normalizer.dart';

/// نتيجة الفلتر — هل الرسالة مرشحة لأن تكون معاملة مالية؟
enum CandidateStatus {
  /// مؤكدة مالية — تعبر للـ parser
  financial,

  /// مرفوضة — رسالة غير مالية (OTP / تنبيه أمني / إعلانية / معلوماتية)
  nonFinancial,

  /// محتملة لكن لا دليل كافٍ — تروح للـ Review مباشرة بدون parser
  uncertain,
}

class CandidateResult {
  final CandidateStatus status;
  final String reason; // سبب القرار (للـ Source Test UI / Logging)

  const CandidateResult(this.status, this.reason);
  bool get isFinancialCandidate => status == CandidateStatus.financial;
}

/// I6 — Gate واضح يأتي بعد Reassembly وقبل أي Parser.
///
/// الترتيب في Pipeline:
///   Fragments → Reassemble → [هذا الـ Filter] → PromotionalFilter → Parser
///
/// وظيفة الـ filter:
///   "هل هذه الرسالة مرشحة أصلًا لأن تكون حركة مالية؟"
///   لا يقرر المبلغ النهائي ولا النوع — ده شغل الـ parser.
class TransactionCandidateFilter {
  // -----------------------------------------------------------------------
  // أنماط OTP / التحقق (تُستبعد أولًا لأنها شائعة جدًا وغير مالية)
  // -----------------------------------------------------------------------
  static final _otpPatterns = RegExp(
    r'رمز التحقق|رمز المرور|كود التفعيل|كود التحقق|رمز تفعيل'
    r'|otp\b|verification code|one.time.password'
    r'|رمز لمرة واحدة|كلمة السر لمرة واحدة',
    caseSensitive: false,
  );

  // -----------------------------------------------------------------------
  // أنماط تنبيهات الأمان (لا تحتوي حركة مالية)
  // -----------------------------------------------------------------------
  static final _securityPatterns = RegExp(
    r'تسجيل دخول جديد|تم تسجيل الدخول من|محاولة دخول'
    r'|تم تغيير كلمة (المرور|السر)|password (changed|reset|updated)'
    r'|suspicious (login|activity)|unusual login'
    r'|تنبيه أمني|security alert',
    caseSensitive: false,
  );

  // -----------------------------------------------------------------------
  // أنماط معلوماتية صرفة (تحديث بيانات، إشعارات تشغيلية)
  // -----------------------------------------------------------------------
  static final _informationalPatterns = RegExp(
    r'تم تحديث بيانات[كك]|تم تسجيل طلب[كك]?|تم استلام طلب[كك]?'
    r'|موعد[كك]? (?:القادم|المحدد)|تذكير بموعد'
    r'|تم تفعيل (الخدمة|الاشتراك) بنجاح(?!\s*(?:مبلغ|بمبلغ|\d))'
    r'|your request has been received'
    r'|تم تسجيل بيانات[كك]?',
    caseSensitive: false,
  );

  // -----------------------------------------------------------------------
  // Financial action keywords (شرط وجوده قبل اعتبار الرسالة مالية)
  // -----------------------------------------------------------------------
  static final _financialActionPatterns = RegExp(
    r'تم (?:تنفيذ|تحويل|دفع|خصم|سحب|استلام|شحن|إيداع|إضافة)'
    r'|تمت عملية (?:تحويل|خصم|سحب|إيداع|شراء)'
    r'|credit(?:ed)?|debit(?:ed)?|deposit(?:ed)?'
    r'|payment|transfer|withdrawal|purchase'
    r'|نجاح عملية|عملية ناجحة|اكتملت العملية',
    caseSensitive: false,
  );

  // -----------------------------------------------------------------------
  // Amount context markers — دليل وجود مبلغ مالي في السياق
  // -----------------------------------------------------------------------
  static final _amountContextPattern = RegExp(
    r'(?:ب?مبلغ|جم|جني[هةا]|EGP|LE|ج\.م)'
    r'|\d+(?:,\d{3})*(?:\.\d{1,2})?\s*(?:جم|جني[هةا]|EGP|LE)'
    r'|رصيد حسابك|رصيد محفظتك|وخصم \d',
    caseSensitive: false,
  );

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// الفلتر الرئيسي.
  ///
  /// [sender]: المرسل (SMS sender أو package name) — مستخدم في الـ logging بس
  /// [text]: النص بعد Reassembly (لكن قبل إدخاله للـ parser)
  static CandidateResult check(String sender, String text) {
    final normalized = TextNormalizer.prepare(text).toLowerCase();

    // ---- Priority 1: OTP (رفض فوري) ----
    if (_otpPatterns.hasMatch(normalized)) {
      return const CandidateResult(
        CandidateStatus.nonFinancial,
        'رسالة تحقق/OTP — لا تحتوي معاملة مالية',
      );
    }

    // ---- Priority 2: Security alert (رفض فوري) ----
    if (_securityPatterns.hasMatch(normalized)) {
      return const CandidateResult(
        CandidateStatus.nonFinancial,
        'تنبيه أمني — لا تحتوي معاملة مالية',
      );
    }

    // ---- Priority 3: Informational (رفض إلا لو فيه دليل مالي) ----
    if (_informationalPatterns.hasMatch(normalized) &&
        !_hasFinancialEvidence(normalized)) {
      return const CandidateResult(
        CandidateStatus.nonFinancial,
        'رسالة معلوماتية — لا تحتوي حركة مالية واضحة',
      );
    }

    // ---- Priority 4: يجب أن يكون هناك دليل مالي ----
    if (_hasFinancialEvidence(normalized)) {
      return const CandidateResult(
        CandidateStatus.financial,
        'رسالة مالية مرشحة — فعل مالي + سياق مبلغ',
      );
    }

    // ---- Priority 5: لا دليل كافٍ ----
    // رسالة فيها أرقام بس بدون سياق مالي → uncertain → Review
    return const CandidateResult(
      CandidateStatus.uncertain,
      'لا يوجد دليل كافٍ على حركة مالية — ستظهر للمراجعة',
    );
  }

  static bool _hasFinancialEvidence(String normalized) {
    return _financialActionPatterns.hasMatch(normalized) &&
        _amountContextPattern.hasMatch(normalized);
  }
}
