import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// سجل تشخيصي بسيط لأي SMS/إشعار اترفض بصمت قبل ما يوصل حتى لصندوق
/// المراجعة (بوابة المرسل، أو فلتر "هل دي رسالة مالية؟"). قبل الملف ده،
/// الرفض ده كان بيحصل من غير أي أثر خالص - مفيش طريقة للمستخدم يكتشف
/// إن رسالة بنكه الحقيقية اترفضت غلط. السجل محلي بالكامل (SharedPreferences)
/// ومحدود بعدد أقصى من العناصر - مش جزء من البيانات المالية نفسها، مجرد
/// أداة تشخيص يقدر المستخدم يراجعها من الإعدادات.
class RejectionLogEntry {
  final String source; // 'sms' | 'notification'
  final String identifier; // sender أو packageName
  final String reason;
  final String snippet; // أول جزء من النص - للتشخيص بس
  final DateTime timestamp;

  const RejectionLogEntry({
    required this.source,
    required this.identifier,
    required this.reason,
    required this.snippet,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'source': source,
        'identifier': identifier,
        'reason': reason,
        'snippet': snippet,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory RejectionLogEntry.fromJson(Map<String, dynamic> json) => RejectionLogEntry(
        source: json['source'] as String? ?? '',
        identifier: json['identifier'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        snippet: json['snippet'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int? ?? 0),
      );
}

class RejectionLog {
  static const _key = 'mahfazty_rejection_log_v1';
  static const _maxEntries = 100;
  static const _maxSnippetLength = 160;

  static Future<void> log({
    required String source,
    required String identifier,
    required String reason,
    required String snippet,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      final entry = RejectionLogEntry(
        source: source,
        identifier: identifier,
        reason: reason,
        snippet: snippet.length > _maxSnippetLength ? snippet.substring(0, _maxSnippetLength) : snippet,
        timestamp: DateTime.now(),
      );
      raw.add(jsonEncode(entry.toJson()));
      final trimmed = raw.length > _maxEntries ? raw.sublist(raw.length - _maxEntries) : raw;
      await prefs.setStringList(_key, trimmed);
    } catch (_) {
      // السجل أداة تشخيصية ثانوية - فشل الكتابة هنا مايوقفش أي حاجة
      // تانية في مسار الاستقبال نفسه.
    }
  }

  /// الأحدث أولًا.
  static Future<List<RejectionLogEntry>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw.reversed
        .map((s) {
          try {
            return RejectionLogEntry.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<RejectionLogEntry>()
        .toList();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
