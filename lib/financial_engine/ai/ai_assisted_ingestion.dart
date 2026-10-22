import '../parser/sms_parser.dart';
import '../parser/transaction_candidate_filter.dart';
import '../parser/message_reassembler.dart';
import '../parser/notification_parser.dart';
import '../policy/source_policy.dart';
import '../engine/financial_engine.dart';
import '../models/financial_event.dart';
import '../models/wallet_source.dart';
import '../../core/utils/text_normalizer.dart';
import 'ai_backend_client.dart';
import 'ai_settings_store.dart';

/// طبقة تنسيق مستقلة: Rule Engine أولًا، AI backend فقط كـfallback عند الحاجة.
///
/// **الـ AI بقى المفسّر الأساسي للرسالة** - لو مفعّل وعنده مفتاح، هو أول
/// حاجة بتحاول تفهم الرسالة، مش بس مساعد لحالات الثقة الواطية زي قبل.
/// الـ Rule Engine (Templates + SemanticClassifier) دلوقتي بيشتغل بس لما
/// الـ AI **مش متاح** (مفيش مفتاح، متقفل، أو فشل الاتصال) - وده قصدي، مش
/// سهو: التطبيق ده أوفلاين بالأساس، فلازم يفضل شغال بمنطق داخلي حتى لو
/// المستخدم معملش AI Key أو النت مقطوع.
///
/// قرار "مين المصدر المقبول؟" قاعدة صلبة بتتطبق قبل أي حاجة تانية - الـ
/// AI مالوش دخل فيها خالص. المصدر مقبول في حالتين: (أ) أحد المصدرين
/// الثابتين الجاهزين (SourcePolicy — فودافون كاش/البنك الأهلي، وليهم
/// Templates حرفية جاهزة) أو (ب) مصدر مُسجّل ديناميكيًا من المستخدم نفسه
/// (WalletSource من نوع SMS على أي محفظة — بنك مصر، أورنج كاش، اتصالات
/// كاش، وي باي، ...) وفي الحالة دي مفيش Template جاهز، فالتفسير بيعتمد
/// على SemanticClassifier (كلمات مفتاحية + "بمبلغ") مباشرة، ونفس درجات
/// الثقة المتدرجة اللي بتتطبق على أي رسالة من مصدر ثابت مطابقتش Template
/// بالحرف.
class AiAssistedIngestion {
  final FinancialEngine engine;
  final AiSettingsStore aiSettings;

  /// المثيل الوحيد للـ Reassembler — المسار الكامل بعد C1:
  /// Raw SMS/Notification → MessageReassembler → SourcePolicy → AI → RuleEngine → engine.ingest
  final MessageReassembler _reassembler = MessageReassembler();
  final AiBackendClient _aiClient;

  AiAssistedIngestion(this.engine, this.aiSettings, {AiBackendClient? aiClient})
      : _aiClient = aiClient ?? AiBackendClient();

  Future<void> ingestSms(String sender, String body, {DateTime? receivedAt}) async {
    final source = SourcePolicy.identifySmsSource(sender);

    // مش معروف ثابتًا؟ نشوف لو المستخدم نفسه سجّل المرسل ده كـ WalletSource
    // من محفظة (فودافون/الأهلي بس عندهم Templates جاهزة، أي بنك/محفظة
    // تانية المستخدم ضافها بنفسه بتعدّي من هنا). البوابة لسه صلبة — لو
    // مش معروف ثابتًا ومش مسجّل يدويًا، نرفض فورًا.
    final isDynamic = source == SmsSourceMatch.unknown && _hasDynamicSmsSource(sender);
    if (source == SmsSourceMatch.unknown && !isDynamic) return;

    final normalized = TextNormalizer.prepare(body);

    // C1 — Fragmentation Reassembly: مش بنبعت fragment ناقص للـ parser.
    // بنعدي الرسالة على الـ reassembler الأول. لو رجع قائمة فاضية، الـ
    // fragment اتخزن وهنستنى الجزء القادم. لو رجع رسالة/رسائل مكتملة،
    // كل واحدة منهم بتعدي على المسار الكامل (AI → Rule Engine → engine.ingest).
    final assembled = _reassembler.addSmsFragment(
      sender: sender,
      normalizedBody: normalized,
      receivedAt: receivedAt ?? DateTime.now(),
    );
    for (final msg in assembled) {
      await _processSmsMessage(
        sender: sender,
        normalizedBody: msg.text,
        source: source,
        isDynamicSource: isDynamic,
        receivedAt: msg.timestamp,
      );
    }
  }

