import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/wallet.dart';

/// I4 — شاشة التحويل بين المحافظ.
class TransferScreen extends StatefulWidget {
  final FinancialEngine engine;
  const TransferScreen({super.key, required this.engine});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  Wallet? _from;
  Wallet? _to;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _amountCtrl.dispose(); _noteCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final activeWallets =
        widget.engine.wallets.where((w) => !w.archived).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('تحويل بين المحافظ')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WalletDropdown(
              label: 'من', wallets: activeWallets,
              selected: _from, exclude: _to,
              onChanged: (w) => setState(() => _from = w),
            ),
            const SizedBox(height: 16),
            _WalletDropdown(
              label: 'إلى', wallets: activeWallets,
              selected: _to, exclude: _from,
              onChanged: (w) => setState(() => _to = w),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'المبلغ (جنيه)',
                prefixIcon: Icon(Icons.attach_money)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'ملاحظة (اختياري)'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _confirmTransfer,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('تحويل'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmTransfer() async {
    final from = _from; final to = _to;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (from == null || to == null) { _snack('اختر المحفظة المصدر والمستهدفة'); return; }
    if (from.id == to.id) { _snack('لا يمكن التحويل لنفس المحفظة'); return; }
    if (amount == null || amount <= 0) { _snack('أدخل مبلغًا موجبًا وصالحًا'); return; }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد التحويل'),
        content: Text('من ${from.name}\nإلى ${to.name}\n'
            '${amount.toStringAsFixed(2)} جنيه',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 16, height: 1.8)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await widget.engine.transferBetweenWallets(
        fromWalletId: from.id, toWalletId: to.id, amount: amount,
        note: _noteCtrl.text.trim().isEmpty
            ? 'تحويل من ${from.name} إلى ${to.name}'
            : _noteCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } on ArgumentError catch (e) {
      _snack(e.message.toString());
    } catch (_) {
      _snack('حدث خطأ غير متوقع — لم يتم التحويل');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _WalletDropdown extends StatelessWidget {
  final String label;
  final List<Wallet> wallets;
  final Wallet? selected;
  final Wallet? exclude;
  final ValueChanged<Wallet?> onChanged;
  const _WalletDropdown({
    required this.label, required this.wallets,
    required this.selected, this.exclude, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final available = wallets.where((w) => w.id != exclude?.id).toList();
    return DropdownButtonFormField<Wallet>(
      // ignore: deprecated_member_use
      value: available.contains(selected) ? selected : null,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: available.map((w) =>
          DropdownMenuItem(value: w, child: Text(w.name))).toList(),
      onChanged: onChanged,
    );
  }
}
