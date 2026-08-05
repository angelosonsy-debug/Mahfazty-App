import '../models/financial_event.dart';
import '../../core/utils/text_normalizer.dart';

/// تصنيف دلالي (Semantic) بديل عن الاعتماد على Template مضبوط بالحرف.
/// بيفهم "معنى" الرسالة من كلمات مفتاحية بدل ما يحتاج نص مطابق تمامًا.
/// دلوقتي بيرجع نوعين بس: إيداع أو سحب - أي تصنيف أدق (شراء/تحويل) لسه
/// شغلانة الـ Templates المضبوطة (فودافون كاش/البنك الأهلي).
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

    // بنجرب السحب الأول عمدًا: بعض الكلمات ("تم تحويل") ممكن تكون غامضة
    // لوحدها، لكن "تم تحويل منك" أوضح من "تم تحويل إليك" - الترتيب هنا
    // مش بيغير النتيجة لأن كل عبارة كاملة ومحددة الاتجاه بوضوح.
    for (final k in _depositKeywords) {
      if (normalized.contains(k.toLowerCase())) return FinancialEventType.deposit;
    }
    for (final k in _withdrawalKeywords) {
      if (normalized.contains(k.toLowerCase())) return FinancialEventType.withdrawal;
    }
    return null;
  }

  /// استخراج المبلغ - بيدعم أرقام عربي/إنجليزي، فواصل آلاف، كسور عشرية،
  /// و"جنيه"/"EGP"/"LE" قبل أو بعد الرقم
  static final RegExp _amountRegex = RegExp(
    r'(\d+(?:,\d{3})*(?:\.\d{1,2})?)\s*(?:جنيه|جنيها|ج\.م|egp|le)'
    r'|(?:egp|le)\s*(\d+(?:,\d{3})*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static double? extractAmount(String text) {
    final normalized = TextNormalizer.prepare(text);
    final match = _amountRegex.firstMatch(normalized);
    if (match == null) return null;
    final raw = (match.group(1) ?? match.group(2))?.replaceAll(',', '');
    if (raw == null) return null;
    return double.tryParse(raw);
  }
}
