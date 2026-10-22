import 'message_fragment.dart';
import 'reassembled_message.dart';

/// حد أقصى للـ fragments المعلقة في نفس الوقت (حماية من تراكم الذاكرة
/// في حالة بنود متعددة من مصادر مختلفة كلها معلقة مع بعض)
const int _kMaxPendingSlots = 20;

class _PendingBuffer {
  final List<MessageFragment> fragments;
  String currentText;

  _PendingBuffer({
    required MessageFragment first,
  })  : fragments = [first],
        currentText = first.normalizedText;

  DateTime get firstTimestamp => fragments.first.receivedAt;
  String get sender => fragments.first.sender;
  FragmentSourceType get sourceType => fragments.first.sourceType;
}

/// تخزين مؤقت in-memory (بدون persistence — النافذة الزمنية قصيرة جدًا
/// ولا يوجد مبرر لحفظ fragments على الـ disk). الـ expiration بيحصل
/// تلقائيًا لما يوصل fragment جديد، أو عند استدعاء [flushExpired].
class FragmentBuffer {
  /// نافذة الانتظار — configurable من مكان واحد
  static const Duration fragmentWindow = Duration(seconds: 7);

  /// حد الـ overlap اللي بنكشفه ونحذفه (حروف)
  static const int _kMaxOverlapScan = 40;
  static const int _kMinOverlapMatch = 4;

  final Map<String, _PendingBuffer> _pending = {};

  /// أضف fragment جديد.
  ///
  /// يرجع:
  /// - قائمة فيها [ReassembledMessage] جاهزة للـ parser
  ///   (ممكن تكون أكتر من واحدة لو فيه buffers قديمة انتهت
  ///    في نفس الوقت اللي وصل فيه fragment جديد)
  /// - القائمة ممكن تكون فاضية لو الـ fragment اتخزن مؤقتًا
  ///   وهو في انتظار المزيد
  List<ReassembledMessage> add(MessageFragment fragment) {
    final results = <ReassembledMessage>[];

    // 1. أول حاجة: flush أي buffers خلّصت وقتها
    results.addAll(_evictExpired(except: fragment.sender, now: fragment.receivedAt));

    // 2. دور على buffer معلق لنفس المرسل
    final pending = _pending[fragment.sender];

    if (pending != null) {
      // قبل أي محاولة دمج: تأكد إن الـ buffer نفسه مش منتهي الصلاحية.
      // _evictExpired بيتجاهل نفس المرسل (except:) — هنا بنعوض ده صراحة.
      final age = fragment.receivedAt.difference(pending.firstTimestamp);
      if (age > fragmentWindow) {
        results.add(_flush(fragment.sender));
        // ابدأ buffer جديد للـ fragment الحالي
        _startNewBuffer(fragment, results);
        return results;
      }

      // تحقق إن الـ fragment ده فعلًا تابع للـ buffer المعلق
      final merged = _tryMerge(pending, fragment);
      if (merged != null) {
        pending.currentText = merged;
        pending.fragments.add(fragment);

        // لو النص المدموج يبدو مكتمل → flush على طول
        if (looksLikeComplete(pending.currentText)) {
          results.add(_flush(fragment.sender));
        }
        // وإلا: نفضل ننتظر — return without adding
      } else {
        // الـ fragment الجديد مش تابع للـ buffer المعلق →
        // flush المعلق زي ما هو (unknown/incomplete) وابدأ buffer جديد
        results.add(_flush(fragment.sender));
        _startNewBuffer(fragment, results);
      }
    } else {
      _startNewBuffer(fragment, results);
    }

    // 3. تأكد مننحتفلش بأكتر من _kMaxPendingSlots
    if (_pending.length > _kMaxPendingSlots) {
      _evictOldest(results);
    }

    return results;
  }

  /// يرجع كل الـ messages المعلقة اللي انتهى وقتها، ممكن استدعاؤه
  /// يدويًا (مثلًا عند فتح التطبيق) عشان نتأكد إن مفيش fragment
  /// عالق إلى الأبد.
  List<ReassembledMessage> flushExpired({DateTime? now}) {
    return _evictExpired(except: null, now: now ?? DateTime.now());
  }

  // -----------------------------------------------------------------------
  // Private helpers
  // -----------------------------------------------------------------------

