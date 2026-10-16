/// تنسيق مبلغ بفواصل الآلاف من غير أي مكتبة إضافية (مثال: 4160 → "4,160.00").
/// القيمة السالبة بتتكتب بشرطة في الأول، والصفر (حتى -0.001) بيتكتب من غير شرطة.
String formatMoney(double value, {int decimals = 2}) {
  final fixed = value.abs().toStringAsFixed(decimals);
  final isZero = double.parse(fixed) == 0;
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final remaining = intPart.length - i;
    buffer.write(intPart[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  final body = decimals > 0 ? '${buffer.toString()}.${parts[1]}' : buffer.toString();
  return (value < 0 && !isZero) ? '-$body' : body;
}
