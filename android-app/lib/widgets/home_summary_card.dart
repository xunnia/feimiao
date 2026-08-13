import 'package:decimal/decimal.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/budget/budget_engine.dart';
import '../core/money_format.dart';
import '../core/statistics/statistics_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'animated_money.dart';
import 'budget_progress.dart';
import 'glass.dart';
import 'mascot.dart';

const String _maskedMoneyText = '¥****';

// Both peeking mascot PNGs keep about 1.8 logical pixels of transparent
// padding on the right at 96dp high. Bleed the image box by 4dp so the drawn
// outline overlaps the card edge instead of leaving an anti-aliased seam.
const double _homeMascotRightBleed = 4;

class HomeSummaryCard extends StatelessWidget {
  final double topChrome;
  final DateTime monthDate;
  final bool isCurrentMonth;
  final MonthlySummary summary;
  final BudgetStatus? budgetStatus;
  final Decimal? budget;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;
  final VoidCallback? onPickMonth;
  final VoidCallback? onJumpCurrent;
  final VoidCallback? onStatsTap;
  final VoidCallback? onOpenBudgetSettings;
  final bool maskAmounts;

  /// 桌面小组件渲染专用：去掉左右/底部外边距（贴边渲染才能铺满格子宽度）、
  /// 卡底改不透明纯色（半透明卡在花壁纸上可读性崩，用户点名取消）。
  /// App 内不要传。
  final bool compact;

