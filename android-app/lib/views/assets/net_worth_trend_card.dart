import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/account/net_worth_snapshot.dart';
import '../../core/budget/budget_window_resolver.dart';
import '../../core/money_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/settings_ui.dart';

class NetWorthEstimatedTrendCard extends StatelessWidget {
  final NetWorthTrendResult trend;

  const NetWorthEstimatedTrendCard({super.key, required this.trend});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final latestChange = trend.changes.isEmpty ? null : trend.changes.last;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: appCardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('净资产趋势', style: AppType.rowTitle(scheme)),
          const SizedBox(height: 3),
          Text('自动估算', style: AppType.caption(scheme)),
          const SizedBox(height: 12),
          if (!trend.hasTrend)
            SizedBox(
              height: 72,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  trend.status == NetWorthTrendStatus.noComparablePairs
                      ? '已有快照的口径不同，暂不连线比较'
                      : '至少积累 2 个可比快照后显示趋势',
                  style: AppType.secondary(scheme),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 116,
              width: double.infinity,
              child: Semantics(
                image: true,
                label: _trendSemanticsLabel(trend),
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: _NetWorthTrendPainter(
                      segments: trend.segments,
                      lineColor: scheme.primary,
                      gridColor: AppColors.hairline(scheme),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (latestChange != null)
              Text.rich(
                TextSpan(
                  style: AppType.secondary(scheme),
                  children: [
                    const TextSpan(text: '较上次 '),
                    TextSpan(
                      text:
                          '${latestChange.amountDeltaMinor >= 0 ? '+' : '-'}'
                          '${MoneyFormat.string(
                            budgetDecimalFromCents(
                              latestChange.amountDeltaMinor.abs(),
                            )!,
                          )}',
                      style: const TextStyle(fontFamily: 'Nunito'),
                    ),
                  ],
                ),
              ),
            if (trend.breaks.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text('统计范围变化处断开', style: AppType.caption(scheme)),
            ],
          ],
        ],
      ),
    );
  }
}

String _trendSemanticsLabel(NetWorthTrendResult trend) {
  final points = trend.segments
      .expand((segment) => segment.points)
      .toList(growable: false)
    ..sort((a, b) => a.lineage.asOf.compareTo(b.lineage.asOf));
  if (points.length < 2) return '净资产趋势，暂无足够的可比数据';
  final first = points.first;
  final last = points.last;
  String day(DateTime value) => '${value.year}年${value.month}月${value.day}日';
  String amount(int minor) => MoneyFormat.string(
        budgetDecimalFromCents(minor)!,
      );
  final breakText =
      trend.breaks.isEmpty ? '' : '，其中有${trend.breaks.length}处因统计口径变化断开';
  return '净资产趋势，共${points.length}个可比点，'
      '${day(first.lineage.asOf)}为${amount(first.netWorthMinor)}，'
      '${day(last.lineage.asOf)}为${amount(last.netWorthMinor)}$breakText';
}

class _NetWorthTrendPainter extends CustomPainter {
  final List<NetWorthTrendSegment> segments;
  final Color lineColor;
  final Color gridColor;

  const _NetWorthTrendPainter({
    required this.segments,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final points = segments.expand((segment) => segment.points).toList();
    if (points.length < 2 || size.isEmpty) return;
    final minDate = points
        .map((point) => point.lineage.asOf.millisecondsSinceEpoch)
        .reduce(math.min);
    final maxDate = points
        .map((point) => point.lineage.asOf.millisecondsSinceEpoch)
        .reduce(math.max);
    var minValue = points.map((point) => point.netWorthMinor).reduce(math.min);
    var maxValue = points.map((point) => point.netWorthMinor).reduce(math.max);
    if (minValue == maxValue) {
      minValue -= 1;
      maxValue += 1;
    }
    const inset = 6.0;
    final chart = Rect.fromLTWH(
      inset,
      inset,
      math.max(1, size.width - inset * 2),
      math.max(1, size.height - inset * 2),
    );
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.7;
    for (var index = 1; index <= 2; index++) {
      final y = chart.top + chart.height * index / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    Offset position(ComputedNetWorthSnapshot point) {
      final date = point.lineage.asOf.millisecondsSinceEpoch;
      final xRatio =
          maxDate == minDate ? 0.5 : (date - minDate) / (maxDate - minDate);
      final yRatio = (point.netWorthMinor - minValue) / (maxValue - minValue);
      return Offset(
        chart.left + chart.width * xRatio,
        chart.bottom - chart.height * yRatio,
      );
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    for (final segment in segments.where((item) => item.points.isNotEmpty)) {
      final path = Path();
      for (var index = 0; index < segment.points.length; index++) {
        final offset = position(segment.points[index]);
        if (index == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
        canvas.drawCircle(offset, 2.7, pointPaint);
      }
      if (segment.points.length > 1) canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NetWorthTrendPainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}
