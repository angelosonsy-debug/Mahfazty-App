/// طبقة سياسة صريحة لقبول/رفض المصادر - القرار هنا وبس، مش متوزع بين
/// الـ Parser والـ AI والـ UI والـ Storage. أي حد عايز يعرف "هل المصدر
/// ده مقبول؟" بيسأل هنا. **مهم جدًا: السياسة دي بتتطبق قبل أي استدعاء
/// للـ AI خالص** - الـ AI بيفسّر معنى رسالة من مصدر اتوافق عليه بالفعل،
/// مش بيقرر هو نفسه هل المصدر مقبول ولا لأ. النص جوه الرسالة (حتى لو
/// فيه كلمة "InstaPay" حرفيًا) مش دليل كافي على مين المصدر الحقيقي.
enum SmsSourceMatch { vodafoneCash, alAhlyBank, unknown }

class SourcePolicy {
  static String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// فودافون كاش: المرسل المقبول هو VF-Cash بس (بأي صيغة تشكيل بينها/
  /// فراغات - "VF-Cash", "VFCash", "vf cash"...). أي اسم "Vodafone" عام
  /// تاني (زي "Vodafone Egypt" أو أي عرض/خدمة) **مرفوض تمامًا** ومش
  /// بيتحسب كمحفظة Vodafone Cash.
  static bool isVodafoneCashSender(String sender) {
    return _normalize(sender) == 'vfcash';
  }

  /// البنك الأهلي - أحد مصدرين ماليين مقبولين لمحفظة InstaPay (التاني هو
  /// إشعار تطبيق InstaPay نفسه - شوف isInstaPayAppNotification تحت).
  static bool isAlAhlyBankSender(String sender) {
    final lower = sender.toLowerCase();
    return lower.contains('ahly') ||
        lower.contains('alahly') ||
        sender.contains('اهلي') ||
        sender.contains('أهلي');
  }

  static SmsSourceMatch identifySmsSource(String sender) {
    if (isVodafoneCashSender(sender)) return SmsSourceMatch.vodafoneCash;
    if (isAlAhlyBankSender(sender)) return SmsSourceMatch.alAhlyBank;
    return SmsSourceMatch.unknown;
  }

  /// المصدر الثاني المقبول لمحفظة InstaPay: إشعار حقيقي من تطبيق
  /// InstaPay نفسه - بنتأكد من هوية التطبيق اللي بعت الإشعار عن طريق
  /// الـ package name الفعلي اللي أندرويد بيدّيهولنا (مش قابل للتزييف من
  /// تطبيق تاني)، **مش من نص الإشعار**. أي إشعار من WhatsApp أو Vodafone
  /// أو أي تطبيق تاني - حتى لو نصه فيه كلمة "InstaPay" أو "تحويل" أو أي
  /// كلمة مالية - مرفوض هنا، ومش بيوصل حتى لخطوة فهم الـ AI.
  static bool isInstaPayAppNotification(String packageName) {
    return packageName.toLowerCase().contains('instapay');
  }
}
