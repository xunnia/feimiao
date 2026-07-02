import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:provider/provider.dart';

import '../../core/budget/budget_engine.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/models/transaction_record.dart';
import '../../core/money_format.dart';
import '../../core/statistics/spending_insights.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../data/app_repository.dart';
import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/sliding_segment.dart';
import 'monthly_report_view.dart';

/// 统计页：周 / 月 / 年 / 自定义 四个时间维度（Telegram 胶囊切换），
/// 右上角可切账本；首图=环形图；趋势按维度给对应粒度；全部卡片化。
class StatisticsView extends StatefulWidget {
  const StatisticsView({super.key});

  @override
  State<StatisticsView> createState() => _StatisticsViewState();
}

enum _StatRange { week, month, year, custom }

class _StatisticsViewState extends State<StatisticsView> {
  _StatRange _range = _StatRange.month;
  DateTime _displayedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  late DateTime _weekStart = _mondayOf(DateTime.now());
  DateTimeRange? _customRange;

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

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

  void _shiftWeek(int delta) {
    setState(() {
      final shifted = _weekStart.add(Duration(days: 7 * delta));
      if (shifted.isAfter(DateTime.now())) return;
      _weekStart = shifted;
    });
  }

  void _shiftYear(int delta) {
    setState(() {
      final y = _displayedMonth.year + delta;
      if (y > DateTime.now().year) return;
      _displayedMonth = DateTime(y, _displayedMonth.month);
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _displayedMonth.year == now.year &&
        _displayedMonth.month == now.month;
  }

  bool get _isCurrentWeek =>
      _weekStart == _mondayOf(DateTime.now());

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 29)),
            end: now,
          ),
    );
    if (picked != null && mounted) {
      setState(() => _customRange = picked);
    }
  }

  void _onRangeChanged(_StatRange r) {
    Haptics.selection();
    setState(() => _range = r);
    if (r == _StatRange.custom && _customRange == null) _pickCustomRange();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: '月度报告',
            onPressed: () => Navigator.push<void>(
              context,
              CupertinoPageRoute<void>(
                  builder: (_) => const MonthlyReportView()),
            ),
          ),
          // 账本切换（多账本时统计口径跟着切）
          const _BookChip(),
          const SizedBox(width: 12),
        ],
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final records = repo.allRecords;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SlidingSegment<_StatRange>(
                  items: const [
                    (_StatRange.week, '周'),
                    (_StatRange.month, '月'),
                    (_StatRange.year, '年'),
                    (_StatRange.custom, '自定义'),
                  ],
                  value: _range,
                  onChanged: _onRangeChanged,
                ),
              ),
              Expanded(child: _buildContent(records, repo)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(List<TransactionRecord> records, AppRepository repo) {
    switch (_range) {
      case _StatRange.week:
        return _WeekContent(
          records: records,
          weekStart: _weekStart,
          isCurrentWeek: _isCurrentWeek,
          onShift: _shiftWeek,
        );
      case _StatRange.month:
        return _MonthlyContent(
          records: records,
          displayedMonth: _displayedMonth,
          isCurrentMonth: _isCurrentMonth,
          // 预算期间模型：历史月显示当时生效的预算。
          monthlyBudget: repo.budgetTotalFor(
              _displayedMonth.year, _displayedMonth.month),
          onShiftMonth: _shiftMonth,
        );
      case _StatRange.year:
        return _YearlyContent(
          records: records,
          year: _displayedMonth.year,
          isCurrentYear: _displayedMonth.year == DateTime.now().year,
          onShift: _shiftYear,
        );
      case _StatRange.custom:
        return _CustomContent(
          records: records,
          range: _customRange,
          onPick: _pickCustomRange,
        );
    }
  }
}

/// 右上角账本切换：与首页顶栏账本胶囊同款（同类同设计）。
class _BookChip extends StatelessWidget {
  const _BookChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final book = repo.currentBook;
    if (repo.books.length < 2) return const SizedBox.shrink();

