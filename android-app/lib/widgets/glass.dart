import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Claude 风玻璃边：沿圆角矩形 / 圆形描一圈「深浅不均」的细线——
/// 顶部一抹白色高光，往下渐变成一条很细的黑线（明暗、粗细看着都不等）。
class GlassEdgePainter extends CustomPainter {
  final double radius;
  final bool circle;

  const GlassEdgePainter({this.radius = 20, this.circle = false});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0x99FFFFFF), // 顶部高光（白 ~60%）
        Color(0x0F000000), // 中段很淡（黑 ~6%）
        Color(0x29000000), // 底部偏深（黑 ~16%）
      ],
      stops: [0.0, 0.45, 1.0],
    ).createShader(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = shader;
    if (circle) {
      canvas.drawCircle(rect.center, (size.shortestSide / 2) - 0.5, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GlassEdgePainter old) =>
      old.radius != radius || old.circle != circle;
}

/// 透明模糊玻璃面：背景模糊 + 半透明白底 + 不规则细黑边。
/// 全 App 的按钮 / 小弹窗 / 浮层统一用它，保证设计语言一致。
///
/// ⚠️ 性能：`BackdropFilter` 实时模糊很贵（每次失效都要 GPU 重算一片背景）。
/// 控件背后是**纯色/静态背景**时模糊了肉眼也看不出来，传 `blur: 0`
/// 走免模糊快速通道（观感一致、GPU 白省）——首页常驻小按钮都应该这么用；
/// 只有真正盖在滚动内容/动态画面上的浮层（如底部输入卡）才留模糊。
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final bool circle;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry? padding;

  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 20,
    this.circle = false,
    this.blur = 6,
    this.opacity = 0.4,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ShapeBorder shape = circle
        ? const CircleBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

    final core = CustomPaint(
      foregroundPainter: GlassEdgePainter(radius: radius, circle: circle),
      child: Container(
        padding: padding,
        color: scheme.surface.withValues(alpha: opacity),
        child: child,
      ),
    );

    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: blur <= 0
          ? core
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: core,
            ),
    );
  }
}
