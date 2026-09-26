import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/wallet.dart';
import '../../financial_engine/models/wallet_source.dart';
import '../../financial_engine/parser/sms_parser.dart';

/// I1 — Wizard إضافة/تعديل محفظة (3 خطوات + اختبار المصدر).
///
/// الخطوات:
///   1. الاسم
///   2. النوع (WalletType)
///   3. المصدر (SourceType + identifier)
///   [اختياري] اختبار المصدر — Parsing Preview لا ينشئ Transaction
class WalletWizard extends StatefulWidget {
  final FinancialEngine engine;
  final Wallet? existing; // null = وضع الإنشاء، غير null = وضع التعديل

  const WalletWizard({super.key, required this.engine, this.existing});

  @override
  State<WalletWizard> createState() => _WalletWizardState();
}

class _WalletWizardState extends State<WalletWizard> {
  final _pageCtrl = PageController();
  int _page = 0;

  // Step 1
  final _nameCtrl = TextEditingController();

  // Step 2
  WalletType _type = WalletType.bankAccount;

  // Step 3
  SourceType _sourceType = SourceType.sms;
  final _identifierCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  bool _manualOnly = false;

  // Source test (I8)
  final _testMsgCtrl = TextEditingController();
  _ParsePreview? _preview;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!.name;
      _type = widget.existing!.type;
      // تحميل أول source مرتبط بالمحفظة
      final sources = widget.engine.sourcesForWallet(widget.existing!.id);
      if (sources.isNotEmpty) {
        _sourceType = sources.first.sourceType;
        _identifierCtrl.text = sources.first.identifier;
        _displayNameCtrl.text = sources.first.displayName;
      }
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _identifierCtrl.dispose();
    _displayNameCtrl.dispose();
    _testMsgCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 2) { _save(); return; }
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _page++);
  }

  void _back() {
    if (_page == 0) { Navigator.pop(context); return; }
    _pageCtrl.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _page--);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب إدخال اسم المحفظة')),
      );
      return;
    }

    final engine = widget.engine;
    final isEdit = widget.existing != null;

    // إنشاء أو تعديل المحفظة
    final wallet = Wallet(
      id: isEdit ? widget.existing!.id : generateWalletId(),
      name: name,
      type: _type,
      createdAt: isEdit ? widget.existing!.createdAt : DateTime.now(),
    );

    if (isEdit) {
      await engine.updateWallet(wallet);
    } else {
      await engine.addWallet(wallet);
    }

    // إضافة/تحديث المصدر (لو مش manual-only)
    if (!_manualOnly && _identifierCtrl.text.trim().isNotEmpty) {
      final identifier = _identifierCtrl.text.trim();

      // تحقق من تعارض المصدر
      final conflict = engine.findConflictingSource(identifier, wallet.id);
      if (conflict != null && mounted) {
        final confirmed = await _showConflictDialog(conflict);
        if (!confirmed) return;
      }

      final displayName = _displayNameCtrl.text.trim().isEmpty
          ? '$name (${_sourceType.labelAr})'
          : _displayNameCtrl.text.trim();

      final existingSources = engine.sourcesForWallet(wallet.id);
      if (existingSources.isEmpty) {
        await engine.addWalletSource(WalletSource(
          id: generateWalletSourceId(),
          walletId: wallet.id,
          sourceType: _sourceType,
          identifier: identifier,
          displayName: displayName,
        ));
      } else {
        // تحديث أول source موجود
        final updated = existingSources.first.copyWith(
          displayName: displayName,
        );
        await engine.updateWalletSource(updated);
      }
    }

    if (mounted) Navigator.pop(context);
  }

  Future<bool> _showConflictDialog(WalletSource conflict) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تعارض في المصدر'),
            content: Text(
              'المعرّف «${conflict.identifier}» مرتبط بالفعل '
              'بمحفظة أخرى (${conflict.displayName}).\n\n'
              'هل تريد نقله لهذه المحفظة؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('نقل'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _runTest() {
    final msg = _testMsgCtrl.text.trim();
    final sender = _identifierCtrl.text.trim().isEmpty
        ? 'VF-Cash'
        : _identifierCtrl.text.trim();
    if (msg.isEmpty) return;

    // Parsing Preview فقط — لا يُنشئ Transaction
    final result = SmsParser.parse(sender, msg);
    setState(() {
      if (result.event != null) {
        _preview = _ParsePreview(
          source: sender,
          direction: result.event!.eventType.name,
          amount: result.event!.amount?.toStringAsFixed(2) ?? '—',
          confidence: result.event!.confidence.toString(),
        );
      } else {
        _preview = const _ParsePreview(
          source: '—',
          direction: 'غير معروف',
          amount: '—',
          confidence: '0',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'إضافة محفظة' : 'تعديل المحفظة'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          LinearProgressIndicator(value: (_page + 1) / 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text('الخطوة ${_page + 1} من 3',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Spacer(),
                Text(
                  ['الاسم', 'النوع', 'المصدر'][_page],
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [_step1(), _step2(), _step3()],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Step 1: الاسم
  Widget _step1() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ما اسم هذه المحفظة؟',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('مثل: Vodafone Cash، البنك الأهلي، فلوسي',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'اسم المحفظة',
              hintText: 'مثال: Vodafone Cash',
            ),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _next(),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Step 2: النوع
  Widget _step2() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ما نوع هذه المحفظة؟',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: WalletType.values.map((t) {
              final selected = _type == t;
              return ChoiceChip(
                label: Text(t.labelAr),
                selected: selected,
                onSelected: (_) => setState(() => _type = t),
                selectedColor:
                    Theme.of(context).colorScheme.primaryContainer,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Step 3: المصدر
  Widget _step3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('من أين أقرأ عمليات هذه المحفظة؟',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'التطبيق سيراقب المصدر الذي تختاره تلقائيًا.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Manual toggle
          SwitchListTile(
            title: const Text('إدخال يدوي فقط'),
            subtitle: const Text('بدون ربط رسائل أو إشعارات'),
            value: _manualOnly,
            onChanged: (v) => setState(() => _manualOnly = v),
          ),

          if (!_manualOnly) ...[
            const Divider(),
            const Text('نوع المصدر:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<SourceType>(
              segments: const [
                ButtonSegment(
                    value: SourceType.sms, label: Text('رسائل SMS')),
                ButtonSegment(
                    value: SourceType.notification,
                    label: Text('إشعارات')),
              ],
              selected: {_sourceType},
              onSelectionChanged: (s) =>
                  setState(() => _sourceType = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _identifierCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'معرّف المصدر (sender أو package name)',
                hintText: 'مثال: VF-Cash أو AhlyBank',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _displayNameCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'اسم العرض (اختياري)',
                hintText: 'مثال: Vodafone Cash SMS',
              ),
            ),
            const SizedBox(height: 20),

            // I8: اختبار المصدر — Parsing Preview فقط
            const Text('اختبار المصدر:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'أدخل مثالًا على رسالة لمعاينة التحليل — لن تُضاف كمعاملة.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _testMsgCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'نص رسالة للاختبار',
                hintText: 'الصق رسالة SMS مثلًا...',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _runTest,
              icon: const Icon(Icons.play_arrow),
              label: const Text('اختبار التحليل'),
            ),
            if (_preview != null) ...[
              const SizedBox(height: 12),
              _preview!,
            ],
          ],
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (_page > 0)
              OutlinedButton(
                onPressed: _back,
                child: const Text('رجوع'),
              ),
            const Spacer(),
            FilledButton(
              onPressed: _next,
              child: Text(_page == 2 ? 'حفظ' : 'التالي'),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------
class _ParsePreview extends StatelessWidget {
  final String source;
  final String direction;
  final String amount;
  final String confidence;

  const _ParsePreview({
    required this.source,
    required this.direction,
    required this.amount,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    final confInt = int.tryParse(confidence) ?? 0;
    final confColor = confInt >= 85
        ? Colors.green
        : confInt >= 50
            ? Colors.orange
            : Colors.red;
    final confLabel = confInt >= 85
        ? 'عالية'
        : confInt >= 50
            ? 'متوسطة'
            : 'منخفضة';

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade50,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('المصدر', source),
          _row('نوع العملية', direction),
          _row('المبلغ', '$amount جنيه'),
          Row(
            children: [
              const Text('الثقة: ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(confLabel,
                    style: TextStyle(
                        color: confColor, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }
}
