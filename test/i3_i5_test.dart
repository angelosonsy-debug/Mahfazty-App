// ignore_for_file: prefer_const_constructors, lines_longer_than_80_chars

/// اختبارات I3 (Amount Extraction) + I5 (Vodafone Cash Templates)
///
/// Pure Dart — يتشغّل بـ `dart test test/i3_i5_test.dart` بدون Flutter SDK.
///
/// معيار النجاح المطلوب:
///   NBE:      "تم تنفيذ تحويل ... بمبلغ 720.00 جم" → DEBIT / 720
///   Vodafone: "تم دفع ... مبلغ 100 جنيه"         → DEBIT / 100
///   Vodafone: "تم استلام ... مبلغ 500 جنيه"       → CREDIT / 500
///   مع عدم الخلط بين Amount / Reference / Phone / Date / Time
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:trial/core/utils/text_normalizer.dart';
import 'package:trial/financial_engine/parser/semantic_classifier.dart';
import 'package:trial/financial_engine/parser/sms_templates.dart';
import 'package:trial/financial_engine/parser/sms_parser.dart';
import 'package:trial/financial_engine/models/financial_event.dart';

// ============================================================
// Helpers
// ============================================================

const _nbeSender = 'AhlyBank';
const _vfSender = 'VF-Cash';

TemplateExtraction? _matchTemplate(List<SmsTemplate> templates, String text) {
  final normalized = TextNormalizer.prepare(text);
  for (final t in templates) {
    final m = t.pattern.firstMatch(normalized);
    if (m != null) return t.build(m);
  }
  return null;
}

// ============================================================
// I3 — Amount Extraction Tests
// ============================================================

