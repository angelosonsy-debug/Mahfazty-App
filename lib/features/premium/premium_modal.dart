import 'package:flutter/material.dart';

import '../../core/services/billing_service.dart';

/// نافذة "وصلت لحد النسخة المجانية" - بتستخدم BillingService (Google Play
/// Billing حقيقي)، مش TODO placeholder زي قبل كده.
class PremiumModal extends StatefulWidget {
  const PremiumModal({super.key});

  @override
  State<PremiumModal> createState() => _PremiumModalState();
}

class _PremiumModalState extends State<PremiumModal> {
  final _billing = BillingService.instance;

  @override
  void initState() {
    super.initState();
    _billing.addListener(_onBillingChanged);
  }

  @override
  void dispose() {
    _billing.removeListener(_onBillingChanged);
    super.dispose();
  }

  void _onBillingChanged() {
    if (!mounted) return;
    final state = _billing.state;
    if (state.status == BillingStatus.success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تفعيل Premium! افتح محافظ غير محدودة دلوقتي 🎉')),
      );
      return;
    }
    if (state.status == BillingStatus.error && state.message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message!)));
    }
    setState(() {}); // لتحديث شكل الزرار (تحميل/معطّل/إلخ)
  }

  @override
  Widget build(BuildContext context) {
    final state = _billing.state;
    final isBusy = state.status == BillingStatus.purchasing || state.status == BillingStatus.loading;
    final unavailable = state.status == BillingStatus.unavailable;
    final priceLabel = state.product?.price;

    return AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined, size: 36),
      title: const Text('وصلت لحد النسخة المجانية'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'النسخة المجانية تتيح محفظتين. افتح محافظ غير محدودة مع Premium.',
            textAlign: TextAlign.center,
          ),
          if (unavailable) ...[
            const SizedBox(height: 12),
            Text(
              state.message ?? 'الشراء مش متاح دلوقتي',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: isBusy ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        if (!unavailable)
          TextButton(
            onPressed: isBusy ? null : _billing.restorePurchases,
            child: const Text('استرجاع شراء سابق'),
          ),
        FilledButton(
          onPressed: (unavailable || isBusy) ? null : _billing.buyPremium,
          child: isBusy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(priceLabel != null ? 'اشترِ Premium — $priceLabel' : 'اشترِ Premium'),
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
