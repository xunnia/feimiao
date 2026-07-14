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
        AppColors.income(scheme),
        value / _warningStop,
      )!;
    }
    return Color.lerp(
      AppColors.income(scheme),
      AppColors.warning,
      (value - _warningStop) / (1 - _warningStop),
    )!;
  }

  static LinearGradient gradient(ColorScheme scheme) => LinearGradient(
        colors: [
          AppColors.budgetHealthy(scheme),
          AppColors.income(scheme),
          AppColors.warning,
        ],
        stops: const [0.0, _warningStop, 1.0],
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

  const BudgetProgressBar({
    super.key,
    required this.value,
    this.height = 7,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
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
}

/// 带同色浅轨道与略深轮廓的预算圆环。
class BudgetProgressRing extends StatelessWidget {
  final double value;
  final double strokeWidth;
  final Color activeColor;

  const BudgetProgressRing({
    super.key,
    required this.value,
    required this.activeColor,
    this.strokeWidth = 7,
  });

  @override
  Widget build(BuildContext context) {
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
}
