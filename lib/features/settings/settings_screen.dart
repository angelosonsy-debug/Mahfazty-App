import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/engine/backup_service.dart';
import '../../financial_engine/engine/local_store.dart';
import '../../financial_engine/ai/ai_settings_store.dart';

class SettingsScreen extends StatelessWidget {
  final FinancialEngine engine;
  final bool smsPermissionGranted;
  final bool notificationAccessGranted;
  final VoidCallback onRequestSmsPermission;
  final VoidCallback onOpenNotificationSettings;
  final VoidCallback onOpenInbox;

  const SettingsScreen({
    super.key,
    required this.engine,
    required this.smsPermissionGranted,
    required this.notificationAccessGranted,
    required this.onRequestSmsPermission,
    required this.onOpenNotificationSettings,
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
            subtitle: const Text('مطلوب عشان نلقط رسائل فودافون كاش (VF-Cash) والبنك الأهلي'),
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
        const SizedBox(height: 24),
        Text('مصادر البيانات', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('✅ Vodafone Cash - رسائل SMS من VF-Cash بس'),
                SizedBox(height: 4),
                Text('✅ InstaPay - إشعار InstaPay + رسالة SMS البنك الأهلي بيتطابقوا '
                    'تلقائي لو نفس المبلغ خلال دقيقتين ويتحسبوا كمعاملة واحدة'),
                SizedBox(height: 4),
                Text('🚫 رسائل/إشعارات ترويجية أو عروض - بتتجاهل تمامًا'),
                SizedBox(height: 4),
                Text('✅ الكاش والديون - يدوي بالكامل دايمًا'),
              ],
            ),
          ),
        ),
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
        _BackupSection(engine: engine),
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
      ],
    );
  }
}

/// نسخ احتياطي/استعادة محلي عن طريق النص المنسوخ (Clipboard) - من غير أي
/// مكتبة جديدة. صدّر، انسخ النص، احفظه فين ما حبيت. استرجع، الصق النص،
/// استورد.
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