  /// فيه WalletSource من نوع SMS، مفعّلة، ومعرّفها بيطابق المرسل ده؟
  /// نفس منطق المطابقة المستخدم في [_assignWalletId] (substring في
  /// الاتجاهين) عشان القرارين يفضلوا متسقين مع بعض.
  bool _hasDynamicSmsSource(String sender) {
    final lower = sender.toLowerCase();
    return engine.walletSources.any((ws) {
      if (!ws.enabled || ws.sourceType != SourceType.sms) return false;
      final id = ws.identifier.toLowerCase();
      return lower.contains(id) || id.contains(lower);
    });
  }

  Future<void> _processSmsMessage({
    required String sender,
    required String normalizedBody,
    required SmsSourceMatch source,
    required bool isDynamicSource,
    required DateTime receivedAt,
  }) async {
    // I6 — Candidate Filter: AFTER reassembly, BEFORE parser
    final candidate = TransactionCandidateFilter.check(sender, normalizedBody);
    if (candidate.status == CandidateStatus.nonFinancial) {
      return; // رسالة OTP أو تنبيه أمني أو معلوماتية — نتجاهلها تمامًا
    }
    if (candidate.status == CandidateStatus.uncertain) {
      // نروّح للـ Review مباشرة بدون parser — لا ننشئ event غلط
      final uncertainEvent = FinancialEvent(
        id: generateEventId(),
        source: SourcePolicy.legacyFinancialSourceFor(source),
        eventType: FinancialEventType.unknown,
        amount: null,
        confidence: 20, // أقل من 85 → تروح للـ Review
        timestamp: receivedAt,
        rawMessage: normalizedBody,
        rawSource: sender,
      );
      await engine.ingest(_assignWalletId(uncertainEvent, sender));
      return;
    }
    // candidate.status == financial → المسار الطبيعي
    // C3: Rules FIRST — AI فقط لو الثقة منخفضة
    final ruleResult = SmsParser.parse(
      sender,
      normalizedBody,
      receivedAt: receivedAt,
      isDynamicallyRegistered: isDynamicSource,
    );
    final ruleEvent = ruleResult.event;

    // Rule Engine بثقة عالية → Apply مباشرة بدون AI (Cost + Privacy protection)
    if (ruleEvent != null && ruleEvent.confidence >= 85) {
      await engine.ingest(_assignWalletId(ruleEvent, sender));
      return;
    }

    // Rule Engine بثقة منخفضة → نجرب AI (لو مفعّل ومتاح)
    final aiResult = await _tryAiBackend(
      normalizedBody,
      sender,
      isSms: true,
      resolvedSource: SourcePolicy.legacyFinancialSourceFor(source),
    );
    if (aiResult != null) {
      await engine.ingest(_assignWalletId(aiResult, sender));
      return;
    }

    // AI مش متاح أو فشل → نستخدم rule result كما هو (قد يروح للـ Review)
    if (ruleEvent != null) {
      await engine.ingest(_assignWalletId(ruleEvent, sender));
    }
    // لو مفيش rule result ومفيش AI → الحدث يضيع بأمان (مش هنسجل حاجة غلط)
  }

  Future<void> ingestNotification(
    String packageName,
    String title,
    String text, {
    DateTime? receivedAt,
  }) async {
    if (!SourcePolicy.isInstaPayAppNotification(packageName)) return;

    final normalized = TextNormalizer.prepare('$title $text');

    // C1 — نفس منطق الـ reassembly للإشعارات
    final assembled = _reassembler.addNotificationFragment(
      packageName: packageName,
      normalizedCombinedText: normalized,
      receivedAt: receivedAt ?? DateTime.now(),
    );
    for (final msg in assembled) {
      await _processNotificationMessage(
        packageName: packageName,
        title: title,
        normalizedText: msg.text,
        receivedAt: msg.timestamp,
      );
    }
  }

