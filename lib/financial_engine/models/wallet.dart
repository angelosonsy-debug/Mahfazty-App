import 'dart:math';

enum WalletType {
  cash,          // نقدي — فلوس الجيب
  bankAccount,   // حساب بنكي
  mobileWallet,  // محفظة إلكترونية (Vodafone Cash، إلخ)
  card,          // بطاقة ائتمان/خصم
  instaPay,      // InstaPay
  custom,        // أخرى
}

/// شركة الاتصالات — بتتحدد بس لو WalletType == mobileWallet.
/// قيمة null (محفظة قديمة اتحفظت قبل الحقل ده) معناها "مش محددة".
enum MobileCarrier { vodafone, etisalat, orange, we, unknown }

extension MobileCarrierLabel on MobileCarrier {
  String get labelAr {
    switch (this) {
      case MobileCarrier.vodafone:
        return 'فودافون كاش';
      case MobileCarrier.etisalat:
        return 'اتصالات كاش';
      case MobileCarrier.orange:
        return 'أورنج موني';
      case MobileCarrier.we:
        return 'وي باي';
      case MobileCarrier.unknown:
        return 'غير محددة';
    }
  }
}

extension WalletTypeLabel on WalletType {
  String get labelAr {
    switch (this) {
      case WalletType.cash:          return 'نقدي';
      case WalletType.bankAccount:   return 'حساب بنكي';
      case WalletType.mobileWallet:  return 'محفظة إلكترونية';
      case WalletType.card:          return 'بطاقة';
      case WalletType.instaPay:      return 'InstaPay';
      case WalletType.custom:        return 'أخرى';
    }
  }
}

final _walletRng = Random();

String generateWalletId() =>
    'w_${DateTime.now().microsecondsSinceEpoch}_${_walletRng.nextInt(99999)}';

class Wallet {
  final String id;
  final String name;
  final WalletType type;
  final DateTime createdAt;

  /// Archive بدل Delete — الأحداث تبقى مرتبطة بالمحفظة حتى لو أُرشفت
  final bool archived;

  /// شركة الاتصالات (nullable — آمن للبيانات القديمة). مهم بس لو
  /// type == mobileWallet، وبتحدد هل نعرض زر USSD ولا لأ.
  final MobileCarrier? carrier;

  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    this.archived = false,
    this.carrier,
  });

  /// Balance = مشتقّ دائمًا من الأحداث (FinancialEngine._recomputeWallets)
  /// ولا يُخزَّن هنا — مفيش حقل balance في الـ model

  /// [clearCarrier] = true بيمسح شركة الاتصالات (لأن null في [carrier]
  /// معناها "سيب القيمة القديمة" زي باقي الحقول).
  Wallet copyWith({
    String? name,
    WalletType? type,
    bool? archived,
    MobileCarrier? carrier,
    bool clearCarrier = false,
  }) {
    return Wallet(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      createdAt: createdAt,
      archived: archived ?? this.archived,
      carrier: clearCarrier ? null : (carrier ?? this.carrier),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'archived': archived,
        // الحقل بيتكتب بس لو موجود، عشان شكل الـ JSON للمحافظ القديمة
        // (والنسخ الاحتياطية القديمة) يفضل مطابق تمامًا.
        if (carrier != null) 'carrier': carrier!.name,
      };

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        id: json['id'] as String,
        name: json['name'] as String,
        type: WalletType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => WalletType.custom,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        archived: json['archived'] as bool? ?? false,
        carrier: _carrierFromJson(json['carrier']),
      );

  static MobileCarrier? _carrierFromJson(Object? raw) {
    if (raw is! String) return null;
    for (final c in MobileCarrier.values) {
      if (c.name == raw) return c;
    }
    return MobileCarrier.unknown;
  }
}
