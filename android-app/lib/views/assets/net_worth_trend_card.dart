import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/account/net_worth_snapshot.dart';
import '../../core/budget/budget_window_resolver.dart';
import '../../core/money_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/settings_ui.dart';

class NetWorthEstimatedTrendCard extends StatefulWidget {
  final NetWorthTrendResult trend;

  /// true = 嵌入外层合并卡（不画自己的卡片装饰），标题与「较上次」行照旧。
  final bool embedded;

  const NetWorthEstimatedTrendCard({
    super.key,
    required this.trend,
    this.embedded = false,
  });

  @override
  State<NetWorthEstimatedTrendCard> createState() =>
      _NetWorthEstimatedTrendCardState();
}

class _NetWorthEstimatedTrendCardState
    extends State<NetWorthEstimatedTrendCard> {
  int _rangeDays = 0; // 0=全部, 90=3个月, 365=1年

  NetWorthTrendResult get _filteredTrend {
    if (_rangeDays == 0 || !widget.trend.hasTrend) return widget.trend;
    final cutoff = DateTime.now().subtract(Duration(days: _rangeDays));
    // 从全量 points 里截取时间窗口内的点，然后重新 resolve 确保 segment/change 逻辑一致。
    final filtered = widget.trend.points
        .where((point) =>
            !point.lineage.asOf.isBefore(cutoff))
        .toList();
    if (filtered.length < 2) {
      return NetWorthTrendResult(
        status: NetWorthTrendStatus.insufficientEligiblePoints,
        points: filtered,
        isolatedPoints: const [],
        segments: const [],
        breaks: const [],
        changes: const [],
      );
    }
    return resolveNetWorthTrend(filtered);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trend = _filteredTrend;
    final latestChange = trend.changes.isEmpty ? null : trend.changes.last;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: widget.embedded ? null : appCardDecoration(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('净资产趋势', style: AppType.rowTitle(scheme)),
                    const SizedBox(height: 3),
                    Text('自动估算', style: AppType.caption(scheme)),
                  ],
                ),
              ),
              // 区间选择器（3月/1年/全部）
              if (widget.trend.hasTrend)
                _RangeSelector(
                  value: _rangeDays,
                  onChanged: (days) => setState(() => _rangeDays = days),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!trend.hasTrend)
            SizedBox(
              height: 72,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _rangeDays > 0
                      ? '该时间段内快照不足'
                      : widget.trend.status ==
                              NetWorthTrendStatus.noComparablePairs
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

// 区间选择器：3个月 / 1年 / 全部，轻量文字按钮样式。
class _RangeSelector extends StatelessWidget {
  final int value; // 0=全部, 90=3月, 365=1年
  final ValueChanged<int> onChanged;

  const _RangeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const options = [(90, '3月'), (365, '1年'), (0, '全部')];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          GestureDetector(
            onTap: () => onChanged(option.$1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                option.$2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: value == option.$1
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: value == option.$1
                      ? scheme.onSurface
                      : AppTextColor.hint(scheme),
                ),
              ),
            ),
          ),
      ],
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
    // 线下渐变填充：主色 18% 透明度渐隐到 0，按段独立（口径断点处不连成一片）。
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, chart.top),
        Offset(0, chart.bottom),
        [
          lineColor.withValues(alpha: 0.18),
          lineColor.withValues(alpha: 0.0),
        ],
      );
    for (final segment in segments.where((item) => item.points.isNotEmpty)) {
      final path = Path();
      Offset first = Offset.zero;
      Offset last = Offset.zero;
      for (var index = 0; index < segment.points.length; index++) {
        final offset = position(segment.points[index]);
        if (index == 0) {
          path.moveTo(offset.dx, offset.dy);
          first = offset;
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
        last = offset;
        canvas.drawCircle(offset, 2.7, pointPaint);
      }
      if (segment.points.length > 1) {
        // 填充画在网格线之后、描线之前。
        final fill = Path.from(path)
          ..lineTo(last.dx, chart.bottom)
          ..lineTo(first.dx, chart.bottom)
          ..close();
        canvas.drawPath(fill, fillPaint);
        canvas.drawPath(path, linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NetWorthTrendPainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}
