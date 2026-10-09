import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/services/ads_service.dart';
import 'core/services/debt_reminder_scheduler.dart';
import 'core/services/notification_service.dart';
import 'core/services/premium_service.dart';
import 'core/services/transaction_notifier.dart';
import 'core/theme/app_theme.dart';

import 'financial_engine/engine/financial_engine.dart';
import 'financial_engine/engine/schema_migrator.dart';
import 'financial_engine/engine/backup_service.dart';
import 'financial_engine/engine/local_store.dart';
import 'financial_engine/ai/ai_assisted_ingestion.dart';
import 'financial_engine/ai/ai_settings_store.dart';
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
  runApp(const MahfaztyApp());
  // AdMob بعد runApp عشان تهيئته (ممكن تاخد ثواني على نت ضعيف) ما تأخرش
  // فتح التطبيق. لو فشلت، التطبيق شغال عادي من غير إعلانات.
  unawaited(AdsService.instance.init());
}

class MahfaztyApp extends StatelessWidget {
  const MahfaztyApp({super.key});

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
      home: const AppShell(),
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

class _AppShellState extends State<AppShell> {
  static const MethodChannel _smsChannel = MethodChannel('mahfazty/sms');
  static const MethodChannel _notificationsChannel = MethodChannel('mahfazty/notifications');

  late final FinancialEngine _engine;
  late final AiAssistedIngestion _ingestion;
  int _tabIndex = 0;
  bool _smsPermissionGranted = false;
  bool _notificationAccessGranted = false;

  @override
  void initState() {
    super.initState();
    final store = LocalStore();
    _engine = FinancialEngine(
      store,
      notifier: TransactionNotifier.instance,
      reminderScheduler: DebtReminderScheduler.instance,
    );
    _ingestion = AiAssistedIngestion(_engine, AiSettingsStore());
    _engine.addListener(() => setState(() {}));
    // I1: Migration آمنة (idempotent — لا تشتغل مرتين)
    SchemaMigrator(store, BackupService(store)).runIfNeeded();
    _engine.load();

    _smsChannel.setMethodCallHandler(_handleSms);
    _notificationsChannel.setMethodCallHandler(_handleNotification);
    _checkPermissions();
    unawaited(_initNotifications());
  }

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

  Future<void> _checkPermissions() async {
    try {
      final granted = await _smsChannel.invokeMethod<bool>('isSmsPermissionGranted');
      setState(() => _smsPermissionGranted = granted ?? false);
    } on PlatformException {
      setState(() => _smsPermissionGranted = false);
    }
    try {
      final granted = await _notificationsChannel.invokeMethod<bool>('isNotificationAccessGranted');
      setState(() => _notificationAccessGranted = granted ?? false);
    } on PlatformException {
      setState(() => _notificationAccessGranted = false);
    }
  }

  Future<void> _requestSmsPermission() async {
    try {
      await _smsChannel.invokeMethod('requestSmsPermission');
    } on PlatformException {
      // ignore
    }
    Future.delayed(const Duration(seconds: 1), _checkPermissions);
  }

  Future<void> _openNotificationAccessSettings() async {
    try {
      await _notificationsChannel.invokeMethod('openNotificationAccessSettings');
    } on PlatformException {
      // ignore
    }
    Future.delayed(const Duration(seconds: 1), _checkPermissions);
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
    final screens = [
      DashboardScreen(
        engine: _engine,
        onOpenWallets: () => setState(() => _tabIndex = 1),
        onOpenDebts: _openDebts,
        onOpenPocket: _openPocket,
        onOpenReview: () => setState(() => _tabIndex = 2),
        onOpenSettings: () => setState(() => _tabIndex = 4),
      ),
      WalletsScreen(engine: _engine),
      InboxScreen(engine: _engine),
      TimelineScreen(engine: _engine),
      SettingsScreen(
        engine: _engine,
        smsPermissionGranted: _smsPermissionGranted,
        notificationAccessGranted: _notificationAccessGranted,
        onRequestSmsPermission: _requestSmsPermission,
        onOpenNotificationSettings: _openNotificationAccessSettings,
        onOpenInbox: () => setState(() => _tabIndex = 2),
      ),
    ];

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
            if (!_smsPermissionGranted || !_notificationAccessGranted)
              _PermissionBanner(onOpenSettings: () => setState(() => _tabIndex = 4)),
            Expanded(
              child: _engine.isLoaded
                  ? screens[_tabIndex]
                  : const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) {
          // إعلان بيني واحد بس لكل فتحة تطبيق، عند أول انتقال مناسب
          if (i != _tabIndex) AdsService.instance.maybeShowOnTransition();
          setState(() => _tabIndex = i);
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
