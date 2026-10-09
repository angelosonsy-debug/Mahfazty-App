/// حساب القسط (Flat rate بسيط — تقديري، مش بديل لعقد البنك/الشركة).
class InstallmentPlan {
  final double financedAmount; // المبلغ بعد المقدّم
  final double totalInterest;
  final double monthlyPayment;
  final double totalPaid; // المقدّم + كل الأقساط

  const InstallmentPlan({
    required this.financedAmount,
    required this.totalInterest,
    required this.monthlyPayment,
    required this.totalPaid,
  });
}

/// بترجع null لو المدخلات غير منطقية (مبلغ <= 0، مقدّم >= الإجمالي،
/// شهور خارج 1..120، فايدة سالبة أو غير صالحة).
InstallmentPlan? calculateInstallment({
  required double total,
  double downPayment = 0,
  required int months,
  double annualRatePercent = 0,
}) {
  if (!total.isFinite || total <= 0) return null;
  if (!downPayment.isFinite || downPayment < 0 || downPayment >= total) return null;
  if (months < 1 || months > 120) return null;
  if (!annualRatePercent.isFinite || annualRatePercent < 0) return null;

  final financed = total - downPayment;
  final years = months / 12;
  final interest = financed * (annualRatePercent / 100) * years;
  final monthly = (financed + interest) / months;
  return InstallmentPlan(
    financedAmount: financed,
    totalInterest: interest,
    monthlyPayment: monthly,
    totalPaid: downPayment + financed + interest,
  );
}

/// تاريخ القسط رقم [index] (يبدأ من 1) بعد [start] بالشهور الميلادية —
/// لو اليوم مش موجود في الشهر الهدف (31 → فبراير) بنستخدم آخر يوم فيه.
DateTime installmentDueDate(DateTime start, int index) {
  final monthIndex = start.month - 1 + index;
  final year = start.year + monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = start.day > lastDay ? lastDay : start.day;
  return DateTime(year, month, day);
}
