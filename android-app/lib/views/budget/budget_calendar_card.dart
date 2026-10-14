import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../core/budget/budget_rule_calendar.dart';
import '../../core/budget/budget_rule_display.dart';
import '../../core/budget/budget_rules.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
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
    final title = '$year年$month月';
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
    return BudgetCard(
      key: const ValueKey('budget-calendar-card'),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              BudgetMonthArrow(
                key: const ValueKey('budget-month-prev'),
                icon: CupertinoIcons.chevron_back,
                semanticLabel: '上个月',
                onPressed: onPrev,
              ),
              BudgetMonthArrow(
                key: const ValueKey('budget-month-next'),
                icon: CupertinoIcons.chevron_forward,
                semanticLabel: '下个月',
                onPressed: onNext,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final name in _weekdays)
                Expanded(
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTextColor.hint(scheme),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          for (final week in weeks)
            _WeekRow(
              week: week,
              spendByDay: spendByDay,
              today: budgetDay(today),
              onTapDay: onTapDay,
            ),
          const SizedBox(height: 6),
          _Legend(scheme: scheme),
        ],
      ),
    );
  }
}

/// 预算页统一的主题卡片底、大圆角和轻投影。
class BudgetCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const BudgetCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.hairline(scheme), width: 0.5),
      ),
      child: child,
    );
  }
}

/// 日历翻月的小箭头：只有图标，不带圆底（示意图「‹ ›」）。
class BudgetMonthArrow extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;

  const BudgetMonthArrow({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: PressableScale(
        onPressed: onPressed,
        child: SizedBox(
          width: 36,
          height: 32,
          child: Icon(icon, size: 18, color: AppTextColor.secondary(scheme)),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final ColorScheme scheme;

  const _Legend({required this.scheme});

  Widget _dot(Color color) => Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11.5, color: AppTextColor.hint(scheme));
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('数字 = 当天花了多少', style: style),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _dot(AppColors.warning),
          Text('超了当天预算', style: style),
        ]),
      ],
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
    final bars = _bars();
    return Container(
      padding: const EdgeInsets.only(top: 3, bottom: 1),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final scaler = MediaQuery.textScalerOf(context);
              final circleSize = math.min(
                constraints.maxWidth / 7 - 4,
                math.max(27.0, scaler.scale(27)),
              );
              final subHeight = math.max(12.0, scaler.scale(10.5) * 1.15);
              return Row(
                children: [
                  for (final info in week)
                    Expanded(
                      child: info == null
                          ? SizedBox(height: circleSize + subHeight)
                          : _DayCell(
                              info: info,
                              spentCents:
                                  spendByDay[budgetDayKey(info.day)] ?? 0,
                              today: today,
                              circleSize: circleSize,
                              subHeight: subHeight,
                              onTap: () => onTapDay(info),
                            ),
                    ),
                ],
              );
            },
          ),
          if (bars.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final cell = constraints.maxWidth / 7;
                return SizedBox(
                  height: math.max(
                    20.0,
                    MediaQuery.textScalerOf(context).scale(11) * 1.4 + 4,
                  ),
                  child: Stack(
                    children: [
                      for (final (from, to, rule) in bars)
                        Positioned(
                          left: from * cell + 3,
                          width: (to - from + 1) * cell - 6,
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
    final unit = switch (rule.unit) {
      BudgetRuleUnit.day => '天',
      BudgetRuleUnit.week => '周',
      BudgetRuleUnit.month => '月',
      BudgetRuleUnit.year => '年',
    };
    final label =
        '${budgetRuleName(rule)} ${budgetYuanText(rule.amountCents)}/$unit';
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final BudgetDayInfo info;
  final int spentCents;
  final DateTime today;
  final double circleSize;
  final double subHeight;
  final VoidCallback onTap;

  const _DayCell({
    required this.info,
    required this.spentCents,
    required this.today,
    required this.circleSize,
    required this.subHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = info.day == today;
    final isPast = info.day.isBefore(today);
    final over = info.covered && spentCents > info.budgetCents;
    String? sub;
    Color subColor = scheme.onSurface.withValues(alpha: 0.58);
    if (isToday) {
      sub = '今天';
      subColor = scheme.primary;
    } else if (isPast && info.covered && spentCents >= 100) {
      sub = '${(spentCents / 100).floor()}';
      if (over) subColor = AppColors.warning;
    }
    return Semantics(
      button: true,
      selected: isToday,
      label: '${info.day.month}月${info.day.day}日'
          '${isToday ? '，今天' : ''}'
          '${info.covered ? '，预算${budgetYuanText(info.budgetCents)}' : '，没有预算'}'
          '${isPast ? '，花了${budgetYuanText(spentCents)}' : ''}',
      child: PressableScale(
        key: ValueKey('budget-day-${budgetDayKey(info.day)}'),
        onPressed: onTap,
        child: SizedBox(
          height: circleSize + subHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: circleSize,
                height: circleSize,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(
                        color: scheme.primary, shape: BoxShape.circle)
                    : isPast && over
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border: Border(
                              bottom: BorderSide(
                                color:
                                    AppColors.warning.withValues(alpha: 0.55),
                                width: 2,
                              ),
                            ),
                          )
                        : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${info.day.day}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      color: isToday
                          ? scheme.onPrimary
                          : isPast
                              ? scheme.onSurface
                              : scheme.onSurface.withValues(alpha: 0.33),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: subHeight,
                child: sub == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            sub,
                            style: TextStyle(
                              fontFamily: isToday ? null : 'AssetAmount',
                              fontSize: 10.5,
                              fontWeight:
                                  isToday ? FontWeight.w700 : FontWeight.w800,
                              color: subColor,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
