// 资金 Tab 账户列表卡片，从 accounts_view.dart 拆出。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money_format.dart';
import '../../core/app_clock.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/settings_ui.dart';
import 'asset_form_kit.dart';

class FundsSectionHeader extends StatelessWidget {
  const FundsSectionHeader({super.key, required this.title, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final style =
        AppType.secondary(Theme.of(context).colorScheme).copyWith(fontSize: 13);
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 7),
        child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(title, style: style),
              if (trailing != null)
                Text(trailing!, style: style.copyWith(fontFamily: 'Nunito')),
            ]));
  }
}

/// Shared funds/receivables geometry, with a second line for large text.
class FundsAssetRow extends StatelessWidget {
  const FundsAssetRow(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      required this.amount,
      required this.onTap,
      this.muted = false,
      this.negative = false});
  final IconData icon;
  final String title;
  final Widget subtitle;
  final String amount;
  final VoidCallback onTap;
  final bool muted;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleWidget = Text(title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppType.rowTitle(scheme).copyWith(
            fontSize: 15,
            color: muted ? AppTextColor.hint(scheme) : scheme.onSurface));
    final money = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(amount,
            style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: muted
                    ? AppTextColor.hint(scheme)
                    : negative
                        ? AppColors.warning
                        : scheme.onSurface)));
    return InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: LayoutBuilder(builder: (context, constraints) {
              final stacked = constraints.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(15) > 21;
              final labels = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    titleWidget,
                    const SizedBox(height: 2),
                    subtitle,
                    if (stacked) ...[
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerRight, child: money)
                    ]
                  ]);
              return Row(children: [
                Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.iconCircleFill(scheme),
                        borderRadius: BorderRadius.circular(11)),
                    child: Icon(icon,
                        size: 18, color: AppTextColor.secondary(scheme))),
                const SizedBox(width: 12),
                Expanded(child: labels),
                if (!stacked) ...[
                  const SizedBox(width: 10),
                  ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
                      child: money)
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 15, color: AppTextColor.hint(scheme)),
              ]);
            })));
  }
}

/// repo.upcomingRepayments() 的行记录（结构化 record 类型别名，UI 侧引用用）。
typedef UpcomingRepaymentItem = ({
  LiabilityProfileEntity profile,
  AccountEntity? account,
  DateTime nextDate,
  int daysLeft,
});

/// 资金页顶部「最近要还」卡（A 批 A1）：10 天内到期的还款按日排，
/// 行内「还款」直达还款弹层。今天到期=warning 橙、1-3 天=kCatGold。
class UpcomingRepaymentsCard extends StatelessWidget {
  final List<UpcomingRepaymentItem> items;
  final ValueChanged<UpcomingRepaymentItem> onRepay;

  const UpcomingRepaymentsCard({
    super.key,
    required this.items,
    required this.onRepay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: appCardDecoration(scheme),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 4),
            child: Text('最近要还', style: AppType.sectionLabel(scheme)),
          ),
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) appCardDivider(scheme),
            _UpcomingRepaymentRow(item: items[i], onRepay: onRepay),
          ],
        ],
      ),
    );
  }
}

class _UpcomingRepaymentRow extends StatelessWidget {
  final UpcomingRepaymentItem item;
  final ValueChanged<UpcomingRepaymentItem> onRepay;

  const _UpcomingRepaymentRow({required this.item, required this.onRepay});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = item.nextDate;
    final dateText = '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    // 借入的一次性还款日可能已过（daysLeft < 0），如实标逾期。
    final dueText = item.daysLeft < 0
        ? '已逾期 ${-item.daysLeft} 天'
        : item.daysLeft == 0
            ? '今天'
            : '还有 ${item.daysLeft} 天';
    final dueColor = item.daysLeft <= 0
        ? AppColors.warning
        : item.daysLeft <= 3
            ? kCatGold
            : null;
    final subtitleStyle = AppType.secondary(scheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // 档案挂的账户被删/归档时不瞎编名字，如实兜底。
                  item.account?.name ?? '负债账户',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowTitle(scheme),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    digitAwareAmountSpan('$dateText · ', subtitleStyle),
                    digitAwareAmountSpan(
                      dueText,
                      dueColor == null
                          ? subtitleStyle
                          : subtitleStyle.copyWith(color: dueColor),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppPillButton(
            key: Key('upcoming-repay-${item.profile.id}'),
            label: '还款',
            onPressed: () => onRepay(item),
          ),
        ],
      ),
    );
  }
}

class FundsAccountBalance {
  final AccountEntity account;
  final Decimal balance;
  final String? qualityText;
  final DateTime? calibratedAt;

  const FundsAccountBalance({
    required this.account,
    required this.balance,
    this.qualityText,
    this.calibratedAt,
  });
}

class FundsAccountGroup {
  final AccountType type;
  final List<FundsAccountBalance> items;

  const FundsAccountGroup({
    required this.type,
    required this.items,
  });
}

class FundsAccountGroupCard extends StatelessWidget {
  final FundsAccountGroup group;
  final ValueChanged<AccountEntity> onTap;

  const FundsAccountGroupCard({
    super.key,
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 组内币种不一致时不硬加，避免算出一个混币种的假小计（数据诚实性优先）。
    final currencies =
        group.items.map((item) => item.account.currencyCode).toSet();
    final showSubtotal = currencies.length == 1 && group.items.length > 1;
    final subtotal = group.items
        .fold<Decimal>(Decimal.zero, (sum, item) => sum + item.balance);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FundsSectionHeader(
          title: '${group.type.label} · ${group.items.length}',
          trailing: showSubtotal
              ? MoneyFormat.string(subtotal, currencyCode: currencies.single)
              : null),
      Container(
        decoration: ShapeDecoration(
            color: AppColors.card(scheme),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side:
                    BorderSide(color: AppColors.hairline(scheme), width: 0.5))),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (int i = 0; i < group.items.length; i++) ...[
            if (i > 0) appCardDivider(scheme),
            FundsAccountBalanceTile(
              item: group.items[i],
              onTap: () => onTap(group.items[i].account),
            ),
          ],
        ]),
      ),
    ]);
  }
}

