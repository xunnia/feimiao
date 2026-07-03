import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute, CupertinoIcons;
import 'package:provider/provider.dart';

import '../../core/budget/budget_engine.dart';
import '../../core/haptics.dart';
import '../../core/models/cat_svg_icon.dart';
import '../../core/models/category_seed.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/animated_money.dart';
import '../../widgets/mascot.dart';
import '../../widgets/sliding_segment.dart';
import '../../widgets/tag_selector.dart';
import '../../widgets/transaction_actions.dart';
import '../statistics/statistics_view.dart';
import '../settings/budget_setting_view.dart';
import '../transactions/edit_transaction_sheet.dart';

enum _TxFilter { all, expense, income }

/// 首页：折叠吸顶大卡片（预算+收支）+ 按所选月分组的明细列表。
class HomeView extends StatefulWidget {
  final VoidCallback onShowTransactions;

  const HomeView({super.key, required this.onShowTransactions});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late int _year;
  late int _month;
  _TxFilter _filter = _TxFilter.all;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _year == now.year && _month == now.month;
  }

  void _stepMonth(int delta) {
    final m = DateTime(_year, _month + delta, 1);
    final now = DateTime.now();
    // 不翻到未来（没有未来数据）。
    if (m.year > now.year || (m.year == now.year && m.month > now.month)) return;
    Haptics.selection();
    setState(() {
      _year = m.year;
      _month = m.month;
    });
  }

  void _jumpToCurrent() {
    final now = DateTime.now();
    setState(() {
      _year = now.year;
      _month = now.month;
    });
  }

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
    final isCurrent = _isCurrentMonth;
    final monthDate = DateTime(_year, _month);

    final summary = StatisticsEngine.monthlySummary(
      repo.allRecords,
      year: _year,
      month: _month,
    );
    // 预算走「期间」模型：历史月显示当时生效的预算，不被后来的调整覆盖。
    final monthBudget = repo.budgetTotalFor(_year, _month);
    final budgetStatus = monthBudget != null
        ? BudgetEngine.status(
            monthlyBudget: monthBudget,
            records: repo.allRecords,
            on: isCurrent
                ? DateTime.now()
                : DateTime(_year, _month,
                    StatisticsEngine.daysInMonth(year: _year, month: _month)),
          )
        : null;

    // 所选月的交易 + 收支筛选（退款行不单独显示，挂在原账单里）。
    final monthTx = repo.visibleTransactions
        .where((t) => t.date.year == _year && t.date.month == _month)
        .toList();
    final filtered = monthTx.where((t) {
      switch (_filter) {
        case _TxFilter.all:
          return true;
        case _TxFilter.expense:
          return t.txKind == TransactionKind.expense;
        case _TxFilter.income:
          return t.txKind == TransactionKind.income;
      }
    }).toList();
    final sections = _groupByDay(filtered);

    // 顶部大卡片与下方筛选胶囊的间距收紧（用户 0702：原间距太远，减半）。
    final double expandedHeight = budgetStatus == null ? 188.0 : 224.0;
    const double minExtent = kToolbarHeight;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          automaticallyImplyLeading: false,
          pinned: true,
          expandedHeight: expandedHeight,
          collapsedHeight: minExtent,
          backgroundColor: AppColors.appBg(Theme.of(context).colorScheme),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: LayoutBuilder(
            builder: (context, constraints) {
              final maxH = constraints.maxHeight;
              final expandedTotal =
                  expandedHeight + MediaQuery.of(context).padding.top;
              final collapsedTotal =
                  minExtent + MediaQuery.of(context).padding.top;
              final t = ((maxH - collapsedTotal) /
                      (expandedTotal - collapsedTotal).clamp(1.0, double.infinity))
                  .clamp(0.0, 1.0);

              return Stack(
                children: [
                  Opacity(
                    opacity: t,
                    child: IgnorePointer(
                      ignoring: t < 0.3,
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: _ExpandedSummaryCard(
                          monthDate: monthDate,
                          isCurrentMonth: isCurrent,
                          summary: summary,
                          budgetStatus: budgetStatus,
                          budget: monthBudget,
                          onPrevMonth: () => _stepMonth(-1),
                          onNextMonth: () => _stepMonth(1),
                          onJumpCurrent: _jumpToCurrent,
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
                          isCurrentMonth: isCurrent,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (monthTx.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          )
        else ...[
          SliverToBoxAdapter(
            child: _FilterSegment(
              value: _filter,
              onChanged: (f) {
                if (f == _filter) return;
                Haptics.selection();
                setState(() => _filter = f);
              },
            ),
          ),
          if (sections.isEmpty)
            SliverToBoxAdapter(child: _FilterEmptyHint(filter: _filter))
          else
            for (final s in sections)
              SliverToBoxAdapter(
                child: _DayCard(section: s, repo: repo),
              ),
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 展开态大卡片
// ---------------------------------------------------------------------------

class _ExpandedSummaryCard extends StatelessWidget {
  final DateTime monthDate;
  final bool isCurrentMonth;
  final MonthlySummary summary;
  final BudgetStatus? budgetStatus;
  final Decimal? budget;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onJumpCurrent;

  const _ExpandedSummaryCard({
    required this.monthDate,
    required this.isCurrentMonth,
    required this.summary,
    required this.budgetStatus,
    required this.budget,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onJumpCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOverspend = budgetStatus?.isOverBudget ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Card(
        elevation: 1,
        color: AppColors.card(scheme),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Transform.translate(
                    offset: const Offset(-12, 0),
                    child: _MonthStepper(
                      monthDate: monthDate,
                      isCurrentMonth: isCurrentMonth,
                      onPrev: onPrevMonth,
                      onNext: onNextMonth,
                      onJumpCurrent: onJumpCurrent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.push<void>(
                      context,
                      CupertinoPageRoute<void>(
                        builder: (_) => const StatisticsView(),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.card(scheme),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                          width: 0.5,
                        ),
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
                            CupertinoIcons.chevron_forward,
                            size: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              if (budgetStatus != null)
                _BudgetBody(
                  summary: summary,
                  budgetStatus: budgetStatus!,
                  budget: budget!,
                  isCurrentMonth: isCurrentMonth,
                )
              else ...[
                _HeroBlock(
                  summary: summary,
                  budgetStatus: budgetStatus,
                  isCurrentMonth: isCurrentMonth,
                ),
                const SizedBox(height: AppSpacing.md),
                _IncomeExpenseRow(summary: summary),
              ],
            ],
          ),
        ),
      ),
          Positioned(
            top: -8,
            right: -2,
            child: IgnorePointer(
              child: MascotBreath(
                // 探头猫贴在卡片顶边,改成向下浮动(抵消放大的上移),避免被顶边裁掉。
                bob: 4.0,
                child: Image.asset(
                  'assets/mascot/${isOverspend ? 'overspend' : 'idle'}.png',
                  height: 96,
                  fit: BoxFit.fitHeight,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 月份步进器：‹ 2026年6月 ›。到当月时禁用向后箭头；点月份名跳回当月。
class _MonthStepper extends StatelessWidget {
  final DateTime monthDate;
  final bool isCurrentMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onJumpCurrent;

  const _MonthStepper({
    required this.monthDate,
    required this.isCurrentMonth,
    required this.onPrev,
    required this.onNext,
    required this.onJumpCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget arrow(IconData icon, VoidCallback? onTap) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Icon(
              icon,
              size: 16,
              color: onTap == null
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.3)
                  : scheme.onSurfaceVariant,
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(CupertinoIcons.chevron_back, onPrev),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isCurrentMonth ? null : onJumpCurrent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${monthDate.year}年${monthDate.month}月',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
            ),
          ),
        ),
        arrow(
          CupertinoIcons.chevron_forward,
          isCurrentMonth ? null : onNext,
        ),
      ],
    );
  }
}

/// 收入 | 支出 两栏（中间发丝竖线）。
class _IncomeExpenseRow extends StatelessWidget {
  final MonthlySummary summary;

  const _IncomeExpenseRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
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
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
    );
  }
}

/// 当月有预算时的大卡片主体：左侧（月预算剩余 + 收支 + 进度条）+ 右侧今日可花环形图。
class _BudgetBody extends StatelessWidget {
  final MonthlySummary summary;
  final BudgetStatus budgetStatus;
  final Decimal budget;
  final bool isCurrentMonth;

  const _BudgetBody({
    required this.summary,
    required this.budgetStatus,
    required this.budget,
    required this.isCurrentMonth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = budgetStatus;
    final over = s.isOverBudget;
    final remaining = s.remaining;

    final rawRatio = budget > Decimal.zero
        ? (s.spentThisMonth / budget)
            .toDecimal(scaleOnInfinitePrecision: 4)
            .toDouble()
        : 0.0;
    final ratio = rawRatio.clamp(0.0, 1.0);
    final pct = (rawRatio * 100).round();

    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final remainingDays = daysInMonth - now.day + 1;

    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ▎月预算剩余
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 2,
              height: 11,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isCurrentMonth
                  ? (over ? '月预算已超' : '月预算剩余')
                  : (over ? '该月超预算' : '该月预算剩余'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppTextColor.hint(scheme),
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        AnimatedMoney(
          value: remaining.abs(),
          prefix: over ? '-' : '',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontFamily: 'Nunito',
            color: over ? AppColors.warning : scheme.onSurface,
            // ignore: deprecated_member_use
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _IncomeExpenseRow(summary: summary),
        const SizedBox(height: AppSpacing.md),
        _BudgetBar(ratio: ratio),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$pct%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Nunito',
                ),
              ),
            ),
            const Spacer(),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: MoneyFormat.string(budget),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Nunito',
                      // ignore: deprecated_member_use
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (isCurrentMonth)
                    TextSpan(
                      text: ' · 剩 $remainingDays 天',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );

    // 右侧环形图：当月 = 今日可花(金额)；历史月 = 本月预算用量(百分比)。
    final String ringLabel;
    final String ringText;
    final double ringVal;
    final Color ringColor;
    if (isCurrentMonth) {
      final today = s.todayAllowance;
      final todayNeg = today < Decimal.zero;
      final dayEnv = s.spentToday + (todayNeg ? Decimal.zero : today);
      ringVal = todayNeg
          ? 0.0
          : (dayEnv > Decimal.zero
              ? (today / dayEnv)
                  .toDecimal(scaleOnInfinitePrecision: 4)
                  .toDouble()
                  .clamp(0.0, 1.0)
              : 1.0);
      ringColor = todayNeg ? AppColors.warning : const Color(0xFF7FB069);
      ringLabel = '今日可花';
      ringText = todayNeg
          ? '-${MoneyFormat.string(today.abs())}'
          : MoneyFormat.string(today);
    } else {
      ringVal = ratio;
      ringColor = over ? AppColors.warning : const Color(0xFF7FB069);
      ringLabel = '已用';
      ringText = '$pct%';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: leftColumn),
        const SizedBox(width: 14),
        Transform.translate(
          offset: const Offset(-8, 8),
          child: _TodayRing(
            value: ringVal,
            label: ringLabel,
            amountText: ringText,
            color: ringColor,
          ),
        ),
      ],
    );
  }
}

/// 预算进度条：填充部分是「绿 → 黄橙 → 红」渐变的左侧切片，花得越多越往红推进。
class _BudgetBar extends StatelessWidget {
  final double ratio;
  const _BudgetBar({required this.ratio});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = ratio.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        height: 7,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth;
            return Stack(
              children: [
                Container(
                  width: w,
                  height: 7,
                  color: scheme.surfaceContainerHighest,
                ),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: r,
                    child: Container(
                      width: w,
                      height: 7,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF7FB069), // 绿
                            Color(0xFFF2B23C), // 黄橙
                            Color(0xFFE0552B), // 红
                          ],
                          stops: [0.0, 0.6, 1.0],
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
    );
  }
}

/// 今日可花环形图（右侧）。
class _TodayRing extends StatelessWidget {
  final double value;
  final String label;
  final String amountText;
  final Color color;

  const _TodayRing({
    required this.value,
    required this.label,
    required this.amountText,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 7,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTextColor.hint(scheme),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                amountText,
                maxLines: 1,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Nunito',
                  color: scheme.onSurface,
                  // ignore: deprecated_member_use
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 大卡片主角：
/// - 当月有预算：预算剩余 + 趋势 +（今日可用 / 今天已花）
/// - 非当月有预算：该月预算剩余
/// - 无预算：本月结余 + 邀请去设预算
class _HeroBlock extends StatelessWidget {
  final MonthlySummary summary;
  final BudgetStatus? budgetStatus;
  final bool isCurrentMonth;

  const _HeroBlock({
    required this.summary,
    required this.budgetStatus,
    required this.isCurrentMonth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget bigMoney(Decimal v, {bool neg = false, required Color color}) =>
        AnimatedMoney(
          value: v.abs(),
          prefix: neg ? '-' : '',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: color,
            fontFamily: 'Nunito',
            // ignore: deprecated_member_use
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
    TextStyle? hint() =>
        theme.textTheme.labelSmall?.copyWith(color: AppTextColor.hint(scheme));

    // 1) 无预算 → 结余 + 邀请去设预算。
    if (budgetStatus == null) {
      final balance = summary.balance;
      final neg = balance < Decimal.zero;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          bigMoney(balance,
              neg: neg, color: neg ? AppColors.warning : scheme.onSurface),
          const SizedBox(height: 3),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                  builder: (_) => const BudgetSettingView()),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_circle_outline, size: 13, color: scheme.primary),
                const SizedBox(width: 3),
                Text(
                  '设预算 · 帮你盯每天能花多少',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.primary),
                ),
                const SizedBox(width: 1),
                Icon(CupertinoIcons.chevron_forward,
                    size: 11, color: scheme.primary),
              ],
            ),
          ),
        ],
      );
    }

    final s = budgetStatus!;
    final over = s.isOverBudget;
    final heroColor = over ? AppColors.warning : scheme.onSurface;

    // 2) 非当月 → 该月预算剩余（今日/趋势对历史月无意义）。
    if (!isCurrentMonth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          bigMoney(s.remaining, neg: over, color: heroColor),
          Text(over ? '该月超预算' : '该月预算剩余', style: hint()),
        ],
      );
    }

    // 3) 当月 → 预算剩余 + 今日可用/今天已花（节奏看进度条颜色即可，不重复标趋势）。
    final today = s.todayAllowance; // 可负
    final todayNeg = today < Decimal.zero;
    final secondLine = todayNeg
        ? '今日超 ${MoneyFormat.string(today.abs())} · 今天已花 ${MoneyFormat.string(s.spentToday)}'
        : '今日可用 ${MoneyFormat.string(today)} · 今天已花 ${MoneyFormat.string(s.spentToday)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bigMoney(s.remaining, neg: over, color: heroColor),
        const SizedBox(height: 3),
        Text(over ? '已超预算' : '预算剩余', style: hint()),
        const SizedBox(height: 2),
        Text(
          secondLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppTextColor.secondary(scheme),
            fontFamily: 'Nunito',
            // ignore: deprecated_member_use
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 列表上方的 全部 / 支出 / 收入 分段筛选（Telegram 式滑块，全局组件）。
class _FilterSegment extends StatelessWidget {
  final _TxFilter value;
  final ValueChanged<_TxFilter> onChanged;

  const _FilterSegment({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SlidingSegment<_TxFilter>(
        items: const [
          (_TxFilter.all, '全部'),
          (_TxFilter.expense, '支出'),
          (_TxFilter.income, '收入'),
        ],
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// 筛选后该月无对应记录时的占位提示。
class _FilterEmptyHint extends StatelessWidget {
  final _TxFilter filter;

  const _FilterEmptyHint({required this.filter});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final word = filter == _TxFilter.income ? '收入' : '支出';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
      child: Center(
        child: Text(
          '这个月还没有$word记录',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
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
                fontWeight: FontWeight.w400,
                color: color,
                fontFamily: 'Nunito',
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
  final DateTime monthDate;
  final bool isCurrentMonth;

  const _BudgetStrip({
    required this.budgetStatus,
    required this.budget,
    required this.isOverspend,
    required this.monthDate,
    required this.isCurrentMonth,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (budgetStatus == null || budget == null) {
      return const SizedBox.shrink();
    }

    final status = budgetStatus!;
    final budgetVal = budget!;
    final ratio = budgetVal > Decimal.zero
        ? (status.spentThisMonth / budgetVal)
            .toDecimal(scaleOnInfinitePrecision: 4)
            .toDouble()
            .clamp(0.0, 1.0)
        : 0.0;

    // 时间进度：当月用今天/总天数；历史月视作已走完（1.0）。
    final now = DateTime.now();
    final daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    final timeRatio =
        (isCurrentMonth ? now.day / daysInMonth : 1.0).clamp(0.0, 1.0);
    // 花钱进度 vs 时间进度：没超时间进度 = 柔绿；超了 = 越深的橙
    final Color barColor;
    if (isOverspend) {
      barColor = const Color(0xFFE0552B);
    } else if (ratio <= timeRatio) {
      barColor = const Color(0xFF7FB069);
    } else {
      final over = (1 - timeRatio) <= 0
          ? 1.0
          : ((ratio - timeRatio) / (1 - timeRatio)).clamp(0.0, 1.0);
      barColor =
          Color.lerp(const Color(0xFFF2B23C), const Color(0xFFE0552B), over)!;
    }

    final remainingDays = daysInMonth - now.day + 1;
    final caption = isOverspend
        ? '已超 ${MoneyFormat.string(status.spentThisMonth - budgetVal)} · 预算 ${MoneyFormat.string(budgetVal)}'
        : isCurrentMonth
            ? '已用 ${MoneyFormat.string(status.spentThisMonth)} / ${MoneyFormat.string(budgetVal)} · 剩 $remainingDays 天'
            : '已用 ${MoneyFormat.string(status.spentThisMonth)} / ${MoneyFormat.string(budgetVal)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                fontWeight: FontWeight.w300,
                fontFamily: 'Nunito',
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
  final bool isCurrentMonth;

  const _CollapsedMiniBar({
    required this.summary,
    required this.budgetStatus,
    required this.isCurrentMonth,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final String label;
    final String value;
    final Color color;
    final b = budgetStatus;

    if (b != null && isCurrentMonth) {
      // 与展开态一致：剩 ¥X · 今日 ¥Y
      final over = b.isOverBudget;
      final todayNeg = b.todayAllowance < Decimal.zero;
      final todayStr = todayNeg
          ? '今日超 ${MoneyFormat.string(b.todayAllowance.abs())}'
          : '今日 ${MoneyFormat.string(b.todayAllowance)}';
      label = over ? '超 ' : '剩 ';
      value = '${MoneyFormat.string(b.remaining.abs())} · $todayStr';
      color = over ? AppColors.warning : scheme.onSurface;
    } else if (b != null) {
      final over = b.isOverBudget;
      label = over ? '该月超 ' : '该月剩 ';
      value = MoneyFormat.string(b.remaining.abs());
      color = over ? AppColors.warning : scheme.onSurface;
    } else {
      final balance = summary.balance;
      final neg = balance < Decimal.zero;
      label = '结余 ';
      value = '${neg ? '-' : ''}${MoneyFormat.string(balance.abs())}';
      color = neg ? AppColors.warning : scheme.onSurface;
    }

    return SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: color,
                    fontFamily: 'Nunito',
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

/// 按天分组的白色卡片：卡内 = 日期头 + 当天各笔（发丝线分隔）。
class _DayCard extends StatelessWidget {
  final _DaySection section;
  final AppRepository repo;

  const _DayCard({required this.section, required this.repo});

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
          _DaySectionHeader(section: section),
          for (int i = 0; i < section.items.length; i++) ...[
            if (i > 0)
              Container(
                margin: const EdgeInsets.only(left: 66, right: 14),
                height: 0.5,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            _DismissibleRow(transaction: section.items[i]),
          ],
        ],
      ),
    );
  }
}


class _DaySectionHeader extends StatelessWidget {
  final _DaySection section;

  const _DaySectionHeader({required this.section});

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
          if (hasExpense) ...[
            Text(
              '支 ${MoneyFormat.string(totalExpense).replaceAll('¥', '')}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'Nunito',
                    // ignore: deprecated_member_use
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
          if (hasExpense && hasIncome) const SizedBox(width: 8),
          if (hasIncome)
            Text(
              '收 ${MoneyFormat.string(totalIncome).replaceAll('¥', '')}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
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

class _DismissibleRow extends StatelessWidget {
  final TransactionEntity transaction;

  const _DismissibleRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    return TransactionSlidable(
      transaction: transaction,
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

  // 退款冲账 = 负向支出：显示成「+¥x」铜金色。
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
    // 附着式退款：这笔有退款时显示净额 + 划掉原价 + 「已退 X」绿标。
    final refunded = context.read<AppRepository>().refundedAmountOf(transaction.id);
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
                    if (hasRefund) _RefundBadge(refunded: refunded),
                    if (transaction.reimbursable) const _ReimburseBadge(),
                    if (transaction.excluded) const _ExcludedBadge(),
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
          // 有退款：划线原价（小、灰）+ 净额；否则单显金额。
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
              // 净额归 0（全额退/报销）就不带负号，避免「-¥0.00」。
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

/// 「已退 X」小标。退款=钱回来了，用铜金（守住「不用红绿」的配色铁律）。
class _RefundBadge extends StatelessWidget {
  final Decimal refunded;

  const _RefundBadge({required this.refunded});

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
      child: Text(
        '已退 ${MoneyFormat.string(refunded)}',
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          color: gold,
          fontWeight: FontWeight.w500,
        ),
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
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 「不计入收支」小标：这笔在列表里，但统计/预算都跳过它。
class _ExcludedBadge extends StatelessWidget {
  const _ExcludedBadge();

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
      child: Text(
        '不计入',
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 空状态：只有猫，不配文案（用户 0702 拍板）。
/// 唯一例外：整个 App 一笔账都没有（新用户首启），给一句上手引导——
/// 不然新人进来只看到一只睡觉的猫，不知道第一步干嘛。
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final firstUse = context.watch<AppRepository>().transactions.isEmpty;
    if (!firstUse) {
      return const Center(
        child: Mascot(mood: MascotMood.empty, size: 184, animate: true),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Mascot(mood: MascotMood.empty, size: 184, animate: true),
          const SizedBox(height: 10),
          Text(
            '点下面的输入框，跟我说「午饭花了 20」试试喵',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
