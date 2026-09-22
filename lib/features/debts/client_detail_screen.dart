import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/client.dart';

/// تفاصيل عميل واحد - كل معاملاته، وكام دائن/مدين/الصافي بوضوح.
class ClientDetailScreen extends StatelessWidget {
  final FinancialEngine engine;
  final Client client;
  const ClientDetailScreen({super.key, required this.engine, required this.client});

  Future<void> _addTransaction(BuildContext context) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    DebtEntryDirection direction = DebtEntryDirection.theyOweUs;

    final transaction = await showDialog<DebtTransaction>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('إضافة معاملة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<DebtEntryDirection>(
                segments: const [
                  ButtonSegment(value: DebtEntryDirection.theyOweUs, label: Text('دائن (ليا)')),
                  ButtonSegment(value: DebtEntryDirection.weOweThem, label: Text('مدين (عليّ)')),
                ],
                selected: {direction},
                onSelectionChanged: (s) => setState(() => direction = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ', suffixText: 'جنيه'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) return;
                Navigator.pop(
                  context,
                  DebtTransaction(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    clientId: client.id,
                    direction: direction,
                    amount: amount,
                    timestamp: DateTime.now(),
                    note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                  ),
                );
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );

    if (transaction != null) {
      await engine.addDebtTransaction(transaction);
    }
  }

  Future<void> _editTransaction(BuildContext context, DebtTransaction t) async {
    final amountController = TextEditingController(text: t.amount.toStringAsFixed(2));
    final noteController = TextEditingController(text: t.note ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل المعاملة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ', suffixText: 'جنيه'),
            ),
            const SizedBox(height: 8),
            TextField(controller: noteController, decoration: const InputDecoration(labelText: 'ملاحظة')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );

    if (confirmed == true) {
      await engine.updateDebtTransaction(
        t.id,
        amount: double.tryParse(amountController.text),
        note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
      );
    }
  }

  Future<void> _deleteTransaction(BuildContext context, DebtTransaction t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المعاملة؟'),
        content: const Text('الإجراء ده مش قابل للتراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true) {
      await engine.deleteDebtTransaction(t.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theyOweUs = engine.theyOweUsTotal(client.id);
    final weOweThem = engine.weOweThemTotal(client.id);
    final net = theyOweUs - weOweThem;
    final transactions = engine.transactionsForClient(client.id);

    return Scaffold(
      appBar: AppBar(title: Text(client.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Stat(label: 'ليا عنده', value: theyOweUs, color: Colors.green),
                      _Stat(label: 'له عندي', value: weOweThem, color: Colors.red),
                    ],
                  ),
                  const Divider(height: 24),
                  Text(
                    net == 0
                        ? 'الحساب متسوّى'
                        : net > 0
                            ? '${client.name} مديون لينا ${net.toStringAsFixed(2)} جنيه'
                            : 'احنا مديونين لـ ${client.name} ${net.abs().toStringAsFixed(2)} جنيه',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: net == 0 ? null : (net > 0 ? Colors.green : Colors.red),
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('المعاملات', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('مفيش معاملات لسه'),
            )
          else
            for (final t in transactions)
              Dismissible(
                key: ValueKey(t.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: const Icon(Icons.delete_outline),
                ),
                confirmDismiss: (_) async {
                  await _deleteTransaction(context, t);
                  return false;
                },
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      t.direction == DebtEntryDirection.theyOweUs ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      color: t.direction == DebtEntryDirection.theyOweUs ? Colors.green : Colors.red,
                    ),
                    title: Text('${t.amount.toStringAsFixed(2)} جنيه'),
                    subtitle: Text(
                      '${t.direction == DebtEntryDirection.theyOweUs ? "دائن (ليا)" : "مدين (عليّ)"}'
                      '${t.note != null ? ' - ${t.note}' : ''}\n'
                      '${t.timestamp.day}/${t.timestamp.month}/${t.timestamp.year}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _editTransaction(context, t),
                    ),
                  ),
                ),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTransaction(context),
        icon: const Icon(Icons.add),
        label: const Text('معاملة جديدة'),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value.toStringAsFixed(2),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color),
        ),
      ],
    );
  }
}
