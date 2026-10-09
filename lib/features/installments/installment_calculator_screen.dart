import 'package:flutter/material.dart';

import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/client.dart';
import 'installment_math.dart';
import '../../core/utils/money_format.dart';


class InstallmentCalculatorScreen extends StatefulWidget {
  final FinancialEngine engine;
  const InstallmentCalculatorScreen({super.key, required this.engine});

  @override
  State<InstallmentCalculatorScreen> createState() => _State();
}

class _State extends State<InstallmentCalculatorScreen> {
  final _totalCtrl = TextEditingController();
  final _downCtrl = TextEditingController();
  final _monthsCtrl = TextEditingController(text: '12');
  final _rateCtrl = TextEditingController(text: '0');

  InstallmentPlan? _plan;
  String? _error;

  void _calculate() {
    final total = double.tryParse(_totalCtrl.text.replaceAll(',', ''));
    final down = double.tryParse(_downCtrl.text.replaceAll(',', '')) ?? 0;
    final months = int.tryParse(_monthsCtrl.text) ?? 0;
    final rate = double.tryParse(_rateCtrl.text) ?? 0;

    final plan = calculateInstallment(
      total: total ?? 0,
      downPayment: down,
      months: months,
      annualRatePercent: rate,
    );

    setState(() {
      _plan = plan;
      _error = plan == null ? 'تحقق من المدخلات: المبلغ موجب، المقدّم أقل من الإجمالي، الشهور 1-120' : null;
    });
  }

  Future<void> _convertToDebt() async {
    final plan = _plan;
    if (plan == null) return;

    // اختيار أو إنشاء عميل
    String? selectedClientId;
    final nameCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sst) => AlertDialog(
          title: const Text('تحويل لدين متابع'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.engine.clients.isNotEmpty) ...[
                const Text('اختر عميلاً موجوداً:'),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text('— اختر —'),
                  value: selectedClientId,
                  items: widget.engine.clients
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => sst(() => selectedClientId = v),
                ),
                const Divider(height: 24),
                const Text('أو أضف عميلاً جديداً:'),
                const SizedBox(height: 8),
              ] else
                const Text('أضف اسم العميل/الجهة:'),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final engine = widget.engine;
                String clientId;
                if (nameCtrl.text.trim().isNotEmpty) {
                  final client = Client(
                    id: generateClientId(),
                    name: nameCtrl.text.trim(),
                    createdAt: DateTime.now(),
                    notes: 'قسط: ${_monthsCtrl.text} شهر × ${formatMoney(plan.monthlyPayment)} ج.م',
                  );
                  await engine.addClient(client);
                  clientId = client.id;
                } else if (selectedClientId != null) {
                  clientId = selectedClientId!;
                } else {
                  return;
                }
                final now = DateTime.now();
                for (var i = 1; i <= int.parse(_monthsCtrl.text); i++) {
                  await engine.addDebtTransaction(DebtTransaction(
                    id: generateDebtId(),
                    clientId: clientId,
                    direction: DebtEntryDirection.weOweThem,
                    amount: plan.monthlyPayment,
                    timestamp: now,
                    note: 'قسط $i من ${_monthsCtrl.text}',
                    dueDate: installmentDueDate(now, i),
                  ));
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم تسجيل ${_monthsCtrl.text} قسط في ملف العميل')),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _totalCtrl.dispose(); _downCtrl.dispose();
    _monthsCtrl.dispose(); _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('حاسبة الأقساط')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            color: Color(0xFFFFF8E1),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'ملاحظة: الحساب تقديري باستخدام الفائدة الثابتة (Flat Rate). يختلف عن '
                'طريقة البنوك وشركات التقسيط — استخدمه للمقارنة فقط.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _field(_totalCtrl, 'المبلغ الكلي', 'جنيه'),
          const SizedBox(height: 12),
          _field(_downCtrl, 'المقدّم (اختياري)', 'جنيه'),
          const SizedBox(height: 12),
          _field(_monthsCtrl, 'عدد الشهور', 'شهر', isInt: true),
          const SizedBox(height: 12),
          _field(_rateCtrl, 'نسبة الفائدة السنوية (اختياري)', '%'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _calculate,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('احسب'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (plan != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _resultRow('القسط الشهري', '${formatMoney(plan.monthlyPayment)} ج.م',
                        large: true),
                    const Divider(height: 24),
                    _resultRow('الفائدة الكلية', '${formatMoney(plan.totalInterest)} ج.م'),
                    const SizedBox(height: 8),
                    _resultRow('إجمالي المدفوع', '${formatMoney(plan.totalPaid)} ج.م'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _convertToDebt,
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('تحويل لدين متابع'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String suffix,
      {bool isInt = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isInt
          ? TextInputType.number
          : const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        suffixText: suffix,
      ),
    );
  }

  Widget _resultRow(String label, String value, {bool large = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: large ? FontWeight.bold : null)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: large ? 22 : 16,
            color: large ? const Color(0xFF1A6E5E) : null,
          ),
        ),
      ],
    );
  }
}
