import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/services/ads_service.dart';
import 'core/services/billing_service.dart';
import 'core/services/debt_reminder_scheduler.dart';
import 'core/services/notification_service.dart';
import 'core/services/onboarding_store.dart';
import 'core/services/premium_service.dart';
import 'core/services/transaction_notifier.dart';
import 'core/theme/app_theme.dart';

import 'financial_engine/engine/financial_engine.dart';
import 'financial_engine/engine/schema_migrator.dart';
import 'financial_engine/engine/backup_service.dart';
import 'financial_engine/engine/local_store.dart';
import 'financial_engine/ai/ai_assisted_ingestion.dart';
import 'financial_engine/ai/ai_settings_store.dart';
import 'financial_engine/policy/bank_wallet_overrides.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/wallets/wallets_screen.dart';
import 'features/debts/clients_screen.dart';
import 'features/pocket/pocket_screen.dart';
import 'features/inbox/inbox_screen.dart';
import 'features/timeline/timeline_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/installments/installment_calculator_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PremiumService.instance.load();
  // لازم تخلص (await) قبل runApp: sourceCatalog.matches() بتقرأ القيم دي
  // synchronously أثناء معالجة أي SMS واردة، فلازم تبقى جاهزة قبل ما
  // AppShell.initState() تسجّل أي MethodChannel handler.
  await BankWalletOverrides.load();
  final onboardingDone = await OnboardingStore.isCompleted();
  runApp(MahfaztyApp(onboardingDone: onboardingDone));
  // AdMob بعد runApp عشان تهيئته (ممكن تاخد ثواني على نت ضعيف) ما تأخرش
  // فتح التطبيق. لو فشلت، التطبيق شغال عادي من غير إعلانات.
  unawaited(AdsService.instance.init());
  // نفس فكرة AdsService: بعد runApp عشان ما تأخرش فتح التطبيق. لو
  // المتجر مش متاح أو المنتج لسه مش متسجّل في Play Console، BillingService
  // بيتعامل مع ده بهدوء (حالة unavailable واضحة في premium_modal) من غير
  // ما يأثر على باقي التطبيق.
  unawaited(BillingService.instance.init());
}

class MahfaztyApp extends StatelessWidget {
  final bool onboardingDone;
  const MahfaztyApp({super.key, required this.onboardingDone});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'محفظتي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(),
      home: onboardingDone ? const AppShell() : const OnboardingScreen(),
    );
  }
}

