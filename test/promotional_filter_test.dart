import 'package:flutter_test/flutter_test.dart';
import 'package:trial/financial_engine/parser/promotional_filter.dart';
import 'package:trial/financial_engine/parser/notification_parser.dart';
import 'package:trial/financial_engine/parser/sms_parser.dart';

void main() {
  group('PromotionalFilter', () {
    test('رسائل ترويجية واضحة بتتصنف كترويجية', () {
      expect(PromotionalFilter.isPromotional('عرض خاص! اشترك الآن واحصل على خصم'), isTrue);
      expect(PromotionalFilter.isPromotional('جدد باقتك دلوقتي لفترة محدودة'), isTrue);
      expect(PromotionalFilter.isPromotional('Special offer just for you!'), isTrue);
    });

    test('رسالة مالية حقيقية مش بتتصنف كترويجية', () {
      expect(PromotionalFilter.isPromotional('تم إضافة مبلغ 300 جنيه إلى حسابك'), isFalse);
      expect(PromotionalFilter.isPromotional('تم خصم مبلغ 450 جنيه'), isFalse);
    });
  });

  group('NotificationParser (InstaPay) - مع فلترة الترويجي', () {
    test('إشعار ترويجي بيترفض تمامًا - مبيوصلش حتى لصندوق المراجعة', () {
      final event = NotificationParser.analyze(
        'com.instapay.app',
        'عرض خاص',
        'اشترك الآن واحصل على كاش باك يصل لـ 50 جنيه',
      );
      expect(event, isNull);
    });

    test('إشعار InstaPay مالي حقيقي بيتسجل بثقة محدودة (محتاج تطابق أو تأكيد)', () {
      final event = NotificationParser.analyze(
        'com.instapay.app',
        'InstaPay',
        'تم إضافة مبلغ 500 جنيه إلى حسابك',
      );
      expect(event, isNotNull);
      expect(event!.amount, 500);
      expect(event.confidence, lessThan(85)); // لسه محتاج تطابق/تأكيد
    });
  });

  group('SmsParser - فلترة الترويجي في الرسائل من مصادر معروفة', () {
    test('رسالة ترويجية من VF-Cash بتترفض حتى لو المرسل معروف', () {
      final result = SmsParser.parse(
        'VF-Cash',
        'عرض خاص من فودافون كاش! اشترك الآن في باقة جديدة',
      );
      expect(result.event, isNull);
    });
  });
}
