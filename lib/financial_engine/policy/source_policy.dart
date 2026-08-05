/// طبقة سياسة صريحة لقبول/رفض المصادر - القرار هنا وبس، مش متوزع بين
/// الـ Parser والـ UI والـ Storage. أي حد عايز يعرف "هل المصدر ده مقبول؟"
/// بيسأل هنا، مفيش قرار مصادر في أي مكان تاني.
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

  /// البنك الأهلي - المصدر المالي الحقيقي الوحيد لمحفظة InstaPay (شرح
  /// في README). بنقبل أي صيغة معروفة لاسم المرسل.
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

  /// InstaPay مستبعدة تمامًا من أي حساب مالي تلقائي. إشعاراتها ممكن
  /// تتلقط على مستوى أندرويد (الإذن لسه موجود)، لكن التطبيق ممنوع
  /// يبني منها أي FinancialEvent أو يأثر بيها على أي رصيد. التعامل
  /// المالي الفعلي لمحفظة InstaPay بيجي حصريًا من رسائل البنك الأهلي.
  static bool acceptInstaPayNotificationsForAccounting() => false;
}
