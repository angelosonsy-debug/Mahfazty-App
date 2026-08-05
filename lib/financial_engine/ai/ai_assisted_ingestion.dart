import '../parser/sms_parser.dart';
import '../parser/notification_parser.dart';
import '../policy/source_policy.dart';
import '../engine/financial_engine.dart';
import '../models/financial_event.dart';
import '../../core/utils/text_normalizer.dart';
import 'ai_parser.dart';
import 'ai_settings_store.dart';

/// طبقة تنسيق مستقلة: بتوصل بين السياسة (SourcePolicy) والـ AI (AiParser)
/// والـ Rule Engine (SmsParser/NotificationParser) والـ FinancialEngine.
///
/// **الـ AI بقى المفسّر الأساسي للرسالة** - لو مفعّل وعنده مفتاح، هو أول
/// حاجة بتحاول تفهم الرسالة، مش بس مساعد لحالات الثقة الواطية زي قبل.
/// الـ Rule Engine (Templates + SemanticClassifier) دلوقتي بيشتغل بس لما
/// الـ AI **مش متاح** (مفيش مفتاح، متقفل، أو فشل الاتصال) - وده قصدي، مش
/// سهو: التطبيق ده أوفلاين بالأساس، فلازم يفضل شغال بمنطق داخلي حتى لو
/// المستخدم معملش AI Key أو النت مقطوع. قرار "مين المصدر المقبول؟"
/// (SourcePolicy) قاعدة صلبة بتتطبق قبل أي حاجة تانية - الـ AI مالوش
/// دخل فيها خالص، لأنها قاعدة مالية مش تفسير رسالة.
class AiAssistedIngestion {
  final FinancialEngine engine;
  final AiSettingsStore aiSettings;

  AiAssistedIngestion(this.engine, this.aiSettings);

  /// أعلى ثقة ممكن الـ AI يديها لحدث - أقل من 99 عمدًا (محجوزة لتأكيد
  /// يدوي فعلي من المستخدم نفسه)
  static const _aiConfidenceCap = 95;

  Future<void> ingestSms(String sender, String body, {DateTime? receivedAt}) async {
    final source = SourcePolicy.identifySmsSource(sender);
    if (source == SmsSourceMatch.unknown) return; // سياسة صلبة - الـ AI مالوش دخل فيها

    final normalized = TextNormalizer.prepare(body);
    final financialSource =
        source == SmsSourceMatch.vodafoneCash ? FinancialSource.vodafoneCash : FinancialSource.alAhlyBank;

    final aiAttempt = await _tryAiFirst(normalized, financialSource, sender, receivedAt);
    switch (aiAttempt.outcome) {
      case _AiOutcome.event:
        await engine.ingest(aiAttempt.event!);
        return;
      case _AiOutcome.ignored:
        return; // الـ AI قرر إنها ترويجية/مش مالية - خلاص، منرجعش نجرب القواعد
      case _AiOutcome.unavailable:
        break; // الـ AI مش متاح - نكمل بالقواعد تحت
    }

    final ruleResult = SmsParser.parse(sender, body, receivedAt: receivedAt);
    if (ruleResult.event != null) {
      await engine.ingest(ruleResult.event!);
    }
  }

  Future<void> ingestNotification(
    String packageName,
    String title,
    String text, {
    DateTime? receivedAt,
  }) async {
    final normalized = TextNormalizer.prepare('$title $text');

    final aiAttempt = await _tryAiFirst(normalized, FinancialSource.instaPay, packageName, receivedAt);
    switch (aiAttempt.outcome) {
      case _AiOutcome.event:
        await engine.ingest(aiAttempt.event!);
        return;
      case _AiOutcome.ignored:
        return;
      case _AiOutcome.unavailable:
        break;
    }

    final ruleEvent = NotificationParser.analyze(packageName, title, text, receivedAt: receivedAt);
    if (ruleEvent != null) {
      await engine.ingest(ruleEvent);
    }
  }

  Future<_AiAttempt> _tryAiFirst(
    String normalizedMessage,
    FinancialSource source,
    String rawSource,
    DateTime? receivedAt,
  ) async {
    final enabled = await aiSettings.loadEnabled();
    if (!enabled) return const _AiAttempt(_AiOutcome.unavailable);

    final apiKey = await aiSettings.loadApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) return const _AiAttempt(_AiOutcome.unavailable);

    final aiResult = await AiParser.analyze(normalizedMessage, apiKey: apiKey);
    if (aiResult == null) {
      // فشل الاتصال أو رد غير مفهوم - نتعامل معاه زي "مفيش AI خالص"
      return const _AiAttempt(_AiOutcome.unavailable);
    }

    if (aiResult.shouldIgnore || aiResult.isPromotional || !aiResult.isFinancial) {
      return const _AiAttempt(_AiOutcome.ignored);
    }

    final event = FinancialEvent(
      id: generateEventId(),
      source: source,
      eventType: aiResult.eventType ?? FinancialEventType.unknown,
      amount: aiResult.amount,
      balanceAfter: aiResult.remainingBalance,
      person: aiResult.senderName ?? aiResult.receiverName,
      timestamp: receivedAt ?? DateTime.now(),
      confidence: aiResult.confidence.clamp(0, _aiConfidenceCap),
      rawMessage: normalizedMessage,
      rawSource: rawSource,
      metadata: {
        'aiPrimary': true,
        if (aiResult.provider != null) 'provider': aiResult.provider!,
      },
    );

    return _AiAttempt(_AiOutcome.event, event);
  }
}

enum _AiOutcome { unavailable, ignored, event }

class _AiAttempt {
  final _AiOutcome outcome;
  final FinancialEvent? event;
  const _AiAttempt(this.outcome, [this.event]);
}
