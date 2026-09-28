import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// 预算进度的统一视觉语义：健康绿 -> 临界金 -> 超支橙。
class BudgetProgressPalette {
  BudgetProgressPalette._();

  static const double _warningStop = 0.60;

  static Color colorAt(ColorScheme scheme, double progress) {
    final value = progress.clamp(0.0, 1.0);
    if (value <= _warningStop) {
      return Color.lerp(
        AppColors.budgetHealthy(scheme),
        AppColors.budgetCaution(scheme),
        value / _warningStop,
      )!;
    }
    return Color.lerp(
      AppColors.budgetCaution(scheme),
      AppColors.warning,
      (value - _warningStop) / (1 - _warningStop),
    )!;
  }

  static LinearGradient gradient(ColorScheme scheme) => LinearGradient(
        colors: [
          AppColors.budgetHealthy(scheme),
          AppColors.budgetCaution(scheme),
          AppColors.warning,
        ],
        stops: const [0.0, _warningStop, 1.0],
      );

  /// 超支时只用一个橙色系：超出部分是实橙 [AppColors.warning]，
  /// 预算内的 100% 用同一个橙的浅色，不再叠加绿→金渐变。
  static const Color overspend = AppColors.warning;

  static Color overspendWithin(ColorScheme scheme) => AppColors.warning
      .withValues(alpha: scheme.brightness == Brightness.dark ? 0.42 : 0.34);

  /// 100% 分界线颜色：接近卡片底色的细线，在任意填充色上都能看清。
  static Color boundaryColor(ColorScheme scheme) => scheme.surface.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.85 : 0.95,
      );

  /// 未完成轨道和当前进度末端同色相，只降低强度。
  static Color trackColor(ColorScheme scheme, Color reference) =>
      reference.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.22 : 0.16,
      );

  /// 轨道边缘比底色略深，避免浅色卡片上融成一片。
  static Color trackOutlineColor(ColorScheme scheme, Color reference) =>
      reference.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.38 : 0.28,
      );
}

