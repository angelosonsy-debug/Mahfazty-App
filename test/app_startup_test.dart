import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mahfazty/main.dart';

void main() {
  testWidgets('التطبيق بيشتغل من غير أخطاء ويظهر اسم "محفظتي"', (tester) async {
    SharedPreferences.setMockInitialValues({});

    // نحاكي قنوات الأذونات عشان مانوقعش في MissingPluginException وقت
    // الاختبار (مفيش منصة حقيقية هنا تردّ على النداءات دي)
    const smsChannel = MethodChannel('mahfazty/sms');
    const notificationsChannel = MethodChannel('mahfazty/notifications');
    const powerChannel = MethodChannel('mahfazty/power');

    // ignore: deprecated_member_use
    smsChannel.setMockMethodCallHandler((call) async {
      if (call.method == 'isSmsPermissionGranted') return false;
      return null;
    });
    // ignore: deprecated_member_use
    notificationsChannel.setMockMethodCallHandler((call) async {
      if (call.method == 'isNotificationAccessGranted') return false;
      return null;
    });
    // استثناء تحسين البطارية — قناة جديدة (mahfazty/power)، لازم تتحاكى
    // هنا كمان زي الاتنين اللي فوق، وإلا MissingPluginException بتهرب
    // من catch (_) في main.dart لو مكتوبة on PlatformException بس.
    // ignore: deprecated_member_use
    powerChannel.setMockMethodCallHandler((call) async {
      if (call.method == 'isIgnoringBatteryOptimizations') return false;
      return null;
    });

    // runAsync لازم هنا: ingestion pipeline (AiAssistedIngestion) بتشغّل
    // Timer دوري حقيقي (فحص/تفريغ أجزاء رسائل SMS غير مكتملة كل ثانية)
    // من dart:async. في بيئة اختبار الـ widget العادية (FakeAsync)، أي
    // Timer حقيقي بيفضل "معلّق" وقت ما الـ widget tree بيتفكك، وFlutter
    // test framework بيرفض ده صراحة ("A Timer is still pending even
    // after the widget tree was disposed"). runAsync هو الحل الموثّق من
    // Flutter نفسها بالظبط لهذه الحالة — بيشغّل الكود في zone حقيقي
    // فعلًا، فالـ Timer يقدر يستنى وينتهي طبيعي (وقت تنفيذ الاختبار
    // هيزيد شوية، دي تكلفة مقبولة ومتوقعة، مش عيب).
    //
    // ملحوظة: قبل كده كان فيه سبب تاني هنا بردو (main.dart._maybeBackupOnOpen
    // بتاع Google Drive)، اتشال مع إزالة Google Sign-In/Drive بالكامل من
    // المشروع - السبب الحالي (الـ SMS fragment timer) قائم بذاته ومستقل.
    await tester.runAsync(() async {
      // onboardingDone: true — الاختبار ده بيغطي الـ AppShell الرئيسي،
      // مش شاشات التعريف (ليها اختبارها الخاص لو احتجنا).
      await tester.pumpWidget(const MahfaztyApp(onboardingDone: true));
      await tester.pumpAndSettle();
    });

    // اسم التطبيق الظاهر بقى "محفظتي" - مفيش أي أثر لـ "Trial"/"Mahfazty" ظاهر
    expect(find.text('محفظتي'), findsWidgets);
    expect(find.textContaining('Trial'), findsNothing);
  });
}
