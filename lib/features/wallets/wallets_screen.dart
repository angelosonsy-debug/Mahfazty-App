import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/wallet.dart';
import 'wallet_wizard.dart';

/// I1: شاشة المحافظ الجديدة — محافظ ديناميكية من engine.wallets.
class WalletsScreen extends StatelessWidget {
  final FinancialEngine engine;
  const WalletsScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final activeWallets = engine.wallets.where((w) => !w.archived).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('المحافظ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'إضافة محفظة',
            onPressed: () => _openWizard(context),
          ),
        ],
      ),
      body: activeWallets.isEmpty
          ? _EmptyState(onAdd: () => _openWizard(context))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: activeWallets.length,
              itemBuilder: (ctx, i) =>
                  _WalletCard(wallet: activeWallets[i], engine: engine),
            ),
    );
  }

  void _openWizard(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => WalletWizard(engine: engine)));
  }
}

class _WalletCard extends StatelessWidget {
  final Wallet wallet;
  final FinancialEngine engine;
  const _WalletCard({required this.wallet, required this.engine});

  @override
  Widget build(BuildContext context) {
    final balance = engine.balanceForWallet(wallet.id);
    final lastEvent = engine.lastEventForWallet(wallet.id);
    final sources = engine.sourcesForWallet(wallet.id);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(_walletIcon(wallet.type),
              color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(wallet.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              balance != null ? '${balance.toStringAsFixed(2)} جنيه' : '— جنيه',
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600,
                color: (balance ?? 0) >= 0 ? Colors.green : Colors.red),
            ),
            if (sources.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(sources.map((s) => s.displayName).join(' • '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
            if (lastEvent != null) ...[
              const SizedBox(height: 2),
              Text('آخر عملية: ${_fmtDate(lastEvent.timestamp)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ],
        ),
        trailing: PopupMenuButton<_WalletAction>(
          onSelected: (action) => _handleAction(context, action),
          itemBuilder: (_) => const [
            PopupMenuItem(value: _WalletAction.edit, child: Text('تعديل')),
            PopupMenuItem(value: _WalletAction.adjustBalance, child: Text('تعديل الرصيد')),
            PopupMenuItem(value: _WalletAction.archive, child: Text('أرشفة')),
          ],
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, _WalletAction action) {
    switch (action) {
      case _WalletAction.edit:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => WalletWizard(engine: engine, existing: wallet)));
      case _WalletAction.adjustBalance:
        _showBalanceDialog(context);
      case _WalletAction.archive:
        _confirmArchive(context);
    }
  }

  void _showBalanceDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الرصيد'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'الرصيد الفعلي (جنيه)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null) engine.setWalletBalanceManually(wallet.id, v);
              Navigator.pop(ctx);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  void _confirmArchive(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('أرشفة المحفظة'),
        content: Text('سيتم إخفاء «${wallet.name}» من القائمة الرئيسية. الأحداث القديمة لن تُحذف.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { engine.archiveWallet(wallet.id); Navigator.pop(ctx); },
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
  }

  IconData _walletIcon(WalletType type) {
    return switch (type) {
      WalletType.cash => Icons.money,
      WalletType.bankAccount => Icons.account_balance,
      WalletType.mobileWallet => Icons.phone_android,
      WalletType.card => Icons.credit_card,
      WalletType.instaPay => Icons.flash_on,
      WalletType.custom => Icons.wallet,
    };
  }

  String _fmtDate(DateTime dt) => '\${dt.day}/\${dt.month}/\${dt.year}';
}

enum _WalletAction { edit, adjustBalance, archive }

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wallet_outlined, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        const Text('لا توجد محافظ بعد', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 8),
        const Text('ابدأ بإضافة أول محفظة', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('إضافة محفظة')),
      ]),
    );
  }
}
