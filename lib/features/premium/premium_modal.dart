import 'package:flutter/material.dart';

/// نافذة "وصلت لحد النسخة المجانية". زر الشراء placeholder لحد ما
/// Google Play Billing يتربط (هيتنادى PremiumService.setPremium(true) بعد
/// التحقق من الشراء).
class PremiumModal extends StatelessWidget {
  const PremiumModal({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined, size: 36),
      title: const Text('وصلت لحد النسخة المجانية'),
      content: const Text(
        'النسخة المجانية تتيح محفظتين. افتح محافظ غير محدودة مع Premium.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            // TODO(billing): هنا هنبدأ عملية الشراء عبر Google Play Billing.
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context);
            messenger.showSnackBar(
              const SnackBar(content: Text('الشراء داخل التطبيق هيتفعّل قريبًا')),
            );
          },
          child: const Text('اشترِ Premium'),
        ),
      ],
    );
  }
}

Future<void> showPremiumModal(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const PremiumModal(),
  );
}
