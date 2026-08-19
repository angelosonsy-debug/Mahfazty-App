import 'text_normalizer.dart';

/// بيحول رسالة لـ"بصمة" ثابتة بتجاهل الأجزاء المتغيرة (الأرقام: مبالغ،
/// أرصدة، أرقام عمليات، تواريخ) - عشان نقدر نقول "الرسالة دي نفس شكل
/// رسالة اتصححت قبل كده" حتى لو المبلغ مختلف.
class MessageFingerprint {
  static String of(String rawMessage) {
    final withoutDigits = rawMessage.replaceAll(RegExp(r'[\d٠-٩]+'), '#');
    return TextNormalizer.collapseWhitespace(withoutDigits).toLowerCase();
  }
}
