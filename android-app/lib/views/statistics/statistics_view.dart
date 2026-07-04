import 'dart:math' as math;

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
import '../../widgets/app_buttons.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/glass.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/sliding_segment.dart';
import 'category_txns_view.dart';
import 'monthly_report_view.dart';

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
    BuildContext context, String name, DateTime start, DateTime end) {
  Navigator.push(
    context,
    CupertinoPageRoute<void>(
      builder: (_) =>
          CategoryTxnsView(categoryName: name, start: start, end: end),
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
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('统计'),
        centerTitle: true,
        actions: [
          // 月度报告：Claude 同款文件图标（灰圆按钮）。
          AppCircleButton(
            icon: CupertinoIcons.doc_text,
            iconSize: 19,
            onPressed: () => Navigator.push<void>(
              context,
              CupertinoPageRoute<void>(
                  builder: (_) => const MonthlyReportView()),
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
          // 预算期间模型：历史月显示当时生效的预算。
          monthlyBudget: repo.budgetTotalFor(
              _displayedMonth.year, _displayedMonth.month),
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
    final s = StatisticsEngine.rangeSummary(records,
        start: weekStart, end: weekEnd);
    final label =
        '${weekStart.month}月${weekStart.day}日 – ${weekEnd.month}月${weekEnd.day}日';

    final header = Column(
      children: [
        _PeriodDropdown(label: label, onTap: onPick),
        const SizedBox(height: 16),
        _TotalsRow(
          expense: s.totalExpense,
          income: s.totalIncome,
          balance: s.balance,
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
                onDrill: (n) =>
                    _drillToCategory(context, n, weekStart, weekEnd),
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
  final Decimal? monthlyBudget;
  final VoidCallback onPick;

  const _MonthlyContent({
    required this.records,
    required this.repo,
    required this.displayedMonth,
    required this.isCurrentMonth,
    required this.monthlyBudget,
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

    final topExpenses = records
        .where((r) =>
            r.kind == TransactionKind.expense &&
            r.date.year == displayedMonth.year &&
            r.date.month == displayedMonth.month)
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final top5 = topExpenses.take(5).toList();

    final header = Column(
      children: [
        _PeriodDropdown(
          label: '${displayedMonth.year}年${displayedMonth.month}月',
          onTap: onPick,
        ),
        const SizedBox(height: 16),
        _TotalsRow(
          expense: summary.totalExpense,
          income: summary.totalIncome,
          balance: summary.balance,
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
      buildCard: (k) => _buildCard(context, k, summary, prevSummary, top5),
    );
  }

  Widget? _buildCard(
    BuildContext context,
    String key,
    MonthlySummary summary,
    MonthlySummary prevSummary,
    List<TransactionRecord> top5,
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
          monthlyBudget: monthlyBudget,
          isCurrentMonth: isCurrentMonth,
        );
      case 'budget':
        if (monthlyBudget == null) return null;
        return _BudgetProgressCard(
          monthlyBudget: monthlyBudget!,
          records: records,
          isCurrentMonth: isCurrentMonth,
          monthDate: displayedMonth,
        );
      case 'battery':
        return _BudgetBatteryCard(
          dailyTotals: summary.dailyTotals,
          monthlyBudget: monthlyBudget,
          isCurrentMonth: isCurrentMonth,
        );
      case 'budget_cat':
        final budgets = repo.categoryBudgets;
        if (budgets.isEmpty) return null;
        return _SectionCard(
          title: '预算 vs 实际',
          child: _BudgetVsActualCard(
            records: records,
            year: displayedMonth.year,
            month: displayedMonth.month,
            budgets: budgets,
          ),
        );
      case 'ring':
        if (!hasExpense) return null;
        return _RingCard(
          title: '支出构成',
          totalLabel: '本月支出',
          total: summary.totalExpense,
          categories: summary.expenseByCategory,
          onDrill: drill,
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
    }
    return null;
  }

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
    'insights': '喵的洞察',
    'battery': '本月电量',
    'budget': '本月预算',
    'budget_cat': '预算 vs 实际',
    'ring': '支出构成',
    'daily': '趋势图',
    'ranking': '分类排行',
    'top5': '单笔支出排行',
    'heatmap': '消费热力图',
    'radar': '本月 vs 上月',
    'stacked': '近 12 月收支',
  };

  /// 只在月视图有意义的卡（图表库里标注出来）。
  static const Set<String> monthOnly = {
    'insights', 'battery', 'budget', 'budget_cat', 'heatmap', 'radar',
    'stacked',
  };

  /// 默认可见卡片（其余在图表库里，用户自己加）。
  static const List<String> defaultOrder = [
    'insights', 'battery', 'budget', 'budget_cat', 'ring', 'daily',
    'ranking', 'top5',
  ];

  static List<String> visibleKeys(AppRepository repo) {
    final saved = repo.statCardOrder;
    if (saved.isEmpty) return List.of(defaultOrder);
    return [
      for (final k in saved)
        if (cardTitles.containsKey(k)) k
    ];
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
      footer: _CustomizeButton(
        onTap: () => _showCardLibrary(context),
      ),
      itemCount: items.length,
      onReorder: (o, n) {
        if (n > o) n--;
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
  void _showCardLibrary(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            final cur = visibleKeys(repo);
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
                      child: SettingsGroup(
                        children: [
                          for (final e in cardTitles.entries)
                            SettingsRow(
                              title: monthOnly.contains(e.key)
                                  ? '${e.value} · 月'
                                  : e.value,
                              trailing: AppSwitch(
                                value: cur.contains(e.key),
                                onChanged: (on) {
                                  final next = List.of(cur);
                                  if (on) {
                                    next.add(e.key);
                                  } else {
                                    next.remove(e.key);
                                  }
                                  repo.setStatCardOrder(next);
                                  setLocal(() {});
                                },
                              ),
                            ),
                        ],
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
    super.key,
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
        width: 124,
        child: SlidingSegment<bool>(
          items: const [(false, '支出'), (true, '收入')],
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

/// 底部「自定义图表」按钮。
class _CustomizeButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CustomizeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: PressableScale(
        onPressed: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.card(scheme),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline(scheme)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('自定义图表',
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
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

    final header = Column(
      children: [
        _PeriodDropdown(label: '$year年', onTap: onPick),
        const SizedBox(height: 16),
        _TotalsRow(
          expense: summary.totalExpense,
          income: summary.totalIncome,
          balance: summary.balance,
          prefix: '全年',
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
                onDrill: (n) => _drillToCategory(
                    context, n, DateTime(year, 1, 1), DateTime(year, 12, 31)),
              ),
        'ranking' => !hasExpense
            ? null
            : _SectionCard(
                title: '全年分类排行',
                child: _CategoryRanking(
                  categories: summary.expenseByCategory,
                  maxItems: 10,
                  onDrill: (n) => _drillToCategory(context, n,
                      DateTime(year, 1, 1), DateTime(year, 12, 31)),
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
                    fontWeight: FontWeight.w600,
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
    final s = StatisticsEngine.rangeSummary(records, start: r.start, end: r.end);

    final header = Column(
      children: [
        // 起止两个可点日期字段（对齐咔皮：点哪个改哪个，各自弹全局日历）。
        Row(
          children: [
            Expanded(child: _DateField(date: r.start, onTap: onPickStart)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('–',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            Expanded(child: _DateField(date: r.end, onTap: onPickEnd)),
          ],
        ),
        const SizedBox(height: 16),
        _TotalsRow(
          expense: s.totalExpense,
          income: s.totalIncome,
          balance: s.balance,
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
                onDrill: (n) => _drillToCategory(context, n, r.start, r.end),
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
                    MoneyFormat.toDouble(d.expense)
                        .clamp(0.0, double.infinity),
                ],
                income: [
                  for (final d in s.dailyTotals)
                    MoneyFormat.toDouble(d.income)
                        .clamp(0.0, double.infinity),
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

/// 期间文案 + ⌄ 的下拉切换器（周/月/年通用）：点开走滚轮选择，替代左右翻箭头。
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

/// 「本月电量」：预算=满格，累计支出在放电——「预算剩余」随每天花钱往下掉，
/// 掉到 0 以下=透支(橙色)。当月只画到今天。没设预算给引导。
class _BudgetBatteryCard extends StatelessWidget {
  final List<DailyTotal> dailyTotals;
  final Decimal? monthlyBudget;
  final bool isCurrentMonth;

  const _BudgetBatteryCard({
    required this.dailyTotals,
    required this.monthlyBudget,
    required this.isCurrentMonth,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (monthlyBudget == null || monthlyBudget! <= Decimal.zero) {
      return _SectionCard(
        title: '本月电量',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '设了本月预算后，这里用「电量」展示预算消耗：预算是满格，花钱在放电，超支就见红。',
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final budget = MoneyFormat.toDouble(monthlyBudget!);
    final days = dailyTotals.length;
    final remaining = <double>[];
    var cum = 0.0;
    for (final d in dailyTotals) {
      cum += MoneyFormat.toDouble(d.expense).clamp(0.0, double.infinity);
      remaining.add(budget - cum);
    }
    // 当月只画到今天；历史月画满整月。
    final shownEnd = (isCurrentMonth ? DateTime.now().day : days).clamp(1, days);
    final shown = remaining.take(shownEnd).toList();
    final spots = [
      for (var i = 0; i < shown.length; i++) FlSpot(i.toDouble(), shown[i])
    ];
    final minY = shown.fold<double>(budget, (a, b) => b < a ? b : a);
    final over = minY < 0;
    final remainNow = shown.last;

    final step = _niceStep(budget);
    final maxY = ((budget / step).floor() + 1) * step;
    final loY = over ? -(((-minY) / step).floor() + 1) * step : 0.0;
    final lineColor = over ? AppColors.warning : scheme.primary;
    final xInterval = (days / 6).ceilToDouble().clamp(1.0, 999.0);

    // 底部每日「支出/收入」小柱 strip 的数据。
    final expColor = AppColors.expense(scheme);
    final incColor = AppColors.income(scheme);
    final dExp = [
      for (final d in dailyTotals)
        MoneyFormat.toDouble(d.expense).clamp(0.0, double.infinity)
    ];
    final dInc = [
      for (final d in dailyTotals)
        MoneyFormat.toDouble(d.income).clamp(0.0, double.infinity)
    ];
    final stripMax = [...dExp, ...dInc].fold<double>(0.0, (a, b) => a > b ? a : b);
    final stripStep = _niceStep(stripMax);
    final stripMaxY = stripMax <= 0
        ? stripStep
        : ((stripMax / stripStep).floor() + 1) * stripStep;

    return _SectionCard(
      title: '本月电量',
      trailing: Text(
        '剩 ${MoneyFormat.axisLabel(remainNow)} / ${MoneyFormat.axisLabel(budget)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'Nunito',
          color: over ? AppColors.warning : scheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        children: [
          // ── 上：预算剩余"电量"线 ──
          SizedBox(
            height: 130,
            child: LineChart(
              LineChartData(
                minY: loY,
                maxY: maxY,
                minX: 0,
                maxX: (days - 1).toDouble(),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    color: lineColor,
                    barWidth: 2.6,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          lineColor.withValues(alpha: 0.24),
                          lineColor.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
                extraLinesData: ExtraLinesData(horizontalLines: [
                  if (over)
                    HorizontalLine(
                      y: 0,
                      color: AppColors.warning.withValues(alpha: 0.6),
                      strokeWidth: 1,
                      dashArray: const [4, 3],
                    ),
                ]),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: scheme.outlineVariant.withValues(alpha: 0.3),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: _moneyLeftTitles(scheme, step),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((s) {
                      return LineTooltipItem(
                        '第${s.x.toInt() + 1}天 剩 ${MoneyFormat.axisLabel(s.y)}',
                        TextStyle(
                            color: lineColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // ── 下：每日 支出(深)/收入(金) 小柱条，点看当天 ──
          SizedBox(
            height: 46,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: stripMaxY,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                      '${g.x.toInt() + 1}日 ${ri == 0 ? '支' : '收'} '
                      '${MoneyFormat.axisLabel(rod.toY)}',
                      TextStyle(
                          color: ri == 0 ? expColor : incColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < days; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 1,
                      barRods: [
                        BarChartRodData(
                            toY: dExp[i], color: expColor, width: 3),
                        BarChartRodData(
                            toY: dInc[i], color: incColor, width: 3),
                      ],
                    ),
                ],
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: false, reservedSize: 40)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 16,
                      interval: xInterval,
                      getTitlesWidget: (v, meta) {
                        final day = v.toInt() + 1;
                        if (day != 1 && day % xInterval.toInt() != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('$day',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: scheme.onSurfaceVariant)),
                        );
                      },
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  /// 与标题同一行、靠右的部件（如趋势图的 支出/收入 切换）。
  final Widget? trailing;

  const _SectionCard(
      {required this.title, required this.child, this.trailing});

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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (trailing != null) trailing!,
            ],
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

  /// 点分类（图例）下钻到该分类明细；「其他」聚合项不下钻。
  final void Function(String name)? onDrill;

  const _RingCard({
    required this.title,
    required this.totalLabel,
    required this.total,
    required this.categories,
    this.onDrill,
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
                  final canDrill = onDrill != null && item.name != '其他';
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canDrill ? () => onDrill!(item.name) : null,
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
                                fontWeight: FontWeight.w500,
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
                    fontSize: 12,
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
    final maxV = [...data, if (compare != null) ...compare]
        .fold<double>(0, (a, b) => a > b ? a : b);
    final step = _niceStep(maxV);
    final maxY = maxV <= 0 ? step : ((maxV / step).floor() + 1) * step;

    LineChartBarData bar(List<double> d, Color c) => LineChartBarData(
          spots: [
            for (var i = 0; i < d.length; i++) FlSpot(i.toDouble(), d[i])
          ],
          color: c,
          // 直线段（不用曲线平滑，避免数据点少时"过冲"出不存在的起伏）。
          isCurved: false,
          barWidth: 2.5,
          dotData: FlDotData(
            show: d.length <= 14,
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
            _dot(color),
            const SizedBox(width: 4),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (compare != null) ...[
              const SizedBox(width: 12),
              Container(
                  width: 12,
                  height: 2,
                  color: color.withValues(alpha: 0.4)),
              const SizedBox(width: 4),
              Text(compareLabel ?? '上期',
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
              lineBarsData: [
                if (compare != null)
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < compare.length; i++)
                        FlSpot(i.toDouble(), compare[i])
                    ],
                    color: color.withValues(alpha: 0.4),
                    isCurved: false,
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
                getDrawingHorizontalLine: (v) => FlLine(
                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                  strokeWidth: 0.5,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: _moneyLeftTitles(scheme, step),
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
                    return LineTooltipItem(
                      '$label ${MoneyFormat.axisLabel(s.y)}',
                      TextStyle(
                        color: color,
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
  final void Function(String name)? onDrill;

  const _CategoryRanking(
      {required this.categories, this.maxItems, this.onDrill});

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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDrill == null ? null : () => onDrill!(item.name),
          child: Padding(
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
        ));
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
                style:
                    TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
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
            Text(
                maxVal > 0
                    ? '多 · 单日最高 ${MoneyFormat.axisLabel(maxVal)}'
                    : '多',
                style:
                    TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
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
    double prevOf(String name) {
      final p =
          previous.expenseByCategory.where((c) => c.name == name).toList();
      return p.isEmpty ? 0 : MoneyFormat.toDouble(p.first.total);
    }

    final curColor = AppColors.expense(scheme);
    final prevColor = scheme.onSurfaceVariant.withValues(alpha: 0.35);
    var maxV = 0.0;
    for (final c in cats) {
      maxV = math.max(maxV, math.max(MoneyFormat.toDouble(c.total), prevOf(c.name)));
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
          bar(prevColor, prevOf(c.name)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// 预算 vs 实际：每个设了预算的分类一条横条（已花/预算），超支标橙。
class _BudgetVsActualCard extends StatelessWidget {
  final List<TransactionRecord> records;
  final int year;
  final int month;
  final Map<String, Decimal> budgets;

  const _BudgetVsActualCard({
    required this.records,
    required this.year,
    required this.month,
    required this.budgets,
  });

  static String? _topKeyOf(String categoryName) {
    for (final s in CategorySeed.all) {
      if (s.nameZh == categoryName) return s.parentKey ?? s.key;
    }
    return null;
  }

  static String _nameOf(String key) {
    for (final s in CategorySeed.all) {
      if (s.key == key) return s.nameZh;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 本月各顶级分类实际支出。
    final spent = <String, double>{};
    for (final r in records) {
      if (r.kind != TransactionKind.expense) continue;
      if (r.date.year != year || r.date.month != month) continue;
      final k = _topKeyOf(r.categoryName);
      if (k == null) continue;
      spent[k] = (spent[k] ?? 0) + MoneyFormat.toDouble(r.amount);
    }
    final rows = <(String, String, double, double)>[];
    for (final e in budgets.entries) {
      final b = MoneyFormat.toDouble(e.value);
      if (b <= 0) continue;
      rows.add((e.key, _nameOf(e.key), spent[e.key] ?? 0, b));
    }
    if (rows.isEmpty) {
      return Text('还没有设分类预算',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
    }
    rows.sort((a, b) => (b.$3 / b.$4).compareTo(a.$3 / a.$4));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows) ...[
          Row(
            children: [
              CatIcon(
                  categoryKey: r.$1,
                  emoji: CategorySeed.emojiOf(r.$1),
                  size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              Text(
                '${MoneyFormat.axisLabel(r.$3)} / ${MoneyFormat.axisLabel(r.$4)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFamily: 'Nunito',
                      color: r.$3 > r.$4
                          ? AppColors.warning
                          : scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (r.$3 / r.$4).clamp(0.0, 1.0),
              minHeight: 6,
              color: r.$3 > r.$4 ? AppColors.warning : scheme.primary,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// 近 12 月收支堆叠柱：柱高=当月收支较大者；深色=花掉的，金色=结余，橙色=超支。
class _StackedBars12 extends StatelessWidget {
  final List<TransactionRecord> records;
  final DateTime endMonth;

  const _StackedBars12({required this.records, required this.endMonth});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final months = <DateTime>[];
    for (var i = 11; i >= 0; i--) {
      months.add(DateTime(endMonth.year, endMonth.month - i, 1));
    }
    final exp = <double>[];
    final inc = <double>[];
    var maxV = 0.0;
    var any = false;
    for (final m in months) {
      final s = StatisticsEngine.monthlySummary(records,
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
    if (!any) {
      return Text('近 12 个月还没有记录',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
    }

    final spentColor = AppColors.expense(scheme);
    final savedColor = AppColors.income(scheme);
    final step = _niceStep(maxV);

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
              maxY: ((maxV / step).floor() + 1) * step,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, rod, ri) {
                    final i = g.x.toInt();
                    return BarTooltipItem(
                      '${months[i].month}月\n支 ${MoneyFormat.axisLabel(exp[i])}  '
                      '收 ${MoneyFormat.axisLabel(inc[i])}',
                      TextStyle(
                          color: scheme.onSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < months.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: exp[i] > inc[i] ? exp[i] : inc[i],
                        width: 12,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3)),
                        rodStackItems: [
                          // 花掉的部分（不超过收入的那截）
                          BarChartRodStackItem(0,
                              exp[i] < inc[i] ? exp[i] : inc[i], spentColor),
                          // 结余（收入 > 支出）
                          if (inc[i] > exp[i])
                            BarChartRodStackItem(exp[i], inc[i], savedColor),
                          // 超支（支出 > 收入）
                          if (exp[i] > inc[i])
                            BarChartRodStackItem(
                                inc[i], exp[i], AppColors.warning),
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
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= months.length || i.isOdd) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          '${months[i].month}月',
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
