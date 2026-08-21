import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/financial_event.dart';
import '../models/client.dart';

/// حفظ محلي عبر SharedPreferences - بديل Drift اللي رفض يتبني بسبب
/// تعارض إصدارات Gradle/Kotlin في مكتبة jni الفرعية (مشكلة برّه الكود
/// نفسه، ومعنديش وسيلة أتأكد من حلها من غير بيئة Flutter حقيقية).
/// الواجهة هنا مطابقة لنفس الميثودز اللي كان DriftStore بيوفرها، فـ
/// FinancialEngine ماحتاجش يتغير خالص غير في مكان الإنشاء.
class PocketAdjustmentRow {
  final String id;
  final double delta;
  final String? note;
  final int timestamp;

  const PocketAdjustmentRow({
    required this.id,
    required this.delta,
    this.note,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {'id': id, 'delta': delta, 'note': note, 'timestamp': timestamp};

  factory PocketAdjustmentRow.fromJson(Map<String, dynamic> json) => PocketAdjustmentRow(
        id: json['id'] as String,
        delta: (json['delta'] as num).toDouble(),
        note: json['note'] as String?,
        timestamp: json['timestamp'] as int,
      );
}

class LocalStore {
  static const _eventsKey = 'mahfazty_events_v2';
  static const _clientsKey = 'mahfazty_clients_v1';
  static const _debtTransactionsKey = 'mahfazty_debt_transactions_v1';
  static const _pocketKey = 'mahfazty_pocket_adjustments_v2';
  static const _learningKey = 'mahfazty_learning_v2';

  // --------------------------- Financial Events ---------------------------

  Future<List<FinancialEvent>> loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_eventsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    final events = list.map((e) => FinancialEvent.fromJson(e as Map<String, dynamic>)).toList();
    // مهم: لازم نرجّع الأحدث أولًا - ده اللي FinancialEngine بيتوقعه (بيحط
    // كل حدث جديد في index 0). التخزين نفسه بيحتفظ بترتيب الإدخال (الأقدم
    // أولًا، لأننا بنعمل .add() في upsertEvent)، فمن غير الترتيب الصريح
    // ده هنا، أي إعادة تحميل (Reload/إعادة فتح التطبيق) كانت بتدي
    // FinancialEngine._recomputeWallets() القايمة بترتيب معكوس، فيحسب
    // آخر رصيد يدوي غلط (بيرجع لأول قيمة اتحطت بدل آخر واحدة).
    //
    // Bug Fix: الاعتماد على timestamp لوحده مش كافي. لو حصلت أكتر من
    // setWalletBalanceManually (أو أي ingest) ورا بعض بسرعة كبيرة (زي في
    // التيستات، أو حتى في الاستخدام الحقيقي على جهاز سريع)، ممكن يجيلهم
    // نفس الـ millisecond بالظبط. List.sort في Dart مش مضمون إنه stable،
    // فوقت التعادل ده الترتيب بينهم بيبقى غير محدد - ده اللي كان بيخلي
    // آخر تعديل يدوي أحيانًا يضيع ويرجع رصيد أقدم بدل الأحدث. الحل: نضيف
    // ترتيب الإضافة الأصلي (index في التخزين، اللي فعلاً زمني صح لأننا
    // بنعمل .add() بس) كـ tiebreaker، فمفيش تعادل حقيقي يوصل لـ sort خالص.
    final indices = List<int>.generate(events.length, (i) => i);
    indices.sort((ia, ib) {
      final cmp = events[ib].timestamp.compareTo(events[ia].timestamp);
      if (cmp != 0) return cmp;
      return ib.compareTo(ia); // وقت التعادل: اللي اتضاف بعدين (index أكبر) يطلع فوق
    });
    return indices.map((i) => events[i]).toList();
  }

  Future<void> _saveAllEvents(List<FinancialEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_eventsKey, jsonEncode(events.map((e) => e.toJson()).toList()));
  }

  Future<void> upsertEvent(FinancialEvent e) async {
    final events = await loadEvents();
    final index = events.indexWhere((x) => x.id == e.id);
    if (index == -1) {
      events.add(e);
    } else {
      events[index] = e;
    }
    await _saveAllEvents(events);
  }

  Future<void> deleteEvent(String id) async {
    final events = await loadEvents();
    events.removeWhere((x) => x.id == id);
    await _saveAllEvents(events);
  }

  // ------------------------------ Clients + Debt Transactions ------------------------------

