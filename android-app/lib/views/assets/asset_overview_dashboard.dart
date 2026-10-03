import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/account/net_worth_snapshot.dart';
import '../../core/app_clock.dart';
import '../../core/assets/asset_overview_projection.dart';
import '../../core/money_cents.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/settings_ui.dart';
import '../common/app_sheet.dart';
import 'asset_overview_style.dart';

class AssetOverviewDashboard extends StatefulWidget {
  const AssetOverviewDashboard({
    super.key,
    required this.breakdown,
    required this.trend,
    required this.partial,
    required this.excludedCount,
  });

  final NetWorthBreakdown breakdown;
  final NetWorthTrendResult trend;
  final bool partial;
  final int excludedCount;

  @override
  State<AssetOverviewDashboard> createState() => _AssetOverviewDashboardState();
}

class _AssetOverviewDashboardState extends State<AssetOverviewDashboard> {
  AssetTrendRange _range = AssetTrendRange.all;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final projection = AssetOverviewProjection(
        source: widget.trend, range: _range, now: AppClock.now);
    final values = <AssetOverviewMetric, Decimal>{
      AssetOverviewMetric.netWorth: widget.breakdown.netWorth,
      AssetOverviewMetric.funds: widget.breakdown.cashAssets +
          widget.breakdown.investmentAssets +
          widget.breakdown.receivableAssets,
      AssetOverviewMetric.physical: widget.breakdown.physicalAssets,
      AssetOverviewMetric.total: widget.breakdown.totalAssets,
      AssetOverviewMetric.liabilities: widget.breakdown.totalLiabilities,
    };
    final labelStyle = AssetOverviewStyle.label(context);
    final minor = decimalToBudgetCents(widget.breakdown.netWorth);
    final delta =
        projection.delta(AssetOverviewMetric.netWorth, currentMinor: minor);
    final qualitySummary = [
      if (widget.partial) '部分金额待确认',
      if (widget.excludedCount > 0) '${widget.excludedCount} 项未计入',
      if (projection.trend.breaks.isNotEmpty) '趋势有断点',
    ].join(' · ');
    final changeLabel = Text(
      delta == null
          ? '区间变化暂不可比'
          : '区间变化 ${delta >= 0 ? '+' : ''}${_amount(budgetDecimalFromCents(delta)!)}',
      style: AppType.secondary(scheme).copyWith(fontFamily: 'Nunito'),
    );
    final rangeControl = Builder(
      builder: (anchor) => TextButton(
        key: const ValueKey('asset-trend-range'),
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface.withValues(alpha: 0.65),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => showIosMenu(anchor, [
          for (final range in AssetTrendRange.values)
            IosMenuItem(
              label: range.label,
              icon: CupertinoIcons.calendar,
              selected: range == _range,
              onTap: () => setState(() => _range = range),
            ),
        ]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_range.label, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          const Icon(CupertinoIcons.chevron_down, size: 12),
        ]),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('asset-net-worth-card'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: ShapeDecoration(
              color: AppColors.card(scheme),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: BorderSide(
                      color: AppColors.hairline(scheme), width: 0.5))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text('净资产',
                      key: const ValueKey('asset-net-worth-title'),
                      style: labelStyle)),
              Text('人民币', style: AppType.caption(scheme)),
              const SizedBox(width: 6),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  tooltip: '估算与数据说明',
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                  onPressed: () => _showExplanation(context, projection),
                  icon: const Icon(CupertinoIcons.info_circle),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            AssetOverviewAmount(widget.breakdown.netWorth,
                size: 41.75, weight: FontWeight.w800),
            const SizedBox(height: 6),
            if (MediaQuery.textScalerOf(context).scale(13) > 18)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                changeLabel,
                Align(alignment: Alignment.centerRight, child: rangeControl),
              ])
            else
              Row(children: [
                Expanded(child: changeLabel),
                const SizedBox(width: 8),
                rangeControl,
              ]),
            const SizedBox(height: 6),
            SizedBox(
                height: projection.trend.hasTrend
                    ? 184 +
                        math.max(
                                0,
                                MediaQuery.textScalerOf(context).scale(10) -
                                    10) *
                            4
                    : 72,
                child: AssetOverviewChart(
                    projection: projection,
                    metric: AssetOverviewMetric.netWorth,
                    color: kCatBlueGray,
                    axes: true)),
            if (qualitySummary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(qualitySummary, style: AppType.caption(scheme)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(15) > 22;
          final columns = largeText ? 1 : 2;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          final height = math.max(106.0, width * 3 / 5);
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final metric in AssetOverviewMetric.values
                .where((m) => m != AssetOverviewMetric.netWorth))
              SizedBox(
                  width: width,
                  child: _MetricCard(
                    metric: metric,
                    amount: values[metric]!,
                    projection: projection,
                    height: height,
                    width: width,
                    largeText: largeText,
                    labelStyle: labelStyle,
                  )),
          ]);
        }),
      ],
    );
  }

  void _showExplanation(BuildContext context, AssetOverviewProjection p) {
    final scheme = Theme.of(context).colorScheme;
    final missing = p.trend.points
        .where((point) => point.valuationCoverage.missingValuationCount > 0)
        .length;
    final messages = [
      '金额为已计入资产的人民币自动估算，区间变化不是投资收益率。',
      if (widget.partial) '当前部分金额待确认，请到「数据待完善」检查具体项目。',
      if (widget.excludedCount > 0) '${widget.excludedCount} 项未计入当前净资产。',
      if (missing > 0) '$missing 个历史快照估值待确认，不参与连线或比较，不能把补齐估值当作增长。',
      if (p.trend.breaks.isNotEmpty) '统计范围或数据质量变化处断开，不跨断点计算涨幅。',
      if (p.trend.points
          .any((point) => !point.lineage.currencyCoverage.isComplete))
        '部分外币未换算；仅在排除币种、统计范围和计算版本一致时比较已覆盖金额。',
    ];
    showBlurSheet<void>(context,
        child: Builder(
            builder: (sheetContext) => DecoratedBox(
                  decoration:
                      BoxDecoration(color: AppColors.sheetSurface(scheme)),
                  child: SingleChildScrollView(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SheetHeader(
                          title: '估算与数据说明',
                          onClose: () => Navigator.of(sheetContext).pop()),
                      Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final message in messages)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Text(message,
                                          style: AppType.secondary(scheme))),
                              ])),
                    ],
                  )),
                )));
  }
}

