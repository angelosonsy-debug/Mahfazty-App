/// Model خفيف للـ fragment الخام قبل أي reassembly.
/// الحقول هنا بس اللي بتوصلنا فعليًا من أندرويد — مش هناك إضافات
/// افتراضية. ملحوظة: أندرويد مش بيديّنا SMS id ولا concatenation
/// reference number على مستوى الـ MethodChannel الحالي، فبنعتمد على
/// sender + timestamp + textual continuity بس.
enum FragmentSourceType { sms, notification }

class MessageFragment {
  final String fragmentId;

  /// نوع المصدر — SMS ولا Notification
  final FragmentSourceType sourceType;

  /// للـ SMS: رقم المرسل ("VF-Cash"، "AhlyBank"، إلخ)
  /// للـ Notification: packageName ("com.instapay.eg"، إلخ)
  final String sender;

  /// النص بعد TextNormalizer.prepare():
  /// - SMS: body
  /// - Notification: "$title $text"
  final String normalizedText;

  /// وقت الاستلام من أندرويد — System.currentTimeMillis() أو postTime
  final DateTime receivedAt;

  const MessageFragment({
    required this.fragmentId,
    required this.sourceType,
    required this.sender,
    required this.normalizedText,
    required this.receivedAt,
  });
}
