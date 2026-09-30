import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/app_clock.dart';
import '../core/models/cat_svg_icon.dart';
import '../core/models/category_seed.dart';
import '../core/models/transaction_record.dart';
import '../core/money_format.dart';
import '../core/statistics/monthly_pace.dart';
import '../core/statistics/statistics_engine.dart';

export '../core/statistics/monthly_pace.dart'
    show MonthlyPaceSample, computeMonthlyPaceSamples;
import '../theme/app_tokens.dart';
import '../theme/app_colors.dart';
import 'pressable_scale.dart';

const String _maskedMoneyText = '¥****';

class MonthlyPaceCard extends StatelessWidget {
  final List<TransactionRecord> records;
  final MonthlySummary summary;
  final int year;
  final int month;
  final bool isCurrentMonth;
  final bool maskAmounts;

  /// 紧凑模式（桌面小组件用）：只保留进度核心——截至今日/平均/本月/柱图，
  /// 省掉「分类与支出活动」列表（4x2 格子装不下，也是用户拍板的小组件形态）。
  final bool compact;
  final void Function(
    Set<String> categoryNames,
    DateTime start,
    DateTime end,
  )? onOpenAllExpenseActivity;

  const MonthlyPaceCard({
    super.key,
    required this.records,
    required this.summary,
    required this.year,
    required this.month,
    required this.isCurrentMonth,
    this.maskAmounts = false,
    this.compact = false,
    this.onOpenAllExpenseActivity,
  });

  void _openAllExpenseActivity(
    List<CategoryTotal> categories,
    int cutoffDay,
  ) {
    final callback = onOpenAllExpenseActivity;
    if (callback == null) return;
    final names = categories
        .where((c) => c.total > Decimal.zero)
        .map((c) => c.name)
        .toSet();
    if (names.isEmpty) return;
    callback(names, DateTime(year, month), DateTime(year, month, cutoffDay));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lastDay = DateTime(year, month + 1, 0).day;
    final today = AppClock.now;
    final cutoffDay = isCurrentMonth ? math.min(today.day, lastDay) : lastDay;
    final samples = computeMonthlyPaceSamples(
      records: records,
      year: year,
      month: month,
      isCurrentMonth: isCurrentMonth,
      now: today,
    );
    final current = samples.last.pace;

    // 07 D-STAT-010/011：和桌面小组件同一套规则（core/statistics/monthly_pace）：
    // 开始记账前的月不算，真实 0 月算，至少 2 个月才给平均。
    final avgResult = monthlyPaceAverage(samples);
    final average = avgResult?.average ?? Decimal.zero;
    // 翻到过去的月份不能再写「本月」。
    // 和周视图的「该周」一致；不用「8月」，免得和 X 轴的月份标签重复。
    final periodName = isCurrentMonth ? '本月' : '该月';
    final title = avgResult == null
        ? (current > Decimal.zero
            ? '截至 $month月$cutoffDay日，$periodName已有支出记录'
            : '截至 $month月$cutoffDay日，$periodName还没有支出')
        : '截至 $month月$cutoffDay日，$periodName支出与往常'
            '${monthlyPaceRelation(current, average)}';

    final topCategories = summary.expenseByCategory
        .where((c) => c.total > Decimal.zero)
        .take(3)
        .toList();

    return _SectionCard(
      title: '',
      solid: compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 紧凑模式（小组件）补一行头部：月份 + 统计入口提示，卡片不再光秃。
          if (compact) ...[
            Row(
              children: [
                Text(
                  '$month月',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '统计 ›',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                ),
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            thickness: 0.7,
            color: scheme.outlineVariant.withValues(alpha: 0.42),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _PaceMetric(
                label: '平均',
                amount: average,
                muted: avgResult == null,
                maskAmounts: maskAmounts,
                large: compact,
              ),
              const SizedBox(width: 42),
              _PaceMetric(
                label: periodName,
                amount: current,
                // 06：强调色用主色，不再写死系统蓝。
                color: Theme.of(context).colorScheme.primary,
                maskAmounts: maskAmounts,
                large: compact,
              ),
            ],
          ),
          SizedBox(height: compact ? 12 : 18),
          _PaceBarsChart(
            samples: samples,
            average: average,
            height: compact ? 104 : 166,
          ),
          if (!compact) ...[
            const SizedBox(height: 20),
            Text(
              '分类与支出活动',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface.withValues(alpha: 0.74),
                  ),
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 0.7,
              color: scheme.outlineVariant.withValues(alpha: 0.42),
            ),
            const SizedBox(height: 10),
            if (topCategories.isEmpty)
              Text(
                isCurrentMonth ? '本月还没有支出分类。' : '这个月没有支出分类。',
                style: AppType.secondary(scheme),
              )
            else ...[
              for (int i = 0; i < topCategories.length; i++) ...[
                _PaceCategoryRow(
                    item: topCategories[i], maskAmounts: maskAmounts),
                Divider(
                  height: 1,
                  thickness: 0.6,
                  indent: 42,
                  color: scheme.outlineVariant.withValues(alpha: 0.38),
                ),
              ],
              _PaceViewAllRow(
                onTap: onOpenAllExpenseActivity == null
                    ? null
                    : () => _openAllExpenseActivity(
                          summary.expenseByCategory,
                          cutoffDay,
                        ),
              ),
            ],
          ],
        ],
      ),
    );
  }

}

