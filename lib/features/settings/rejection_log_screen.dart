import 'package:flutter/material.dart';

import '../../core/services/rejection_log.dart';

/// شاشة تشخيصية بسيطة: بتعرض آخر الرسائل/الإشعارات اللي اترفضت بصمت
/// قبل ما توصل حتى لصندوق المراجعة (بوابة المرسل، أو فلتر "هل دي رسالة
/// مالية؟"، أو فشل استخراج التفاصيل بالكامل). الهدف: لو رسالة بنك
/// حقيقية بترفض غلط، المستخدم يقدر يكتشف ده هنا بدل ما تضيع بصمت تام.
class RejectionLogScreen extends StatefulWidget {
  const RejectionLogScreen({super.key});

  @override
  State<RejectionLogScreen> createState() => _RejectionLogScreenState();
}

class _RejectionLogScreenState extends State<RejectionLogScreen> {
  late Future<List<RejectionLogEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = RejectionLog.readAll();
  }

  void _refresh() => setState(() => _future = RejectionLog.readAll());

  Future<void> _clear() async {
    await RejectionLog.clear();
    _refresh();
  }

  String _sourceLabel(String source) => source == 'notification' ? 'إشعار' : 'SMS';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('رسائل مرفوضة بصمت'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: 'تحديث'),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clear, tooltip: 'مسح السجل'),
        ],
      ),
      body: FutureBuilder<List<RejectionLogEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'مفيش حاجة اترفضت لحد دلوقتي. لو حسيت إن رسالة بنك أو محفظة حقيقية اختفت، هتلاقيها هنا بعد كده.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final e = entries[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Chip(label: Text(_sourceLabel(e.source)), visualDensity: VisualDensity.compact),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(e.identifier, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(e.reason, style: const TextStyle(color: Colors.orange, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text(e.snippet, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 6),
                      Text(
                        '${e.timestamp.day}/${e.timestamp.month}/${e.timestamp.year} - ${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
