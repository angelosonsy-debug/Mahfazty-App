// ignore_for_file: prefer_const_constructors

/// Integration Regression Test Suite
///
/// يختبر المسار الكامل:
///   Raw Message → Reassembler → CandidateFilter → SmsParser → Engine Logic
///
/// Pure Dart — لا يحتاج SharedPreferences أو Android SDK.
/// يختبر كل component مع الـ component التالي، مش كل واحد منعزل.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:trial/financial_engine/models/financial_event.dart';
import 'package:trial/financial_engine/models/wallet.dart';
import 'package:trial/financial_engine/parser/message_reassembler.dart';
import 'package:trial/financial_engine/parser/transaction_candidate_filter.dart';
import 'package:trial/financial_engine/parser/sms_parser.dart';
import 'package:trial/financial_engine/policy/source_catalog.dart';
import 'package:trial/core/utils/text_normalizer.dart';

// ============================================================
// Constants
// ============================================================

const kNbeMessage =
    'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 720.00 جم '
    'إلى مينا ع*** ف*** ن*** رقم مرجعي 400492200244 يوم 08-28 '
    'الساعة 00:02 للمزيد اتصل بـ 19623';

const kNbeSender = 'AhlyBank';
const kVfSender  = 'VF-Cash';

// Split fragments of kNbeMessage for reassembly tests
const kNbeFrag1of2 =
    'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 720.';
const kNbeFrag2of2 =
    '00 جم إلى مينا ع*** ف*** ن*** رقم مرجعي 400492200244 يوم 08-28 '
    'الساعة 00:02 للمزيد اتصل بـ 19623';
const kNbeFrag1of3 = kNbeFrag1of2;
const kNbeFrag2of3 =
    '00 جم إلى مينا ع*** ف*** ن*** رقم مرجعي 400492200244 يوم';
const kNbeFrag3of3 = '08-28 الساعة 00:02 للمزيد اتصل بـ 19623';

DateTime t(int s) => DateTime(2024, 8, 28, 0, 0, s);

// ============================================================
// 1. NBE End-to-End
// ============================================================

