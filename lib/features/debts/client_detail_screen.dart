import 'package:flutter/material.dart';
import '../../core/utils/money_format.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/client.dart';
import '../../financial_engine/models/wallet.dart';

/// تفاصيل عميل واحد - كل معاملاته، وكام دائن/مدين/الصافي بوضوح.
class ClientDetailScreen extends StatelessWidget {
  final FinancialEngine engine;
  final Client client;
  const ClientDetailScreen({super.key, required this.engine, required this.client});

  Future<void> _addTransaction(BuildContext context) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    DebtEntryDirection direction = DebtEntryDirection.theyOweUs;
    DateTime? selectedDueDate;

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
              const SizedBox(height: 12),
              StatefulBuilder(builder: (ctx2, setSt2) {
                return _DueDatePicker(
                  initialDate: null,
                  onChanged: (d) => selectedDueDate = d,
                );
              }),
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
                    id: generateDebtId(),
                    clientId: client.id,
                    direction: direction,
                    amount: amount,
                    timestamp: DateTime.now(),
                    note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                    dueDate: selectedDueDate,
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
    DateTime? editedDueDate = t.dueDate;
    bool clearDue = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
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
              const SizedBox(height: 12),
              _DueDatePicker(
                initialDate: editedDueDate,
                onChanged: (d) { editedDueDate = d; clearDue = (d == null); },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await engine.updateDebtTransaction(
        t.id,
        amount: double.tryParse(amountController.text),
        note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
        dueDate: editedDueDate,
        clearDueDate: clearDue,
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
          _PaySuggestionCard(engine: engine, client: client),
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
                    title: Text('${formatMoney(t.amount)} جنيه'),
                    subtitle: Text(
                      '${t.direction == DebtEntryDirection.theyOweUs ? "دائن (ليا)" : "مدين (عليّ)"}'
                      '${t.note != null ? " - ${t.note}" : ""}\n'
                      '${t.timestamp.day}/${t.timestamp.month}/${t.timestamp.year}'
                      '${t.dueDate != null ? "  📅 ${t.dueDate!.day}/${t.dueDate!.month}/${t.dueDate!.year}" : ""}',
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
          formatMoney(value),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color),
        ),
      ],
    );
  }
}

// ─── اقتراح سداد الدين من محفظة ───────────────────────────────────────────
class _PaySuggestionCard extends StatelessWidget {
  final FinancialEngine engine;
  final Client client;
  const _PaySuggestionCard({required this.engine, required this.client});

  @override
  Widget build(BuildContext context) {
    final owed = engine.owedByMeTo(client.id);
    if (owed < 0.01) return const SizedBox.shrink();

    // أول محفظة فيها رصيد كافي
    Wallet? suggWallet;
    for (final w in engine.wallets.where((w) => !w.archived)) {
      final bal = engine.balanceForWallet(w.id);
      if (bal != null && bal >= owed) { suggWallet = w; break; }
    }
    if (suggWallet == null) return const SizedBox.shrink();

    final wName = suggWallet.name;
    final wId = suggWallet.id;

    return Card(
      color: const Color(0xFFE8F5E9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('عندك ${formatMoney(engine.balanceForWallet(wId) ?? 0)} جنيه في $wName — تحب تسدد الدين منها؟',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded),
              label: const Text('سداد'),
              onPressed: () => _confirmPay(context, wId, wName, owed),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmPay(
    BuildContext context,
    String walletId,
    String walletName,
    double amount,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد السداد'),
        content: Text(
          'سيتم خصم ${formatMoney(amount)} جنيه من $walletName وتسجيل سداد الدين لـ ${client.name}.هل أنت متأكد؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await engine.payDebtFromWallet(
        clientId: client.id,
        walletId: walletId,
        amount: amount,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تسجيل السداد بنجاح')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
      }
    }
  }
}

// ─── اختيار تاريخ الاستحقاق ────────────────────────────────────────────────
class _DueDatePicker extends StatefulWidget {
  final DateTime? initialDate;
  final ValueChanged<DateTime?> onChanged;
  const _DueDatePicker({required this.initialDate, required this.onChanged});
  @override
  State<_DueDatePicker> createState() => _DueDatePickerState();
}

class _DueDatePickerState extends State<_DueDatePicker> {
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.calendar_today_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _date == null
                ? 'تاريخ الاستحقاق (اختياري)'
                : 'الاستحقاق: ${_date!.day}/${_date!.month}/${_date!.year}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (_date != null)
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            onPressed: () { setState(() => _date = null); widget.onChanged(null); },
          ),
        TextButton(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date ?? DateTime.now().add(const Duration(days: 30)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
            );
            if (picked != null) { setState(() => _date = picked); widget.onChanged(picked); }
          },
          child: Text(_date == null ? 'اختر تاريخ' : 'تغيير'),
        ),
      ],
    );
  }
}