  /// لو النص يبدو مكتمل → flush مباشرة من غير buffering.
  /// لو يبدو غير مكتمل → ابدأ buffering وانتظر الجزء القادم.
  void _startNewBuffer(MessageFragment fragment, List<ReassembledMessage> results) {
    // الإشعارات (notifications) دايمًا رسائل كاملة في نفسها — passthrough فوري
    // بدون أي looksLikeComplete check، لأنها مش بتيجي في أجزاء زي الـ SMS
    if (fragment.sourceType == FragmentSourceType.notification ||
        looksLikeComplete(fragment.normalizedText)) {
      results.add(ReassembledMessage(
        text: fragment.normalizedText,
        timestamp: fragment.receivedAt,
        sender: fragment.sender,
        sourceType: fragment.sourceType,
        fragmentCount: 1,
      ));
    } else {
      // رسالة SMS تبدو منقوصة → نخزنها وننتظر
      _pending[fragment.sender] = _PendingBuffer(first: fragment);
    }
  }

  /// يحاول يدمج [fragment] في [pending].
  ///
  /// يرجع النص المدموج لو الدمج آمن، أو null لو مش مناسب.
  /// القاعدة: كل الشروط لازم تتحقق مع بعض — اتنين مش كافيين.
  String? _tryMerge(_PendingBuffer pending, MessageFragment fragment) {
    // شرط 1: نفس نوع المصدر
    if (pending.sourceType != fragment.sourceType) return null;

    // شرط 2: ضمن النافذة الزمنية
    final elapsed = fragment.receivedAt.difference(pending.firstTimestamp);
    if (elapsed.abs() > fragmentWindow) return null;

    // شرط 3: الـ fragment الجديد مش يبدو وكأنه بداية رسالة مستقلة
    if (looksLikeStandaloneStart(fragment.normalizedText)) return null;

    // شرط 4: الـ buffer الحالي يبدو منقوص (ما انتهاش بجملة مكتملة)
    // أو فيه overlap واضح مع الـ fragment الجديد
    final overlapResult = detectOverlap(pending.currentText, fragment.normalizedText);
    final candidateAfterOverlap = overlapResult ?? fragment.normalizedText;

    final currentIncomplete = !looksLikeComplete(pending.currentText);
    final hasOverlap = overlapResult != null;

    // دمج مسموح لو:
    // (الـ buffer غير مكتمل — والـ fragment مش بداية مستقلة، تحقق منه فوق)
    // أو (فيه overlap واضح بيثبت إن الجزء ده تابع)
    if (currentIncomplete || hasOverlap) {
      final joined = hasOverlap
          ? '${pending.currentText} $candidateAfterOverlap'
          : '${pending.currentText} ${fragment.normalizedText}';
      return _collapseSpaces(joined);
    }

    return null;
  }

  ReassembledMessage _flush(String sender) {
    final buf = _pending.remove(sender)!;
    return ReassembledMessage(
      text: buf.currentText,
      timestamp: buf.firstTimestamp,
      sender: buf.sender,
      sourceType: buf.sourceType,
      fragmentCount: buf.fragments.length,
    );
  }

  List<ReassembledMessage> _evictExpired({String? except, required DateTime now}) {
    final results = <ReassembledMessage>[];
    final expiredKeys = _pending.entries
        .where((e) =>
            e.key != except &&
            now.difference(e.value.firstTimestamp) > fragmentWindow)
        .map((e) => e.key)
        .toList();
    for (final key in expiredKeys) {
      results.add(_flush(key));
    }
    return results;
  }

  void _evictOldest(List<ReassembledMessage> results) {
    if (_pending.isEmpty) return;
    final oldest = _pending.entries
        .reduce((a, b) => a.value.firstTimestamp.isBefore(b.value.firstTimestamp) ? a : b);
    results.add(_flush(oldest.key));
  }

  // -----------------------------------------------------------------------
  // Text analysis helpers (static, no state)
  // -----------------------------------------------------------------------

