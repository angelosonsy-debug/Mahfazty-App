import 'package:flutter/material.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/financial_event.dart';
import '../review/pending_review_screen.dart';

/// Inbox رسمي: أي حدث جديد بيوصل يتصنف تلقائي إما Auto Apply (ثقة عالية،
/// اتطبق على الرصيد على طول) أو Review (هنا، محتاج تأكيدك). الشاشة دي
/// بتوريك اللي محتاج مراجعة، وبتديك مدخل واحد واضح لمراجعتهم واحد واحد.
class InboxScreen extends StatelessWidget {
  final FinancialEngine engine;
  const InboxScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final pending = engine.pendingReview;
    final autoApplied = engine.autoAppliedEvents.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _StatChip(
                label: 'اتطبقت تلقائي',
                value: autoApplied.toString(),
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatChip(
                label: 'محتاجة مراجعتك',
                value: pending.length.toString(),
                color: pending.isEmpty ? Colors.grey : Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('مفيش حاجة محتاجة مراجعة دلوقتي 🎉')),
          )
        else ...[
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PendingReviewScreen(engine: engine)),
            ),
            icon: const Icon(Icons.rate_review_outlined),
            label: Text('ابدأ المراجعة (${pending.length})'),
          ),
          const SizedBox(height: 16),
          for (final e in pending)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${e.source.labelAr} - ${e.eventType.labelAr}'),
                subtitle: Text(
                  e.amount != null ? '${e.amount!.toStringAsFixed(2)} جنيه' : 'مفيش مبلغ مستخرج',
                ),
                trailing: Text(e.confidenceLabelAr, style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