/// 带动态同色轨道的预算进度条。
///
/// 不传 [activeColor] 时保留预算原有的绿/金/橙渐变；传入时用于已有明确
/// 状态色的场景（例如专项预算已临界或已超支）。
class BudgetProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? activeColor;

  /// 超支时 100% 预算线在整条中的位置（= 预算 / 已花，0~1 之间）。
  ///
  /// 传入后整条按「已花」铺满：左段浅橙代表预算内的 100%，
  /// 分界线右侧实橙表示超出的部分（见 [BudgetProgressPalette.overspend]）。
  /// 为 null 时保持原来的单段进度。
  final double? overflowStart;

  const BudgetProgressBar({
    super.key,
    required this.value,
    this.height = 7,
    this.activeColor,
    this.overflowStart,
  });

  @override
  Widget build(BuildContext context) {
    final overflowAt = overflowStart;
    if (overflowAt != null && overflowAt < 1) {
      return _buildOverflow(context, overflowAt.clamp(0.0, 1.0));
    }
    final scheme = Theme.of(context).colorScheme;
    final progress = value.clamp(0.0, 1.0);
    final endpointColor = activeColor ??
        BudgetProgressPalette.colorAt(
          scheme,
          progress,
        );
    final trackColor = BudgetProgressPalette.trackColor(
      scheme,
      endpointColor,
    );
    final outlineColor = BudgetProgressPalette.trackOutlineColor(
      scheme,
      endpointColor,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  key: const ValueKey('budget-progress-track'),
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: outlineColor, width: 0.75),
                  ),
                ),
                if (progress > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(
                      key: const ValueKey('budget-progress-fill-clip'),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: SizedBox(
                        width: width * progress,
                        height: height,
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: width,
                          maxWidth: width,
                          child: DecoratedBox(
                            key: const ValueKey('budget-progress-fill'),
                            decoration: BoxDecoration(
                              color: activeColor,
                              gradient: activeColor == null
                                  ? BudgetProgressPalette.gradient(scheme)
                                  : null,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOverflow(BuildContext context, double boundary) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final splitX = width * boundary;
            return Stack(
              children: [
                // 预算内的 100%：同色系浅橙，占分界线左侧。
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: splitX,
                  child: ColoredBox(
                    key: const ValueKey('budget-progress-fill-clip'),
                    color: BudgetProgressPalette.overspendWithin(scheme),
                  ),
                ),
                // 超出部分：实橙，占分界线右侧。
                Positioned(
                  left: splitX,
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: const ColoredBox(
                    key: ValueKey('budget-progress-overflow'),
                    color: BudgetProgressPalette.overspend,
                  ),
                ),
                // 100% 分界线。
                Positioned(
                  left: (splitX - 1).clamp(0.0, math.max(0.0, width - 2)),
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: ColoredBox(
                    key: const ValueKey('budget-progress-boundary'),
                    color: BudgetProgressPalette.boundaryColor(scheme),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 带同色浅轨道与略深轮廓的预算圆环。
class BudgetProgressRing extends StatelessWidget {
  final double value;
  final double strokeWidth;
  final Color activeColor;

  /// 超支模式：和横条同一套颜色。从 12 点顺时针到 [value] 是预算内的浅橙，
  /// 之后是实橙超出部分，[value] 处画分界线。此模式下忽略 [activeColor]。
  final bool overflow;

  const BudgetProgressRing({
    super.key,
    required this.value,
    required this.activeColor,
    this.strokeWidth = 7,
    this.overflow = false,
  });

  @override
  Widget build(BuildContext context) {
    if (overflow) return _buildOverflow(context);
    final scheme = Theme.of(context).colorScheme;
    final trackColor = BudgetProgressPalette.trackColor(scheme, activeColor);
    final outlineColor =
        BudgetProgressPalette.trackOutlineColor(scheme, activeColor);
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          child: CircularProgressIndicator(
            key: const ValueKey('budget-progress-ring-outline'),
            value: 1,
            strokeWidth: strokeWidth + 1.5,
            strokeAlign: CircularProgressIndicator.strokeAlignCenter,
            strokeCap: StrokeCap.butt,
            trackGap: 0,
            padding: EdgeInsets.zero,
            color: outlineColor,
          ),
        ),
        CircularProgressIndicator(
          key: const ValueKey('budget-progress-ring-fill'),
          value: value.clamp(0.0, 1.0),
          strokeWidth: strokeWidth,
          strokeAlign: CircularProgressIndicator.strokeAlignCenter,
          strokeCap: StrokeCap.round,
          trackGap: 0,
          padding: EdgeInsets.zero,
          color: activeColor,
          backgroundColor: trackColor,
        ),
      ],
    );
  }

  Widget _buildOverflow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CustomPaint(
        key: const ValueKey('budget-progress-ring-overflow'),
        painter: BudgetOverflowRingPainter(
          withinFraction: value.clamp(0.0, 1.0),
          withinColor: BudgetProgressPalette.overspendWithin(scheme),
          overflowColor: BudgetProgressPalette.overspend,
          boundaryColor: BudgetProgressPalette.boundaryColor(scheme),
          strokeWidth: strokeWidth,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 超支圆环：12 点起顺时针的预算内弧 + 其余的超出弧 + 100% 分界线。
///
/// 两段分开画、互不重叠，所以预算内那段可以用半透明浅色而不会被底色染深。
class BudgetOverflowRingPainter extends CustomPainter {
  /// 预算内部分占整圈的比例；0 表示今天开始前就已经没有额度，整圈超支色、不画分界线。
  final double withinFraction;
  final Color withinColor;
  final Color overflowColor;
  final Color boundaryColor;
  final double strokeWidth;

  const BudgetOverflowRingPainter({
    required this.withinFraction,
    required this.withinColor,
    required this.overflowColor,
    required this.boundaryColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2;

    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..color = color;

    if (withinFraction <= 0 || withinFraction >= 1) {
      canvas.drawCircle(
        center,
        radius,
        stroke(withinFraction <= 0 ? overflowColor : withinColor),
      );
      return;
    }

    final sweep = 2 * math.pi * withinFraction;
    canvas.drawArc(rect, start, sweep, false, stroke(withinColor));
    canvas.drawArc(
      rect,
      start + sweep,
      2 * math.pi - sweep,
      false,
      stroke(overflowColor),
    );

    // 分界线：沿半径方向的一道细线，略出头于环宽。
    final angle = start + sweep;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final half = strokeWidth / 2 + 1;
    canvas.drawLine(
      center + direction * (radius - half),
      center + direction * (radius + half),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.butt
        ..color = boundaryColor,
    );
  }

  @override
  bool shouldRepaint(BudgetOverflowRingPainter oldDelegate) =>
      oldDelegate.withinFraction != withinFraction ||
      oldDelegate.withinColor != withinColor ||
      oldDelegate.overflowColor != overflowColor ||
      oldDelegate.boundaryColor != boundaryColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
