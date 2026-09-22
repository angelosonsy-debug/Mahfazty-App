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
}
