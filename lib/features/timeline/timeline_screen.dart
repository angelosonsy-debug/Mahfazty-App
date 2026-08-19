import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/financial_event.dart';

/// تايم لاين لكل حدث مالي (تلقائي أو يدوي) - ودلوقتي فيه فعليًا إجراءات
/// المراجعة (تأكيد/تعديل/تجاهل) بدل ما يكون للعرض بس.
class TimelineScreen extends StatelessWidget {
  final FinancialEngine engine;
  const TimelineScreen({super.key, required this.engine});

  IconData _iconFor(FinancialEvent e) {
    switch (e.eventType) {
      case FinancialEventType.deposit:
        return Icons.arrow_downward;
      case FinancialEventType.withdrawal:
        return Icons.arrow_upward;
      case FinancialEventType.transfer:
        return Icons.swap_horiz;
      case FinancialEventType.purchase:
        return Icons.shopping_bag_outlined;
      case FinancialEventType.refund:
        return Icons.replay;
      case FinancialEventType.manualAdjustment:
        return Icons.edit_outlined;
      case FinancialEventType.debtCreated:
      case FinancialEventType.debtPaid:
        return Icons.handshake_outlined;
      case FinancialEventType.pocketAdjustment:
        return Icons.account_balance_wallet_outlined;
      case FinancialEventType.unknown:
        return Icons.help_outline;
    }
  }

  Future<void> _reviewEvent(BuildContext context, FinancialEvent e) async {
    final amountController = TextEditingController(text: e.amount?.toStringAsFixed(2) ?? '');
    final balanceController = TextEditingController(text: e.balanceAfter?.toStringAsFixed(2) ?? '');
    FinancialEventType selectedType = e.eventType;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('مراجعة المعاملة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    e.rawMessage,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('نوع العملية', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<FinancialEventType>(
                  isExpanded: true,
                  value: selectedType,
                  items: FinancialEventType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.labelAr)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => selectedType = v);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'المبلغ', suffixText: 'جنيه'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: balanceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'الرصيد بعد العملية (لو معروف - اختياري)',
                    suffixText: 'جنيه',
                  ),
                ),
                if (selectedType == FinancialEventType.unknown)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'لو سبتها "غير معروف" هتفضل من غير أثر على رصيد المحفظة '
                      'حتى لو حطيت مبلغ - لازم تحدد إيداع/سحب/تحويل/شراء.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await engine.updateEventManually(
        e.id,
        amount: double.tryParse(amountController.text),
        balanceAfter: double.tryParse(balanceController.text),
        eventType: selectedType,
      );
    }
  }

  Future<void> _confirmDismiss(BuildContext context, FinancialEvent e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تجاهل المعاملة؟'),
        content: const Text('هتحذفها نهائيًا ومش هيكون ليها أي أثر على أي رصيد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('تجاهل')),
        ],
      ),
    );
    if (confirmed == true) {
      await engine.deleteEvent(e.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (engine.events.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('مفيش أحداث اتسجلت لسه.', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: engine.events.length,
      itemBuilder: (context, index) {
        final e = engine.events[index];
        final needsReview = e.confidence < 85;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: needsReview ? Theme.of(context).colorScheme.surfaceVariant : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(_iconFor(e), size: 20)),
                  title: Text('${e.source.labelAr} - ${e.eventType.labelAr}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (e.amount != null) Text('${e.amount!.toStringAsFixed(2)} جنيه'),
                      if (e.person != null) Text('مع: ${e.person}'),
                      if (e.merchant != null) Text('عند: ${e.merchant}'),
                      Text(
                        e.rawMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  trailing: Text(
                    '${e.timestamp.day}/${e.timestamp.month}\n'
                    '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  isThreeLine: true,
                ),
                if (needsReview)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _confirmDismiss(context, e),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('تجاهل'),
                      ),
                      TextButton.icon(
                        onPressed: () => _reviewEvent(context, e),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('تعديل'),
                      ),
                      if (e.amount != null)
                        FilledButton.icon(
                          onPressed: () => engine.confirmEvent(e.id),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('صحيح'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
