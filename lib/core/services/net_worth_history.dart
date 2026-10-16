import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// لقطة يومية لصافي الثروة (آخر قيمة اتسجلت في كل يوم) — بنستخدمها في
/// "▲ +X% مقارنة بالأمس". مخزّنة محليًا بس في SharedPreferences.
///
/// "الأمس" هنا = آخر لقطة محفوظة قبل النهارده (مش بالضرورة امبارح بالظبط
/// لو التطبيق ما اتفتحش يوم).
class NetWorthHistory {
  const NetWorthHistory();

  static const _key = 'mahfazty_networth_snapshots_v1';
  static const _maxDays = 30;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Map<String, double>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {}; // لقطة تالفة مش مبرر نوقّع الشاشة الرئيسية
    }
  }

  Future<void> recordToday(double netWorth, {DateTime? now}) async {
    final map = await _load();
    map[dayKey(now ?? DateTime.now())] = netWorth;
    final keys = map.keys.toList()..sort();
    while (keys.length > _maxDays) {
      map.remove(keys.removeAt(0));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map));
  }

  /// آخر لقطة قبل النهارده، أو null لو مفيش.
  Future<double?> baselineBeforeToday({DateTime? now}) async {
    final today = dayKey(now ?? DateTime.now());
    final map = await _load();
    final earlier = map.keys.where((k) => k.compareTo(today) < 0).toList()..sort();
    if (earlier.isEmpty) return null;
    return map[earlier.last];
  }

  /// نسبة التغيير المئوية، أو null لو مفيش أساس مقارنة منطقي (صفر).
  static double? changePercent(double current, double? baseline) {
    if (baseline == null || baseline.abs() < 0.01) return null;
    return (current - baseline) / baseline.abs() * 100;
  }
}
