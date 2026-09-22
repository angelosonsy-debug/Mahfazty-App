import 'package:flutter/foundation.dart';

import '../models/financial_event.dart';
import '../models/client.dart';
import '../models/wallet.dart';
import '../models/wallet_source.dart';
import '../policy/source_catalog.dart';
import 'local_store.dart';
import '../../core/utils/message_fingerprint.dart';

/// المصدر الوحيد لتحديث أي رصيد. أي شاشة عايزة تعدّل حاجة (بوكيت، ديون،
/// رصيد محفظة) لازم تعدي من هنا، مش تلمس أي state تاني مباشرة.
///
/// قاعدة مصادر InstaPay: مفيش عزل بين إشعار InstaPay ورسالة SMS البنك
/// الأهلي - لو نفس المبلغ ونفس النافذة الزمنية (دقيقتين)، بيتعتبروا نفس
/// المعاملة وبيتدمجوا في حدث واحد موثوق (ثقة 99). إشعار InstaPay لوحده
/// من غير تطابق بيفضل بثقة محدودة في صندوق المراجعة لحد ما يتأكد يدويًا
/// أو يتطابق مع رسالة بنك تجيله.
class FinancialEngine extends ChangeNotifier {
  final LocalStore _store;

  FinancialEngine(this._store);

  /// نافذة اكتشاف "نفس الإشعار/الرسالة اتكرر" من نفس المصدر (أندرويد
  /// بيعيد نشر إشعارات/يعيد تسليم رسائل أحيانًا)
  static const _repostWindow = Duration(seconds: 90);

  /// نافذة دمج المعاملة الواحدة عبر مصادر مختلفة (InstaPay + البنك
  /// الأهلي) - ثابتة عند دقيقتين لكل المصادر زي ما اتحدد.
  static const _crossSourceMergeWindow = Duration(minutes: 2);

  final List<FinancialEvent> events = [];

  /// Backward-compat — الـ tests القديمة تمرر FinancialSource مباشرة.
  Future<void> setWalletBalanceManuallyBySource(
      FinancialSource source, double value) async {
    await setWalletBalanceManually(legacySourceToWalletId(source), value);
  }

  /// I1: الرصيد مفتاحه walletId (String) بدل FinancialSource (enum)
  final Map<String, double?> walletBalances = {};

  /// الـ wallets والـ sources المرتبطة بهم (بتُحمَّل من LocalStore)
  final List<Wallet> wallets = [];
  final List<WalletSource> walletSources = [];
  final List<Client> clients = [];
  final List<DebtTransaction> debtTransactions = [];
  final List<PocketAdjustmentRow> pocketHistory = [];
  double pocketBalance = 0;
  Map<String, FinancialEventType> _learningMemory = {};

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final storedEvents = await _store.loadEvents();
    events
      ..clear()
      ..addAll(storedEvents);
    _recomputeWallets();

    clients
      ..clear()
      ..addAll(await _store.loadClients());

    debtTransactions
      ..clear()
      ..addAll(await _store.loadDebtTransactions());

    pocketHistory
      ..clear()
      ..addAll(await _store.loadPocketAdjustments());
    pocketBalance = pocketHistory.fold(0.0, (s, a) => s + a.delta);

    _learningMemory = await _store.loadLearningMemory();

    // I1: تحميل المحافظ والمصادر
    wallets
      ..clear()
      ..addAll(await _store.loadWallets());
    walletSources
      ..clear()
      ..addAll(await _store.loadWalletSources());

