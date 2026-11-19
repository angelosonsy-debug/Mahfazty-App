import 'package:shared_preferences/shared_preferences.dart';

import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/wallet.dart';
import '../../financial_engine/models/wallet_source.dart';
import '../../financial_engine/policy/bank_wallet_overrides.dart';
import '../../financial_engine/policy/source_catalog.dart';

/// اختيار المستخدم للمحفظة في شاشات التعريف.
enum OnboardingWalletChoice { vodafone, orange, etisalat, we, other }

extension OnboardingWalletChoiceLabel on OnboardingWalletChoice {
  String get labelAr {
    switch (this) {
      case OnboardingWalletChoice.vodafone: return 'فودافون كاش';
      case OnboardingWalletChoice.orange:   return 'أورنج كاش';
      case OnboardingWalletChoice.etisalat: return 'اتصالات كاش';
      case OnboardingWalletChoice.we:        return 'وي باي';
      case OnboardingWalletChoice.other:     return 'محفظة تانية';
    }
  }

  MobileCarrier get carrier {
    switch (this) {
      case OnboardingWalletChoice.vodafone: return MobileCarrier.vodafone;
      case OnboardingWalletChoice.orange:   return MobileCarrier.orange;
      case OnboardingWalletChoice.etisalat: return MobileCarrier.etisalat;
      case OnboardingWalletChoice.we:        return MobileCarrier.we;
      case OnboardingWalletChoice.other:     return MobileCarrier.unknown;
    }
  }
}

/// نتيجة شاشات التعريف — بتتحفظ وتتطبّق مرة واحدة بس بعد أول migration.
class OnboardingAnswers {
  final bool isCustomBank;
  final String? bankSenderId;
  final String? bankDisplayName;
  final OnboardingWalletChoice walletChoice;
  final String? walletSenderId;   // null لو vodafone (افتراضي) أو we (مفيهاش SMS أصلًا)
  final String? walletDisplayName; // null يعني استخدم labelAr الافتراضي

  const OnboardingAnswers({
    required this.isCustomBank,
    this.bankSenderId,
    this.bankDisplayName,
    required this.walletChoice,
    this.walletSenderId,
    this.walletDisplayName,
  });
}

class OnboardingStore {
  static const _completedKey = 'mahfazty_onboarding_completed_v1';
  static const _appliedKey = 'mahfazty_onboarding_applied_v1';
  static const _bankCustomKey = 'mahfazty_onboarding_bank_custom_v1';
  static const _bankSenderKey = 'mahfazty_onboarding_bank_sender_v1';
  static const _bankNameKey = 'mahfazty_onboarding_bank_name_v1';
  static const _walletChoiceKey = 'mahfazty_onboarding_wallet_choice_v1';
  static const _walletSenderKey = 'mahfazty_onboarding_wallet_sender_v1';
  static const _walletNameKey = 'mahfazty_onboarding_wallet_name_v1';

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  /// بتتنادى أول ما المستخدم يخلّص شاشات التعريف. بتحفظ الإجابات، وبتفعّل
  /// الـ overrides فورًا (عشان أي SMS توصل من اللحظة دي تتطابق صح حتى لو
  /// المحفظة/المصدر لسه معملهاش migration في قاعدة البيانات أصلًا على
  /// جهاز المستخدم ده بالذات - حالة نادرة بس آمن نتعامل معها).
  static Future<void> saveAndComplete(OnboardingAnswers answers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bankCustomKey, answers.isCustomBank);
    await prefs.setString(_walletChoiceKey, answers.walletChoice.name);
    if (answers.bankSenderId != null) {
      await prefs.setString(_bankSenderKey, answers.bankSenderId!);
    }
    if (answers.bankDisplayName != null) {
      await prefs.setString(_bankNameKey, answers.bankDisplayName!);
    }
    if (answers.walletSenderId != null) {
      await prefs.setString(_walletSenderKey, answers.walletSenderId!);
    }
    if (answers.walletDisplayName != null) {
      await prefs.setString(_walletNameKey, answers.walletDisplayName!);
    }
    await prefs.setBool(_completedKey, true);

