import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:provider/provider.dart';

import '../../core/ai/bill_categorizer.dart';
import '../../core/budget/budget_window_resolver.dart';
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
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/budget_progress.dart';
import '../../widgets/glass.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/monthly_pace_card.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import 'category_txns_view.dart';
import '../../widgets/app_page_route.dart';

/// 图表 Y 轴的「漂亮步长」：把最大值凑成 100/200/500/1000/2000/5000… 这类整齐刻度。
double _niceStep(double maxV) {
  if (maxV <= 0) return 1;
  final rough = maxV / 3; // 目标 ~3 条网格线
  final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final norm = rough / mag;
  final step = norm <= 1 ? 1.0 : (norm <= 2 ? 2.0 : (norm <= 5 ? 5.0 : 10.0));
  return step * mag;
}

/// 图表左侧金额刻度（¥/万，隐藏 0），全统计页统一走它。
AxisTitles _moneyLeftTitles(ColorScheme scheme, double step) {
  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 40,
      interval: step,
      getTitlesWidget: (v, meta) {
        if (v < step * 0.5) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(MoneyFormat.axisLabel(v),
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
        );
      },
    ),
  );
}

/// 点分类下钻：进「该分类在本区间的明细」页。
void _drillToCategory(
  BuildContext context,
  String name,
  DateTime start,
  DateTime end, {
  Set<String>? categoryNames,
}) {
  Navigator.push(
    context,
    AppPageRoute<void>(
      builder: (_) => CategoryTxnsView(
        categoryName: name,
        categoryNames: categoryNames,
        start: start,
        end: end,
      ),
    ),
  );
}

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

  @override
  void initState() {
    super.initState();
    // 记住上次「自定义」区间：再次进入不用重选。
    final saved = context.read<AppRepository>().statCustomRange;
    if (saved != null) {
      _customRange = DateTimeRange(start: saved.$1, end: saved.$2);
    }
  }

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  // 月/周/年 改用滚轮选择（点期间文案的 ⌄ 打开，替代左右翻箭头）。
  Future<void> _pickMonth() async {
    final picked = await showAppMonthPicker(context,
        initial: _displayedMonth, last: DateTime.now());
    if (picked != null && mounted) {
      setState(() => _displayedMonth = DateTime(picked.year, picked.month));
    }
  }

  Future<void> _pickWeek() async {
    final picked = await showAppWeekPicker(context,
        initialWeekStart: _weekStart, last: DateTime.now());
    if (picked != null && mounted) {
      setState(() => _weekStart = _mondayOf(picked));
    }
  }

  Future<void> _pickYear() async {
    final picked = await showAppYearPicker(context,
        initial: _displayedMonth.year, lastYear: DateTime.now().year);
    if (picked != null && mounted) {
      setState(() => _displayedMonth = DateTime(picked, _displayedMonth.month));
    }
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _displayedMonth.year == now.year &&
        _displayedMonth.month == now.month;
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 进入「自定义」时若还没区间，默认给「本月 1 号 → 今天」，界面上就有两个
  /// 可点的起止日期字段（对齐咔皮），不再是一片空白要先弹窗。
  DateTimeRange get _effectiveRange {
    final now = DateTime.now();
    return _customRange ??
        DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
  }

  Future<void> _applyRange(DateTimeRange r) async {
    setState(() => _customRange = r);
    await context.read<AppRepository>().setStatCustomRange(r.start, r.end);
  }

  /// 点开始日期：选完若晚于结束，把结束顺到同一天。
  Future<void> _pickStart() async {
    final cur = _effectiveRange;
    final picked = await showAppDatePicker(
      context,
      initial: cur.start,
      first: DateTime(2000),
      last: DateTime.now(),
      title: '开始时间',
    );
    if (picked == null || !mounted) return;
    final start = _dayOnly(picked);
    final end = cur.end.isBefore(start) ? start : cur.end;
    await _applyRange(DateTimeRange(start: start, end: end));
  }

  /// 点结束日期：不能早于开始。
  Future<void> _pickEnd() async {
    final cur = _effectiveRange;
    final picked = await showAppDatePicker(
      context,
      initial: cur.end,
      first: cur.start,
      last: DateTime.now(),
      title: '结束时间',
    );
    if (picked == null || !mounted) return;
    await _applyRange(DateTimeRange(start: cur.start, end: _dayOnly(picked)));
  }

  void _onRangeChanged(_StatRange r) {
    Haptics.selection();
    setState(() => _range = r);
    // 首次进自定义、还没区间 → 落一个默认区间并持久化（界面立刻有两个日期字段）。
    if (r == _StatRange.custom && _customRange == null) {
      _applyRange(_effectiveRange);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 暖渐变背景已全局化（MaterialApp builder + 主题透明化），页面不再自铺。
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('统计'),
        centerTitle: true,
        actions: [
          AppCircleButton(
            icon: CupertinoIcons.plus,
            iconSize: 22,
            onPressed: () => _ManagedCards.showCardLibrary(
              context,
              context.read<AppRepository>(),
            ),
          ),
          const SizedBox(width: 8),
          // 账本切换（多账本时统计口径跟着切）
          const _BookChip(),
          const SizedBox(width: 12),
        ],
      ),
      body: Consumer<AppRepository>(
        builder: (context, repo, _) {
          final records = repo.allRecordsRef;
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
          repo: repo,
          weekStart: _weekStart,
          onPick: _pickWeek,
        );
      case _StatRange.month:
        return _MonthlyContent(
          records: records,
          repo: repo,
          displayedMonth: _displayedMonth,
          isCurrentMonth: _isCurrentMonth,
          onPick: _pickMonth,
        );
      case _StatRange.year:
        return _YearlyContent(
          records: records,
          repo: repo,
          year: _displayedMonth.year,
          onPick: _pickYear,
        );
      case _StatRange.custom:
        return _CustomContent(
          records: records,
          repo: repo,
          range: _effectiveRange,
          onPickStart: _pickStart,
          onPickEnd: _pickEnd,
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
  final AppRepository repo;
  final DateTime weekStart;
  final VoidCallback onPick;

  const _WeekContent({
    required this.records,
    required this.repo,
    required this.weekStart,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final s =
        StatisticsEngine.rangeSummary(records, start: weekStart, end: weekEnd);
    final label =
        '${weekStart.month}月${weekStart.day}日 – ${weekEnd.month}月${weekEnd.day}日';

    // 徽章基准=上周同期：本周比到上周同一星期几，历史周全周对全周。
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isCurrentWeek = !today.isBefore(weekStart) && !today.isAfter(weekEnd);
    final prevStart = weekStart.subtract(const Duration(days: 7));
    final prevEnd = isCurrentWeek
        ? prevStart.add(Duration(days: today.difference(weekStart).inDays))
        : prevStart.add(const Duration(days: 6));
    final prevSame =
        StatisticsEngine.rangeSummary(records, start: prevStart, end: prevEnd);

    final header = Column(
      children: [
        _PeriodDropdown(label: label, onTap: onPick),
        const SizedBox(height: 16),
        _TotalsHeader(
          expense: s.totalExpense,
          income: s.totalIncome,
          balance: s.balance,
          periodLabel: isCurrentWeek ? '本周' : '该周',
          prevExpense: prevSame.totalExpense,
          prevIncome: prevSame.totalIncome,
          prevBalance: prevSame.balance,
          series: [
            for (final d in s.dailyTotals)
              (
                '${d.date.month}/${d.date.day}',
                MoneyFormat.toDouble(d.expense).clamp(0.0, double.infinity),
                MoneyFormat.toDouble(d.income).clamp(0.0, double.infinity),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );

    if (s.totalExpense == Decimal.zero && s.totalIncome == Decimal.zero) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          header,
          const _EmptyState(message: '这一周没有记录', sub: '换一周看看吧'),
        ],
      );
    }

    final top5 = _topExpenses(records, weekStart, weekEnd);
    final hasExpense = s.expenseByCategory.isNotEmpty;

    return _ManagedCards(
      repo: repo,
      header: header,
      buildCard: (k) => switch (k) {
        'ring' => !hasExpense
            ? null
            : _RingCard(
                title: '支出构成',
                totalLabel: '本周支出',
                total: s.totalExpense,
                categories: s.expenseByCategory,
                onDrill: (n, {categoryNames}) => _drillToCategory(
                  context,
                  n,
                  weekStart,
                  weekEnd,
                  categoryNames: categoryNames,
                ),
              ),
        'daily' => !hasExpense
            ? null
            : _SectionCard(
                title: '每日支出',
                child: _WeekBars(daily: s.dailyTotals),
              ),
        'ranking' => !hasExpense
            ? null
            : _SectionCard(
                title: '分类排行',
                child: _CategoryRanking(
                    categories: s.expenseByCategory,
                    onDrill: (n) =>
                        _drillToCategory(context, n, weekStart, weekEnd)),
              ),
        'top5' => top5.isEmpty
            ? null
            : _SectionCard(
                title: '单笔支出排行',
                child: _TopTxnList(items: top5),
              ),
        _ => null, // 其余卡是月视图专属
      },
    );
  }
}

/// 任意日期区间内金额最大的 5 笔支出（周/年/自定义视图的单笔排行用）。
List<TransactionRecord> _topExpenses(
    List<TransactionRecord> records, DateTime start, DateTime end) {
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day, 23, 59, 59);
  final list = records
      .where((r) =>
          r.kind == TransactionKind.expense &&
          !r.date.isBefore(s) &&
          !r.date.isAfter(e))
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
  return list.take(5).toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// 月视图：月切换 + 合计 + 环比 + 喵的洞察 + 预算 + 环形首图 + 每日趋势线 + 排行
// ─────────────────────────────────────────────────────────────────────────────

class _MonthlyContent extends StatelessWidget {
  final List<TransactionRecord> records;
  final AppRepository repo;
  final DateTime displayedMonth;
  final bool isCurrentMonth;
  final VoidCallback onPick;

  const _MonthlyContent({
    required this.records,
    required this.repo,
    required this.displayedMonth,
    required this.isCurrentMonth,
    required this.onPick,
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
    final budgetWindow = repo.budgetForCalendarMonth(displayedMonth);

    final topExpenses = records
        .where((r) =>
            r.kind == TransactionKind.expense &&
            r.date.year == displayedMonth.year &&
            r.date.month == displayedMonth.month)
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final top5 = topExpenses.take(5).toList();

    // 徽章基准=上月「同期」：当月比到上月同一天（比全月才诚实——
    // 月初拿 9 天比上月 31 天永远显示大降），历史月才全月对全月。
    final now = DateTime.now();
    final prevMonthDays =
        DateTime(displayedMonth.year, displayedMonth.month, 0).day;
    final prevSameEnd = DateTime(
      prevMonth.year,
      prevMonth.month,
      isCurrentMonth ? now.day.clamp(1, prevMonthDays) : prevMonthDays,
    );
    final prevSame = StatisticsEngine.rangeSummary(
      records,
      start: DateTime(prevMonth.year, prevMonth.month, 1),
      end: prevSameEnd,
    );

    final header = Column(
      children: [
        _PeriodDropdown(
          label: '${displayedMonth.year}年${displayedMonth.month}月',
          onTap: onPick,
        ),
        const SizedBox(height: 16),
        _TotalsHeader(
          expense: summary.totalExpense,
          income: summary.totalIncome,
          balance: summary.balance,
          periodLabel: '${displayedMonth.month}月',
          prevExpense: prevSame.totalExpense,
          prevIncome: prevSame.totalIncome,
          prevBalance: prevSame.balance,
          series: [
            for (final d in summary.dailyTotals)
              (
                '${displayedMonth.month}/${d.day}',
                MoneyFormat.toDouble(d.expense).clamp(0.0, double.infinity),
                MoneyFormat.toDouble(d.income).clamp(0.0, double.infinity),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );

    // 本月完全没数据：给空状态，不进卡片管理。
    if (summary.expenseByCategory.isEmpty &&
        summary.totalIncome == Decimal.zero) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          header,
          const _EmptyState(
            message: '本月还没有记录',
            sub: '记几笔之后这里会出现分析图表',
          ),
        ],
      );
    }

    // ── 卡片管理走全维度共享的 _ManagedCards ──
    return _ManagedCards(
      repo: repo,
      header: header,
      buildCard: (k) => _buildCard(
        context,
        k,
        summary,
        prevSummary,
        top5,
        budgetWindow,
      ),
    );
  }

  Widget? _buildCard(
    BuildContext context,
    String key,
    MonthlySummary summary,
    MonthlySummary prevSummary,
    List<TransactionRecord> top5,
    BudgetWindowResult budgetWindow,
  ) {
    final hasExpense = summary.expenseByCategory.isNotEmpty;
    final mStart = DateTime(displayedMonth.year, displayedMonth.month, 1);
    final mEnd = DateTime(displayedMonth.year, displayedMonth.month + 1, 0);
    void drill(String n) => _drillToCategory(context, n, mStart, mEnd);
    switch (key) {
      case 'insights':
        return _InsightsCard(
          records: records,
          year: displayedMonth.year,
          month: displayedMonth.month,
          monthlyBudget: budgetWindow.plannedAmount,
          isCurrentMonth: isCurrentMonth,
        );
      case 'battery':
        return MonthlyPaceCard(
          records: records,
          summary: summary,
          year: displayedMonth.year,
          month: displayedMonth.month,
          isCurrentMonth: isCurrentMonth,
          onOpenAllExpenseActivity: (categoryNames, start, end) {
            Navigator.push(
              context,
              AppPageRoute<void>(
                builder: (_) => CategoryTxnsView(
                  categoryName: '全部支出活动',
                  categoryNames: categoryNames,
                  start: start,
                  end: end,
                ),
              ),
            );
          },
        );
      case 'budget_ring':
        // 没设预算不占位（引导在预算页，别在统计页塞空环）。
        final planned = budgetWindow.plannedAmount;
        final spent = budgetWindow.spentAmount;
        if (planned == null || planned <= Decimal.zero || spent == null) {
          return null;
        }
        return _BudgetRingCard(
          spent: spent,
          budget: planned,
          isCurrentMonth: isCurrentMonth,
          displayedMonth: displayedMonth,
          excludedForeignCount: budgetWindow.excludedForeignTransactionCount,
        );
      case 'ring':
        if (!hasExpense) return null;
        return _RingCard(
          title: '支出构成',
          totalLabel: '本月支出',
          total: summary.totalExpense,
          categories: summary.expenseByCategory,
          onDrill: (n, {categoryNames}) => _drillToCategory(
            context,
            n,
            mStart,
            mEnd,
            categoryNames: categoryNames,
          ),
        );
      case 'daily':
        if (!hasExpense) return null;
        return _TrendCard(
          title: '每日趋势',
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
          // 上月同期每日（淡色虚线）+ 今天竖线。
          compareExpense: [
            for (final d in prevSummary.dailyTotals)
              MoneyFormat.toDouble(d.expense).clamp(0.0, double.infinity),
          ],
          compareIncome: [
            for (final d in prevSummary.dailyTotals)
              MoneyFormat.toDouble(d.income).clamp(0.0, double.infinity),
          ],
          compareLabel: '上月同期',
          markIndex: isCurrentMonth ? DateTime.now().day - 1 : null,
        );
      case 'ranking':
        if (!hasExpense) return null;
        return _SectionCard(
          title: '分类排行',
          child: _CategoryRanking(
              categories: summary.expenseByCategory, onDrill: drill),
        );
      case 'top5':
        if (top5.isEmpty) return null;
        return _SectionCard(
          title: '单笔支出排行',
          child: _TopTxnList(items: top5),
        );
      case 'heatmap':
        if (!hasExpense) return null;
        return _SectionCard(
          title: '消费热力图',
          child: _CalendarHeatmap(
            dailyTotals: summary.dailyTotals,
            year: displayedMonth.year,
            month: displayedMonth.month,
          ),
        );
      case 'radar':
        if (summary.expenseByCategory.isEmpty) return null;
        return _SectionCard(
          title: '本月 vs 上月',
          child: _CompareBarsH(current: summary, previous: prevSummary),
        );
      case 'stacked':
        return _SectionCard(
          title: '近 12 月收支',
          child: _StackedBars12(records: records, endMonth: displayedMonth),
        );
      case 'sources':
        final sources = _topSpendSources(records, mStart, mEnd);
        if (sources.isEmpty) return null;
        return _SectionCard(
          title: '消费来源',
          child: _SourceBars(items: sources),
        );
    }
    return null;
  }
}

/// 月内支出按「商户/备注归一化」聚合，净额 TOP6（消费地图的替代方案：
/// 回答"钱都花在哪些地方"，数据用现成的账单备注，不需要位置信息）。
List<(String, Decimal)> _topSpendSources(
  List<TransactionRecord> records,
  DateTime start,
  DateTime end,
) {
  final endEx = DateTime(end.year, end.month, end.day + 1);
  final totals = <String, Decimal>{};
  for (final r in records) {
    if (r.kind != TransactionKind.expense) continue;
    if (r.date.isBefore(start) || !r.date.isBefore(endEx)) continue;
    final src = BillCategorizer.normalizeMerchant(r.note).trim();
    final key = src.isEmpty ? '未标注' : src;
    // 退款负数行同 key 相抵，聚合完自然是净额。
    totals[key] = (totals[key] ?? Decimal.zero) + r.amount;
  }
  final list = totals.entries
      .where((e) => e.value > Decimal.zero)
      .map((e) => (e.key, e.value))
      .toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return list.take(6).toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// 全维度通用：可管理卡片列表（长按拖排序 + 图表库开关，周/月/年/自定义共用）
// ─────────────────────────────────────────────────────────────────────────────

class _ManagedCards extends StatelessWidget {
  final AppRepository repo;
  final Widget header;

  /// key → 该维度下这张卡的 Widget；null = 此维度不适用或没数据（跳过但保留位置）。
  final Widget? Function(String key) buildCard;

  const _ManagedCards({
    required this.repo,
    required this.header,
    required this.buildCard,
  });

  /// 卡片注册表：key 用于持久化，别改已有 key。顺序/开关全维度共用一份。
  static const Map<String, String> cardTitles = {
    'battery': '截至今日进度',
    'budget_ring': '预算使用',
    'ring': '支出构成',
    'daily': '趋势图',
    'ranking': '分类排行',
    'top5': '单笔支出排行',
    'sources': '消费来源',
    'insights': '喵的洞察',
    'heatmap': '消费热力图',
    'radar': '本月 vs 上月',
    'stacked': '近 12 月收支',
  };

  /// 只在月视图有意义的卡（图表库里标注出来）。
  static const Set<String> monthOnly = {
    'battery',
    'budget_ring',
    'insights',
    'heatmap',
    'radar',
    'stacked',
    'sources',
  };

  /// 默认可见卡片（其余在图表库里，用户自己加）。
  /// 注意：已保存过卡片配置的老用户不会自动看到新加的卡
  /// （区分不了"没见过"和"手动关了"，宁可让用户自己从图表库开一次）。
  static const List<String> defaultOrder = [
    'battery',
    'budget_ring',
    'ring',
    'daily',
    'ranking',
    'top5',
    'sources',
  ];

  static List<String> visibleKeys(AppRepository repo) {
    final saved = repo.statCardOrder;
    if (!repo.hasStatCardOrderConfig && saved.isEmpty) {
      return List.of(defaultOrder);
    }
    final restored = [
      for (final k in saved)
        if (cardTitles.containsKey(k)) k
    ];
    return restored;
  }

  @override
  Widget build(BuildContext context) {
    final visible = visibleKeys(repo);
    final items = <(String, Widget)>[];
    for (final k in visible) {
      final w = buildCard(k);
      if (w != null) items.add((k, w));
    }

    // .builder 懒加载：只 layout/paint 当前视口内的卡，离屏的 fl_chart 滚到才算，
    // 统计页打开更快、滚动更跟手。items 里的 Widget 是廉价构造，真正贵的图表
    // layout/paint 由 .builder 按需触发。
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      buildDefaultDragHandles: false,
      header: header,
      footer: const SizedBox(height: 8),
      itemCount: items.length,
      onReorderItem: (o, n) {
        final itemKeys = [for (final e in items) e.$1];
        final moved = itemKeys.removeAt(o);
        itemKeys.insert(n, moved);
        Haptics.selection();
        // 新顺序 = 参与排序的卡 + 此维度隐藏的卡（保持原相对顺序放后面）
        repo.setStatCardOrder([
          ...itemKeys,
          ...visible.where((k) => !itemKeys.contains(k)),
        ]);
      },
      itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
        key: ValueKey('stat_card_${items[i].$1}'),
        index: i,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          // 每张图表卡隔离重绘：滚动/拖排序时旁边的 fl_chart 不用跟着重画。
          child: RepaintBoundary(child: items[i].$2),
        ),
      ),
    );
  }

  /// 图表库弹层：开关每张卡（开=追加到底部，关=移除）。全维度同一份配置。
  static void showCardLibrary(BuildContext context, AppRepository repo) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        var localVisible = visibleKeys(repo);
        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SheetHeader(
                    title: '自定义图表',
                    subtitle: '打开想看的图表，长按卡片可拖动排序；带「月」标的只在月视图显示',
                    onClose: () => Navigator.pop(ctx2),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                      child: _ChartLibraryGroup(
                        entries: cardTitles.entries.toList(growable: false),
                        monthOnly: monthOnly,
                        visible: localVisible.toSet(),
                        onChanged: (key, on) {
                          final next = List.of(localVisible);
                          if (on) {
                            if (!next.contains(key)) next.add(key);
                          } else {
                            next.remove(key);
                          }
                          setLocal(() => localVisible = next);
                          repo.setStatCardOrder(next);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 趋势卡：右上角 支出/收入 开关，二选一显示（两条线挤一起看不清）。
class _TrendCard extends StatefulWidget {
  final String title;
  final List<String> xLabels;
  final List<double> expense;
  final List<double> income;
  final List<double>? compareExpense;
  final List<double>? compareIncome;
  final String? compareLabel;
  final int? markIndex;

  const _TrendCard({
    required this.title,
    required this.xLabels,
    required this.expense,
    required this.income,
    this.compareExpense,
    this.compareIncome,
    this.compareLabel,
    this.markIndex,
  });

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  bool _showIncome = false;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: widget.title,
      // 支出/收入 切换挪到标题同一行（不再单独占一行、下压图表）。
      trailing: SizedBox(
        width: 108,
        child: _TrendModeSegment(
          value: _showIncome,
          onChanged: (v) {
            Haptics.selection();
            setState(() => _showIncome = v);
          },
        ),
      ),
      child: _DualLineChart(
        xLabels: widget.xLabels,
        expense: widget.expense,
        income: widget.income,
        showIncome: _showIncome,
        compareExpense: widget.compareExpense,
        compareIncome: widget.compareIncome,
        compareLabel: widget.compareLabel,
        markIndex: widget.markIndex,
      ),
    );
  }
}

class _TrendModeSegment extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TrendModeSegment({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = value ? 1 : 0;
    return Container(
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline(scheme)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemW = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                left: index * itemW,
                top: 0,
                bottom: 0,
                width: itemW,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: [
                  _TrendModeItem(
                    label: '支出',
                    selected: !value,
                    onTap: () => onChanged(false),
                  ),
                  _TrendModeItem(
                    label: '收入',
                    selected: value,
                    onTap: () => onChanged(true),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrendModeItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TrendModeItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: selected
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant.withValues(alpha: 0.82),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartLibraryGroup extends StatelessWidget {
  final List<MapEntry<String, String>> entries;
  final Set<String> monthOnly;
  final Set<String> visible;
  final void Function(String key, bool value) onChanged;

  const _ChartLibraryGroup({
    required this.entries,
    required this.monthOnly,
    required this.visible,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < entries.length; i++)
            _ChartLibraryRow(
              title: monthOnly.contains(entries[i].key)
                  ? '${entries[i].value} · 月'
                  : entries[i].value,
              value: visible.contains(entries[i].key),
              showDivider: i != entries.length - 1,
              onChanged: (v) => onChanged(entries[i].key, v),
            ),
        ],
      ),
    );
  }
}

class _ChartLibraryRow extends StatelessWidget {
  final String title;
  final bool value;
  final bool showDivider;
  final ValueChanged<bool> onChanged;

  const _ChartLibraryRow({
    required this.title,
    required this.value,
    required this.showDivider,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dividerColor = scheme.outlineVariant.withValues(alpha: 0.38);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    fontVariations: const [FontVariation('wght', 400)],
                    color: scheme.onSurface.withValues(alpha: 0.94),
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _ChartLibrarySwitch(
                    value: value,
                    onChanged: onChanged,
                  ),
                ),
              ),
              const SizedBox(width: 11),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 13, right: 13),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: dividerColor.withValues(alpha: 0.58),
            ),
          ),
      ],
    );
  }
}

class _ChartLibrarySwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ChartLibrarySwitch({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const width = 43.2;
    const height = 28.8;
    const trackHeight = 24.0;
    const thumbSize = 20.0;
    const padding = 2.0;
    const activeTrack = Color(0xFF73767D);
    const inactiveTrack = Color(0xFFE8E9EC);
    const inactiveBorder = Color(0xFFD8DADF);
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.selection();
          onChanged(!value);
        },
        child: SizedBox(
          width: width,
          height: height,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              width: width,
              height: trackHeight,
              padding: const EdgeInsets.all(padding),
              decoration: BoxDecoration(
                color: value ? activeTrack : inactiveTrack,
                borderRadius: BorderRadius.circular(999),
                border: value ? null : Border.all(color: inactiveBorder),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 年视图：年切换 + 合计 + 12 月双线趋势 + 环形 + 全年排行
// ─────────────────────────────────────────────────────────────────────────────

class _YearlyContent extends StatelessWidget {
  final List<TransactionRecord> records;
  final AppRepository repo;
  final int year;
  final VoidCallback onPick;

  const _YearlyContent({
    required this.records,
    required this.repo,
    required this.year,
    required this.onPick,
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
    // 去年每月支出/收入（趋势对比线用）。
    final prevYear = StatisticsEngine.yearlySummary(records, year: year - 1);
    final prevExpense = [
      for (final e in prevYear.monthlyExpenses)
        MoneyFormat.toDouble(e).clamp(0.0, double.infinity)
    ];
    final prevIncome = List<double>.filled(12, 0);
    for (final r in records) {
      if (r.kind != TransactionKind.income) continue;
      if (r.date.year != year - 1) continue;
      prevIncome[r.date.month - 1] += MoneyFormat.toDouble(r.amount);
    }
    final markMonth =
        year == DateTime.now().year ? DateTime.now().month - 1 : null;

    // 徽章基准=去年同期：今年比到去年同月同日，历史年全年对全年。
    final nowDate = DateTime.now();
    final isCurrentYear = year == nowDate.year;
    final prevSame = StatisticsEngine.rangeSummary(
      records,
      start: DateTime(year - 1, 1, 1),
      end: isCurrentYear
          ? DateTime(
              year - 1,
              nowDate.month,
              nowDate.day
                  .clamp(1, DateTime(year - 1, nowDate.month + 1, 0).day))
          : DateTime(year - 1, 12, 31),
    );

    final header = Column(
      children: [
        _PeriodDropdown(label: '$year年', onTap: onPick),
        const SizedBox(height: 16),
        _TotalsHeader(
          expense: summary.totalExpense,
          income: summary.totalIncome,
          balance: summary.balance,
          periodLabel: '$year年',
          prevExpense: prevSame.totalExpense,
          prevIncome: prevSame.totalIncome,
          prevBalance: prevSame.balance,
          series: [
            for (var i = 0; i < 12; i++)
              (
                '${i + 1}月',
                MoneyFormat.toDouble(summary.monthlyExpenses[i])
                    .clamp(0.0, double.infinity),
                monthlyIncome[i],
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );

    if (summary.totalExpense == Decimal.zero &&
        summary.totalIncome == Decimal.zero) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          header,
          const _EmptyState(
            message: '今年还没有账目',
            sub: '记几笔之后这里会出现年度报告',
          ),
        ],
      );
    }

    final hasExpense = summary.expenseByCategory.isNotEmpty;
    final top5 =
        _topExpenses(records, DateTime(year, 1, 1), DateTime(year, 12, 31));

    return _ManagedCards(
      repo: repo,
      header: header,
      buildCard: (k) => switch (k) {
        'daily' => _TrendCard(
            title: '全年趋势',
            xLabels: [
              for (var m = 1; m <= 12; m++) m.isOdd ? '$m月' : '',
            ],
            expense: [
              for (final e in summary.monthlyExpenses)
                MoneyFormat.toDouble(e).clamp(0.0, double.infinity),
            ],
            income: monthlyIncome,
            compareExpense: prevExpense,
            compareIncome: prevIncome,
            compareLabel: '去年同期',
            markIndex: markMonth,
          ),
        'ring' => !hasExpense
            ? null
            : _RingCard(
                title: '支出构成',
                totalLabel: '全年支出',
                total: summary.totalExpense,
                categories: summary.expenseByCategory,
                onDrill: (n, {categoryNames}) => _drillToCategory(
                  context,
                  n,
                  DateTime(year, 1, 1),
                  DateTime(year, 12, 31),
                  categoryNames: categoryNames,
                ),
              ),
        'ranking' => !hasExpense
            ? null
            : _SectionCard(
                title: '全年分类排行',
                child: _CategoryRanking(
                  categories: summary.expenseByCategory,
                  onDrill: (n) => _drillToCategory(
                      context, n, DateTime(year, 1, 1), DateTime(year, 12, 31)),
                ),
              ),
        'top5' => top5.isEmpty
            ? null
            : _SectionCard(
                title: '单笔支出排行',
                child: _TopTxnList(items: top5),
              ),
        _ => null,
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 自定义视图：起止日期任选
// ─────────────────────────────────────────────────────────────────────────────

/// 自定义区间里的单个日期字段（起 / 止），点开走全局日历。
class _DateField extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;
  const _DateField({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 咔皮式：纯文字 + 小 ⌄，不加底框（保持我们的日期格式）。
    return PressableScale(
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${date.year}/${date.month}/${date.day}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurface)),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_down,
                size: 14, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _CustomContent extends StatelessWidget {
  final List<TransactionRecord> records;
  final AppRepository repo;
  final DateTimeRange range;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _CustomContent({
    required this.records,
    required this.repo,
    required this.range,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = range;
    final s =
        StatisticsEngine.rangeSummary(records, start: r.start, end: r.end);

    final header = Column(
      children: [
        // 起止两个可点日期字段挨在一起（开始紧贴结束，不再左右撑开）。
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _DateField(date: r.start, onTap: onPickStart),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child:
                  Text('–', style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            _DateField(date: r.end, onTap: onPickEnd),
          ],
        ),
        const SizedBox(height: 16),
        // 自定义区间没有天然同期，不传 prev → 徽章隐藏（与同期虚线规则一致）。
        _TotalsHeader(
          expense: s.totalExpense,
          income: s.totalIncome,
          balance: s.balance,
          periodLabel: '区间',
          series: [
            for (final d in s.dailyTotals)
              (
                '${d.date.month}/${d.date.day}',
                MoneyFormat.toDouble(d.expense).clamp(0.0, double.infinity),
                MoneyFormat.toDouble(d.income).clamp(0.0, double.infinity),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );

    if (s.totalExpense == Decimal.zero && s.totalIncome == Decimal.zero) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          header,
          const _EmptyState(message: '这段时间没有记录', sub: '换个区间试试'),
        ],
      );
    }

    final hasExpense = s.expenseByCategory.isNotEmpty;
    final top5 = _topExpenses(records, r.start, r.end);

    return _ManagedCards(
      repo: repo,
      header: header,
      buildCard: (k) => switch (k) {
        'ring' => !hasExpense
            ? null
            : _RingCard(
                title: '支出构成',
                totalLabel: '期间支出',
                total: s.totalExpense,
                categories: s.expenseByCategory,
                onDrill: (n, {categoryNames}) => _drillToCategory(
                  context,
                  n,
                  r.start,
                  r.end,
                  categoryNames: categoryNames,
                ),
              ),
        // 区间不超过约两个月才画每日线，太长看不清。
        'daily' => !hasExpense || s.dayCount > 62
            ? null
            : _TrendCard(
                title: '每日趋势',
                xLabels: [
                  for (var i = 0; i < s.dailyTotals.length; i++)
                    (i == 0 || i % (s.dayCount > 14 ? 7 : 2) == 0)
                        ? '${s.dailyTotals[i].date.month}/${s.dailyTotals[i].date.day}'
                        : '',
                ],
                expense: [
                  for (final d in s.dailyTotals)
                    MoneyFormat.toDouble(d.expense).clamp(0.0, double.infinity),
                ],
                income: [
                  for (final d in s.dailyTotals)
                    MoneyFormat.toDouble(d.income).clamp(0.0, double.infinity),
                ],
              ),
        'ranking' => !hasExpense
            ? null
            : _SectionCard(
                title: '分类排行',
                child: _CategoryRanking(
                    categories: s.expenseByCategory,
                    onDrill: (n) =>
                        _drillToCategory(context, n, r.start, r.end)),
              ),
        'top5' => top5.isEmpty
            ? null
            : _SectionCard(
                title: '单笔支出排行',
                child: _TopTxnList(items: top5),
              ),
        _ => null,
      },
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
    final lines =
        SpendingInsights.summaryLines(records, year: year, month: month);
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                            fontSize: 13, height: 1.5, color: scheme.onSurface),
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

class _PeriodDropdown extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PeriodDropdown({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: PressableScale(
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w500, fontFamily: 'Nunito'),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_down,
                size: 17, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// 期间合计头（2026-07-09 视觉升级二轮，逐项对齐参考图 iOS Cloudflare 客户端）：
/// 主卡=「总支出」标签+右上无底徽章+大金额+**内嵌支出曲线**（合体，用户拍板）；
/// 收入/结余=两张半宽小卡：大号加粗金额+左下无底徽章+右下迷你曲线。
/// [series] = (标签, 支出, 收入) 逐期序列（月/周/自定义=每日，年=每月），喂曲线用。
/// [prevExpense] 等传「同期基准」；null=无同期可比（自定义视图），徽章整体隐藏。
class _TotalsHeader extends StatelessWidget {
  final Decimal expense;
  final Decimal income;
  final Decimal balance;
  final Decimal? prevExpense;
  final Decimal? prevIncome;
  final Decimal? prevBalance;
  final String periodLabel;
  final List<(String, double, double)> series;

  const _TotalsHeader({
    required this.expense,
    required this.income,
    required this.balance,
    required this.periodLabel,
    required this.series,
    this.prevExpense,
    this.prevIncome,
    this.prevBalance,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 金额统一中性深灰（参考图口径：数字不带彩，彩色只给徽章和迷你曲线）。
    final amountGrey = scheme.onSurface.withValues(alpha: 0.87);

    final card = BoxDecoration(
      color: AppColors.card(scheme),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ],
    );

    final expenseSeries = [for (final s in series) s.$2];
    final incomeSeries = [for (final s in series) s.$3];
    // 结余迷你曲线用累计值（逐日净结余的爬坡线，比单日抖动有意义）。
    final balanceSeries = <double>[];
    var acc = 0.0;
    for (final s in series) {
      acc += s.$3 - s.$2;
      balanceSeries.add(acc);
    }

    return Column(
      children: [
        // 通栏主卡：总支出 + 内嵌支出曲线（参考图同款合体）。
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '总支出 · $periodLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w400,
                          ),
                    ),
                  ),
                  _DeltaBadge(
                    current: expense,
                    prev: prevExpense,
                    goodWhenUp: false,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                MoneyFormat.string(expense),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Nunito',
                  height: 1.15,
                  color: amountGrey,
                ),
              ),
              if (expenseSeries.any((v) => v > 0)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 128,
                  child: _HeaderCurve(
                    values: expenseSeries,
                    labels: [for (final s in series) s.$1],
                    color: scheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MiniTotalCard(
                title: '收入',
                amount: income,
                color: amountGrey,
                prev: prevIncome,
                goodWhenUp: true,
                decoration: card,
                spark: incomeSeries,
                sparkColor: AppColors.income(scheme),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniTotalCard(
                title: '结余',
                amount: balance,
                color: amountGrey,
                prev: prevBalance,
                goodWhenUp: true,
                decoration: card,
                spark: balanceSeries,
                sparkColor: scheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 主卡内嵌支出曲线（简化版）：曲线+渐变填充+右侧淡刻度+稀疏日期，无图例。
class _HeaderCurve extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;

  const _HeaderCurve({
    required this.values,
    required this.labels,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = values.fold<double>(0, (a, b) => a > b ? a : b);
    final step = _niceStep(maxV);
    final maxY = maxV <= 0 ? step : ((maxV / step).floor() + 1) * step;
    final labelEvery = (labels.length / 4).ceil().clamp(1, labels.length);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i])
            ],
            color: color,
            isCurved: true,
            curveSmoothness: 0.4,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.22),
                  color.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: step,
          getDrawingHorizontalLine: (v) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            strokeWidth: 0.8,
            dashArray: const [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          // 参考图刻度在右侧。
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: step,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  v == 0 ? '' : MoneyFormat.axisLabel(v, withSymbol: false),
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'Nunito',
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                // 第一个刻度不显示：开头是几号人人都知道（参考图逻辑）。
                if (i <= 0 || i >= labels.length || i % labelEvery != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'Nunito',
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniTotalCard extends StatelessWidget {
  final String title;
  final Decimal amount;
  final Color color;
  final Decimal? prev;
  final bool goodWhenUp;
  final BoxDecoration decoration;
  final List<double> spark;
  final Color sparkColor;

  const _MiniTotalCard({
    required this.title,
    required this.amount,
    required this.color,
    required this.prev,
    required this.goodWhenUp,
    required this.decoration,
    required this.spark,
    required this.sparkColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
          ),
          const SizedBox(height: 4),
          // 金额加大加粗（对齐参考图小指标卡）。
          Text(
            MoneyFormat.string(amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              fontFamily: 'Nunito',
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          // 左下徽章 + 右下迷你曲线（参考图布局）。
          Row(
            children: [
              _DeltaBadge(
                current: amount,
                prev: prev,
                goodWhenUp: goodWhenUp,
              ),
              const Spacer(),
              if (spark.any((v) => v != 0))
                SizedBox(
                  width: 64,
                  height: 26,
                  child: _Sparkline(values: spark, color: sparkColor),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 迷你趋势线（无轴无网格，参考图小卡右下角那种）。
class _Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;

  const _Sparkline({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    var minV = values.first;
    var maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    if (maxV == minV) maxV = minV + 1;

    return LineChart(
      LineChartData(
        minY: minV,
        maxY: maxV,
        clipData: const FlClipData.all(),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i])
            ],
            color: color,
            isCurved: true,
            curveSmoothness: 0.4,
            barWidth: 1.8,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        ],
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
      ),
    );
  }
}

/// 涨跌徽章：↑/↓ + 同期百分比，无底色纯彩字（参考图同款）。
/// 配色：绿=好事、红=坏事（2026-07-09 用户拍板"更直观"，徽章处破红绿铁律）。
/// 上期无数据/为 0、或变化小于 0.05% 时整体隐藏（不出 ∞%/0% 噪声）。
class _DeltaBadge extends StatelessWidget {
  static const _up = Color(0xFF34A853);
  static const _down = Color(0xFFE5484D);

  final Decimal current;
  final Decimal? prev;
  final bool goodWhenUp;

  const _DeltaBadge({
    required this.current,
    required this.prev,
    required this.goodWhenUp,
  });

  @override
  Widget build(BuildContext context) {
    final base = prev;
    if (base == null || base == Decimal.zero) return const SizedBox.shrink();
    // 结余可能为负：分母取绝对值，方向语义才不翻车。
    final baseVal = MoneyFormat.toDouble(base).abs();
    final pct = (MoneyFormat.toDouble(current) - MoneyFormat.toDouble(base)) /
        baseVal *
        100;
    if (pct.abs() < 0.05) return const SizedBox.shrink();
    final up = pct > 0;
    final good = up == goodWhenUp;
    final pctText = pct.abs() >= 10
        ? pct.abs().toStringAsFixed(0)
        : pct.abs().toStringAsFixed(1);

    return Text(
      '${up ? '↑' : '↓'} $pctText%',
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        fontFamily: 'Nunito',
        color: good ? _up : _down,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  /// 与标题同一行、靠右的部件（如趋势图的 支出/收入 切换）。
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

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
          if (title.isNotEmpty || trailing != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w400),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// 消费来源 TOP 横向条形（视觉升级批⑤，消费地图的替代）：
/// 每行 = 来源名 + 相对最大值的条形 + 净额。条形用猫系色板循环。
class _SourceBars extends StatelessWidget {
  final List<(String, Decimal)> items;

  const _SourceBars({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxVal = MoneyFormat.toDouble(items.first.$2);

    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 10),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    items[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 12,
                      color: AppColors.inputFill(scheme),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: maxVal <= 0
                            ? 0
                            : (MoneyFormat.toDouble(items[i].$2) / maxVal)
                                .clamp(0.04, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _kPieColors[i % _kPieColors.length],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  MoneyFormat.string(items[i].$2),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
      ],
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
// 预算使用环形卡（2026-07-10 用户拍板，参考 iOS Cloudflare 客户端的缓存命中率卡）：
// 左=环形进度（中心百分比），右=大字百分比 + 已用/总额 + 剩余天数。
// ─────────────────────────────────────────────────────────────────────────────

class _BudgetRingCard extends StatelessWidget {
  final Decimal spent;
  final Decimal budget;
  final bool isCurrentMonth;
  final DateTime displayedMonth;
  final int excludedForeignCount;

  const _BudgetRingCard({
    required this.spent,
    required this.budget,
    required this.isCurrentMonth,
    required this.displayedMonth,
    required this.excludedForeignCount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = MoneyFormat.toDouble(spent) / MoneyFormat.toDouble(budget);
    final over = ratio > 1.0;
    final ringColor =
        over ? AppColors.warning : AppColors.budgetHealthy(scheme);
    // 文字与环图用同一个舍入后的值，避免「显示 100% 但环未满」的割裂。
    final displayRatio = (ratio * 100).round() / 100.0;
    final pctText = '${(displayRatio * 100).toInt()}%';
    final lastDay =
        DateTime(displayedMonth.year, displayedMonth.month + 1, 0).day;
    final daysLeft = isCurrentMonth ? lastDay - DateTime.now().day : 0;

    return _SectionCard(
      title: '',
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: BudgetProgressRing(
                    value: displayRatio.clamp(0.0, 1.0),
                    strokeWidth: 9,
                    activeColor: ringColor,
                  ),
                ),
                Text(
                  pctText,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Nunito',
                    color: scheme.onSurface.withValues(alpha: 0.87),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '预算使用',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTextColor.secondary(scheme),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  over ? '超支 ${MoneyFormat.string(spent - budget)}' : pctText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: over ? 22 : 28,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Nunito',
                    color: over
                        ? AppColors.warning
                        : scheme.onSurface.withValues(alpha: 0.87),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '已用 ${MoneyFormat.string(spent)} / ${MoneyFormat.string(budget)}'
                  '${daysLeft > 0 ? ' · 剩 $daysLeft 天' : ''}',
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTextColor.secondary(scheme),
                    fontFamily: 'Nunito',
                  ),
                ),
                if (excludedForeignCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '已排除 $excludedForeignCount 笔其他币种记录',
                    style: AppType.caption(scheme),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 环形图首图：环左（中心=期间支出）+ 图例右（名称/占比/金额），>6 类归「其他」
// ─────────────────────────────────────────────────────────────────────────────

class _RingCard extends StatelessWidget {
  final String title;
  final String totalLabel;
  final Decimal total;
  final List<CategoryTotal> categories;

  /// 点分类（图例）下钻到该分类明细；「更多」会带上被折叠的真实分类集合。
  final void Function(String name, {Set<String>? categoryNames})? onDrill;

  const _RingCard({
    required this.title,
    required this.totalLabel,
    required this.total,
    required this.categories,
    this.onDrill,
  });

  /// 只取净额为正的分类；超过 6 类把尾部归成「更多」。
  /// 不能再硬叫「其他」：如果真实分类里本来就有「其他」，
  /// 图例会出现两个同名项，用户也分不清哪个能下钻。
  List<CategoryTotal> _condensed() {
    final positive =
        categories.where((c) => MoneyFormat.toDouble(c.total) > 0).toList();
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
        name: '更多',
        total: restTotal,
        share: restShare,
        count: restCount,
      ),
    ];
  }

  Set<String> _moreCategoryNames() {
    final positive =
        categories.where((c) => MoneyFormat.toDouble(c.total) > 0).toList();
    if (positive.length <= 6) return const {};
    return positive.skip(5).map((c) => c.name).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _condensed();
    final moreCategoryNames = _moreCategoryNames();
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
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  final isMore = item.name == '更多' &&
                      i == items.length - 1 &&
                      moreCategoryNames.isNotEmpty;
                  final canDrill = onDrill != null;
                  return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: canDrill
                          ? () => onDrill!(
                                item.name,
                                categoryNames:
                                    isMore ? moreCategoryNames : null,
                              )
                          : null,
                      child: Padding(
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
                                    fontWeight: FontWeight.w400,
                                  ),
                            ),
                            if (canDrill) ...[
                              const SizedBox(width: 2),
                              Icon(CupertinoIcons.chevron_forward,
                                  size: 11, color: scheme.onSurfaceVariant),
                            ],
                          ],
                        ),
                      ));
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
    final step = _niceStep(maxVal);

    return SizedBox(
      height: 150,
      child: BarChart(
        BarChartData(
          maxY: maxVal <= 0 ? step : ((maxVal / step).floor() + 1) * step,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                MoneyFormat.axisLabel(rod.toY),
                TextStyle(
                    color: AppColors.expense(scheme),
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          barGroups: List.generate(daily.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: MoneyFormat.toDouble(daily[i].expense)
                      .clamp(0.0, double.infinity),
                  color: AppColors.expense(scheme),
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
            horizontalInterval: step,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant,
              strokeWidth: 0.5,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: _moneyLeftTitles(scheme, step),
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

  /// 二选一显示（用户 0703：支出/收入别挤在一张图里）。
  /// 默认只画支出；[showIncome]=true 时只画收入。
  final bool showIncome;

  /// 上一周期同期数据（月=上月每日、年=去年每月），画成淡色虚线做对比。
  final List<double>? compareExpense;
  final List<double>? compareIncome;
  final String? compareLabel;

  /// "今天"竖虚线的下标（当月/当年才传）。
  final int? markIndex;

  const _DualLineChart({
    required this.xLabels,
    required this.expense,
    required this.income,
    this.showIncome = false,
    this.compareExpense,
    this.compareIncome,
    this.compareLabel,
    this.markIndex,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expColor = AppColors.expense(scheme);
    final incColor = AppColors.income(scheme);
    final data = showIncome ? income : expense;
    final compare = showIncome ? compareIncome : compareExpense;
    final color = showIncome ? incColor : expColor;
    final label = showIncome ? '收入' : '支出';
    final compareText = compareLabel ?? '上期';
    final primaryLabel = compare == null
        ? label
        : compareText.contains('上月')
            ? '本月$label'
            : compareText.contains('去年')
                ? '今年$label'
                : '本期$label';
    final maxV = [...data, if (compare != null) ...compare]
        .fold<double>(0, (a, b) => a > b ? a : b);
    final step = _niceStep(maxV);
    final maxY = maxV <= 0 ? step : ((maxV / step).floor() + 1) * step;

    LineChartBarData bar(List<double> d, Color c) => LineChartBarData(
          spots: [
            for (var i = 0; i < d.length; i++) FlSpot(i.toDouble(), d[i])
          ],
          color: c,
          // 曲线（2026-07-10 用户点名要真圆滑：防过冲参数会把曲线压成直线，
          // 改自由曲线，越界由 minY+clipData 兜住）。
          isCurved: true,
          curveSmoothness: 0.4,
          barWidth: 2.5,
          dotData: FlDotData(
            show: d.length <= 14,
            getDotPainter: (s, p, b, i) =>
                FlDotCirclePainter(radius: 2.5, color: c, strokeWidth: 0),
          ),
          // 线下渐变填充（对齐参考图）：线色 → 透明。
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                c.withValues(alpha: 0.22),
                c.withValues(alpha: 0.02),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _dot(color),
            const SizedBox(width: 4),
            Text(primaryLabel,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (compare != null) ...[
              const SizedBox(width: 11),
              Container(
                  width: 12, height: 2, color: color.withValues(alpha: 0.4)),
              const SizedBox(width: 4),
              Text(compareText,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              clipData: const FlClipData.all(),
              lineBarsData: [
                if (compare != null)
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < compare.length; i++)
                        FlSpot(i.toDouble(), compare[i])
                    ],
                    color: color.withValues(alpha: 0.4),
                    isCurved: true,
                    curveSmoothness: 0.4,
                    barWidth: 1.6,
                    dashArray: const [4, 3],
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                bar(data, color),
              ],
              extraLinesData: ExtraLinesData(verticalLines: [
                if (markIndex != null)
                  VerticalLine(
                    x: markIndex!.toDouble(),
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    strokeWidth: 1,
                    dashArray: const [3, 3],
                  ),
              ]),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: step,
                // 淡虚线网格（对齐参考图质感）。
                getDrawingHorizontalLine: (v) => FlLine(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                  strokeWidth: 0.8,
                  dashArray: const [4, 4],
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: _moneyLeftTitles(scheme, step),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= xLabels.length || xLabels[i].isEmpty) {
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
                getTouchedSpotIndicator: (barData, indicators) {
                  final isCompare = barData.dashArray != null;
                  return indicators
                      .map(
                        (_) => TouchedSpotIndicatorData(
                          FlLine(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: isCompare ? 0.06 : 0.16,
                            ),
                            strokeWidth: 0.8,
                            dashArray: const [3, 4],
                          ),
                          FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, bar, index) =>
                                FlDotCirclePainter(
                              radius: isCompare ? 4 : 6,
                              color: isCompare
                                  ? scheme.onSurfaceVariant
                                      .withValues(alpha: 0.45)
                                  : color,
                              strokeWidth: isCompare ? 1.6 : 2,
                              strokeColor: AppColors.card(scheme),
                            ),
                          ),
                        ),
                      )
                      .toList();
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.card(scheme),
                  tooltipBorder: BorderSide(
                    color: AppColors.hairline(scheme, strength: 1.2),
                  ),
                  tooltipRoundedRadius: 12,
                  tooltipPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  tooltipMargin: 10,
                  maxContentWidth: 190,
                  fitInsideHorizontally: true,
                  getTooltipItems: (spots) => spots.map((s) {
                    final i = s.x.round().clamp(0, data.length - 1).toInt();
                    if (s != spots.first) return null;
                    final current = data[i];
                    final previous = compare != null && i < compare.length
                        ? compare[i]
                        : null;
                    final diff = previous == null ? null : current - previous;
                    final pointLabel = compareText.contains('去年')
                        ? '${i + 1}月'
                        : compareText.contains('上月') || xLabels.length > 20
                            ? '${i + 1}日'
                            : (i < xLabels.length && xLabels[i].isNotEmpty
                                ? xLabels[i]
                                : '第${i + 1}项');
                    return LineTooltipItem(
                      '$pointLabel\n',
                      TextStyle(
                        color: scheme.onSurface,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.left,
                      children: [
                        TextSpan(
                          text:
                              '$primaryLabel  ${MoneyFormat.axisLabel(current)}',
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Nunito',
                          ),
                        ),
                        if (previous != null && diff != null) ...[
                          TextSpan(
                            text:
                                '\n$compareText  ${MoneyFormat.axisLabel(previous)}',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              fontFamily: 'Nunito',
                            ),
                          ),
                          TextSpan(
                            text:
                                '\n较$compareText  ${diff >= 0 ? '+' : '-'}${MoneyFormat.axisLabel(diff.abs())}',
                            style: TextStyle(
                              color:
                                  diff >= 0 ? color : scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Nunito',
                            ),
                          ),
                        ],
                      ],
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
  final void Function(String name)? onDrill;

  const _CategoryRanking({required this.categories, this.onDrill});

  String? _keyForName(String name) {
    for (final s in CategorySeed.all) {
      if (s.nameZh == name) return s.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = categories.take(5).toList();

    return Column(
      children: items.map((item) {
        final displayShare = ((item.share * 100).round()) / 100.0;
        final pct = (displayShare * 100).toInt();
        final key = _keyForName(item.name);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDrill == null ? null : () => onDrill!(item.name),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CatIcon(
                      categoryKey: key ?? '',
                      emoji: key != null ? CategorySeed.emojiOf(key) : '🏷️',
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w400,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${item.count} 笔',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'Nunito',
                          ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      MoneyFormat.string(item.total),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            fontFamily: 'Nunito',
                          ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '$pct%',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w400,
                              fontFamily: 'Nunito',
                            ),
                      ),
                    ),
                    if (onDrill != null) ...[
                      const SizedBox(width: 3),
                      Icon(
                        CupertinoIcons.chevron_forward,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: displayShare.clamp(0.0, 1.0),
                    minHeight: 5,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.66),
                    backgroundColor:
                        scheme.outlineVariant.withValues(alpha: 0.48),
                  ),
                ),
              ],
            ),
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
        final label = r.note.trim().isNotEmpty ? r.note.trim() : r.categoryName;
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
                        color:
                            i < 3 ? scheme.secondary : scheme.onSurfaceVariant,
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

// ─────────────────────────────────────────────────────────────────────────────
// 图表库新卡（批7）：日历热力图 / 本月vs上月分组柱 / 结构雷达 / 近12月堆叠柱
// ─────────────────────────────────────────────────────────────────────────────

/// 消费日历热力图：颜色越深花得越多（GitHub 提交热力图的记账版）。
class _CalendarHeatmap extends StatelessWidget {
  final List<DailyTotal> dailyTotals;
  final int year;
  final int month;

  const _CalendarHeatmap({
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
    // 周一开头的偏移空格。
    final leading = DateTime(year, month, 1).weekday - 1;
    const names = ['一', '二', '三', '四', '五', '六', '日'];

    return Column(
      children: [
        Row(
          children: [
            for (final n in names)
              Expanded(
                child: Center(
                  child: Text(n,
                      style: TextStyle(
                          fontSize: 10, color: scheme.onSurfaceVariant)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (final d in dailyTotals)
              Builder(builder: (cellCtx) {
                final v = MoneyFormat.toDouble(d.expense);
                final t = maxVal <= 0 ? 0.0 : (v / maxVal).clamp(0.0, 1.0);
                final bg = v <= 0
                    ? scheme.outlineVariant.withValues(alpha: 0.25)
                    : scheme.primary.withValues(alpha: 0.18 + 0.72 * t);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showAppToast(
                    cellCtx,
                    v <= 0
                        ? '$month月${d.day}日 没花钱'
                        : '$month月${d.day}日 支出 ${MoneyFormat.string(d.expense)}',
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 9,
                        color:
                            t > 0.55 ? Colors.white : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('少',
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            const SizedBox(width: 4),
            for (final a in [0.2, 0.45, 0.7, 0.9]) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: a),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 3),
            ],
            const SizedBox(width: 1),
            Text(maxVal > 0 ? '多 · 单日最高 ${MoneyFormat.axisLabel(maxVal)}' : '多',
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

/// 消费结构雷达：本月 vs 上月的 TOP 分类金额轮廓对比。
/// 本月 vs 上月：TOP 分类横向分组条（替代难读的雷达图）。
/// 每个分类两条横条：本月(深) / 上月(浅)，长度按最大值归一。
class _CompareBarsH extends StatelessWidget {
  final MonthlySummary current;
  final MonthlySummary previous;

  const _CompareBarsH({required this.current, required this.previous});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cats = current.expenseByCategory
        .where((c) => c.total > Decimal.zero)
        .take(6)
        .toList();
    if (cats.isEmpty) {
      return Text('本月还没有支出',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
    }
    double prevOf(CategoryTotal current) {
      final p = previous.expenseByCategory
          .where((c) => c.identity == current.identity)
          .toList();
      return p.isEmpty ? 0 : MoneyFormat.toDouble(p.first.total);
    }

    final curColor = AppColors.expense(scheme);
    final prevColor = scheme.onSurfaceVariant.withValues(alpha: 0.35);
    var maxV = 0.0;
    for (final c in cats) {
      maxV = math.max(maxV, math.max(MoneyFormat.toDouble(c.total), prevOf(c)));
    }
    if (maxV <= 0) maxV = 1;

    Widget bar(Color color, double v) => Container(
          height: 7,
          decoration: BoxDecoration(
            color: scheme.outlineVariant.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (v / maxV).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: curColor, label: '本月'),
            const SizedBox(width: 14),
            _LegendDot(color: prevColor, label: '上月'),
          ],
        ),
        const SizedBox(height: 12),
        for (final c in cats) ...[
          Row(
            children: [
              Expanded(
                child: Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium),
              ),
              Text(MoneyFormat.axisLabel(MoneyFormat.toDouble(c.total)),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFamily: 'Nunito', color: scheme.onSurface)),
            ],
          ),
          const SizedBox(height: 4),
          bar(curColor, MoneyFormat.toDouble(c.total)),
          const SizedBox(height: 3),
          bar(prevColor, prevOf(c)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// 近 12 月收支堆叠柱：柱高=当月收支较大者；深色=花掉的，金色=结余，橙色=超支。
/// 12 次 monthlySummary 计算在 initState/didUpdateWidget 里缓存，
/// records 引用不变（来自 allRecordsRef）+ endMonth 不变时跳过重算。
class _StackedBars12 extends StatefulWidget {
  final List<TransactionRecord> records;
  final DateTime endMonth;

  const _StackedBars12({required this.records, required this.endMonth});

  @override
  State<_StackedBars12> createState() => _StackedBars12State();
}

class _StackedBars12State extends State<_StackedBars12> {
  late List<DateTime> _months;
  late List<double> _exp;
  late List<double> _inc;
  late double _maxV;
  late bool _any;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void didUpdateWidget(_StackedBars12 old) {
    super.didUpdateWidget(old);
    // records 来自 allRecordsRef（稳定引用），只在真正变化时重算
    if (!identical(widget.records, old.records) ||
        widget.endMonth != old.endMonth) {
      _compute();
    }
  }

  void _compute() {
    final months = <DateTime>[];
    for (var i = 11; i >= 0; i--) {
      months.add(
          DateTime(widget.endMonth.year, widget.endMonth.month - i, 1));
    }
    final exp = <double>[];
    final inc = <double>[];
    var maxV = 0.0;
    var any = false;
    for (final m in months) {
      final s = StatisticsEngine.monthlySummary(widget.records,
          year: m.year, month: m.month);
      final e =
          MoneyFormat.toDouble(s.totalExpense).clamp(0.0, double.infinity);
      final iv =
          MoneyFormat.toDouble(s.totalIncome).clamp(0.0, double.infinity);
      exp.add(e);
      inc.add(iv);
      final top = e > iv ? e : iv;
      if (top > maxV) maxV = top;
      if (top > 0) any = true;
    }
    _months = months;
    _exp = exp;
    _inc = inc;
    _maxV = maxV;
    _any = any;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_any) {
      return Text('近 12 个月还没有记录',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
    }

    final spentColor = AppColors.expense(scheme);
    final savedColor = AppColors.income(scheme);
    final step = _niceStep(_maxV);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: spentColor, label: '花掉'),
            const SizedBox(width: 14),
            _LegendDot(color: savedColor, label: '结余'),
            const SizedBox(width: 14),
            const _LegendDot(color: AppColors.warning, label: '超支'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: BarChart(
            BarChartData(
              maxY: ((_maxV / step).floor() + 1) * step,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, rod, ri) {
                    final i = g.x.toInt();
                    return BarTooltipItem(
                      '${_months[i].month}月\n支 ${MoneyFormat.axisLabel(_exp[i])}  '
                      '收 ${MoneyFormat.axisLabel(_inc[i])}',
                      TextStyle(
                          color: scheme.onSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < _months.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: _exp[i] > _inc[i] ? _exp[i] : _inc[i],
                        width: 12,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3)),
                        rodStackItems: [
                          // 花掉的部分（不超过收入的那截）
                          BarChartRodStackItem(
                              0, _exp[i] < _inc[i] ? _exp[i] : _inc[i], spentColor),
                          // 结余（收入 > 支出）
                          if (_inc[i] > _exp[i])
                            BarChartRodStackItem(_exp[i], _inc[i], savedColor),
                          // 超支（支出 > 收入）
                          if (_exp[i] > _inc[i])
                            BarChartRodStackItem(
                                _inc[i], _exp[i], AppColors.warning),
                        ],
                      ),
                    ],
                  ),
              ],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                  strokeWidth: 0.5,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: _moneyLeftTitles(scheme, step),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= _months.length || i.isOdd) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          '${_months[i].month}月',
                          style: TextStyle(
                              fontSize: 9, color: scheme.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 图例小圆点 + 文案。
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
