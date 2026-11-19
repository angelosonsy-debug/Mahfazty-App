import 'package:url_launcher/url_launcher.dart';

import '../../financial_engine/models/wallet.dart';
import '../../financial_engine/policy/source_catalog.dart';

/// فتح شاشة الاتصال (Dialer) بكود USSD جاهز — المستخدم هو اللي بيضغط
/// "اتصال" بنفسه. ده ACTION_DIAL/VIEW عبر tel: وليس ACTION_CALL، فمفيش
/// حاجة اسمها صلاحية CALL_PHONE (اللي بتزوّد احتمال رفض Google Play).
///
/// فودافون كاش بس لحد دلوقتي: كود باقي الشبكات مش مؤكد، فمبنعرضش زر
/// ممكن يطلّع كود غلط.
class UssdLauncher {
  const UssdLauncher._();

  /// رقم موبايل مصري: 11 رقم يبدأ بـ 01. الفحص ده أمان مش تجميل — لو سبنا
  /// المستخدم يكتب `*` أو `#` في خانة الرقم، كان ممكن يتغير الكود نفسه.
  static final RegExp _egyptianMobile = RegExp(r'^01[0-9]{9}$');

  static bool isValidPhone(String phone) => _egyptianMobile.hasMatch(phone);

  /// الـ USSD بيقبل مبلغ صحيح بس — مبنقرّبش الكسور بصمت (50.5 → 51 كان
  /// هيحوّل مبلغ غير اللي المستخدم كتبه).
  static bool isValidAmount(double amount) =>
      amount.isFinite && amount >= 1 && amount == amount.roundToDouble();

  static bool isSupported(MobileCarrier? carrier) => carrier == MobileCarrier.vodafone;

  /// لمحافظ فودافون القديمة (اللي اتولّدت من الـ migration قبل ما الحقل
  /// carrier يتضاف) بنعتبرها فودافون لأن الـ id نفسه معروف ومحجوز.
  static MobileCarrier? resolveCarrier(Wallet wallet) {
    if (wallet.type != WalletType.mobileWallet) return null;
    if (wallet.carrier != null) return wallet.carrier;
    if (wallet.id == kLegacyWalletIdVf) return MobileCarrier.vodafone;
    return null;
  }

  /// null لو الشبكة مش مدعومة أو الرقم/المبلغ غير صالحين.
  static String? buildUssdCode(MobileCarrier carrier, String phone, double amount) {
    if (!isValidPhone(phone) || !isValidAmount(amount)) return null;
    switch (carrier) {
      case MobileCarrier.vodafone:
        // %23 = الـ # مُرمّز (الـ # في URI بتتعامل كـ fragment)
        return '*9*7*$phone*${amount.toStringAsFixed(0)}%23';
      case MobileCarrier.etisalat:
      case MobileCarrier.orange:
      case MobileCarrier.we:
      case MobileCarrier.unknown:
        return null;
    }
  }

  /// بترجع false لو مفيش تطبيق اتصال يفتح الرابط أو المدخلات غير صالحة.
  static Future<bool> launch(String phone, double amount, MobileCarrier carrier) async {
    final code = buildUssdCode(carrier, phone, amount);
    if (code == null) return false;
    return launchUrl(Uri.parse('tel:$code'));
  }
}
