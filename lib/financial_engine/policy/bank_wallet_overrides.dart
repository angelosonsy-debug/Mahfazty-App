import 'package:shared_preferences/shared_preferences.dart';

/// شاشات التعريف (Onboarding) بتسأل المستخدم عن بنكه ومحفظته الفعليين.
/// لو اختار غير البنك الأهلي/فودافون كاش، بنفترض (بطلب صريح من المنتج)
/// إن البنك/المحفظة التاني بيبعت نفس نوعية الرسايل بالظبط - فبدل ما
/// نحطه على مسار SemanticClassifier الضعيف (مسار المصادر الديناميكية
/// العادي)، بنخلّي [sourceCatalog] نفسه يطابق مرسل المستخدم الفعلي
/// مكان "ahly"/"vfcash" الافتراضيين، فيستخدم نفس Templates الحرفية
/// بالظبط من غير أي تغيير تاني في منطق التحليل.
///
/// القيم هنا in-memory بس (static) عشان sourceCatalog.matches() محتاجة
/// وصول synchronous أثناء معالجة أي SMS واردة. لازم [load] تتنادى
/// وتخلص (await) قبل أي استقبال SMS ممكن يحصل - main() بتعمل كده قبل
/// runApp() مباشرة، فمضمون تحميلها قبل ما initState بتاعة AppShell
/// تسجّل أي MethodChannel handler.
class BankWalletOverrides {
  static const _bankSenderKey = 'mahfazty_bank_sender_override_v1';
  static const _walletSenderKey = 'mahfazty_wallet_sender_override_v1';

  /// null = استخدم مطابقة البنك الأهلي الافتراضية ("ahly"/"اهلي" إلخ).
  static String? bankSenderId;

  /// null = استخدم مطابقة فودافون كاش الافتراضية ("vfcash").
  static String? walletSenderId;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    bankSenderId = prefs.getString(_bankSenderKey);
    walletSenderId = prefs.getString(_walletSenderKey);
  }

  static Future<void> setBankSender(String? senderId) async {
    bankSenderId = senderId;
    final prefs = await SharedPreferences.getInstance();
    if (senderId == null) {
      await prefs.remove(_bankSenderKey);
    } else {
      await prefs.setString(_bankSenderKey, senderId);
    }
  }

  static Future<void> setWalletSender(String? senderId) async {
    walletSenderId = senderId;
    final prefs = await SharedPreferences.getInstance();
    if (senderId == null) {
      await prefs.remove(_walletSenderKey);
    } else {
      await prefs.setString(_walletSenderKey, senderId);
    }
  }

  /// نفس منطق المطابقة المستخدم في كل مكان تاني بالمشروع (substring في
  /// الاتجاهين، lowercase) - عشان القرار يفضل متسق مع _assignWalletId
  /// وباقي أماكن المطابقة.
  static bool matchesOverride(String identifier, String override) {
    final a = identifier.toLowerCase();
    final b = override.toLowerCase();
    return a.contains(b) || b.contains(a);
  }
}