void main() {
  // ------------------------------------------------------------------
  group('I3 — TextNormalizer: Arabic separator support', () {
    test('Arabic digits convert correctly', () {
      expect(TextNormalizer.prepare('٧٢٠'), equals('720'));
      expect(TextNormalizer.prepare('١٢٥٠'), equals('1250'));
    });

    test('Arabic thousands separator ٬ → comma', () {
      final result = TextNormalizer.prepare('١٬٢٥٠');
      expect(result, equals('1,250'));
    });

    test('Arabic decimal separator ٫ → period', () {
      final result = TextNormalizer.prepare('٧٢٠٫٠٠');
      expect(result, equals('720.00'));
    });

    test('Full Arabic amount: ١٬٢٥٠٫٥٠ جنيه → 1250.50', () {
      final amount = SemanticClassifier.extractAmount('١٬٢٥٠٫٥٠ جنيه');
      expect(amount, closeTo(1250.50, 0.001));
    });
  });

  // ------------------------------------------------------------------
  // Test 7 — "720.00 جم"
  group('I3 — Amount: Test 7 — "720.00 جم"', () {
    test('extractAmount finds 720.00 with جم currency', () {
      final amount = SemanticClassifier.extractAmount('بمبلغ 720.00 جم');
      expect(amount, closeTo(720.00, 0.001));
    });

    test('جم supported in currency-word fallback (no marker)', () {
      final amount = SemanticClassifier.extractAmount('مبلغ محوّل 720.00 جم');
      expect(amount, closeTo(720.00, 0.001));
    });
  });

  // ------------------------------------------------------------------
  // Test 8 — "720 جم"
  group('I3 — Amount: Test 8 — "720 جم"', () {
    test('extractAmount finds 720 (integer) with جم', () {
      final amount = SemanticClassifier.extractAmount('خصم 720 جم');
      expect(amount, closeTo(720.0, 0.001));
    });
  });

  // ------------------------------------------------------------------
  // Test 9 — Arabic digits "٧٢٠ جم"
  group('I3 — Amount: Test 9 — "٧٢٠ جم"', () {
    test('Arabic digits + جم = 720.0', () {
      final amount = SemanticClassifier.extractAmount('بمبلغ ٧٢٠ جم');
      expect(amount, closeTo(720.0, 0.001));
    });

    test('Arabic digits + جنيه = 720.0', () {
      final amount = SemanticClassifier.extractAmount('مبلغ ٧٢٠ جنيه');
      expect(amount, closeTo(720.0, 0.001));
    });
  });

  // ------------------------------------------------------------------
  // Test 10 — "١٬٢٥٠٫٥٠ جنيه"
  group('I3 — Amount: Test 10 — "١٬٢٥٠٫٥٠ جنيه"', () {
    test('Arabic format with separators = 1250.50', () {
      final amount = SemanticClassifier.extractAmount('١٬٢٥٠٫٥٠ جنيه');
      expect(amount, closeTo(1250.50, 0.001));
    });

    test('Latin format 1,250.50 جنيه = 1250.50', () {
      final amount = SemanticClassifier.extractAmount('1,250.50 جنيه');
      expect(amount, closeTo(1250.50, 0.001));
    });
  });

  // ------------------------------------------------------------------
  // Test 11 — رسالة فيها amount + reference number (المبلغ لازم يُختار)
  group('I3 — Amount: Test 11 — context-aware (amount ≠ reference)', () {
    const nbeMessage =
        'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 720.00 جم '
        'إلى مينا ع*** ف*** ن*** رقم مرجعي 400492200244 يوم 08-28 '
        'الساعة 00:02 للمزيد اتصل بـ 19623';

    test('NBE: يستخرج 720 وليس الرقم المرجعي 400492200244', () {
      final amount = SemanticClassifier.extractAmount(nbeMessage);
      expect(amount, closeTo(720.0, 0.001),
          reason: 'يجب أخذ المبلغ بعد "بمبلغ" وليس الرقم المرجعي');
      expect(amount, isNot(closeTo(400492200244.0, 1.0)),
          reason: 'الرقم المرجعي لا يجب أن يُعتبر مبلغًا');
    });

    test('المبلغ بعد marker أولوية على أي رقم آخر في الرسالة', () {
      const msg = 'رقم العملية 9876543210 بمبلغ 150 جنيه تاريخ 2024-08-28';
      final amount = SemanticClassifier.extractAmount(msg);
      expect(amount, closeTo(150.0, 0.001));
      expect(amount, isNot(closeTo(9876543210.0, 1.0)));
    });
  });

  // ------------------------------------------------------------------
  // Test 12 — رسالة فيها phone / date / time
  group('I3 — Amount: Test 12 — رسالة فيها phone وdate وtime', () {
    test('يستخرج المبلغ الصحيح مش رقم الهاتف أو التاريخ', () {
      const msg =
          'تم استلام مبلغ 500 جنيه من رقم 01012345678 '
          'تاريخ العملية 2024-08-28 10:30 رقم العملية 1122334455';
      final amount = SemanticClassifier.extractAmount(msg);
      expect(amount, closeTo(500.0, 0.001));
    });
  });

  // ------------------------------------------------------------------
  // Test 13 — رسالة بدون مبلغ
  group('I3 — Amount: Test 13 — رسالة بدون مبلغ مالي', () {
    test('رسالة OTP — لا يوجد مبلغ', () {
      const msg = 'رمز التحقق الخاص بك هو 123456 صالح لمدة 5 دقائق';
      final amount = SemanticClassifier.extractAmount(msg);
      expect(amount, isNull,
          reason: 'رقم بدون كلمة عملة لا يُعتبر مبلغًا');
    });

    test('رسالة ترويجية بأرقام — لا مبلغ مالي', () {
      const msg = 'عرض خاص: 50 دقيقة مجانية و100 رسالة لمدة 7 أيام';
      final amount = SemanticClassifier.extractAmount(msg);
      expect(amount, isNull);
    });
  });

  // ------------------------------------------------------------------
  // Test 14 — رسالة فيها أرقام وليست معاملة مالية
  group('I3 — Amount: Test 14 — أرقام بدون سياق مالي', () {
    test('تاريخ وساعة ورقم مرجعي فقط → لا مبلغ', () {
      const msg =
          'تأكيد: تاريخ 2024-08-28، الساعة 12:00، رقم الطلب 99887766';
      final amount = SemanticClassifier.extractAmount(msg);
      expect(amount, isNull);
    });
  });

  // ------------------------------------------------------------------
  // Test: Currency markers المطلوبة كلها مدعومة
  group('I3 — Amount: دعم كل الـ currency markers', () {
    final cases = {
      'جم':     '720 جم',
      'جنيه':   '720 جنيه',
      'جنيها':  '720 جنيها',
      'جنيهًا': '720 جنيهًا',
      'EGP':    '720 EGP',
      'LE':     '720 LE',
      'ج.م':    '720 ج.م',
    };

    cases.forEach((marker, text) {
      test('$marker مدعوم', () {
        final amount = SemanticClassifier.extractAmount(text);
        expect(amount, closeTo(720.0, 0.001),
            reason: 'يجب دعم $marker كـ currency marker');
      });
    });
  });

  // ============================================================
  // I5 — Vodafone Cash Templates
  // ============================================================

  // ------------------------------------------------------------------
  // Test 1 — تم تحويل
  group('I5 — VF: Test 1 — تم تحويل → DEBIT', () {
    test('vf_transfer_out matches تم تحويل', () {
      const msg =
          'تم تحويل 200 جنيه لرقم 01000000000 '
          'مصاريف الخدمة 1 جنيه رصيد حسابك فى فودافون كاش الحالي 1300 '
          'تاريخ العملية 2024-08-28 10:00 رقم العملية 112233';
      final r = _matchTemplate(vodafoneCashTemplates, msg);
      expect(r, isNotNull);
      expect(r!.eventType, equals(FinancialEventType.transfer));
      expect(r.amount, closeTo(200.0, 0.001));
    });
  });

  // ------------------------------------------------------------------
  // Test 2 — تم دفع
  group('I5 — VF: Test 2 — تم دفع → DEBIT', () {
    test('vf_payment matches تم دفع رسوم خدمة', () {
      const msg =
          'تم دفع مبلغ 100 جنيه رسوم خدمة لفودافون كاش. '
          'رصيد محفظتك الحالي 900 جنيه. '
          'رقم العملية 9988776655 تاريخ العملية 2024-08-28 09:00.';
      final r = _matchTemplate(vodafoneCashTemplates, msg);
      expect(r, isNotNull);
      expect(r!.eventType, equals(FinancialEventType.withdrawal));
      expect(r.amount, closeTo(100.0, 0.001));
    });

    test('DEBIT direction confirmed for تم دفع', () {
      final type = SemanticClassifier.classify('تم دفع مبلغ 100 جنيه');
      expect(type, equals(FinancialEventType.withdrawal));
    });
  });

  // ------------------------------------------------------------------
  // Test 3 — تم شحن
  group('I5 — VF: Test 3 — تم شحن → DEBIT', () {
    test('vf_recharge matches تم شحن', () {
      const msg =
          'تم شحن رصيد موبايلك ب 10 بنجاح وخصم 10.50 من محفظتك شاملة الضريبة '
          'رصيد حسابك فى فودافون كاش الحالي 489.50';
      final r = _matchTemplate(vodafoneCashTemplates, msg);
      expect(r, isNotNull);
      expect(r!.eventType, equals(FinancialEventType.purchase));
      expect(r.amount, closeTo(10.50, 0.001));
    });

    test('SemanticClassifier: تم شحن = withdrawal keyword', () {
      expect(
        SemanticClassifier.classify('تم شحن رصيد'),
        anyOf(equals(FinancialEventType.withdrawal), isNull),
        reason: 'تم شحن إما يُصنَّف سحب أو يُترك للـ template',
      );
    });
  });

  // ------------------------------------------------------------------
  // Test 4 — تم خصم (I5 — النمط الجديد)
  group('I5 — VF: Test 4 — تم خصم → DEBIT (vf_debit_general)', () {
    test('vf_debit_general template matches تم خصم', () {
      const msg =
          'تم خصم مبلغ 50 جنيه من محفظتك. '
          'رصيد حسابك الحالي 450 جنيه. '
          'رقم العملية 5544332211';
      final r = _matchTemplate(vodafoneCashTemplates, msg);
      expect(r, isNotNull, reason: 'vf_debit_general يجب أن يطابق "تم خصم"');
      expect(r!.eventType, isNotNull);
      expect(r.eventType, equals(FinancialEventType.withdrawal));
      expect(r.amount, closeTo(50.0, 0.001));
    });

    test('تم خصم بدون مبلغ keyword', () {
      const msg = 'تم خصم 75 جنيه كرسوم اشتراك';
      final r = _matchTemplate(vodafoneCashTemplates, msg);
      expect(r, isNotNull);
      expect(r!.eventType, equals(FinancialEventType.withdrawal));
      expect(r.amount, closeTo(75.0, 0.001));
    });

    test('SemanticClassifier: تم خصم = withdrawal', () {
      final type = SemanticClassifier.classify('تم خصم 50 جنيه');
      expect(type, equals(FinancialEventType.withdrawal));
    });
  });

  // ------------------------------------------------------------------
  // Test 5 — تم سحب
  group('I5 — VF: Test 5 — تم سحب → DEBIT', () {
    test('vf_withdraw_atm matches تم سحب', () {
      const msg =
          'تم سحب 300 جنيه من محفظة فودافون كاش. '
          'رصيد حسابك الحالي 700 جنيه. '
          'تاريخ العملية 2024-08-28 11:00 رقم العملية: 6677889900';
      final r = _matchTemplate(vodafoneCashTemplates, msg);
      expect(r, isNotNull);
      expect(r!.eventType, equals(FinancialEventType.withdrawal));
      expect(r.amount, closeTo(300.0, 0.001));
    });
  });

  // ------------------------------------------------------------------
  // Test 6 — تم استلام → CREDIT
  group('I5 — VF: Test 6 — تم استلام → CREDIT', () {
    test('vf_receive matches تم استلام', () {
      const msg =
          'تم استلام مبلغ 500 جنيه من رقم 01099999999 '
          'المسجل بإسم محمد على على رقم محفظتك 01011112222. '
          'رصيدك الحالي: 1500 جنيه '
          'تاريخ العملية: 2024-08-28 12:00 رقم العملية: 7788990011';
      final r = _matchTemplate(vodafoneCashTemplates, msg);
      expect(r, isNotNull);
      expect(r!.eventType, equals(FinancialEventType.deposit));
      expect(r.amount, closeTo(500.0, 0.001));
    });

    test('SemanticClassifier: تم استلام = deposit', () {
      final type = SemanticClassifier.classify('تم استلام مبلغ 500 جنيه');
      expect(type, equals(FinancialEventType.deposit));
    });
  });

  // ============================================================
  // Integration — SmsParser end-to-end
  // ============================================================

  group('Integration — SmsParser معيار النجاح الرسمي', () {
    test('NBE: بمبلغ 720.00 جم → DEBIT / 720 (مش الرقم المرجعي)', () {
      const msg =
          'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 720.00 جم '
          'إلى مينا ع*** ف*** ن*** رقم مرجعي 400492200244 يوم 08-28 '
          'الساعة 00:02 للمزيد اتصل بـ 19623';
      final result = SmsParser.parse(_nbeSender, msg);
      expect(result.event, isNotNull, reason: 'يجب أن ينشئ FinancialEvent');
      expect(result.event!.amount, closeTo(720.0, 0.001),
          reason: 'المبلغ 720 وليس الرقم المرجعي 400492200244');
      expect(
        result.event!.eventType,
        anyOf(
          equals(FinancialEventType.transfer),
          equals(FinancialEventType.withdrawal),
        ),
        reason: 'DEBIT direction',
      );
    });

    test('Vodafone: تم دفع مبلغ 100 جنيه → DEBIT / 100', () {
      const msg =
          'تم دفع مبلغ 100 جنيه رسوم خدمة لفودافون كاش. '
          'رصيد محفظتك الحالي 900 جنيه. '
          'رقم العملية 1234567890 تاريخ العملية 2024-08-28 08:00.';
      final result = SmsParser.parse(_vfSender, msg);
      expect(result.event, isNotNull);
      expect(result.event!.amount, closeTo(100.0, 0.001));
      expect(result.event!.eventType, equals(FinancialEventType.withdrawal));
    });

    test('Vodafone: تم استلام مبلغ 500 جنيه → CREDIT / 500', () {
      const msg =
          'تم استلام مبلغ 500 جنيه من رقم 01099999999 '
          'المسجل بإسم أحمد محمود على رقم محفظتك 01011112222. '
          'رصيدك الحالي: 2000 جنيه '
          'تاريخ العملية: 2024-08-28 13:00 رقم العملية: 9900112233';
      final result = SmsParser.parse(_vfSender, msg);
      expect(result.event, isNotNull);
      expect(result.event!.amount, closeTo(500.0, 0.001));
      expect(result.event!.eventType, equals(FinancialEventType.deposit));
    });

    test('Vodafone: تم خصم 50 جنيه → DEBIT / 50 (new vf_debit_general)', () {
      const msg =
          'تم خصم مبلغ 50 جنيه من محفظتك. '
          'رصيد حسابك الحالي 450 جنيه. '
          'رقم العملية 5544332211';
      final result = SmsParser.parse(_vfSender, msg);
      expect(result.event, isNotNull);
      expect(result.event!.amount, closeTo(50.0, 0.001));
      expect(result.event!.eventType, equals(FinancialEventType.withdrawal));
    });
  });

  // ============================================================
  // Regression guard: direction semantics are consistent
  // ============================================================

  group('Regression: DEBIT/CREDIT semantics unchanged', () {
    test('تم تحويل (VF) = DEBIT not CREDIT', () {
      final type = SemanticClassifier.classify('تم تحويل من حسابك');
      expect(type, isNot(equals(FinancialEventType.deposit)));
    });

    test('تم استلام (VF) = CREDIT not DEBIT', () {
      final type = SemanticClassifier.classify('تم استلام مبلغ 500 جنيه');
      expect(type, equals(FinancialEventType.deposit));
    });

    test('تم دفع = DEBIT (withdrawal)', () {
      final type = SemanticClassifier.classify('تم دفع مبلغ من حسابك');
      expect(type, equals(FinancialEventType.withdrawal));
    });

    test('تم سحب = DEBIT (withdrawal)', () {
      final type = SemanticClassifier.classify('تم سحب 300 جنيه');
      expect(type, equals(FinancialEventType.withdrawal));
    });
  });
}
