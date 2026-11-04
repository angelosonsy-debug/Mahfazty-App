import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/premium_service.dart';
import '../../core/services/ussd_launcher.dart';
import '../../core/utils/money_format.dart';
import '../../features/premium/premium_modal.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/financial_event.dart';
import '../../financial_engine/models/wallet.dart';
import 'wallet_wizard.dart';

/// I1: شاشة المحافظ الجديدة — محافظ ديناميكية من engine.wallets.
class WalletsScreen extends StatelessWidget {
  final FinancialEngine engine;
  const WalletsScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final activeWallets = engine.wallets.where((w) => !w.archived).toList();
    final archivedWallets = engine.wallets.where((w) => w.archived).toList();
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
      body: activeWallets.isEmpty && archivedWallets.isEmpty
          ? _EmptyState(onAdd: () => _openWizard(context))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (activeWallets.isEmpty)
                  _EmptyState(onAdd: () => _openWizard(context))
                else
                  ...activeWallets.map((w) => _WalletCard(wallet: w, engine: engine)),
                if (archivedWallets.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('المحافظ المأرشفة',
                        style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
                  ),
                  ...archivedWallets.map((w) => _WalletCard(wallet: w, engine: engine, archived: true)),
                ],
              ],
            ),
    );
  }

  Future<void> _openWizard(BuildContext context) async {
    final ps = PremiumService.instance;
    if (!ps.canAddWallet(engine.wallets)) {
      if (context.mounted) await showPremiumModal(context);
      return;
    }
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => WalletWizard(engine: engine)));
  }
}

class _WalletCard extends StatelessWidget {
  final Wallet wallet;
  final FinancialEngine engine;
  final bool archived;
  const _WalletCard({required this.wallet, required this.engine, this.archived = false});

  @override
  Widget build(BuildContext context) {
    final balance = engine.balanceForWallet(wallet.id);
    final lastEvent = engine.lastEventForWallet(wallet.id);
    final sources = engine.sourcesForWallet(wallet.id);
    return Opacity(
      opacity: archived ? 0.55 : 1.0,
      child: Card(
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
              balance != null ? '${formatMoney(balance)} جنيه' : '— جنيه',
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
          itemBuilder: (_) => archived
              ? [
                  const PopupMenuItem(value: _WalletAction.unarchive, child: Text('إلغاء الأرشفة')),
                  const PopupMenuItem(
                    value: _WalletAction.delete,
                    child: Text('حذف نهائياً', style: TextStyle(color: Colors.red)),
                  ),
                ]
              : [
                  const PopupMenuItem(value: _WalletAction.addTransaction, child: Text('إضافة معاملة')),
                  const PopupMenuItem(value: _WalletAction.edit, child: Text('تعديل')),
                  const PopupMenuItem(value: _WalletAction.adjustBalance, child: Text('تصحيح الرصيد')),
                  const PopupMenuItem(value: _WalletAction.archive, child: Text('أرشفة')),
                  if (UssdLauncher.isSupported(UssdLauncher.resolveCarrier(wallet)))
                    const PopupMenuItem(value: _WalletAction.ussdTransfer, child: Text('تحويل فودافون كاش')),
                ],
        ),
      ),
    ),
    );
  }

  void _handleAction(BuildContext context, _WalletAction action) {
    switch (action) {
      case _WalletAction.addTransaction:
        _showAddTransactionSheet(context);
      case _WalletAction.edit:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => WalletWizard(engine: engine, existing: wallet)));
      case _WalletAction.adjustBalance:
        _showBalanceDialog(context);
      case _WalletAction.archive:
        _confirmArchive(context);
      case _WalletAction.unarchive:
        engine.unarchiveWallet(wallet.id);
      case _WalletAction.delete:
        _confirmDelete(context);
      case _WalletAction.ussdTransfer:
        _showUssdSheet(context);
    }
  }

  void _showBalanceDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصحيح الرصيد'),
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
                'استخدم هذا فقط لتصحيح رصيد غير مطابق — لن يُسجَّل كعملية عادية.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'الرصيد الفعلي (جنيه)'),
        ),
          ],
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

  // ─── إضافة معاملة يدوية ───────────────────────────────────────────
  void _showAddTransactionSheet(BuildContext context) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var isDeposit = true;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, sst) => Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20,
              MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إضافة معاملة — ${wallet.name}',
                  style: Theme.of(sheetCtx).textTheme.titleMedium),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('إيداع'), icon: Icon(Icons.add)),
                  ButtonSegment(value: false, label: Text('سحب'), icon: Icon(Icons.remove)),
                ],
                selected: {isDeposit},
                onSelectionChanged: (s) => sst(() => isDeposit = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'المبلغ',
                  suffixText: 'جنيه',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'ملاحظة (اختياري)',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final amount = double.tryParse(
                      amountCtrl.text.replaceAll(',', ''));
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('أدخل مبلغًا صالحًا')));
                    return;
                  }
                  Navigator.pop(sheetCtx);
                  await engine.recordManualTransaction(
                    walletId: wallet.id,
                    type: isDeposit
                        ? FinancialEventType.deposit
                        : FinancialEventType.withdrawal,
                    amount: amount,
                    note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                  );
                },
                child: const Text('تسجيل'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── USSD ──────────────────────────────────────────────────────────
  void _showUssdSheet(BuildContext context) {
    final phoneCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تحويل عبر فودافون كاش',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'سيُفتح الـ Dialer بالكود جاهزًا — ستحتاج لضغط "اتصال" بنفسك.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'رقم المستلم',
                hintText: '010xxxxxxxx',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'المبلغ (أرقام صحيحة)',
                suffixText: 'جنيه',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.phone_outlined),
              label: const Text('فتح الـ Dialer'),
              onPressed: () async {
                final phone = phoneCtrl.text.trim();
                final amount = double.tryParse(amountCtrl.text.trim());
                final carrier = UssdLauncher.resolveCarrier(wallet);
                if (!UssdLauncher.isValidPhone(phone)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('رقم الهاتف غير صالح (11 رقم يبدأ بـ 01)')));
                  return;
                }
                if (amount == null || !UssdLauncher.isValidAmount(amount)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('المبلغ يجب أن يكون رقمًا صحيحًا موجبًا')));
                  return;
                }
                Navigator.pop(sheetCtx);
                if (carrier != null) {
                  final ok = await UssdLauncher.launch(phone, amount, carrier);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تعذّر فتح تطبيق الاتصال')));
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('نسخ البيانات'),
              onPressed: () {
                final phone = phoneCtrl.text.trim();
                final amount = amountCtrl.text.trim();
                Clipboard.setData(ClipboardData(text: 'رقم: $phone — مبلغ: $amount جنيه'));
                Navigator.pop(sheetCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم النسخ للحافظة')));
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── حذف نهائي (للمؤرشفة فقط) ─────────────────────────────────────
  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 40),
        title: const Text('حذف نهائي؟'),
        content: Text(
          'هذا الإجراء نهائي وسيحذف كل المعاملات المرتبطة بـ «${wallet.name}». '
          'لا يمكن التراجع عنه.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await engine.deleteWallet(wallet.id);
            },
            child: const Text('حذف نهائياً'),
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

enum _WalletAction { addTransaction, edit, adjustBalance, archive, unarchive, delete, ussdTransfer }

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