  Future<List<Client>> loadClients() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clientsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    final clients = list.map((e) => Client.fromJson(e as Map<String, dynamic>)).toList();
    // نفس سبب loadEvents بالظبط: تعادل في createdAt ممكن يحصل، وsort مش stable.
    final indices = List<int>.generate(clients.length, (i) => i);
    indices.sort((ia, ib) {
      final cmp = clients[ib].createdAt.compareTo(clients[ia].createdAt);
      if (cmp != 0) return cmp;
      return ib.compareTo(ia);
    });
    return indices.map((i) => clients[i]).toList();
  }

  Future<void> _saveAllClients(List<Client> clients) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clientsKey, jsonEncode(clients.map((e) => e.toJson()).toList()));
  }

  Future<void> upsertClient(Client c) async {
    final clients = await loadClients();
    final index = clients.indexWhere((x) => x.id == c.id);
    if (index == -1) {
      clients.add(c);
    } else {
      clients[index] = c;
    }
    await _saveAllClients(clients);
  }

  Future<void> deleteClient(String id) async {
    final clients = await loadClients();
    clients.removeWhere((x) => x.id == id);
    await _saveAllClients(clients);
    // حذف العميل بيمسح كل معاملاته كمان - مفيش معاملات يتيمة من غير عميل
    final transactions = await loadDebtTransactions();
    transactions.removeWhere((t) => t.clientId == id);
    await _saveAllDebtTransactions(transactions);
  }

  Future<List<DebtTransaction>> loadDebtTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_debtTransactionsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    final transactions = list.map((e) => DebtTransaction.fromJson(e as Map<String, dynamic>)).toList();
    // نفس سبب loadEvents بالظبط: تعادل في timestamp ممكن يحصل، وsort مش stable.
    final indices = List<int>.generate(transactions.length, (i) => i);
    indices.sort((ia, ib) {
      final cmp = transactions[ib].timestamp.compareTo(transactions[ia].timestamp);
      if (cmp != 0) return cmp;
      return ib.compareTo(ia);
    });
    return indices.map((i) => transactions[i]).toList();
  }

  Future<void> _saveAllDebtTransactions(List<DebtTransaction> transactions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_debtTransactionsKey, jsonEncode(transactions.map((e) => e.toJson()).toList()));
  }

  Future<void> upsertDebtTransaction(DebtTransaction t) async {
    final transactions = await loadDebtTransactions();
    final index = transactions.indexWhere((x) => x.id == t.id);
    if (index == -1) {
      transactions.add(t);
    } else {
      transactions[index] = t;
    }
    await _saveAllDebtTransactions(transactions);
  }

  Future<void> deleteDebtTransaction(String id) async {
    final transactions = await loadDebtTransactions();
    transactions.removeWhere((x) => x.id == id);
    await _saveAllDebtTransactions(transactions);
  }

  // ---------------------------- Pocket History ------------------------------

  Future<List<PocketAdjustmentRow>> loadPocketAdjustments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pocketKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    final rows = list.map((e) => PocketAdjustmentRow.fromJson(e as Map<String, dynamic>)).toList();
    // نفس سبب الأحداث المالية بالظبط: تعادل في timestamp ممكن يحصل، وsort مش stable.
    final indices = List<int>.generate(rows.length, (i) => i);
    indices.sort((ia, ib) {
      final cmp = rows[ib].timestamp.compareTo(rows[ia].timestamp);
      if (cmp != 0) return cmp;
      return ib.compareTo(ia);
    });
    return indices.map((i) => rows[i]).toList();
  }

  Future<void> addPocketAdjustment(String id, double delta, String? note) async {
    final rows = await loadPocketAdjustments();
    rows.add(PocketAdjustmentRow(
      id: id,
      delta: delta,
      note: note,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pocketKey, jsonEncode(rows.map((r) => r.toJson()).toList()));
  }

  // --------------------------- Learning Memory ------------------------------

  Future<Map<String, FinancialEventType>> loadLearningMemory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_learningKey);
    if (raw == null) return {};
    final map = jsonDecode(raw) as Map;
    final result = <String, FinancialEventType>{};
    map.forEach((k, v) {
      try {
        result[k as String] = FinancialEventType.values.firstWhere((t) => t.name == v);
      } catch (_) {
        // نوع غير معروف اتخزن قديم - نتجاهله
      }
    });
    return result;
  }

  Future<void> saveLearningCorrection(String fingerprint, FinancialEventType type) async {
    final memory = await loadLearningMemory();
    memory[fingerprint] = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_learningKey, jsonEncode(memory.map((k, v) => MapEntry(k, v.name))));
  }
}
