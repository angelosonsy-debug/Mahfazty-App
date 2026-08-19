import 'package:shared_preferences/shared_preferences.dart';

/// تخزين مفتاح الـ API محليًا بس على جهاز المستخدم - أبدًا مش بيتحط في
/// الكود المصدري ولا بيترفع على GitHub. المستخدم بيدخله بنفسه من شاشة
/// الإعدادات مرة واحدة، ومن ساعتها بيتقرأ من التخزين المحلي بس.
class AiSettingsStore {
  static const _apiKeyKey = 'mahfazty_ai_api_key_v1';
  static const _enabledKey = 'mahfazty_ai_enabled_v1';

  Future<String?> loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  Future<void> saveApiKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == null || key.trim().isEmpty) {
      await prefs.remove(_apiKeyKey);
    } else {
      await prefs.setString(_apiKeyKey, key.trim());
    }
  }

  Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> saveEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }
}
