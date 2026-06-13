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

/// 首页概览：本月收支 + 今日可花 + 最近 5 笔。
/// 数据通过 context.watch<AppRepository>() 实时刷新。
///
/// 注意：HomeView 不再持有 Scaffold；它只渲染可滚动内容，
/// 外层的 Scaffold / AppBar 由 RootShell 负责。
class HomeView extends StatelessWidget {
  /// 打开明细页的回调（由 RootShell 注入）。
  final VoidCallback onShowTransactions;

  const HomeView({super.key, required this.onShowTransactions});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final now = DateTime.now();
    final summary = StatisticsEngine.monthlySummary(
      repo.allRecords,
      year: now.year,
      month: now.month,
    );
    final recentTx = repo.transactions.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        // 本月收支卡片
        _MonthSummaryCard(summary: summary),
        const SizedBox(height: 12),

        // 今日可花横幅（已设预算时显示）
        if (repo.monthlyBudget != null)
          _TodayAllowanceBanner(
            status: BudgetEngine.status(
              monthlyBudget: repo.monthlyBudget!,
              records: repo.allRecords,
            ),
          ),
        if (repo.monthlyBudget != null) const SizedBox(height: 12),

        // 最近 5 笔
        _RecentTransactionsCard(
          transactions: recentTx,
          allEmpty: repo.transactions.isEmpty,
          onShowAll: onShowTransactions,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 本月收支卡片
// ---------------------------------------------------------------------------

class _MonthSummaryCard extends StatelessWidget {
  final MonthlySummary summary;

  const _MonthSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balance = summary.balance;
    final balanceColor = balance < Decimal.zero
        ? AppColors.warning
        : AppColors.income(scheme);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Row(
          children: [
            // 支出
            Expanded(
              child: _SummaryCell(
                label: '支出',
                amount: summary.totalExpense,
                color: scheme.onSurface,
              ),
            ),
            _Divider(),
            // 收入
            Expanded(
              child: _SummaryCell(
                label: '收入',
                amount: summary.totalIncome,
                color: AppColors.income(scheme),
              ),
            ),
            _Divider(),
            // 结余
            Expanded(
              child: _SummaryCell(
                label: '结余',
                amount: balance,
                color: balanceColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final Decimal amount;
  final Color color;

  const _SummaryCell({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          MoneyFormat.string(amount.abs()),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
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

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      width: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

// ---------------------------------------------------------------------------
// 今日可花横幅
// ---------------------------------------------------------------------------

class _TodayAllowanceBanner extends StatelessWidget {
  final BudgetStatus status;

  const _TodayAllowanceBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOver = status.todayAllowance < Decimal.zero;
    final bgColor = isOver
        ? AppColors.warning.withOpacity(0.10)
        : scheme.primaryContainer.withOpacity(0.45);
    final textColor = isOver ? AppColors.warning : AppColors.income(scheme);
    final icon = isOver ? Icons.warning_amber_rounded : Icons.savings_outlined;

    final text = isOver
        ? '今日已超出节奏 ${MoneyFormat.string(-status.todayAllowance)}，缓一缓'
        : '今日可花 ${MoneyFormat.string(status.todayAllowance)} · 本月剩 ${MoneyFormat.string(status.remaining)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 最近 5 笔列表卡片
// ---------------------------------------------------------------------------

class _RecentTransactionsCard extends StatelessWidget {
  final List<TransactionEntity> transactions;
  final bool allEmpty;
  final VoidCallback onShowAll;

  const _RecentTransactionsCard({
    required this.transactions,
    required this.allEmpty,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Text(
                    '最近记录',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                  ),
                  const Spacer(),
                  if (!allEmpty)
                    TextButton(
                      onPressed: onShowAll,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '查看全部',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.income(scheme),
                                ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: AppColors.income(scheme),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // 空状态
            if (allEmpty) _EmptyState(),

            // 交易列表
            if (!allEmpty)
              ...transactions.map(
                (tx) => _TransactionRow(tx: tx),
              ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 40,
            color: scheme.onSurfaceVariant.withOpacity(0.4),
          ),
          const SizedBox(height: 12),
          Text(
            '还没有账目',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant.withOpacity(0.6),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '在下方输入框记第一笔',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant.withOpacity(0.45),
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 单行交易
// ---------------------------------------------------------------------------

class _TransactionRow extends StatelessWidget {
  final TransactionEntity tx;

  const _TransactionRow({required this.tx});

  IconData get _icon {
    final seed = CategorySeed.all.where((s) => s.key == tx.categoryKey).firstOrNull;
    return seed?.icon ?? Icons.label_outline;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = tx.txKind == TransactionKind.income;
    final amountColor = isIncome ? AppColors.income(scheme) : scheme.onSurface;
    final sign = isIncome ? '+' : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 分类图标
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerHighest,
            ),
            child: Icon(_icon, size: 18, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),

          // 分类名 + 备注
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.categoryNameZh.isNotEmpty ? tx.categoryNameZh : '未分类',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (tx.note.isNotEmpty)
                  Text(
                    tx.note,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // 金额
          Text(
            '$sign${MoneyFormat.string(tx.amount)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w600,
                  // ignore: deprecated_member_use
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}
