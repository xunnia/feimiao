import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../core/budget/budget_rule_calendar.dart';
import '../../core/budget/budget_rule_display.dart';
import '../../core/budget/budget_rules.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/pressable_scale.dart';
import 'budget_rule_colors.dart';

/// 预算页的大日历（docs/08 §6.8 第 3 块）：周一开头；过去的日子写当天已花，
/// 超当天日历预算显示橙色；今天实心圆；以后留空；特别安排画彩色条和名字。
class BudgetCalendarCard extends StatelessWidget {
  final int year;
  final int month;
  final List<BudgetDayInfo> days;
  final Map<int, int> spendByDay;
  final DateTime today;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<BudgetDayInfo> onTapDay;

  const BudgetCalendarCard({
    super.key,
    required this.year,
    required this.month,
    required this.days,
    required this.spendByDay,
    required this.today,
    required this.onPrev,
    required this.onNext,
    required this.onTapDay,
  });

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lead = DateTime(year, month).weekday - 1;
    final cells = <BudgetDayInfo?>[
      ...List<BudgetDayInfo?>.filled(lead, null),
      ...days,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final weeks = [
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];
    return Container(
      key: const ValueKey('budget-calendar-card'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  year == today.year ? '$month月' : '$year年$month月',
                  style: AppType.rowTitle(scheme),
                ),
              ),
              AppCircleButton(
                key: const ValueKey('budget-month-prev'),
                icon: CupertinoIcons.chevron_back,
                size: 32,
                iconSize: 16,
                semanticLabel: '上个月',
                onPressed: onPrev,
              ),
              const SizedBox(width: 8),
              AppCircleButton(
                key: const ValueKey('budget-month-next'),
                icon: CupertinoIcons.chevron_forward,
                size: 32,
                iconSize: 16,
                semanticLabel: '下个月',
                onPressed: onNext,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final name in _weekdays)
                Expanded(
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: AppType.caption(scheme),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final week in weeks) _WeekRow(
            week: week,
            spendByDay: spendByDay,
            today: budgetDay(today),
            onTapDay: onTapDay,
          ),
          const SizedBox(height: 6),
          Text(
            '数字是当天花了多少，橙色表示当天超了',
            style: AppType.caption(scheme),
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  final List<BudgetDayInfo?> week;
  final Map<int, int> spendByDay;
  final DateTime today;
  final ValueChanged<BudgetDayInfo> onTapDay;

  const _WeekRow({
    required this.week,
    required this.spendByDay,
    required this.today,
    required this.onTapDay,
  });

  /// 同一条特别安排连续的几天合成一段色条：(起列, 止列, 规则)。
  List<(int, int, BudgetRule)> _bars() {
    final bars = <(int, int, BudgetRule)>[];
    for (var i = 0; i < week.length; i++) {
      final rule = week[i]?.specialRule;
      if (rule == null) continue;
      final last = bars.lastOrNull;
      if (last != null && last.$2 == i - 1 && last.$3.id == rule.id) {
        bars[bars.length - 1] = (last.$1, i, rule);
      } else {
        bars.add((i, i, rule));
      }
    }
    return bars;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bars = _bars();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline(scheme))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final info in week)
                Expanded(
                  child: info == null
                      ? const SizedBox(height: 46)
                      : _DayCell(
                          info: info,
                          spentCents: spendByDay[budgetDayKey(info.day)] ?? 0,
                          today: today,
                          onTap: () => onTapDay(info),
                        ),
                ),
            ],
          ),
          if (bars.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final cell = constraints.maxWidth / 7;
                return SizedBox(
                  height: 18,
                  child: Stack(
                    children: [
                      for (final (from, to, rule) in bars)
                        Positioned(
                          left: from * cell + 2,
                          width: (to - from + 1) * cell - 4,
                          top: 0,
                          bottom: 0,
                          child: _RuleBar(rule: rule),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _RuleBar extends StatelessWidget {
  final BudgetRule rule;

  const _RuleBar({required this.rule});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = budgetRuleColor(rule, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        budgetRuleName(rule),
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.1,
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final BudgetDayInfo info;
  final int spentCents;
  final DateTime today;
  final VoidCallback onTap;

  const _DayCell({
    required this.info,
    required this.spentCents,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = info.day == today;
    final isPast = info.day.isBefore(today);
    final weekend = info.day.weekday >= 6;
    final over = info.covered && spentCents > info.budgetCents;
    String? sub;
    Color subColor = AppTextColor.hint(scheme);
    if (isToday) {
      sub = '今天';
      subColor = scheme.primary;
    } else if (isPast && info.covered && spentCents >= 100) {
      sub = '${(spentCents / 100).floor()}';
      if (over) subColor = AppColors.warning;
    }
    return PressableScale(
      key: ValueKey('budget-day-${budgetDayKey(info.day)}'),
      onPressed: onTap,
      child: SizedBox(
        height: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                  : null,
              child: Text(
                '${info.day.day}',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isToday
                      ? scheme.onPrimary
                      : weekend
                          ? AppTextColor.secondary(scheme)
                          : scheme.onSurface,
                ),
              ),
            ),
            SizedBox(
              height: 14,
              child: sub == null
                  ? null
                  : Text(
                      sub,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 11,
                        fontWeight:
                            over || isToday ? FontWeight.w600 : FontWeight.w400,
                        color: subColor,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
