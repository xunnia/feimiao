import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:provider/provider.dart';

import '../../core/app_clock.dart';
import '../../core/budget/budget_engine.dart';
import '../../core/haptics.dart';
import '../../core/models/transaction_record.dart';
import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../data/app_repository.dart';
import '../../widgets/home_summary_card.dart';
import '../../widgets/mascot.dart';
import '../../widgets/sliding_segment.dart';
import '../../widgets/transaction_day_list.dart';
import '../statistics/statistics_view.dart';
import '../settings/budget_setting_view.dart';
import '../../widgets/app_page_route.dart';

enum _TxFilter { all, expense, income }

const double _homeFilterGap = 8.0;

/// 首页：顶部汇总大卡片（预算+收支）+ 按所选月分组的明细列表。
class HomeView extends StatefulWidget {
  final VoidCallback onShowTransactions;
  final double bottomInset;

  const HomeView({
    super.key,
    required this.onShowTransactions,
    this.bottomInset = 150,
  });

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
    final now = AppClock.now;
    _year = now.year;
    _month = now.month;
  }

  bool get _isCurrentMonth {
    final now = AppClock.now;
    return _year == now.year && _month == now.month;
  }

  void _stepMonth(int delta) {
    final m = DateTime(_year, _month + delta, 1);
    final now = AppClock.now;
    // 不翻到未来（没有未来数据）。
    if (m.year > now.year || (m.year == now.year && m.month > now.month)) {
      return;
    }
    Haptics.selection();
    setState(() {
      _year = m.year;
      _month = m.month;
    });
  }

  void _jumpToCurrent() {
    final now = AppClock.now;
    setState(() {
      _year = now.year;
      _month = now.month;
    });
  }

  Future<void> _pickMonth() async {
    final repo = context.read<AppRepository>();
    // The home month selector intentionally follows the original lightweight
    // sheet (the reference design): dim the page without the heavyweight
    // blurred overlay used by form sheets.
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _HomeMonthPickerSheet(
        initial: DateTime(_year, _month),
        last: AppClock.now,
        records: repo.allRecordsRef,
      ),
    );
    if (picked == null || !mounted) return;
    Haptics.selection();
    setState(() {
      _year = picked.year;
      _month = picked.month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final isCurrent = _isCurrentMonth;
    final monthDate = DateTime(_year, _month);

    final summary = StatisticsEngine.monthlySummary(
      repo.allRecordsRef,
      year: _year,
      month: _month,
    );
    // Cold start paints the home shell before the repository has selected a
    // real book. Budget queries require a positive book id, so show the normal
    // no-budget state for this brief window and rebuild with real data when
    // repository initialization notifies listeners.
    final budgetWindow =
        repo.currentBookId > 0 ? repo.budgetForCalendarMonth(monthDate) : null;
    final monthBudget = budgetWindow?.plannedAmount;
    final budgetStatus = budgetWindow == null
        ? null
        : BudgetEngine.fromWindowResult(budgetWindow);

    // 所选月的交易 + 收支筛选（退款行不单独显示，挂在原账单里）。
    // The repository keeps this view as a stable, immutable reference.  Using
    // it here avoids copying the entire visible ledger on every home rebuild;
    // only the selected month's list is materialized for grouping.
    final monthTx = [
      for (final transaction in repo.visibleTransactionsRef)
        if (transaction.date.year == _year && transaction.date.month == _month)
          transaction,
    ];
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
    final sections = groupTxnsByDay(filtered);

    final topChrome = MediaQuery.paddingOf(context).top;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: HomeSummaryCard(
            topChrome: topChrome,
            monthDate: monthDate,
            isCurrentMonth: isCurrent,
            summary: summary,
            budgetStatus: budgetStatus,
            budget: monthBudget,
            onPrevMonth: () => _stepMonth(-1),
            onNextMonth: () => _stepMonth(1),
            onPickMonth: _pickMonth,
            onJumpCurrent: _jumpToCurrent,
            onStatsTap: () => Navigator.push<void>(
              context,
              AppPageRoute<void>(
                builder: (_) => const StatisticsView(),
              ),
            ),
            onOpenBudgetSettings: () => Navigator.of(context).push(
              AppPageRoute<void>(
                builder: (_) => const BudgetSettingView(),
              ),
            ),
          ),
        ),
        // Do not show the first-use cat while SQLite is still converging. That
        // false empty state is especially jarring for existing users: it
        // appears for a moment and then the real ledger drops in underneath.
        if (repo.isInitializing)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.bottomInset),
              child: const SizedBox.shrink(),
            ),
          )
        else if (monthTx.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.bottomInset),
              child: const _EmptyState(),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: _FilterSegment(
              value: _filter,
              onChanged: (f) {
                if (f == _filter) return;
                setState(() => _filter = f);
              },
            ),
          ),
          if (sections.isEmpty)
            SliverToBoxAdapter(child: _FilterEmptyHint(filter: _filter))
          else
            SliverList.builder(
              itemCount: sections.length,
              itemBuilder: (_, i) => TxDayCard(section: sections[i]),
            ),
          SliverToBoxAdapter(child: SizedBox(height: widget.bottomInset)),
        ],
      ],
    );
  }
}