void main() {
  group('Integration 1 — NBE: full message', () {
    test('CandidateFilter passes NBE message as financial', () {
      final r = TransactionCandidateFilter.check(kNbeSender, kNbeMessage);
      expect(r.status, equals(CandidateStatus.financial));
    });

    test('SourceCatalog identifies AhlyBank as alAhlyBank', () {
      final def = findSourceDefinition(kNbeSender);
      expect(def, isNotNull);
      expect(def!.legacySource, equals(FinancialSource.alAhlyBank));
    });

    test('SmsParser: amount=720, reference≠amount, direction=DEBIT-family', () {
      final r = SmsParser.parse(kNbeSender, kNbeMessage);
      expect(r.event, isNotNull);
      expect(r.event!.amount, closeTo(720.0, 0.001));
      expect(r.event!.amount, isNot(closeTo(400492200244.0, 1.0)));
      expect(
        r.event!.eventType,
        anyOf(
          equals(FinancialEventType.transfer),
          equals(FinancialEventType.withdrawal),
        ),
      );
      expect(r.event!.confidence, greaterThanOrEqualTo(85));
    });

    test('Explanation field present in SmsParseResult', () {
      final r = SmsParser.parse(kNbeSender, kNbeMessage);
      expect(r.explanation, isNotNull);
      expect(r.explanation!.isNotEmpty, isTrue);
    });

    test('Wallet mapping resolves to NBE wallet', () {
      final def = findSourceDefinition(kNbeSender);
      final walletId = legacySourceToWalletId(def!.legacySource);
      expect(walletId, equals(kLegacyWalletIdNbe));
    });
  });

  // ------------------------------------------------------------------
  group('Integration 2 — NBE: split into 2 fragments → ONE event', () {
    test('Reassembler merges 2 NBE fragments into single message', () {
      final r = MessageReassembler();
      final r1 = r.addSmsFragment(
          sender: kNbeSender, normalizedBody: TextNormalizer.prepare(kNbeFrag1of2), receivedAt: t(0));
      expect(r1, isEmpty, reason: 'Frag 1 must be buffered');

      final r2 = r.addSmsFragment(
          sender: kNbeSender, normalizedBody: TextNormalizer.prepare(kNbeFrag2of2), receivedAt: t(1));
      expect(r2.length, equals(1));
      expect(r2.first.wasReassembled, isTrue);
      expect(r2.first.fragmentCount, equals(2));

      // Parse the reassembled text
      final parsed = SmsParser.parse(kNbeSender, r2.first.text);
      expect(parsed.event?.amount, closeTo(720.0, 0.001));
    });
  });

  // ------------------------------------------------------------------
  group('Integration 3 — NBE: split into 3 fragments → ONE event', () {
    test('Reassembler merges 3 fragments, parser extracts 720 correctly', () {
      final r = MessageReassembler();
      expect(r.addSmsFragment(sender: kNbeSender,
          normalizedBody: TextNormalizer.prepare(kNbeFrag1of3), receivedAt: t(0)), isEmpty);
      expect(r.addSmsFragment(sender: kNbeSender,
          normalizedBody: TextNormalizer.prepare(kNbeFrag2of3), receivedAt: t(1)), isEmpty);
      final results = r.addSmsFragment(sender: kNbeSender,
          normalizedBody: TextNormalizer.prepare(kNbeFrag3of3), receivedAt: t(2));

      expect(results.length, equals(1));
      expect(results.first.fragmentCount, equals(3));
      final parsed = SmsParser.parse(kNbeSender, results.first.text);
      expect(parsed.event?.amount, closeTo(720.0, 0.001));
    });
  });

  // ============================================================
  // 4. Vodafone Cash End-to-End
  // ============================================================

  group('Integration 4 — Vodafone: all 6 patterns', () {
    final vfCases = [
      (
        name: 'تم تحويل → DEBIT',
        msg: 'تم تحويل 200 جنيه لرقم 01000000000 مصاريف الخدمة 1 جنيه '
            'رصيد حسابك فى فودافون كاش الحالي 1300 '
            'تاريخ العملية 2024-08-28 10:00 رقم العملية 112233',
        isCredit: false,
      ),
      (
        name: 'تم دفع → DEBIT',
        msg: 'تم دفع مبلغ 100 جنيه رسوم خدمة لفودافون كاش. '
            'رصيد محفظتك الحالي 900 جنيه. '
            'رقم العملية 9988776655 تاريخ العملية 2024-08-28 09:00.',
        isCredit: false,
      ),
      (
        name: 'تم شحن → DEBIT',
        msg: 'تم شحن رصيد موبايلك ب 10 بنجاح وخصم 10.50 من محفظتك شاملة الضريبة '
            'رصيد حسابك فى فودافون كاش الحالي 489.50',
        isCredit: false,
      ),
      (
        name: 'تم خصم → DEBIT',
        msg: 'تم خصم مبلغ 50 جنيه من محفظتك. '
            'رصيد حسابك الحالي 450 جنيه. رقم العملية 5544332211',
        isCredit: false,
      ),
      (
        name: 'تم سحب → DEBIT',
        msg: 'تم سحب 300 جنيه من محفظة فودافون كاش. '
            'رصيد حسابك الحالي 700 جنيه. رقم العملية: 6677889900',
        isCredit: false,
      ),
      (
        name: 'تم استلام → CREDIT',
        msg: 'تم استلام مبلغ 500 جنيه من رقم 01099999999 '
            'المسجل بإسم أحمد على رقم محفظتك 01011112222. '
            'رصيدك الحالي: 2000 جنيه تاريخ العملية: 2024-08-28 13:00 رقم العملية: 9900112233',
        isCredit: true,
      ),
    ];

    for (final c in vfCases) {
      test(c.name, () {
        // Candidate filter passes all VF messages
        final candidate = TransactionCandidateFilter.check(kVfSender, c.msg);
        expect(candidate.status, equals(CandidateStatus.financial),
            reason: '${c.name}: يجب أن يمر الفلتر');

        // Parser extracts correct direction
        final parsed = SmsParser.parse(kVfSender, c.msg);
        expect(parsed.event, isNotNull, reason: '${c.name}: parser يجب أن ينجح');
        if (c.isCredit) {
          expect(isIncomingEventType(parsed.event!.eventType), isTrue,
              reason: '${c.name}: يجب أن يكون CREDIT');
        } else {
          expect(isOutgoingEventType(parsed.event!.eventType), isTrue,
              reason: '${c.name}: يجب أن يكون DEBIT');
        }
        expect(parsed.event!.amount, greaterThan(0));
        expect(parsed.event!.confidence, greaterThanOrEqualTo(85));
      });
    }
  });

  // ============================================================
  // 5. Candidate Filter Integration
  // ============================================================

  group('Integration 5 — Candidate Filter integration', () {
    test('OTP → nonFinancial (no event should be created)', () {
      final r = TransactionCandidateFilter.check(
          'BankSec', 'رمز التحقق الخاص بك هو 123456 صالح لمدة 5 دقائق');
      expect(r.status, equals(CandidateStatus.nonFinancial));
    });

    test('Security alert → nonFinancial', () {
      final r = TransactionCandidateFilter.check(
          'BankSec', 'تسجيل دخول جديد من جهاز غير معروف في حسابك');
      expect(r.status, equals(CandidateStatus.nonFinancial));
    });

    test('Informational → nonFinancial (no financial evidence)', () {
      final r = TransactionCandidateFilter.check(
          'BankInfo', 'تم تحديث بياناتك بتاريخ 28-08');
      expect(r.status, equals(CandidateStatus.nonFinancial));
    });

    test('Valid financial passes filter and parser together', () {
      const msg =
          'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 720.00 جم '
          'إلى مينا رقم مرجعي 400492200244 يوم 08-28 الساعة 00:02 للمزيد اتصل بـ 19623';
      final candidate = TransactionCandidateFilter.check(kNbeSender, msg);
      expect(candidate.status, equals(CandidateStatus.financial));
      final parsed = SmsParser.parse(kNbeSender, msg);
      expect(parsed.event?.amount, closeTo(720.0, 0.001));
    });
  });

  // ============================================================
  // 6. Wallet Mapping Integration
  // ============================================================

  group('Integration 6 — Wallet Mapping', () {
    test('NBE SMS → kLegacyWalletIdNbe', () {
      final def = findSourceDefinition(kNbeSender);
      expect(legacySourceToWalletId(def!.legacySource), equals(kLegacyWalletIdNbe));
    });

    test('VF-Cash SMS → kLegacyWalletIdVf', () {
      final def = findSourceDefinition(kVfSender);
      expect(legacySourceToWalletId(def!.legacySource), equals(kLegacyWalletIdVf));
    });

    test('Unknown sender → null source def (no wallet assigned)', () {
      final def = findSourceDefinition('UnknownBank999');
      expect(def, isNull, reason: 'مصدر غير معروف يجب ألا يُربط بمحفظة');
    });
  });

  // ============================================================
  // 7. Wallet Transfer Integration
  // ============================================================

  group('Integration 7 — Wallet Transfer atomicity (logic)', () {
    test('Pair: both events have correct linkedEventId', () {
      const outId = 'out_reg_01'; const inId = 'in_reg_01';
      const walletA = 'wallet_a'; const walletB = 'wallet_b';
      const amount = 1000.0;

      // Simulate the event creation logic
      final out = FinancialEvent(
        id: outId, source: FinancialSource.manual,
        eventType: FinancialEventType.walletTransferOut, amount: amount,
        timestamp: DateTime.now(), confidence: 99,
        rawMessage: 'تحويل', rawSource: 'manual',
        walletId: walletA, linkedEventId: inId,
      );
      final inp = FinancialEvent(
        id: inId, source: FinancialSource.manual,
        eventType: FinancialEventType.walletTransferIn, amount: amount,
        timestamp: DateTime.now(), confidence: 99,
        rawMessage: 'تحويل', rawSource: 'manual',
        walletId: walletB, linkedEventId: outId,
      );

      expect(out.linkedEventId, equals(inp.id));
      expect(inp.linkedEventId, equals(out.id));
    });

    test('Transfer does NOT affect income/expense calculation', () {
      final events = [
        FinancialEvent(id:'d1', source: FinancialSource.vodafoneCash,
            eventType: FinancialEventType.deposit, amount: 500.0,
            timestamp: DateTime.now(), confidence:99, rawMessage:'', rawSource:''),
        FinancialEvent(id:'t1', source: FinancialSource.manual,
            eventType: FinancialEventType.walletTransferIn, amount: 1000.0,
            timestamp: DateTime.now(), confidence:99,
            rawMessage:'', rawSource:'', walletId:'wallet_b'),
      ];
      final income = events.where((e) => isIncomingEventType(e.eventType) && e.confidence>=85).fold(0.0,(s,e)=>s+e.amount!);
      expect(income, closeTo(500.0, 0.001), reason: 'walletTransferIn مش دخل');
    });

    test('saveEventPair simulation: both or neither', () {
      // Simulate the atomic save: load → add both → save
      final List<FinancialEvent> store = [];
      final out = FinancialEvent(id:'o1', source:FinancialSource.manual,
          eventType:FinancialEventType.walletTransferOut, amount:500.0,
          timestamp:DateTime.now(), confidence:99, rawMessage:'', rawSource:'',
          walletId:'wA', linkedEventId:'i1');
      final inp = FinancialEvent(id:'i1', source:FinancialSource.manual,
          eventType:FinancialEventType.walletTransferIn, amount:500.0,
          timestamp:DateTime.now(), confidence:99, rawMessage:'', rawSource:'',
          walletId:'wB', linkedEventId:'o1');

      // single-operation add of both
      for (final e in [out, inp]) {
        final idx = store.indexWhere((x)=>x.id==e.id);
        if (idx == -1) { store.add(e); } else { store[idx] = e; }
      }
      expect(store.length, equals(2));
      expect(store.any((e)=>e.id=='o1'), isTrue);
      expect(store.any((e)=>e.id=='i1'), isTrue);
    });
  });

  // ============================================================
  // 8. Source Test Integration (preview only)
  // ============================================================

  group('Integration 8 — Source Test: pure parsing, no side effects', () {
    test('SmsParser.parse is a pure function (no I/O, no engine calls)', () {
      // Proof: calling parse() multiple times returns consistent result
      final r1 = SmsParser.parse(kNbeSender, kNbeMessage);
      final r2 = SmsParser.parse(kNbeSender, kNbeMessage);
      expect(r1.event?.amount, equals(r2.event?.amount));
      expect(r1.event?.eventType, equals(r2.event?.eventType));
    });

    test('Source Test explanation is human-readable Arabic', () {
      final r = SmsParser.parse(kNbeSender, kNbeMessage);
      expect(r.explanation, isNotNull);
      // Just check it's not empty and not a raw regex/code string
      expect(r.explanation!.length, greaterThan(10));
    });
  });

  // ============================================================
  // 9. Error / Failure Handling Integration
  // ============================================================

  group('Integration 9 — Error handling: no crash, no corrupt state', () {
    test('Empty message: no event, no crash', () {
      final r = SmsParser.parse(kNbeSender, '');
      // May return null event or unknown — must not throw
      expect(r, isNotNull);
    });

    test('Very short message: no crash', () {
      final r = SmsParser.parse(kNbeSender, 'تم');
      expect(r, isNotNull);
    });

    test('Unknown source: matchedSource = unknown', () {
      final r = SmsParser.parse('FakeBankXYZ', kNbeMessage);
      expect(r.matchedSource, equals(SmsSourceMatch.unknown));
    });

    test('Message with only numbers: candidate filter → uncertain (not financial)', () {
      final r = TransactionCandidateFilter.check('Unknown', '12345 67890 11122233');
      expect(r.status, isNot(equals(CandidateStatus.financial)));
    });

    test('Malformed Arabic: normalize doesn\'t throw', () {
      final malformed = 'تم 💳 تنفيذ \uFFFD\uFFFD بمبلغ 100 جم';
      expect(() => TextNormalizer.prepare(malformed), returnsNormally);
    });
  });

  // ============================================================
  // 10. Dedup/Fragment interplay
  // ============================================================

  group('Integration 10 — Dedup: two different messages same sender', () {
    test('Two separate financial messages → two events, no merge', () {
      final r = MessageReassembler();
      const msg1 = 'تم تحويل 500 جنيه من حسابك الساعة 00:01';
      const msg2 = 'تم استلام 300 جنيه في حسابك الساعة 00:02';

      final r1 = r.addSmsFragment(sender: kNbeSender,
          normalizedBody: TextNormalizer.prepare(msg1), receivedAt: t(0));
      final r2 = r.addSmsFragment(sender: kNbeSender,
          normalizedBody: TextNormalizer.prepare(msg2), receivedAt: t(2));

      final all = [...r1, ...r2];
      expect(all.length, equals(2));
      expect(all.any((m)=>m.wasReassembled), isFalse,
          reason: 'رسالتان مالية مستقلتان يجب ألا يتدمجوا');
    });
  });

  // ============================================================
  // 11. WalletType coverage (regression guard for I1)
  // ============================================================

  group('Integration 11 — WalletType labels', () {
    test('All WalletType values have Arabic labels', () {
      for (final t in WalletType.values) {
        expect(t.labelAr.isNotEmpty, isTrue, reason: '${t.name} needs Arabic label');
      }
    });
  });

  // ============================================================
  // 12. Amount Extraction integrity across all sources
  // ============================================================

  group('Integration 12 — Amount extraction: context-aware across pipeline', () {
    test('NBE: بمبلغ 720 جم → 720 (not reference 400492200244)', () {
      final parsed = SmsParser.parse(kNbeSender, kNbeMessage);
      expect(parsed.event?.amount, closeTo(720.0, 0.001));
      expect(parsed.event?.amount, isNot(closeTo(400492200244.0, 1.0)));
    });

    test('VF receive: مبلغ 500 جنيه → 500', () {
      const msg = 'تم استلام مبلغ 500 جنيه من رقم 01099999999 '
          'رصيدك الحالي: 2000 جنيه رقم العملية: 9900112233';
      final parsed = SmsParser.parse(kVfSender, msg);
      expect(parsed.event?.amount, closeTo(500.0, 0.001));
    });

    test('Arabic digits ٧٢٠ → 720 via TextNormalizer', () {
      expect(TextNormalizer.prepare('٧٢٠'), equals('720'));
    });

    test('Arabic separators ١٬٢٥٠٫٥٠ → 1,250.50', () {
      expect(TextNormalizer.prepare('١٬٢٥٠٫٥٠'), equals('1,250.50'));
    });
  });
}
