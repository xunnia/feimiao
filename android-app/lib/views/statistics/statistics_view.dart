import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/budget/budget_engine.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/models/transaction_record.dart';
import '../../core/money_format.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';

/// 统计页：月度 / 年度分段，饼图 + 柱状图 + 分类排行。
class StatisticsView extends StatefulWidget {
  const StatisticsView({super.key});

  @override
  State<StatisticsView> createState() => _StatisticsViewState();
}

class _StatisticsViewState extends State<StatisticsView> {
  bool _isYearly = false;
  // 月度视图当前显示月份
  DateTime _displayedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  void _shiftMonth(int delta) {
    setState(() {
      final shifted = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + delta,
      );
      final now = DateTime.now();
      // 不允许跳到未来月
      if (shifted.isAfter(DateTime(now.year, now.month))) return;
      _displayedMonth = shifted;
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _displayedMonth.year == now.year &&
        _displayedMonth.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统计'), centerTitle: true),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final records = repo.allRecords;
          return Column(
            children: [
              // 月度 / 年度分段切换
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('月度')),
                    ButtonSegment(value: true, label: Text('年度')),
                  ],
                  selected: {_isYearly},
                  onSelectionChanged: (s) =>
                      setState(() => _isYearly = s.first),
                ),
              ),
              Expanded(
                child: _isYearly
                    ? _YearlyContent(
                        records: records,
                        year: _displayedMonth.year,
                      )
                    : _MonthlyContent(
                        records: records,
                        displayedMonth: _displayedMonth,
                        isCurrentMonth: _isCurrentMonth,
                        monthlyBudget: repo.monthlyBudget,
                        onShiftMonth: _shiftMonth,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 月度内容
// ---------------------------------------------------------------------------

class _MonthlyContent extends StatelessWidget {
  final List<TransactionRecord> records;
  final DateTime displayedMonth;
  final bool isCurrentMonth;
  final Decimal? monthlyBudget;
  final void Function(int) onShiftMonth;

  const _MonthlyContent({
    required this.records,
    required this.displayedMonth,
    required this.isCurrentMonth,
    required this.monthlyBudget,
    required this.onShiftMonth,
  });

  @override
  Widget build(BuildContext context) {
    final summary = StatisticsEngine.monthlySummary(
      records,
      year: displayedMonth.year,
      month: displayedMonth.month,
    );
    // 上月汇总（用于环比）
    final prevMonth = DateTime(displayedMonth.year, displayedMonth.month - 1);
    final prevSummary = StatisticsEngine.monthlySummary(
      records,
      year: prevMonth.year,
      month: prevMonth.month,
    );

    // 单笔支出排行：本月支出按金额降序取前 5
    final topExpenses = records
        .where((r) =>
            r.kind == TransactionKind.expense &&
            r.date.year == displayedMonth.year &&
            r.date.month == displayedMonth.month)
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final top5 = topExpenses.take(5).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 月份切换器
        _MonthSwitcher(
          displayedMonth: displayedMonth,
          isCurrentMonth: isCurrentMonth,
          onShift: onShiftMonth,
        ),
        const SizedBox(height: 16),

        // 支出 / 收入 / 结余卡
        _TotalsRow(summary: summary),
        _MoMComparison(current: summary, previous: prevSummary),
        const SizedBox(height: 16),

        // 预算进度（有预算且是当月时）
        if (monthlyBudget != null)
          _BudgetProgressCard(
            monthlyBudget: monthlyBudget!,
            records: records,
            isCurrentMonth: isCurrentMonth,
          ),
        if (monthlyBudget != null) const SizedBox(height: 16),

        // 无支出空状态
        if (summary.expenseByCategory.isEmpty)
          _EmptyState(
            icon: Icons.pie_chart_outline,
            message: '本月还没有支出',
            sub: '记几笔之后这里会出现分析图表',
          )
        else ...[
          // 支出构成饼图
          _SectionCard(
            title: '支出构成',
            child: _ExpensePieChart(categories: summary.expenseByCategory),
          ),
          const SizedBox(height: 16),

          // 每日支出柱状图
          _SectionCard(
            title: '每日支出',
            child: _DailyBarChart(
              dailyTotals: summary.dailyTotals,
              year: displayedMonth.year,
              month: displayedMonth.month,
            ),
          ),
          const SizedBox(height: 16),

          // 分类排行
          _SectionCard(
            title: '分类排行',
            child: _CategoryRanking(
              categories: summary.expenseByCategory,
            ),
          ),
          if (top5.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: '单笔支出排行',
              child: _TopTxnList(items: top5),
            ),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 年度内容
// ---------------------------------------------------------------------------

class _YearlyContent extends StatelessWidget {
  final List<TransactionRecord> records;
  final int year;

  const _YearlyContent({required this.records, required this.year});

  @override
  Widget build(BuildContext context) {
    final summary = StatisticsEngine.yearlySummary(records, year: year);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 年度标题
        Center(
          child: Text(
            '$year 年',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(height: 16),

        // 全年收支卡
        _YearlyTotalsRow(summary: summary),
        const SizedBox(height: 16),

        if (summary.totalExpense == Decimal.zero &&
            summary.totalIncome == Decimal.zero)
          _EmptyState(
            icon: Icons.bar_chart_outlined,
            message: '今年还没有账目',
            sub: '记几笔之后这里会出现年度报告',
          )
        else ...[
          // 12 个月支出柱状图
          _SectionCard(
            title: '每月支出',
            child: _MonthlyBarChart(
                monthlyExpenses: summary.monthlyExpenses, year: year),
          ),
          const SizedBox(height: 16),

          // 全年分类排行
          _SectionCard(
            title: '全年分类排行',
            child: _CategoryRanking(
              categories: summary.expenseByCategory,
              maxItems: 10,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 月份切换器
// ---------------------------------------------------------------------------

class _MonthSwitcher extends StatelessWidget {
  final DateTime displayedMonth;
  final bool isCurrentMonth;
  final void Function(int) onShift;

  const _MonthSwitcher({
    required this.displayedMonth,
    required this.isCurrentMonth,
    required this.onShift,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onShift(-1),
        ),
        Expanded(
          child: Center(
            child: Text(
              '${displayedMonth.year} 年 ${displayedMonth.month} 月',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          // 当前月不能往后跳
          onPressed: isCurrentMonth ? null : () => onShift(1),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 收支结余三卡
// ---------------------------------------------------------------------------

/// 环比：本月支出相对上月的涨跌（上月无支出则不显示）。
class _MoMComparison extends StatelessWidget {
  final MonthlySummary current;
  final MonthlySummary previous;

  const _MoMComparison({required this.current, required this.previous});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prev = previous.totalExpense.toDouble();
    if (prev <= 0) return const SizedBox.shrink();
    final cur = current.totalExpense.toDouble();
    final pct = (cur - prev) / prev * 100;
    final up = pct >= 0;
    final color = up ? AppColors.warning : scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_down,
              size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            '本月支出较上月 ${up ? '+' : '-'}${pct.abs().toStringAsFixed(0)}%',
            style:
                Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final MonthlySummary summary;

  const _TotalsRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balanceColor = summary.balance >= Decimal.zero
        ? AppColors.income(scheme)
        : AppColors.warning;

    return Row(
      children: [
        _TotalCard(
          title: '支出',
          amount: summary.totalExpense,
          color: AppColors.expense(scheme),
        ),
        const SizedBox(width: 8),
        _TotalCard(
          title: '收入',
          amount: summary.totalIncome,
          color: AppColors.income(scheme),
        ),
        const SizedBox(width: 8),
        _TotalCard(
          title: '结余',
          amount: summary.balance,
          color: balanceColor,
        ),
      ],
    );
  }
}

class _YearlyTotalsRow extends StatelessWidget {
  final YearlySummary summary;

  const _YearlyTotalsRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balanceColor = summary.balance >= Decimal.zero
        ? AppColors.income(scheme)
        : AppColors.warning;

    return Row(
      children: [
        _TotalCard(
          title: '全年支出',
          amount: summary.totalExpense,
          color: AppColors.expense(scheme),
        ),
        const SizedBox(width: 8),
        _TotalCard(
          title: '全年收入',
          amount: summary.totalIncome,
          color: AppColors.income(scheme),
        ),
        const SizedBox(width: 8),
        _TotalCard(
          title: '全年结余',
          amount: summary.balance,
          color: balanceColor,
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String title;
  final Decimal amount;
  final Color color;

  const _TotalCard({
    required this.title,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              MoneyFormat.string(amount),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
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
// 预算进度卡
// ---------------------------------------------------------------------------

class _BudgetProgressCard extends StatelessWidget {
  final Decimal monthlyBudget;
  final List<TransactionRecord> records;
  final bool isCurrentMonth;

  const _BudgetProgressCard({
    required this.monthlyBudget,
    required this.records,
    required this.isCurrentMonth,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = BudgetEngine.status(
      monthlyBudget: monthlyBudget,
      records: records,
    );
    final ratio = (MoneyFormat.toDouble(status.spentThisMonth) /
            MoneyFormat.toDouble(monthlyBudget).clamp(0.01, double.infinity))
        .clamp(0.0, 1.0);

    final isOver = status.isOverBudget;
    final progressColor = isOver ? AppColors.warning : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '本月预算',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${MoneyFormat.string(status.spentThisMonth)} / ${MoneyFormat.string(monthlyBudget)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isOver ? AppColors.warning : scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              color: progressColor,
              backgroundColor: scheme.outlineVariant,
            ),
          ),
          if (isCurrentMonth) ...[
            const SizedBox(height: 6),
            Text(
              status.todayAllowance >= Decimal.zero
                  ? '今日可花 ${MoneyFormat.string(status.todayAllowance)} · 本月剩 ${MoneyFormat.string(status.remaining)}'
                  : '今日已超出节奏 ${MoneyFormat.string(-status.todayAllowance)}，缓一缓',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: status.todayAllowance >= Decimal.zero
                        ? scheme.onSurfaceVariant
                        : AppColors.warning,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 分段标题卡片容器
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 饼图：支出构成
// ---------------------------------------------------------------------------

/// 取前 8 分类。颜色用 ColorScheme 的调色板循环。
const _kPieColors = [
  Color(0xFF7D8B9B), // 猫蓝灰
  Color(0xFFF2B23C), // 铜金
  Color(0xFFF4A9B8), // 萌粉
  Color(0xFFFF9F68), // 暖橙
  Color(0xFF8FBF9F), // 薄荷绿
  Color(0xFF9BB7D4), // 浅蓝
  Color(0xFFCBA6C3), // 藕紫
  Color(0xFFF3C44B), // 钱袋金
];

class _ExpensePieChart extends StatelessWidget {
  final List<CategoryTotal> categories;

  const _ExpensePieChart({required this.categories});

  @override
  Widget build(BuildContext context) {
    final items = categories.take(8).toList();

    return SizedBox(
      height: 200,
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sections: List.generate(items.length, (i) {
                  final item = items[i];
                  return PieChartSectionData(
                    value: MoneyFormat.toDouble(item.total),
                    color: _kPieColors[i % _kPieColors.length],
                    radius: 60,
                    title: '',
                    showTitle: false,
                  );
                }),
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 图例
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(items.length, (i) {
              final item = items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _kPieColors[i % _kPieColors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(item.share * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 柱状图：每日支出
// ---------------------------------------------------------------------------

class _DailyBarChart extends StatelessWidget {
  final List<DailyTotal> dailyTotals;
  final int year;
  final int month;

  const _DailyBarChart({
    required this.dailyTotals,
    required this.year,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 只展示有支出的日期（若全月无支出不会进到这里）
    final maxVal = dailyTotals
        .map((d) => MoneyFormat.toDouble(d.expense))
        .fold(0.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 140,
      child: BarChart(
        BarChartData(
          maxY: maxVal * 1.2,
          barGroups: dailyTotals.map((d) {
            return BarChartGroupData(
              x: d.day,
              barRods: [
                BarChartRodData(
                  toY: MoneyFormat.toDouble(d.expense),
                  color: scheme.primary,
                  width: 6,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ],
            );
          }).toList(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant,
              strokeWidth: 0.5,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                interval: 5.0,
                getTitlesWidget: (value, meta) {
                  final day = value.toInt();
                  if (day % 5 != 0 && day != 1) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    '$day',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 柱状图：每月支出（年度）
// ---------------------------------------------------------------------------

class _MonthlyBarChart extends StatelessWidget {
  final List<Decimal> monthlyExpenses;
  final int year;

  const _MonthlyBarChart({required this.monthlyExpenses, required this.year});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxVal = monthlyExpenses
        .map(MoneyFormat.toDouble)
        .fold(0.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 140,
      child: BarChart(
        BarChartData(
          maxY: maxVal * 1.2,
          barGroups: List.generate(12, (i) {
            return BarChartGroupData(
              x: i + 1,
              barRods: [
                BarChartRodData(
                  toY: MoneyFormat.toDouble(monthlyExpenses[i]),
                  color: scheme.primary,
                  width: 14,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            );
          }),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant,
              strokeWidth: 0.5,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}月',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 分类排行列表
// ---------------------------------------------------------------------------

class _CategoryRanking extends StatelessWidget {
  final List<CategoryTotal> categories;
  final int? maxItems;

  const _CategoryRanking({required this.categories, this.maxItems});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items =
        maxItems != null ? categories.take(maxItems!).toList() : categories;

    return Column(
      children: items.map((item) {
        final pct = (item.share * 100).toStringAsFixed(0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${item.count} 笔',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    MoneyFormat.string(item.total),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$pct%',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: item.share.clamp(0.0, 1.0),
                  minHeight: 4,
                  color: scheme.primary,
                  backgroundColor: scheme.outlineVariant,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// 单笔支出排行
// ---------------------------------------------------------------------------

class _TopTxnList extends StatelessWidget {
  final List<TransactionRecord> items;

  const _TopTxnList({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(items.length, (i) {
        final r = items[i];
        final label =
            r.note.trim().isNotEmpty ? r.note.trim() : r.categoryName;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${i + 1}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: i < 3 ? scheme.secondary : scheme.onSurfaceVariant,
                      ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      '${r.categoryName} · ${r.date.month}月${r.date.day}日',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '-${MoneyFormat.string(r.amount)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// 空状态
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String sub;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 56, color: scheme.outlineVariant),
          const SizedBox(height: 16),
          Text(message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
          const SizedBox(height: 6),
          Text(sub,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }
}
