import 'package:flutter/material.dart';

import '../../core/budget/budget_rule_display.dart';
import '../../core/budget/budget_rule_engine.dart';
import '../../core/budget/budget_rules.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/budget_progress.dart';
import 'budget_calendar_card.dart' show BudgetCard;

/// 预算页顶部大数字卡（docs/08 §6.8 第 2 块）。
class BudgetHeroCard extends StatelessWidget {
  final BudgetMonthResult month;
  final DateTime today;

  /// 近 3 个自然月平均支出（取整到百，分）；没有记录时为 null。
  final int? suggestionCents;

  /// 下个月会用的结余方式（过去的月份写「已留给 X月」用）。
  final BudgetRolloverMode nextMonthMode;
  final VoidCallback onCreate;

  const BudgetHeroCard({
    super.key,
    required this.month,
    required this.today,
    required this.suggestionCents,
    required this.nextMonthMode,
    required this.onCreate,
  });

  int get _monthIndex => month.year * 12 + month.month - 1;
  int get _todayIndex => today.year * 12 + today.month - 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BudgetCard(
      key: const ValueKey('budget-hero-card'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: !month.hasRules
            ? _empty(context, scheme)
            : _monthIndex < _todayIndex
                ? _past(scheme)
                : _monthIndex > _todayIndex
                    ? _future(scheme)
                    : _current(scheme),
      ),
    );
  }

  Widget _big(String text, ColorScheme scheme, {Color? color}) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          key: const ValueKey('budget-hero-amount'),
          maxLines: 1,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 44,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            height: 1.1,
            color: color ?? scheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );

  Widget _bar(ColorScheme scheme) {
    final effective = month.effectiveCents;
    final spent = month.spentCents;
    final ratio = effective <= 0 ? (spent > 0 ? 1.0 : 0.0) : spent / effective;
    final overflowStart = spent > effective && spent > 0
        ? (effective / spent).clamp(0.0, 1.0)
        : null;
    final today = month.today;
    final plannedRatio = today == null || effective <= 0
        ? null
        : (today.plannedBeforeTodayCents / effective).clamp(0.0, 1.0);
    return SizedBox(
      height: 18,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          BudgetProgressBar(
            value: ratio.clamp(0.0, 1.0).toDouble(),
            height: 10,
            overflowStart: overflowStart?.toDouble(),
          ),
          // 细竖线：按计划到今天该花到哪。
          if (plannedRatio != null && overflowStart == null)
            Align(
              alignment: Alignment(plannedRatio * 2 - 1, 0),
              child: Container(
                key: const ValueKey('budget-hero-plan-mark'),
                width: 2,
                height: 18,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _caption(ColorScheme scheme) => SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              '已花 ${budgetYuanText(month.spentCents)}',
              key: const ValueKey('budget-hero-spent-caption'),
              style: AppType.caption(scheme),
            ),
            Text(
              '${month.month}月预算 ${budgetYuanText(month.budgetCents)}',
              key: const ValueKey('budget-hero-budget-caption'),
              style: AppType.caption(scheme),
            ),
          ],
        ),
      );

  /// 开了结转时多一行说明带进来多少。
  Widget? _carryLine(ColorScheme scheme) {
    final carry = month.carryInCents;
    if (carry == 0) return null;
    final prev = month.month == 1 ? 12 : month.month - 1;
    final text = carry > 0
        ? '${month.month}月预算 ${budgetYuanText(month.budgetCents)} + $prev月省下 ${budgetYuanText(carry)}'
        : '$prev月超出的 ${budgetYuanText(-carry)} 从这个月扣';
    return Text(text, style: AppType.secondary(scheme));
  }

  Widget _label(String text, ColorScheme scheme) => Text(
        text,
        key: const ValueKey('budget-hero-label'),
        style: AppType.secondary(scheme),
      );

  List<Widget> _empty(BuildContext context, ColorScheme scheme) {
    if (_monthIndex < _todayIndex) {
      return [
        _label('${month.month}月', scheme),
        const SizedBox(height: 6),
        Text('这个月没有设预算', style: AppType.rowTitle(scheme)),
      ];
    }
    final suggestion = suggestionCents;
    return [
      Text('给这个月定个小目标吧', style: AppType.rowTitle(scheme)),
      const SizedBox(height: 6),
      Text(
        suggestion == null
            ? '先定一个每月能花多少，之后每天都能看到还剩多少'
            : '近 3 个月平均每月花 ${budgetYuanText(suggestion)}，可以从这个数开始',
        style: AppType.secondary(scheme),
      ),
      const SizedBox(height: 14),
      AppPillButton(
        key: const ValueKey('budget-hero-create'),
        label: '设个预算',
        onPressed: onCreate,
      ),
    ];
  }

  List<Widget> _past(ColorScheme scheme) {
    final result = month.remainingCents;
    final next = month.month == 12 ? 1 : month.month + 1;
    final saved = result >= 0;
    String? handoff;
    if (saved && result > 0 && nextMonthMode != BudgetRolloverMode.reset) {
      handoff = '已留给 $next月';
    } else if (!saved && nextMonthMode == BudgetRolloverMode.carryBoth) {
      handoff = '已从 $next月扣';
    }
    return [
      _label(
        saved ? '${month.month}月顺利收官，省下' : '${month.month}月超出',
        scheme,
      ),
      const SizedBox(height: 2),
      _big(
        budgetYuanText(budgetFloorYuanCents(result.abs())),
        scheme,
        color: saved ? null : AppColors.warning,
      ),
      if (handoff != null) ...[
        const SizedBox(height: 4),
        Text(handoff, style: AppType.secondary(scheme)),
      ],
      const SizedBox(height: 12),
      _bar(scheme),
      const SizedBox(height: 6),
      _caption(scheme),
    ];
  }

  List<Widget> _future(ColorScheme scheme) => [
        _label('${month.month}月预算', scheme),
        const SizedBox(height: 2),
        _big(budgetYuanText(month.budgetCents), scheme),
        const SizedBox(height: 4),
        Text('到时候按下面的规则来', style: AppType.secondary(scheme)),
      ];

  List<Widget> _current(ColorScheme scheme) {
    final remaining = month.remainingCents;
    final effective = month.effectiveCents;
    final over = remaining < 0 && effective >= 0;
    final today = month.today;
    final todayCovered = month.days.any(
      (d) => d.covered && d.day.day == this.today.day,
    );
    String? todayLine;
    if (today != null) {
      final days = '还剩 ${today.remainingDays} 天';
      if (!todayCovered) {
        todayLine = '今天没有预算 · $days';
      } else if (today.leftTodayCents >= 0) {
        todayLine = '今天约 ${budgetYuanText(today.leftTodayCents)} · $days';
      } else {
        todayLine = '今天多花了 ${budgetYuanText(-today.leftTodayCents)} · $days';
      }
    }
    final prev = month.month == 1 ? 12 : month.month - 1;
    final pace = budgetPaceText(month);
    final carryLine = _carryLine(scheme);
    return [
      _label(over ? '${month.month}月超出' : '${month.month}月还能花', scheme),
      const SizedBox(height: 2),
      _big(
        budgetYuanText(
          over
              ? budgetFloorYuanCents(-remaining)
              : budgetLeftDisplayCents(remaining),
        ),
        scheme,
        color: over ? AppColors.warning : null,
      ),
      if (todayLine != null) ...[
        const SizedBox(height: 4),
        _todayText(todayLine, scheme),
      ],
      if (carryLine != null) ...[const SizedBox(height: 2), carryLine],
      if (effective < 0) ...[
        const SizedBox(height: 2),
        Text(
          '$prev月超出的还有 ${budgetYuanText(-effective)} 没扣完，这个月先省着点',
          style: AppType.secondary(scheme).copyWith(color: AppColors.warning),
        ),
      ],
      const SizedBox(height: 12),
      _bar(scheme),
      const SizedBox(height: 6),
      _caption(scheme),
      if (pace.text.isNotEmpty && todayCovered) ...[
        const SizedBox(height: 10),
        _pill(pace.text, pace.warning, scheme),
      ],
    ];
  }

  /// 「今天约 **¥140** · 还剩 13 天」：金额加粗，整行比说明文字深一档。
  Widget _todayText(String line, ColorScheme scheme) {
    final base = TextStyle(
      fontSize: 15,
      height: 1.4,
      color: scheme.onSurface.withValues(alpha: 0.72),
    );
    final match = RegExp(r'¥[\d,]+').firstMatch(line);
    return Text.rich(
      key: const ValueKey('budget-hero-today'),
      match == null
          ? TextSpan(text: line)
          : TextSpan(children: [
              TextSpan(text: line.substring(0, match.start)),
              TextSpan(
                text: match.group(0),
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              TextSpan(text: line.substring(match.end)),
            ]),
      style: base,
    );
  }

  Widget _pill(String text, bool warning, ColorScheme scheme) {
    final color = warning ? AppColors.warning : AppColors.budgetHealthy(scheme);
    // 字色比底色深一档，浅底上才读得清（同色相，不引入新颜色）。
    final textColor = scheme.brightness == Brightness.dark
        ? color
        : Color.lerp(color, Colors.black, 0.32)!;
    return Container(
      key: const ValueKey('budget-hero-pace'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: AppType.secondary(scheme).copyWith(
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