class _HomeMonthPickerSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime last;
  final List<TransactionRecord> records;

  const _HomeMonthPickerSheet({
    required this.initial,
    required this.last,
    required this.records,
  });

  @override
  State<_HomeMonthPickerSheet> createState() => _HomeMonthPickerSheetState();
}

@visibleForTesting
Widget buildHomeMonthPickerForTesting({
  DateTime? initial,
  DateTime? last,
  List<TransactionRecord> records = const [],
}) =>
    _HomeMonthPickerSheet(
      initial: initial ?? DateTime(2026, 8),
      last: last ?? DateTime(2026, 8, 28),
      records: records,
    );

class _HomeMonthPickerSheetState extends State<_HomeMonthPickerSheet> {
  late int _year = widget.initial.year;
  static const int _firstYear = 2015;

  bool _isFutureMonth(int month) {
    final m = DateTime(_year, month);
    return m.isAfter(DateTime(widget.last.year, widget.last.month));
  }

  bool _canShiftYear(int delta) {
    final y = _year + delta;
    return y >= _firstYear && y <= widget.last.year;
  }

  void _shiftYear(int delta) {
    if (!_canShiftYear(delta)) return;
    Haptics.selection();
    setState(() => _year += delta);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '月份选择',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '月统计起始日：每月 1 号',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                children: [
                  _YearArrow(
                    icon: CupertinoIcons.chevron_left,
                    enabled: _canShiftYear(-1),
                    onTap: () => _shiftYear(-1),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '$_year年',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  _YearArrow(
                    icon: CupertinoIcons.chevron_right,
                    enabled: _canShiftYear(1),
                    onTap: () => _shiftYear(1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.28,
              ),
              itemBuilder: (context, i) {
                final month = i + 1;
                final selected = _year == widget.initial.year &&
                    month == widget.initial.month;
                final disabled = _isFutureMonth(month);
                final summary = StatisticsEngine.monthlySummary(
                  widget.records,
                  year: _year,
                  month: month,
                );
                return _MonthGridCell(
                  month: month,
                  selected: selected,
                  disabled: disabled,
                  expense: summary.totalExpense,
                  income: summary.totalIncome,
                  onTap: disabled
                      ? null
                      : () => Navigator.pop(context, DateTime(_year, month)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _YearArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _YearArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? scheme.onSurfaceVariant.withValues(alpha: 0.58)
              : scheme.onSurfaceVariant.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}

class _MonthGridCell extends StatelessWidget {
  final int month;
  final bool selected;
  final bool disabled;
  final Decimal expense;
  final Decimal income;
  final VoidCallback? onTap;

  const _MonthGridCell({
    required this.month,
    required this.selected,
    required this.disabled,
    required this.expense,
    required this.income,
    required this.onTap,
  });

  bool get _hasExpense => expense > Decimal.zero;
  bool get _hasIncome => income > Decimal.zero;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.34);
    final enabledText = scheme.onSurface.withValues(alpha: 0.92);
    final fill = disabled
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.34)
        : const Color(0xFFF7FAFF);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF1F7FF) : fill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFBBD9FF) : Colors.transparent,
            width: selected ? 1.2 : 0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$month月',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: disabled ? muted : enabledText,
              ),
            ),
            const Spacer(),
            if (_hasExpense)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '-${MoneyFormat.string(expense)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Nunito',
                    color: Color(0xFF174C8F),
                  ),
                ),
              ),
            if (_hasIncome)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '+${MoneyFormat.string(income)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Nunito',
                    color: Color(0xFF87512A),
                  ),
                ),
              )
            else if (!_hasExpense)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '0',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Nunito',
                    color: disabled ? muted : scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 列表上方的 全部 / 支出 / 收入 分段筛选（Telegram 式滑块，全局组件）。
///
/// 这里先让滑块完成本地移动，再通知父级刷新列表。否则 2000+ 笔账单重建会吃掉
/// AnimatedPositioned 的首帧，看起来像没有移动动画。
class _FilterSegment extends StatefulWidget {
  final _TxFilter value;
  final ValueChanged<_TxFilter> onChanged;

  const _FilterSegment({required this.value, required this.onChanged});

  @override
  State<_FilterSegment> createState() => _FilterSegmentState();
}

class _FilterSegmentState extends State<_FilterSegment> {
  late _TxFilter _visualValue = widget.value;
  int _notifyToken = 0;

  @override
  void didUpdateWidget(covariant _FilterSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _visualValue) {
      _visualValue = widget.value;
    }
  }

  void _select(_TxFilter next) {
    if (next == _visualValue) return;
    Haptics.selection();
    setState(() => _visualValue = next);
    final token = ++_notifyToken;
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || token != _notifyToken) return;
      widget.onChanged(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, _homeFilterGap),
      child: SlidingSegment<_TxFilter>(
        key: const ValueKey('home-filter-control'),
        items: const [
          (_TxFilter.all, '全部'),
          (_TxFilter.expense, '支出'),
          (_TxFilter.income, '收入'),
        ],
        value: _visualValue,
        onChanged: _select,
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
