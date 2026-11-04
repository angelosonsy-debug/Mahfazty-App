import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// نقطة التهيئة الوحيدة لـ flutter_local_notifications — بيستخدمها
/// TransactionNotifier (إشعارات تأكيد العمليات) وDebtReminderScheduler
/// (تذكير الديون). ملحوظة: ده منفصل تمامًا عن Notification Access
/// (MethodChannel 'mahfazty/notifications') اللي بيقرأ إشعارات InstaPay.
///
/// كل الدوال هنا بتبلع الأخطاء عمدًا: فشل إشعار (أو غياب الـ plugin في
/// بيئة الاختبار) ما لازم يوقّع تسجيل معاملة مالية أبدًا.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _permissionAskedKey = 'notif_permission_asked_v1';

  FlutterLocalNotificationsPlugin get plugin => FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<bool> ensureInitialized() async {
    if (_initialized) return true;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await plugin.initialize(const InitializationSettings(android: androidInit));
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService.init failed: $e');
    }
    return _initialized;
  }

  /// بيطلب صلاحية POST_NOTIFICATIONS (أندرويد 13+ بس بيظهر Dialog؛ في
  /// الإصدارات الأقدم بيرجع true من غير ما يسأل). الـ plugin نفسه بيتعامل
  /// مع فحص نسخة الأندرويد، فمش محتاجين permission_handler ولا MethodChannel.
  Future<bool> requestPermission() async {
    try {
      if (!await ensureInitialized()) return false;
      final android = plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('NotificationService.requestPermission failed: $e');
      return false;
    }
  }

  /// أول فتح للتطبيق بس: نطلب الصلاحية مرة واحدة، ومنسألش تاني تلقائي
  /// (لو رفض، بيقدر يفعّلها من إعدادات التطبيق).
  Future<void> requestPermissionOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_permissionAskedKey) ?? false) return;
      await prefs.setBool(_permissionAskedKey, true);
      await requestPermission();
    } catch (e) {
      debugPrint('NotificationService.requestPermissionOnce failed: $e');
    }
  }
}