class _PaceMetric extends StatelessWidget {
  final String label;
  final Decimal amount;
  final Color? color;
  final bool muted;
  final bool maskAmounts;

  /// 小组件紧凑模式下指标数字加大加粗（卡片内容少，数字要撑起视觉重量）。
  final bool large;

  const _PaceMetric({
    required this.label,
    required this.amount,
    required this.maskAmounts,
    this.color,
    this.muted = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor =
        muted ? scheme.onSurfaceVariant.withValues(alpha: 0.62) : color;
    final labelColor = color ?? scheme.onSurface.withValues(alpha: 0.72);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          muted
              ? '--'
              : maskAmounts
                  ? _maskedMoneyText
                  : MoneyFormat.string(amount),
          style: TextStyle(
            fontSize: large ? 22 : 18,
            fontWeight: large ? FontWeight.w700 : FontWeight.w400,
            fontFamily: 'Nunito',
            color: effectiveColor ?? scheme.onSurface,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class _PaceBarsChart extends StatelessWidget {
  final List<MonthlyPaceSample> samples;
  final Decimal average;

  /// 整个柱图区总高（含底部月份标签）；小组件紧凑模式传小值。
  final double height;

  const _PaceBarsChart({
    required this.samples,
    required this.average,
    this.height = 166,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 06：本月那根柱和标签用主色（原来写死 #0A84FF 系统蓝）。
    final currentBlue = scheme.primary;
    final values = <double>[
      for (final s in samples) MoneyFormat.toDouble(s.full),
      for (final s in samples) MoneyFormat.toDouble(s.pace),
      MoneyFormat.toDouble(average),
    ];
    final maxValue = values.fold<double>(0.01, math.max);
    final chartHeight = height - 34.0;
    final averageTop =
        chartHeight * (1 - (MoneyFormat.toDouble(average) / maxValue));
    final averageLineTop = (average <= Decimal.zero ? chartHeight : averageTop)
        .clamp(16.0, chartHeight - 8.0)
        .toDouble();

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: averageLineTop,
            child: Container(
              height: 2.25,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            right: 0,
            top: (averageLineTop - 22).clamp(0.0, chartHeight - 20.0),
            child: Text(
              '平均',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
              ),
            ),
          ),
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final sample in samples)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: chartHeight,
                          width: 24,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _PaceBar(
                              sample: sample,
                              maxValue: maxValue,
                              height: chartHeight,
                              currentColor: currentBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sample.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: sample.current
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: sample.current
                                ? currentBlue
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaceBar extends StatelessWidget {
  final MonthlyPaceSample sample;
  final double maxValue;
  final double height;
  final Color currentColor;

  const _PaceBar({
    required this.sample,
    required this.maxValue,
    required this.height,
    required this.currentColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fullHeight = (MoneyFormat.toDouble(sample.full) / maxValue * height)
        .clamp(8.0, height);
    final paceHeight = (MoneyFormat.toDouble(sample.pace) / maxValue * height)
        .clamp(8.0, height);
    final fullColor = scheme.outlineVariant.withValues(alpha: 0.42);
    final paceColor = sample.current
        ? currentColor
        : scheme.onSurfaceVariant.withValues(alpha: 0.55);
    return SizedBox(
      width: 24,
      height: height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            width: 18,
            height: fullHeight,
            decoration: BoxDecoration(
              color: fullColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Container(
            width: 18,
            height: paceHeight,
            decoration: BoxDecoration(
              color: paceColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaceCategoryRow extends StatelessWidget {
  final CategoryTotal item;
  final bool maskAmounts;

  const _PaceCategoryRow({
    required this.item,
    required this.maskAmounts,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = _categoryKeyForName(item.name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          CatIcon(
            categoryKey: key ?? '',
            emoji: CategorySeed.emojiOf(key),
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            maskAmounts ? _maskedMoneyText : MoneyFormat.string(item.total),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'Nunito',
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 42,
            child: Text(
              '${(item.share * 100).round()}%',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                fontFamily: 'Nunito',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaceViewAllRow extends StatelessWidget {
  final VoidCallback? onTap;

  const _PaceViewAllRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onTap,
      pressedScale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '查看所有支出活动',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  /// 小组件渲染用：卡底不透明（半透明在花壁纸上可读性崩）。
  final bool solid;

  const _SectionCard(
      {required this.title, required this.child, this.solid = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: solid
            ? (scheme.brightness == Brightness.dark
                ? const Color(0xFF332F2C)
                : Colors.white)
            : AppColors.card(scheme),
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
          if (title.isNotEmpty) ...[
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

String? _categoryKeyForName(String name) {
  for (final seed in CategorySeed.all) {
    if (seed.nameZh == name) return seed.key;
  }
  return null;
}
