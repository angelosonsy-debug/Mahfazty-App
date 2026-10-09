import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../financial_engine/models/financial_event.dart';
import '../utils/money_format.dart';
import 'notification_service.dart';

/// إشعار تأكيد لكل عملية مؤكدة (ثقة >= 95) — بيتنادى من
/// FinancialEngine.ingest() بعد ما الرصيد يتحسب.
///
/// الكلاس قابل للوراثة عمدًا (الاختبارات بتعمل Fake منه من غير ما تحتاج
/// plugin حقيقي).
class TransactionNotifier {
  TransactionNotifier();

  static final TransactionNotifier instance = TransactionNotifier();

  /// مفتاح SharedPreferences اللي بيتحكم فيه سويتش الإعدادات
  static const prefsKey = 'notify_on_transaction';

  bool enabled = true; // الافتراضي: مفعّل

  Future<void> init() async {
    await NotificationService.instance.ensureInitialized();
    await loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(prefsKey) ?? true;
    } catch (e) {
      debugPrint('TransactionNotifier.loadSettings failed: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, value);
    if (value) {
      // لو المستخدم لسه ما وافقش على الصلاحية (أو رفضها قبل كده)
      // بنطلبها تاني لما يفعّل السويتش بإرادته.
      await NotificationService.instance.requestPermission();
    }
  }

  Future<void> notifyTransaction(FinancialEvent event, {String? walletName}) async {
    if (!enabled) return;
    try {
      if (!await NotificationService.instance.ensureInitialized()) return;
      final isIncoming = isIncomingEventType(event.eventType);
      final title = isIncoming ? 'تم الإضافة لمحفظتك' : 'تم الخصم من محفظتك';
      final amountText = event.amount == null ? '' : formatMoney(event.amount!);
      final currency = event.currency == 'EGP' ? 'جنيه' : event.currency;
      final prefix = (walletName == null || walletName.isEmpty) ? '' : '$walletName • ';
      final body = '$prefix${event.eventType.labelAr} — $amountText $currency'.trim();

      await NotificationService.instance.plugin.show(
        event.id.hashCode & 0x7FFFFFFF,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'transactions',
            'تأكيد العمليات',
            channelDescription: 'إشعار عند تسجيل كل عملية مالية مؤكدة',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (e) {
      debugPrint('TransactionNotifier.notifyTransaction failed: $e');
    }
  }
}
