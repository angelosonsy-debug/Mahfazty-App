library;
/// I2: SourcePolicy thin wrapper على SourceCatalog.
import '../models/financial_event.dart' show FinancialSource;
import 'source_catalog.dart';

export 'source_catalog.dart'
    show
        SourcePolicyDefinition,
        sourceCatalog,
        findSourceDefinition,
        kLegacyWalletIdNbe,
        kLegacyWalletIdVf,
        kUnmappedWalletId,
        legacySourceToWalletId;

enum SmsSourceMatch { vodafoneCash, alAhlyBank, unknown }

class SourcePolicy {
  /// تحديد مصدر SMS — عبر SourceCatalog.
  static SmsSourceMatch identifySmsSource(String sender) {
    final def = findSourceDefinition(sender);
    if (def == null) return SmsSourceMatch.unknown;
    switch (def.legacySource) {
      case FinancialSource.vodafoneCash:
        return SmsSourceMatch.vodafoneCash;
      case FinancialSource.alAhlyBank:
        return SmsSourceMatch.alAhlyBank;
      default:
        return SmsSourceMatch.unknown;
    }
  }

  /// Convenience methods — used by tests and existing code
  static bool isVodafoneCashSender(String sender) =>
      identifySmsSource(sender) == SmsSourceMatch.vodafoneCash;

  static bool isAlAhlyBankSender(String sender) =>
      identifySmsSource(sender) == SmsSourceMatch.alAhlyBank;

  /// تحديد إشعار InstaPay — عبر SourceCatalog.
  static bool isInstaPayAppNotification(String packageName) {
    final def = findSourceDefinition(packageName);
    return def?.id == 'instapay_notification';
  }

  /// تحويل SmsSourceMatch لـ FinancialSource المقابلة — نقطة واحدة
  /// يُستخدم منها SmsParser وAiAssistedIngestion، عشان الخريطة تفضل
  /// مكان واحد بس (قبل كده كانت متكررة بـ ternary في أكتر من ملف، وفيه
  /// واحدة منها كانت بتخمّن المصدر من نص الـ sender نفسه بدل ما تاخده
  /// من القرار الفعلي). [unknown] بترجع dynamicSource — الاستدعاء هنا
  /// المفروض يبقى لمصدر اتأكد المستدعي إنه مسجّل ديناميكيًا من المستخدم
  /// (WalletSource)، مش unknown حقيقي، لأن ده كان هيتوقف في البوابة
  /// قبل ما يوصل هنا أصلًا.
  static FinancialSource legacyFinancialSourceFor(SmsSourceMatch match) {
    switch (match) {
      case SmsSourceMatch.vodafoneCash:
        return FinancialSource.vodafoneCash;
      case SmsSourceMatch.alAhlyBank:
        return FinancialSource.alAhlyBank;
      case SmsSourceMatch.unknown:
        return FinancialSource.dynamicSource;
    }
  }
}
