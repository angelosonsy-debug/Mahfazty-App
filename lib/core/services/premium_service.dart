import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../financial_engine/models/wallet.dart';

/// حالة Premium. دلوقتي مجرد علم محلي (placeholder) لحد ما نربط Google Play
/// Billing — وقتها `setPremium(true)` هو اللي هيتنادى بعد التحقق من الشراء.
///
/// عمدًا مش جزء من النسخة الاحتياطية (BackupService) عشان استعادة نسخة
/// احتياطية ما تفتحش Premium من غير شراء.
class PremiumService extends ChangeNotifier {
  PremiumService();

  static final PremiumService instance = PremiumService();

  static const freeWalletLimit = 2;
  static const _prefsKey = 'is_premium';

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isPremium = prefs.getBool(_prefsKey) ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('PremiumService.load failed: $e');
    }
  }

  Future<void> setPremium(bool value) async {
    _isPremium = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
    notifyListeners();
  }

  /// المحافظ المؤرشفة مبتتحسبش على حد النسخة المجانية.
  int activeWalletCount(Iterable<Wallet> wallets) => wallets.where((w) => !w.archived).length;

  bool canAddWallet(Iterable<Wallet> wallets) =>
      _isPremium || activeWalletCount(wallets) < freeWalletLimit;
}
