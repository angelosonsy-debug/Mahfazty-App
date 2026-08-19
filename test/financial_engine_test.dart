import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trial/financial_engine/engine/financial_engine.dart';
import 'package:trial/financial_engine/engine/local_store.dart';
import 'package:trial/financial_engine/models/financial_event.dart';
import 'package:trial/financial_engine/models/client.dart';
import 'package:trial/financial_engine/engine/backup_service.dart';

FinancialEngine _newEngine() => FinancialEngine(LocalStore());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // مهم: SharedPreferences.getInstance() سنجليتون واحد لكل عملية الاختبار،
  // فلازم نصفّرها قبل كل اختبار عشان منسربش حالة بين الاختبارات.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('سياسة InstaPay: السمة الأهلي بس هي اللي بتحدّث الرصيد', () {
    test('رسالة بنك أهلي فيها رصيد صريح بتحدّث محفظة InstaPay مباشرة', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.ingest(FinancialEvent(
        id: 'ahly_1',
        source: FinancialSource.alAhlyBank,
        eventType: FinancialEventType.deposit,
        amount: 500,
        balanceAfter: 1500,
        person: 'أحمد محمد',
        reference: '123456',
        timestamp: DateTime.now(),
        confidence: 99,
        rawMessage: 'رسالة البنك الأهلي',
        rawSource: 'BanK-AlAhly',
      ));

      expect(engine.walletBalance[FinancialSource.instaPay], 1500);
    });

    test('رسالة بنك أهلي من غير رصيد صريح بتضيف/تخصم من آخر رصيد معروف', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.setWalletBalanceManually(FinancialSource.instaPay, 1000);
      expect(engine.walletBalance[FinancialSource.instaPay], 1000);

      await engine.ingest(FinancialEvent(
        id: 'ahly_2',
        source: FinancialSource.alAhlyBank,
        eventType: FinancialEventType.deposit,
        amount: 200,
        timestamp: DateTime.now().add(const Duration(minutes: 10)),
        confidence: 99,
        rawMessage: 'تحويل وارد للبطاقة',
        rawSource: 'BanK-AlAhly',
      ));

      expect(engine.walletBalance[FinancialSource.instaPay], 1200);

      await engine.ingest(FinancialEvent(
        id: 'ahly_3',
        source: FinancialSource.alAhlyBank,
        eventType: FinancialEventType.transfer,
        amount: 300,
        timestamp: DateTime.now().add(const Duration(minutes: 20)),
        confidence: 99,
        rawMessage: 'تحويل صادر من البطاقة',
        rawSource: 'BanK-AlAhly',
      ));

      expect(engine.walletBalance[FinancialSource.instaPay], 900);
    });

    test('حدث مصدره InstaPay مباشرة بثقة عالية (زي بعد تأكيد يدوي) بيأثر على الرصيد', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.setWalletBalanceManually(FinancialSource.instaPay, 500);

      // من v8: مفيش عزل كامل لـ InstaPay - لو حدث مصدره InstaPay وصل بثقة
      // عالية بالفعل (زي بعد تأكيد يدوي أو دمج ناجح مع رسالة بنك)، المفروض
      // يأثر على الرصيد زي أي حدث تاني موثوق.
      await engine.ingest(FinancialEvent(
        id: 'insta_confirmed',
        source: FinancialSource.instaPay,
        eventType: FinancialEventType.deposit,
        amount: 1000,
        timestamp: DateTime.now().add(const Duration(minutes: 5)),
        confidence: 99,
        rawMessage: 'إشعار InstaPay اتأكد يدويًا',
        rawSource: 'com.instapay.app',
      ));

      expect(engine.walletBalance[FinancialSource.instaPay], 1500);
    });
  });

  group('Manual editing', () {
    test('تعديل مبلغ معاملة يدويًا (بنك أهلي)', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.ingest(FinancialEvent(
        id: 'e1',
        source: FinancialSource.alAhlyBank,
        eventType: FinancialEventType.unknown,
        timestamp: DateTime.now(),
        confidence: 40,
        rawMessage: 'رسالة بنك من غير مبلغ واضح',
        rawSource: 'BanK-AlAhly',
      ));

      await engine.updateEventManually('e1', amount: 250, balanceAfter: 1000);

      final updated = engine.events.first;
      expect(updated.amount, 250);
      expect(updated.balanceAfter, 1000);
      expect(updated.confidence, 99);
      expect(updated.metadata['manuallyEdited'], true);
      expect(engine.walletBalance[FinancialSource.instaPay], 1000);
    });

    test('تعديل رصيد محفظة كامل يدويًا', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.setWalletBalanceManually(FinancialSource.vodafoneCash, 750);

      expect(engine.walletBalance[FinancialSource.vodafoneCash], 750);
    });
  });

  group('استمرارية تعديل رصيد المحفظة عبر إعادة التشغيل (Bug Fix)', () {
    test('رصيد أولي -> تعديل يدوي -> إعادة تحميل -> القيمة المعدّلة تفضل', () async {
      final store = LocalStore();
      final engine1 = FinancialEngine(store);
      await engine1.load();

      // رصيد أولي
      await engine1.setWalletBalanceManually(FinancialSource.vodafoneCash, 1000);
      expect(engine1.walletBalance[FinancialSource.vodafoneCash], 1000);

      // تعديل يدوي لاحق
      await engine1.setWalletBalanceManually(FinancialSource.vodafoneCash, 2500);
      expect(engine1.walletBalance[FinancialSource.vodafoneCash], 2500);

      // محاكاة إعادة تشغيل التطبيق - محرك جديد تمامًا، نفس التخزين
      final engine2 = FinancialEngine(LocalStore());
      await engine2.load();

      expect(engine2.walletBalance[FinancialSource.vodafoneCash], 2500,
          reason: 'لازم يفضل آخر قيمة اتحطت، مش أول قيمة (2500 مش 1000)');
    });

    test('تعديل مرتين -> إعادة تحميل -> القيمة التانية هي اللي بتفضل', () async {
      final engine1 = FinancialEngine(LocalStore());
      await engine1.load();

      await engine1.setWalletBalanceManually(FinancialSource.instaPay, 300);
      await engine1.setWalletBalanceManually(FinancialSource.instaPay, 800);
      await engine1.setWalletBalanceManually(FinancialSource.instaPay, 150);

      final engine2 = FinancialEngine(LocalStore());
      await engine2.load();

      expect(engine2.walletBalance[FinancialSource.instaPay], 150,
          reason: 'آخر تعديل (150) هو اللي المفروض يفضل بعد 3 تعديلات متتالية');
    });

    test('الحسابات (صافي الثروة) بتستخدم آخر قيمة محفوظة بعد إعادة التحميل', () async {
      final engine1 = FinancialEngine(LocalStore());
      await engine1.load();

      await engine1.setWalletBalanceManually(FinancialSource.vodafoneCash, 500);
      await engine1.setWalletBalanceManually(FinancialSource.vodafoneCash, 3000);
      await engine1.addPocketAdjustment(200);

      final engine2 = FinancialEngine(LocalStore());
      await engine2.load();

      expect(engine2.walletsTotal, 3000);
      expect(engine2.netWorth, 3200); // 3000 محفظة + 200 كاش
    });

    test('نفس السلوك لما يكون فيه أحداث تلقائية (SMS) قبل التعديل اليدوي', () async {
      final engine1 = FinancialEngine(LocalStore());
      await engine1.load();

      // حدث تلقائي أولًا
      await engine1.ingest(FinancialEvent(
        id: 'auto_1',
        source: FinancialSource.vodafoneCash,
        eventType: FinancialEventType.deposit,
        amount: 100,
        balanceAfter: 100,
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
        confidence: 99,
        rawMessage: 'رسالة',
        rawSource: 'VF-Cash',
      ));

      // بعدين تعديل يدوي لاحق
      await engine1.setWalletBalanceManually(FinancialSource.vodafoneCash, 5000);

      final engine2 = FinancialEngine(LocalStore());
      await engine2.load();

      expect(engine2.walletBalance[FinancialSource.vodafoneCash], 5000,
          reason: 'آخر حدث زمنيًا (التعديل اليدوي) هو اللي المفروض يحسم الرصيد');
    });
  });

  group('العملاء والمعاملات (Client + Transactions - النموذج الإلزامي)', () {
    test('إضافة عميل وحذفه', () async {
      final engine = _newEngine();
      await engine.load();

      final client = Client(id: 'c1', name: 'أحمد', createdAt: DateTime.now());
      await engine.addClient(client);
      expect(engine.clients.length, 1);

      await engine.deleteClient('c1');
      expect(engine.clients.length, 0);
    });

    test('حذف عميل بيمسح كل معاملاته كمان', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.addClient(Client(id: 'c2', name: 'محمد', createdAt: DateTime.now()));
      await engine.addDebtTransaction(DebtTransaction(
        id: 't1',
        clientId: 'c2',
        direction: DebtEntryDirection.theyOweUs,
        amount: 300,
        timestamp: DateTime.now(),
      ));
      expect(engine.debtTransactions.length, 1);

      await engine.deleteClient('c2');
      expect(engine.debtTransactions.where((t) => t.clientId == 'c2'), isEmpty);
    });

    test('تعديل اسم العميل - المعاملات تفضل مرتبطة بيه صح', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.addClient(Client(id: 'c_rename', name: 'محمد', createdAt: DateTime.now()));
      await engine.addDebtTransaction(DebtTransaction(
        id: 't_rename_1',
        clientId: 'c_rename',
        direction: DebtEntryDirection.theyOweUs,
        amount: 500,
        timestamp: DateTime.now(),
      ));

      await engine.updateClient('c_rename', name: 'محمد أحمد', notes: 'صاحب المحل');

      final renamed = engine.clients.firstWhere((c) => c.id == 'c_rename');
      expect(renamed.name, 'محمد أحمد');
      expect(renamed.notes, 'صاحب المحل');
      // المعاملة لسه مرتبطة بنفس العميل ومحتفظة ببياناتها بعد التعديل
      expect(engine.transactionsForClient('c_rename').length, 1);
      expect(engine.theyOweUsTotal('c_rename'), 500);
    });

    test('تعديل اسم عميل مش موجود مالوش أي تأثير (بدل ما يكسر حاجة)', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.updateClient('غير_موجود', name: 'اسم جديد');
      expect(engine.clients, isEmpty);
    });

    test('حذف عميل من غير معاملات خالص - سلوك سليم من غير أخطاء', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.addClient(Client(id: 'c_empty', name: 'سارة', createdAt: DateTime.now()));
      await engine.deleteClient('c_empty');

      expect(engine.clients, isEmpty);
      expect(engine.debtTransactions, isEmpty);
    });

    test('إضافة معاملات دائنة ومدينة داخل عميل وحساب الصافي', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.addClient(Client(id: 'c3', name: 'سارة', createdAt: DateTime.now()));

      await engine.addDebtTransaction(DebtTransaction(
        id: 't2',
        clientId: 'c3',
        direction: DebtEntryDirection.theyOweUs, // هي مديونة لينا
        amount: 500,
        timestamp: DateTime.now(),
      ));
      await engine.addDebtTransaction(DebtTransaction(
        id: 't3',
        clientId: 'c3',
        direction: DebtEntryDirection.weOweThem, // واحنا مديونين لها جزء
        amount: 200,
        timestamp: DateTime.now(),
      ));

      expect(engine.theyOweUsTotal('c3'), 500);
      expect(engine.weOweThemTotal('c3'), 200);
      expect(engine.clientNet('c3'), 300); // صافي: هي مديونة لينا 300
    });

    test('تعديل معاملة وحذفها', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.addClient(Client(id: 'c4', name: 'خالد', createdAt: DateTime.now()));
      await engine.addDebtTransaction(DebtTransaction(
        id: 't4',
        clientId: 'c4',
        direction: DebtEntryDirection.theyOweUs,
        amount: 1000,
        timestamp: DateTime.now(),
      ));

      await engine.updateDebtTransaction('t4', amount: 1200, note: 'اتزود');
      final updated = engine.transactionsForClient('c4').first;
      expect(updated.amount, 1200);
      expect(updated.note, 'اتزود');

      await engine.deleteDebtTransaction('t4');
      expect(engine.transactionsForClient('c4'), isEmpty);
    });

    test('إجمالي الديون على مستوى التطبيق كله عبر أكتر من عميل', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.addClient(Client(id: 'c5', name: 'محمد', createdAt: DateTime.now()));
      await engine.addClient(Client(id: 'c6', name: 'أحمد', createdAt: DateTime.now()));

      await engine.addDebtTransaction(DebtTransaction(
        id: 't5', clientId: 'c5', direction: DebtEntryDirection.theyOweUs, amount: 300, timestamp: DateTime.now(),
      ));
      await engine.addDebtTransaction(DebtTransaction(
        id: 't6', clientId: 'c6', direction: DebtEntryDirection.theyOweUs, amount: 200, timestamp: DateTime.now(),
      ));
      await engine.addDebtTransaction(DebtTransaction(
        id: 't7', clientId: 'c5', direction: DebtEntryDirection.weOweThem, amount: 100, timestamp: DateTime.now(),
      ));

      expect(engine.moneyOwedToMe, 500); // 300 + 200
      expect(engine.moneyIOwe, 100);
    });

    test('كشف الأشخاص المتكررين في المعاملات المالية (مختلف عن العملاء)', () async {
      final engine = _newEngine();
      await engine.load();

      for (var i = 0; i < 3; i++) {
        await engine.ingest(FinancialEvent(
          id: 'p$i',
          source: FinancialSource.vodafoneCash,
          eventType: FinancialEventType.transfer,
          person: 'أحمد محمد',
          amount: 100.0 + i,
          timestamp: DateTime.now().add(Duration(days: i)),
          confidence: 99,
          rawMessage: 'تحويل',
          rawSource: 'VF-Cash',
        ));
      }

      final recurring = engine.recurringPersons;
      expect(recurring.isNotEmpty, true);
      expect(recurring.first.key, 'أحمد محمد');
      expect(recurring.first.value, 3);
    });
  });

  group('Pocket', () {
    test('إضافة وخصم من الكاش وتتبع السجل', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.addPocketAdjustment(500, note: 'رصيد أولي');
      await engine.addPocketAdjustment(-100, note: 'مصروف');

      expect(engine.pocketBalance, 400);
      expect(engine.pocketHistory.length, 2);
    });
  });

  group('Review actions: confirm/edit/delete', () {
    test('تأكيد معاملة يرفع الثقة من غير تغيير البيانات', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.ingest(FinancialEvent(
        id: 'ev1',
        source: FinancialSource.vodafoneCash,
        eventType: FinancialEventType.deposit,
        amount: 50,
        timestamp: DateTime.now(),
        confidence: 60,
        rawMessage: 'رسالة',
        rawSource: 'VF-Cash',
      ));

      await engine.confirmEvent('ev1');

      final confirmed = engine.events.first;
      expect(confirmed.confidence, 99);
      expect(confirmed.metadata['userConfirmed'], true);
    });

    test('تعديل معاملة "غير معروف" (بنك أهلي) بتحديد نوعها بيخليها تؤثر على الرصيد', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.setWalletBalanceManually(FinancialSource.instaPay, 500);

      await engine.ingest(FinancialEvent(
        id: 'ev2',
        source: FinancialSource.alAhlyBank,
        eventType: FinancialEventType.unknown,
        timestamp: DateTime.now().add(const Duration(minutes: 1)),
        confidence: 40,
        rawMessage: 'رسالة بنك من غير مبلغ واضح',
        rawSource: 'BanK-AlAhly',
      ));

      expect(engine.walletBalance[FinancialSource.instaPay], 500);

      await engine.updateEventManually(
        'ev2',
        amount: 150,
        eventType: FinancialEventType.deposit,
      );

      expect(engine.walletBalance[FinancialSource.instaPay], 650);
    });

    test('حذف معاملة يشيلها تمامًا وبلا أثر', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.ingest(FinancialEvent(
        id: 'ev3',
        source: FinancialSource.vodafoneCash,
        eventType: FinancialEventType.unknown,
        timestamp: DateTime.now(),
        confidence: 70,
        rawMessage: 'إشعار مش حقيقي',
        rawSource: 'VF-Cash',
      ));

      expect(engine.events.length, 1);
      await engine.deleteEvent('ev3');
      expect(engine.events.length, 0);
    });
  });

  group('دمج InstaPay مع البنك الأهلي (رجّع تاني - نافذة دقيقتين)', () {
    test('إشعار InstaPay + رسالة بنك أهلي بنفس المبلغ خلال دقيقتين بيتدمجوا', () async {
      final engine = _newEngine();
      await engine.load();

      final now = DateTime.now();

      await engine.ingest(FinancialEvent(
        id: 'insta_1',
        source: FinancialSource.instaPay,
        eventType: FinancialEventType.unknown,
        amount: 500,
        timestamp: now,
        confidence: 70,
        rawMessage: 'إشعار InstaPay',
        rawSource: 'com.instapay.app',
      ));
      expect(engine.events.length, 1);

      await engine.ingest(FinancialEvent(
        id: 'ahly_1',
        source: FinancialSource.alAhlyBank,
        eventType: FinancialEventType.deposit,
        amount: 500,
        person: 'أحمد محمد',
        reference: '123456',
        timestamp: now.add(const Duration(seconds: 90)),
        confidence: 99,
        rawMessage: 'رسالة البنك الأهلي',
        rawSource: 'BanK-AlAhly',
      ));

      expect(engine.events.length, 1); // اتدمجوا في حدث واحد
      final merged = engine.events.first;
      expect(merged.source, FinancialSource.instaPay);
      expect(merged.confidence, 99);
      expect(merged.person, 'أحمد محمد');
      expect(engine.walletBalance[FinancialSource.instaPay], isNotNull);
    });

    test('نفس المبلغ بس بعد أكتر من دقيقتين - مبيتدمجوش', () async {
      final engine = _newEngine();
      await engine.load();

      final now = DateTime.now();

      await engine.ingest(FinancialEvent(
        id: 'insta_2',
        source: FinancialSource.instaPay,
        eventType: FinancialEventType.unknown,
        amount: 300,
        timestamp: now,
        confidence: 70,
        rawMessage: 'إشعار InstaPay',
        rawSource: 'com.instapay.app',
      ));

      await engine.ingest(FinancialEvent(
        id: 'ahly_2',
        source: FinancialSource.alAhlyBank,
        eventType: FinancialEventType.deposit,
        amount: 300,
        timestamp: now.add(const Duration(minutes: 5)),
        confidence: 99,
        rawMessage: 'رسالة البنك الأهلي',
        rawSource: 'BanK-AlAhly',
      ));

      expect(engine.events.length, 2); // برّه نطاق الدمج
    });

    test('إشعار InstaPay لوحده من غير تطابق مبيأثرش على الرصيد لحد المراجعة', () async {
      final engine = _newEngine();
      await engine.load();

      await engine.ingest(FinancialEvent(
        id: 'insta_3',
        source: FinancialSource.instaPay,
        eventType: FinancialEventType.deposit,
        amount: 1000,
        timestamp: DateTime.now(),
        confidence: 70, // ثقة قايمة لوحدها، من غير تطابق بنك ولا تأكيد يدوي
        rawMessage: 'إشعار InstaPay من غير تطابق',
        rawSource: 'com.instapay.app',
      ));

      expect(engine.walletBalance[FinancialSource.instaPay], isNull);
    });
  });

  group('Backup / Restore', () {
    test('تصدير واستعادة النسخة الاحتياطية بيرجّع نفس البيانات', () async {
      final engine1 = _newEngine();
      await engine1.load();

      await engine1.ingest(FinancialEvent(
        id: 'backup_ev1',
        source: FinancialSource.vodafoneCash,
        eventType: FinancialEventType.deposit,
        amount: 250,
        balanceAfter: 1000,
        timestamp: DateTime.now(),
        confidence: 99,
        rawMessage: 'رسالة',
        rawSource: 'VF-Cash',
      ));
      await engine1.addClient(Client(id: 'backup_c1', name: 'محمد', createdAt: DateTime.now()));
      await engine1.addDebtTransaction(DebtTransaction(
        id: 'backup_t1',
        clientId: 'backup_c1',
        direction: DebtEntryDirection.theyOweUs,
        amount: 400,
        timestamp: DateTime.now(),
      ));

      final backupService = BackupService(LocalStore());
      final json = await backupService.exportBackup();

      // نمسح كل حاجة ونستعيد من النسخة الاحتياطية على محرك جديد
      SharedPreferences.setMockInitialValues({});
      final freshStore = LocalStore();
      final freshBackupService = BackupService(freshStore);
      final result = await freshBackupService.importBackup(json);

      expect(result.eventsCount, 1);
      expect(result.clientsCount, 1);
      expect(result.transactionsCount, 1);

      final engine2 = FinancialEngine(freshStore);
      await engine2.load();

      expect(engine2.events.length, 1);
      expect(engine2.events.first.amount, 250);
      expect(engine2.clients.length, 1);
      expect(engine2.clients.first.name, 'محمد');
      expect(engine2.theyOweUsTotal('backup_c1'), 400);
    });

    test('نص مش نسخة احتياطية صالحة بيرمي استثناء واضح', () async {
      final backupService = BackupService(LocalStore());
      expect(() => backupService.importBackup('مش JSON خالص'), throwsA(anything));
    });
  });
}
