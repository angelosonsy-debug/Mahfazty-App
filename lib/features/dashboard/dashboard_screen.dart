import 'package:flutter/material.dart';

import '../../core/services/net_worth_history.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_format.dart';
import '../../financial_engine/engine/financial_engine.dart';
import '../../financial_engine/models/financial_event.dart';
import '../../financial_engine/models/wallet.dart';
import '../shared/event_actions.dart';

class DashboardScreen extends StatefulWidget {
  final FinancialEngine engine;
  final VoidCallback onOpenWallets;
  final VoidCallback onOpenDebts;
  final VoidCallback onOpenPocket;
  final VoidCallback onOpenReview;
  final VoidCallback? onOpenSettings;

  const DashboardScreen({
    super.key,
    required this.engine,
    required this.onOpenWallets,
    required this.onOpenDebts,
    required this.onOpenPocket,
    required this.onOpenReview,
    this.onOpenSettings,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _history = NetWorthHistory();

  double? _baseline; // آخر لقطة محفوظة قبل النهارده
  double? _lastRecorded;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _loadBaseline();
  }

  Future<void> _loadBaseline() async {
    final baseline = await _history.baselineBeforeToday();
    if (mounted) setState(() => _baseline = baseline);
  }

  /// بنسجّل لقطة النهارده (آخر قيمة في اليوم بتكسب) بس لما القيمة تتغير.
  void _recordSnapshot(double netWorth) {
    final last = _lastRecorded;
    if (last != null && (netWorth - last).abs() < 0.005) return;
    _lastRecorded = netWorth;
    _history.recordToday(netWorth);
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final netWorth = engine.netWorth;
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordSnapshot(netWorth));

    final recentEvents = engine.events.take(5).toList();
    final activeDebts =
        engine.clients.where((c) => engine.clientNet(c.id).abs() > 0.005).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _Header(
          hasPendingReview: engine.pendingReview.isNotEmpty,
          onOpenReview: widget.onOpenReview,
          onOpenSettings: widget.onOpenSettings,
        ),
        const SizedBox(height: 12),
        _NetWorthCard(
          netWorth: netWorth,
          changePercent: NetWorthHistory.changePercent(netWorth, _baseline),
          hidden: _hidden,
          onToggleHidden: () => setState(() => _hidden = !_hidden),
        ),
        if (engine.pendingReview.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.rate_review_outlined),
              title: Text('${engine.pendingReview.length} معاملة محتاجة مراجعتك'),
              subtitle: const Text('راجعها واحدة واحدة - صحيح / تعديل / تجاهل'),
              trailing: FilledButton(onPressed: widget.onOpenReview, child: const Text('راجع الآن')),
            ),
          ),
        ],
        const SizedBox(height: 16),
        // RTL: أول عنصر على اليمين — نفس ترتيب المرجع (الديون / Pocket / المحافظ)
        IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.handshake_outlined,
                title: 'الديون',
                color: AppColors.debtsPurple,
                background: AppColors.debtsPurpleBg,
                lines: [
                  _SummaryLine('لي', '${formatMoney(engine.moneyOwedToMe)} ج.م'),
                  _SummaryLine('عليّ', '${formatMoney(engine.moneyIOwe)} ج.م'),
                ],
                footer: 'عدد الديون: $activeDebts',
                hidden: _hidden,
                onTap: widget.onOpenDebts,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SummaryCard(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Pocket',
                color: AppColors.pocketRed,
                background: AppColors.pocketRedBg,
                lines: [_SummaryLine('متاح', '${formatMoney(engine.pocketBalance)} ج.م')],
                hidden: _hidden,
                onTap: widget.onOpenPocket,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SummaryCard(
                icon: Icons.credit_card,
                title: 'المحافظ',
                color: AppColors.walletsBlue,
                background: AppColors.walletsBlueBg,
                lines: [_SummaryLine('متاح', '${formatMoney(engine.walletsTotal)} ج.م')],
                hidden: _hidden,
                onTap: widget.onOpenWallets,
              ),
            ),
          ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.schedule, size: 20),
            const SizedBox(width: 6),
            Text('آخر المعاملات', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        if (recentEvents.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('مفيش معاملات اتسجلت لسه.')),
            ),
          )
        else ...[
          Card(
            child: Column(
              children: [
                for (var i = 0; i < recentEvents.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  _TransactionRow(
                    event: recentEvents[i],
                    walletType: _walletTypeFor(recentEvents[i]),
                    walletName: _walletNameFor(recentEvents[i]),
                    hidden: _hidden,
                    onLongPress: () => showEventActions(context, engine, recentEvents[i]),
                  ),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'اضغط مطولًا على أي معاملة للتراجع عنها',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ],
    );
  }

  Wallet? _walletFor(FinancialEvent e) {
    final id = e.walletId;
    if (id == null) return null;
    for (final w in widget.engine.wallets) {
      if (w.id == id) return w;
    }
    return null;
  }

  WalletType? _walletTypeFor(FinancialEvent e) => _walletFor(e)?.type;
  String? _walletNameFor(FinancialEvent e) => _walletFor(e)?.name;
}

class _Header extends StatelessWidget {
  final bool hasPendingReview;
  final VoidCallback onOpenReview;
  final VoidCallback? onOpenSettings;

  const _Header({
    required this.hasPendingReview,
    required this.onOpenReview,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // RTL: أول عنصر على اليمين
        _RoundIconButton(
          icon: Icons.person_outline,
          tooltip: 'الإعدادات',
          onPressed: onOpenSettings,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'محفظتي',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'إدارة أموالك .. أسهل',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        _RoundIconButton(
          icon: Icons.notifications_none,
          tooltip: 'مراجعة المعاملات',
          showDot: hasPendingReview,
          onPressed: onOpenReview,
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool showDot;
  final VoidCallback? onPressed;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton.filledTonal(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: Colors.grey.shade200,
            foregroundColor: AppColors.ink,
          ),
        ),
        if (showDot)
          PositionedDirectional(
            top: 8,
            end: 8,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  final double netWorth;
  final double? changePercent;
  final bool hidden;
  final VoidCallback onToggleHidden;

  const _NetWorthCard({
    required this.netWorth,
    required this.changePercent,
    required this.hidden,
    required this.onToggleHidden,
  });

  @override
  Widget build(BuildContext context) {
    final percent = changePercent;
    final isUp = percent == null || percent >= 0;
    final changeColor = isUp ? const Color(0xFF7DF0B4) : const Color(0xFFFFB4A8);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // محفظة شفافة زخرفية في الخلفية
          Positioned(
            left: -14,
            bottom: -18,
            child: Icon(
              Icons.account_balance_wallet_rounded,
              size: 140,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'صافي الثروة',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: onToggleHidden,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hidden ? '••••••' : '${formatMoney(netWorth)} ج.م',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (percent != null && !hidden) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(isUp ? '▲' : '▼', style: TextStyle(color: changeColor, fontSize: 13)),
                      const SizedBox(width: 4),
                      Text(
                        '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(1)}%',
                        style: TextStyle(color: changeColor, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'مقارنة بالأمس',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine {
  final String label;
  final String value;
  const _SummaryLine(this.label, this.value);
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Color background;
  final List<_SummaryLine> lines;
  final String? footer;
  final bool hidden;
  final VoidCallback onTap;

  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.background,
    required this.lines,
    required this.hidden,
    required this.onTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: background,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withValues(alpha: 0.15)),
      ),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color,
                    child: Icon(icon, size: 18, color: Colors.white),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_left, size: 18, color: color),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 6),
              for (final line in lines) ...[
                Text(line.label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    hidden ? '••••' : line.value,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              if (footer != null)
                Text(footer!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final FinancialEvent event;
  final WalletType? walletType;
  final String? walletName;
  final bool hidden;
  final VoidCallback onLongPress;

  const _TransactionRow({
    required this.event,
    required this.walletType,
    required this.walletName,
    required this.hidden,
    required this.onLongPress,
  });

  /// أيقونة/لون حسب نوع المصدر: بنك=أخضر، موبايل=بنفسجي، خدمات=برتقالي.
  ({IconData icon, Color fg, Color bg}) get _style {
    final isService = event.eventType == FinancialEventType.purchase;
    if (isService) {
      return (icon: Icons.bolt, fg: AppColors.servicesOrange, bg: AppColors.servicesOrangeBg);
    }
    switch (event.source) {
      case FinancialSource.vodafoneCash:
        return (icon: Icons.phone_android, fg: AppColors.mobilePurple, bg: AppColors.mobilePurpleBg);
      case FinancialSource.alAhlyBank:
      case FinancialSource.instaPay:
        return (icon: Icons.account_balance, fg: AppColors.bankGreen, bg: AppColors.bankGreenBg);
      case FinancialSource.manual:
        switch (walletType) {
          case WalletType.mobileWallet:
            return (icon: Icons.phone_android, fg: AppColors.mobilePurple, bg: AppColors.mobilePurpleBg);
          case WalletType.bankAccount:
          case WalletType.instaPay:
          case WalletType.card:
            return (icon: Icons.account_balance, fg: AppColors.bankGreen, bg: AppColors.bankGreenBg);
          case WalletType.cash:
          case WalletType.custom:
          case null:
            return (icon: Icons.bolt, fg: AppColors.servicesOrange, bg: AppColors.servicesOrangeBg);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final type = event.eventType;
    final incoming =
        isIncomingEventType(type) || type == FinancialEventType.walletTransferIn;
    final outgoing =
        isOutgoingEventType(type) || type == FinancialEventType.walletTransferOut;

    final Color amountColor = incoming
        ? AppColors.incoming
        : (outgoing ? AppColors.outgoing : Colors.grey.shade700);
    final prefix = outgoing ? '- ' : '';
    final String amountText;
    if (event.amount != null) {
      amountText = '$prefix${formatMoney(event.amount!)} ج.م';
    } else if (event.balanceAfter != null) {
      amountText = 'الرصيد ${formatMoney(event.balanceAfter!)} ج.م';
    } else {
      amountText = '—';
    }

    final title = '${walletName ?? event.source.labelAr} - ${type.labelAr}';
    final time =
        '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: style.bg,
              child: Icon(style.icon, color: style.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hidden ? '••••' : amountText,
                    style: TextStyle(fontWeight: FontWeight.w700, color: amountColor),
                  ),
                  if (event.category != null)
                    Text(
                      event.category!,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
            Text(time, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
