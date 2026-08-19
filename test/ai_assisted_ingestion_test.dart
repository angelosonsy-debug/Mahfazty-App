import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trial/financial_engine/ai/ai_assisted_ingestion.dart';
import 'package:trial/financial_engine/ai/ai_settings_store.dart';
import 'package:trial/financial_engine/engine/financial_engine.dart';
import 'package:trial/financial_engine/engine/local_store.dart';
import 'package:trial/financial_engine/models/financial_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  AiAssistedIngestion _newIngestion(FinancialEngine engine) =>
      AiAssistedIngestion(engine, AiSettingsStore());

  group('بوابة مصدر InstaPay (Bug Fix - النص وحده مش كافي)', () {
    test('إشعار من تطبيق InstaPay الحقيقي - مقبول', () async {
      final engine = FinancialEngine(LocalStore());
      await engine.load();
      final ingestion = _newIngestion(engine);

      await ingestion.ingestNotification(
        'com.instapay.egypt',
        'InstaPay',
        'تم إضافة مبلغ 500 جنيه إلى حسابك',
      );

      expect(engine.events.length, 1);
      expect(engine.events.first.source, FinancialSource.instaPay);
    });

    test('SMS من البنك الأهلي - مقبول (المصدر التاني الوحيد)', () async {
      final engine = FinancialEngine(LocalStore());
      await engine.load();
      final ingestion = _newIngestion(engine);

      await ingestion.ingestSms(
        'BanK-AlAhly',
        'تم إضافة تحويل لحظي لبطاقتكم مسبقة الدفع بمبلغ 300.00 جم من '
        'أحمد رقم مرجعي 123456789 يوم 07-23 الساعة 19:43 للمزيد اتصل بـ 19623',
      );

      expect(engine.events.length, 1);
    });

    test('إشعار من Vodafone Cash - مرفوض كـ InstaPay', () async {
      final engine = FinancialEngine(LocalStore());
      await engine.load();
      final ingestion = _newIngestion(engine);

      await ingestion.ingestNotification(
        'com.vodafone.vodafonecash',
        'Vodafone Cash',
        'تم إضافة مبلغ 300 جنيه إلى محفظتك عبر InstaPay', // نص فيه كلمة InstaPay عمدًا
      );

      expect(engine.events, isEmpty);
    });

    test('إشعار من WhatsApp - مرفوض كـ InstaPay حتى لو نصه مالي', () async {
      final engine = FinancialEngine(LocalStore());
      await engine.load();
      final ingestion = _newIngestion(engine);

      await ingestion.ingestNotification(
        'com.whatsapp',
        'أحمد',
        'حولتلك 500 جنيه على InstaPay بص كده',
      );

      expect(engine.events, isEmpty);
    });

    test('إشعار عام (نظام/تحديث) فيه كلمة InstaPay في النص - مرفوض بردو', () async {
      final engine = FinancialEngine(LocalStore());
      await engine.load();
      final ingestion = _newIngestion(engine);

      await ingestion.ingestNotification(
        'com.android.systemui',
        'System',
        'InstaPay transfer payment received EGP 500',
      );

      expect(engine.events, isEmpty);
    });

    test('SMS من بنك مش معروف (مش VF-Cash ولا البنك الأهلي) - مرفوض تمامًا', () async {
      final engine = FinancialEngine(LocalStore());
      await engine.load();
      final ingestion = _newIngestion(engine);

      await ingestion.ingestSms('SomeOtherBank', 'تم إضافة مبلغ 1000 جنيه إلى حسابك');

      expect(engine.events, isEmpty);
    });

    test('SMS من Vodafone عام (مش VF-Cash) - مرفوض حتى لو نصه فيه "تحويل"', () async {
      final engine = FinancialEngine(LocalStore());
      await engine.load();
      final ingestion = _newIngestion(engine);

      await ingestion.ingestSms('Vodafone', 'تم تنفيذ تحويل بقيمة 275 جنيه');

      expect(engine.events, isEmpty);
    });

    test('SMS عادي فيه كلمة "transfer" من مرسل عشوائي - مرفوض', () async {
      final engine = FinancialEngine(LocalStore());
      await engine.load();
      final ingestion = _newIngestion(engine);

      await ingestion.ingestSms('RandomSender', 'Your transfer of 100 EGP is complete');

      expect(engine.events, isEmpty);
    });
  });

  group('دمج InstaPay + البنك الأهلي عبر المسار الكامل (Ingestion -> Engine)', () {
    test('إشعار InstaPay حقيقي + SMS بنك أهلي بنفس المبلغ خلال دقيقتين - حدث واحد بس', () async {
      final engine = FinancialEngine(LocalStore());
      await engine.load();
      final ingestion = _newIngestion(engine);

      await ingestion.ingestNotification(
        'com.instapay.egypt',
        'InstaPay',
        'تم استلام 500 جنيه',
      );
      expect(engine.events.length, 1);

      await ingestion.ingestSms(
        'BanK-AlAhly',
        'تم إضافة تحويل لحظي لبطاقتكم مسبقة الدفع بمبلغ 500.00 جم من '
        'محمد رقم مرجعي 987654321 يوم 07-23 الساعة 20:00 للمزيد اتصل بـ 19623',
      );

      expect(engine.events.length, 1); // اتدمجوا في حدث واحد، مش اتنين
    });
  });
}
