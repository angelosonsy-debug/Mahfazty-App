import 'dart:math';

/// نموذج الديون الإلزامي: عميل + معاملات جوّاه - مش List مفلطحة. كل عميل
/// (شخص) عنده سجل معاملات مستقل، وكل معاملة إما دائنة (هو مديون لينا)
/// أو مدينة (احنا مديونين له).
enum DebtEntryDirection { theyOweUs, weOweThem }

final _clientRng = Random();

String generateClientId() =>
    'c_${DateTime.now().microsecondsSinceEpoch}_${_clientRng.nextInt(99999)}';

String generateDebtId() =>
    'd_${DateTime.now().microsecondsSinceEpoch}_${_clientRng.nextInt(99999)}';

class Client {
  final String id;
  final String name;
  final String? notes;
  final DateTime createdAt;

  const Client({
    required this.id,
    required this.name,
    required this.createdAt,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Client.fromJson(Map<String, dynamic> json) => Client(
        id: json['id'] as String,
        name: json['name'] as String,
        notes: json['notes'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      );
}

/// معاملة واحدة جوّه عميل - سجل مستقل بالكامل، مبيتدمجش مع غيره
class DebtTransaction {
  final String id;
  final String clientId;
  final DebtEntryDirection direction;
  final double amount;
  final String? note;
  final DateTime timestamp;

  /// تاريخ استحقاق اختياري (null = من غير ميعاد). آمن للبيانات القديمة.
  final DateTime? dueDate;

  const DebtTransaction({
    required this.id,
    required this.clientId,
    required this.direction,
    required this.amount,
    required this.timestamp,
    this.note,
    this.dueDate,
  });

  /// مبلغ سالب = سداد (بيقلل الدين بدل ما يزوده). بنستخدمه في "سداد
  /// الدين من محفظة" بدل ما نعمل نوع تاني من المعاملات.
  bool get isSettlement => amount < 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientId': clientId,
        'direction': direction.name,
        'amount': amount,
        'note': note,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'dueDate': dueDate?.millisecondsSinceEpoch,
      };

  factory DebtTransaction.fromJson(Map<String, dynamic> json) => DebtTransaction(
        id: json['id'] as String,
        clientId: json['clientId'] as String,
        direction: DebtEntryDirection.values.firstWhere((e) => e.name == json['direction']),
        amount: (json['amount'] as num).toDouble(),
        note: json['note'] as String?,
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        dueDate: json['dueDate'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['dueDate'] as int)
            : null,
      );
}
