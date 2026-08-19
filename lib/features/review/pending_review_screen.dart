import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/financial_event.dart';

/// شاشة مراجعة واحدة تلو الأخرى - بدل ما المراجعة تكون متفرقة في الشاشة،
/// هنا معاملة واحدة بس، بأزرار واضحة: صحيح / تعديل / تجاهل. بعد أي إجراء
/// بتتنقل تلقائي للمعاملة اللي بعدها.
class PendingReviewScreen extends StatefulWidget {
  final FinancialEngine engine;
  const PendingReviewScreen({super.key, required this.engine});

  @override
  State<PendingReviewScreen> createState() => _PendingReviewScreenState();
}

class _PendingReviewScreenState extends State<PendingReviewScreen> {
  late final TextEditingController _amountController;
  late final TextEditingController _balanceController;
  FinancialEventType? _selectedType;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _balanceController = TextEditingController();
    _loadCurrentIntoForm();
  }

  void _loadCurrentIntoForm() {
    final current = widget.engine.pendingReview.isNotEmpty ? widget.engine.pendingReview.first : null;
    _amountController.text = current?.amount?.toStringAsFixed(2) ?? '';
    _balanceController.text = current?.balanceAfter?.toStringAsFixed(2) ?? '';
    _selectedType = current?.eventType;
    _editing = false;
  }

  Future<void> _confirm(FinancialEvent e) async {
    await widget.engine.confirmEvent(e.id);
    setState(_loadCurrentIntoForm);
  }

  Future<void> _dismiss(FinancialEvent e) async {
    await widget.engine.deleteEvent(e.id);
    setState(_loadCurrentIntoForm);
  }

  Future<void> _saveEdit(FinancialEvent e) async {
    await widget.engine.updateEventManually(
      e.id,
      amount: double.tryParse(_amountController.text),
      balanceAfter: double.tryParse(_balanceController.text),
      eventType: _selectedType,
    );
    setState(_loadCurrentIntoForm);
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.engine.pendingReview;

    if (queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('مراجعة المعاملات')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('مفيش معاملات محتاجة مراجعة دلوقتي 🎉', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final current = queue.first;

    return Scaffold(
      appBar: AppBar(title: Text('مراجعة المعاملات (${queue.length} متبقي)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(current.source.labelAr, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(current.rawMessage),
                    ),
                    const SizedBox(height: 16),
                    if (!_editing) ...[
                      Text(
                        current.amount != null
                            ? '${current.amount!.toStringAsFixed(2)} جنيه'
                            : 'مفيش مبلغ مستخرج',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text('النوع المتوقع: ${current.eventType.labelAr}'),
                    ] else ...[
                      DropdownButton<FinancialEventType>(
                        isExpanded: true,
                        value: _selectedType,
                        items: FinancialEventType.values
                            .map((t) => DropdownMenuItem(value: t, child: Text(t.labelAr)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedType = v),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'المبلغ', suffixText: 'جنيه'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _balanceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'الرصيد بعد العملية (اختياري)',
                          suffixText: 'جنيه',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (!_editing)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _dismiss(current),
                      icon: const Icon(Icons.close),
                      label: const Text('تجاهل'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('تعديل'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: current.amount != null ? () => _confirm(current) : null,
                      icon: const Icon(Icons.check),
                      label: const Text('صحيح'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(_loadCurrentIntoForm),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _saveEdit(current),
                      child: const Text('حفظ'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
