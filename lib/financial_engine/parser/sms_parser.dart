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

  /// I8: شرح مبسّط للمستخدم — كيف تم تفسير الرسالة (للـ Source Test UI)
  final String? explanation;

  const SmsParseResult({
    required this.matchedSource,
    required this.event,
    required this.normalizedBody,
    this.explanation,
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
  ///
  /// [isDynamicallyRegistered]: المستدعي (AiAssistedIngestion) بيحددها
  /// true لو المرسل ده اتسجّل كـ WalletSource من المستخدم نفسه (محفظة
  /// مش من ضمن المصادر الثابتة الجاهزة زي فودافون كاش/البنك الأهلي).
  /// في الحالة دي، SourcePolicy بترجع unknown (لأنها معتمدة بس على
  /// الكتالوج الثابت)، بس إحنا هنا بنعامل المصدر كـ "معروف" بدل ما نرفضه
  /// فورًا — مفيش Templates جاهزة له، فهيعدّي مباشرة على SemanticClassifier
  /// (كلمات مفتاحية + "بمبلغ") زي أي رسالة معروفة المصدر بس مطابقتش
  /// Template بالحرف.
  static SmsParseResult parse(
    String sender,
    String body, {
    DateTime? receivedAt,
    bool isDynamicallyRegistered = false,
  }) {
    final matchedSource = identifySource(sender);
    final normalized = TextNormalizer.prepare(body);
    final timestamp = receivedAt ?? DateTime.now();

    final isKnown = matchedSource != SmsSourceMatch.unknown || isDynamicallyRegistered;
    if (!isKnown) {
      return SmsParseResult(matchedSource: matchedSource, event: null, normalizedBody: normalized);
    }

    // مفيش Templates جاهزة إلا للمصدرين الثابتين — أي مصدر ديناميكي
    // (unknown + isDynamicallyRegistered) بيعدّي على طول لـ SemanticClassifier
    // تحت، من غير محاولة مطابقة قوالب مش موجودة أصلًا.
    final List<SmsTemplate> templates;
    if (matchedSource == SmsSourceMatch.vodafoneCash) {
      templates = vodafoneCashTemplates;
    } else if (matchedSource == SmsSourceMatch.alAhlyBank) {
      templates = alAhlyBankTemplates;
    } else {
      templates = const <SmsTemplate>[];
    }

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
        return SmsParseResult(
          matchedSource: matchedSource,
          event: event,
          normalizedBody: normalized,
          explanation: 'تم التعرف على النمط «${template.id}» من المصدر $sender.',
        );
      }
    }

    // المرسل معروف بس مفيش Template اتطبق بالحرف. الأول: لو الرسالة
    // ترويجية/عرض واضح، نتجاهلها تمامًا - مش معاملة، ومش هتوصل حتى لصندوق
    // المراجعة (Inbox) خالص.
    if (PromotionalFilter.isPromotional(normalized)) {
      return SmsParseResult(matchedSource: matchedSource, event: null, normalizedBody: normalized);
    }

    // قبل ما نستسلم، نجرب نفهم "معنى" الرسالة (كلمة إضافة/خصم + مبلغ)
    // بدل ما نرجع "غير معروف" على طول. ده بالظبط المسار اللي أي مصدر
    // ديناميكي (بنك/محفظة جديدة المستخدم ضافها) بيمر عليه دايمًا، لأنه
    // مفيش Template جاهز ليه أصلًا.
    final source = SourcePolicy.legacyFinancialSourceFor(matchedSource);

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
    final amountText = fallbackEvent.amount?.toStringAsFixed(2) ?? 'غير محدد';
    final explainFallback = matchedSource == SmsSourceMatch.unknown
        ? 'مصدر مُضاف يدويًا — تم التعرف من السياق العام (كلمات مفتاحية + المبلغ). '
            'المبلغ: $amountText'
        : 'تم التعرف على الرسالة من السياق العام. المبلغ: $amountText';
    return SmsParseResult(
      matchedSource: matchedSource,
      event: fallbackEvent,
      normalizedBody: normalized,
      explanation: explainFallback,
    );
  }
}
