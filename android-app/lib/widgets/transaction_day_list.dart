import 'dart:ui' show FontFeature;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/cat_svg_icon.dart';
import '../core/models/category_seed.dart';
import '../core/models/transaction_kind.dart';
import '../core/money_format.dart';
import '../data/app_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../views/transactions/edit_transaction_sheet.dart';
import 'tag_selector.dart';
import 'transaction_actions.dart';

/// 账单列表的公共 UI（主页 + 搜索复用，同类功能同一种设计）：
/// 按天分组的白卡 + 每笔行（图标/标题/备注/标签/金额，附着退款净额、待报销/不计入标）。

class TxSection {
  final DateTime day;
  final List<TransactionEntity> items;
  const TxSection({required this.day, required this.items});
}

/// 把交易按天分组（最新的天在前）。
List<TxSection> groupTxnsByDay(List<TransactionEntity> transactions) {
  final map = <DateTime, List<TransactionEntity>>{};
  for (final t in transactions) {
    final day = DateTime(t.date.year, t.date.month, t.date.day);
    map.putIfAbsent(day, () => []).add(t);
  }
  return map.entries
      .map((e) => TxSection(day: e.key, items: e.value))
      .toList()
    ..sort((a, b) => b.day.compareTo(a.day));
}

/// 按天分组的白色卡片：卡内 = 日期头 + 当天各笔（发丝线分隔）。
class TxDayCard extends StatelessWidget {
  final TxSection section;

  const TxDayCard({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      elevation: 1,
      color: AppColors.card(scheme),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          _TxDaySectionHeader(section: section),
          for (int i = 0; i < section.items.length; i++) ...[
            if (i > 0)
              Container(
                margin: const EdgeInsets.only(left: 66, right: 14),
                height: 0.5,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            TxDismissibleRow(transaction: section.items[i]),
          ],
        ],
      ),
    );
  }
}

class _TxDaySectionHeader extends StatelessWidget {
  final TxSection section;

  const _TxDaySectionHeader({required this.section});

  String _dateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final full =
        '${section.day.month}月${section.day.day}日 周${_weekday(section.day.weekday)}';
    if (section.day == today) return '今天 · $full';
    if (section.day == yesterday) return '昨天 · $full';
    return full;
  }

  String _weekday(int w) =>
      const ['一', '二', '三', '四', '五', '六', '日'][w - 1];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalExpense = section.items
        .where((t) => t.txKind == TransactionKind.expense)
        .fold(Decimal.zero, (s, t) => s + t.amount);
    final totalIncome = section.items
        .where((t) => t.txKind == TransactionKind.income)
        .fold(Decimal.zero, (s, t) => s + t.amount);
    final hasExpense = totalExpense > Decimal.zero;
    final hasIncome = totalIncome > Decimal.zero;

    TextStyle? small() => Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w400,
          color: scheme.onSurfaceVariant,
          fontFamily: 'Nunito',
          // ignore: deprecated_member_use
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Text(
            _dateLabel(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const Spacer(),
          if (hasExpense)
            Text('支 ${MoneyFormat.string(totalExpense).replaceAll('¥', '')}',
                style: small()),
          if (hasExpense && hasIncome) const SizedBox(width: 8),
          if (hasIncome)
            Text('收 ${MoneyFormat.string(totalIncome).replaceAll('¥', '')}',
                style: small()),
        ],
      ),
    );
  }
}

class TxDismissibleRow extends StatelessWidget {
  final TransactionEntity transaction;

  const TxDismissibleRow({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    return TransactionSlidable(
      transaction: transaction,
      child: InkWell(
        onTap: () => showEditTransactionSheet(context, transaction),
        child: TxRow(transaction: transaction),
      ),
    );
  }
}

class TxRow extends StatelessWidget {
  final TransactionEntity transaction;

  const TxRow({super.key, required this.transaction});

  bool get _isTransfer => transaction.txKind == TransactionKind.transfer;

  String get _emoji {
    if (_isTransfer) return '🔁';
    final seed = CategorySeed.all
        .where((s) => s.key == transaction.categoryKey)
        .firstOrNull;
    return seed?.emoji ?? '🏷️';
  }

  String get _title {
    switch (transaction.txKind) {
      case TransactionKind.transfer:
        return '${transaction.accountName} → ${transaction.toAccountName}';
      default:
        final name = transaction.categoryNameZh;
        return name.isNotEmpty ? name : '未分类';
    }
  }

  // 老的独立退款冲账行（负支出）：显示成「+¥x」铜金色。
  bool get _isRefund =>
      transaction.txKind == TransactionKind.expense &&
      transaction.amount < Decimal.zero;

  String get _amountText {
    if (_isRefund) return '+${MoneyFormat.string(transaction.amount.abs())}';
    final text = MoneyFormat.string(transaction.amount);
    switch (transaction.txKind) {
      case TransactionKind.expense:
        return '-$text';
      case TransactionKind.income:
        return '+$text';
      case TransactionKind.transfer:
        return text;
    }
  }

  Color _amountColor(ColorScheme scheme) {
    if (_isRefund) return AppColors.income(scheme);
    switch (transaction.txKind) {
      case TransactionKind.income:
        return AppColors.income(scheme);
      case TransactionKind.expense:
        return scheme.onSurface;
      case TransactionKind.transfer:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final refunded =
        context.read<AppRepository>().refundedAmountOf(transaction.id);
    final hasRefund = refunded > Decimal.zero &&
        transaction.txKind == TransactionKind.expense;
    final net = transaction.amount - refunded;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          CatIcon(
            categoryKey: _isTransfer ? 'transfer' : transaction.categoryKey,
            emoji: _emoji,
            size: 36,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: AppTextColor.primary(scheme),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasRefund) _TxRefundBadge(refunded: refunded),
                    if (transaction.reimbursable) const _TxReimburseBadge(),
                    if (transaction.excluded) const _TxExcludedBadge(),
                  ],
                ),
                if (transaction.note.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    transaction.note,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTextColor.hint(scheme),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                InlineTagChips(tagIds: transaction.tagIds),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (hasRefund) ...[
            Text(
              MoneyFormat.string(transaction.amount),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTextColor.hint(scheme),
                    decoration: TextDecoration.lineThrough,
                    fontFamily: 'Nunito',
                  ),
            ),
            const SizedBox(width: 6),
            Text(
              net <= Decimal.zero
                  ? MoneyFormat.string(net)
                  : '-${MoneyFormat.string(net)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Nunito',
                    // ignore: deprecated_member_use
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ] else
            Text(
              _amountText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _amountColor(scheme),
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Nunito',
                    // ignore: deprecated_member_use
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
        ],
      ),
    );
  }
}

class _TxRefundBadge extends StatelessWidget {
  final Decimal refunded;
  const _TxRefundBadge({required this.refunded});

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.income(Theme.of(context).colorScheme);
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('已退 ${MoneyFormat.string(refunded)}',
          style: TextStyle(
              fontSize: 10,
              height: 1.2,
              color: gold,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _TxReimburseBadge extends StatelessWidget {
  const _TxReimburseBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('待报销',
          style: TextStyle(
              fontSize: 10,
              height: 1.2,
              color: AppColors.warning,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _TxExcludedBadge extends StatelessWidget {
  const _TxExcludedBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('不计入',
          style: TextStyle(
              fontSize: 10,
              height: 1.2,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500)),
    );
  }
}
