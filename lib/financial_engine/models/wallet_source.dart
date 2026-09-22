import 'dart:math';

enum SourceType { sms, notification }

extension SourceTypeLabel on SourceType {
  String get labelAr {
    switch (this) {
      case SourceType.sms:          return 'رسائل SMS';
      case SourceType.notification:  return 'إشعارات التطبيق';
    }
  }
}

final _srcRng = Random();
String generateWalletSourceId() =>
    'ws_${DateTime.now().microsecondsSinceEpoch}_${_srcRng.nextInt(99999)}';

class WalletSource {
  final String id;
  final String walletId;      // FK → Wallet.id

  final SourceType sourceType;

  /// المعرّف الحقيقي من أندرويد — مش اسم تجميلي فقط.
  /// لـ SMS:          sender name ("VF-Cash", "AhlyBank", ...)
  /// لـ Notification: package name ("com.instapay.eg", ...)
  final String identifier;

  /// اسم للعرض في الـ UI (ممكن يختلف عن identifier)
  final String displayName;

  final bool enabled;

  const WalletSource({
    required this.id,
    required this.walletId,
    required this.sourceType,
    required this.identifier,
    required this.displayName,
    this.enabled = true,
  });

  WalletSource copyWith({
    String? walletId,
    bool? enabled,
    String? displayName,
  }) {
    return WalletSource(
      id: id,
      walletId: walletId ?? this.walletId,
      sourceType: sourceType,
      identifier: identifier,
      displayName: displayName ?? this.displayName,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'walletId': walletId,
        'sourceType': sourceType.name,
        'identifier': identifier,
        'displayName': displayName,
        'enabled': enabled,
      };

  factory WalletSource.fromJson(Map<String, dynamic> json) => WalletSource(
        id: json['id'] as String,
        walletId: json['walletId'] as String,
        sourceType: SourceType.values.firstWhere(
          (e) => e.name == json['sourceType'],
          orElse: () => SourceType.sms,
        ),
        identifier: json['identifier'] as String,
        displayName: json['displayName'] as String,
        enabled: json['enabled'] as bool? ?? true,
      );
}
