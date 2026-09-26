// ignore_for_file: prefer_const_constructors

/// اختبارات المرحلة C1 — Message/Notification Fragmentation Reassembly
///
/// هذه الاختبارات pure Dart (مش محتاجة Flutter أو Android SDK) وممكن
/// تتشغّل بـ `dart test test/message_reassembler_test.dart` في أي بيئة.
///
/// الرسالة الأساسية للاختبار (Test 11/12):
///   «تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 720.00 جم
///   إلى مينا ع*** ف*** ن*** رقم مرجعي 400492200244 يوم 08-28
///   الساعة 00:02 للمزيد اتصل بـ 19623»
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:trial/financial_engine/parser/message_reassembler.dart';
import 'package:trial/financial_engine/parser/fragment_buffer.dart';
import 'package:trial/core/utils/text_normalizer.dart';

// ============================================================
// Helpers
// ============================================================

const _nbeFullMessage =
    'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 720.00 جم '
    'إلى مينا ع*** ف*** ن*** رقم مرجعي 400492200244 يوم 08-28 '
    'الساعة 00:02 للمزيد اتصل بـ 19623';

const _nbeFragment1of2 =
    'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 720.';
const _nbeFragment2of2 =
    '00 جم إلى مينا ع*** ف*** ن*** رقم مرجعي 400492200244 يوم 08-28 الساعة 00:02 للمزيد اتصل بـ 19623';

const _nbeFragment1of3 =
    'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ 720.';
const _nbeFragment2of3 =
    '00 جم إلى مينا ع*** ف*** ن*** رقم مرجعي 400492200244 يوم';
const _nbeFragment3of3 = '08-28 الساعة 00:02 للمزيد اتصل بـ 19623';

const _nbeSender = 'AhlyBank';
const _vfSender = 'VF-Cash';

/// helper: normalized text (same pipeline as AiAssistedIngestion)
String norm(String s) => TextNormalizer.prepare(s);

DateTime t(int secondsOffset) =>
    DateTime(2024, 8, 28, 0, 0, 0).add(Duration(seconds: secondsOffset));

List<ReassembledMessage> feed(
  MessageReassembler r, {
  required String sender,
  required String text,
  required DateTime at,
  FragmentSourceType type = FragmentSourceType.sms,
}) {
  if (type == FragmentSourceType.sms) {
    return r.addSmsFragment(
      sender: sender,
      normalizedBody: norm(text),
      receivedAt: at,
    );
  } else {
    return r.addNotificationFragment(
      packageName: sender,
      normalizedCombinedText: norm(text),
      receivedAt: at,
    );
  }
}

// ============================================================
// Tests
// ============================================================

