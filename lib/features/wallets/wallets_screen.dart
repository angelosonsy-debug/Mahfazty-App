import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/financial_event.dart';

class WalletsScreen extends StatelessWidget {
  final FinancialEngine engine;
  const WalletsScreen({super.key, required this.engine});

  Future<void> _editBalance(BuildContext context, FinancialSource source, double? current) async {
    final controller = TextEditingController(text: current?.toStringAsFixed(2) ?? '');
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل رصيد ${source.labelAr} يدويًا'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'جنيه'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result != null) {
      await engine.setWalletBalanceManually(source, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _WalletCard(
          title: 'Vodafone Cash',
          icon: Icons.phone_android,
          balance: engine.walletBalance[FinancialSource.vodafoneCash],
          lastEvent: engine.lastEventFor(FinancialSource.vodafoneCash),
          onEditBalance: () => _editBalance(
            context,
            FinancialSource.vodafoneCash,
            engine.walletBalance[FinancialSource.vodafoneCash],
          ),
        ),
        const SizedBox(height: 12),
        _WalletCard(
          title: 'InstaPay',
          icon: Icons.qr_code,
          balance: engine.walletBalance[FinancialSource.instaPay],
          // ملحوظة: أحداث InstaPay الحقيقية اتسجلت تحت مصدر البنك الأهلي
          // (FinancialSource.alAhlyBank) - ده المصدر المالي الوحيد ليها.
          lastEvent: engine.lastEventFor(FinancialSource.alAhlyBank),
          onEditBalance: () => _editBalance(
            context,
            FinancialSource.instaPay,
            engine.walletBalance[FinancialSource.instaPay],
          ),
        ),
      ],
    );
  }
}

class _WalletCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double? balance;
  final FinancialEvent? lastEvent;
  final VoidCallback onEditBalance;

  const _WalletCard({
    required this.title,
    required this.icon,
    required this.balance,
    required this.lastEvent,
    required this.onEditBalance,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Icon(icon)),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: 'تعديل الرصيد يدويًا',
                  onPressed: onEditBalance,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              balance != null ? '${balance!.toStringAsFixed(2)} جنيه' : 'لسه معندناش بيانات',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (lastEvent != null) ...[
              Text('آخر عملية: ${lastEvent!.eventType.labelAr}'),
              Text(
                '${lastEvent!.timestamp.day}/${lastEvent!.timestamp.month} '
                '${lastEvent!.timestamp.hour.toString().padLeft(2, '0')}:'
                '${lastEvent!.timestamp.minute.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
              Text('لسه مفيش عمليات', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
