import 'package:flutter_test/flutter_test.dart';
import 'package:trial/financial_engine/policy/source_policy.dart';
import 'package:trial/financial_engine/parser/sms_parser.dart';

void main() {
  group('SourcePolicy - Vodafone Cash: VF-Cash فقط', () {
    test('VF-Cash بأي تشكيل مقبول', () {
      expect(SourcePolicy.isVodafoneCashSender('VF-Cash'), isTrue);
      expect(SourcePolicy.isVodafoneCashSender('VFCash'), isTrue);
      expect(SourcePolicy.isVodafoneCashSender('vf cash'), isTrue);
      expect(SourcePolicy.isVodafoneCashSender('VF-CASH'), isTrue);
    });

    test('أي مرسل تاني باسم Vodafone عام مرفوض تمامًا', () {
      expect(SourcePolicy.isVodafoneCashSender('Vodafone'), isFalse);
      expect(SourcePolicy.isVodafoneCashSender('Vodafone Egypt'), isFalse);
      expect(SourcePolicy.isVodafoneCashSender('VodafoneOffers'), isFalse);
      expect(SourcePolicy.isVodafoneCashSender('Vodafone-Ads'), isFalse);
    });

    test('مرسل من Vodafone عام (مش VF-Cash) يترفض تمامًا من التصنيف كـ SMS مالي', () {
      final result = SmsParser.parse('Vodafone', 'تم إضافة مبلغ 300 جنيه إلى محفظتك.');
      expect(result.matchedSource, SmsSourceMatch.unknown);
      expect(result.event, isNull);
    });
  });

  group('SourcePolicy - البنك الأهلي', () {
    test('صيغ مختلفة لاسم المرسل مقبولة', () {
      expect(SourcePolicy.isAlAhlyBankSender('BanK-AlAhly'), isTrue);
      expect(SourcePolicy.isAlAhlyBankSender('Al-Ahly'), isTrue);
      expect(SourcePolicy.isAlAhlyBankSender('البنك الأهلي'), isTrue);
    });
  });

  group('SourcePolicy - InstaPay: إشعارات مستبعدة تمامًا', () {
    test('قبول إشعارات InstaPay في الحساب المالي ممنوع دايمًا', () {
      expect(SourcePolicy.acceptInstaPayNotificationsForAccounting(), isFalse);
    });
  });
}