    if (answers.isCustomBank && answers.bankSenderId != null) {
      await BankWalletOverrides.setBankSender(answers.bankSenderId);
    }
    if (answers.walletChoice == OnboardingWalletChoice.other && answers.walletSenderId != null) {
      await BankWalletOverrides.setWalletSender(answers.walletSenderId);
    }
  }

  /// بتتنادى بعد أول migration/engine.load() في main.dart — بتسمّي
  /// المحفظتين الافتراضيتين (والمصدرين) باختيارات المستخدم الفعلية.
  /// Idempotent عبر [_appliedKey]: تتطبّق مرة واحدة بس حتى لو التطبيق
  /// اتقفل وفتح تاني قبل ما تخلص.
  static Future<void> applyPendingCustomization(FinancialEngine engine) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_completedKey) != true) return;
    if (prefs.getBool(_appliedKey) == true) return;

    final isCustomBank = prefs.getBool(_bankCustomKey) ?? false;
    final bankSender = prefs.getString(_bankSenderKey);
    final bankName = prefs.getString(_bankNameKey);
    final walletChoiceName = prefs.getString(_walletChoiceKey);
    final walletChoice = OnboardingWalletChoice.values
        .where((c) => c.name == walletChoiceName)
        .firstOrNull ?? OnboardingWalletChoice.vodafone;
    final walletSender = prefs.getString(_walletSenderKey);
    final walletName = prefs.getString(_walletNameKey);

    if (isCustomBank && bankSender != null && bankName != null) {
      await _renameBankWallet(engine, newName: bankName, newSender: bankSender);
    }

    if (walletChoice != OnboardingWalletChoice.vodafone) {
      await _renameMobileWallet(
        engine,
        newName: walletName ?? walletChoice.labelAr,
        carrier: walletChoice.carrier,
        newSender: walletChoice == OnboardingWalletChoice.other ? walletSender : null,
        // وي باي ما بيبعتش SMS أصلًا - نعطّل مصدر SMS القديم (فودافون
        // كاش) بدل ما نسيبه شغال على اسم مرسل غلط.
        disableSmsSource: walletChoice == OnboardingWalletChoice.we,
      );
    }

    await prefs.setBool(_appliedKey, true);
  }

  static Future<void> _renameBankWallet(
    FinancialEngine engine, {
    required String newName,
    required String newSender,
  }) async {
    final wallet = engine.wallets.where((w) => w.id == kLegacyWalletIdNbe).firstOrNull;
    if (wallet != null) {
      await engine.updateWallet(wallet.copyWith(name: '$newName / InstaPay'));
    }
    final source = engine.walletSources.where((s) => s.id == 'ws_nbe_sms_legacy').firstOrNull;
    if (source != null) {
      await engine.updateWalletSource(WalletSource(
        id: source.id,
        walletId: source.walletId,
        sourceType: source.sourceType,
        identifier: newSender,
        displayName: '$newName (SMS)',
        enabled: source.enabled,
      ));
    }
  }

  static Future<void> _renameMobileWallet(
    FinancialEngine engine, {
    required String newName,
    required MobileCarrier carrier,
    String? newSender,
    required bool disableSmsSource,
  }) async {
    final wallet = engine.wallets.where((w) => w.id == kLegacyWalletIdVf).firstOrNull;
    if (wallet != null) {
      await engine.updateWallet(wallet.copyWith(name: newName, carrier: carrier));
    }
    final source = engine.walletSources.where((s) => s.id == 'ws_vf_cash_sms_legacy').firstOrNull;
    if (source != null) {
      await engine.updateWalletSource(WalletSource(
        id: source.id,
        walletId: source.walletId,
        sourceType: source.sourceType,
        identifier: newSender ?? source.identifier,
        displayName: '$newName (SMS)',
        enabled: disableSmsSource ? false : source.enabled,
      ));
    }
  }
}