/// ملحوظة معمارية: قناتين شغالتين - SMS (فودافون كاش/البنك الأهلي)
/// وNotifications (InstaPay). الاتنين بيعدّوا على AiAssistedIngestion،
/// اللي بيفصل بوضوح بين القواعد (Rule Engine) والـ AI المساعد والـ
/// FinancialEngine. FinancialEngine هو اللي بعد كده بيحاول يطابق
/// أحداث InstaPay مع رسائل البنك الأهلي (دقيقتين) قبل ما يعتمدها.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const MethodChannel _smsChannel = MethodChannel('mahfazty/sms');
  static const MethodChannel _notificationsChannel = MethodChannel('mahfazty/notifications');
  static const MethodChannel _powerChannel = MethodChannel('mahfazty/power');

  late final FinancialEngine _engine;
  late final AiAssistedIngestion _ingestion;
  int _tabIndex = 0;
  bool _smsPermissionGranted = false;
  bool _notificationAccessGranted = false;
  bool _batteryOptimizationIgnored = false;
  Object? _startupError;

  /// التابات اللي اتزارت فعليًا على الأقل مرة — بنستخدمها عشان نبني
  /// شاشة التاب بس أول ما المستخدم يفتحه فعليًا (lazy)، مش كل الخمسة
  /// مع بعض من أول تشغيل. تاب ٠ (الرئيسية) مزور من البداية بطبيعته.
  final Set<int> _visitedTabs = {0};

  /// نقطة واحدة لتغيير التاب — بتسجّله في _visitedTabs كمان، عشان
  /// IndexedStack يعرف يبني الشاشة دي أول مرة تتفتح.
  void _selectTab(int i) {
    setState(() {
      _tabIndex = i;
      _visitedTabs.add(i);
    });
  }

  @override
  void initState() {
    super.initState();
    // R-fix6: الصلاحيات (خصوصًا استثناء البطارية وNotification Access)
    // ممكن تتسحب من النظام نفسه وقت ما التطبيق مقفول (خصوصًا على
    // Xiaomi/Oppo/Huawei/Samsung) من غير ما يحصل أي تنبيه واضح. قبل كده
    // كان الفحص بيحصل مرة واحدة بس عند فتح التطبيق لأول مرة (initState)،
    // فلو اتسحبت صلاحية والمستخدم فاتح التطبيق فترة طويلة، مش هيكتشف
    // غير لو قفل وفتح التطبيق تاني. بنضيف observer يعيد الفحص كل مرة
    // التطبيق يرجع من الخلفية، والبانر الموجود بالفعل (_PermissionBanner)
    // هيظهر تلقائي لو أي حاجة اتسحبت.
    WidgetsBinding.instance.addObserver(this);
    final store = LocalStore();
    _engine = FinancialEngine(
      store,
      notifier: TransactionNotifier.instance,
      reminderScheduler: DebtReminderScheduler.instance,
    );
    _ingestion = AiAssistedIngestion(_engine, AiSettingsStore());
    // ملحوظة أداء: ما بنعملش _engine.addListener(() => setState(() {}))
    // هنا عمدًا — ده كان بيسبب إعادة بناء الـ Scaffold/NavigationBar/كل
    // الشاشات الخمسة مع بعض عند أي حدث مالي واحد في أي حتة، حتى لو
    // المستخدم قاعد في تاب تاني خالص. الاستماع الفعلي بقى محدود حوالين
    // محتوى التاب النشط بس، جوه build() (راجع ListenableBuilder هناك).
    _smsChannel.setMethodCallHandler(_handleSms);
    _notificationsChannel.setMethodCallHandler(_handleNotification);
    _checkPermissions();
    unawaited(_initNotifications());
    unawaited(_initializeFinancialData(store));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkPermissions());
    }
  }

  Future<void> _initializeFinancialData(LocalStore store) async {
    try {
      // يجب أن ينتهي الترحيل بالكامل قبل تحميل المحرك؛ تشغيلهما بالتوازي
      // قد يجعل المحرك يقرأ حالة نصف مُرحّلة ويحتفظ بها طوال الجلسة.
      final migration = await SchemaMigrator(store, BackupService(store)).runIfNeeded();
      if (migration.status == MigrationStatus.failed) {
        throw StateError(migration.failureReason ?? 'فشل ترحيل البيانات');
      }
      await _engine.load();
      // لازم بعد load() مباشرة — محتاجة engine.wallets/walletSources
      // محمّلين عشان تلاقي الصفوف الافتراضية وتسمّيها باختيارات
      // المستخدم من شاشات التعريف. Idempotent (OnboardingStore بتتأكد
      // من علم "applied" بنفسها)، فمفيش خطورة من تكرار الاستدعاء.
      await OnboardingStore.applyPendingCustomization(_engine);
      // طابور دائم: أي SMS/إشعار وصل والتطبيق كان مقفول تمامًا (راجع
      // PendingQueue.kt) اتخزّن على القرص بدل ما يتفقد - نسحبه ونعالجه
      // دلوقتي بنفس مسار المعالجة العادي بالظبط.
      await _drainPendingQueue();
      if (!mounted) return;
      setState(() => _startupError = null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _startupError = error);
    }
  }

  /// فحص صامت (fire-and-forget، مش بيحجب الواجهة) عند فتح التطبيق —
  /// إشعارات تأكيد العمليات: تهيئة + (أول فتح بس) طلب صلاحية POST_NOTIFICATIONS
  /// على أندرويد 13+. كله بيبلع الأخطاء — مفيش حاجة هنا تمنع التطبيق يفتح.
  Future<void> _initNotifications() async {
    final notifier = TransactionNotifier.instance;
    await notifier.init();
    if (notifier.enabled) {
      await NotificationService.instance.requestPermissionOnce();
    }
  }

  Future<void> _handleSms(MethodCall call) async {
    if (call.method != 'onSms') return;
    final map = call.arguments as Map<dynamic, dynamic>;
    final sender = map['sender']?.toString() ?? '';
    final body = map['body']?.toString() ?? '';
    final receivedAt = DateTime.fromMillisecondsSinceEpoch(
      (map['time'] is int) ? map['time'] as int : DateTime.now().millisecondsSinceEpoch,
    );

    await _ingestion.ingestSms(sender, body, receivedAt: receivedAt);
  }

  Future<void> _handleNotification(MethodCall call) async {
    if (call.method != 'onNotification') return;
    final map = call.arguments as Map<dynamic, dynamic>;
    final packageName = map['packageName']?.toString() ?? 'unknown';
    final title = map['title']?.toString() ?? '';
    final text = map['text']?.toString() ?? '';
    final receivedAt = DateTime.fromMillisecondsSinceEpoch(
      (map['time'] is int) ? map['time'] as int : DateTime.now().millisecondsSinceEpoch,
    );

    await _ingestion.ingestNotification(packageName, title, text, receivedAt: receivedAt);
  }

  /// بتتنادى مرة واحدة عند كل فتح للتطبيق (بعد migration + load) - بتسحب
  /// أي SMS/إشعار اتخزّن في الطابور الدائم وقت ما التطبيق كان مقفول
  /// تمامًا، وتعالجه بنفس مسار المعالجة اللي _handleSms/_handleNotification
  /// بتستخدمه. لو القناة مش متاحة (بيئة اختبار widget من غير mock، أو
  /// منصة غير أندرويد) بتفشل بهدوء من غير ما توقف باقي التهيئة.
  Future<void> _drainPendingQueue() async {
    try {
      final pendingSms = await _smsChannel.invokeMethod<List<dynamic>>('drainPendingSms');
      for (final item in pendingSms ?? const []) {
        final map = item as Map<dynamic, dynamic>;
        final sender = map['sender']?.toString() ?? '';
        final body = map['body']?.toString() ?? '';
        if (sender.isEmpty || body.isEmpty) continue;
        final receivedAt = DateTime.fromMillisecondsSinceEpoch(
          (map['time'] is int) ? map['time'] as int : DateTime.now().millisecondsSinceEpoch,
        );
        await _ingestion.ingestSms(sender, body, receivedAt: receivedAt);
      }
    } catch (_) {
      // تجاهل - القناة مش متاحة أو فشلت، مش حرج لدرجة إيقاف فتح التطبيق
    }

    try {
      final pendingNotifications =
          await _notificationsChannel.invokeMethod<List<dynamic>>('drainPendingNotifications');
      for (final item in pendingNotifications ?? const []) {
        final map = item as Map<dynamic, dynamic>;
        final packageName = map['packageName']?.toString() ?? 'unknown';
        final title = map['title']?.toString() ?? '';
        final text = map['text']?.toString() ?? '';
        if (title.isEmpty && text.isEmpty) continue;
        final receivedAt = DateTime.fromMillisecondsSinceEpoch(
          (map['time'] is int) ? map['time'] as int : DateTime.now().millisecondsSinceEpoch,
        );
        await _ingestion.ingestNotification(packageName, title, text, receivedAt: receivedAt);
      }
    } catch (_) {
      // تجاهل - نفس السبب فوق
    }
  }

  // ملحوظة مهمة: كل catch هنا بقى catch (_) عامة بدل on PlatformException
  // تحديدًا. لو القناة مالهاش handler مسجّل خالص (مش متاحة على المنصة،
  // أو في بيئة اختبار widget مش عاملة mock ليها)، Flutter بيرمي
  // MissingPluginException — وده كلاس منفصل تمامًا، مش فرع من
  // PlatformException، فكان بيهرب من الـ catch القديم ويوقّع اختبارات
  // زي app_startup_test.dart حتى لو التطبيق شغال فعليًا كويس (كان ده
  // بالظبط سبب فشل الاختبار: الاختبار بيعمل mock لقنوات SMS/الإشعارات
  // بس، مش قناة mahfazty/power الجديدة).
  Future<void> _checkPermissions() async {
    try {
      final granted = await _smsChannel.invokeMethod<bool>('isSmsPermissionGranted');
      setState(() => _smsPermissionGranted = granted ?? false);
    } catch (_) {
      setState(() => _smsPermissionGranted = false);
    }
    try {
      final granted = await _notificationsChannel.invokeMethod<bool>('isNotificationAccessGranted');
      setState(() => _notificationAccessGranted = granted ?? false);
    } catch (_) {
      setState(() => _notificationAccessGranted = false);
    }
    try {
      final ignored = await _powerChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      setState(() => _batteryOptimizationIgnored = ignored ?? false);
    } catch (_) {
      setState(() => _batteryOptimizationIgnored = false);
    }
  }

  /// إفصاح صريح (Prominent Disclosure) قبل أي طلب صلاحية حساسة - شرط من
  /// Google Play لتطبيقات بتاخد صلاحية SMS عشان توافَق تحت "Core App
  /// Functionality". قبل الإضافة دي، الزرار كان بيطلب الصلاحية من النظام
  /// على طول من غير أي شرح قبلها في التطبيق نفسه.
  Future<bool> _showDisclosureDialog({
    required String title,
    required String body,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('فهمت، كمّل'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _requestSmsPermission() async {
    final confirmed = await _showDisclosureDialog(
      title: 'قراءة رسائل SMS',
      body: 'محفظتي بتقرأ نص رسائل SMS على جهازك عشان تكتشف تلقائيًا '
          'معاملات بنكك/محفظتك (مبلغ، رصيد، نوع العملية) وتسجّلها بنفسها '
          'من غير ما تدخلها يدويًا. الرسائل بتتحلل على جهازك فقط ومتسيبش '
          'التطبيق، ماعدا لو فعّلت "الفهم الذكي" من الإعدادات بنفسك - '
          'وقتها نص الرسالة بس (من غير بيانات تانية) بيتبعت لخدمة تحليل '
          'خارجية. تقدر توقف الصلاحية دي في أي وقت من إعدادات الجهاز.',
    );
    if (!confirmed) return;
    try {
      await _smsChannel.invokeMethod('requestSmsPermission');
    } catch (_) {
      // ignore
    }
    Future.delayed(const Duration(seconds: 1), _checkPermissions);
  }

  Future<void> _openNotificationAccessSettings() async {
    final confirmed = await _showDisclosureDialog(
      title: 'الوصول إلى الإشعارات',
      body: 'محفظتي بتقرا محتوى إشعارات تطبيق InstaPay بس عشان تسجّل '
          'معاملاتك تلقائيًا، وبتتجاهل أي إشعار من أي تطبيق تاني فورًا من '
          'غير ما تخزّنه أو تحلله. هتوصّلك لشاشة إعدادات أندرويد عشان تدّي '
          'محفظتي الصلاحية دي بنفسك، وتقدر تلغيها في أي وقت من نفس '
          'الشاشة.',
    );
    if (!confirmed) return;
    try {
      await _notificationsChannel.invokeMethod('openNotificationAccessSettings');
    } catch (_) {
      // ignore
    }
    Future.delayed(const Duration(seconds: 1), _checkPermissions);
  }

  Future<void> _requestIgnoreBatteryOptimizations() async {
    try {
      await _powerChannel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {
      // ignore
    }
    // الدايلوج بتاع النظام بياخد وقت أطول شوية من إعدادات تانية — مهلة
    // أطول قبل ما نعيد الفحص.
    Future.delayed(const Duration(seconds: 2), _checkPermissions);
  }

  /// أي شاشة بتتفتح كـ Route منفصل (Push) لازم تتلف بـ ListenableBuilder
  /// عشان تتحدث فورًا لو حصل تعديل مالي وهي مفتوحة - من غير كده الشاشة
  /// دي StatelessWidget مش هترجع تتبني تاني إلا لو المستخدم خرج ورجع.
  void _openDebts() {
    AdsService.instance.maybeShowOnTransition();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ListenableBuilder(
        listenable: _engine,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text('العملاء والديون'),
            actions: [
              IconButton(
                icon: const Icon(Icons.calculate_outlined),
                tooltip: 'حاسبة الأقساط',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => InstallmentCalculatorScreen(engine: _engine),
                )),
              ),
            ],
          ),
          body: ClientsScreen(engine: _engine),
        ),
      ),
    ));
  }

  void _openPocket() {
    AdsService.instance.maybeShowOnTransition();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ListenableBuilder(
        listenable: _engine,
        builder: (context, _) => PocketScreen(engine: _engine),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // كل شاشة بتتبني بس أول مرة تابها يتزار فعليًا (_visitedTabs) — قبل
    // كده كانت IndexedStack بتبني الخمسة مع بعض من أول تشغيل (ده
    // بالظبط سبب فشل app_startup_test.dart: شاشة الإعدادات بكل اللي
    // فيها (Google Sign-In، بانر AdMob) كانت بتتبني فورًا حتى لو
    // المستخدم عمره ما فتح تاب الإعدادات، وده كان كمان شغل حقيقي زيادة
    // وقت فتح التطبيق مش بس مشكلة اختبار). بعد أول زيارة، الشاشة بتفضل
    // "مزورة" للأبد في الجلسة دي، فبتحافظ على حالتها زي ما كان مقصود.
    final titles = ['محفظتي', 'المحافظ', 'صندوق المراجعة', 'كل الأحداث', 'الإعدادات'];

    // الرئيسية ليها هيدر خاص جواها (اسم التطبيق + شعاره + جرس المراجعة)،
    // فبنخفي الـ AppBar العادي وبنحمي الـ status bar بـ SafeArea بدله.
    final isHome = _tabIndex == 0;

    return Scaffold(
      appBar: isHome ? null : AppBar(title: Text(titles[_tabIndex]), centerTitle: true),
      body: SafeArea(
        top: isHome,
        bottom: false,
        child: Column(
          children: [
            if (!_smsPermissionGranted || !_notificationAccessGranted || !_batteryOptimizationIgnored)
              _PermissionBanner(onOpenSettings: () => _selectTab(4)),
            Expanded(
              // الاستماع لتغييرات المحرك محدود هنا بس (مش حوالين
              // الـ Scaffold/NavigationBar كله زي قبل) — فحدث مالي
              // واحد بيعيد بناء محتوى التاب بس، مش التطبيق كله.
              //
              // IndexedStack بدل التبديل المباشر بين الشاشات: بيحافظ
              // على حالة كل تاب (بما فيها _CloudBackupSection جوه
              // الإعدادات) من غير ما يتبني من الصفر كل مرة تسيب التاب
              // وترجعله — ده كان بيعيد محاولة تسجيل الدخول بـ Google
              // من جديد كل زيارة للإعدادات.
              child: ListenableBuilder(
                listenable: _engine,
                builder: (context, _) {
                  if (_startupError != null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 42),
                            const SizedBox(height: 12),
                            const Text('تعذر تحميل بيانات التطبيق. لم يتم فتح البيانات قبل اكتمال التهيئة.'),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => _initializeFinancialData(LocalStore()),
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (!_engine.isLoaded) {
                    return const Center(child: CircularProgressIndicator());
                  }
                      final screens = [
      _visitedTabs.contains(0)
          ? DashboardScreen(
              engine: _engine,
              onOpenWallets: () => _selectTab(1),
              onOpenDebts: _openDebts,
              onOpenPocket: _openPocket,
              onOpenReview: () => _selectTab(2),
              onOpenSettings: () => _selectTab(4),
            )
          : const SizedBox.shrink(),
      _visitedTabs.contains(1) ? WalletsScreen(engine: _engine) : const SizedBox.shrink(),
      _visitedTabs.contains(2) ? InboxScreen(engine: _engine) : const SizedBox.shrink(),
      _visitedTabs.contains(3) ? TimelineScreen(engine: _engine) : const SizedBox.shrink(),
      _visitedTabs.contains(4)
          ? SettingsScreen(
              engine: _engine,
              smsPermissionGranted: _smsPermissionGranted,
              notificationAccessGranted: _notificationAccessGranted,
              batteryOptimizationIgnored: _batteryOptimizationIgnored,
              onRequestSmsPermission: _requestSmsPermission,
              onOpenNotificationSettings: _openNotificationAccessSettings,
              onRequestBatteryOptimization: _requestIgnoreBatteryOptimizations,
              onOpenInbox: () => _selectTab(2),
            )
          : const SizedBox.shrink(),
    ];
                  return IndexedStack(index: _tabIndex, children: screens);
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) {
          // إعلان بيني واحد بس لكل فتحة تطبيق، عند أول انتقال مناسب
          if (i != _tabIndex) AdsService.instance.maybeShowOnTransition();
          _selectTab(i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'المحافظ',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox),
            label: 'المراجعة',
          ),
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline),
            label: 'الأحداث',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _PermissionBanner({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'فيه أذونات ناقصة عشان نلقط معاملاتك تلقائي.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: onOpenSettings, child: const Text('الإعدادات')),
          ],
        ),
      ),
    );
  }
}
