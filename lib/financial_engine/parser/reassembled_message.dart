import 'message_fragment.dart';

/// الناتج من MessageReassembler — إما نص مُجمَّع من عدة fragments
/// أو نص واحد مرّ عبر النظام من غير تعديل (passthrough).
class ReassembledMessage {
  /// النص النهائي الجاهز للـ parser
  final String text;

  /// timestamp أقدم fragment (هو اللي بنعتمده كوقت العملية)
  final DateTime timestamp;

  /// sender/packageName
  final String sender;

  final FragmentSourceType sourceType;

  /// عدد الـ fragments اللي اتجمعوا (1 = passthrough / رسالة كاملة)
  final int fragmentCount;

  /// true لو أكتر من fragment اتدمجوا
  bool get wasReassembled => fragmentCount > 1;

  const ReassembledMessage({
    required this.text,
    required this.timestamp,
    required this.sender,
    required this.sourceType,
    required this.fragmentCount,
  });
}
