import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../financial_engine/models/client.dart';
import '../utils/money_format.dart';
import 'notification_service.dart';

/// جدولة تذكير قبل تاريخ استحقاق الدين.
///
/// القرارات:
///  - التذكير الأساسي قبل الاستحقاق بـ 3 أيام، الساعة 9 الصبح (تاريخ
///    الاستحقاق نفسه من DatePicker من غير ساعة، فنفس الساعة هتبقى 12 بالليل).
///  - لو ميعاد الـ 3 أيام فات والدين لسه مستحقش (مثلًا استحقاق بعد يومين)،
///    بنرجع لتذكير قبله بيوم، وبعدين يوم الاستحقاق نفسه، بدل ما التذكير
///    يضيع بصمت.
///  - inexactAllowWhileIdle: من غير صلاحية SCHEDULE_EXACT_ALARM (تذكير ديون
///    ممكن يتأخر دقائق من غير مشكلة).
class DebtReminderScheduler {
  DebtReminderScheduler();

  static final DebtReminderScheduler instance = DebtReminderScheduler();

  static const leadDays = 3;
  static const reminderHour = 9;
  static const _horizon = Duration(days: 180);

  bool _tzReady = false;

  static int notificationIdFor(String debtId) => 'debt_$debtId'.hashCode & 0x7FFFFFFF;

  /// بترجع وقت التذكير (بتوقيت الجهاز) أو null لو مفيش ميعاد صالح.
  /// دالة نقية عشان تتختبر بسهولة.
  static DateTime? reminderTimeFor(DateTime dueDate, DateTime now) {
    final candidates = <DateTime>[
      DateTime(dueDate.year, dueDate.month, dueDate.day - leadDays, reminderHour),
      DateTime(dueDate.year, dueDate.month, dueDate.day - 1, reminderHour),
      DateTime(dueDate.year, dueDate.month, dueDate.day, reminderHour),
    ];
    for (final c in candidates) {
      if (c.isAfter(now)) return c;
    }
    return null;
  }

  void _ensureTimeZones() {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    // التطبيق للسوق المصري؛ ومش عايزين مكتبة إضافية بس عشان نعرف
    // المنطقة الزمنية. TZDateTime.from بتحافظ على اللحظة الفعلية صح
    // حتى لو جهاز المستخدم على منطقة تانية.
    tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    _tzReady = true;
  }

  Future<void> schedule(DebtTransaction t, {required String clientName}) async {
    try {
      await cancel(t.id); // نستبدل أي تذكير قديم لنفس المعاملة دايمًا
      final due = t.dueDate;
      if (due == null || t.isSettlement) return;

      final now = DateTime.now();
      final when = reminderTimeFor(due, now);
      if (when == null || when.isAfter(now.add(_horizon))) return;
      if (!await NotificationService.instance.ensureInitialized()) return;
      _ensureTimeZones();

      final amountText = formatMoney(t.amount);
      final dueText = '${due.day}/${due.month}/${due.year}';
      final theyOweUs = t.direction == DebtEntryDirection.theyOweUs;
      final title = theyOweUs ? 'تذكير: دين ليك قرّب ميعاده' : 'تذكير: دين عليك قرّب ميعاده';
      final body = theyOweUs
          ? '$clientName عليه $amountText جنيه — الاستحقاق $dueText'
          : 'عليك $amountText جنيه لـ $clientName — الاستحقاق $dueText';

      await NotificationService.instance.plugin.zonedSchedule(
        notificationIdFor(t.id),
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'debt_reminders',
            'تذكير الديون',
            channelDescription: 'تذكير قبل ميعاد استحقاق الديون',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('DebtReminderScheduler.schedule failed: $e');
    }
  }

  Future<void> cancel(String debtId) async {
    try {
      await NotificationService.instance.plugin.cancel(notificationIdFor(debtId));
    } catch (e) {
      debugPrint('DebtReminderScheduler.cancel failed: $e');
    }
  }
}
