import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/account/net_worth_snapshot.dart';
import '../../core/account/net_worth_verified_checkpoint.dart';
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
    this.cashAccountCount = 0,
    this.physicalCount = 0,
    this.excludedPhysicalCount = 0,
    this.liabilityCount = 0,
    this.physicalPartial = false,
    this.lastVerifiedAt,
    this.verifiedComparison,
    this.onReview,
  });

  final NetWorthBreakdown breakdown;
  final NetWorthTrendResult trend;
  final bool partial;
  final int excludedCount;
  final int cashAccountCount;
  final int physicalCount;
  final int excludedPhysicalCount;
  final int liabilityCount;
  final bool physicalPartial;
  final DateTime? lastVerifiedAt;
  final NetWorthVerifiedCheckpointComparison? verifiedComparison;
  final VoidCallback? onReview;

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
    final labelStyle = AssetOverviewStyle.label(context);
    final minor = decimalToBudgetCents(widget.breakdown.netWorth);
    final delta =
        projection.delta(AssetOverviewMetric.netWorth, currentMinor: minor);
    final qualitySummary = [
      if (widget.partial) '部分金额待确认',
      if (widget.excludedCount > 0) '${widget.excludedCount} 项未计入',
      if (projection.trend.breaks.isNotEmpty) '趋势有断点',
    ].join(' · ');
    final verified = widget.verifiedComparison;
    final verifiedChange = verified?.change;
    final changeLabel = widget.lastVerifiedAt == null && verifiedChange == null
        ? Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
                Text('还没有完整核对', style: AppType.secondary(scheme)),
                if (widget.onReview != null)
                  GestureDetector(
                    onTap: widget.onReview,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('去核对 ›',
                          style: AppType.secondary(scheme)
                              .copyWith(color: scheme.primary)),
                    ),
                  ),
              ])
        : Text.rich(
            TextSpan(children: [
              if (verifiedChange != null) ...[
                TextSpan(
                  text:
                      '${verifiedChange.netWorthDeltaMinor >= 0 ? '↑ ' : '↓ '}'
                      '${_amount(budgetDecimalFromCents(verifiedChange.netWorthDeltaMinor)!).replaceFirst('-', '')}  ',
                  style: const TextStyle(
                      fontFamily: 'Nunito', fontWeight: FontWeight.w700),
                ),
                TextSpan(
                    text:
                        '两次完整核对 · ${_shortDay(verified!.earlier.header.asOf.toLocal())}'),
              ] else
                TextSpan(
                    text:
                        '上次完整核对 · ${_shortDay(widget.lastVerifiedAt!.toLocal())}'),
            ]),
            style: AppType.secondary(scheme));
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
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(
              color: AppColors.card(scheme),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
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
            const SizedBox(height: 4),
            AssetOverviewAmount(widget.breakdown.netWorth,
                size: 40, weight: FontWeight.w800),
            const SizedBox(height: 4),
            if (MediaQuery.textScalerOf(context).scale(13) > 18)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                changeLabel,
                if (projection.trend.hasTrend)
                  Align(alignment: Alignment.centerRight, child: rangeControl),
              ])
            else
              Row(children: [
                Expanded(child: changeLabel),
                if (projection.trend.hasTrend) ...[
                  const SizedBox(width: 8),
                  rangeControl,
                ],
              ]),
            const SizedBox(height: 10),
            if (projection.trend.hasTrend) ...[
              SizedBox(
                height: 78 +
                    math.max(
                        0, MediaQuery.textScalerOf(context).scale(11) - 11),
                child: AssetOverviewChart(
                    projection: projection,
                    metric: AssetOverviewMetric.netWorth,
                    color: scheme.primary,
                    axes: true,
                    compact: true),
              ),
              if (widget.partial || projection.trend.breaks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(delta == null ? '估算趋势有缺口，区间暂不可比' : '估算趋势，非投资收益',
                      style: AppType.caption(scheme)),
                ),
            ] else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: AppColors.inputFill(scheme),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(CupertinoIcons.chart_bar,
                      size: 15, color: AssetOverviewStyle.labelColor(context)),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(
                          projection.trend.points.length > 1
                              ? '已有快照暂不可比'
                              : '至少积累 2 个可比快照后显示趋势',
                          style: AppType.caption(scheme))),
                ]),
              ),
            const SizedBox(height: 14),
            Divider(
                height: 0.5, thickness: 0.5, color: AppColors.hairline(scheme)),
            const SizedBox(height: 14),
            _OverviewStrip(
              breakdown: widget.breakdown,
              cashAccountCount: widget.cashAccountCount,
              physicalCount: widget.physicalCount,
              excludedPhysicalCount: widget.excludedPhysicalCount,
              liabilityCount: widget.liabilityCount,
              physicalPartial: widget.physicalPartial,
            ),
            if (qualitySummary.isNotEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _showExplanation(context, projection),
                child: Row(children: [
                  Icon(CupertinoIcons.info_circle,
                      size: 14, color: AssetOverviewStyle.labelColor(context)),
                  const SizedBox(width: 5),
                  Expanded(
                      child:
                          Text(qualitySummary, style: AppType.caption(scheme))),
                  Text('查看 ›',
                      style: AppType.caption(scheme)
                          .copyWith(color: scheme.primary)),
                ]),
              ),
            ],
          ]),
        ),
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
String _shortDay(DateTime date) => '${date.month}月${date.day}日';

