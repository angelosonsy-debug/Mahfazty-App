import 'dart:convert';

import '../models/financial_event.dart';
import '../models/client.dart';
import '../models/wallet.dart';
import '../models/wallet_source.dart';
import 'local_store.dart';

/// نسخ احتياطي محلي بالكامل - من غير أي مكتبة جديدة (Clipboard بس، جزء
/// أساسي من Flutter SDK نفسه). النسخة بتتحول لنص JSON تقدر تنسخه وتحفظه
/// فين ما حبيت (تطبيق ملاحظات، إيميل لنفسك، أي حاجة) وترجّعه وقت ما
/// تحتاج.
///
/// ملحوظة: عمدًا مفيش file_picker ولا share_plus ولا أي مكتبة تانية ليها
/// كود Android أصلي - بعد تجربتنا مع Drift/jni قبل كده، مش هخاطر بمكتبة
/// جديدة ليها سطح Gradle/Kotlin من غير ما أقدر أتأكد إنها هتبني صح.
/// النص اللي بيتنسخ فعليًا "ملف" بمعنى إنه بيانات كاملة قابلة للحفظ
/// والاستعادة، بس النقل بيتم عن طريق الـ Clipboard بدل ملف على القرص.
class BackupService {
  final LocalStore _store;
  static const _backupVersion = 1;

  BackupService(this._store);

  Future<String> exportBackup() async {
    final events = await _store.loadEvents();
    final clients = await _store.loadClients();
    final transactions = await _store.loadDebtTransactions();
    final pocketAdjustments = await _store.loadPocketAdjustments();
    final learningMemory = await _store.loadLearningMemory();

    final backup = {
      'backupVersion': _backupVersion,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'events': events.map((e) => e.toJson()).toList(),
      'clients': clients.map((c) => c.toJson()).toList(),
      'debtTransactions': transactions.map((t) => t.toJson()).toList(),
      'pocketAdjustments': pocketAdjustments.map((p) => p.toJson()).toList(),
      'learningMemory': learningMemory.map((k, v) => MapEntry(k, v.name)),
      // I1: إضافة المحافظ والمصادر للنسخة الاحتياطية
      'wallets': (await _store.loadWallets()).map((w) => w.toJson()).toList(),
      'walletSources': (await _store.loadWalletSources()).map((s) => s.toJson()).toList(),
      'schemaVersion': 1,
      // مفتاح الـ AI عمدًا مش بيتضاف للنسخة الاحتياطية - حاجة حساسة، ولو
      // حد تاني شاف نص النسخة (لصقه في مكان غلط) منريدوش يشوف مفتاحك.
    };

    return jsonEncode(backup);
  }

  /// بيرجع عدد العناصر اللي اتستعادت، أو بيرمي استثناء لو النص مش نسخة
  /// احتياطية صالحة (JSON فاسد أو بنية غير متوقعة)
  Future<BackupRestoreResult> importBackup(String backupText) async {
    final decoded = jsonDecode(backupText) as Map<String, dynamic>;

    final events = (decoded['events'] as List? ?? [])
        .map((e) => FinancialEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    final clients =
        (decoded['clients'] as List? ?? []).map((c) => Client.fromJson(c as Map<String, dynamic>)).toList();
    final transactions = (decoded['debtTransactions'] as List? ?? [])
        .map((t) => DebtTransaction.fromJson(t as Map<String, dynamic>))
        .toList();

    // R1: كل نوع بيانات بكتابة واحدة بدل upsert منفصل لكل عنصر — الطريقة
    // القديمة كانت بتعمل قراءة+فك+ترميز+كتابة لكل الملف مع كل عنصر لوحده
    // (O(n) كاملة لكل n)، وده كان بطيء على نسخة فيها مئات العناصر وكمان
    // بيوسّع نافذة التداخل مع أي ingest حي بشكل غير داعي. الكتابة الواحدة
    // هنا بتتسلسل مع الـ ingest queue من المستدعي (FinancialEngine.restoreBackup)
    // مش من هنا.
    await _store.mergeEvents(events);
    await _store.mergeClients(clients);
    await _store.mergeDebtTransactions(transactions);

    // I1: استعادة المحافظ والمصادر (لو موجودين في النسخة)
    final wallets = (decoded['wallets'] as List? ?? [])
        .map((w) => Wallet.fromJson(w as Map<String, dynamic>))
        .toList();
    final walletSources = (decoded['walletSources'] as List? ?? [])
        .map((s) => WalletSource.fromJson(s as Map<String, dynamic>))
        .toList();
    await _store.mergeWallets(wallets);
    await _store.mergeWalletSources(walletSources);

    final pocketAdjustments = (decoded['pocketAdjustments'] as List? ?? [])
        .map((p) => PocketAdjustmentRow.fromJson(p as Map<String, dynamic>))
        .toList();
    await _store.mergePocketAdjustments(pocketAdjustments);

    final learningMemoryRaw = decoded['learningMemory'] as Map<String, dynamic>? ?? {};
    final learningMemory = <String, FinancialEventType>{};
    for (final entry in learningMemoryRaw.entries) {
      try {
        learningMemory[entry.key] =
            FinancialEventType.values.firstWhere((t) => t.name == entry.value);
      } catch (_) {
        // نوع غير معروف في النسخة الاحتياطية - نتجاهله بدل ما نوقف الاستعادة كلها
      }
    }
    await _store.mergeLearningMemory(learningMemory);

    return BackupRestoreResult(
      eventsCount: events.length,
      clientsCount: clients.length,
      transactionsCount: transactions.length,
    );
  }
}

class BackupRestoreResult {
  final int eventsCount;
  final int clientsCount;
  final int transactionsCount;

  const BackupRestoreResult({
    required this.eventsCount,
    required this.clientsCount,
    required this.transactionsCount,
  });
}
