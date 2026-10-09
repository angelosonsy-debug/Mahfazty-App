import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/financial_event.dart';
import '../../financial_engine/parser/sms_parser.dart';
import '../../financial_engine/parser/transaction_candidate_filter.dart';
import '../../financial_engine/policy/source_catalog.dart';

/// I8 — شاشة اختبار المصدر.
///
/// Parsing Preview فقط — لا ينشئ FinancialEvent ولا يغير الرصيد.
/// الشاشة تشرح للمستخدم كيف فُسِّرت الرسالة وبأي منطق.
class SourceTestScreen extends StatefulWidget {
  final FinancialEngine engine;
  final String? initialSender;

  const SourceTestScreen({
    super.key,
    required this.engine,
    this.initialSender,
  });

  @override
  State<SourceTestScreen> createState() => _SourceTestScreenState();
}

class _SourceTestScreenState extends State<SourceTestScreen> {
  final _msgCtrl = TextEditingController();
  final _senderCtrl = TextEditingController();

  _PreviewResult? _result;

  // أمثلة مدمجة لاختبار سريع
  static const _examples = [
    (
      label: 'بنك أهلي — خصم',
      sender: 'AhlyBank',
      msg: 'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 720.00 جم '
          'إلى مينا ع*** رقم مرجعي 400492200244 يوم 08-28 الساعة 00:02 '
          'للمزيد اتصل بـ 19623',
    ),
    (
      label: 'Vodafone Cash — استلام',
      sender: 'VF-Cash',
      msg: 'تم استلام مبلغ 500 جنيه من رقم 01099999999 '
          'رصيدك الحالي: 1500 جنيه رقم العملية: 7788990011',
    ),
    (
      label: 'OTP (مش مالية)',
      sender: 'BankMsg',
      msg: 'رمز التحقق الخاص بك هو 123456 صالح لمدة 5 دقائق',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _senderCtrl.text = widget.initialSender ?? '';
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _senderCtrl.dispose();
    super.dispose();
  }

  void _runTest() {
    final sender = _senderCtrl.text.trim();
    final msg    = _msgCtrl.text.trim();
    if (msg.isEmpty) return;

    // 1. Candidate filter
    final candidate = TransactionCandidateFilter.check(sender, msg);

    if (candidate.status == CandidateStatus.nonFinancial) {
      setState(() {
        _result = _PreviewResult.nonFinancial(candidate.reason);
      });
      return;
    }

    // 2. Source catalog check
    final sourceDef = findSourceDefinition(sender);

    // 3. Parse (preview only — لا يُضاف لـ engine)
    final parsed = SmsParser.parse(sender, msg);
    final event  = parsed.event;

    // 4. Wallet mapping
    String? walletName;
    String? walletConflictMsg;
    if (sourceDef != null) {
      final sourceWalletId = legacySourceToWalletId(sourceDef.legacySource);
      final matchingSources = widget.engine.walletSources
          .where((ws) => ws.walletId == sourceWalletId ||
              ws.identifier.toLowerCase() == sender.toLowerCase())
          .toList();

      if (matchingSources.length > 1) {
        walletConflictMsg =
            'هذا المصدر مرتبط بأكثر من محفظة (${matchingSources.map((s) => s.displayName).join("، ")})';
      } else if (matchingSources.isEmpty) {
        walletConflictMsg = 'المصدر معروف، لكن غير مربوط بمحفظة';
      } else {
        final wallet = widget.engine.wallets
            .where((w) => w.id == matchingSources.first.walletId)
            .firstOrNull;
        walletName = wallet?.name ?? matchingSources.first.displayName;
      }
    }

    setState(() {
      _result = _PreviewResult.parsed(
        sourceName: sourceDef?.displayName ?? 'غير معروف',
        eventType: event?.eventType,
        amount: event?.amount,
        confidence: event?.confidence ?? 0,
        walletName: walletName,
        walletConflict: walletConflictMsg,
        candidateReason: candidate.reason,
        parsedExplanation: parsed.explanation,
        isUnknown: event == null || event.eventType == FinancialEventType.unknown,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اختبار المصدر')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'معاينة فقط — لن يتم إنشاء أي معاملة أو تغيير الرصيد.',
                      style: TextStyle(color: Colors.blue, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Sender
            TextField(
              controller: _senderCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'المرسل (sender / package)',
                hintText: 'مثال: VF-Cash أو AhlyBank',
              ),
            ),
            const SizedBox(height: 12),

            // Message input
            TextField(
              controller: _msgCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'نص الرسالة',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),

            // Examples
            Wrap(
              spacing: 6,
              children: _examples.map((ex) {
                return ActionChip(
                  label: Text(ex.label, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _senderCtrl.text = ex.sender;
                    _msgCtrl.text = ex.msg;
                    _runTest();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _runTest,
              icon: const Icon(Icons.play_arrow),
              label: const Text('تحليل'),
            ),
            const SizedBox(height: 20),

            if (_result != null) _ResultCard(result: _result!),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------
class _PreviewResult {
  final bool isNonFinancial;
  final String? nonFinancialReason;
  final String? sourceName;
  final FinancialEventType? eventType;
  final double? amount;
  final int confidence;
  final String? walletName;
  final String? walletConflict;
  final String? candidateReason;
  final String? parsedExplanation;
  final bool isUnknown;

  const _PreviewResult._({
    required this.isNonFinancial,
    this.nonFinancialReason,
    this.sourceName,
    this.eventType,
    this.amount,
    this.confidence = 0,
    this.walletName,
    this.walletConflict,
    this.candidateReason,
    this.parsedExplanation,
    this.isUnknown = false,
  });

  factory _PreviewResult.nonFinancial(String reason) =>
      _PreviewResult._(isNonFinancial: true, nonFinancialReason: reason);

  factory _PreviewResult.parsed({
    required String sourceName,
    required FinancialEventType? eventType,
    required double? amount,
    required int confidence,
    required String? walletName,
    required String? walletConflict,
    required String candidateReason,
    required String? parsedExplanation,
    required bool isUnknown,
  }) =>
      _PreviewResult._(
        isNonFinancial: false,
        sourceName: sourceName,
        eventType: eventType,
        amount: amount,
        confidence: confidence,
        walletName: walletName,
        walletConflict: walletConflict,
        candidateReason: candidateReason,
        parsedExplanation: parsedExplanation,
        isUnknown: isUnknown,
      );
}

class _ResultCard extends StatelessWidget {
  final _PreviewResult result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.isNonFinancial) {
      return _infoCard(
        Icons.block,
        Colors.orange,
        'رسالة غير مالية',
        result.nonFinancialReason ?? '',
      );
    }

    if (result.isUnknown) {
      return _infoCard(
        Icons.help_outline,
        Colors.grey,
        'لم نتمكن من تحديد العملية',
        'لم نتمكن من تحديد نوع العملية أو المبلغ بثقة كافية.\n'
            'لن يتم تسجيل أي معاملة.',
      );
    }

    final conf = result.confidence;
    final confColor = conf >= 85
        ? Colors.green
        : conf >= 50
            ? Colors.orange
            : Colors.red;
    final confLabel =
        conf >= 85 ? 'عالية ($conf%)' : conf >= 50 ? 'متوسطة ($conf%)' : 'منخفضة ($conf%)';

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('المصدر', result.sourceName ?? '—'),
          _row('نوع العملية', result.eventType?.labelAr ?? '—'),
          _row(
            'المبلغ',
            result.amount != null
                ? '${result.amount!.toStringAsFixed(2)} جنيه'
                : '—',
          ),
          Row(
            children: [
              const Text('الثقة: ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(confLabel,
                    style: TextStyle(
                        color: confColor, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Wallet mapping
          if (result.walletConflict != null)
            _alertRow(Icons.warning_amber, Colors.orange, result.walletConflict!)
          else if (result.walletName != null)
            _row('المحفظة', result.walletName!),

          const Divider(height: 20),

          // Explainability
          const Text('لماذا هذا التفسير؟',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            result.parsedExplanation ??
                result.candidateReason ??
                'تم التعرف على الرسالة من السياق العام.',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _alertRow(IconData icon, Color color, String msg) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
                child: Text(msg, style: TextStyle(color: color, fontSize: 13))),
          ],
        ),
      );

  Widget _infoCard(IconData icon, Color color, String title, String body) =>
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.05),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
}