  /// هل النص يبدو رسالة مكتملة؟ (لا نحتاج fragment إضافي بعده)
  static bool looksLikeComplete(String text) {
    final t = text.trimRight();
    if (t.isEmpty) return true;

    // ينتهي برقم هاتف خط ساخن شائع (19623، 16888، 19777، إلخ)
    if (RegExp(r'\d{5}$').hasMatch(t)) return true;

    // ينتهي بوقت (HH:MM) أو وقت + علامة ترقيم (HH:MM.)
    if (RegExp(r'\d{2}:\d{2}[.؟!?]?$').hasMatch(t)) return true;

    // ينتهي بعلامة ترقيم حقيقية — لكن مش رقم+نقطة (مثل "720.")
    final lastChar = t[t.length - 1];
    if ('.!؟?'.contains(lastChar)) {
      // "720." يبدو كسر عشري ناقص → مش مكتمل
      if (RegExp(r'\d+\.$').hasMatch(t)) return false;
      return true;
    }

    return false;
  }

  /// هل النص يبدو وكأنه بداية رسالة مالية مستقلة جديدة؟
  /// إذا نعم → لا نجمعه مع buffer معلق
  static bool looksLikeStandaloneStart(String text) {
    final t = text.trimLeft().toLowerCase();

    // تبدأ بـ "تم" (أشهر بداية لرسائل الخصم/الإيداع العربية)
    if (t.startsWith('تم ')) return true;

    // تبدأ بـ "عزيز" أو "برجاء" أو "تنبيه" أو "تهانينا"
    if (t.startsWith('عزيز') || t.startsWith('برجاء') || t.startsWith('تنبيه')) return true;

    // تبدأ بحرف عربي كبداية كلمة حقيقية (مش رقم أو رمز)
    // لكن لها طول كافٍ (> 15 حرف) وفيها مبلغ → على الأرجح رسالة مستقلة
    // استثناء: بعض الكلمات دي واضح إنها استمرار لجملة (مش بداية رسالة مستقلة)
    const continuationPrefixes = [
      'بمبلغ', 'بقيمة', 'خدمة ', 'شاملة', 'ورقم', 'ورصيد', 'وتاريخ',
    ];
    final startsWithContinuation =
        continuationPrefixes.any((p) => text.trimLeft().startsWith(p));
    if (!startsWithContinuation &&
        text.length > 15 &&
        RegExp(r'^[\u0600-\u06FF]').hasMatch(text) &&
        RegExp(r'\d+(?:\.\d+)?\s*(?:جم|جني[ةه]|EGP|LE)', caseSensitive: false).hasMatch(text)) {
      return true;
    }

    return false;
  }

  /// هل النص يبدو استمرارًا (مش بداية رسالة مستقلة)?
  static bool looksLikeContinuation(String text) {
    final t = text.trimLeft();
    if (t.isEmpty) return false;

    // يبدأ برقم (مثل "00 جم" أو "50 جنيه")
    if (RegExp(r'^\d').hasMatch(t)) return true;

    // يبدأ بكلمة عملة مباشرة
    if (t.startsWith('جم') || t.startsWith('جني') || t.startsWith('EGP') || t.startsWith('LE')) {
      return true;
    }

    // يبدأ بكلمة حرف جر + اسم (إلى / من / على) — شائع في منتصف الجمل
    if (RegExp(r'^(إلى|من|على|في|لـ|لـ|وإلى)\s').hasMatch(t)) {
      return true;
    }

    return false;
  }

  /// يكشف overlap في نهاية [a] وبداية [b].
  /// يرجع [b] بعد حذف الجزء المكرر، أو null لو مفيش overlap واضح.
  static String? detectOverlap(String a, String b) {
    // نستخدم a.length - 1 (مش a.length ~/ 2) عشان الـ overlap قد يكون أطول
    // من نص ثانوي (تخيل A = 9 حروف كلها overlap مع بداية B).
    final maxScan = [_kMaxOverlapScan, a.length, b.length]
        .reduce((x, y) => x < y ? x : y);
    for (int n = maxScan; n >= _kMinOverlapMatch; n--) {
      if (a.length < n || b.length < n) continue;
      final suffix = a.substring(a.length - n);
      if (b.startsWith(suffix)) {
        final remainder = b.substring(n).trimLeft();
        return remainder.isEmpty ? null : remainder;
      }
    }
    return null;
  }

  /// للاختبار فقط — يُعيد عدد الـ buffers المعلقة حاليًا
  int get pendingCount => _pending.length;

  static String _collapseSpaces(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
