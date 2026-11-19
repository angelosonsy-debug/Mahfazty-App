import 'package:flutter/material.dart';
import '../../core/services/transaction_notifier.dart';
import '../../core/widgets/banner_ad_widget.dart';
import 'package:flutter/services.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/engine/backup_service.dart';
import '../../financial_engine/engine/local_store.dart';
import '../../financial_engine/ai/ai_backend_client.dart';
import '../../financial_engine/ai/ai_settings_store.dart';
import '../../financial_engine/models/wallet_source.dart';
import 'rejection_log_screen.dart';

class SettingsScreen extends StatelessWidget {
  final FinancialEngine engine;
  final bool smsPermissionGranted;
  final bool notificationAccessGranted;
  final bool batteryOptimizationIgnored;
  final VoidCallback onRequestSmsPermission;
  final VoidCallback onOpenNotificationSettings;
  final VoidCallback onRequestBatteryOptimization;
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
        Card(
          child: ListTile(
            leading: const Icon(Icons.search_off_outlined),
            title: const Text('رسائل مرفوضة بصمت'),
            subtitle: const Text('شك إن رسالة بنك/محفظة ضاعت؟ شوفها هنا'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RejectionLogScreen()),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _BackupSection(engine: engine),
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

/// النسخ الاحتياطي/الاستعادة الوحيدة حاليًا: عن طريق النص المنسوخ
/// (Clipboard) - من غير أي مكتبة خارجية أو تسجيل دخول. صدّر، انسخ النص،
/// احفظه فين ما حبيت. استرجع، الصق النص، استورد.
///
/// النسخ السحابي عبر Google Sign-In/Google Drive اتشال بالكامل من المشروع
/// (كان قسم _CloudBackupSection هنا) - قرار واعي لحد ما نرجع للموضوع في
/// أبديت لاحقة. تفاصيل إعداد OAuth المطلوبة لو رجّعناه موجودة في
/// docs/google-sign-in-troubleshooting.md (متسيب عمدًا كمرجع مستقبلي).
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
      // R1: عبر FinancialEngine.restoreBackup عشان يتسلسل مع أي ingest حي
      // (SMS/إشعار واصل وقت الاستعادة) بدل ما يكتب على LocalStore مباشرة.
      final result = await widget.engine.restoreBackup(_backupService, controller.text.trim());
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
    final configured = AiBackendClient.isConfigured;
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
                if (!configured) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'الخدمة دي لسه مش متاحة على السيرفر — التفعيل هنا '
                    'مش هيغيّر حاجة دلوقتي، والتطبيق هيفضل شغال بنظام '
                    'القواعد بس لحد ما تتاح.',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل الفهم الذكي'),
                  subtitle: Text(
                    !configured
                        ? 'مش متاح دلوقتي'
                        : (_enabled ? 'مفعّل — قد تُرسَل رسائل غير مؤكدة للتحليل' : 'متوقف — يعمل بالقواعد فقط'),
                    style: TextStyle(
                      fontSize: 12,
                      color: !configured ? Colors.grey : (_enabled ? Colors.orange : Colors.grey),
                    ),
                  ),
                  value: _enabled && configured,
                  onChanged: configured ? _toggle : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

