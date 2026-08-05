import 'dart:math';

/// ملحوظة: البرومبت الأصلي حدد FinancialSource بـ 3 قيم بس
/// (vodafoneCash / instaPay / manual). ضفنا alAhlyBank لأن عندنا Templates
/// حقيقية شغالة له بالفعل من المرحلة اللي فاتت، وحابين منرميهاش. البنك
/// الأهلي مش هيظهر كـ"محفظة" في شاشة Wallets (اللي هي Vodafone Cash و
/// InstaPay بس حسب التحديد الرسمي)، لكن أحداثه لسه بتتسجل وتظهر في
/// الـ Inbox/الإحصائيات العامة.
enum FinancialSource { vodafoneCash, alAhlyBank, instaPay, manual }

enum FinancialEventType {
  deposit,
  withdrawal,
  transfer,
  purchase,
  refund,
  manualAdjustment,
  debtCreated,
  debtPaid,
  pocketAdjustment,
  unknown,
}

/// نوع العملية بتحدد هل بتقلل رصيد (مصروف) ولا لأ - مستخدمة في حساب
/// الرصيد التراكمي للمحافظ
bool isOutgoingEventType(FinancialEventType type) {
  return type == FinancialEventType.withdrawal ||
      type == FinancialEventType.purchase ||
      type == FinancialEventType.transfer;
}

/// عكسها - أي عملية بتزود الرصيد
bool isIncomingEventType(FinancialEventType type) {
  return type == FinancialEventType.deposit || type == FinancialEventType.refund;
}

extension FinancialSourceLabel on FinancialSource {
  String get labelAr {
    switch (this) {
      case FinancialSource.vodafoneCash:
        return 'Vodafone Cash';
      case FinancialSource.alAhlyBank:
        return 'البنك الأهلي';
      case FinancialSource.instaPay:
        return 'InstaPay';
      case FinancialSource.manual:
        return 'يدوي';
    }
  }
}

extension FinancialEventTypeLabel on FinancialEventType {
  String get labelAr {
    switch (this) {
      case FinancialEventType.deposit:
        return 'إيداع';
      case FinancialEventType.withdrawal:
        return 'سحب / خصم';
      case FinancialEventType.transfer:
        return 'تحويل';
      case FinancialEventType.purchase:
        return 'شراء / دفع';
      case FinancialEventType.refund:
        return 'استرجاع';
      case FinancialEventType.manualAdjustment:
        return 'تعديل يدوي';
      case FinancialEventType.debtCreated:
        return 'دين جديد';
      case FinancialEventType.debtPaid:
        return 'سداد دين';
      case FinancialEventType.pocketAdjustment:
        return 'تعديل الكاش';
      case FinancialEventType.unknown:
        return 'غير معروف - يحتاج مراجعة';
    }
  }
}

final _idRandom = Random();
String generateEventId() {
  return '${DateTime.now().microsecondsSinceEpoch}_${_idRandom.nextInt(999999)}';
}

/// النموذج الموحّد - كل الـ Parsers (SMS أو Notification) لازم يرجعوه بس.
/// مفيش حاجة تانية في التطبيق المفروض تعتمد مباشرة على SMS أو Notification.
class FinancialEvent {
  final String id;
  final FinancialSource source;
  final FinancialEventType eventType;
  final double? amount;
  final String currency;
  final double? balanceAfter;
  final String? merchant;
  final String? person;
  final String? reference;
  final DateTime timestamp;
  final int confidence; // 0-100
  final String rawMessage;
  final String rawSource; // رقم SMS أو اسم الـ package
  final Map<String, dynamic> metadata;
  final String? category; // null = لسه متصنفش (بيتحسب كـ"أخرى" في الميزانية)

  const FinancialEvent({
    required this.id,
    required this.source,
    required this.eventType,
    required this.timestamp,
    required this.confidence,
    required this.rawMessage,
    required this.rawSource,
    this.amount,
    this.currency = 'EGP',
    this.balanceAfter,
    this.merchant,
    this.person,
    this.reference,
    this.metadata = const {},
    this.category,
  });

  /// حسب مقاييس الثقة المتفق عليها من الأول
  String get confidenceLabelAr {
    if (confidence >= 99) return 'استيراد تلقائي';
    if (confidence >= 95) return 'استيراد صامت';
    if (confidence >= 85) return 'صندوق المراجعة';
    if (confidence >= 70) return 'يحتاج مراجعتك';
    return 'متجاهل';
  }

  FinancialEvent copyWith({
    FinancialEventType? eventType,
    double? amount,
    double? balanceAfter,
    String? merchant,
    String? person,
    String? reference,
    int? confidence,
    Map<String, dynamic>? metadata,
    String? category,
  }) {
    return FinancialEvent(
      id: id,
      source: source,
      eventType: eventType ?? this.eventType,
      amount: amount ?? this.amount,
      currency: currency,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      merchant: merchant ?? this.merchant,
      person: person ?? this.person,
      reference: reference ?? this.reference,
      timestamp: timestamp,
      confidence: confidence ?? this.confidence,
      rawMessage: rawMessage,
      rawSource: rawSource,
      metadata: metadata ?? this.metadata,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'eventType': eventType.name,
        'amount': amount,
        'currency': currency,
        'balanceAfter': balanceAfter,
        'merchant': merchant,
        'person': person,
        'reference': reference,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'confidence': confidence,
        'rawMessage': rawMessage,
        'rawSource': rawSource,
        'metadata': metadata,
        'category': category,
      };

  factory FinancialEvent.fromJson(Map<String, dynamic> json) {
    return FinancialEvent(
      id: json['id'] as String,
      source: FinancialSource.values.firstWhere((e) => e.name == json['source']),
      eventType: FinancialEventType.values.firstWhere((e) => e.name == json['eventType']),
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'EGP',
      balanceAfter: (json['balanceAfter'] as num?)?.toDouble(),
      merchant: json['merchant'] as String?,
      person: json['person'] as String?,
      reference: json['reference'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      confidence: json['confidence'] as int,
      rawMessage: json['rawMessage'] as String? ?? '',
      rawSource: json['rawSource'] as String? ?? '',
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      category: json['category'] as String?,
    );
  }
}
