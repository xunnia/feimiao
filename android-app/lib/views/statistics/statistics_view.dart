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
          repo: repo,
          weekStart: _weekStart,
          isCurrentWeek: _isCurrentWeek,
          onShift: _shiftWeek,
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
          onShiftMonth: _shiftMonth,
        );
      case _StatRange.year:
        return _YearlyContent(
          records: records,
          repo: repo,
          year: _displayedMonth.year,
          isCurrentYear: _displayedMonth.year == DateTime.now().year,
          onShift: _shiftYear,
        );
      case _StatRange.custom:
        return _CustomContent(
          records: records,
          repo: repo,
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
  final AppRepository repo;
  final DateTime weekStart;
  final bool isCurrentWeek;
  final void Function(int) onShift;

  const _WeekContent({
    required this.records,
    required this.repo,
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

    final header = Column(
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
                child: _CategoryRanking(categories: s.expenseByCategory),
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
  final void Function(int) onShiftMonth;

  const _MonthlyContent({
    required this.records,
    required this.repo,
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

    final header = Column(
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
      buildCard: (k) => _buildCard(k, summary, prevSummary, top5),
    );
  }

  Widget? _buildCard(
    String key,
    MonthlySummary summary,
    MonthlySummary prevSummary,
    List<TransactionRecord> top5,
  ) {
    final hasExpense = summary.expenseByCategory.isNotEmpty;
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
      case 'ring':
        if (!hasExpense) return null;
        return _RingCard(
          title: '支出构成',
          totalLabel: '本月支出',
          total: summary.totalExpense,
          categories: summary.expenseByCategory,
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
        );
      case 'ranking':
        if (!hasExpense) return null;
        return _SectionCard(
          title: '分类排行',
          child: _CategoryRanking(categories: summary.expenseByCategory),
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
      case 'compare':
        if (!hasExpense && prevSummary.expenseByCategory.isEmpty) return null;
        return _SectionCard(
          title: '本月 vs 上月',
          child: _CompareBars(current: summary, previous: prevSummary),
        );
      case 'radar':
        if (summary.expenseByCategory.length < 3) return null;
        return _SectionCard(
          title: '消费结构雷达（本月 vs 上月）',
          child: _RadarCompare(current: summary, previous: prevSummary),
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
    'budget': '本月预算',
    'ring': '支出构成',
    'daily': '趋势图',
    'ranking': '分类排行',
    'top5': '单笔支出排行',
    'heatmap': '消费热力图',
    'compare': '本月 vs 上月',
    'radar': '消费结构雷达',
    'stacked': '近 12 月收支',
  };

  /// 只在月视图有意义的卡（图表库里标注出来）。
  static const Set<String> monthOnly = {
    'insights', 'budget', 'heatmap', 'compare', 'radar', 'stacked',
  };

  /// 默认可见卡片（其余在图表库里，用户自己加）。
  static const List<String> defaultOrder = [
    'insights', 'budget', 'ring', 'daily', 'ranking', 'top5',
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

    return ReorderableListView(
      padding: const EdgeInsets.all(16),
      buildDefaultDragHandles: false,
      header: header,
      footer: _CustomizeButton(
        onTap: () => _showCardLibrary(context),
      ),
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
      children: [
        for (var i = 0; i < items.length; i++)
          ReorderableDelayedDragStartListener(
            key: ValueKey('stat_card_${items[i].$1}'),
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              // 每张图表卡隔离重绘：滚动/拖排序时旁边的 fl_chart 不用跟着重画。
              child: RepaintBoundary(child: items[i].$2),
            ),
          ),
      ],
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('自定义图表',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('打开想看的图表，长按卡片可拖动排序；带「月」标的只在月视图显示',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(ctx2).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    for (final e in cardTitles.entries)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              monthOnly.contains(e.key)
                                  ? '${e.value} · 月'
                                  : e.value,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          Switch(
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
                        ],
                      ),
                  ],
                ),
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

  const _TrendCard({
    super.key,
    required this.title,
    required this.xLabels,
    required this.expense,
    required this.income,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 132,
              child: SlidingSegment<bool>(
                items: const [(false, '支出'), (true, '收入')],
                value: _showIncome,
                onChanged: (v) {
                  Haptics.selection();
                  setState(() => _showIncome = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          _DualLineChart(
            xLabels: widget.xLabels,
            expense: widget.expense,
            income: widget.income,
            showIncome: _showIncome,
          ),
        ],
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
  final bool isCurrentYear;
  final void Function(int) onShift;

  const _YearlyContent({
    required this.records,
    required this.repo,
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

    final header = Column(
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
          ),
        'ring' => !hasExpense
            ? null
            : _RingCard(
                title: '支出构成',
                totalLabel: '全年支出',
                total: summary.totalExpense,
                categories: summary.expenseByCategory,
              ),
        'ranking' => !hasExpense
            ? null
            : _SectionCard(
                title: '全年分类排行',
                child: _CategoryRanking(
                  categories: summary.expenseByCategory,
                  maxItems: 10,
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

class _CustomContent extends StatelessWidget {
  final List<TransactionRecord> records;
  final AppRepository repo;
  final DateTimeRange? range;
  final VoidCallback onPick;

  const _CustomContent({
    required this.records,
    required this.repo,
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

    final header = Column(
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
                child: _CategoryRanking(categories: s.expenseByCategory),
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

  /// 二选一显示（用户 0703：支出/收入别挤在一张图里）。
  /// 默认只画支出；[showIncome]=true 时只画收入。
  final bool showIncome;

  const _DualLineChart({
    required this.xLabels,
    required this.expense,
    required this.income,
    this.showIncome = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expColor = AppColors.expense(scheme);
    final incColor = AppColors.income(scheme);
    final data = showIncome ? income : expense;
    final color = showIncome ? incColor : expColor;
    final label = showIncome ? '收入' : '支出';
    final maxV = data.fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = maxV <= 0 ? 1.0 : maxV * 1.25;

    LineChartBarData bar(List<double> d, Color c) => LineChartBarData(
          spots: [
            for (var i = 0; i < d.length; i++) FlSpot(i.toDouble(), d[i])
          ],
          color: c,
          isCurved: true,
          curveSmoothness: 0.25,
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
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              lineBarsData: [bar(data, color)],
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
                    return LineTooltipItem(
                      '$label ¥${s.y.toStringAsFixed(0)}',
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
              Builder(builder: (_) {
                final v = MoneyFormat.toDouble(d.expense);
                final t = maxVal <= 0 ? 0.0 : (v / maxVal).clamp(0.0, 1.0);
                final bg = v <= 0
                    ? scheme.outlineVariant.withValues(alpha: 0.25)
                    : scheme.primary.withValues(alpha: 0.18 + 0.72 * t);
                return Container(
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
            Text('多',
                style:
                    TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

/// 本月 vs 上月：TOP5 分类的分组柱状对比。
class _CompareBars extends StatelessWidget {
  final MonthlySummary current;
  final MonthlySummary previous;

  const _CompareBars({required this.current, required this.previous});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cats = current.expenseByCategory
        .where((c) => c.total > Decimal.zero)
        .take(5)
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

    final curColor = scheme.primary;
    final prevColor = scheme.outlineVariant;
    var maxV = 0.0;
    for (final c in cats) {
      final cur = MoneyFormat.toDouble(c.total);
      final prev = prevOf(c.name);
      if (cur > maxV) maxV = cur;
      if (prev > maxV) maxV = prev;
    }

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
        SizedBox(
          height: 170,
          child: BarChart(
            BarChartData(
              maxY: maxV * 1.2,
              barGroups: [
                for (var i = 0; i < cats.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 3,
                    barRods: [
                      BarChartRodData(
                        toY: prevOf(cats[i].name),
                        color: prevColor,
                        width: 9,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3)),
                      ),
                      BarChartRodData(
                        toY: MoneyFormat.toDouble(cats[i].total),
                        color: curColor,
                        width: 9,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3)),
                      ),
                    ],
                  ),
              ],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
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
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= cats.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          cats[i].name.length > 3
                              ? cats[i].name.substring(0, 3)
                              : cats[i].name,
                          style: TextStyle(
                              fontSize: 10, color: scheme.onSurfaceVariant),
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

/// 消费结构雷达：本月 vs 上月的 TOP 分类金额轮廓对比。
class _RadarCompare extends StatelessWidget {
  final MonthlySummary current;
  final MonthlySummary previous;

  const _RadarCompare({required this.current, required this.previous});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cats = current.expenseByCategory
        .where((c) => c.total > Decimal.zero)
        .take(6)
        .toList();
    if (cats.length < 3) {
      return Text('分类不足 3 个，雷达图画不起来',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
    }
    double prevOf(String name) {
      final p =
          previous.expenseByCategory.where((c) => c.name == name).toList();
      return p.isEmpty ? 0 : MoneyFormat.toDouble(p.first.total);
    }

    final curColor = scheme.primary;
    final prevColor = AppColors.income(scheme);

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
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: RadarChart(
            RadarChartData(
              radarShape: RadarShape.polygon,
              tickCount: 3,
              ticksTextStyle:
                  const TextStyle(color: Colors.transparent, fontSize: 8),
              tickBorderData: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                  width: 0.5),
              gridBorderData: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                  width: 0.7),
              radarBorderData: const BorderSide(color: Colors.transparent),
              borderData: FlBorderData(show: false),
              getTitle: (index, angle) => RadarChartTitle(
                text: cats[index].name.length > 4
                    ? cats[index].name.substring(0, 4)
                    : cats[index].name,
              ),
              titleTextStyle:
                  TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              titlePositionPercentageOffset: 0.14,
              dataSets: [
                RadarDataSet(
                  fillColor: prevColor.withValues(alpha: 0.12),
                  borderColor: prevColor,
                  borderWidth: 1.6,
                  entryRadius: 2,
                  dataEntries: [
                    for (final c in cats) RadarEntry(value: prevOf(c.name)),
                  ],
                ),
                RadarDataSet(
                  fillColor: curColor.withValues(alpha: 0.16),
                  borderColor: curColor,
                  borderWidth: 2,
                  entryRadius: 2.5,
                  dataEntries: [
                    for (final c in cats)
                      RadarEntry(value: MoneyFormat.toDouble(c.total)),
                  ],
                ),
              ],
            ),
          ),
        ),
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
              maxY: maxV * 1.15,
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
                getDrawingHorizontalLine: (_) => FlLine(
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