String _amount(Decimal value) => AssetOverviewStyle.amount(value);

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.metric,
      required this.amount,
      required this.projection,
      required this.height,
      required this.width,
      required this.largeText,
      required this.labelStyle});
  final AssetOverviewMetric metric;
  final Decimal amount;
  final AssetOverviewProjection projection;
  final double height;
  final double width;
  final bool largeText;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final minor = decimalToBudgetCents(amount);
    final change = projection.delta(metric, currentMinor: minor);
    final percent = projection.percentage(metric, currentMinor: minor);
    final color = switch (metric) {
      AssetOverviewMetric.physical => kCatGold,
      AssetOverviewMetric.liabilities => AppColors.warning,
      _ => kCatBlueGray,
    };
    return Container(
      key: ValueKey('asset-metric-${metric.name}'),
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: AppColors.card(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.hairline(scheme), width: 0.5),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(metric.label, style: labelStyle),
        const SizedBox(height: 4),
        SizedBox(
            width: double.infinity,
            child: AssetOverviewAmount(amount, size: 22.5)),
        SizedBox(height: largeText ? 12 : math.max(0, height - 106)),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
              child: Semantics(
            label: percent == null
                ? '区间估算变化不可比'
                : '区间估算${change! < 0 ? '下降' : change > 0 ? '上升' : '持平'} $percent，非收益率',
            child: ExcludeSemantics(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (percent != null)
                Icon(
                    change! < 0
                        ? Icons.arrow_downward
                        : change > 0
                            ? Icons.arrow_upward
                            : Icons.remove,
                    size: 12,
                    color: AssetOverviewStyle.labelColor(context)),
              Flexible(
                  child: Text(percent ?? '—',
                      style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature('ss01')],
                          color: AssetOverviewStyle.labelColor(context)))),
            ])),
          )),
          const SizedBox(width: 4),
          SizedBox(
              width: width >= 160 ? 64 : 40,
              height: 28,
              child: AssetOverviewChart(
                  projection: projection, metric: metric, color: color)),
        ]),
      ]),
    );
  }
}

class AssetOverviewChart extends StatelessWidget {
  const AssetOverviewChart(
      {super.key,
      required this.projection,
      required this.metric,
      required this.color,
      this.axes = false});
  final AssetOverviewProjection projection;
  final AssetOverviewMetric metric;
  final Color color;
  final bool axes;

