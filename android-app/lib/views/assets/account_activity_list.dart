import 'package:flutter/material.dart';

import '../../core/account/account_activity.dart';
import '../../core/account/account_movement_projection.dart';
import '../../core/budget/budget_window_resolver.dart';
import '../../core/money_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/settings_ui.dart';

class AccountActivityList extends StatelessWidget {
  final List<AccountActivityItem> items;

  const AccountActivityList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionLabel('近期活动'),
        Container(
          decoration: appCardDecoration(scheme),
          clipBehavior: Clip.antiAlias,
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('还没有可归属到这个账户的结算活动',
                      style: AppType.secondary(scheme)),
                )
              : Column(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      if (index > 0) appCardDivider(scheme),
                      _ActivityRow(item: items[index]),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final AccountActivityItem item;

  const _ActivityRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inflow = item.direction == AccountActivityDirection.inflow;
    final date = item.settledAt ?? item.attributionAt;
    final amount = MoneyFormat.string(
      budgetDecimalFromCents(item.amountMinor)!,
      currencyCode: item.currencyCode,
    );
    final signedAmount = '${inflow ? '+' : '-'}$amount';
    final details = <String>[
      _eventLabel(item.eventType),
      if (item.bookName.isNotEmpty) item.bookName,
      if (item.categoryName.isNotEmpty) item.categoryName,
      if (item.isPartial) '时间或账户为历史推定',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.iconCircleFill(scheme),
            ),
            child: Icon(
              inflow ? Icons.call_received : Icons.call_made,
              size: 17,
              color: inflow ? kCatGold : AppTextColor.secondary(scheme),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowTitle(scheme),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_dateText(date)} · ${details.join(' · ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption(scheme),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Semantics(
              label: '${inflow ? '流入' : '流出'} $amount',
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    signedAmount,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w600,
                          color: inflow ? kCatGold : scheme.onSurface,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _eventLabel(TransactionEventType type) => switch (type) {
      TransactionEventType.expense => '支出',
      TransactionEventType.income => '收入',
      TransactionEventType.refund => '退款到账',
      TransactionEventType.reimbursement => '报销到账',
      TransactionEventType.transfer => '转账',
      TransactionEventType.assetPurchase => '购买物品',
      TransactionEventType.assetSale => '出售物品',
      TransactionEventType.receivableRecovery => '权益收回',
      TransactionEventType.principalPayment => '归还本金',
      TransactionEventType.interest => '利息费用',
      TransactionEventType.legacyAdjustment => '历史账户变动',
    };

String _dateText(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
