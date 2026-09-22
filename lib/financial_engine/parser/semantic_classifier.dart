import '../models/financial_event.dart';
import '../../core/utils/text_normalizer.dart';

/// تصنيف دلالي (Semantic) بديل عن الاعتماد على Template مضبوط بالحرف.
/// بيفهم "معنى" الرسالة من كلمات مفتاحية بدل ما يحتاج نص مطابق تمامًا.
///
/// بعد I3: استخراج المبلغ بقى context-aware:
///   الأولوية لوجود "مبلغ / بمبلغ" كـmarker صريح للمبلغ (مش أي رقم).
///   يدعم الآن: جم، جنيه، جنيها، جنيهًا، EGP، LE، ج.م
///   ويدعم الأرقام العربية (تتحول لاتينية عبر TextNormalizer.prepare).
class SemanticClassifier {
  static final List<String> _depositKeywords = [
    // عربي
    'تم إضافة', 'تمت إضافة', 'تم إيداع', 'تمت عملية إيداع', 'تم تحويل إليك',
    'استلمت', 'تم استلام', 'تم تغذية الحساب', 'تم استلام حوالة', 'تم استلام مبلغ',
    'إلى حسابك', 'إلى حسابكم', 'شحن محفظتك',
    // English
    'credit', 'credited', 'deposit', 'incoming transfer', 'received',
    'added', 'money received',
  ];

  static final List<String> _withdrawalKeywords = [
    // عربي
    'تم خصم', 'تمت عملية خصم', 'تنفيذ عملية خصم', 'تم سحب', 'تم تحويل منك',
    'تم الدفع', 'تم دفع', 'تم إرسال', 'دفعت', 'تم تنفيذ عملية شراء',
    'من حسابك', 'من حسابكم', 'من محفظتك', 'تنفيذ تحويل',
    // English
    'debit', 'debited', 'withdrawal', 'payment', 'transfer sent',
    'purchase', 'cash out',
  ];

  /// بيرجع نوع العملية لو لقى كلمة مفتاحية واضحة، أو null لو مقدرش يحدد
  static FinancialEventType? classify(String text) {
    final normalized = TextNormalizer.prepare(text).toLowerCase();

    for (final k in _depositKeywords) {
      if (normalized.contains(k.toLowerCase())) return FinancialEventType.deposit;
    }
    for (final k in _withdrawalKeywords) {
      if (normalized.contains(k.toLowerCase())) return FinancialEventType.withdrawal;
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Amount Extraction — I3
  // -----------------------------------------------------------------------

  /// Priority 1 — "مبلغ" / "بمبلغ" marker:
  ///   الأكثر موثوقية لأن وجود الكلمة يشير مباشرة للمبلغ،
  ///   حتى لو الرسالة تحتوي أرقامًا أخرى (مرجع، هاتف، تاريخ).
  static final RegExp _amountByMarkerRegex = RegExp(
    r'ب?مبلغ\s*(\d+(?:,\d{3})*(?:\.\d{1,2})?)'
    r'(?:\s*(?:جم|جنيه(?:ًا|ا)?|ج\.م|EGP|LE))?',
    caseSensitive: false,
  );

  /// Priority 2 — رقم + كلمة عملة (بدون marker):
  ///   يدعم: جم، جنيه، جنيها، جنيهًا، EGP، LE، ج.م
  static final RegExp _amountByCurrencyRegex = RegExp(
    r'(\d+(?:,\d{3})*(?:\.\d{1,2})?)\s*(?:جم|جنيه(?:ًا|ا)?|ج\.م|EGP|LE)'
    r'|(?:EGP|LE)\s*(\d+(?:,\d{3})*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// استخراج المبلغ:
  ///   1. نجهز النص (أرقام عربية + فواصل عربية → لاتينية)
  ///   2. نجرب pattern الـ marker أولًا (ب?مبلغ)
  ///   3. لو مفيش marker، نجرب رقم + كلمة عملة
  ///   4. لو مفيش عملة، نرجع null (ممنوع نأخذ أي رقم عشوائيًا)
  static double? extractAmount(String text) {
    final normalized = TextNormalizer.prepare(text);

    // Priority 1: marker صريح
    final markerMatch = _amountByMarkerRegex.firstMatch(normalized);
    if (markerMatch != null) {
      final raw = markerMatch.group(1)?.replaceAll(',', '');
      if (raw != null) return double.tryParse(raw);
    }

    // Priority 2: رقم + عملة
    final currencyMatch = _amountByCurrencyRegex.firstMatch(normalized);
    if (currencyMatch != null) {
      final raw = (currencyMatch.group(1) ?? currencyMatch.group(2))
          ?.replaceAll(',', '');
      if (raw != null) return double.tryParse(raw);
    }

    return null; // مفيش سياق كافٍ — أمان أفضل من تخمين رقم خاطئ
  }
}
