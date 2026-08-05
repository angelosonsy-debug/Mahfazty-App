import '../models/financial_event.dart';
import 'sms_templates.dart';
import 'semantic_classifier.dart';
import 'promotional_filter.dart';
import '../policy/source_policy.dart';
import '../../core/utils/text_normalizer.dart';

export '../policy/source_policy.dart' show SmsSourceMatch;

class SmsParseResult {
  final SmsSourceMatch matchedSource;
  final FinancialEvent? event;
  final String normalizedBody;

  const SmsParseResult({
    required this.matchedSource,
    required this.event,
    required this.normalizedBody,
  });
}

class SmsParser {
  /// قرار "مين المرسل المقبول" بقى كله في SourcePolicy - الـ Parser مبيقررش
  /// لوحده، بيسأل السياسة بس.
  static SmsSourceMatch identifySource(String sender) => SourcePolicy.identifySmsSource(sender);

  /// [receivedAt] هو وقت استلام الرسالة الفعلي من أندرويد (epoch) - بنستخدمه
  /// كـ timestamp للحدث بدل ما نحاول نفسر التاريخ/الوقت المكتوب جوه نص
  /// الرسالة نفسه (صيغته مش ثابتة دايمًا)، وبنسيب النص الخام في metadata
  /// للمراجعة لو احتجناه.
  static SmsParseResult parse(String sender, String body, {DateTime? receivedAt}) {
    final matchedSource = identifySource(sender);
    final normalized = TextNormalizer.prepare(body);
    final timestamp = receivedAt ?? DateTime.now();

    if (matchedSource == SmsSourceMatch.unknown) {
      return SmsParseResult(matchedSource: matchedSource, event: null, normalizedBody: normalized);
    }

    final templates =
        matchedSource == SmsSourceMatch.vodafoneCash ? vodafoneCashTemplates : alAhlyBankTemplates;

    for (final template in templates) {
      final match = template.pattern.firstMatch(normalized);
      if (match != null) {
        final extraction = template.build(match);
        final event = FinancialEvent(
          id: generateEventId(),
          source: extraction.source,
          eventType: extraction.eventType,
          amount: extraction.amount,
          balanceAfter: extraction.balanceAfter,
          merchant: extraction.merchant,
          person: extraction.person,
          reference: extraction.reference,
          timestamp: timestamp,
          confidence: extraction.confidence,
          rawMessage: normalized,
          rawSource: sender,
          metadata: extraction.rawDateTimeText != null
              ? {'rawDateTimeText': extraction.rawDateTimeText}
              : const {},
        );
        return SmsParseResult(matchedSource: matchedSource, event: event, normalizedBody: normalized);
      }
    }

    // المرسل معروف بس مفيش Template اتطبق بالحرف. الأول: لو الرسالة
    // ترويجية/عرض واضح، نتجاهلها تمامًا - مش معاملة، ومش هتوصل حتى لصندوق
    // المراجعة (Inbox) خالص.
    if (PromotionalFilter.isPromotional(normalized)) {
      return SmsParseResult(matchedSource: matchedSource, event: null, normalizedBody: normalized);
    }

    // قبل ما نستسلم، نجرب نفهم "معنى" الرسالة (كلمة إضافة/خصم + مبلغ)
    // بدل ما نرجع "غير معروف" على طول.
    final source =
        matchedSource == SmsSourceMatch.vodafoneCash ? FinancialSource.vodafoneCash : FinancialSource.alAhlyBank;

    final semanticType = SemanticClassifier.classify(normalized);
    final semanticAmount = SemanticClassifier.extractAmount(normalized);

    final int confidence;
    if (semanticType != null && semanticAmount != null) {
      confidence = 85;
    } else if (semanticType != null) {
      confidence = 60;
    } else if (semanticAmount != null) {
      confidence = 50;
    } else {
      confidence = 70; // مفيش كلمة ولا مبلغ واضح - يحتاج مراجعة يدوية كاملة
    }

    final fallbackEvent = FinancialEvent(
      id: generateEventId(),
      source: source,
      eventType: semanticType ?? FinancialEventType.unknown,
      amount: semanticAmount,
      timestamp: timestamp,
      confidence: confidence,
      rawMessage: normalized,
      rawSource: sender,
    );
    return SmsParseResult(matchedSource: matchedSource, event: fallbackEvent, normalizedBody: normalized);
  }
}
