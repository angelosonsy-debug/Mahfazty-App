import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/client.dart';
import 'client_detail_screen.dart';

/// قائمة العملاء - كل عميل بيوريك صافي حسابه على طول (مين عليه لمين)
/// من غير ما تحتاج تفتحه. الديون مبنية على عميل + معاملات جواه، مش
/// List مفلطحة من الديون المنفصلة.
class ClientsScreen extends StatelessWidget {
  final FinancialEngine engine;
  const ClientsScreen({super.key, required this.engine});

  Future<void> _addClient(BuildContext context) async {
    final nameController = TextEditingController();
    final notesController = TextEditingController();

    final client = await showDialog<Client>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة عميل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'الاسم'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                Client(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  name: nameController.text.trim(),
                  createdAt: DateTime.now(),
                  notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                ),
              );
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );

    if (client != null) {
      await engine.addClient(client);
    }
  }

  Future<void> _renameClient(BuildContext context, Client client) async {
    final nameController = TextEditingController(text: client.name);
    final notesController = TextEditingController(text: client.notes ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل العميل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'الاسم'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );

    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      await engine.updateClient(
        client.id,
        name: nameController.text.trim(),
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      );
    }
  }

  Future<void> _deleteClient(BuildContext context, Client client) async {
    final transactionCount = engine.transactionsForClient(client.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف "${client.name}"؟'),
        content: Text(
          transactionCount > 0
              ? 'هيتحذف العميل ده وكل معاملاته ($transactionCount معاملة) نهائيًا. الإجراء ده مش قابل للتراجع.'
              : 'الإجراء ده مش قابل للتراجع.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true) {
      await engine.deleteClient(client.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalTheyOweUs = engine.moneyOwedToMe;
    final totalWeOweThem = engine.moneyIOwe;
    final net = totalTheyOweUs - totalWeOweThem;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _NetStat(label: 'ليا عند الكل', value: totalTheyOweUs),
                  _NetStat(label: 'عليّ للكل', value: totalWeOweThem),
                  _NetStat(
                    label: 'الصافي',
                    value: net,
                    highlight: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (engine.clients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('مفيش عملاء لسه - دوس + عشان تضيف حد')),
            )
          else
            for (final client in engine.clients)
              _ClientCard(
                client: client,
                net: engine.clientNet(client.id),
                transactionCount: engine.transactionsForClient(client.id).length,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ListenableBuilder(
                      listenable: engine,
                      builder: (context, _) => ClientDetailScreen(engine: engine, client: client),
                    ),
                  ),
                ),
                onRename: () => _renameClient(context, client),
                onDelete: () => _deleteClient(context, client),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addClient(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('إضافة عميل'),
      ),
    );
  }
}

class _NetStat extends StatelessWidget {
  final String label;
  final double value;
  final bool highlight;

  const _NetStat({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final color = !highlight
        ? null
        : (value > 0 ? Colors.green : (value < 0 ? Colors.red : null));
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value.abs().toStringAsFixed(0),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
        ),
      ],
    );
  }
}

class _ClientCard extends StatelessWidget {
  final Client client;
  final double net;
  final int transactionCount;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ClientCard({
    required this.client,
    required this.net,
    required this.transactionCount,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theyOweUs = net > 0;
    final settled = net == 0;
    final color = settled ? Colors.grey : (theyOweUs ? Colors.green : Colors.red);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(child: Text(client.name.substring(0, 1))),
        title: Text(client.name),
        subtitle: Text(
          settled
              ? 'متسوّى - $transactionCount معاملة'
              : theyOweUs
                  ? 'مديون لينا ${net.toStringAsFixed(2)} جنيه - $transactionCount معاملة'
                  : 'احنا مديونينله ${net.abs().toStringAsFixed(2)} جنيه - $transactionCount معاملة',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: color),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'rename') onRename();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'rename', child: Text('تعديل الاسم')),
                const PopupMenuItem(value: 'delete', child: Text('حذف العميل')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
