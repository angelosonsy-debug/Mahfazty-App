import '../models/financial_event.dart';
import '../models/wallet_source.dart';
import '../parser/sms_templates.dart';

/// تعريف مصدر واحد — يجمع: معرّف المطابقة + القواعد + المصدر القديم للتوافق.
///
/// إضافة بنك/مصدر جديد = تسجيل SourcePolicyDefinition واحد في [sourceCatalog]
/// فقط، من غير تعديل أي ملف آخر.
class SourcePolicyDefinition {
  final String id;            // "nbe_sms", "vf_cash_sms", إلخ
  final String displayName;   // "البنك الأهلي (SMS)"
  final SourceType sourceType;

  /// دالة المطابقة — بتاخد الـ identifier الفعلي من أندرويد
  /// (sender name أو package name) وترجع true لو ده مصدرنا
  final bool Function(String identifier) matches;

  /// Templates الخاصة بهذا المصدر (مستخدمة في SmsParser الحالي)
  final List<SmsTemplate> templates;

  /// المصدر القديم (للتوافق مع الـ reconcile logic الحالي و الـ migration)
  final FinancialSource legacySource;

  const SourcePolicyDefinition({
    required this.id,
    required this.displayName,
    required this.sourceType,
    required this.matches,
    required this.templates,
    required this.legacySource,
  });
}

/// Catalog المصادر — القائمة الكاملة للمصادر المدعومة.
/// بيتُفحص بالترتيب — أول تعريف بيطابق الـ identifier يُستخدم.
final List<SourcePolicyDefinition> sourceCatalog = [
  // -----------------------------------------------------------------------
  // Vodafone Cash SMS
  // -----------------------------------------------------------------------
  SourcePolicyDefinition(
    id: 'vf_cash_sms',
    displayName: 'Vodafone Cash (SMS)',
    sourceType: SourceType.sms,
    matches: (id) {
      final n = id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      return n == 'vfcash';
    },
    templates: vodafoneCashTemplates,
    legacySource: FinancialSource.vodafoneCash,
  ),

  // -----------------------------------------------------------------------
  // البنك الأهلي SMS
  // -----------------------------------------------------------------------
  SourcePolicyDefinition(
    id: 'nbe_sms',
    displayName: 'البنك الأهلي (SMS)',
    sourceType: SourceType.sms,
    matches: (id) {
      final lower = id.toLowerCase();
      return lower.contains('ahly') ||
          lower.contains('alahly') ||
          id.contains('اهلي') ||
          id.contains('أهلي');
    },
    templates: alAhlyBankTemplates,
    legacySource: FinancialSource.alAhlyBank,
  ),

  // -----------------------------------------------------------------------
  // InstaPay Notification
  // -----------------------------------------------------------------------
  SourcePolicyDefinition(
    id: 'instapay_notification',
    displayName: 'InstaPay (إشعار)',
    sourceType: SourceType.notification,
    matches: (id) => id.toLowerCase().contains('instapay'),
    templates: const [],            // الإشعارات مش بيوصلها templates بنفس طريقة SMS
    legacySource: FinancialSource.instaPay,
  ),
];

/// ابحث عن تعريف المصدر المناسب لـ identifier معين.
/// يرجع null لو مفيش مصدر معروف (→ event يروح للـ Review)
SourcePolicyDefinition? findSourceDefinition(String identifier) {
  for (final def in sourceCatalog) {
    if (def.matches(identifier)) return def;
  }
  return null;
}

/// عنوان البنك الأهلي الافتراضي جوه Migration — walletId ثابت للـ migration
const kLegacyWalletIdNbe = 'wallet_nbe_legacy';

/// عنوان Vodafone Cash الافتراضي جوه Migration
const kLegacyWalletIdVf = 'wallet_vf_legacy';

/// لو مفيش mapping معروف للـ source → يُخزَّن تحت هذا الـ walletId كـ fallback
/// بدل ما يُفقَد الحدث أو يُهمَل
const kUnmappedWalletId = 'wallet_unmapped';

/// حوّل FinancialSource القديمة لـ walletId المقابلة (للتوافق أثناء الـ migration)
String legacySourceToWalletId(FinancialSource source) {
  switch (source) {
    case FinancialSource.vodafoneCash:
      return kLegacyWalletIdVf;
    case FinancialSource.alAhlyBank:
    case FinancialSource.instaPay:
      return kLegacyWalletIdNbe;
    case FinancialSource.manual:
      // Manual events تبقى بدون walletId هنا — engine يتعامل معها
      return kUnmappedWalletId;
  }
}