class _OverviewStrip extends StatelessWidget {
  const _OverviewStrip(
      {required this.breakdown,
      required this.cashAccountCount,
      required this.physicalCount,
      required this.excludedPhysicalCount,
      required this.liabilityCount,
      required this.physicalPartial});
  final NetWorthBreakdown breakdown;
  final int cashAccountCount;
  final int physicalCount;
  final int excludedPhysicalCount;
  final int liabilityCount;
  final bool physicalPartial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final values = [
      (
        'funds',
        '可动用资金',
        breakdown.cashAssets,
        breakdown.investmentAssets > Decimal.zero
            ? '另有投资 ${_amount(breakdown.investmentAssets)}'
            : '$cashAccountCount 个账户',
        false
      ),
      (
        'physical',
        '计入物品',
        breakdown.physicalAssets,
        physicalPartial
            ? '估值待确认'
            : physicalCount == 0 && excludedPhysicalCount > 0
                ? '$excludedPhysicalCount 件 · 未计入'
                : '$physicalCount 件',
        physicalPartial &&
            physicalCount > 0 &&
            breakdown.physicalAssets == Decimal.zero
      ),
      (
        'liabilities',
        '总负债',
        breakdown.totalLiabilities,
        '$liabilityCount 项',
        false
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = MediaQuery.textScalerOf(context).scale(12) > 17 ||
          constraints.maxWidth < 270;
      Widget metric(int index) {
        final (key, label, amount, caption, unknown) = values[index];
        return Container(
          key: ValueKey('asset-metric-$key'),
          padding: stacked
              ? EdgeInsets.only(top: index == 0 ? 0 : 12)
              : EdgeInsets.only(
                  left: index == 0 ? 0 : 8, right: index == 2 ? 0 : 8),
          decoration: BoxDecoration(
              border: !stacked && index > 0
                  ? Border(
                      left: BorderSide(
                          color: AppColors.hairline(scheme), width: 0.5))
                  : null),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style:
                    AssetOverviewStyle.label(context).copyWith(fontSize: 12)),
            const SizedBox(height: 3),
            if (unknown)
              Text('—',
                  style: TextStyle(
                      fontFamily: 'AssetAmount',
                      fontSize: 16.5,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface))
            else
              SizedBox(
                  width: double.infinity,
                  child: AssetOverviewAmount(amount, size: 16.5)),
            const SizedBox(height: 3),
            Text(caption,
                style: AppType.caption(scheme).copyWith(fontSize: 11)),
          ]),
        );
      }

      return stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (var i = 0; i < values.length; i++) metric(i)])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < values.length; i++) Expanded(child: metric(i))
            ]);
    });
  }
}

class AssetOverviewChart extends StatelessWidget {
  const AssetOverviewChart(
      {super.key,
      required this.projection,
      required this.metric,
      required this.color,
      this.axes = false,
      this.compact = false});
  final AssetOverviewProjection projection;
  final AssetOverviewMetric metric;
  final Color color;
  final bool axes;
  final bool compact;

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

    final chart = LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: low - padding,
          maxY: high + padding,
          // Compact endpoints sit on the plot edge; the padded Y range contains them.
          clipData: compact ? const FlClipData.none() : const FlClipData.all(),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
              show: axes && !compact,
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
                    showTitles: axes && !compact,
                    reservedSize:
                        math.max(25, axisScale * (crossesYear ? 28 : 14) + 8),
                    interval: dateInterval,
                    getTitlesWidget: dateTitle)),
            rightTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: axes && !compact,
                    reservedSize: 46 * axisScale,
                    interval: (high - low + padding * 2) / 3,
                    getTitlesWidget: (value, meta) => Text(
                        MoneyFormat.axisLabel(value, withSymbol: false),
                        style:
                            AppType.caption(scheme).copyWith(fontSize: 10)))),
          ),
          lineBarsData: [
            for (final segment in trend.segments)
              LineChartBarData(
                spots: [
                  for (final p in segment.points)
                    FlSpot(p.lineage.asOf.difference(first).inDays.toDouble(),
                        metric.minor(p.components) / 100)
                ],
                isCurved: !compact,
                preventCurveOverShooting: true,
                color: color,
                barWidth: compact
                    ? 2
                    : axes
                        ? 2.2
                        : 1.8,
                isStrokeCapRound: true,
                dotData: FlDotData(
                    show: compact,
                    checkToShowDot: (spot, data) => spot.x == maxX),
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
        duration: Duration.zero);
    return Semantics(
      image: true,
      label: '${metric.label}估算趋势，${points.length}个快照，'
          '${_dayLabel(first)}为${MoneyFormat.string(budgetDecimalFromCents(metric.minor(points.first.components))!)}人民币，'
          '${_dayLabel(last)}为${MoneyFormat.string(budgetDecimalFromCents(metric.minor(points.last.components))!)}人民币，'
          '${trend.breaks.length}处断点，'
          '${trend.points.any((point) => point.lineage.quality != NetWorthSnapshotQuality.available) ? '部分数据，' : ''}非收益率',
      child: ExcludeSemantics(
          child: compact
              ? Column(children: [
                  Expanded(child: chart),
                  const SizedBox(height: 2),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            '${crossesYear ? '${first.year}/' : ''}${first.month}/${first.day}',
                            style:
                                AppType.caption(scheme).copyWith(fontSize: 11)),
                        Text(
                            '${crossesYear ? '${last.year}/' : ''}${last.month}/${last.day}',
                            style:
                                AppType.caption(scheme).copyWith(fontSize: 11)),
                      ])
                ])
              : chart),
    );
  }
}

String _dayLabel(DateTime day) => '${day.year}年${day.month}月${day.day}日';
