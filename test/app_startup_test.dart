import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trial/main.dart';

void main() {
  testWidgets('التطبيق بيشتغل من غير أخطاء ويظهر اسم "محفظتي"', (tester) async {
    SharedPreferences.setMockInitialValues({});

    // نحاكي قنوات الأذونات عشان مانوقعش في MissingPluginException وقت
    // الاختبار (مفيش منصة حقيقية هنا تردّ على النداءات دي)
    const smsChannel = MethodChannel('mahfazty/sms');
    const notificationsChannel = MethodChannel('mahfazty/notifications');

    smsChannel.setMockMethodCallHandler((call) async {
      if (call.method == 'isSmsPermissionGranted') return false;
      return null;
    });
    notificationsChannel.setMockMethodCallHandler((call) async {
      if (call.method == 'isNotificationAccessGranted') return false;
      return null;
    });

    await tester.pumpWidget(const MahfaztyApp());
    await tester.pumpAndSettle();

    // اسم التطبيق الظاهر بقى "محفظتي" - مفيش أي أثر لـ "Trial"/"Mahfazty" ظاهر
    expect(find.text('محفظتي'), findsWidgets);
    expect(find.textContaining('Trial'), findsNothing);
  });
}
