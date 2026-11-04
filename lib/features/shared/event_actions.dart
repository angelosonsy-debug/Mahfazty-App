import 'package:flutter/material.dart';

import '../../core/utils/money_format.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/financial_event.dart';

/// قائمة إجراءات المعاملة (ضغطة مطولة على أي معاملة في "آخر المعاملات"):
/// تفاصيل مختصرة + زر "تراجع" لو المعاملة ضمن آخر [FinancialEngine.undoWindow].
Future<void> showEventActions(
  BuildContext context,
  FinancialEngine engine,
  FinancialEvent event,
) async {
  final canUndo = engine.canUndo(event.id);
  final amount = event.amount == null ? null : '${formatMoney(event.amount!)} جنيه';

  final wantsUndo = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${event.source.labelAr} - ${event.eventType.labelAr}',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            if (amount != null) ...[
              const SizedBox(height: 4),
              Text(amount, style: Theme.of(sheetContext).textTheme.bodyLarge),
            ],
            if (event.rawMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                event.rawMessage,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            if (canUndo)
              FilledButton.icon(
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.undo),
                label: const Text('تراجع'),
              )
            else
              const Text(
                'التراجع متاح لآخر 5 معاملات بس.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
          ],
        ),
      ),
    ),
  );

  if (wantsUndo != true || !context.mounted) return;
  await confirmAndUndo(context, engine, event);
}

/// Dialog تأكيد → engine.undoEvent → SnackBar فيه "إعادة" لو اتراجع بالغلط.
Future<void> confirmAndUndo(
  BuildContext context,
  FinancialEngine engine,
  FinancialEvent event,
) async {
  final isTransfer = engine.isWalletTransferEvent(event);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تراجع عن المعاملة؟'),
      content: Text(
        isTransfer
            ? 'هيتحذف التحويل بين المحافظ بالكامل (الخصم والإضافة) والأرصدة هترجع زي ما كانت.'
            : 'المعاملة هتتحذف والرصيد هيترجع زي ما كان قبلها.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تراجع')),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final done = await engine.undoEvent(event.id);
  if (!done) return;

  messenger.showSnackBar(
    SnackBar(
      content: const Text('تم التراجع عن المعاملة'),
      action: SnackBarAction(
        label: 'إعادة',
        onPressed: () => engine.restoreLastUndone(),
      ),
    ),
  );
}