    return Builder(
      builder: (ctx) => PressableScale(
        onPressed: () => showIosMenu(ctx, [
          for (final b in repo.books)
            IosMenuItem(
              label: '${b.icon} ${b.name}',
              icon: b.id == repo.currentBookId
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              onTap: () => repo.switchBook(b.id),
            ),
        ]),
        child: GlassSurface(
          radius: 16,
          blur: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(book?.icon ?? '📒', style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    book?.name ?? '账本',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: scheme.onSurface),
                  ),
                ),
                Icon(CupertinoIcons.chevron_down,
                    size: 12, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 周视图：周切换 + 合计 + 环形 + 7 天柱状 + 分类排行
// ─────────────────────────────────────────────────────────────────────────────

class _WeekContent extends StatelessWidget {
  final List<TransactionRecord> records;
  final DateTime weekStart;
  final bool isCurrentWeek;
  final void Function(int) onShift;

  const _WeekContent({
    required this.records,
    required this.weekStart,
    required this.isCurrentWeek,
    required this.onShift,
  });

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final s = StatisticsEngine.rangeSummary(records,
        start: weekStart, end: weekEnd);
    final label =
        '${weekStart.month}月${weekStart.day}日 – ${weekEnd.month}月${weekEnd.day}日';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ArrowSwitcher(
          label: label,
          onPrev: () => onShift(-1),
          onNext: isCurrentWeek ? null : () => onShift(1),
        ),
        const SizedBox(height: 16),
        _TotalsRow(
          expense: s.totalExpense,
          income: s.totalIncome,
          balance: s.balance,
        ),
        const SizedBox(height: 16),
        if (s.totalExpense == Decimal.zero && s.totalIncome == Decimal.zero)
          const _EmptyState(message: '这一周没有记录', sub: '换一周看看吧')
        else ...[
          _RingCard(
            title: '支出构成',
            totalLabel: '本周支出',
            total: s.totalExpense,
            categories: s.expenseByCategory,
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '每日支出',
            child: _WeekBars(daily: s.dailyTotals),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '分类排行',
            child: _CategoryRanking(categories: s.expenseByCategory),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 月视图：月切换 + 合计 + 环比 + 喵的洞察 + 预算 + 环形首图 + 每日趋势线 + 排行
// ─────────────────────────────────────────────────────────────────────────────

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
        _ArrowSwitcher(
          label: '${displayedMonth.year} 年 ${displayedMonth.month} 月',
          onPrev: () => onShiftMonth(-1),
          onNext: isCurrentMonth ? null : () => onShiftMonth(1),
        ),
        const SizedBox(height: 16),
        _TotalsRow(
          expense: summary.totalExpense,
          income: summary.totalIncome,
          balance: summary.balance,
        ),
        _MoMComparison(current: summary, previous: prevSummary),
        const SizedBox(height: 16),
        _InsightsCard(
          records: records,
          year: displayedMonth.year,
          month: displayedMonth.month,
          monthlyBudget: monthlyBudget,
          isCurrentMonth: isCurrentMonth,
        ),
        if (monthlyBudget != null) ...[
          _BudgetProgressCard(
            monthlyBudget: monthlyBudget!,
            records: records,
            isCurrentMonth: isCurrentMonth,
            monthDate: displayedMonth,
          ),
          const SizedBox(height: 16),
        ],
        if (summary.expenseByCategory.isEmpty)
          const _EmptyState(
            message: '本月还没有支出',
            sub: '记几笔之后这里会出现分析图表',
          )
        else ...[
          _RingCard(
            title: '支出构成',
            totalLabel: '本月支出',
            total: summary.totalExpense,
            categories: summary.expenseByCategory,
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '每日趋势',
            child: _DualLineChart(
              xLabels: [
                for (final d in summary.dailyTotals)
                  (d.day == 1 || d.day % 5 == 0) ? '${d.day}' : '',
              ],
              expense: [
                for (final d in summary.dailyTotals)
                  MoneyFormat.toDouble(d.expense).clamp(0.0, double.infinity),
              ],
              income: [
                for (final d in summary.dailyTotals)
                  MoneyFormat.toDouble(d.income).clamp(0.0, double.infinity),
              ],
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

// ─────────────────────────────────────────────────────────────────────────────
// 年视图：年切换 + 合计 + 12 月双线趋势 + 环形 + 全年排行
// ─────────────────────────────────────────────────────────────────────────────

class _YearlyContent extends StatelessWidget {
  final List<TransactionRecord> records;
  final int year;
  final bool isCurrentYear;
  final void Function(int) onShift;

  const _YearlyContent({
    required this.records,
    required this.year,
    required this.isCurrentYear,
    required this.onShift,
  });

  @override
  Widget build(BuildContext context) {
    final summary = StatisticsEngine.yearlySummary(records, year: year);
    // 12 个月的收入（yearlySummary 只带支出，收入这里现算）。
    final monthlyIncome = List<double>.filled(12, 0);
    for (final r in records) {
      if (r.kind != TransactionKind.income) continue;
      if (r.date.year != year) continue;
      monthlyIncome[r.date.month - 1] += MoneyFormat.toDouble(r.amount);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ArrowSwitcher(
          label: '$year 年',
          onPrev: () => onShift(-1),
          onNext: isCurrentYear ? null : () => onShift(1),
        ),
        const SizedBox(height: 16),
        _TotalsRow(
          expense: summary.totalExpense,
          income: summary.totalIncome,
          balance: summary.balance,
          prefix: '全年',
        ),
        const SizedBox(height: 16),
        if (summary.totalExpense == Decimal.zero &&
            summary.totalIncome == Decimal.zero)
          const _EmptyState(
            message: '今年还没有账目',
            sub: '记几笔之后这里会出现年度报告',
          )
        else ...[
          _SectionCard(
            title: '全年趋势',
            child: _DualLineChart(
              xLabels: [
                for (var m = 1; m <= 12; m++) m.isOdd ? '$m月' : '',
              ],
              expense: [
                for (final e in summary.monthlyExpenses)
                  MoneyFormat.toDouble(e).clamp(0.0, double.infinity),
              ],
              income: monthlyIncome,
            ),
          ),
          const SizedBox(height: 16),
          _RingCard(
            title: '支出构成',
            totalLabel: '全年支出',
            total: summary.totalExpense,
            categories: summary.expenseByCategory,
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

// ─────────────────────────────────────────────────────────────────────────────
// 自定义视图：起止日期任选
// ─────────────────────────────────────────────────────────────────────────────

class _CustomContent extends StatelessWidget {
  final List<TransactionRecord> records;
  final DateTimeRange? range;
  final VoidCallback onPick;

  const _CustomContent({
    required this.records,
    required this.range,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = range;
    if (r == null) {
      return Center(
        child: PressableScale(
          onPressed: onPick,
          child: GlassSurface(
            radius: 18,
            blur: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.date_range_outlined,
                    size: 17, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                const Text('选择起止日期', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    final s = StatisticsEngine.rangeSummary(records, start: r.start, end: r.end);
    final label =
        '${r.start.year}/${r.start.month}/${r.start.day} – ${r.end.year}/${r.end.month}/${r.end.day}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: PressableScale(
            onPressed: onPick,
            child: GlassSurface(
              radius: 16,
              blur: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style:
                          TextStyle(fontSize: 13, color: scheme.onSurface)),
                  const SizedBox(width: 6),
                  Icon(Icons.edit_calendar_outlined,
                      size: 15, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _TotalsRow(
          expense: s.totalExpense,
          income: s.totalIncome,
          balance: s.balance,
        ),
        const SizedBox(height: 16),
        if (s.totalExpense == Decimal.zero && s.totalIncome == Decimal.zero)
          const _EmptyState(message: '这段时间没有记录', sub: '换个区间试试')
        else ...[
          _RingCard(
            title: '支出构成',
            totalLabel: '期间支出',
            total: s.totalExpense,
            categories: s.expenseByCategory,
          ),
          const SizedBox(height: 16),
          // 区间不超过约两个月才画每日线，太长看不清。
          if (s.dayCount <= 62) ...[
            _SectionCard(
              title: '每日趋势',
              child: _DualLineChart(
                xLabels: [
                  for (var i = 0; i < s.dailyTotals.length; i++)
                    (i == 0 || i % (s.dayCount > 14 ? 7 : 2) == 0)
                        ? '${s.dailyTotals[i].date.month}/${s.dailyTotals[i].date.day}'
                        : '',
                ],
                expense: [
                  for (final d in s.dailyTotals)
                    MoneyFormat.toDouble(d.expense)
                        .clamp(0.0, double.infinity),
                ],
                income: [
                  for (final d in s.dailyTotals)
                    MoneyFormat.toDouble(d.income)
                        .clamp(0.0, double.infinity),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          _SectionCard(
            title: '分类排行',
            child: _CategoryRanking(categories: s.expenseByCategory),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 喵的洞察卡：消费摘要 + 画像 + 超支预测（纯本地规则）
// ─────────────────────────────────────────────────────────────────────────────

class _InsightsCard extends StatelessWidget {
  final List<TransactionRecord> records;
  final int year;
  final int month;
  final Decimal? monthlyBudget;
  final bool isCurrentMonth;

  const _InsightsCard({
    required this.records,
    required this.year,
    required this.month,
    required this.monthlyBudget,
    required this.isCurrentMonth,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = SpendingInsights.summaryLines(records, year: year, month: month);
    final profile = SpendingInsights.profile(records, year: year, month: month);
    final forecast = isCurrentMonth
        ? SpendingInsights.forecast(records, monthlyBudget: monthlyBudget)
        : null;

    if (lines.isEmpty && profile == null && forecast == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _SectionCard(
        title: '喵的洞察',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (profile != null) ...[
              Row(
                children: [
                  Text(profile.emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      profile.title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                profile.advice,
                style: TextStyle(
                    fontSize: 13, height: 1.5, color: scheme.onSurfaceVariant),
              ),
              if (lines.isNotEmpty || forecast != null)
                const SizedBox(height: 8),
            ],
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('·  ',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            if (forecast != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  forecast.text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: forecast.overBy > Decimal.zero
                        ? AppColors.warning
                        : scheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 通用小件
// ─────────────────────────────────────────────────────────────────────────────

/// 左右箭头 + 中间期间文案的切换器（周/月/年通用）。
class _ArrowSwitcher extends StatelessWidget {
  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _ArrowSwitcher({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _glassArrow(context, CupertinoIcons.chevron_back, onPrev),
        Expanded(
          child: Center(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w500, fontFamily: 'Nunito'),
            ),
          ),
        ),
        _glassArrow(context, CupertinoIcons.chevron_forward, onNext),
      ],
    );
  }

  Widget _glassArrow(
      BuildContext context, IconData icon, VoidCallback? onTap) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              Haptics.selection();
              onTap();
            },
      child: GlassSurface(
        circle: true,
        blur: 0, // 纯色背景，模糊看不出来，省 GPU
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
  final Decimal expense;
  final Decimal income;
  final Decimal balance;
  final String prefix;

  const _TotalsRow({
    required this.expense,
    required this.income,
    required this.balance,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balanceColor = balance >= Decimal.zero
        ? AppColors.income(scheme)
        : AppColors.warning;

    return Row(
      children: [
        _TotalCard(
          title: '$prefix支出',
          amount: expense,
          color: AppColors.expense(scheme),
        ),
        const SizedBox(width: 8),
        _TotalCard(
          title: '$prefix收入',
          amount: income,
          color: AppColors.income(scheme),
        ),
        const SizedBox(width: 8),
        _TotalCard(
          title: '$prefix结余',
          amount: balance,
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
  final DateTime monthDate;

  const _BudgetProgressCard({
    required this.monthlyBudget,
    required this.records,
    required this.isCurrentMonth,
    required this.monthDate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 历史月按该月最后一天算执行情况；当月按今天。
    final status = BudgetEngine.status(
      monthlyBudget: monthlyBudget,
      records: records,
      on: isCurrentMonth
          ? DateTime.now()
          : DateTime(monthDate.year, monthDate.month + 1, 0),
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

/// 猫系低饱和多色板（从主色/铜金/粉/橙衍生，不用大红大绿）。
const _kPieColors = [
  Color(0xFF7D8B9B),
  Color(0xFFF2B23C),
  Color(0xFFF4A9B8),
  Color(0xFFFF9F68),
  Color(0xFF8FBF9F),
  Color(0xFF9BB7D4),
  Color(0xFFCBA6C3),
];

// ─────────────────────────────────────────────────────────────────────────────
// 环形图首图：环左（中心=期间支出）+ 图例右（名称/占比/金额），>6 类归「其他」
// ─────────────────────────────────────────────────────────────────────────────

class _RingCard extends StatelessWidget {
  final String title;
  final String totalLabel;
  final Decimal total;
  final List<CategoryTotal> categories;

  const _RingCard({
    required this.title,
    required this.totalLabel,
    required this.total,
    required this.categories,
  });

  /// 只取净额为正的分类；超过 6 类把尾部归成「其他」。
  List<CategoryTotal> _condensed() {
    final positive = categories
        .where((c) => MoneyFormat.toDouble(c.total) > 0)
        .toList();
    if (positive.length <= 6) return positive;
    final head = positive.take(5).toList();
    var restTotal = Decimal.zero;
    var restShare = 0.0;
    var restCount = 0;
    for (final c in positive.skip(5)) {
      restTotal += c.total;
      restShare += c.share;
      restCount += c.count;
    }
    return [
      ...head,
      CategoryTotal(
        name: '其他',
        total: restTotal,
        share: restShare,
        count: restCount,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _condensed();
    if (items.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      title: title,
      child: SizedBox(
        height: 190,
        child: Row(
          children: [
            // ── 左：环形图 + 中心合计 ──
            Expanded(
              flex: 5,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: List.generate(items.length, (i) {
                        return PieChartSectionData(
                          value: MoneyFormat.toDouble(items[i].total),
                          color: _kPieColors[i % _kPieColors.length],
                          radius: 22,
                          title: '',
                          showTitle: false,
                        );
                      }),
                      centerSpaceRadius: 56,
                      sectionsSpace: 2,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        totalLabel,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        MoneyFormat.string(total),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Nunito',
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // ── 右：图例（名称 / 占比 / 金额）──
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(items.length, (i) {
                  final item = items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: _kPieColors[i % _kPieColors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        Text(
                          '${(item.share * 100).toStringAsFixed(0)}%',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          MoneyFormat.string(item.total),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                fontFamily: 'Nunito',
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 周 7 天柱状图
// ─────────────────────────────────────────────────────────────────────────────

class _WeekBars extends StatelessWidget {
  final List<DateTotal> daily;

  const _WeekBars({required this.daily});

  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxVal = daily
        .map((d) => MoneyFormat.toDouble(d.expense))
        .fold(0.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 140,
      child: BarChart(
        BarChartData(
          maxY: maxVal <= 0 ? 1 : maxVal * 1.2,
          barGroups: List.generate(daily.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: MoneyFormat.toDouble(daily[i].expense)
                      .clamp(0.0, double.infinity),
                  color: scheme.primary,
                  width: 16,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
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
                  final i = value.toInt();
                  if (i < 0 || i >= _weekdayNames.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    _weekdayNames[i],
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

// ─────────────────────────────────────────────────────────────────────────────
// 通用 支出/收入 双线趋势（月=每日线 / 年=12月线 / 自定义=每日线）
// ─────────────────────────────────────────────────────────────────────────────

class _DualLineChart extends StatelessWidget {
  /// 每个数据点的横轴文案；空字符串 = 该点不显示刻度。
  final List<String> xLabels;
  final List<double> expense;
  final List<double> income;

  const _DualLineChart({
    required this.xLabels,
    required this.expense,
    required this.income,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expColor = AppColors.expense(scheme);
    final incColor = AppColors.income(scheme);
    final maxV =
        [...expense, ...income].fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = maxV <= 0 ? 1.0 : maxV * 1.25;

    LineChartBarData bar(List<double> data, Color c) => LineChartBarData(
          spots: [
            for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i])
          ],
          color: c,
          isCurved: true,
          curveSmoothness: 0.25,
          barWidth: 2.5,
          dotData: FlDotData(
            show: data.length <= 14,
            getDotPainter: (s, p, b, i) =>
                FlDotCirclePainter(radius: 2.5, color: c, strokeWidth: 0),
          ),
          belowBarData: BarAreaData(show: false),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _dot(expColor),
            const SizedBox(width: 4),
            Text('支出',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: 16),
            _dot(incColor),
            const SizedBox(width: 4),
            Text('收入',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              lineBarsData: [bar(expense, expColor), bar(income, incColor)],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 3,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                  strokeWidth: 0.5,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 ||
                          i >= xLabels.length ||
                          xLabels[i].isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(xLabels[i],
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((s) {
                    final label = s.barIndex == 0 ? '支出' : '收入';
                    return LineTooltipItem(
                      '$label ¥${s.y.toStringAsFixed(0)}',
                      TextStyle(
                        color: s.barIndex == 0 ? expColor : incColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dot(Color c) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
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
