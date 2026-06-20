import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/budget/budget_engine.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/mascot.dart';
import '../../widgets/tag_selector.dart';
import '../statistics/statistics_view.dart';
import '../settings/budget_setting_view.dart';
import '../transactions/edit_transaction_sheet.dart';

/// 首页：折叠吸顶大卡片（收支+预算）+ 全量按天分组明细列表。
class HomeView extends StatelessWidget {
  final VoidCallback onShowTransactions;

  const HomeView({super.key, required this.onShowTransactions});

  List<_DaySection> _groupByDay(List<TransactionEntity> transactions) {
    final map = <DateTime, List<TransactionEntity>>{};
    for (final t in transactions) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      map.putIfAbsent(day, () => []).add(t);
    }
    return map.entries
        .map((e) => _DaySection(day: e.key, items: e.value))
        .toList()
      ..sort((a, b) => b.day.compareTo(a.day));
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final now = DateTime.now();
    final summary = StatisticsEngine.monthlySummary(
      repo.allRecords,
      year: now.year,
      month: now.month,
    );
    final budgetStatus = repo.monthlyBudget != null
        ? BudgetEngine.status(
            monthlyBudget: repo.monthlyBudget!,
            records: repo.allRecords,
          )
        : null;

    final transactions = repo.transactions;
    final sections = _groupByDay(transactions);

