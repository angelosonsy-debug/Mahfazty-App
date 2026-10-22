import 'dart:math' show Random;

import 'message_fragment.dart';
import 'fragment_buffer.dart';
import 'reassembled_message.dart';

export 'message_fragment.dart';
export 'reassembled_message.dart';

/// الطبقة العامة للـ reassembly — اللي بيستدعيها AiAssistedIngestion.
///
/// مسؤولياته بالضبط:
///   "هل القطعتان دول ينتموا لنفس الرسالة؟"
///
/// مش مسؤول عن:
///   - معرفة NBE / Vodafone Cash (ده شغل SourcePolicy)
///   - إنشاء FinancialEvent (ده شغل SmsParser/NotificationParser/AI)
///   - deduplication (ده شغل FinancialEngine._isDuplicateRepost)
class MessageReassembler {
  final FragmentBuffer _buffer = FragmentBuffer();

  static final _rng = Random();

  /// الدالة الرئيسية — تستدعيها بـ raw SMS/notification metadata قبل أي
  /// parser. يرجع قائمة من [ReassembledMessage] جاهزة للمعالجة. ممكن
  /// تكون فاضية لو الـ fragment اتخزن ومازال في انتظار المزيد.
  ///
  /// قاعدة "Unknown أفضل من False Merge":
  ///   لو الـ buffer مش واثق إن الجزأين ينتموا لبعض، بيرجعهم منفصلين
  ///   بدل ما يدمجهم ويخلق معاملة مالية غلط.
  List<ReassembledMessage> addSmsFragment({
    required String sender,
    required String normalizedBody,
    required DateTime receivedAt,
  }) {
    final fragment = MessageFragment(
      fragmentId: _newId(),
      sourceType: FragmentSourceType.sms,
      sender: sender,
      normalizedText: normalizedBody,
      receivedAt: receivedAt,
    );
    return _buffer.add(fragment);
  }

  List<ReassembledMessage> addNotificationFragment({
    required String packageName,
    required String normalizedCombinedText,
    required DateTime receivedAt,
  }) {
    final fragment = MessageFragment(
      fragmentId: _newId(),
      sourceType: FragmentSourceType.notification,
      sender: packageName,
      normalizedText: normalizedCombinedText,
      receivedAt: receivedAt,
    );
    return _buffer.add(fragment);
  }

  /// Flush أي fragments منتهية الصلاحية (يتم استدعاؤه عند فتح التطبيق
  /// أو من وقت لوقت). الـ fragments دي راحت للـ parser كـ incomplete
  /// messages، والـ parser نفسه بيبعتها للـ Inbox/Review لو الثقة واطية.
  List<ReassembledMessage> flushExpired() => _buffer.flushExpired();

  /// @visibleForTesting
  FragmentBuffer get bufferForTesting => _buffer;

  static String _newId() {
    return _rng.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  }
}
