import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../core/amount_expression.dart';
import '../../core/haptics.dart';
import '../../widgets/pressable_scale.dart';

/// 记账数字键盘（对齐咔皮布局，4 列）：
///
///   1  2  3  ⌫   （⌫ 长按清空）
///   4  5  6  ＋
///   7  8  9  −
///  再记 0  .  完成
///
/// [onSaveAgain] 传 null 时左下角显示「C」清空键（编辑页没有"再记"场景）。
/// 按键用 iOS 按压手感（按下缩放 + 变暗），不用 Material 水波纹。
class AmountKeypad extends StatelessWidget {
  final AmountExpression expression;
  final VoidCallback onExpressionChanged;

  /// 「完成」：保存并关闭。
  final VoidCallback onSave;

  /// 「再记」：保存但不关闭，继续记下一笔。null = 不显示（显示 C 清空键）。
  final VoidCallback? onSaveAgain;

  /// 完成键文案（编辑页用「保存」）。
  final String saveLabel;

  const AmountKeypad({
    super.key,
    required this.expression,
    required this.onExpressionChanged,
    required this.onSave,
    this.onSaveAgain,
    this.saveLabel = '完成',
  });

  static const double _keyHeight = 52;
  static const double _spacing = 8;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSave = expression.value > Decimal.zero;

    Widget digit(String d) => _key(context,
        label: d, onPressed: () => _tap(() => expression.insertDigit(d)));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          _row([
            digit('1'),
            digit('2'),
            digit('3'),
            _key(
              context,
              icon: Icons.backspace_outlined,
              onPressed: () => _tap(() => expression.deleteBackward()),
              onLongPress: () => _tap(() => expression.clear()),
            ),
          ]),
          const SizedBox(height: _spacing),
          _row([
            digit('4'),
            digit('5'),
            digit('6'),
            _key(context,
                icon: Icons.add,
                onPressed: () => _tap(() => expression.beginAddition())),
          ]),
          const SizedBox(height: _spacing),
          _row([
            digit('7'),
            digit('8'),
            digit('9'),
            _key(context,
                icon: Icons.remove,
                onPressed: () => _tap(() => expression.beginSubtraction())),
          ]),
          const SizedBox(height: _spacing),
          _row([
            if (onSaveAgain != null)
              _key(
                context,
                label: '再记',
                labelColor: canSave
                    ? scheme.primary
                    : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                labelSize: 16,
                onPressed: canSave ? onSaveAgain : null,
                haptic: Haptic.medium,
              )
            else
              _key(context,
                  label: 'C', onPressed: () => _tap(() => expression.clear())),
            digit('0'),
            _key(context,
                label: '.',
                onPressed: () => _tap(() => expression.insertDot())),
            _key(
              context,
              label: saveLabel,
              labelSize: 16,
              fill: canSave ? scheme.primary : scheme.primary.withAlpha(90),
              labelColor: scheme.onPrimary,
              onPressed: canSave ? onSave : null,
              haptic: Haptic.medium, // 保存是确认动作，给更实的触感
            ),
          ]),
        ],
      ),
    );
  }

  Widget _row(List<Widget> keys) {
    return Row(
      children: [
        for (int i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: _spacing),
          Expanded(child: keys[i]),
        ],
      ],
    );
  }

  Widget _key(
    BuildContext context, {
    String? label,
    IconData? icon,
    Color? fill,
    Color? labelColor,
    double? labelSize,
    VoidCallback? onPressed,
    VoidCallback? onLongPress,
    Haptic haptic = Haptic.selection,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return _KeyButton(
      height: _keyHeight,
      color: fill ?? scheme.surfaceContainerHigh,
      onPressed: onPressed,
      onLongPress: onLongPress,
      haptic: haptic,
      child: icon != null
          ? Icon(icon, color: scheme.onSurface)
          : Text(
              label!,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: labelSize,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Nunito',
                    color: labelColor,
                  ),
            ),
    );
  }

  void _tap(VoidCallback action) {
    // 触感交给 _KeyButton 里的 PressableScale 统一处理（避免重复振动）。
    action();
    onExpressionChanged();
  }
}

/// 圆角卡片按键：iOS 按压手感（缩放 + 变暗）+ 触感，取代 Material 水波纹。
class _KeyButton extends StatelessWidget {
  final double height;
  final Color color;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Widget child;
  final Haptic haptic;

  const _KeyButton({
    required this.height,
    required this.color,
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.haptic = Haptic.selection,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onPressed: onPressed,
      onLongPress: onLongPress,
      haptic: haptic,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
