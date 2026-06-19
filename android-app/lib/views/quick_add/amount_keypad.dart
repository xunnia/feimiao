import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/amount_expression.dart';

/// 快记数字键盘（M41 改版，参考咔皮）。
///
/// 4×4 布局：
///   1 2 3 ⌫(长按=清空)
///   4 5 6 ＋
///   7 8 9 －
///   再记 0 . 保存
///
/// [onSaveAndContinue] 为空时（如编辑页），左下角显示「C 清空」而非「再记」。
class AmountKeypad extends StatelessWidget {
  final AmountExpression expression;
  final VoidCallback onExpressionChanged;
  final VoidCallback onSave;
  final VoidCallback? onSaveAndContinue;

  const AmountKeypad({
    super.key,
    required this.expression,
    required this.onExpressionChanged,
    required this.onSave,
    this.onSaveAndContinue,
  });

  static const double _keyHeight = 54;
  static const double _spacing = 8;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSave = expression.value > Decimal.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          _row([
            _digit(context, '1'),
            _digit(context, '2'),
            _digit(context, '3'),
            _func(context,
                icon: Icons.backspace_outlined,
                onTap: () => _tap(() => expression.deleteBackward()),
                onLongPress: () => _tap(() => expression.clear())),
          ]),
          const SizedBox(height: _spacing),
          _row([
            _digit(context, '4'),
            _digit(context, '5'),
            _digit(context, '6'),
            _func(context,
                icon: Icons.add,
                onTap: () => _tap(() => expression.beginAddition())),
          ]),
          const SizedBox(height: _spacing),
          _row([
            _digit(context, '7'),
            _digit(context, '8'),
            _digit(context, '9'),
            _func(context,
                icon: Icons.remove,
                onTap: () => _tap(() => expression.beginSubtraction())),
          ]),
          const SizedBox(height: _spacing),
          _row([
            // 左下：再记（有回调时）/ 否则清空
            onSaveAndContinue != null
                ? _text(context, '再记',
                    color: scheme.secondaryContainer,
                    textColor: scheme.onSecondaryContainer,
                    onTap: canSave
                        ? () {
                            HapticFeedback.mediumImpact();
                            onSaveAndContinue!();
                          }
                        : null)
                : _text(context, 'C',
                    color: scheme.surfaceContainerHigh,
                    textColor: scheme.onSurface,
                    onTap: () => _tap(() => expression.clear())),
            _digit(context, '0'),
            _digit(context, '.', onTap: () => _tap(() => expression.insertDot())),
            _text(context, '保存',
                color: canSave ? scheme.primary : scheme.primary.withAlpha(90),
                textColor: scheme.onPrimary,
                bold: true,
                onTap: canSave ? onSave : null),
          ]),
        ],
      ),
    );
  }

  Widget _row(List<Widget> cells) {
    return Row(
      children: [
        for (int i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: _spacing),
          Expanded(child: cells[i]),
        ],
      ],
    );
  }

  Widget _digit(BuildContext context, String label, {VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return _KeyButton(
      height: _keyHeight,
      color: scheme.surfaceContainerHigh,
      onPressed: onTap ?? () => _tap(() => expression.insertDigit(label)),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _func(BuildContext context,
      {required IconData icon,
      required VoidCallback onTap,
      VoidCallback? onLongPress}) {
    final scheme = Theme.of(context).colorScheme;
    return _KeyButton(
      height: _keyHeight,
      color: scheme.surfaceContainerHighest,
      onPressed: onTap,
      onLongPress: onLongPress,
      child: Icon(icon, color: scheme.onSurfaceVariant),
    );
  }

  Widget _text(BuildContext context, String label,
      {required Color color,
      required Color textColor,
      bool bold = false,
      VoidCallback? onTap}) {
    return _KeyButton(
      height: _keyHeight,
      color: color,
      onPressed: onTap,
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: textColor,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
            ),
      ),
    );
  }

  void _tap(VoidCallback action) {
    HapticFeedback.lightImpact();
    action();
    onExpressionChanged();
  }
}

/// 圆角卡片按键，统一触感和外观。
class _KeyButton extends StatelessWidget {
  final double height;
  final Color color;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Widget child;

  const _KeyButton({
    required this.height,
    required this.color,
    required this.onPressed,
    this.onLongPress,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          onLongPress: onLongPress,
          child: Center(child: child),
        ),
      ),
    );
  }
}
