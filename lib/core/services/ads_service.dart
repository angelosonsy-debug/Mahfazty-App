import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'premium_service.dart';

/// AdMob: تهيئة + إعلان بيني واحد بس لكل فتحة تطبيق (Session).
///
/// الـ IDs الحقيقية بتتستخدم في الـ release بس. في الـ debug/profile بنستخدم
/// IDs الاختبار الرسمية من Google — الضغط على إعلانات حقيقية وقت التطوير
/// ممكن يعرّض حساب AdMob للإيقاف.
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  /// App ID الموجود في AndroidManifest.xml تحت
  /// `com.google.android.gms.ads.APPLICATION_ID`.
  /// ⚠️  ثابت للتطبيق كله — لو غيّرته هنا غيّره في الـ Manifest أيضًا.
  static const appId = 'ca-app-pub-1668741011095023~4128418397';
  static const _prodBanner = 'ca-app-pub-1668741011095023/7283038655';
  static const _prodInterstitial = 'ca-app-pub-1668741011095023/7876091711';
  static const _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';

  /// أقل وقت بعد فتح التطبيق قبل ما نعرض البيني — عشان مايطلعش على
  /// أول لمسة (تجربة وحشة، وبعض سياسات AdMob بتمنع إعلان وقت الفتح).
  static const minTimeBeforeFirstAd = Duration(seconds: 20);

  String get bannerUnitId => kReleaseMode ? _prodBanner : _testBanner;
  String get interstitialUnitId => kReleaseMode ? _prodInterstitial : _testInterstitial;

  /// بتبقى true بعد نجاح MobileAds.initialize (في الاختبارات مش بتبقى true
  /// أبدًا، فكل الدوال هنا no-op ومفيش نداء لأي plugin).
  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  final DateTime _startedAt = DateTime.now();
  InterstitialAd? _interstitial;
  bool _loading = false;
  bool _shownThisSession = false;
  int _retries = 0;

  Future<void> init() async {
    try {
      await MobileAds.instance.initialize();
      ready.value = true;
      _loadInterstitial();
    } catch (e) {
      debugPrint('AdsService.init failed: $e');
    }
  }

  void _loadInterstitial() {
    if (!ready.value || _loading || _interstitial != null || _shownThisSession) return;
    if (PremiumService.instance.isPremium) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loading = false;
          _retries = 0;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          debugPrint('Interstitial failed to load: $error');
          if (_retries < 3) {
            _retries++;
            Future<void>.delayed(Duration(seconds: 30 * _retries), _loadInterstitial);
          }
        },
      ),
    );
  }

  /// بتتنادى عند أي انتقال طبيعي (تغيير تاب / فتح شاشة). بتعرض البيني
  /// مرة واحدة بس في الجلسة، ولو مش جاهز بتحاول تحمّله وتسيبها للانتقال
  /// الجاي. مبتعرضش لمستخدم Premium.
  bool maybeShowOnTransition() {
    if (!ready.value || _shownThisSession || PremiumService.instance.isPremium) return false;
    if (DateTime.now().difference(_startedAt) < minTimeBeforeFirstAd) return false;
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return false;
    }
    _shownThisSession = true;
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) => ad.dispose(),
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Interstitial failed to show: $error');
        ad.dispose();
      },
    );
    ad.show();
    return true;
  }
}