  @override
  Widget build(BuildContext context) {
    final trend = projection.trend;
    if (!trend.hasTrend) {
      return Center(
          child: axes
              ? Text(trend.points.length > 1 ? '已有快照暂不可比' : '至少积累 2 个可比快照后显示趋势',
                  style: AppType.secondary(Theme.of(context).colorScheme))
              : const SizedBox.shrink());
    }
    final points = trend.segments.expand((s) => s.points).toList();
    final first = points.first.lineage.asOf;
    final last = points.last.lineage.asOf;
    final dates =
        points.map((p) => p.lineage.asOf.difference(first).inDays.toDouble());
    final maxX = math.max(1.0, dates.reduce(math.max));
    final amounts = points.map((p) => metric.minor(p.components) / 100);
    final low = amounts.reduce(math.min);
    final high = amounts.reduce(math.max);
    final padding =
        math.max((high - low) * 0.12, math.max(high.abs() * 0.01, 1.0));
    final scheme = Theme.of(context).colorScheme;
    final axisScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final crossesYear = first.year != last.year;
    final dateInterval = (maxX / (axisScale > 1.3 ? 1 : 3)).ceilToDouble();
    Widget dateTitle(double value, TitleMeta meta) {
      if (value != meta.min &&
          value != meta.max &&
          meta.max - value < dateInterval * 0.5) {
        return const SizedBox.shrink();
      }
      final date = DateTime(first.year, first.month, first.day + value.round());
      return SideTitleWidget(
          axisSide: meta.axisSide,
          fitInside:
              SideTitleFitInsideData.fromTitleMeta(meta, distanceFromEdge: 0),
          child: Text(
              '${crossesYear ? '${date.year}\n' : ''}${date.month}/${date.day}',
              style: AppType.caption(scheme).copyWith(fontSize: 10)));
    }

    return Semantics(
      image: true,
      label: '${metric.label}估算趋势，${points.length}个快照，'
          '${_dayLabel(first)}为${MoneyFormat.string(budgetDecimalFromCents(metric.minor(points.first.components))!)}人民币，'
          '${_dayLabel(last)}为${MoneyFormat.string(budgetDecimalFromCents(metric.minor(points.last.components))!)}人民币，'
          '${trend.breaks.length}处断点，'
          '${trend.points.any((point) => point.lineage.quality != NetWorthSnapshotQuality.available) ? '部分数据，' : ''}非收益率',
      child: ExcludeSemantics(
          child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: low - padding,
          maxY: high + padding,
          clipData: const FlClipData.all(),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
              show: axes,
              drawVerticalLine: false,
              horizontalInterval: (high - low + padding * 2) / 3,
              getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.hairline(scheme),
                  strokeWidth: 0.7,
                  dashArray: [3, 4])),
          lineTouchData: const LineTouchData(enabled: false),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: axes,
                    reservedSize:
                        math.max(25, axisScale * (crossesYear ? 28 : 14) + 8),
                    interval: dateInterval,
                    getTitlesWidget: dateTitle)),
            rightTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: axes,
                    reservedSize: 46 * axisScale,
                    interval: (high - low + padding * 2) / 3,
                    getTitlesWidget: (value, meta) {
                      final gap = (meta.max - meta.min) / 3;
                      if ((value != meta.max && meta.max - value < gap * 0.5) ||
                          (value != meta.min && value - meta.min < gap * 0.5)) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                          MoneyFormat.axisLabel(value, withSymbol: false),
                          style:
                              AppType.caption(scheme).copyWith(fontSize: 10));
                    })),
          ),
          lineBarsData: [
            for (final segment in trend.segments)
              LineChartBarData(
                spots: [
                  for (final p in segment.points)
                    FlSpot(p.lineage.asOf.difference(first).inDays.toDouble(),
                        metric.minor(p.components) / 100)
                ],
                isCurved: true,
                preventCurveOverShooting: true,
                color: color,
                barWidth: axes ? 2.2 : 1.8,
                isStrokeCapRound: true,
                dotData: FlDotData(
                    show: axes,
                    checkToShowDot: (spot, bar) => spot == bar.spots.last),
                belowBarData: BarAreaData(
                    show: axes,
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          color.withValues(alpha: 0.16),
                          color.withValues(alpha: 0)
                        ])),
              ),
          ],
        ),
        duration: Duration.zero,
      )),
    );
  }
}

String _dayLabel(DateTime day) => '${day.year}年${day.month}月${day.day}日';
