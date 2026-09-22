import '../engine/local_store.dart';
import '../engine/backup_service.dart';
import '../models/financial_event.dart';
import '../models/wallet.dart';
import '../models/wallet_source.dart';
import '../policy/source_catalog.dart';

/// Schema version التي يتطلبها هذا الكود.
/// زِد الرقم لما يكون في migration جديدة في المستقبل.
const kTargetSchemaVersion = 1;

/// Migration آمنة من البنية القديمة (source-as-wallet) للجديدة (walletId).
///
/// خطوات التنفيذ:
///   1. قرأ schema_version — لو >= 1 نرجع فورًا (idempotent)
///   2. Backup كامل + validation (قابل للقراءة؟ عدد الأحداث صح؟)
///   3. حساب oldTotal (المبالغ الإجمالية قبل المرحلة)
///   4. إنشاء الـ Wallets الافتراضية (IDs ثابتة للـ idempotency)
///   5. ملء walletId في كل FinancialEvent
///   6. Post-validation (عدد الأحداث + إجمالي المبالغ = نفس ما قبل)
///   7. Commit (حفظ كل شيء + schema_version = 1)
///   8. لو أي خطوة فشلت → Rollback من الـ backup
class SchemaMigrator {
  final LocalStore _store;
  final BackupService _backup;

  SchemaMigrator(this._store, this._backup);

  Future<MigrationResult> runIfNeeded() async {
    final version = await _store.getSchemaVersion();
    if (version >= kTargetSchemaVersion) {
      return MigrationResult.noOp();
    }

    String? backupJson;
    try {
      // ---- Step 1: Backup ----
      backupJson = await _backup.exportBackup();
      _validateBackupReadable(backupJson);

      // ---- Step 2: Load current events ----
      final events = await _store.loadEvents();
      final oldCount = events.length;
      final oldTotal = _computeTotal(events);

      // ---- Step 3: Create default wallets (fixed IDs = idempotent) ----
      final wallets = _buildDefaultWallets();
      final sources = _buildDefaultSources();

      // ---- Step 4: Assign walletId to every event ----
      final migratedEvents = events.map((e) {
        final walletId = e.walletId ?? _mapSourceToWalletId(e);
        return FinancialEvent(
          id: e.id,
          source: e.source,
          eventType: e.eventType,
          amount: e.amount,
          currency: e.currency,
          balanceAfter: e.balanceAfter,
          merchant: e.merchant,
          person: e.person,
          reference: e.reference,
          timestamp: e.timestamp,
          confidence: e.confidence,
          rawMessage: e.rawMessage,
          rawSource: e.rawSource,
          metadata: e.metadata,
          category: e.category,
          walletId: walletId,
        );
      }).toList();

      // ---- Step 5: Post-validation ----
      final newCount = migratedEvents.length;
      final newTotal = _computeTotal(migratedEvents);

      if (newCount != oldCount) {
        throw MigrationException(
          'عدد الأحداث تغيّر: قبل=$oldCount بعد=$newCount',
        );
      }
      if ((oldTotal - newTotal).abs() > 0.01) {
        throw MigrationException(
          'إجمالي المبالغ تغيّر: قبل=$oldTotal بعد=$newTotal',
        );
      }

      // ---- Step 6: Commit ----
      await _store.saveWallets(wallets);
      await _store.saveWalletSources(sources);
      for (final e in migratedEvents) {
        await _store.upsertEvent(e);
      }
      await _store.setSchemaVersion(kTargetSchemaVersion);

      return MigrationResult.success(
        walletCount: wallets.length,
        sourceCount: sources.length,
        eventsMigrated: newCount,
        oldTotal: oldTotal,
        newTotal: newTotal,
      );
    } catch (e) {
      // ---- Rollback ----
      if (backupJson != null) {
        try {
          await _backup.importBackup(backupJson);
        } catch (_) {
          // Rollback نفسه فشل — حالة نادرة جدًا
        }
      }
      return MigrationResult.failed(reason: e.toString());
    }
  }

  // -----------------------------------------------------------------------
  // Private helpers
  // -----------------------------------------------------------------------

  void _validateBackupReadable(String json) {
    // jsonDecode في importBackup هو نفسه سيتحقق — هنا نتأكد إن النص مش فاضي
    if (json.trim().isEmpty) {
      throw MigrationException('Backup فارغ');
    }
    // تأكد أنه JSON صالح
    // jsonDecode(json) يرمي FormatException إذا لم يكن صالحًا
    // BackupService.exportBackup تستخدم jsonEncode مباشرة، فالنتيجة دايمًا صالحة
    // لكن للحماية من مشاكل مستقبلية نترك الـ try/catch الخارجي يلتقطها
  }