  Future<void> _processNotificationMessage({
    required String packageName,
    required String title,
    required String normalizedText,
    required DateTime receivedAt,
  }) async {
    // C3: Rules FIRST
    final ruleEvent = NotificationParser.analyze(
      packageName, title, normalizedText, receivedAt: receivedAt);

    if (ruleEvent != null && ruleEvent.confidence >= 85) {
      await engine.ingest(_assignWalletId(ruleEvent, packageName));
      return;
    }

    final aiResult = await _tryAiBackend(
      normalizedText,
      packageName,
      isSms: false,
      resolvedSource: FinancialSource.instaPay,
    );
    if (aiResult != null) {
      await engine.ingest(_assignWalletId(aiResult, packageName));
      return;
    }

    if (ruleEvent != null) {
      await engine.ingest(_assignWalletId(ruleEvent, packageName));
    }
  }

  /// C3: يحاول استدعاء AI backend — يرجع FinancialEvent أو null لو فشل.
  /// يُستدعى فقط لو Rule Engine أنتج ثقة منخفضة (< 85).
  ///
  /// [resolvedSource]: المصدر الفعلي اللي تحدد بالفعل من [SourcePolicy]
  /// (أو instaPay للإشعارات) — بنستقبله جاهز من المستدعي بدل ما نخمّنه
  /// هنا من نص الـ sender نفسه (كان فيه قبل كده تخمين بـ .contains('vf')
  /// كان بيحط أي مرسل مش شايف فيه "vf"/"vodafone" على إنه البنك الأهلي
  /// غلط، حتى لو كان مصدر ديناميكي تالت تمامًا).
  Future<FinancialEvent?> _tryAiBackend(
    String normalizedText,
    String sender, {
    required bool isSms,
    required FinancialSource resolvedSource,
  }) async {
    final enabled = await aiSettings.loadEnabled();
    if (!enabled) return null;

    final aiResult = await _aiClient.analyze(
      source: sender,
      text: normalizedText,
      isSms: isSms,
    );
    if (aiResult == null) return null;
    if (!aiResult.isFinancial) return null;
    if (aiResult.direction == null) return null;

    final confidenceInt = (aiResult.confidence * 100).round().clamp(0, 100);

    return FinancialEvent(
      id: generateEventId(),
      source: resolvedSource,
      eventType: aiResult.direction!,
      amount: aiResult.amount,
      confidence: confidenceInt,
      timestamp: DateTime.now(),
      rawMessage: normalizedText,
      rawSource: 'ai_backend:$sender',
    );
  }

  /// I1: يحدد walletId المناسب للـ event بناءً على المصدر الفعلي + ربط المستخدم.
  FinancialEvent _assignWalletId(FinancialEvent event, String rawIdentifier) {
    if (event.walletId != null) return event;

    try {
      final ws = engine.walletSources.firstWhere(
        (ws) {
          if (!ws.enabled) return false;
          final lower = rawIdentifier.toLowerCase();
          final id = ws.identifier.toLowerCase();
          return lower.contains(id) || id.contains(lower);
        },
      );
      return FinancialEvent(
        id: event.id,
        source: event.source,
        eventType: event.eventType,
        amount: event.amount,
        currency: event.currency,
        balanceAfter: event.balanceAfter,
        merchant: event.merchant,
        person: event.person,
        reference: event.reference,
        timestamp: event.timestamp,
        confidence: event.confidence,
        rawMessage: event.rawMessage,
        rawSource: event.rawSource,
        metadata: event.metadata,
        category: event.category,
        walletId: ws.walletId,
        linkedEventId: event.linkedEventId,
      );
    } catch (_) {
      return event;
    }
  }
}
