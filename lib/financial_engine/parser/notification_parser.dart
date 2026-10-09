import '../models/financial_event.dart';
import '../../core/utils/text_normalizer.dart';
import 'semantic_classifier.dart';
import 'promotional_filter.dart';

/// Parser للإشعارات العامة (InstaPay) - بيستخدم نفس الفهم الدلالي
/// (SemanticClassifier) اللي بيستخدمه SmsParser، وبيستبعد أي إشعار
/// ترويجي/غير مالي تمامًا قبل ما يوصل لأي حاجة.
///
/// ملحوظة سياسة مهمة: إشعار InstaPay لوحده مش كافي يتحسب على الرصيد
/// فورًا (بيتسجل بثقة محدودة) - القرار النهائي بتاخده FinancialEngine،
/// اللي بيحاول يطابقه مع رسالة SMS من البنك الأهلي لنفس المبلغ في نفس
/// النافذة الزمنية (دقيقتين) قبل ما يعتمده كمعاملة موثوقة.
class NotificationParser {
  static FinancialEvent? analyze(
    String packageName,
    String title,
    String text, {
    DateTime? receivedAt,
  }) {
    final combinedRaw = '$title $text';
    final normalized = TextNormalizer.prepare(combinedRaw);

    if (PromotionalFilter.isPromotional(normalized)) {
      return null; // إشعار ترويجي/غير مالي - نتجاهله تمامًا
    }

    final eventType = SemanticClassifier.classify(combinedRaw);
    final amount = SemanticClassifier.extractAmount(combinedRaw);

    if (eventType == null && amount == null) {
      return null; // مش مالي خالص
    }

    final int confidence;
    if (eventType != null && amount != null) {
      confidence = 70; // واضح بس لسه محتاج تطابق مع البنك الأهلي عشان يتوثق
    } else if (eventType != null) {
      confidence = 55;
    } else {
      confidence = 45;
    }

    return FinancialEvent(
      id: generateEventId(),
      source: FinancialSource.instaPay,
      eventType: eventType ?? FinancialEventType.unknown,
      amount: amount,
      timestamp: receivedAt ?? DateTime.now(),
      confidence: confidence,
      rawMessage: normalized,
      rawSource: packageName,
    );
  }
}
