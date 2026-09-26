import 'package:flutter_test/flutter_test.dart';
import 'package:trial/financial_engine/ai/ai_parser.dart';
import 'package:trial/financial_engine/models/financial_event.dart';

void main() {
  group('AiParser.parseModelReply - تفسير رد الموديل (من غير أي اتصال شبكة)', () {
    test('رد JSON نضيف - إيداع بمبلغ واضح', () {
      const reply = '{"transactionType":"deposit","amount":300,"currency":"EGP",'
          '"wallet":"InstaPay","confidence":92}';
      final result = AiParser.parseModelReply(reply);

      expect(result, isNotNull);
      expect(result!.eventType, FinancialEventType.deposit);
      expect(result.amount, 300);
      expect(result.wallet, 'InstaPay');
      expect(result.confidence, 92);
    });

    test('رد JSON بثقة بصيغة 0-1 بدل 0-100 - بيتطبّع صح', () {
      const reply = '{"transactionType":"withdrawal","amount":150,"currency":"EGP",'
          '"wallet":"Vodafone Cash","confidence":0.85}';
      final result = AiParser.parseModelReply(reply);

      expect(result!.eventType, FinancialEventType.withdrawal);
      expect(result.confidence, 85);
    });

    test('رد فيه نص زيادة حوالين الـ JSON (مقدمة/خاتمة من الموديل) - لسه بيتفهم', () {
      const reply = 'أكيد، هيا النتيجة:\n'
          '{"transactionType":"deposit","amount":500,"currency":"EGP",'
          '"wallet":"unknown","confidence":70}\n'
          'خلصت.';
      final result = AiParser.parseModelReply(reply);

      expect(result!.eventType, FinancialEventType.deposit);
      expect(result.amount, 500);
      expect(result.wallet, isNull); // "unknown" بيترجم لـ null
      expect(result.confidence, 70);
    });

    test('رد مش JSON خالص - بيرجع null من غير ما يرمي استثناء', () {
      expect(AiParser.parseModelReply('مش قادر أفهم الرسالة دي'), isNull);
    });

    test('رد JSON فاسد (ناقص قوس) - بيرجع null', () {
      expect(AiParser.parseModelReply('{"transactionType":"deposit"'), isNull);
    });
  });

  group('AiParser.parseModelReply - الحقول الغنية الجديدة', () {
    test('رد فيه رصيد متبقي ومزوّد خدمة وأطراف المعاملة', () {
      const reply = '{"isFinancial":true,"isPromotional":false,"shouldIgnore":false,'
          '"transactionType":"deposit","amount":400,"remainingBalance":1500,'
          '"wallet":"InstaPay","provider":"البنك الأهلي","sender":"أحمد محمد",'
          '"receiver":"unknown","confidence":95}';
      final result = AiParser.parseModelReply(reply);

      expect(result!.isFinancial, isTrue);
      expect(result.remainingBalance, 1500);
      expect(result.provider, 'البنك الأهلي');
      expect(result.senderName, 'أحمد محمد');
      expect(result.receiverName, isNull); // "unknown" بيترجم لـ null
    });

    test('رد بيوضح إن الرسالة ترويجية - shouldIgnore=true', () {
      const reply = '{"isFinancial":false,"isPromotional":true,"shouldIgnore":true,'
          '"transactionType":"unknown","amount":null,"wallet":"unknown","confidence":90}';
      final result = AiParser.parseModelReply(reply);

      expect(result!.isFinancial, isFalse);
      expect(result.isPromotional, isTrue);
      expect(result.shouldIgnore, isTrue);
    });

    test('رد قديم الشكل (من غير الحقول الجديدة) لسه بيتفهم بشكل معقول', () {
      const reply = '{"transactionType":"deposit","amount":200,"wallet":"InstaPay","confidence":80}';
      final result = AiParser.parseModelReply(reply);

      expect(result!.isFinancial, isTrue); // اتحسبت من eventType/amount
      expect(result.isPromotional, isFalse); // افتراضي
      expect(result.remainingBalance, isNull);
    });
  });
}
