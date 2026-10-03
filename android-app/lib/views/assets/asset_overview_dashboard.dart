import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
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
    final labelStyle = TextStyle(
      fontFamily: 'AssetLabels',
      fontSize: 15,
      height: 1.35,
      fontWeight: FontWeight.w400,
      fontVariations: const [FontVariation('wght', 450)],
      color: scheme.onSurface.withValues(alpha: 0.65),
    );
    final minor = decimalToBudgetCents(widget.breakdown.netWorth);
    final delta =
        projection.delta(AssetOverviewMetric.netWorth, currentMinor: minor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('asset-net-worth-card'),
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
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
            ]),
            const SizedBox(height: 8),
            _Amount(widget.breakdown.netWorth,
                size: 38, weight: FontWeight.w700),
            const SizedBox(height: 6),
            Text(
              delta == null
                  ? '区间变化暂不可比'
                  : '区间变化 ${delta >= 0 ? '+' : '-'}${_amount(budgetDecimalFromCents(delta.abs())!)}',
              style: AppType.secondary(scheme).copyWith(fontFamily: 'Nunito'),
            ),
            if (widget.partial || widget.excludedCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                  [
                    if (widget.partial) '部分金额待确认',
                    if (widget.excludedCount > 0)
                      '${widget.excludedCount} 项未计入',
                  ].join(' · '),
                  style: AppType.caption(scheme)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('自动估算', style: AppType.caption(scheme))),
              Builder(
                  builder: (anchor) => TextButton(
                        key: const ValueKey('asset-trend-range'),
                        style: TextButton.styleFrom(
                            foregroundColor:
                                scheme.onSurface.withValues(alpha: 0.65),
                            padding: const EdgeInsets.symmetric(horizontal: 4)),
                        onPressed: () => showIosMenu(anchor, [
                          for (final range in AssetTrendRange.values)
                            IosMenuItem(
                                label: range.label,
                                icon: Icons.calendar_today_outlined,
                                selected: range == _range,
                                onTap: () => setState(() => _range = range)),
                        ]),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(_range.label,
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down, size: 15)
                        ]),
                      )),
            ]),
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
            if (projection.trend.breaks.isNotEmpty)
              Text('统计范围或数据质量变化处断开', style: AppType.caption(scheme)),
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
}

String _amount(Decimal value) =>
    MoneyFormat.string(value).replaceAll('¥', '').trim();

class _Amount extends StatelessWidget {
  const _Amount(this.value, {required this.size, required this.weight});
  final Decimal value;
  final double size;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${_amount(value)} 人民币',
        child: ExcludeSemantics(
            child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_amount(value),
              style: TextStyle(
                  fontFamily: size == 28 ? 'AssetAmount' : 'Nunito',
                  fontSize: size,
                  height: size == 28 ? 1 : 1.1,
                  fontWeight: weight,
                  color: value < Decimal.zero
                      ? AppColors.warning
                      : Theme.of(context).colorScheme.onSurface)),
        )),
      );
}

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
      padding: const EdgeInsets.all(12),
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
            child: _Amount(amount, size: 28, weight: FontWeight.w800)),
        SizedBox(height: largeText ? 12 : math.max(2, height - 104.25)),
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
                    color: scheme.onSurface.withValues(alpha: 0.65)),
              Flexible(
                  child: Text(percent ?? '—',
                      style: labelStyle.copyWith(
                          fontSize: 12.5,
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w600))),
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
    Widget dateTitle(double value, TitleMeta meta) {
      final date = DateTime(first.year, first.month, first.day + value.round());
      return SideTitleWidget(
          axisSide: meta.axisSide,
          fitInside:
              SideTitleFitInsideData.fromTitleMeta(meta, distanceFromEdge: 0),
          child: Text('${date.month}/${date.day}',
              style: AppType.caption(scheme).copyWith(fontSize: 10)));
    }

    return Semantics(
      image: true,
      label:
          '${metric.label}估算趋势，${points.length}个快照，${trend.breaks.length}处断点，非收益率',
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
                    reservedSize: math.max(25, axisScale * 14 + 8),
                    interval: maxX / (axisScale > 1.3 ? 1 : 3),
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
