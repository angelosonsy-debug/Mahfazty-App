import 'package:flutter_test/flutter_test.dart';
import 'package:trial/financial_engine/parser/sms_parser.dart';
import 'package:trial/financial_engine/models/financial_event.dart';

// ملحوظة: النصوص هنا نسخة معدّلة (Anonymized) من رسائل حقيقية - الأرقام
// والأسماء الشخصية اتغيرت لأرقام/أسماء وهمية، بس تنسيق الرسالة فضل زي
// الأصل بالظبط.

void main() {
  group('Vodafone Cash SMS parsing -> FinancialEvent', () {
    test('رسالة دفع رسوم', () {
      const sms = 'تم دفع مبلغ 1.0 جنيه رسوم خدمة لفودافون كاش. '
          'رصيد محفظتك الحالي 29.55 جنيه. رقم العملية 022000683716 '
          'تاريخ العملية 23-07-26 23:28. استخدم خدمات فودافون كاش';

      final result = SmsParser.parse('VF-Cash', sms);

      expect(result.matchedSource, SmsSourceMatch.vodafoneCash);
      final event = result.event;
      expect(event, isNotNull);
      expect(event!.source, FinancialSource.vodafoneCash);
      expect(event.eventType, FinancialEventType.withdrawal);
      expect(event.amount, 1.0);
      expect(event.balanceAfter, 29.55);
      expect(event.reference, '022000683716');
      expect(event.confidence, 99);
    });

    test('رسالة استلام تحويل', () {
      const sms = 'تم استلام مبلغ 815 جنيه من رقم 01000000000 '
          'المسجل بإسم Test Sender على رقم محفظتك 01099999999.\n'
          'رصيدك الحالي: 994.05 جنيه\n'
          'تاريخ العملية: 20:30 26-07-22\n'
          'رقم العملية: 021962311072';

      final event = SmsParser.parse('VF-Cash', sms).event!;

      expect(event.eventType, FinancialEventType.deposit);
      expect(event.amount, 815);
      expect(event.balanceAfter, 994.05);
      expect(event.person, 'Test Sender');
      expect(event.reference, '021962311072');
    });

    test('رسالة سحب من ATM', () {
      const sms = 'تم سحب 1600.00 جنية من محفظة فودافون كاش. '
          'رصيد حسابك الحالي 78.05 جنيه. تاريخ العملية 23:30 26-07-22 '
          'رقم العملية; 021969214975.';

      final event = SmsParser.parse('VF-Cash', sms).event!;

      expect(event.eventType, FinancialEventType.withdrawal);
      expect(event.amount, 1600.00);
      expect(event.balanceAfter, 78.05);
      expect(event.reference, '021969214975');
    });

    test('رسالة شحن رصيد', () {
      const sms = 'تم شحن رصيد موبايلك ب 6.3 بنجاح وخصم 9 من محفظتك شاملة '
          'الضريبة; رصيد حسابك في فودافون كاش الحالي 20.05.';

      final event = SmsParser.parse('VF-Cash', sms).event!;

      expect(event.eventType, FinancialEventType.purchase);
      expect(event.amount, 9);
      expect(event.balanceAfter, 20.05);
    });

    test('رسالة تحويل صادر', () {
      const sms = 'تم تحويل 100 جنيه لرقم 01000000001 مصاريف الخدمة 1 جنيه '
          'رصيد حسابك فى فودافون كاش الحالي 29.05.\n'
          'تاريخ العملية 15:11 26-07-22 :\n'
          'رقم العملية 021952428756 :';

      final event = SmsParser.parse('VF-Cash', sms).event!;

      expect(event.eventType, FinancialEventType.transfer);
      expect(event.amount, 100);
      expect(event.balanceAfter, 29.05);
      expect(event.person, '01000000001');
      expect(event.reference, '021952428756');
    });

    test('مرسل غير معروف يترفض من غير Template', () {
      final result = SmsParser.parse('SomeRandomSender', 'رسالة عشوائية 100 جنيه');
      expect(result.matchedSource, SmsSourceMatch.unknown);
      expect(result.event, isNull);
    });
  });

  group('Al-Ahly Bank SMS parsing -> FinancialEvent', () {
    test('تحويل وارد على البطاقة', () {
      const sms = 'تم إضافة تحويل لحظي لبطاقتكم مسبقة الدفع بمبلغ 400.00 جم '
          'من أحمد محمد رقم مرجعي 500000000000 يوم 07-23 الساعة 19:43 '
          'للمزيد اتصل بـ 19623';

      final result = SmsParser.parse('BanK-AlAhly', sms);
      final event = result.event!;

      expect(result.matchedSource, SmsSourceMatch.alAhlyBank);
      expect(event.source, FinancialSource.alAhlyBank);
      expect(event.eventType, FinancialEventType.deposit);
      expect(event.amount, 400.00);
      expect(event.person, 'أحمد محمد');
      expect(event.reference, '500000000000');
      // البنك الأهلي مبيبعتش رصيد بعد العملية في رسائله
      expect(event.balanceAfter, isNull);
    });

    test('خصم لحظي من الكارت', () {
      const sms = 'تم خصم مبلغ 144.80 جم لحظيا باستخدام شبكة المدفوعات '
          'اللحظية من بطاقتكم (مسبقة الدفع/المرتبات) عند فاتورة تليفون '
          'أرضي يوم 07-22 الساعة 15:32 مرجع التاجر 100000000000 '
          'للمزيد اتصل بـ 19623.';

      final event = SmsParser.parse('BanK-AlAhly', sms).event!;

      expect(event.eventType, FinancialEventType.purchase);
      expect(event.amount, 144.80);
      expect(event.merchant, contains('فاتورة'));
      expect(event.reference, '100000000000');
    });

    test('تحويل صادر من البطاقة', () {
      const sms = 'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 16600.00 '
          'جم إلى شخص آخر رقم مرجعي 600000000000 يوم 07-22 الساعة 13:25 '
          'للمزيد اتصل بـ 19623';

      final event = SmsParser.parse('BanK-AlAhly', sms).event!;

      expect(event.eventType, FinancialEventType.transfer);
      expect(event.amount, 16600.00);
      expect(event.person, 'شخص آخر');
      expect(event.reference, '600000000000');
    });
  });

  group('Arabic-Indic digits support', () {
    test('نفس رسالة الدفع بس بأرقام عربية هندية', () {
      const sms = 'تم دفع مبلغ ١.٠ جنيه رسوم خدمة لفودافون كاش. '
          'رصيد محفظتك الحالي ٢٩.٥٥ جنيه. رقم العملية ٠٢٢٠٠٠٦٨٣٧١٦ '
          'تاريخ العملية ٢٣-٠٧-٢٦ ٢٣:٢٨.';

      final event = SmsParser.parse('VF-Cash', sms).event!;

      expect(event.eventType, FinancialEventType.withdrawal);
      expect(event.amount, 1.0);
      expect(event.balanceAfter, 29.55);
      expect(event.reference, '022000683716');
    });
  });

  group('FinancialEvent JSON round-trip (persistence)', () {
    test('toJson -> fromJson بيحافظ على البيانات', () {
      final event = SmsParser.parse(
        'VF-Cash',
        'تم دفع مبلغ 1.0 جنيه رسوم خدمة لفودافون كاش. رصيد محفظتك الحالي '
            '29.55 جنيه. رقم العملية 022000683716 تاريخ العملية 23-07-26 23:28.',
      ).event!;

      final roundTripped = FinancialEvent.fromJson(event.toJson());

      expect(roundTripped.source, event.source);
      expect(roundTripped.eventType, event.eventType);
      expect(roundTripped.amount, event.amount);
      expect(roundTripped.balanceAfter, event.balanceAfter);
      expect(roundTripped.reference, event.reference);
      expect(roundTripped.confidence, event.confidence);
    });
  });
}
