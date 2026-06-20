import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../core/amount_expression.dart';
import '../../core/haptics.dart';
import '../../widgets/pressable_scale.dart';

/// 快记数字键盘：左侧 3 列数字 + 右侧功能列（删除、连加、保存）。
///
/// 对应 iOS AmountKeypad.swift 布局。按键采用 iOS 按压手感（按下缩放 + 变暗），
/// 不再用 Material 水波纹。
class AmountKeypad extends StatelessWidget {
  final AmountExpression expression;
  final VoidCallback onExpressionChanged;
  final VoidCallback onSave;

  const AmountKeypad({
    super.key,
    required this.expression,
    required this.onExpressionChanged,
    required this.onSave,
  });

  static const double _keyHeight = 56;
  static const double _spacing = 8;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 左侧数字区
          Expanded(
            child: Column(
              children: [
                _digitRow(context, ['7', '8', '9']),
                const SizedBox(height: _spacing),
                _digitRow(context, ['4', '5', '6']),
                const SizedBox(height: _spacing),
                _digitRow(context, ['1', '2', '3']),
                const SizedBox(height: _spacing),
                Row(
                  children: [
                    Expanded(child: _digitKey(context, '.', () => _tap(() => expression.insertDot()))),
                    const SizedBox(width: _spacing),
                    Expanded(child: _digitKey(context, '0', () => _tap(() => expression.insertDigit('0')))),
                    const SizedBox(width: _spacing),
                    Expanded(child: _digitKey(context, 'C', () => _tap(() => expression.clear()))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: _spacing),
          // 右侧功能区
          SizedBox(
            width: 84,
            child: Column(
              children: [
                _functionKey(
                  context,
                  icon: Icons.backspace_outlined,
                  onPressed: () => _tap(() => expression.deleteBackward()),
                ),
                const SizedBox(height: _spacing),
                _functionKey(
                  context,
                  icon: Icons.add,
                  onPressed: () => _tap(() => expression.beginAddition()),
                ),
                const SizedBox(height: _spacing),
                // 保存按钮：高度 = 两个普通按键 + 间距
                _saveKey(context, scheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _digitRow(BuildContext context, List<String> digits) {
    return Row(
      children: [
        for (int i = 0; i < digits.length; i++) ...[
          if (i > 0) const SizedBox(width: _spacing),
          Expanded(child: _digitKey(context, digits[i], () => _tap(() => expression.insertDigit(digits[i])))),
        ],
      ],
    );
  }

  Widget _digitKey(BuildContext context, String label, VoidCallback onPressed) {
    final scheme = Theme.of(context).colorScheme;
    return _KeyButton(
      height: _keyHeight,
      color: scheme.surfaceContainerHigh,
      onPressed: onPressed,
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  Widget _functionKey(BuildContext context, {required IconData icon, required VoidCallback onPressed}) {
    final scheme = Theme.of(context).colorScheme;
    return _KeyButton(
      height: _keyHeight,
      color: scheme.surfaceContainerHigh,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }

  Widget _saveKey(BuildContext context, ColorScheme scheme) {
    final canSave = expression.value > Decimal.zero;
    // height = 2 * keyHeight + 1 * spacing
    const saveHeight = _keyHeight * 2 + _spacing;
    return _KeyButton(
      height: saveHeight,
      color: canSave ? scheme.primary : scheme.primary.withAlpha(90),
      onPressed: canSave ? onSave : null,
      haptic: Haptic.medium, // 保存是确认动作，给更实的触感
      child: Text(
        '保存',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w600,
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
  final Widget child;
  final Haptic haptic;

  const _KeyButton({
    required this.height,
    required this.color,
    required this.onPressed,
    required this.child,
    this.haptic = Haptic.selection,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onPressed: onPressed,
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
