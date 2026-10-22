import 'package:shared_preferences/shared_preferences.dart';

/// C3: المستخدم لا يحتاج إدخال API Key بعد الآن.
/// الإعداد الوحيد هو تفعيل/تعطيل "الفهم الذكي" (AI enabled toggle).
///
/// Migration: لو كان المستخدم حافظ API key قديم محليًا، نحذفه بشكل آمن
/// بدون إرساله لأي مكان.
class AiSettingsStore {
  static const _enabledKey  = 'mahfazty_ai_enabled_v1';
  static const _legacyKeyK  = 'mahfazty_ai_api_key_v1'; // للحذف فقط
  static const _migratedKey = 'mahfazty_ai_c3_migrated';

  /// يُشغَّل عند أول تشغيل بعد C3 — يحذف API key قديم بأمان.
  Future<void> runC3Migration() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey) == true) return; // migration سبق تشتغلت

    // حذف المفتاح القديم — لا نقرأه، لا نطبعه في logs، لا نرسله
    await prefs.remove(_legacyKeyK);
    await prefs.setBool(_migratedKey, true);
  }

  Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> saveEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }
}