class FundsAccountBalanceTile extends StatelessWidget {
  final FundsAccountBalance item;
  final VoidCallback onTap;

  const FundsAccountBalanceTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = context
        .watch<AppRepository>()
        .liabilityProfileForAccount(item.account.id);
    final negative = item.balance < Decimal.zero;
    final muted = !item.account.includeInNetWorth;
    final today = AppClock.now;
    final calibrated = item.calibratedAt;
    final daysSince = calibrated == null
        ? null
        : DateTime(today.year, today.month, today.day)
            .difference(
                DateTime(calibrated.year, calibrated.month, calibrated.day))
            .inDays;
    final calibration = daysSince == null
        ? '从未校准'
        : daysSince == 0
            ? '今天校准'
            : daysSince > 30
                ? '$daysSince 天未校准'
                : '$daysSince 天前校准';
    final daysLeft =
        profile != null && profile.status == LiabilityProfileStatus.active
            ? profile.daysUntilRepayment()
            : null;
    final dueSoon = daysLeft != null && daysLeft <= 10;
    final extra = dueSoon
        ? (daysLeft < 0
            ? '已逾期 ${-daysLeft} 天'
            : daysLeft == 0
                ? '今天还款'
                : '$daysLeft 天后还款')
        : item.qualityText ??
            (!item.account.includeInNetWorth ? '不计入净资产' : calibration);
    // 还款临近的颜色语义：逾期/今天=warning 橙、1-3 天=kCatGold（不用红绿）。
    final extraColor = !dueSoon
        ? daysSince != null && daysSince > 30
            ? AppColors.warning
            : null
        : daysLeft <= 0
            ? AppColors.warning
            : daysLeft <= 3
                ? kCatGold
                : null;
    final subtitleStyle = AppType.secondary(scheme).copyWith(
      fontSize: 12,
      color: muted ? AppTextColor.hint(scheme) : AppTextColor.secondary(scheme),
      fontWeight: FontWeight.w400,
    );
    final subtitleSpan = TextSpan(children: [
      digitAwareAmountSpan(
        extra,
        extraColor == null
            ? subtitleStyle
            : subtitleStyle.copyWith(color: extraColor),
      ),
    ]);
    return FundsAssetRow(
        icon: _accountIcon(item.account.type),
        title: item.account.name,
        subtitle: Text.rich(subtitleSpan),
        amount: MoneyFormat.string(item.balance,
            currencyCode: item.account.currencyCode),
        onTap: onTap,
        muted: muted,
        negative: negative);
  }

  IconData _accountIcon(AccountType type) => switch (type) {
        AccountType.cash => Icons.payments_outlined,
        AccountType.debit => Icons.credit_card,
        AccountType.credit => Icons.credit_score_outlined,
        AccountType.savings => Icons.savings_outlined,
        AccountType.investment => Icons.trending_up,
        AccountType.loan => Icons.request_quote_outlined,
        AccountType.other => Icons.account_balance_wallet_outlined,
      };
}

/// ¥0 账户折叠卡：余额为 0 的账户不再散在各分组里，统一收进这里（默认收起）。
class ZeroBalanceAccountsCard extends StatelessWidget {
  final List<FundsAccountBalance> items;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<AccountEntity> onTap;

  const ZeroBalanceAccountsCard({
    super.key,
    required this.items,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: appCardDecoration(scheme),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const Key('zero-balance-accounts-toggle'),
            onTap: onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              child: Row(
                children: [
                  Text(
                    '已清零账户 (${items.length})',
                    style: AppType.rowTitle(scheme),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppTextColor.secondary(scheme),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            for (int i = 0; i < items.length; i++) ...[
              appCardDivider(scheme),
              FundsAccountBalanceTile(
                item: items[i],
                onTap: () => onTap(items[i].account),
              ),
            ],
        ],
      ),
    );
  }
}

/// 资金页底部入口：当前项目视图下有归档账户/权益时显示，点开切到归档视图。
/// 「借贷往来」入口行（A 批 A2）：有借出/借入数据才显示，
/// 与「已归档 N 项 ›」入口同款轻量行语言。
class LendingEntryRow extends StatelessWidget {
  final VoidCallback onTap;

  const LendingEntryRow({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: const Key('lending-entry'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text('借贷往来 ›', style: AppType.secondary(scheme)),
        ),
      ),
    );
  }
}

class FundsArchiveEntryRow extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const FundsArchiveEntryRow(
      {super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text('已归档 $count 项 ›', style: AppType.secondary(scheme)),
        ),
      ),
    );
  }
}

/// 归档视图顶部返回条，点回切回当前项目视图。
class FundsArchiveBackRow extends StatelessWidget {
  final VoidCallback onTap;

  const FundsArchiveBackRow({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('‹ 返回当前项目', style: AppType.secondary(scheme)),
      ),
    );
  }
}

/// A5：余额口径升级入口横幅。有待迁移的负债账户时显示在资金页顶部。
class LiabilityMigrationBannerRow extends StatelessWidget {
  final VoidCallback onTap;

  const LiabilityMigrationBannerRow({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(Icons.upgrade_rounded,
                size: 18, color: scheme.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '负债账户余额口径可升级',
                style: AppType.secondary(scheme).copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: scheme.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}