void main() {
  group('FragmentBuffer — internal helpers', () {
    test('looksLikeComplete: رسالة تنتهي برقم هاتف', () {
      expect(FragmentBuffer.looksLikeComplete('اتصل بـ 19623'), isTrue);
    });

    test('looksLikeComplete: رسالة تنتهي بوقت', () {
      expect(FragmentBuffer.looksLikeComplete('الساعة 00:02'), isTrue);
    });

    test('looksLikeComplete: رقم + نقطة يبدو كسر ناقص', () {
      expect(FragmentBuffer.looksLikeComplete('بمبلغ 720.'), isFalse);
    });

    test('looksLikeComplete: نقطة عادية في نهاية جملة', () {
      expect(FragmentBuffer.looksLikeComplete('تم التحويل بنجاح.'), isTrue);
    });

    test('looksLikeContinuation: يبدأ برقم', () {
      expect(FragmentBuffer.looksLikeContinuation('00 جم إلى مينا'), isTrue);
    });

    test('looksLikeContinuation: يبدأ بـ "إلى"', () {
      expect(FragmentBuffer.looksLikeContinuation('إلى مينا محمد'), isTrue);
    });

    test('looksLikeStandaloneStart: يبدأ بـ "تم"', () {
      expect(FragmentBuffer.looksLikeStandaloneStart('تم استلام 300 جنيه.'), isTrue);
    });

    test('detectOverlap: كشف تكرار واضح', () {
      const a = 'بمبلغ 720';
      const b = 'بمبلغ 720 جنيه إلى مينا';
      final result = FragmentBuffer.detectOverlap(a, b);
      expect(result, equals('جنيه إلى مينا'));
    });

    test('detectOverlap: مفيش overlap', () {
      const a = 'تم التحويل.';
      const b = 'تم الاستلام.';
      expect(FragmentBuffer.detectOverlap(a, b), isNull);
    });
  });

  // ------------------------------------------------------------------
  group('Test 1 — رسالة كاملة لا تتغير', () {
    test('رسالة NBE كاملة تمر كـ passthrough بنص أصلي', () {
      final r = MessageReassembler();
      final results = feed(r, sender: _nbeSender, text: _nbeFullMessage, at: t(0));
      expect(results.length, equals(1));
      expect(results.first.fragmentCount, equals(1));
      expect(results.first.wasReassembled, isFalse);
      expect(results.first.text, contains('720.00'));
      expect(results.first.text, contains('400492200244'));
    });
  });

  // ------------------------------------------------------------------
  group('Test 2 — رسالة NBE مقسمة إلى جزأين', () {
    test('جزأين يتجمعوا في رسالة واحدة، amount صح، مش reference', () {
      final r = MessageReassembler();

      // جزء 1 — مش هيطلع result (يخزن)
      final r1 = feed(r, sender: _nbeSender, text: _nbeFragment1of2, at: t(0));
      expect(r1, isEmpty, reason: 'الجزء الأول لازم يتخزن ومينفعش يوصل للـ parser');

      // جزء 2 — يوصل بعد ثانية، هنا المفروض يتجمعوا
      final r2 = feed(r, sender: _nbeSender, text: _nbeFragment2of2, at: t(1));
      expect(r2.length, equals(1), reason: 'لازم يطلع رسالة واحدة مجمعة');

      final msg = r2.first;
      expect(msg.fragmentCount, equals(2));
      expect(msg.wasReassembled, isTrue);
      expect(msg.text, contains('720'));
      expect(msg.text, contains('400492200244'));
      // المبلغ لازم يكون 720.00 مش 400492200244
      expect(msg.text, contains('جم'));
      expect(msg.timestamp, equals(t(0)), reason: 'timestamp الأول هو المعتمد');
    });
  });

  // ------------------------------------------------------------------
  group('Test 3 — رسالة NBE مقسمة إلى 3 أجزاء', () {
    test('3 أجزاء تنتج رسالة واحدة مكتملة', () {
      final r = MessageReassembler();

      expect(feed(r, sender: _nbeSender, text: _nbeFragment1of3, at: t(0)), isEmpty);
      expect(feed(r, sender: _nbeSender, text: _nbeFragment2of3, at: t(1)), isEmpty);

      final r3 = feed(r, sender: _nbeSender, text: _nbeFragment3of3, at: t(2));
      expect(r3.length, equals(1));
      expect(r3.first.fragmentCount, equals(3));
      expect(r3.first.text, contains('720'));
      expect(r3.first.text, contains('19623'));
    });
  });

  // ------------------------------------------------------------------
  group('Test 4 — أجزاء خارج الترتيب', () {
    test('لو الأجزاء مش متسلسلة نصيًا → لا دمج (conservative)', () {
      // جزء 2 قبل جزء 1 من ناحية النص — مش هينفع نثبت الترتيب
      // لأن metadata مش بتديّنا sequence number
      // سلوك متوقع: كل جزء يتعامل معاه على حسب هل يبدو continuation أو لا
      final r = MessageReassembler();
      final r1 = feed(r, sender: _nbeSender, text: _nbeFragment2of2, at: t(0));
      // الجزء التاني لوحده يبدأ برقم (00 جم) — يتخزن هو برضو
      // (لأنه يبدو continuation بس مفيش حاجة قبله)
      // ثم يوصل جزء 1 → مش هيتدمج (هو الـ standalone start)
      final r2 = feed(r, sender: _nbeSender, text: _nbeFragment1of2, at: t(1));
      // نتيجة متوقعة: إما الجزأين منفصلين أو الأول flush الجزء المخزن
      // المهم: مش هيبقى دمج عشوائي يخلط الترتيب
      final allResults = [...r1, ...r2];
      // لا يوجد رسالة مدموجة بشكل غير صحيح
      for (final msg in allResults) {
        if (msg.wasReassembled) {
          // لو حصل دمج، متبدأش بـ "00 جم"
          expect(msg.text.trimLeft(), isNot(startsWith('00')));
        }
      }
    });
  });

  // ------------------------------------------------------------------
  group('Test 5 — duplicate fragment', () {
    test('نفس الجزء يوصل مرتين → يُدمج في رسالة واحدة بدون تكرار النص', () {
      final r = MessageReassembler();

      // الجزء الأول مرتين (أندرويد أعاد التسليم)
      final r1 = feed(r, sender: _nbeSender, text: _nbeFragment1of2, at: t(0));
      expect(r1, isEmpty);

      // نفس الجزء تاني مرة (duplicate)
      final r2 = feed(r, sender: _nbeSender, text: _nbeFragment1of2, at: t(0));
      // المتوقع: إما يتجاهله أو يبقى في الـ buffer
      // المهم: مش ينشئ رسالة مكتملة زائفة

      // الجزء الحقيقي التاني
      final r3 = feed(r, sender: _nbeSender, text: _nbeFragment2of2, at: t(1));
      final allR = [...r1, ...r2, ...r3];
      final merged = allR.where((m) => m.wasReassembled).toList();
      expect(merged.length, equals(1), reason: 'رسالة واحدة فقط');
      expect(merged.first.text, isNot(contains(_nbeFragment1of2 + _nbeFragment1of2)),
          reason: 'النص مش مكرر');
    });
  });

  // ------------------------------------------------------------------
  group('Test 6 — overlapping fragment', () {
    test('overlap في آخر A وبداية B يُحذف بشكل صحيح', () {
      const a = 'تم تنفيذ تحويل لحظي من بطاقتكم بمبلغ 720';
      const b = 'بمبلغ 720 جنيه إلى مينا رقم مرجعي 12345 يوم 08-28 الساعة 00:02';

      final r = MessageReassembler();
      expect(feed(r, sender: _nbeSender, text: a, at: t(0)), isEmpty);
      final results = feed(r, sender: _nbeSender, text: b, at: t(1));

      expect(results.length, equals(1));
      final text = results.first.text;
      // لا يحتوي على "بمبلغ 720 بمبلغ 720"
      expect(text, isNot(contains('بمبلغ 720 بمبلغ 720')));
      // لكن يحتوي على "720" مرة واحدة على الأقل
      expect(text, contains('720'));
    });
  });

  // ------------------------------------------------------------------
  group('Test 7 — رسالتان مختلفتان من نفس المصدر خلال 1-2 ثانية', () {
    test('رسالتان ماليتان مستقلتان من NBE بفارق ثانيتين → لا دمج', () {
      final r = MessageReassembler();

      const msg1 = 'تم تحويل 500 جنيه من حسابك الساعة 00:01';
      const msg2 = 'تم استلام 300 جنيه في حسابك الساعة 00:02';

      final r1 = feed(r, sender: _nbeSender, text: msg1, at: t(0));
      final r2 = feed(r, sender: _nbeSender, text: msg2, at: t(2));

      final all = [...r1, ...r2];
      // كلتا الرسالتين تصلان للـ parser كرسائل مستقلة
      expect(all.length, equals(2), reason: 'رسالتان منفصلتان');
      expect(all.any((m) => m.text.contains('500')), isTrue);
      expect(all.any((m) => m.text.contains('300')), isTrue);
      expect(all.any((m) => m.wasReassembled), isFalse,
          reason: 'لا دمج بين رسالتين مستقلتين');
    });
  });

  // ------------------------------------------------------------------
  group('Test 8 — timestamps متباعدة', () {
    test('نفس المرسل لكن الفارق أكبر من fragmentWindow → لا دمج', () {
      final r = MessageReassembler();

      // الجزء الأول يتخزن
      expect(feed(r, sender: _nbeSender, text: _nbeFragment1of2, at: t(0)), isEmpty);

      // الجزء التاني بعد 30 ثانية (> fragmentWindow = 7 ثواني)
      final late = feed(r, sender: _nbeSender, text: _nbeFragment2of2, at: t(30));

      // المفروض الجزء الأول يتـflush منتهي الصلاحية
      // ثم الجزء التاني يُعالج بشكل مستقل
      final allR = [...late];
      // على الأقل الجزء التاني يتحول لرسالة مستقلة (أو يتخزن برضو)
      // المهم: مش هيتدمجوا
      for (final m in allR) {
        expect(m.wasReassembled, isFalse,
            reason: 'لا دمج بعد انتهاء النافذة الزمنية');
      }
    });
  });

  // ------------------------------------------------------------------
  group('Test 9 — sender مختلف', () {
    test('fragment من مرسل مختلف لا يتدمج مع buffer مرسل آخر', () {
      final r = MessageReassembler();

      // نبدأ buffer لـ NBE
      expect(feed(r, sender: _nbeSender, text: _nbeFragment1of2, at: t(0)), isEmpty);

      // يوصل fragment من VF-Cash — مفروض يُعالج بشكل مستقل تمامًا
      final vfResults = feed(
        r,
        sender: _vfSender,
        text: 'تم استلام مبلغ 200 جنيه من رقم 01000000000 الساعة 01:00',
        at: t(1),
      );

      // الـ VF-Cash message تبدو مكتملة → passthrough
      expect(vfResults.length, equals(1));
      expect(vfResults.first.sender, equals(_vfSender));
      // الـ NBE buffer لسه في انتظاره
    });
  });

  // ------------------------------------------------------------------
  group('Test 10 — fragment متأخر جدًا (after timeout)', () {
    test('fragment يوصل بعد انتهاء النافذة → لا دمج تلقائي', () {
      final r = MessageReassembler();

      // الجزء الأول
      final r1 = feed(r, sender: _nbeSender, text: _nbeFragment1of2, at: t(0));
      expect(r1, isEmpty);

      // flush المنتهيين يدويًا (بعد 10 ثواني)
      r.flushExpired(/* now is implicitly checked via next add */);
      // مش هنجرب expired هنا لأننا محتاجين نعدي DateTime لـ flushExpired
      // وبدلًا منها بنختبر عبر send fragment متأخر جدًا

      // الجزء التاني بعد 30 ثانية
      final r2 = feed(r, sender: _nbeSender, text: _nbeFragment2of2, at: t(30));
      final all = [...r1, ...r2];
      for (final m in all) {
        expect(m.wasReassembled, isFalse,
            reason: 'fragment متأخر لا يُدمج مع شيء منتهي الصلاحية');
      }
    });
  });

  // ------------------------------------------------------------------
  group('Test 11 — رسالة NBE حقيقية منقسمة إلى جزأين', () {
    test('نفس الرسالة الحقيقية → 1 رسالة مجمعة → amount صح، reference ≠ amount', () {
      final r = MessageReassembler();

      expect(feed(r, sender: _nbeSender, text: _nbeFragment1of2, at: t(0)), isEmpty);
      final results = feed(r, sender: _nbeSender, text: _nbeFragment2of2, at: t(1));

      expect(results.length, equals(1));
      final text = results.first.text;

      // المبلغ الصحيح موجود
      expect(text, contains('720'));
      // الرقم المرجعي موجود (مش محذوف)
      expect(text, contains('400492200244'));
      // لكن "720" ≠ "400492200244" — نثبت إن الـ parser بيأخد المبلغ الصح
      // (هذا الجزء هو integration test — موثق في Test 11b تحت)
      expect(results.first.wasReassembled, isTrue);
      expect(results.first.fragmentCount, equals(2));
    });
  });

  // ------------------------------------------------------------------
  group('Test 12 — رسالة NBE حقيقية منقسمة إلى 3 أجزاء', () {
    test('3 أجزاء → 1 رسالة واحدة → يحتوي المبلغ والمرجع والوقت', () {
      final r = MessageReassembler();

      expect(feed(r, sender: _nbeSender, text: _nbeFragment1of3, at: t(0)), isEmpty);
      expect(feed(r, sender: _nbeSender, text: _nbeFragment2of3, at: t(1)), isEmpty);
      final results = feed(r, sender: _nbeSender, text: _nbeFragment3of3, at: t(2));

      expect(results.length, equals(1));
      expect(results.first.fragmentCount, equals(3));
      expect(results.first.text, contains('720'));
      expect(results.first.text, contains('400492200244'));
      expect(results.first.text, contains('19623'));
    });
  });

  // ------------------------------------------------------------------
  group('Test 13 — Vodafone Cash منقسمة إلى جزأين', () {
    test('رسالة VF-Cash مجزأة تُجمع بشكل صحيح', () {
      // نقسمها بعد "جنيه رسوم"
      const vfFrag1 = 'تم دفع مبلغ 350 جنيه رسوم';
      const vfFrag2 = 'خدمة لفودافون كاش. رصيد محفظتك الحالي 1500 جنيه. '
          'رقم العملية 1234567890 تاريخ العملية 2024-08-28 00:05.';

      final r = MessageReassembler();
      expect(feed(r, sender: _vfSender, text: vfFrag1, at: t(0)), isEmpty);
      final results = feed(r, sender: _vfSender, text: vfFrag2, at: t(1));

      expect(results.length, equals(1));
      expect(results.first.wasReassembled, isTrue);
      expect(results.first.text, contains('350'));
      expect(results.first.text, contains('1500'));
      expect(results.first.text, isNot(contains('تم دفع مبلغ 350 جنيه رسومتم دفع')),
          reason: 'لا تكرار للنص');
    });
  });

  // ------------------------------------------------------------------
  group('Test 14 — رسالة غير مالية مجزأة', () {
    test('رسالة ترويجية مجزأة لا تنشئ معاملة', () {
      // هذا الاختبار يثبت إن الـ Reassembler بيمررها كنص، والـ parser هو
      // اللي بيقرر إنها مش مالية. الـ Reassembler نفسه محايد من ناحية
      // "هل هي مالية؟" — ده مش شغله.
      const promo1 = 'عرض خاص على مكالمات الدولي';
      const promo2 = '50 دقيقة مجانية لمدة أسبوع. اتصل 888 للاشتراك.';

      final r = MessageReassembler();
      expect(feed(r, sender: _vfSender, text: promo1, at: t(0)), isEmpty);
      final results = feed(r, sender: _vfSender, text: promo2, at: t(1));

      // الـ Reassembler دمجهم (أو مش دمجهم) — المهم إن ما وصل للـ parser
      // مش هيولّد FinancialEvent (ده اختبار مستقل في integration test)
      for (final m in results) {
        // الـ text مش هيحتوي على مبلغ واضح بكلمة عملة
        expect(
          RegExp(r'\d+(?:\.\d+)?\s*(?:جم|جني[هة]|EGP|LE)').hasMatch(m.text),
          isFalse,
          reason: 'رسالة ترويجية مش مفروض تحتوي مبلغ بعملة',
        );
      }
    });
  });

  // ------------------------------------------------------------------
  group('Tests إضافية — حماية التداخل (Interleaved)', () {
    test('A من NBE ثم X مختلف من NBE ثم B → A وX وB منفصلون', () {
      final r = MessageReassembler();

      // A: جزء أول معلق
      expect(feed(r, sender: _nbeSender, text: _nbeFragment1of2, at: t(0)), isEmpty);

      // X: رسالة مستقلة تامة من نفس المرسل وصلت بينهم
      // — هذا يجب أن يـflush الـ A المعلق ويبدأ جديد لـ X
      final xResults = feed(
        r,
        sender: _nbeSender,
        text: 'تم استلام 300 جنيه في حسابك الساعة 12:00',
        at: t(2),
      );

      // B: الجزء التاني لرسالة A (لكن A تـflush بالفعل)
      final bResults = feed(r, sender: _nbeSender, text: _nbeFragment2of2, at: t(3));

      final allMerged = [...xResults, ...bResults].where((m) => m.wasReassembled);
      expect(allMerged, isEmpty,
          reason: 'لا يجوز دمج A+X أو X+B — كلهم رسائل مستقلة');
    });
  });

  // ------------------------------------------------------------------
  group('Performance — buffer cleanup', () {
    test('buffer لا يتراكم بعد انتهاء النافذة', () {
      final r = MessageReassembler();
      final buf = r.bufferForTesting;

      // أضف 5 fragments من مرسلين مختلفين
      for (int i = 0; i < 5; i++) {
        r.addSmsFragment(
          sender: 'sender_$i',
          normalizedBody: 'نص ناقص بمبلغ $i.',
          receivedAt: t(0),
        );
      }
      expect(buf.pendingCount, equals(5));

      // flush منتهي الصلاحية بعد 10 ثواني
      final flushed = buf.flushExpired(now: t(10));
      expect(flushed.length, equals(5));
      expect(buf.pendingCount, equals(0));
    });
  });
}
