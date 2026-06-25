import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoSlidingSegmentedControl, CupertinoIcons;
import 'package:provider/provider.dart';

import '../../core/budget/budget_engine.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/models/transaction_record.dart';
import '../../core/money_format.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../data/app_repository.dart';
import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass.dart';
import '../../widgets/mascot.dart';

/// 统计页：月度 / 年度分段，饼图 + 柱状图 + 分类排行。
class StatisticsView extends StatefulWidget {
  const StatisticsView({super.key});

  @override
  State<StatisticsView> createState() => _StatisticsViewState();
}

class _StatisticsViewState extends State<StatisticsView> {
  bool _isYearly = false;
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Center(
                  child: CupertinoSlidingSegmentedControl<bool>(
                    groupValue: _isYearly,
                    onValueChanged: (v) {
                      if (v != null) setState(() => _isYearly = v);
                    },
                    children: const {
                      false: Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text('月度'),
                      ),
                      true: Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text('年度'),
                      ),
                    },
                  ),
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
    final prevMonth = DateTime(displayedMonth.year, displayedMonth.month - 1);
    final prevSummary = StatisticsEngine.monthlySummary(
      records,
      year: prevMonth.year,
      month: prevMonth.month,
    );

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
        _MonthSwitcher(
          displayedMonth: displayedMonth,
          isCurrentMonth: isCurrentMonth,
          onShift: onShiftMonth,
        ),
        const SizedBox(height: 16),
        _TotalsRow(summary: summary),
        _MoMComparison(current: summary, previous: prevSummary),
        const SizedBox(height: 16),
        if (monthlyBudget != null)
          _BudgetProgressCard(
            monthlyBudget: monthlyBudget!,
            records: records,
            isCurrentMonth: isCurrentMonth,
          ),
        if (monthlyBudget != null) const SizedBox(height: 16),
        if (summary.expenseByCategory.isEmpty)
          _EmptyState(
            message: '本月还没有支出',
            sub: '记几笔之后这里会出现分析图表',
          )
        else ...[
          _SectionCard(
            title: '支出构成',
            child: _ExpensePieChart(categories: summary.expenseByCategory),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '每日支出',
            child: _DailyBarChart(
              dailyTotals: summary.dailyTotals,
              year: displayedMonth.year,
              month: displayedMonth.month,
            ),
          ),
          const SizedBox(height: 16),
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
        Center(
          child: Text(
            '$year 年',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Nunito',
                ),
          ),
        ),
        const SizedBox(height: 16),
        _YearlyTotalsRow(summary: summary),
        const SizedBox(height: 16),
        if (summary.totalExpense == Decimal.zero &&
            summary.totalIncome == Decimal.zero)
          _EmptyState(
            message: '今年还没有账目',
            sub: '记几笔之后这里会出现年度报告',
          )
        else ...[
          _SectionCard(
            title: '每月支出',
            child: _MonthlyBarChart(
                monthlyExpenses: summary.monthlyExpenses, year: year),
          ),
          const SizedBox(height: 16),
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
        _glassArrow(context, CupertinoIcons.chevron_back, () {
          Haptics.selection();
          onShift(-1);
        }),
        Expanded(
          child: Center(
            child: Text(
              '${displayedMonth.year} 年 ${displayedMonth.month} 月',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w500, fontFamily: 'Nunito'),
            ),
          ),
        ),
        _glassArrow(
          context,
          CupertinoIcons.chevron_forward,
          isCurrentMonth
              ? null
              : () {
                  Haptics.selection();
                  onShift(1);
                },
        ),
      ],
    );
  }

  // 玻璃圆形翻月按钮（对齐首页玻璃语言）；禁用态变淡、不可点。
  Widget _glassArrow(
      BuildContext context, IconData icon, VoidCallback? onTap) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassSurface(
        circle: true,
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? scheme.onSurfaceVariant
              : scheme.onSurfaceVariant.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card(scheme),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
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
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Nunito',
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
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
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                '${MoneyFormat.string(status.spentThisMonth)} / ${MoneyFormat.string(monthlyBudget)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isOver ? AppColors.warning : scheme.onSurfaceVariant,
                      fontFamily: 'Nunito',
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 渐变进度条（绿→金→红），与首页预算条统一；超支整条变橙。
          SizedBox(
            height: 7,
            child: LayoutBuilder(
              builder: (ctx, c) {
                final w = c.maxWidth;
                return Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: ratio.clamp(0.0, 1.0),
                        child: Container(
                          width: w,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isOver
                                  ? const [AppColors.warning, AppColors.warning]
                                  : const [
                                      Color(0xFF7FB069),
                                      Color(0xFFF2B23C),
                                      Color(0xFFE0552B),
                                    ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

const _kPieColors = [
  Color(0xFF7D8B9B),
  Color(0xFFF2B23C),
  Color(0xFFF4A9B8),
  Color(0xFFFF9F68),
  Color(0xFF8FBF9F),
  Color(0xFF9BB7D4),
  Color(0xFFCBA6C3),
  Color(0xFFF3C44B),
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

class _CategoryRanking extends StatelessWidget {
  final List<CategoryTotal> categories;
  final int? maxItems;

  const _CategoryRanking({required this.categories, this.maxItems});

  String? _keyForName(String name) {
    for (final s in CategorySeed.all) {
      if (s.nameZh == name) return s.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items =
        maxItems != null ? categories.take(maxItems!).toList() : categories;

    return Column(
      children: items.map((item) {
        final pct = (item.share * 100).toStringAsFixed(0);
        final key = _keyForName(item.name);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CatIcon(
                    categoryKey: key ?? '',
                    emoji: key != null
                        ? CategorySeed.emojiOf(key)
                        : '🏷️',
                    size: 24,
                  ),
                  const SizedBox(width: 8),
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
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Nunito',
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
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Nunito',
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
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Nunito',
                    ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final String sub;

  const _EmptyState({
    required this.message,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Mascot(mood: MascotMood.empty, size: 80, animate: true),
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
