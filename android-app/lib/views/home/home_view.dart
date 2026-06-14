import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/budget/budget_engine.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/mascot.dart';
import '../statistics/statistics_view.dart';

/// 首页：折叠吸顶大卡片（收支+预算）+ 全量按天分组明细列表。
///
/// 数据通过 context.watch<AppRepository>() 实时刷新。
/// 外层 Scaffold 由 RootShell 负责；HomeView 只渲染 CustomScrollView。
class HomeView extends StatelessWidget {
  /// 打开明细页的回调（由 RootShell 注入，目前内部已展示全量明细，保留接口避免破坏 main.dart）。
  final VoidCallback onShowTransactions;

  const HomeView({super.key, required this.onShowTransactions});

  /// 按天分组，降序排列。
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

    // 展平为 [_DaySection, TransactionEntity, TransactionEntity, ...] 的扁平列表
    final flatItems = <Object>[];
    for (final s in sections) {
      flatItems.add(s);
      flatItems.addAll(s.items);
    }

    const double expandedHeight = 230.0;
    const double minExtent = kToolbarHeight;

    return CustomScrollView(
      slivers: [
        // ── 折叠吸顶大卡片 ──────────────────────────────────────────────────
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
              // t=0 → 折叠；t=1 → 完全展开
              final maxH = constraints.maxHeight;
              final expandedTotal = expandedHeight + MediaQuery.of(context).padding.top;
              final collapsedTotal = minExtent + MediaQuery.of(context).padding.top;
              final t = ((maxH - collapsedTotal) /
                      (expandedTotal - collapsedTotal).clamp(1.0, double.infinity))
                  .clamp(0.0, 1.0);

              return Stack(
                children: [
                  // ── 展开态大卡片 ──
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
                  // ── 折叠态迷你条 ──
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

        // ── 全量交易明细列表 ────────────────────────────────────────────────
        if (transactions.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = flatItems[index];
                if (item is _DaySection) {
                  return _DaySectionHeader(section: item);
                } else if (item is TransactionEntity) {
                  return _DismissibleRow(
                    transaction: item,
                    onDelete: () => repo.deleteTransaction(item.id),
                  );
                }
                return const SizedBox.shrink();
              },
              childCount: flatItems.length,
            ),
          ),
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
              // ── 顶部行：月份 + 统计按钮 + 吉祥物 ──
              Row(
                children: [
                  // 月份点击（暂 SnackBar）
                  GestureDetector(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('切换月份开发中'),
                        duration: const Duration(milliseconds: 1800),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                  // 统计 > chip
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
                  // 吉祥物（右上角）
                  Mascot(
                    mood: isOverspend
                        ? MascotMood.overspend
                        : MascotMood.idle,
                    size: 44,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── 主内容行：左·收支 | 分割线 | 右·预算 ──
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左半·收支
                    Expanded(
                      child: _IncomeExpensePanel(
                        summary: summary,
                        balanceNegative: balanceNegative,
                      ),
                    ),
                    // 竖向分割线
                    Container(
                      width: 1,
                      color: scheme.outlineVariant.withOpacity(0.5),
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    // 右半·预算
                    Expanded(
                      child: _BudgetPanel(
                        budgetStatus: budgetStatus,
                        budget: budget,
                        isOverspend: isOverspend,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 左半：收支面板
// ---------------------------------------------------------------------------

class _IncomeExpensePanel extends StatelessWidget {
  final MonthlySummary summary;
  final bool balanceNegative;

  const _IncomeExpensePanel({
    required this.summary,
    required this.balanceNegative,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balance = summary.balance;
    final balanceColor =
        balanceNegative ? AppColors.warning : scheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主数：本月结余
        Text(
          '${balanceNegative ? '-' : ''}${MoneyFormat.string(balance.abs())}',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: balanceColor,
                // ignore: deprecated_member_use
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          '本月结余',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        // 收入小字
        _MiniAmountRow(
          prefix: '↑收入',
          amount: summary.totalIncome,
          color: AppColors.income(scheme),
        ),
        const SizedBox(height: 4),
        // 支出小字
        _MiniAmountRow(
          prefix: '↓支出',
          amount: summary.totalExpense,
          color: AppColors.expense(scheme).withOpacity(0.75),
        ),
      ],
    );
  }
}

class _MiniAmountRow extends StatelessWidget {
  final String prefix;
  final Decimal amount;
  final Color color;

  const _MiniAmountRow({
    required this.prefix,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          prefix,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
              ),
        ),
        const SizedBox(width: 4),
        Text(
          MoneyFormat.string(amount),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
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

// ---------------------------------------------------------------------------
// 右半：预算环形进度面板
// ---------------------------------------------------------------------------

class _BudgetPanel extends StatelessWidget {
  final BudgetStatus? budgetStatus;
  final Decimal? budget;
  final bool isOverspend;

  const _BudgetPanel({
    required this.budgetStatus,
    required this.budget,
    required this.isOverspend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (budgetStatus == null || budget == null) {
      // 未设预算占位
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.savings_outlined,
            size: 28,
            color: scheme.onSurfaceVariant.withOpacity(0.4),
          ),
          const SizedBox(height: 6),
          Text(
            '未设预算',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withOpacity(0.6),
                ),
          ),
        ],
      );
    }

    final status = budgetStatus!;
    final budgetVal = budget!;
    final progressColor =
        isOverspend ? AppColors.warning : scheme.primary;
    final ratio = budgetVal > Decimal.zero
        ? (status.spentThisMonth / budgetVal)
            .toDecimal(scaleOnInfinitePrecision: 4)
            .toDouble()
            .clamp(0.0, 1.0)
        : 0.0;
    final pct = (ratio * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 环形进度
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: ratio,
                strokeWidth: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
              Text(
                '$pct%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: progressColor,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // 已用 / 预算
        Text(
          '已用 ${MoneyFormat.string(status.spentThisMonth)}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                // ignore: deprecated_member_use
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '预算 ${MoneyFormat.string(budgetVal)}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                // ignore: deprecated_member_use
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        // 剩余
        Text(
          isOverspend
              ? '超出 ${MoneyFormat.string(status.spentThisMonth - budgetVal)}'
              : '剩余 ${MoneyFormat.string(status.remaining)}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: progressColor,
                fontWeight: FontWeight.w600,
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

// ---------------------------------------------------------------------------
// 折叠态迷你条
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// 日期分组表头
// ---------------------------------------------------------------------------

class _DaySection {
  final DateTime day;
  final List<TransactionEntity> items;
  const _DaySection({required this.day, required this.items});
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

    // 当日支出与收入合计（设计：大号加粗分色）
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      color: scheme.surface,
      child: Row(
        children: [
          // 日期标签（次要色，不抢戏）
          Text(
            _dateLabel(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const Spacer(),
          // 支出合计（大号加粗，深色）
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
          // 收入合计（大号加粗，金色）
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

// ---------------------------------------------------------------------------
// 可左滑删除的交易行
// ---------------------------------------------------------------------------

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
      child: _TransactionRow(transaction: transaction),
    );
  }
}

// ---------------------------------------------------------------------------
// 单笔交易行（金额小号中性灰，不抢日期行的戏）
// ---------------------------------------------------------------------------

class _TransactionRow extends StatelessWidget {
  final TransactionEntity transaction;

  const _TransactionRow({required this.transaction});

  IconData get _icon {
    if (transaction.txKind == TransactionKind.transfer) {
      return Icons.swap_horiz;
    }
    final seed = CategorySeed.all
        .where((s) => s.key == transaction.categoryKey)
        .firstOrNull;
    return seed?.icon ?? Icons.label_outline;
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // 分类图标
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerHighest,
            ),
            child: Icon(_icon, size: 18, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          // 标题 + 备注
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (transaction.note.isNotEmpty)
                  Text(
                    transaction.note,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 金额（小号中性灰，不抢戏）
          Text(
            _amountText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  // ignore: deprecated_member_use
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 空状态
// ---------------------------------------------------------------------------

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
                color: scheme.onSurfaceVariant.withOpacity(0.6),
              ),
        ),
      ],
    );
  }
}
