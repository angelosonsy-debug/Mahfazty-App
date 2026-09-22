import 'package:flutter_test/flutter_test.dart';
import 'package:trial/financial_engine/parser/semantic_classifier.dart';
import 'package:trial/financial_engine/models/financial_event.dart';

void main() {
  group('SemanticClassifier - deposit (كل عينات الإيداع من المواصفات)', () {
    final cases = [
      'تم إضافة مبلغ 300 جنيه إلى حسابك عبر InstaPay.',
      'تم استلام تحويل بمبلغ 1250 جنيه.',
      'تم تحويل مبلغ 500 جنيه إلى حسابك.',
      'تم إيداع 750.50 جنيه في حسابك.',
      'تم إضافة مبلغ 2000 جنيه إلى رصيد حسابك.',
      'Received 500 EGP through InstaPay.',
      'Incoming transfer: EGP 300.',
      'Credit: 250 EGP has been received.',
      'تم إضافة مبلغ 300 جنيه إلى حسابكم.',
      'تم إيداع مبلغ 1500 جنيه بحسابكم.',
      'Credit Alert:\nEGP 300 has been credited to your account.',
      'Credit: 2500 EGP.',
      'تم إضافة 300 جنيه إلى محفظتك.',
      'تم استلام 150 جنيه من محفظة أخرى.',
      'تم شحن محفظتك بمبلغ 500 جنيه.',
    ];

    for (final text in cases) {
      test('"$text" -> deposit', () {
        expect(SemanticClassifier.classify(text), FinancialEventType.deposit);
      });
    }
  });

  group('SemanticClassifier - withdrawal (كل عينات السحب من المواصفات)', () {
    final cases = [
      'تم تحويل مبلغ 300 جنيه من حسابك.',
      'تم خصم مبلغ 450 جنيه.',
      'تم إرسال مبلغ 1000 جنيه عبر InstaPay.',
      'تم تنفيذ تحويل بقيمة 275 جنيه.',
      'تم دفع مبلغ 95 جنيه.',
      'Transfer Sent: 500 EGP.',
      'Debit: EGP 300.',
      'تم خصم مبلغ 250 جنيه من حسابكم.',
      'تم تنفيذ عملية خصم بقيمة 980 جنيه.',
      'Debit Alert:\nEGP 300 has been debited from your account.',
      'Withdrawal: EGP 450.',
      'تم تحويل 300 جنيه من محفظتك.',
      'تم سحب مبلغ 200 جنيه من محفظتك.',
      'تم الدفع باستخدام Vodafone Cash بمبلغ 150 جنيه.',
    ];

    for (final text in cases) {
      test('"$text" -> withdrawal', () {
        expect(SemanticClassifier.classify(text), FinancialEventType.withdrawal);
      });
    }
  });

  group('SemanticClassifier - amount extraction', () {
    final cases = <String, double>{
      'تم إضافة مبلغ 300 جنيه إلى حسابك': 300,
      'تم إيداع 750.50 جنيه في حسابك': 750.50,
      'تم إضافة مبلغ ١٢٥٠ جنيه إلى رصيد حسابك': 1250,
      'تم استلام تحويل بمبلغ 1250 جنيه.': 1250, // بدون فاصلة آلاف
      'EGP 300 has been credited': 300,
      'Received 500 EGP through InstaPay': 500,
      'تم إضافة مبلغ 1,250 جنيه': 1250, // بفاصلة آلاف
    };

    cases.forEach((text, expected) {
      test('"$text" -> $expected', () {
        expect(SemanticClassifier.extractAmount(text), expected);
      });
    });
  });

  test('نص مالوش أي كلمة مالية ولا مبلغ - مفيش تصنيف', () {
    expect(SemanticClassifier.classify('تحديث تطبيق جديد متاح'), isNull);
    expect(SemanticClassifier.extractAmount('تحديث تطبيق جديد متاح'), isNull);
  });
}
