import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInAccount;
import '../../core/services/transaction_notifier.dart';
import '../../core/widgets/banner_ad_widget.dart';
import 'package:flutter/services.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/engine/backup_service.dart';
import '../../financial_engine/engine/google_drive_backup_service.dart';
import '../../financial_engine/engine/local_store.dart';
import '../../financial_engine/ai/ai_settings_store.dart';
import '../../financial_engine/models/wallet_source.dart';

class SettingsScreen extends StatelessWidget {
  final FinancialEngine engine;
  final bool smsPermissionGranted;
  final bool notificationAccessGranted;
  final bool batteryOptimizationIgnored;
  final VoidCallback onRequestSmsPermission;
  final VoidCallback onOpenNotificationSettings;
  final VoidCallback onRequestBatteryOptimization;
  final Future<int> Function({int sinceDays}) onScanSmsInbox;
  final VoidCallback onOpenInbox;

  const SettingsScreen({
    super.key,
    required this.engine,
    required this.smsPermissionGranted,
    required this.notificationAccessGranted,
    required this.batteryOptimizationIgnored,
    required this.onRequestSmsPermission,
    required this.onOpenNotificationSettings,
    required this.onRequestBatteryOptimization,
    required this.onScanSmsInbox,
    required this.onOpenInbox,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('الأذونات', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(
              smsPermissionGranted ? Icons.check_circle : Icons.error_outline,
              color: smsPermissionGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('قراءة الرسائل (SMS)'),
            subtitle: const Text('مطلوب عشان نلقط رسائل البنوك والمحافظ الإلكترونية'),
            trailing: smsPermissionGranted
                ? null
                : TextButton(onPressed: onRequestSmsPermission, child: const Text('فعّل')),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(
              notificationAccessGranted ? Icons.check_circle : Icons.error_outline,
              color: notificationAccessGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('Notification Access'),
            subtitle: const Text('مطلوب عشان نلقط إشعارات InstaPay ونطابقها مع رسائل البنك'),
            trailing: notificationAccessGranted
                ? null
                : TextButton(onPressed: onOpenNotificationSettings, child: const Text('فعّل')),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(
              batteryOptimizationIgnored ? Icons.check_circle : Icons.error_outline,
              color: batteryOptimizationIgnored ? Colors.green : Colors.red,
            ),
            title: const Text('استثناء من تحسين البطارية'),
            subtitle: Text(
              batteryOptimizationIgnored
                  ? 'التطبيق مستثنى — المعاملات هتتسجل حتى لو التطبيق مقفول'
                  : 'مهم جدًا: من غيره، النظام ممكن يقفل رصد الرسائل/الإشعارات '
                      'في الخلفية على بعض الأجهزة (خصوصًا Xiaomi/Oppo/Huawei) '
                      'وتفوتك معاملات',
              style: TextStyle(
                color: batteryOptimizationIgnored ? null : Colors.red.shade700,
                fontWeight: batteryOptimizationIgnored ? null : FontWeight.w600,
              ),
            ),
            trailing: batteryOptimizationIgnored
                ? null
                : FilledButton(
                    onPressed: onRequestBatteryOptimization,
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                    child: const Text('فعّل الآن'),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        Text('مصادر البيانات', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _DataSourcesCard(engine: engine),
        const SizedBox(height: 24),
        _SmsRescanSection(onScanSmsInbox: onScanSmsInbox),
        const SizedBox(height: 24),
        const _AiSettingsSection(),
        const SizedBox(height: 24),
        Text('مراجعة المعاملات', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.rate_review_outlined),
            title: const Text('صندوق المراجعة (Inbox)'),
            subtitle: Text('${engine.pendingReview.length} معاملة محتاجة تأكيد'),
            trailing: const Icon(Icons.chevron_left),
            onTap: onOpenInbox,
          ),
        ),
        const SizedBox(height: 24),
        _CloudBackupSection(engine: engine),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('خيارات متقدمة'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
          children: [_BackupSection(engine: engine)],
        ),
        const SizedBox(height: 24),
        Text('الإشعارات', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const _NotifyTransactionTile(),
        const SizedBox(height: 24),
        Text('عن التطبيق', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('محفظتي'),
            subtitle: Text('كل البيانات محفوظة على جهازك بس - الإنترنت مطلوب بس لو فعّلت مساعد الفهم بالـ AI'),
          ),
        ),
        const SizedBox(height: 24),
        const BannerAdWidget(),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// بطاقة "مصادر البيانات" — بتعرض المحافظ والمصادر المُضافة فعليًا بدل
/// نص ثابت بيفترض إن كل مستخدم عنده فودافون كاش والبنك الأهلي بس. أي
/// مصدر مش من المصدرين الثابتين (فودافون كاش/البنك الأهلي) بيتوضح إنه
/// بيعتمد على فهم السياق العام (كلمات مفتاحية) مش قالب جاهز حرفي.
class _DataSourcesCard extends StatelessWidget {
  final FinancialEngine engine;
  const _DataSourcesCard({required this.engine});

  @override
  Widget build(BuildContext context) {
    final sources = engine.walletSources.where((s) => s.enabled).toList();
    String walletNameFor(String walletId) {
      for (final w in engine.wallets) {
        if (w.id == walletId) return w.name;
      }
      return 'محفظة محذوفة';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sources.isEmpty)
              const Text(
                'مفيش مصادر مُضافة لسه — ضيف مصدر (SMS أو إشعار) لأي محفظة '
                'من شاشة "المحافظ" عشان نبدأ نلقط معاملاتها أوتوماتيك.',
              )
            else
              for (final s in sources) ...[
                _SourceLine(
                  walletName: walletNameFor(s.walletId),
                  sourceLabel: s.sourceType.labelAr,
                  identifier: s.identifier,
                  isLegacy: _isLegacySource(s.identifier),
                ),
                const SizedBox(height: 4),
              ],
            const Divider(height: 20),
            const Text(
              '✅ InstaPay - إشعار InstaPay + رسالة SMS البنك الأهلي بيتطابقوا '
              'تلقائي لو نفس المبلغ خلال دقيقتين ويتحسبوا كمعاملة واحدة',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            const Text(
              '🚫 رسائل/إشعارات ترويجية أو عروض - بتتجاهل تمامًا',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            const Text(
              '✅ الكاش والديون - يدوي بالكامل دايمًا',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// فودافون كاش والبنك الأهلي بس عندهم قوالب حرفية جاهزة (ثقة فورية
  /// عالية). أي مصدر تاني بيعتمد على SemanticClassifier (كلمات مفتاحية)
  /// فبيستاهل توضيح إضافي إنه مش بنفس درجة الدقة الفورية.
  static bool _isLegacySource(String identifier) {
    final lower = identifier.toLowerCase();
    return lower.contains('vf') || lower.contains('vodafone') || lower.contains('ahly') || lower.contains('nbe');
  }
}

class _SourceLine extends StatelessWidget {
  final String walletName;
  final String sourceLabel;
  final String identifier;
  final bool isLegacy;

  const _SourceLine({
    required this.walletName,
    required this.sourceLabel,
    required this.identifier,
    required this.isLegacy,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          const TextSpan(text: '✅ '),
          TextSpan(text: walletName, style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: ' — $sourceLabel من "$identifier"'),
          if (!isLegacy)
            const TextSpan(
              text: ' (بالفهم العام — بعض المعاملات ممكن تروح للمراجعة للتأكيد)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}

/// فحص يدوي لرسايل الـ SMS القديمة — مفيد أول إعداد (لو المستخدم عمل
/// معاملة قبل ما يفتح التطبيق أو يضيف المصدر)، أو كـ recovery لو الخدمة
/// كانت متوقفة فترة (تحسين بطارية مثلاً).
class _SmsRescanSection extends StatefulWidget {
  final Future<int> Function({int sinceDays}) onScanSmsInbox;
  const _SmsRescanSection({required this.onScanSmsInbox});

  @override
  State<_SmsRescanSection> createState() => _SmsRescanSectionState();
}

class _SmsRescanSectionState extends State<_SmsRescanSection> {
  bool _scanning = false;

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final count = await widget.onScanSmsInbox(sinceDays: 30);
    if (!mounted) return;
    setState(() => _scanning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'تم فحص $count رسالة من آخر 30 يوم — أي معاملة جديدة اتسجلت أو راحت للمراجعة'
              : 'مفيش رسائل جديدة اتلاقت في آخر 30 يوم',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('استرجاع معاملات قديمة', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'عملت معاملة قبل ما تفتح التطبيق أو تضيف المصدر؟ أو مش متأكد '
                  'إن كل حاجة اتسجلت؟ فحص الرسائل القديمة (Inbox) بياخد نفس '
                  'الرسائل اللي كانت هتوصلك لو التطبيق كان شغال، ويعالجها '
                  'بنفس المنطق بالظبط — مفيش هيتضاعف لو كانت متسجلة من قبل.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _scanning ? null : _scan,
                    icon: _scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.history),
                    label: Text(_scanning ? 'جاري الفحص...' : 'فحص آخر 30 يوم'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NotifyTransactionTile extends StatefulWidget {
  const _NotifyTransactionTile();
  @override
  State<_NotifyTransactionTile> createState() => _NotifyTransactionTileState();
}

class _NotifyTransactionTileState extends State<_NotifyTransactionTile> {
  bool _enabled = TransactionNotifier.instance.enabled;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.notifications_active_outlined),
        title: const Text('إشعار عند كل عملية'),
        subtitle: const Text('إشعار لكل عملية مؤكدة (ثقة ≥ 95%)'),
        value: _enabled,
        onChanged: (v) async {
          await TransactionNotifier.instance.setEnabled(v);
          if (mounted) setState(() => _enabled = v);
        },
      ),
    );
  }
}

/// النسخ الاحتياطي السحابي الرئيسي — عبر appDataFolder في Google Drive
/// بتاع المستخدم نفسه (مش سيرفر بتاعنا). ده القسم الأساسي اللي المفروض
/// معظم المستخدمين يستخدموه؛ النسخ عبر Clipboard (_BackupSection تحت)
/// بقى خيار ثانوي جوه "خيارات متقدمة".
class _CloudBackupSection extends StatefulWidget {
  final FinancialEngine engine;
  const _CloudBackupSection({required this.engine});

  @override
  State<_CloudBackupSection> createState() => _CloudBackupSectionState();
}

class _CloudBackupSectionState extends State<_CloudBackupSection> {
  final _drive = GoogleDriveBackupService();
  bool _loading = true;
  bool _signedIn = false;
  String? _email;
  DateTime? _lastBackup;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    final signedIn = await _drive.isSignedIn();
    DateTime? last;
    if (signedIn) {
      try {
        last = await _drive.getLastBackupTimestamp();
      } catch (_) {
        last = null; // فشل الاستعلام (مفيش نت مثلاً) — مش حرج هنا
      }
    }
    if (!mounted) return;
    setState(() {
      _signedIn = signedIn;
      _email = _drive.currentUser?.email;
      _lastBackup = last;
      _loading = false;
    });
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    GoogleSignInAccount? account;
    try {
      account = await _drive.signIn();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تسجيل الدخول بـ Google')),
        );
      }
    }
    if (account != null) {
      // أول نسخة احتياطية فورًا بعد تسجيل الدخول — النسخ التلقائي
      // التالي هيحصل عند فتح التطبيق لاحقًا لو آخر نسخة بقت أقدم من
      // ٢٤ ساعة (راجع main.dart._maybeBackupOnOpen)، مش عبر جدولة
      // خلفية حقيقية.
      try {
        final backupService = BackupService(LocalStore());
        final json = await backupService.exportBackup();
        await _drive.uploadBackup(json);
      } catch (_) {
        // تسجيل الدخول نجح لكن أول رفع فشل (مفيش نت مثلاً) — مش حرج،
        // هيتعاد المحاولة عند فتح التطبيق الجاي أو ضغطة "انسخ احتياطيًا
        // الآن" يدويًا.
      }
    }
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await _drive.signOut();
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    try {
      final backupService = BackupService(LocalStore());
      final json = await backupService.exportBackup();
      await _drive.uploadBackup(json);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم النسخ الاحتياطي بنجاح')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل النسخ الاحتياطي — تأكد من الاتصال بالإنترنت')),
        );
      }
    }
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    bool hasBackup;
    try {
      hasBackup = await _drive.hasExistingBackup();
    } catch (_) {
      hasBackup = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر الوصول لـ Google Drive الآن')),
        );
      }
    }
    if (!mounted) return;
    if (!hasBackup) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مفيش نسخة احتياطية سابقة على Drive بعد')),
        );
      }
      return;
    }

    final lastText = _formatLastBackup(_lastBackup);
    setState(() => _busy = false);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة من Google Drive'),
        content: Text(
          'آخر نسخة احتياطية محفوظة بتاريخ $lastText. الاستعادة هتستبدل '
          'بياناتك الحالية بالكامل بمحتوى هذه النسخة. متأكد؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final json = await _drive.downloadBackup();
      if (json == null) throw StateError('مفيش نسخة');
      final backupService = BackupService(LocalStore());
      final result = await backupService.importBackup(json);
      await widget.engine.load(); // إعادة تحميل الحالة من التخزين بعد الاستعادة
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت الاستعادة: ${result.eventsCount} حدث، ${result.clientsCount} عميل، '
              '${result.transactionsCount} معاملة دين',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشلت الاستعادة')),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  String _formatLastBackup(DateTime? dt) {
    if (dt == null) return 'لسه ما حصلش';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} — $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('النسخ الاحتياطي السحابي', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : (_signedIn ? _buildSignedIn(context) : _buildSignedOut(context)),
          ),
        ),
      ],
    );
  }

  Widget _buildSignedOut(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'بياناتك المالية بتتخزن في مساحتك الخاصة على Google Drive — '
          'التطبيق لا يرى ولا يصل لأي ملفات تانية عندك على Drive.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _signIn,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(_busy ? 'جاري الاتصال...' : 'تسجيل الدخول بـ Google'),
          ),
        ),
      ],
    );
  }

  Widget _buildSignedIn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_circle, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _email ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'آخر نسخة احتياطية: ${_formatLastBackup(_lastBackup)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        const Text(
          'بتتحدّث تلقائيًا لما تفتح التطبيق لو آخر نسخة أقدم من ٢٤ ساعة — '
          'أو اضغط "انسخ احتياطيًا الآن" في أي وقت.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _backupNow,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('انسخ احتياطيًا الآن'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('استعادة'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton.icon(
                onPressed: _busy ? null : _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('تسجيل الخروج'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// نسخ احتياطي/استعادة محلي عن طريق النص المنسوخ (Clipboard) - من غير أي
/// مكتبة جديدة. صدّر، انسخ النص، احفظه فين ما حبيت. استرجع، الصق النص،
/// استورد. خيار ثانوي دلوقتي (جوه "خيارات متقدمة") بعد إضافة النسخ
/// السحابي عبر Google Drive كخيار أساسي.
class _BackupSection extends StatefulWidget {
  final FinancialEngine engine;
  const _BackupSection({required this.engine});

  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  late final BackupService _backupService;

  @override
  void initState() {
    super.initState();
    _backupService = BackupService(LocalStore());
  }

  Future<void> _export(BuildContext context) async {
    final json = await _backupService.exportBackup();
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اتنسخت النسخة الاحتياطية - الصقها فين ما تحب تحفظها')),
      );
    }
  }

  Future<void> _import(BuildContext context) async {
    final controller = TextEditingController();
    final clipboard = await Clipboard.getData('text/plain');
    if (clipboard?.text != null) controller.text = clipboard!.text!;

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'الصق نص النسخة الاحتياطية هنا. البيانات هتتضاف لبياناتك الحالية '
              '(معاملات بنفس الـ ID هتتحدث بدل ما تتكرر).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'الصق النص هنا'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('استعادة')),
        ],
      ),
    );

    if (confirmed != true || controller.text.trim().isEmpty) return;

    try {
      final result = await _backupService.importBackup(controller.text.trim());
      await widget.engine.load(); // إعادة تحميل الحالة من التخزين بعد الاستعادة
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت الاستعادة: ${result.eventsCount} حدث، ${result.clientsCount} عميل، '
              '${result.transactionsCount} معاملة دين',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('النص ده مش نسخة احتياطية صالحة')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('نسخة احتياطية', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'محلي بالكامل - من غير إنترنت، من غير سيرفر. التصدير بينسخ '
                  'نص كامل ببياناتك، والاستعادة بتقراه من نفس المكان.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _export(context),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('تصدير (نسخ)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _import(context),
                        icon: const Icon(Icons.paste_outlined),
                        label: const Text('استعادة'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// إعدادات الـ AI المساعد - المفتاح بيتخزن محليًا بس على الجهاز (SharedPreferences)،
/// C3: الـ API Key أُزيل — المستخدم لا يحتاج إدخاله.
/// الإعداد الوحيد هو تفعيل/تعطيل "الفهم الذكي".
class _AiSettingsSection extends StatefulWidget {
  const _AiSettingsSection();

  @override
  State<_AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends State<_AiSettingsSection> {
  final _store = AiSettingsStore();
  bool _enabled = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _store.loadEnabled().then((v) {
      if (mounted) setState(() { _enabled = v; _loaded = true; });
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await _store.saveEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الفهم الذكي', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'عند تفعيله، الرسائل التي لا يتعرف عليها نظام القواعد '
                  'بثقة كافية تُحلَّل عبر خدمة ذكاء اصطناعي خارجية. '
                  'يُرسَل نص الرسالة فقط — لا تاريخ المعاملات ولا أرصدة '
                  'المحافظ. يمكنك إيقافه في أي وقت.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ملاحظة: التطبيق يعمل كاملًا بدون هذه الميزة.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل الفهم الذكي'),
                  subtitle: Text(
                    _enabled ? 'مفعّل — قد تُرسَل رسائل غير مؤكدة للتحليل' : 'متوقف — يعمل بالقواعد فقط',
                    style: TextStyle(fontSize: 12, color: _enabled ? Colors.orange : Colors.grey),
                  ),
                  value: _enabled,
                  onChanged: _toggle,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