    const double expandedHeight = 256.0;
    const double minExtent = kToolbarHeight;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          automaticallyImplyLeading: false,
          pinned: true,
          expandedHeight: expandedHeight,
          collapsedHeight: minExtent,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: LayoutBuilder(
            builder: (context, constraints) {
              final maxH = constraints.maxHeight;
              final expandedTotal = expandedHeight + MediaQuery.of(context).padding.top;
              final collapsedTotal = minExtent + MediaQuery.of(context).padding.top;
              final t = ((maxH - collapsedTotal) /
                      (expandedTotal - collapsedTotal).clamp(1.0, double.infinity))
                  .clamp(0.0, 1.0);

              return Stack(
                children: [
                  Opacity(
                    opacity: t,
                    child: IgnorePointer(
                      ignoring: t < 0.3,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _ExpandedSummaryCard(
                          now: now,
                          summary: summary,
                          budgetStatus: budgetStatus,
                          budget: repo.monthlyBudget,
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: (1.0 - t * 2).clamp(0.0, 1.0),
                    child: IgnorePointer(
                      ignoring: t > 0.3,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: _CollapsedMiniBar(
                          summary: summary,
                          budgetStatus: budgetStatus,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        if (transactions.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          )
        else ...[
          SliverToBoxAdapter(child: _InsightStrip(summary: summary)),
          for (final s in sections)
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _DayHeaderDelegate(section: s),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _DismissibleRow(
                      transaction: s.items[index],
                      onDelete: () =>
                          repo.deleteTransaction(s.items[index].id),
                    ),
                    childCount: s.items.length,
                  ),
                ),
              ],
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 展开态大卡片
// ---------------------------------------------------------------------------

class _ExpandedSummaryCard extends StatelessWidget {
  final DateTime now;
  final MonthlySummary summary;
  final BudgetStatus? budgetStatus;
  final Decimal? budget;

  const _ExpandedSummaryCard({
    required this.now,
    required this.summary,
    required this.budgetStatus,
    required this.budget,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOverspend = budgetStatus?.isOverBudget ?? false;
    final balance = summary.balance;
    final balanceNegative = balance < Decimal.zero;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        elevation: 1,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const StatisticsView(),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${now.year}年${now.month}月',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const StatisticsView(),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '统计',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right,
                            size: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Mascot(
                    mood: isOverspend
                        ? MascotMood.overspend
                        : MascotMood.idle,
                    size: 44,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              Text(
                '${balanceNegative ? '-' : ''}${MoneyFormat.string(balance.abs())}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: AppWeight.emphasis,
                      color:
                          balanceNegative ? AppColors.warning : scheme.onSurface,
                      // ignore: deprecated_member_use
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '本月结余',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTextColor.hint(scheme),
                    ),
              ),
              const SizedBox(height: AppSpacing.md),

              Row(
                children: [
                  Expanded(
                    child: _SummaryMetric(
                      label: '收入',
                      amount: summary.totalIncome,
                      color: AppColors.income(scheme),
                      up: true,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                    margin:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  ),
                  Expanded(
                    child: _SummaryMetric(
                      label: '支出',
                      amount: summary.totalExpense,
                      color: scheme.onSurface,
                      up: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              _BudgetStrip(
                budgetStatus: budgetStatus,
                budget: budget,
                isOverspend: isOverspend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightStrip extends StatelessWidget {
  final MonthlySummary summary;

  const _InsightStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    if (summary.expenseByCategory.isEmpty) return const SizedBox.shrink();
    final top = summary.expenseByCategory
        .reduce((a, b) => a.total >= b.total ? a : b);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: GestureDetector(
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const StatisticsView()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(Icons.local_fire_department_outlined,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: 6),
              Text(
                '本月最大支出',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTextColor.hint(scheme),
                    ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  top.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: AppWeight.title,
                        color: AppTextColor.primary(scheme),
                      ),
                ),
              ),
              const Spacer(),
              Text(
                '¥${MoneyFormat.string(top.total)} · ${(top.share * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTextColor.secondary(scheme),
                      // ignore: deprecated_member_use
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              Icon(Icons.chevron_right, size: 16, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final Decimal amount;
  final Color color;
  final bool up;

  const _SummaryMetric({
    required this.label,
    required this.amount,
    required this.color,
    required this.up,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTextColor.hint(scheme),
                  ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          MoneyFormat.string(amount),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: AppWeight.title,
                color: color,
                // ignore: deprecated_member_use
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _BudgetStrip extends StatelessWidget {
  final BudgetStatus? budgetStatus;
  final Decimal? budget;
  final bool isOverspend;

  const _BudgetStrip({
    required this.budgetStatus,
    required this.budget,
    required this.isOverspend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (budgetStatus == null || budget == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BudgetSettingView()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '设置本月预算',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final status = budgetStatus!;
    final budgetVal = budget!;
    final color = isOverspend ? AppColors.warning : scheme.primary;
    final ratio = budgetVal > Decimal.zero
        ? (status.spentThisMonth / budgetVal)
            .toDecimal(scaleOnInfinitePrecision: 4)
            .toDouble()
            .clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              '预算',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTextColor.hint(scheme),
                  ),
            ),
            const Spacer(),
            Text(
              isOverspend
                  ? '超出 ${MoneyFormat.string(status.spentThisMonth - budgetVal)}'
                  : '剩余 ${MoneyFormat.string(status.remaining)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: AppWeight.title,
                    // ignore: deprecated_member_use
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '已用 ${MoneyFormat.string(status.spentThisMonth)} / ${MoneyFormat.string(budgetVal)}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTextColor.hint(scheme),
                // ignore: deprecated_member_use
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _CollapsedMiniBar extends StatelessWidget {
  final MonthlySummary summary;
  final BudgetStatus? budgetStatus;

  const _CollapsedMiniBar({
    required this.summary,
    required this.budgetStatus,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balance = summary.balance;
    final balanceNegative = balance < Decimal.zero;
    final balanceColor =
        balanceNegative ? AppColors.warning : scheme.onSurface;

    final budgetPart = budgetStatus != null
        ? (() {
            final b = budgetStatus!;
            final ratio = b.monthlyBudget > Decimal.zero
                ? ((b.spentThisMonth / b.monthlyBudget)
                        .toDecimal(scaleOnInfinitePrecision: 4)
                        .toDouble() *
                    100)
                    .round()
                : 0;
            return ' · 预算 $ratio%';
          })()
        : '';

    return SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '结余 ',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            Text(
              '${balanceNegative ? '-' : ''}¥${MoneyFormat.string(balance.abs())}$budgetPart',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: balanceColor,
                    // ignore: deprecated_member_use
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySection {
  final DateTime day;
  final List<TransactionEntity> items;
  const _DaySection({required this.day, required this.items});
}

class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  final _DaySection section;
  _DayHeaderDelegate({required this.section});

  static const double _height = 44;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _DaySectionHeader(section: section);
  }

  @override
  bool shouldRebuild(covariant _DayHeaderDelegate old) =>
      old.section.day != section.day ||
      old.section.items.length != section.items.length;
}


class _DaySectionHeader extends StatelessWidget {
  final _DaySection section;

  const _DaySectionHeader({required this.section});

  String _dateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (section.day == today) return '今天';
    if (section.day == yesterday) return '昨天';
    return '${section.day.month}月${section.day.day}日 ${_weekday(section.day.weekday)}';
  }

  String _weekday(int w) =>
      const ['一', '二', '三', '四', '五', '六', '日'][w - 1];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final expenseItems =
        section.items.where((t) => t.txKind == TransactionKind.expense);
    final incomeItems =
        section.items.where((t) => t.txKind == TransactionKind.income);

    final totalExpense = expenseItems.fold(
      Decimal.zero,
      (sum, t) => sum + t.amount,
    );
    final totalIncome = incomeItems.fold(
      Decimal.zero,
      (sum, t) => sum + t.amount,
    );

    final hasExpense = totalExpense > Decimal.zero;
    final hasIncome = totalIncome > Decimal.zero;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      color: scheme.surface,
      alignment: Alignment.center,
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
          if (hasExpense) ...[
            Text(
              '支 -${MoneyFormat.string(totalExpense)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    // ignore: deprecated_member_use
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
          if (hasExpense && hasIncome) const SizedBox(width: 8),
          if (hasIncome)
            Text(
              '收 +${MoneyFormat.string(totalIncome)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.income(scheme),
                    // ignore: deprecated_member_use
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
        ],
      ),
    );
  }
}

class _DismissibleRow extends StatelessWidget {
  final TransactionEntity transaction;
  final VoidCallback onDelete;

  const _DismissibleRow({
    required this.transaction,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(transaction.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade400,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除这笔账？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: () => showEditTransactionSheet(context, transaction),
        child: _TransactionRow(transaction: transaction),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final TransactionEntity transaction;

  const _TransactionRow({required this.transaction});

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

  String get _amountText {
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
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          CatIcon(
            categoryKey: _isTransfer ? 'transfer' : transaction.categoryKey,
            emoji: _emoji,
            size: 40,
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: AppWeight.title,
                              color: AppTextColor.primary(scheme),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (transaction.reimbursable) const _ReimburseBadge(),
                  ],
                ),
                if (transaction.note.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    transaction.note,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
          Text(
            _amountText,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _amountColor(scheme),
                  fontWeight: AppWeight.emphasis,
                  // ignore: deprecated_member_use
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

/// 「待报销」小标签。
class _ReimburseBadge extends StatelessWidget {
  const _ReimburseBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '待报销',
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          color: AppColors.warning,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Mascot(mood: MascotMood.empty, size: 72),
        const SizedBox(height: 16),
        Text(
          '还没有记录哦',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          '在下方输入框记第一笔吧',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
        ),
      ],
    );
  }
}