    _loaded = true;
    notifyListeners();
  }

  /// I1: بيحسب رصيد كل محفظة بالـ walletId بدل الـ source enum.
  ///
  /// للأحداث القديمة (walletId = null): نرجع للـ source-based logic القديمة
  /// كـ backward compat مؤقت (سيُزال في مرحلة لاحقة بعد migration كاملة).
  ///
  /// نفس القواعد القديمة: confidence >= 85، balanceAfter كـ anchor.
  void _recomputeWallets() {
    walletBalances.clear();

    final chronological = events.reversed;
    for (final e in chronological) {
      if (e.confidence < 85) continue;

      // تحديد الـ walletId الفعلي للحدث
      String? wId = e.walletId;

      // Backward compat للأحداث القديمة (قبل migration)
      if (wId == null) {
        if (e.source == FinancialSource.vodafoneCash) {
          wId = kLegacyWalletIdVf;
        } else if (e.source == FinancialSource.alAhlyBank ||
            e.source == FinancialSource.instaPay) {
          wId = kLegacyWalletIdNbe;
        } else {
          continue; // manual / unmapped — مش بيدخل في حسابات الرصيد
        }
      }
      if (wId == kUnmappedWalletId) continue;

      if (e.balanceAfter != null) {
        walletBalances[wId] = e.balanceAfter;
        continue;
      }
      if (e.amount == null) continue;
      double? delta;
      // I4: walletTransfer أنواعه الجديدة تؤثر على الرصيد لكن مش على income/expense
      if (e.eventType == FinancialEventType.walletTransferIn) {
        delta = e.amount; // إضافة للمحفظة المستهدفة
      } else if (e.eventType == FinancialEventType.walletTransferOut) {
        delta = -e.amount!; // خصم من المحفظة المصدر
      } else if (isIncomingEventType(e.eventType)) {
        delta = e.amount;
      } else if (isOutgoingEventType(e.eventType)) {
        delta = -e.amount!;
      }
      if (delta == null) continue;
      walletBalances[wId] = (walletBalances[wId] ?? 0) + delta;
    }
  }

  /// أي حدث مالي جديد (جاي من SMS، بعد ما يمر على القواعد وربما الـ AI
  /// المساعد) لازم يعدي من هنا.
  Future<void> ingest(FinancialEvent event) async {
    final learned = _applyLearning(event);

    if (_isDuplicateRepost(learned)) {
      return; // نفس الرسالة اتكررت (أندرويد بيعيد تسليم إشعارات/رسائل أحيانًا)
    }

    if (await _tryReconcile(learned)) {
      _recomputeWallets();
      notifyListeners();
      return;
    }

    events.insert(0, learned);
    await _store.upsertEvent(learned);
    _recomputeWallets();
    notifyListeners();
  }

  bool _isTwinSource(FinancialSource a, FinancialSource b) {
    return (a == FinancialSource.instaPay && b == FinancialSource.alAhlyBank) ||
        (a == FinancialSource.alAhlyBank && b == FinancialSource.instaPay);
  }

  /// بيدور على حدث "توأم" (إشعار InstaPay <-> رسالة SMS البنك الأهلي)
  /// بنفس المبلغ تقريبًا وفي نفس نافذة الدمج (دقيقتين)، ويدمجهم في حدث
  /// واحد موثوق بدل ما يتحسبوا مرتين أو يتعرضوا للمراجعة مرتين منفصلتين.
  Future<bool> _tryReconcile(FinancialEvent newEvent) async {
    if (newEvent.amount == null) return false;
    if (newEvent.source != FinancialSource.instaPay &&
        newEvent.source != FinancialSource.alAhlyBank) {
      return false;
    }

    final matchIndex = events.indexWhere((e) {
      if (!_isTwinSource(e.source, newEvent.source)) return false;
      if (e.amount == null) return false;
      if ((e.amount! - newEvent.amount!).abs() > 0.01) return false;
      if (newEvent.timestamp.difference(e.timestamp).abs() > _crossSourceMergeWindow) return false;
      if (e.metadata['reconciled'] == true) return false;
      // لو الاتجاه معروف في الاتنين ومختلف، مش نفس المعاملة
      if (e.eventType != FinancialEventType.unknown &&
          newEvent.eventType != FinancialEventType.unknown &&
          isIncomingEventType(e.eventType) != isIncomingEventType(newEvent.eventType)) {
        return false;
      }
      return true;
    });

    if (matchIndex == -1) return false;

    final existing = events[matchIndex];
    final bankEvent = existing.source == FinancialSource.alAhlyBank ? existing : newEvent;
    final instaEvent = existing.source == FinancialSource.instaPay ? existing : newEvent;
    final earlier =
        bankEvent.timestamp.isBefore(instaEvent.timestamp) ? bankEvent.timestamp : instaEvent.timestamp;

    // البنك الأهلي بيديّنا تفاصيل أدق (مرجع/تاجر/شخص) - نفضله كمصدر
    // البيانات، بس بنسجل الحدث المدموج تحت InstaPay لأنه ده اللي المستخدم
    // فعليًا شايفه كمحفظة في التطبيق.
    final merged = FinancialEvent(
      id: generateEventId(),
      source: FinancialSource.instaPay,
      eventType: bankEvent.eventType != FinancialEventType.unknown ? bankEvent.eventType : instaEvent.eventType,
      amount: bankEvent.amount ?? instaEvent.amount,
      balanceAfter: bankEvent.balanceAfter ?? instaEvent.balanceAfter,
      merchant: bankEvent.merchant ?? instaEvent.merchant,
      person: bankEvent.person ?? instaEvent.person,
      reference: bankEvent.reference ?? instaEvent.reference,
      timestamp: earlier,
      confidence: 99,
      rawMessage: 'InstaPay: ${instaEvent.rawMessage}\n---\nالبنك الأهلي: ${bankEvent.rawMessage}',
      rawSource: '${instaEvent.rawSource} + ${bankEvent.rawSource}',
      metadata: {
        'reconciled': true,
        'mergedFrom': [instaEvent.id, bankEvent.id],
      },
    );

    events.removeAt(matchIndex);
    events.insert(0, merged);
    await _store.deleteEvent(existing.id);
    await _store.upsertEvent(merged);
    return true;
  }

  /// لو سبق وصححنا رسالة بنفس "الشكل" (نفس النص من غير الأرقام)، نطبق
  /// نفس التصنيف تلقائي على أي رسالة جديدة شبهها.
  FinancialEvent _applyLearning(FinancialEvent event) {
    if (event.eventType != FinancialEventType.unknown && event.confidence >= 85) return event;
    final fingerprint = MessageFingerprint.of(event.rawMessage);
    final learnedType = _learningMemory[fingerprint];
    if (learnedType == null) return event;
    return event.copyWith(
      eventType: learnedType,
      confidence: 95,
      metadata: {...event.metadata, 'appliedFromLearning': true},
    );
  }

  /// رسالة بنفس النص تقريبًا من نفس المصدر وصلت قبل كده بثواني قليلة -
  /// على الأغلب نفس الرسالة اتكررت، مش معاملة جديدة فعلًا.
  ///
  /// Bug Fix: التعديل اليدوي (manualAdjustment) لازم يتستثنى تمامًا من
  /// الفحص ده. كل تعديل يدوي بيتسجل بنفس rawMessage الثابت ('تعديل يدوي
  /// للرصيد') وبـ amount = null (بيحط balanceAfter بس مش amount)، فلو
  /// المستخدم عدّل رصيد نفس المحفظة أكتر من مرة خلال 90 ثانية (زي أي حد
  /// بيصلّح رقم غلط بسرعة، أو حتى تيست بيعمل كذا نداء ورا بعض)، كان بيتحسب
  /// "نفس الرسالة اتكررت" وبيتجاهل بالكامل - فأول قيمة اتحطت تفضل عالقة
  /// للأبد وأي تعديل بعدها بيضيع من غير أي رسالة خطأ. التعديل اليدوي فعل
  /// مقصود من المستخدم دايمًا، مش إشعار ممكن يتكرر بالغلط، فمينفعش يتفلتر
  /// كـ repost أبدًا.
  bool _isDuplicateRepost(FinancialEvent newEvent) {
    if (newEvent.eventType == FinancialEventType.manualAdjustment) return false;
    return events.any((e) {
      if (e.source != newEvent.source) return false;
      if (newEvent.timestamp.difference(e.timestamp).abs() > _repostWindow) return false;
      if (newEvent.reference != null && e.reference != null) {
        return newEvent.reference == e.reference;
      }
      if (newEvent.amount != null &&
          e.amount != null &&
          (newEvent.amount! - e.amount!).abs() > 0.01) {
        return false;
      }
      return e.rawMessage == newEvent.rawMessage;
    });
  }

  /// Backward-compat getter — الـ tests القديمة تستخدم walletBalance[FinancialSource.x].
  /// بعد I1 الـ source of truth هو walletBalances (keyed by walletId string).
  Map<FinancialSource, double?> get walletBalance => {
    FinancialSource.vodafoneCash: walletBalances[kLegacyWalletIdVf],
    FinancialSource.alAhlyBank:   walletBalances[kLegacyWalletIdNbe],
    FinancialSource.instaPay:     walletBalances[kLegacyWalletIdNbe],
    FinancialSource.manual:       null,
  };

  /// I1: مجموع أرصدة كل المحافظ النشطة (غير المؤرشفة)
  double get walletsTotal {
    double total = 0;
    for (final entry in walletBalances.entries) {
      if (entry.key == kUnmappedWalletId) continue;
      total += entry.value ?? 0;
    }
    return total;
  }

  /// رصيد محفظة معينة بـ walletId
  double? balanceForWallet(String walletId) => walletBalances[walletId];

  // ---------------------------------------------------------------------
  // ديون: عميل + معاملات جواه (مش List مفلطحة)
  // ---------------------------------------------------------------------

  double theyOweUsTotal(String clientId) => debtTransactions
      .where((t) => t.clientId == clientId && t.direction == DebtEntryDirection.theyOweUs)
      .fold(0.0, (s, t) => s + t.amount);

  double weOweThemTotal(String clientId) => debtTransactions
      .where((t) => t.clientId == clientId && t.direction == DebtEntryDirection.weOweThem)
      .fold(0.0, (s, t) => s + t.amount);

  /// الصافي لعميل واحد - موجب يعني هو مديون لينا، سالب يعني احنا مديونين له
  double clientNet(String clientId) => theyOweUsTotal(clientId) - weOweThemTotal(clientId);

  List<DebtTransaction> transactionsForClient(String clientId) =>
      debtTransactions.where((t) => t.clientId == clientId).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  /// إجمالي "كام لينا عند كل العملاء" على مستوى التطبيق كله
  double get moneyOwedToMe => debtTransactions
      .where((t) => t.direction == DebtEntryDirection.theyOweUs)
      .fold(0.0, (s, t) => s + t.amount);

  /// إجمالي "كام علينا لكل العملاء" على مستوى التطبيق كله
  double get moneyIOwe =>
      debtTransactions.where((t) => t.direction == DebtEntryDirection.weOweThem).fold(0.0, (s, t) => s + t.amount);

  double get netWorth => pocketBalance + walletsTotal + moneyOwedToMe - moneyIOwe;

  Future<void> addClient(Client client) async {
    clients.insert(0, client);
    await _store.upsertClient(client);
    notifyListeners();
  }

  /// تعديل اسم/ملاحظات العميل - المعاملات مرتبطة بـ clientId ثابت،
  /// فمش محتاجة أي تحديث لما نغيّر الاسم بس.
  Future<void> updateClient(String id, {String? name, String? notes}) async {
    final index = clients.indexWhere((c) => c.id == id);
    if (index == -1) return;
    final current = clients[index];
    final updated = Client(
      id: current.id,
      name: name ?? current.name,
      notes: notes ?? current.notes,
      createdAt: current.createdAt,
    );
    clients[index] = updated;
    await _store.upsertClient(updated);
    notifyListeners();
  }

  Future<void> deleteClient(String id) async {
    clients.removeWhere((c) => c.id == id);
    debtTransactions.removeWhere((t) => t.clientId == id);
    await _store.deleteClient(id);
    notifyListeners();
  }

  Future<void> addDebtTransaction(DebtTransaction transaction) async {
    debtTransactions.insert(0, transaction);
    await _store.upsertDebtTransaction(transaction);
    notifyListeners();
  }

  Future<void> updateDebtTransaction(String id, {double? amount, String? note}) async {
    final index = debtTransactions.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final current = debtTransactions[index];
    final updated = DebtTransaction(
      id: current.id,
      clientId: current.clientId,
      direction: current.direction,
      amount: amount ?? current.amount,
      note: note ?? current.note,
      timestamp: current.timestamp,
    );
    debtTransactions[index] = updated;
    await _store.upsertDebtTransaction(updated);
    notifyListeners();
  }

  Future<void> deleteDebtTransaction(String id) async {
    debtTransactions.removeWhere((t) => t.id == id);
    await _store.deleteDebtTransaction(id);
    notifyListeners();
  }

  /// كل الأحداث اللي لسه محتاجة مراجعتك (ثقة أقل من صندوق المراجعة) -
  /// دي جوهر "Inbox" - أي حدث جديد بيتصنف تلقائي لـ Auto Apply (ثقة
  /// عالية، بيأثر على الرصيد على طول) أو Review (هنا، محتاج تأكيدك).
  List<FinancialEvent> get pendingReview => events.where((e) => e.confidence < 85).toList();

  /// الأحداث اللي اتطبقت فعلًا (Auto Apply) - ظهرت في الأرصدة من غير
  /// ما تحتاج مراجعة
  List<FinancialEvent> get autoAppliedEvents => events.where((e) => e.confidence >= 85).toList();

  // ---------------------------------------------------------------------
  // Pocket - يدوي بالكامل، الرصيد = مجموع كل التعديلات (بيدينا History مجانًا)
  // ---------------------------------------------------------------------

  Future<void> addPocketAdjustment(double delta, {String? note}) async {
    final id = generateEventId();
    await _store.addPocketAdjustment(id, delta, note);
    pocketHistory.insert(
      0,
      PocketAdjustmentRow(
        id: id,
        delta: delta,
        note: note,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    pocketBalance += delta;
    notifyListeners();
  }

  Future<void> setPocketBalanceAbsolute(double value) async {
    final delta = value - pocketBalance;
    if (delta == 0) return;
    await addPocketAdjustment(delta, note: 'ضبط يدوي للرصيد');
  }

  // ---------------------------------------------------------------------
  // تعديل يدوي (على معاملة واحدة، أو رصيد محفظة كامل) + التقاط التعلم
  // ---------------------------------------------------------------------

  Future<void> updateEventManually(
    String id, {
    double? amount,
    double? balanceAfter,
    FinancialEventType? eventType,
  }) async {
    final index = events.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final original = events[index];

    final updated = original.copyWith(
      amount: amount,
      balanceAfter: balanceAfter,
      eventType: eventType,
      confidence: 99,
      metadata: {...original.metadata, 'manuallyEdited': true},
    );
    events[index] = updated;
    await _store.upsertEvent(updated);

    // لو المستخدم حدد نوع عملية واضح لحدث كان غامض، نتعلم من الرسالة
    // دي عشان أي رسالة شبهها بعد كده تتصنف صح من غير ما نسأل تاني
    if (eventType != null &&
        eventType != FinancialEventType.unknown &&
        original.eventType != eventType) {
      final fingerprint = MessageFingerprint.of(original.rawMessage);
      _learningMemory[fingerprint] = eventType;
      await _store.saveLearningCorrection(fingerprint, eventType);
    }

    _recomputeWallets();
    notifyListeners();
  }

  Future<void> confirmEvent(String id) async {
    final index = events.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final updated = events[index].copyWith(
      confidence: 99,
      metadata: {...events[index].metadata, 'userConfirmed': true},
    );
    events[index] = updated;
    await _store.upsertEvent(updated);
    _recomputeWallets();
    notifyListeners();
  }

  Future<void> deleteEvent(String id) async {
    events.removeWhere((e) => e.id == id);
    await _store.deleteEvent(id);
    _recomputeWallets();
    notifyListeners();
  }

  /// I1: تعديل رصيد محفظة بـ walletId (بدل FinancialSource)
  Future<void> setWalletBalanceManually(String walletId, double value) async {
    // نحدد الـ legacySource المقابل للـ walletId (للتوافق مع _tryReconcile الحالي)
    final FinancialSource legacySource;
    if (walletId == kLegacyWalletIdVf) {
      legacySource = FinancialSource.vodafoneCash;
    } else if (walletId == kLegacyWalletIdNbe) {
      legacySource = FinancialSource.alAhlyBank;
    } else {
      // محفظة مخصصة — نستخدم manual كـ source
      legacySource = FinancialSource.manual;
    }
    await ingest(
      FinancialEvent(
        id: generateEventId(),
        source: legacySource,
        eventType: FinancialEventType.manualAdjustment,
        balanceAfter: value,
        confidence: 99,
        timestamp: DateTime.now(),
        rawMessage: 'تعديل يدوي للرصيد',
        rawSource: 'manual',
        walletId: walletId,
      ),
    );
  }

  List<MapEntry<String, int>> get recurringPersons {
    final counts = <String, int>{};
    for (final e in events) {
      final p = e.person?.trim();
      if (p == null || p.isEmpty) continue;
      counts[p] = (counts[p] ?? 0) + 1;
    }
    final entries = counts.entries.where((e) => e.value >= 2).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  double? lastAmountForPerson(String person) {
    for (final e in events) {
      if (e.person == person && e.amount != null) return e.amount;
    }
    return null;
  }

  /// I1: آخر حدث لمحفظة معينة بـ walletId
  FinancialEvent? lastEventForWallet(String walletId) {
    for (final e in events) {
      if (e.walletId == walletId) return e;
      // Backward compat للأحداث القديمة
      if (e.walletId == null) {
        final mapped = legacySourceToWalletId(e.source);
        if (mapped == walletId) return e;
      }
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // I1: إدارة المحافظ والمصادر
  // -----------------------------------------------------------------------

  Future<void> addWallet(Wallet wallet) async {
    wallets.insert(0, wallet);
    await _store.upsertWallet(wallet);
    notifyListeners();
  }

  Future<void> updateWallet(Wallet wallet) async {
    final idx = wallets.indexWhere((w) => w.id == wallet.id);
    if (idx == -1) return;
    wallets[idx] = wallet;
    await _store.upsertWallet(wallet);
    notifyListeners();
  }

  /// Archive بدل Delete — الأحداث تبقى، المحفظة تختفي من الـ UI الرئيسي
  Future<void> archiveWallet(String walletId) async {
    final idx = wallets.indexWhere((w) => w.id == walletId);
    if (idx == -1) return;
    final archived = wallets[idx].copyWith(archived: true);
    wallets[idx] = archived;
    await _store.upsertWallet(archived);
    notifyListeners();
  }

  Future<void> addWalletSource(WalletSource source) async {
    walletSources.add(source);
    await _store.upsertWalletSource(source);
    notifyListeners();
  }

  Future<void> updateWalletSource(WalletSource source) async {
    final idx = walletSources.indexWhere((s) => s.id == source.id);
    if (idx == -1) return;
    walletSources[idx] = source;
    await _store.upsertWalletSource(source);
    notifyListeners();
  }

  Future<void> removeWalletSource(String id) async {
    walletSources.removeWhere((s) => s.id == id);
    await _store.deleteWalletSource(id);
    notifyListeners();
  }

  /// الأحداث المرتبطة بمحفظة معينة
  List<FinancialEvent> eventsForWallet(String walletId) {
    return events.where((e) {
      if (e.walletId == walletId) return true;
      if (e.walletId == null) {
        return legacySourceToWalletId(e.source) == walletId;
      }
      return false;
    }).toList();
  }

  /// المصادر المرتبطة بمحفظة معينة
  List<WalletSource> sourcesForWallet(String walletId) =>
      walletSources.where((s) => s.walletId == walletId).toList();

  /// هل هذا الـ identifier مستخدم بالفعل بمحفظة أخرى؟ (لمنع التعارض)
  WalletSource? findConflictingSource(String identifier, String excludeWalletId) {
    for (final s in walletSources) {
      if (s.walletId == excludeWalletId) continue;
      if (s.identifier.toLowerCase() == identifier.toLowerCase()) return s;
    }
    return null;
  }
  // -----------------------------------------------------------------------
  // I4: إحصائيات الدخل/المصروف — walletTransfer لا يدخل في أي منهما
  // -----------------------------------------------------------------------

  bool _isIncomeType(FinancialEventType t) => isIncomingEventType(t);
  bool _isExpenseType(FinancialEventType t) => isOutgoingEventType(t);
  // walletTransferOut/In excluded from both ^ automatically

  double totalIncomeForMonth(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return events
        .where((e) =>
            e.confidence >= 85 &&
            _isIncomeType(e.eventType) &&
            e.timestamp.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
            e.timestamp.isBefore(end) &&
            e.amount != null)
        .fold(0.0, (s, e) => s + e.amount!);
  }

  double totalExpenseForMonth(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return events
        .where((e) =>
            e.confidence >= 85 &&
            _isExpenseType(e.eventType) &&
            e.timestamp.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
            e.timestamp.isBefore(end) &&
            e.amount != null)
        .fold(0.0, (s, e) => s + e.amount!);
  }
  // -----------------------------------------------------------------------
  // I4: التحويل الداخلي بين المحافظ
  // -----------------------------------------------------------------------

  /// ينشئ زوج أحداث مترابطين (atomic — SharedPreferences write واحد).
  ///
  /// القيود المفروضة:
  ///   - fromWalletId != toWalletId
  ///   - amount > 0
  Future<void> transferBetweenWallets({
    required String fromWalletId,
    required String toWalletId,
    required double amount,
    String? note,
  }) async {
    if (fromWalletId == toWalletId) {
      throw ArgumentError('from == to: لا يمكن التحويل لنفس المحفظة');
    }
    if (amount <= 0 || amount.isNaN || amount.isInfinite) {
      throw ArgumentError('المبلغ يجب أن يكون موجبًا وصالحًا: $amount');
    }

    final now = DateTime.now();
    final outId = generateEventId();
    final inId  = generateEventId();

    final outEvent = FinancialEvent(
      id: outId,
      source: FinancialSource.manual,
      eventType: FinancialEventType.walletTransferOut,
      amount: amount,
      timestamp: now,
      confidence: 99,
      rawMessage: note ?? 'تحويل داخلي',
      rawSource: 'manual_transfer',
      walletId: fromWalletId,
      linkedEventId: inId,
    );

    final inEvent = FinancialEvent(
      id: inId,
      source: FinancialSource.manual,
      eventType: FinancialEventType.walletTransferIn,
      amount: amount,
      timestamp: now,
      confidence: 99,
      rawMessage: note ?? 'تحويل داخلي',
      rawSource: 'manual_transfer',
      walletId: toWalletId,
      linkedEventId: outId,
    );

    // Atomic: load → add both → save في write واحد
    await _store.saveEventPair(outEvent, inEvent);

    // تحديث الـ in-memory list
    events.insertAll(0, [outEvent, inEvent]);
    _recomputeWallets();
    notifyListeners();
  }

  /// حذف زوج التحويل بالكامل (atomic).
  Future<void> deleteTransferPair(String eventId) async {
    final event = events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) return;
    final linkedId = event.linkedEventId;

    if (linkedId != null) {
      await _store.deleteEventPair(eventId, linkedId);
      events.removeWhere((e) => e.id == eventId || e.id == linkedId);
    } else {
      // حدث منفرد (عادةً لن يحدث) — احذفه بشكل عادي
      await _store.deleteEvent(eventId);
      events.removeWhere((e) => e.id == eventId);
    }
    _recomputeWallets();
    notifyListeners();
  }

  /// تعديل مبلغ التحويل الداخلي — يحدّث الزوج بأكمله (atomic).
  Future<void> editTransferAmount(String eventId, double newAmount) async {
    if (newAmount <= 0 || newAmount.isNaN || newAmount.isInfinite) {
      throw ArgumentError('المبلغ يجب أن يكون موجبًا: $newAmount');
    }

    final event = events.where((e) => e.id == eventId).firstOrNull;
    if (event == null) return;
    final linkedId = event.linkedEventId;
    if (linkedId == null) return;

    final linked = events.where((e) => e.id == linkedId).firstOrNull;
    if (linked == null) return;

    final updatedA = event.copyWith(amount: newAmount);
    final updatedB = linked.copyWith(amount: newAmount);

    await _store.saveEventPair(updatedA, updatedB);

    final iA = events.indexWhere((e) => e.id == eventId);
    final iB = events.indexWhere((e) => e.id == linkedId);
    if (iA >= 0) events[iA] = updatedA;
    if (iB >= 0) events[iB] = updatedB;

    _recomputeWallets();
    notifyListeners();
  }

  /// هل الحدث جزء من تحويل داخلي؟
  bool isWalletTransferEvent(FinancialEvent e) =>
      e.eventType == FinancialEventType.walletTransferOut ||
      e.eventType == FinancialEventType.walletTransferIn;
}
