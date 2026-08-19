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
/// أبدًا مش بيتحط في الكود المصدري ولا بيترفع مع الريبو. لو مفيش مفتاح
/// أو الخاصية متقفلة، التطبيق شغال عادي بمنطق القواعد بس (Rule Engine).
class _AiSettingsSection extends StatefulWidget {
  const _AiSettingsSection();

  @override
  State<_AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends State<_AiSettingsSection> {
  final _store = AiSettingsStore();
  final _controller = TextEditingController();
  bool _enabled = true;
  bool _hasKey = false;
  bool _loaded = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await _store.loadApiKey();
    final enabled = await _store.loadEnabled();
    setState(() {
      _hasKey = key != null && key.isNotEmpty;
      _controller.text = key ?? '';
      _enabled = enabled;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await _store.saveApiKey(_controller.text);
    await _store.saveEnabled(_enabled);
    setState(() => _hasKey = _controller.text.trim().isNotEmpty);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اتحفظ محليًا على جهازك بس')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('مساعد الفهم بالـ AI', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'بيتفعّل بس لو رسالة/إشعار وصل بثقة منخفضة من القواعد '
                  '(Rule Engine) - وده اللي بيقلل عدد المرات اللي محتاج فيها '
                  'تراجع بنفسك. المفتاح بتاعك بيتخزن على جهازك بس ومحدش بيشوفه.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل مساعد الـ AI'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                TextField(
                  controller: _controller,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'مفتاح API الخاص بيك',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _hasKey ? Icons.check_circle : Icons.info_outline,
                      size: 16,
                      color: _hasKey ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _hasKey ? 'فيه مفتاح محفوظ' : 'مفيش مفتاح - هيشتغل بالقواعد بس',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _save, child: const Text('حفظ')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