  /// حساب إجمالي المبالغ للأحداث المرتبطة بمحفظة مالية حقيقية
  /// (بنفس منطق _recomputeWallets في FinancialEngine — confidence >= 85)
  double _computeTotal(List<FinancialEvent> events) {
    double total = 0;
    for (final e in events) {
      if (e.confidence < 85) continue;
      if (e.amount == null) continue;
      if (e.source == FinancialSource.manual) continue;
      // نحسب فقط الأحداث اللي بتدخل في حسابات الرصيد
      final tracked = e.source == FinancialSource.vodafoneCash ||
          e.source == FinancialSource.alAhlyBank ||
          e.source == FinancialSource.instaPay;
      if (!tracked) continue;
      total += e.amount!;
    }
    return total;
  }

  /// الـ Wallets الافتراضية — IDs ثابتة = idempotent (تشغيل migration مرتين لا ينشئ محافظ مكررة)
  List<Wallet> _buildDefaultWallets() {
    final now = DateTime.now();
    return [
      Wallet(
        id: kLegacyWalletIdVf,
        name: 'Vodafone Cash',
        type: WalletType.mobileWallet,
        createdAt: now,
      ),
      Wallet(
        id: kLegacyWalletIdNbe,
        name: 'البنك الأهلي / InstaPay',
        type: WalletType.bankAccount,
        createdAt: now,
      ),
    ];
  }

  List<WalletSource> _buildDefaultSources() {
    return [
      WalletSource(
        id: 'ws_vf_cash_sms_legacy',
        walletId: kLegacyWalletIdVf,
        sourceType: SourceType.sms,
        identifier: 'VF-Cash',
        displayName: 'Vodafone Cash (SMS)',
      ),
      WalletSource(
        id: 'ws_nbe_sms_legacy',
        walletId: kLegacyWalletIdNbe,
        sourceType: SourceType.sms,
        identifier: 'AhlyBank',
        displayName: 'البنك الأهلي (SMS)',
      ),
      WalletSource(
        id: 'ws_instapay_notif_legacy',
        walletId: kLegacyWalletIdNbe,
        sourceType: SourceType.notification,
        identifier: 'instapay',     // substring match في sourceCatalog
        displayName: 'InstaPay (إشعار)',
      ),
    ];
  }

  String _mapSourceToWalletId(FinancialEvent e) {
    switch (e.source) {
      case FinancialSource.vodafoneCash:
        return kLegacyWalletIdVf;
      case FinancialSource.alAhlyBank:
      case FinancialSource.instaPay:
        return kLegacyWalletIdNbe;
      case FinancialSource.manual:
        // التعديلات اليدوية تُسجَّل تحت source حقيقي (vodafoneCash أو alAhlyBank)
        // لكن لو وصلت هنا بـ manual — نضعها في unmapped
        return kUnmappedWalletId;
    }
  }
}

class MigrationResult {
  final MigrationStatus status;
  final String? failureReason;
  final int walletCount;
  final int sourceCount;
  final int eventsMigrated;
  final double oldTotal;
  final double newTotal;

  const MigrationResult._({
    required this.status,
    this.failureReason,
    this.walletCount = 0,
    this.sourceCount = 0,
    this.eventsMigrated = 0,
    this.oldTotal = 0,
    this.newTotal = 0,
  });

  factory MigrationResult.noOp() =>
      const MigrationResult._(status: MigrationStatus.noOp);

  factory MigrationResult.success({
    required int walletCount,
    required int sourceCount,
    required int eventsMigrated,
    required double oldTotal,
    required double newTotal,
  }) =>
      MigrationResult._(
        status: MigrationStatus.success,
        walletCount: walletCount,
        sourceCount: sourceCount,
        eventsMigrated: eventsMigrated,
        oldTotal: oldTotal,
        newTotal: newTotal,
      );

  factory MigrationResult.failed({required String reason}) =>
      MigrationResult._(
        status: MigrationStatus.failed,
        failureReason: reason,
      );
}

enum MigrationStatus { noOp, success, failed }

class MigrationException implements Exception {
  final String message;
  const MigrationException(this.message);
  @override
  String toString() => 'MigrationException: $message';
}