  const HomeSummaryCard({
    super.key,
    this.topChrome = 0,
    required this.monthDate,
    required this.isCurrentMonth,
    required this.summary,
    required this.budgetStatus,
    required this.budget,
    this.onPrevMonth,
    this.onNextMonth,
    this.onPickMonth,
    this.onJumpCurrent,
    this.onStatsTap,
    this.onOpenBudgetSettings,
    this.maskAmounts = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOverspend = budgetStatus?.isOverBudget ?? false;
    final solidCard = scheme.brightness == Brightness.dark
        ? const Color(0xFF332F2C)
        : Colors.white;

    return Padding(
      padding: compact
          ? EdgeInsets.fromLTRB(0, topChrome + 8, 0, 0)
          : EdgeInsets.fromLTRB(16, topChrome + 8, 16, 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GlassSurface(
            key: const ValueKey('home-summary-card-surface'),
            radius: 20,
            blur: 0,
            fillColor: compact ? solidCard : AppColors.card(scheme),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _MonthSelectorPill(
                        monthDate: monthDate,
                        isCurrentMonth: isCurrentMonth,
                        onPrev: onPrevMonth,
                        onNext: onNextMonth,
                        onPick: onPickMonth,
                        onJumpCurrent: onJumpCurrent,
                      ),
                      const SizedBox(width: 8),
                      _StatsBadge(onTap: onStatsTap),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (budgetStatus != null && budget != null)
                    _BudgetBody(
                      summary: summary,
                      budgetStatus: budgetStatus!,
                      budget: budget!,
                      isCurrentMonth: isCurrentMonth,
                      maskAmounts: maskAmounts,
                    )
                  else
                    _KapiIncomeExpenseOverview(
                      summary: summary,
                      maskAmounts: maskAmounts,
                      onOpenBudgetSettings: onOpenBudgetSettings,
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -8,
            right: -_homeMascotRightBleed,
            child: IgnorePointer(
              key: const ValueKey('home-summary-mascot-anchor'),
              child: MascotBreath(
                bob: 2.0,
                sway: 0,
                alignment: Alignment.centerRight,
                child: Image.asset(
                  'assets/mascot/${isOverspend ? 'overspend' : 'idle'}.webp',
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

class _MonthSelectorPill extends StatelessWidget {
  final DateTime monthDate;
  final bool isCurrentMonth;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onPick;
  final VoidCallback? onJumpCurrent;

  const _MonthSelectorPill({
    required this.monthDate,
    required this.isCurrentMonth,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onJumpCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: isCurrentMonth ? null : onJumpCurrent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 220) {
          onPrev?.call();
        } else if (velocity < -220 && !isCurrentMonth) {
          onNext?.call();
        }
      },
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 28,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPick,
            onLongPress: isCurrentMonth ? null : onJumpCurrent,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${monthDate.year}年${monthDate.month}月',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurface,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    CupertinoIcons.chevron_down,
                    size: 12,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.82),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsBadge extends StatelessWidget {
  final VoidCallback? onTap;

  const _StatsBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.only(left: 9, right: 7),
        decoration: BoxDecoration(
          color: AppColors.card(scheme),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.28),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '统计',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.82),
                  ),
            ),
            const SizedBox(width: 2),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 11,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomeExpenseRow extends StatelessWidget {
  final MonthlySummary summary;
  final bool maskAmounts;

  const _IncomeExpenseRow({
    required this.summary,
    required this.maskAmounts,
  });

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
            alignment: CrossAxisAlignment.start,
            maskAmounts: maskAmounts,
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
            alignment: CrossAxisAlignment.start,
            maskAmounts: maskAmounts,
          ),
        ),
      ],
    );
  }
}

class _KapiIncomeExpenseOverview extends StatelessWidget {
  final MonthlySummary summary;
  final bool maskAmounts;
  final VoidCallback? onOpenBudgetSettings;

  const _KapiIncomeExpenseOverview({
    required this.summary,
    required this.maskAmounts,
    required this.onOpenBudgetSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final balance = summary.balance;
    final balanceColor =
        balance < Decimal.zero ? AppColors.warning : scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _KapiMoneyColumn(
                label: '支出',
                amount: summary.totalExpense,
                color: scheme.onSurface,
                maskAmounts: maskAmounts,
              ),
            ),
            Container(
              width: 1,
              height: 42,
              color: scheme.outlineVariant.withValues(alpha: 0.42),
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            ),
            Expanded(
              child: _KapiMoneyColumn(
                label: '收入',
                amount: summary.totalIncome,
                color: AppColors.income(scheme),
                maskAmounts: maskAmounts,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Text(
              '结余 ${_moneyText(balance, maskAmounts)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: balanceColor.withValues(alpha: 0.72),
                fontWeight: FontWeight.w400,
                fontFamily: 'Nunito',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenBudgetSettings,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '设置预算',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 11,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KapiMoneyColumn extends StatelessWidget {
  final String label;
  final Decimal amount;
  final Color color;
  final bool maskAmounts;

  const _KapiMoneyColumn({
    required this.label,
    required this.amount,
    required this.color,
    required this.maskAmounts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.headlineSmall?.copyWith(
      fontSize: 23,
      fontWeight: FontWeight.w500,
      color: color,
      fontFamily: 'Nunito',
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppTextColor.hint(scheme),
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 4),
        _AmountText(
          value: amount,
          style: style,
          maskAmounts: maskAmounts,
          animated: !maskAmounts,
        ),
      ],
    );
  }
}

class _BudgetBody extends StatelessWidget {
  final MonthlySummary summary;
  final BudgetStatus budgetStatus;
  final Decimal budget;
  final bool isCurrentMonth;
  final bool maskAmounts;

  const _BudgetBody({
    required this.summary,
    required this.budgetStatus,
    required this.budget,
    required this.isCurrentMonth,
    required this.maskAmounts,
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
    final pct = rawRatio > 1.0
        ? '100%+'
        : rawRatio < 0.0
            ? '0.0%'
            : '${(rawRatio * 100).toStringAsFixed(1)}%';

    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final remainingDays = daysInMonth - now.day + 1;

    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
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
        _AmountText(
          value: remaining.abs(),
          prefix: over ? '-' : '',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
            fontFamily: 'Nunito',
            color: over ? AppColors.warning : scheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maskAmounts: maskAmounts,
          animated: !maskAmounts,
        ),
        const SizedBox(height: AppSpacing.md),
        _IncomeExpenseRow(summary: summary, maskAmounts: maskAmounts),
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
                pct,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Nunito',
                ),
              ),
            ),
            const Spacer(),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _moneyText(budget, maskAmounts),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppTextColor.secondary(scheme),
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Nunito',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (isCurrentMonth)
                    TextSpan(
                      text: ' · 剩 $remainingDays 天',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTextColor.hint(scheme),
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

    final String ringLabel;
    final String ringText;
    final double ringVal;
    final Color ringColor;
    // 只有一次性区间预算（无循环周期）时窗口结果没有日度引导，
    // spentToday/todayAllowance 只是 0 占位——此时画「今日可用 ¥0.00」
    // 满环是误导，退回和历史月一样的「已用 %」圆环。
    if (isCurrentMonth && s.hasDailyGuidance) {
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
      ringColor =
          todayNeg ? AppColors.warning : AppColors.budgetHealthy(scheme);
      ringLabel = '今日可用';
      ringText = maskAmounts
          ? _maskedMoneyText
          : (todayNeg
              ? '-${MoneyFormat.string(today.abs())}'
              : MoneyFormat.string(today));
    } else {
      ringVal = ratio;
      ringColor = over ? AppColors.warning : AppColors.budgetHealthy(scheme);
      ringLabel = '已用';
      ringText = pct;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: leftColumn),
        const SizedBox(width: 14),
        Transform.translate(
          offset: const Offset(0, 8),
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

class _BudgetBar extends StatelessWidget {
  final double ratio;

  const _BudgetBar({required this.ratio});

  @override
  Widget build(BuildContext context) {
    return BudgetProgressBar(value: ratio);
  }
}

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
            child: BudgetProgressRing(
              value: value,
              strokeWidth: 7,
              activeColor: color,
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
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Nunito',
                  color: scheme.onSurface,
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

class _SummaryMetric extends StatelessWidget {
  final String label;
  final Decimal amount;
  final Color color;
  final CrossAxisAlignment alignment;
  final bool maskAmounts;

  const _SummaryMetric({
    required this.label,
    required this.amount,
    required this.color,
    required this.maskAmounts,
    this.alignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: alignment,
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
          _moneyText(amount, maskAmounts),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w400,
            color: color,
            fontFamily: 'Nunito',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _AmountText extends StatelessWidget {
  final Decimal value;
  final String prefix;
  final TextStyle? style;
  final bool maskAmounts;
  final bool animated;

  const _AmountText({
    required this.value,
    required this.style,
    required this.maskAmounts,
    this.prefix = '',
    this.animated = true,
  });

  @override
  Widget build(BuildContext context) {
    if (maskAmounts) {
      return Text(
        _maskedMoneyText,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (animated) {
      return AnimatedMoney(value: value, prefix: prefix, style: style);
    }
    return Text(
      '$prefix${MoneyFormat.string(value)}',
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

String _moneyText(Decimal amount, bool maskAmounts) =>
    maskAmounts ? _maskedMoneyText : MoneyFormat.string(amount);
