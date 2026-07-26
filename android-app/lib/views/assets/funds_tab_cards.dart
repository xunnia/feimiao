// 资金 Tab 账户列表卡片，从 accounts_view.dart 拆出。
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/settings_ui.dart';
import 'asset_form_kit.dart';

class FundsAccountBalance {
  final AccountEntity account;
  final Decimal balance;
  final String? qualityText;

  const FundsAccountBalance({
    required this.account,
    required this.balance,
    this.qualityText,
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
    final showSubtotal = currencies.length == 1;
    final subtotal = group.items
        .fold<Decimal>(Decimal.zero, (sum, item) => sum + item.balance);
    final subtotalStyle = AppType.secondary(scheme).copyWith(
      color: subtotal < Decimal.zero ? AppColors.warning : null,
    );
    return Container(
      decoration: appCardDecoration(scheme),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 8),
            child: Row(
              children: [
                Text(
                  group.type.label,
                  style: AppType.rowTitle(scheme),
                ),
                const SizedBox(width: 6),
                Text(
                  '${group.items.length} 个账户',
                  style: AppType.caption(scheme),
                ),
                if (showSubtotal) ...[
                  const Spacer(),
                  Text.rich(
                    digitAwareAmountSpan(
                      MoneyFormat.string(
                        subtotal,
                        currencyCode: currencies.single,
                      ),
                      subtotalStyle,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          for (int i = 0; i < group.items.length; i++) ...[
            if (i > 0) appCardDivider(scheme),
            FundsAccountBalanceTile(
              item: group.items[i],
              onTap: () => onTap(group.items[i].account),
            ),
          ],
        ],
      ),
    );
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
    // 副标题减负：最多「类型 + 1 个附加段」，
    // 优先级 = 每月N日还款 > 机构 > 「待确认」 > 「不计入」。
    final extra = profile?.repaymentDay != null
        ? '每月${profile!.repaymentDay}日还款'
        : item.account.institution.isNotEmpty
            ? item.account.institution
            : item.qualityText != null
                ? '待确认'
                : !item.account.includeInNetWorth
                    ? '不计入'
                    : null;
    final subtitleText = [
      item.account.type.label,
      if (extra != null) extra,
    ].join(' · ');
    final subtitleStyle =
        (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: muted ? AppTextColor.hint(scheme) : AppTextColor.secondary(scheme),
      fontWeight: FontWeight.w400,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.iconCircleFill(scheme),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _accountIcon(item.account.type),
                size: 18,
                color: muted
                    ? AppTextColor.hint(scheme)
                    : AppTextColor.secondary(scheme),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: muted
                              ? scheme.onSurface.withValues(alpha: 0.55)
                              : scheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    // Nunito 只套在数字子串上（中文混排拆 TextSpan）。
                    digitAwareAmountSpan(subtitleText, subtitleStyle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 128),
              child: Text(
                MoneyFormat.string(
                  item.balance,
                  currencyCode: item.account.currencyCode,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w500,
                      color: muted
                          ? AppTextColor.hint(scheme)
                          : (negative ? AppColors.warning : scheme.onSurface),
                    ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppTextColor.secondary(scheme),
            ),
          ],
        ),
      ),
    );
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
