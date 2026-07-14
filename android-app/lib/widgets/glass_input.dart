import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'glass.dart';
import 'pressable_scale.dart';

/// Shared Liquid Glass-style shell for bottom input bars and focused text areas.
class AppGlassInputShell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final double opacity;

  const AppGlassInputShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 13, 10, 13),
    this.radius = 28,
    this.blur = 6,
    this.opacity = 0.4,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: CustomPaint(
            foregroundPainter: GlassEdgePainter(radius: radius),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(radius),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class AppGlassInputIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final bool mutedWhenDisabled;

  const AppGlassInputIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 36,
    this.iconSize = 18,
    this.color,
    this.mutedWhenDisabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;

    return PressableScale(
      onPressed: onPressed,
      child: SizedBox(
        width: size,
        height: size,
        child: GlassSurface(
          circle: true,
          blur: 0,
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: enabled || !mutedWhenDisabled
                  ? (color ?? scheme.onSurfaceVariant)
                  : scheme.onSurfaceVariant.withValues(alpha: 0.38),
            ),
          ),
        ),
      ),
    );
  }
}

class AppGlassInputPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leading;

  const AppGlassInputPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final color = enabled
        ? scheme.onSurfaceVariant
        : scheme.onSurfaceVariant.withValues(alpha: 0.38);

    return PressableScale(
      onPressed: onPressed,
      child: GlassSurface(
        radius: 16,
        blur: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
