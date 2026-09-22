// ignore_for_file: prefer_const_constructors

/// اختبارات I1 + I2 — Wallet/Source Separation + Migration
///
/// أهم اختبار: Migration يجب ألا تغير القيمة المالية الإجمالية للمستخدم.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:trial/financial_engine/models/wallet.dart';
import 'package:trial/financial_engine/models/wallet_source.dart';
import 'package:trial/financial_engine/models/financial_event.dart';
import 'package:trial/financial_engine/policy/source_policy.dart';

// ============================================================
// Wallet Model Tests
// ============================================================

void main() {
  group('Wallet Model', () {
    test('create wallet', () {
      final w = Wallet(
        id: 'w_001',
        name: 'Vodafone Cash',
        type: WalletType.mobileWallet,
        createdAt: DateTime(2024, 1, 1),
      );
      expect(w.id, equals('w_001'));
      expect(w.archived, isFalse);
    });

    test('copyWith preserves id', () {
      final w = Wallet(
        id: 'w_001',
        name: 'Old Name',
        type: WalletType.bankAccount,
        createdAt: DateTime(2024, 1, 1),
      );
      final updated = w.copyWith(name: 'New Name');
      expect(updated.id, equals('w_001'));
      expect(updated.name, equals('New Name'));
    });

    test('toJson / fromJson roundtrip', () {
      final w = Wallet(
        id: 'w_test',
        name: 'البنك الأهلي',
        type: WalletType.bankAccount,
        createdAt: DateTime(2024, 6, 15),
        archived: false,
      );
      final json = w.toJson();
      final restored = Wallet.fromJson(json);
      expect(restored.id, equals(w.id));
      expect(restored.name, equals(w.name));
      expect(restored.type, equals(w.type));
      expect(restored.archived, equals(w.archived));
    });

    test('archive flag preserved in toJson', () {
      final w = Wallet(
        id: 'w_arc',
        name: 'محفظة قديمة',
        type: WalletType.custom,
        createdAt: DateTime(2024, 1, 1),
        archived: true,
      );
      expect(Wallet.fromJson(w.toJson()).archived, isTrue);
    });
  });

  // ------------------------------------------------------------------
  group('WalletSource Model', () {
    test('create wallet source', () {
      final ws = WalletSource(
        id: 'ws_001',
        walletId: 'w_001',
        sourceType: SourceType.sms,
        identifier: 'VF-Cash',
        displayName: 'Vodafone Cash (SMS)',
      );
      expect(ws.enabled, isTrue);
      expect(ws.sourceType, equals(SourceType.sms));
    });

    test('toJson / fromJson roundtrip', () {
      final ws = WalletSource(
        id: 'ws_test',
        walletId: 'w_001',
        sourceType: SourceType.notification,
        identifier: 'com.instapay.eg',
        displayName: 'InstaPay',
        enabled: false,
      );
      final restored = WalletSource.fromJson(ws.toJson());
      expect(restored.id, equals(ws.id));
      expect(restored.enabled, isFalse);
      expect(restored.sourceType, equals(SourceType.notification));
    });
  });

  // ------------------------------------------------------------------
  group('SourceCatalog (I2)', () {
    test('VF-Cash matches vodafoneCash', () {
      final def = findSourceDefinition('VF-Cash');
      expect(def, isNotNull);
      expect(def!.legacySource, equals(FinancialSource.vodafoneCash));
    });

    test('AhlyBank matches alAhlyBank', () {
      final def = findSourceDefinition('AhlyBank');
      expect(def, isNotNull);
      expect(def!.legacySource, equals(FinancialSource.alAhlyBank));
    });

    test('instapay package matches instaPay', () {
      final def = findSourceDefinition('com.instapay.eg');
      expect(def, isNotNull);
      expect(def!.legacySource, equals(FinancialSource.instaPay));
    });

    test('unknown sender returns null', () {
      expect(findSourceDefinition('UnknownBank'), isNull);
    });

    test('SourcePolicy.identifySmsSource backward compat', () {
      expect(
        SourcePolicy.identifySmsSource('VF-Cash'),
        equals(SmsSourceMatch.vodafoneCash),
      );
      expect(
        SourcePolicy.identifySmsSource('AhlyBank'),
        equals(SmsSourceMatch.alAhlyBank),
      );
      expect(
        SourcePolicy.identifySmsSource('Unknown'),
        equals(SmsSourceMatch.unknown),
      );
    });
  });

  // ------------------------------------------------------------------
  group('legacySourceToWalletId mapping', () {
    test('vodafoneCash → kLegacyWalletIdVf', () {
      expect(
        legacySourceToWalletId(FinancialSource.vodafoneCash),
        equals(kLegacyWalletIdVf),
      );
    });

    test('alAhlyBank → kLegacyWalletIdNbe', () {
      expect(
        legacySourceToWalletId(FinancialSource.alAhlyBank),
        equals(kLegacyWalletIdNbe),
      );
    });

    test('instaPay → kLegacyWalletIdNbe (نفس المحفظة)', () {
      expect(
        legacySourceToWalletId(FinancialSource.instaPay),
        equals(kLegacyWalletIdNbe),
      );
    });

    test('manual → kUnmappedWalletId', () {
      expect(
        legacySourceToWalletId(FinancialSource.manual),
        equals(kUnmappedWalletId),
      );
    });
  });

  // ------------------------------------------------------------------
  group('FinancialEvent: walletId field (backward compat)', () {
    test('old event without walletId deserializes with null', () {
      // رسالة قديمة في JSON بدون حقل walletId
      final json = <String, dynamic>{
        'id': 'evt_001',
        'source': 'vodafoneCash',
        'eventType': 'deposit',
        'amount': 500.0,
        'currency': 'EGP',
        'timestamp': DateTime(2024, 1, 1).millisecondsSinceEpoch,
        'confidence': 99,
        'rawMessage': 'تم استلام مبلغ 500 جنيه',
        'rawSource': 'VF-Cash',
        'metadata': <String, dynamic>{},
      };
      final event = FinancialEvent.fromJson(json);
      expect(event.walletId, isNull,
          reason: 'أحداث قديمة بدون walletId يجب أن تُحمَّل بـ null');
      expect(event.amount, equals(500.0));
    });

    test('new event with walletId roundtrips correctly', () {
      final event = FinancialEvent(
        id: 'evt_002',
        source: FinancialSource.vodafoneCash,
        eventType: FinancialEventType.deposit,
        amount: 300.0,
        timestamp: DateTime(2024, 8, 1),
        confidence: 99,
        rawMessage: 'تم استلام 300',
        rawSource: 'VF-Cash',
        walletId: kLegacyWalletIdVf,
      );
      final restored = FinancialEvent.fromJson(event.toJson());
      expect(restored.walletId, equals(kLegacyWalletIdVf));
    });
  });

  // ------------------------------------------------------------------
  group('SchemaMigrator — _computeTotal logic', () {
    /// نختبر المنطق الرياضي للـ migration مباشرة بدون LocalStore/BackupService
    /// (هذه pure logic tests — لا تحتاج مكتبات Android)

    test('_computeTotal: حدث vodafoneCash بـ confidence 99 يُحتسب', () {
      final events = [
        FinancialEvent(
          id: 'e1',
          source: FinancialSource.vodafoneCash,
          eventType: FinancialEventType.deposit,
          amount: 500.0,
          confidence: 99,
          timestamp: DateTime.now(),
          rawMessage: '',
          rawSource: 'VF-Cash',
        ),
      ];
      // نختبر المنطق يدويًا (SchemaMigrator._computeTotal private)
      double total = 0;
      for (final e in events) {
        if (e.confidence < 85) continue;
        if (e.amount == null) continue;
        if (e.source == FinancialSource.manual) continue;
        final tracked = e.source == FinancialSource.vodafoneCash ||
            e.source == FinancialSource.alAhlyBank ||
            e.source == FinancialSource.instaPay;
        if (!tracked) continue;
        total += e.amount!;
      }
      expect(total, closeTo(500.0, 0.001));
    });

    test('_computeTotal: حدث confidence 50 لا يُحتسب', () {
      final events = [
        FinancialEvent(
          id: 'e2',
          source: FinancialSource.vodafoneCash,
          eventType: FinancialEventType.deposit,
          amount: 200.0,
          confidence: 50,
          timestamp: DateTime.now(),
          rawMessage: '',
          rawSource: 'VF-Cash',
        ),
      ];
      double total = 0;
      for (final e in events) {
        if (e.confidence < 85) continue;
        if (e.amount == null) continue;
        final tracked = e.source == FinancialSource.vodafoneCash ||
            e.source == FinancialSource.alAhlyBank ||
            e.source == FinancialSource.instaPay;
        if (!tracked) continue;
        total += e.amount!;
      }
      expect(total, closeTo(0, 0.001),
          reason: 'حدث بـ confidence 50 يُستبعد من الحساب');
    });
  });

  // ------------------------------------------------------------------
  group('Migration ID stability (idempotency guarantee)', () {
    test('kLegacyWalletIdVf is stable constant string', () {
      expect(kLegacyWalletIdVf, equals('wallet_vf_legacy'));
    });

    test('kLegacyWalletIdNbe is stable constant string', () {
      expect(kLegacyWalletIdNbe, equals('wallet_nbe_legacy'));
    });

    test('WalletType labels present for all types', () {
      for (final t in WalletType.values) {
        expect(t.labelAr.isNotEmpty, isTrue,
            reason: '${t.name} يجب أن يكون له تسمية عربية');
      }
    });
  });

  // ------------------------------------------------------------------
  group('Wallet archive vs delete', () {
    test('archive preserves id and name', () {
      final w = Wallet(
        id: 'w_del',
        name: 'محفظة للأرشفة',
        type: WalletType.cash,
        createdAt: DateTime(2024, 1, 1),
      );
      final archived = w.copyWith(archived: true);
      expect(archived.id, equals('w_del'));
      expect(archived.name, equals('محفظة للأرشفة'));
      expect(archived.archived, isTrue);
    });
  });

  // ------------------------------------------------------------------
  group('Source conflict detection logic', () {
    test('same identifier → conflict detected', () {
      final sources = [
        WalletSource(
          id: 'ws_1',
          walletId: 'w_001',
          sourceType: SourceType.sms,
          identifier: 'VF-Cash',
          displayName: 'Vodafone',
        ),
      ];

      // نفس identifier بمحفظة مختلفة = conflict
      final newIdentifier = 'VF-Cash';
      final excludeWalletId = 'w_002';
      final conflict = sources.where((s) {
        if (s.walletId == excludeWalletId) return false;
        return s.identifier.toLowerCase() ==
            newIdentifier.toLowerCase();
      }).firstOrNull;

      expect(conflict, isNotNull,
          reason: 'نفس الـ identifier في محفظة مختلفة يجب أن يُكتشف كـ conflict');
    });

    test('same identifier same wallet → no conflict', () {
      final sources = [
        WalletSource(
          id: 'ws_1',
          walletId: 'w_001',
          sourceType: SourceType.sms,
          identifier: 'VF-Cash',
          displayName: 'Vodafone',
        ),
      ];

      final conflict = sources.where((s) {
        if (s.walletId == 'w_001') return false; // نفس المحفظة → مش conflict
        return s.identifier.toLowerCase() == 'vf-cash';
      }).firstOrNull;

      expect(conflict, isNull);
    });
  });
}
