import 'package:flutter/material.dart';

import '../../core/services/onboarding_store.dart';
import '../../main.dart';

/// شاشات التعريف — تظهر مرة واحدة بس عند أول تشغيل (قبل أي شاشة تانية في
/// التطبيق). بتعمل حاجتين:
///  1. تسأل عن البنك والمحفظة الفعليين للمستخدم، عشان نضبط إعدادات
///     المطابقة على أساسهم بدل القيم الافتراضية (البنك الأهلي/فودافون
///     كاش) — راجع OnboardingStore لتفاصيل التطبيق الفعلي.
///  2. تشرح بإيجاز مكان كل عنصر مهم في التطبيق واستخدامه.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  bool _busy = false;

  bool _isCustomBank = false;
  final _bankSenderController = TextEditingController();
  final _bankNameController = TextEditingController();

  OnboardingWalletChoice _walletChoice = OnboardingWalletChoice.vodafone;
  final _walletSenderController = TextEditingController();
  final _walletNameController = TextEditingController();

  static const _totalPages = 7; // ترحيب + بنك + محفظة + 4 شرح

  @override
  void dispose() {
    _pageController.dispose();
    _bankSenderController.dispose();
    _bankNameController.dispose();
    _walletSenderController.dispose();
    _walletNameController.dispose();
    super.dispose();
  }

  bool get _walletNeedsSender =>
      _walletChoice == OnboardingWalletChoice.orange ||
      _walletChoice == OnboardingWalletChoice.etisalat ||
      _walletChoice == OnboardingWalletChoice.other;

  /// هل التالي مسموح من الصفحة الحالية؟ (بيمنع التقدّم لو اختار "بنك/
  /// محفظة تانية" ولسه مكتبش اسم المرسل).
  bool get _canGoNext {
    if (_page == 1 && _isCustomBank) {
      return _bankSenderController.text.trim().isNotEmpty &&
          _bankNameController.text.trim().isNotEmpty;
    }
    if (_page == 2 && _walletNeedsSender) {
      return _walletSenderController.text.trim().isNotEmpty &&
          _walletNameController.text.trim().isNotEmpty;
    }
    return true;
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _next() {
    if (!_canGoNext) return;
    if (_page < _totalPages - 1) _goTo(_page + 1);
  }

  void _back() {
    if (_page > 0) _goTo(_page - 1);
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    final answers = OnboardingAnswers(
      isCustomBank: _isCustomBank,
      bankSenderId: _isCustomBank ? _bankSenderController.text.trim() : null,
      bankDisplayName: _isCustomBank ? _bankNameController.text.trim() : null,
      walletChoice: _walletChoice,
      walletSenderId: _walletNeedsSender ? _walletSenderController.text.trim() : null,
      walletDisplayName: _walletNeedsSender ? _walletNameController.text.trim() : null,
    );
    await OnboardingStore.saveAndComplete(answers);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AppShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: List.generate(_totalPages, (i) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i <= _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // التنقل بالأزرار بس — عشان نضمن التحقق قبل التقدم
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _WelcomePage(onNext: _next),
                  _BankQuestionPage(
                    isCustomBank: _isCustomBank,
                    onChanged: (v) => setState(() => _isCustomBank = v),
                    senderController: _bankSenderController,
                    nameController: _bankNameController,
                    onFieldChanged: () => setState(() {}),
                  ),
                  _WalletQuestionPage(
                    choice: _walletChoice,
                    onChanged: (v) => setState(() => _walletChoice = v),
                    needsSender: _walletNeedsSender,
                    senderController: _walletSenderController,
                    nameController: _walletNameController,
                    onFieldChanged: () => setState(() {}),
                  ),
                  const _FeaturePage(
                    icon: Icons.home_outlined,
                    title: 'الرئيسية والصافي',
                    body:
                        'تاب "الرئيسية" بيوريك صافي ثروتك (كل محافظك + اللي ليك عند الناس - اللي عليك)، وآخر المعاملات. الرقم ده بيتحدّث تلقائيًا من غير ما تعمل حاجة.',
                  ),
                  const _FeaturePage(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'المحافظ',
                    body:
                        'هنا تلاقي كل محافظك (البنك/المحفظة اللي اخترتها، والجيب، وأي محفظة تضيفها بعدين). من هنا كمان تقدر تعمل تحويل بين المحافظ، أو تفتح شاشة الاتصال السريع (USSD) لو محفظتك بتدعمها.',
                  ),
                  const _FeaturePage(
                    icon: Icons.people_outline,
                    title: 'الديون والمعاملات',
                    body:
                        'سجّل اللي ليك عند الناس واللي عليك، مع تاريخ استحقاق وتذكير تلقائي. وفي صندوق "المراجعة" هتلاقي أي معاملة التطبيق مش متأكد منها 100% عشان تأكدها بنفسك.',
                  ),
                  _FeaturePage(
                    icon: Icons.rocket_launch_outlined,
                    title: 'يلا نبدأ',
                    body:
                        'كل حاجة جاهزة. لو حبيت تغيّر أي حاجة من اللي اخترتها (البنك، المحفظة، الإشعارات) هتلاقيها في تاب "الإعدادات" في أي وقت.',
                    trailing: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _finish,
                        child: _busy
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('ابدأ استخدام محفظتي'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_page < _totalPages - 1)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (_page > 0)
                      TextButton(onPressed: _back, child: const Text('رجوع'))
                    else
                      const SizedBox(width: 72),
                    const Spacer(),
                    FilledButton(
                      onPressed: _canGoNext ? _next : null,
                      child: const Text('التالي'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text('أهلاً بيك في محفظتي', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text(
            'هنسألك كذا سؤال بسيط عشان نظبط التطبيق على بنكك ومحفظتك، وهنوريك بسرعة أهم حاجة فيه.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _BankQuestionPage extends StatelessWidget {
  final bool isCustomBank;
  final ValueChanged<bool> onChanged;
  final TextEditingController senderController;
  final TextEditingController nameController;
  final VoidCallback onFieldChanged;

  const _BankQuestionPage({
    required this.isCustomBank,
    required this.onChanged,
    required this.senderController,
    required this.nameController,
    required this.onFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إيه بنكك؟', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('عشان نقدر نقرا رسايل بنكك صح.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          RadioGroup<bool>(
            groupValue: isCustomBank,
            onChanged: (v) => onChanged(v ?? false),
            child: const Column(
              children: [
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  title: Text('البنك الأهلي المصري'),
                  value: false,
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  title: Text('بنك تاني'),
                  value: true,
                ),
              ],
            ),
          ),
          if (isCustomBank) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'هنستخدم نفس طريقة قراءة رسايل البنك الأهلي على بنكك، على افتراض إن البنوك المصرية بتبعت رسايل بنفس الشكل تقريبًا.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      onChanged: (_) => onFieldChanged(),
                      decoration: const InputDecoration(
                        labelText: 'اسم البنك',
                        hintText: 'مثال: بنك مصر',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: senderController,
                      onChanged: (_) => onFieldChanged(),
                      decoration: const InputDecoration(
                        labelText: 'اسم مرسل الرسائل',
                        hintText: 'زي ما بيظهر في تطبيق الرسائل عندك',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WalletQuestionPage extends StatelessWidget {
  final OnboardingWalletChoice choice;
  final ValueChanged<OnboardingWalletChoice> onChanged;
  final bool needsSender;
  final TextEditingController senderController;
  final TextEditingController nameController;
  final VoidCallback onFieldChanged;

  const _WalletQuestionPage({
    required this.choice,
    required this.onChanged,
    required this.needsSender,
    required this.senderController,
    required this.nameController,
    required this.onFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إيه محفظتك الإلكترونية؟', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('لو عندك أكتر من محفظة، تقدر تضيف الباقي بعدين من شاشة المحافظ.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          RadioGroup<OnboardingWalletChoice>(
            groupValue: choice,
            onChanged: (v) => onChanged(v ?? OnboardingWalletChoice.vodafone),
            child: Column(
              children: OnboardingWalletChoice.values
                  .map((c) => RadioListTile<OnboardingWalletChoice>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.labelAr),
                        value: c,
                      ))
                  .toList(),
            ),
          ),
          if (choice == OnboardingWalletChoice.we) ...[
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'وي باي مش بتبعت رسايل SMS، فمش هنقدر نسجّل معاملاتها تلقائي. هتقدر تضيفها يدويًا بنفسك من شاشة المحفظة في أي وقت.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
          if (needsSender) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'هنستخدم نفس طريقة قراءة رسايل فودافون كاش على محفظتك، على افتراض إن المحافظ المصرية بتبعت رسايل بنفس الشكل تقريبًا.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      onChanged: (_) => onFieldChanged(),
                      decoration: const InputDecoration(
                        labelText: 'اسم المحفظة',
                        hintText: 'مثال: أورنج كاش',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: senderController,
                      onChanged: (_) => onFieldChanged(),
                      decoration: const InputDecoration(
                        labelText: 'اسم مرسل الرسائل',
                        hintText: 'زي ما بيظهر في تطبيق الرسائل عندك',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeaturePage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;

  const _FeaturePage({required this.icon, required this.title, required this.body, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.5)),
          if (trailing != null) ...[
            const SizedBox(height: 28),
            trailing!,
          ],
        ],
      ),
    );
  }
}
