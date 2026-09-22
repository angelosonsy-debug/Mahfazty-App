import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/financial_event.dart';

class DashboardScreen extends StatelessWidget {
  final FinancialEngine engine;
  final VoidCallback onOpenWallets;
  final VoidCallback onOpenDebts;
  final VoidCallback onOpenPocket;
  final VoidCallback onOpenReview;

  const DashboardScreen({
    super.key,
    required this.engine,
    required this.onOpenWallets,
    required this.onOpenDebts,
    required this.onOpenPocket,
    required this.onOpenReview,
  });

  @override
  Widget build(BuildContext context) {
    final recentEvents = engine.events.take(5).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _NetWorthCard(netWorth: engine.netWorth),
        if (engine.pendingReview.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.rate_review_outlined),
              title: Text('${engine.pendingReview.length} معاملة محتاجة مراجعتك'),
              subtitle: const Text('راجعها واحدة واحدة - صحيح / تعديل / تجاهل'),
              trailing: FilledButton(onPressed: onOpenReview, child: const Text('راجع الآن')),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Pocket',
                subtitle: 'يدوي',
                value: '${engine.pocketBalance.toStringAsFixed(2)} جنيه',
                onTap: onOpenPocket,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                icon: Icons.credit_card,
                title: 'المحافظ',
                subtitle: 'تلقائي',
                value: '${engine.walletsTotal.toStringAsFixed(2)} جنيه',
                onTap: onOpenWallets,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.handshake_outlined,
                title: 'الديون',
                subtitle: 'يدوي',
                value:
                    'لي ${engine.moneyOwedToMe.toStringAsFixed(0)} / عليّ ${engine.moneyIOwe.toStringAsFixed(0)}',
                onTap: onOpenDebts,
                small: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (recentEvents.isNotEmpty) ...[
          Text('آخر الأحداث', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final e in recentEvents)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: Icon(
                  e.source.labelAr == 'البنك الأهلي' ? Icons.account_balance : Icons.bolt,
                  size: 20,
                ),
                title: Text('${e.source.labelAr} - ${e.eventType.labelAr}'),
                subtitle: e.amount != null ? Text('${e.amount!.toStringAsFixed(2)} جنيه') : null,
                trailing: Text(
                  '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}',
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  final double netWorth;
  const _NetWorthCard({required this.netWorth});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('صافي الثروة', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              '${netWorth.toStringAsFixed(2)} جنيه',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;
  final bool small;

  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                  const Icon(Icons.chevron_left, size: 18),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(fontSize: small ? 14 : 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
