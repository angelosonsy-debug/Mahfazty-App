import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'premium_service.dart';

/// طبقة الشراء الحقيقي عبر Google Play Billing. بديل TODO(billing) القديم
/// في premium_modal.dart، اللي كان بيعرض "قريبًا" بس من غير أي اتصال
/// فعلي بمتجر Google.
///
/// معرّف المنتج ده **لازم يتسجّل بنفس الاسم بالحرف** في Play Console
/// (Monetize → Products → In-app products) كمنتج "Managed product"
/// (مش استهلاكي - شراء مرة واحدة يفضل للأبد، يناسب "فتح محافظ غير
/// محدودة" تمامًا). التسجيل في Play Console خطوة بشرية لازم تتعمل
/// بعد ما التطبيق يترفع لأول مرة (حتى لو Internal Testing) - الشراء
/// الحقيقي مش هيشتغل قبل كده، وده قيد من Google نفسه مش من الكود.
const String kPremiumProductId = 'mahfazty_premium_unlock';

enum BillingStatus { idle, unavailable, loading, purchasing, success, error, canceled }

/// نتيجة أبسط للـ UI يستهلكها من غير ما يتعامل مع تفاصيل الـ plugin.
class BillingState {
  final BillingStatus status;
  final String? message;
  final ProductDetails? product;

  const BillingState({required this.status, this.message, this.product});
}

class BillingService extends ChangeNotifier {
  BillingService._();
  static final BillingService instance = BillingService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  BillingState _state = const BillingState(status: BillingStatus.loading);
  BillingState get state => _state;

  bool _initialized = false;

  /// بتتنادى مرة واحدة بس عند بدء التطبيق (main()). لو المتجر مش متاح
  /// (نادر - جهاز من غير خدمات Google مثلًا)، التطبيق يفضل شغال عادي؛
  /// زرار الشراء هيظهر معطّل برسالة واضحة بدل ما يفشل بصمت.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final available = await _iap.isAvailable();
    if (!available) {
      _emit(const BillingState(status: BillingStatus.unavailable, message: 'متجر Google Play مش متاح على الجهاز ده'));
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () => _subscription?.cancel(),
      onError: (Object error) {
        _emit(BillingState(status: BillingStatus.error, message: 'حصل خطأ في المتجر: $error'));
      },
    );

    await _loadProduct();
  }

  Future<void> _loadProduct() async {
    try {
      final response = await _iap.queryProductDetails({kPremiumProductId});
      if (response.error != null) {
        _emit(BillingState(status: BillingStatus.error, message: response.error!.message));
        return;
      }
      if (response.productDetails.isEmpty) {
        // المنتج لسه مش متسجّل في Play Console، أو التطبيق لسه ما
        // اترفعش - حالة متوقعة قبل أول رفع، مش خطأ حقيقي في الكود.
        _emit(const BillingState(
          status: BillingStatus.unavailable,
          message: 'منتج Premium لسه مش متاح على المتجر',
        ));
        return;
      }
      _emit(BillingState(status: BillingStatus.idle, product: response.productDetails.first));
    } catch (e) {
      _emit(BillingState(status: BillingStatus.error, message: 'فشل تحميل بيانات المنتج: $e'));
    }
  }

  /// يبدأ عملية الشراء الفعلية. الاستجابة الحقيقية (نجاح/فشل/إلغاء) بتوصل
  /// لاحقًا عبر purchaseStream → _handlePurchaseUpdates، مش من هنا مباشرة
  /// (الشراء async بطبيعته - ممكن ياخد وقت لو المستخدم بيأكد بصمة/PIN).
  Future<void> buyPremium() async {
    final product = _state.product;
    if (product == null) return;
    _emit(BillingState(status: BillingStatus.purchasing, product: product));
    try {
      final param = PurchaseParam(productDetails: product);
      // Non-consumable: شراء مرة واحدة يفضل للأبد (مش بيتستهلك ويتشترى
      // تاني زي الكوينز مثلًا) - يناسب "فتح محافظ غير محدودة".
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      _emit(BillingState(status: BillingStatus.error, message: 'فشل بدء عملية الشراء: $e', product: product));
    }
  }

  /// لازم نوفّرها - شرط من Google Play لأي منتج غير استهلاكي: المستخدم
  /// لازم يقدر يسترجع شراء سابق (بعد فورمات الجهاز، أو تثبيت على جهاز
  /// جديد) من غير ما يدفع تاني.
  Future<void> restorePurchases() async {
    _emit(BillingState(status: BillingStatus.loading, product: _state.product));
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _emit(BillingState(status: BillingStatus.error, message: 'فشل استرجاع المشتريات: $e', product: _state.product));
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != kPremiumProductId) continue;

      switch (purchase.status) {
        case PurchaseStatus.pending:
          _emit(BillingState(status: BillingStatus.purchasing, product: _state.product));
        case PurchaseStatus.error:
          _emit(BillingState(
            status: BillingStatus.error,
            message: purchase.error?.message ?? 'فشلت عملية الشراء',
            product: _state.product,
          ));
        case PurchaseStatus.canceled:
          _emit(BillingState(status: BillingStatus.canceled, product: _state.product));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // ملحوظة أمان: التحقق هنا على مستوى الجهاز بس (status من
          // الـ plugin نفسه اللي بيتحقق مع Play Store)، مش تحقق سيرفر
          // مستقل بالـ purchase token. التحقق السيرفري أقوى ضد التلاعب
          // لكن بيحتاج backend مخصص للتحقق من الإيصالات - التطبيق ده
          // offline-first ومفيهوش backend عام (غير AI proxy اختياري)،
          // فده تريد-أوف واعي مناسب لمنتج بسعر منخفض single-purchase،
          // مش أمان كامل ضد كل أنواع القرصنة.
          await PremiumService.instance.setPremium(true);
          _emit(BillingState(status: BillingStatus.success, product: _state.product));
      }

      // لازم نأكّد كل عملية شراء (حتى لو فشلت أو اتلغت) - غير كده Google
      // بترجع الفلوس تلقائيًا بعد 3 أيام حتى لو فعليًا اتعالجت صح عندنا.
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  void _emit(BillingState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
