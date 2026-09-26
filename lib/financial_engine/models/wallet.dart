import 'dart:math';

enum WalletType {
  cash,          // نقدي — فلوس الجيب
  bankAccount,   // حساب بنكي
  mobileWallet,  // محفظة إلكترونية (Vodafone Cash، إلخ)
  card,          // بطاقة ائتمان/خصم
  instaPay,      // InstaPay
  custom,        // أخرى
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

  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    this.archived = false,
  });

  /// Balance = مشتقّ دائمًا من الأحداث (FinancialEngine._recomputeWallets)
  /// ولا يُخزَّن هنا — مفيش حقل balance في الـ model

  Wallet copyWith({String? name, WalletType? type, bool? archived}) {
    return Wallet(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      createdAt: createdAt,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'archived': archived,
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
      );
}
