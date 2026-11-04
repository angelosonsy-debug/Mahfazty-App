import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';

/// Pocket = كاش فعلي بس. يدوي بالكامل، أبدًا مش بيتحدث تلقائي.
/// التعديل هنا لازم يكون أسرع حاجة في التطبيق - Bottom Sheet واحد بس،
/// مبلغ سريع أو مبلغ مخصص، وخلاص.
class PocketScreen extends StatelessWidget {
  final FinancialEngine engine;
  const PocketScreen({super.key, required this.engine});

  Future<void> _openQuickAdjustSheet(BuildContext context) async {
    bool isAdd = true;
    final controller = TextEditingController();
    final noteController = TextEditingController();
    const quickAmounts = [50.0, 100.0, 200.0, 500.0];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('إضافة'), icon: Icon(Icons.add)),
                  ButtonSegment(value: false, label: Text('خصم'), icon: Icon(Icons.remove)),
                ],
                selected: {isAdd},
                onSelectionChanged: (s) => setState(() => isAdd = s.first),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final amount in quickAmounts)
                    ActionChip(
                      label: Text('${amount.toStringAsFixed(0)} جنيه'),
                      onPressed: () async {
                        Navigator.pop(context);
                        await engine.addPocketAdjustment(isAdd ? amount : -amount);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'مبلغ مخصص', suffixText: 'جنيه'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final amount = double.tryParse(controller.text);
                  if (amount == null || amount <= 0) return;
                  Navigator.pop(context);
                  await engine.addPocketAdjustment(
                    isAdd ? amount : -amount,
                    note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                  );
                },
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// تصحيح الرصيد الكلي — منفصل تمامًا عن "تعديل سريع" (اللي بيسجّل
  /// delta كعملية عادية في السجل). ده لحالة استثنائية بس: الرصيد المعروض
  /// مش مطابق للكاش الفعلي (مثلاً بعد إعادة تثبيت، أو غلطة تراكمت).
  /// نفس شكل "تصحيح الرصيد" في شاشة المحافظ بالظبط عشان الاتساق البصري.
  void _showAbsoluteCorrectionDialog(BuildContext context) {
    final ctrl = TextEditingController(text: engine.pocketBalance.toStringAsFixed(2));
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصحيح الرصيد الكلي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'استخدم هذا فقط لو الرصيد المعروض مش مطابق للكاش الفعلي معاك. '
                'هيتسجّل في السجل كـ "ضبط يدوي للرصيد" بالفرق، مش كعملية عادية.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'الرصيد الفعلي (جنيه)'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null) engine.setPocketBalanceAbsolute(v);
              Navigator.pop(ctx);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الكاش (Pocket)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('الرصيد الحالي', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Text(
                    '${engine.pocketBalance.toStringAsFixed(2)} جنيه',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openQuickAdjustSheet(context),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل سريع'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showAbsoluteCorrectionDialog(context),
                  icon: const Icon(Icons.price_change_outlined),
                  label: const Text('تصحيح الرصيد'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('السجل', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (engine.pocketHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('مفيش تعديلات لسه'),
            )
          else
            for (final h in engine.pocketHistory)
              Builder(builder: (context) {
                final t = DateTime.fromMillisecondsSinceEpoch(h.timestamp);
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      h.delta >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      color: h.delta >= 0 ? Colors.green : Colors.red,
                    ),
                    title: Text('${h.delta >= 0 ? '+' : ''}${h.delta.toStringAsFixed(2)} جنيه'),
                    subtitle: h.note != null ? Text(h.note!) : null,
                    trailing: Text(
                      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                );
              }),
        ],
      ),
    );
  }
}
