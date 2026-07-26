import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'ios_menu.dart';
import 'pressable_scale.dart';

/// 全局「点击弹菜单选值」表单字段标准件。
///
/// 视觉与 iosInputDecoration 严格对齐：inputFill 底、圆角 12、内距 h14 v10、
/// minHeight 42；按压反馈 = PressableScale。标签一律外置（配 AppLabeledField），
/// 占位 = text 为空时显示 hint（占位色 AppTextColor.hint）。
/// 菜单类字段配套 [showPickerMenu]（菜单宽度跟随字段、左对齐锚点）。
class AppPickerField extends StatelessWidget {
  /// 当前值文案；null/空 = 显示 hint（占位色 AppTextColor.hint）。
  final String? text;
  final String hint;

  /// 可选前置件（Icon / CatIcon 都行）。
  final Widget? leading;

  /// 尾部图标，默认下箭头；日期字段可传 calendar 类图标。
  /// 统一不再用 chevron_right（那是「进入下一页」语义）。
  final IconData trailingIcon;

  /// 点击回调，内置 Builder 提供锚点 menuCtx；null = 禁用置灰不响应。
  final void Function(BuildContext menuCtx)? onTap;

  const AppPickerField({
    super.key,
    required this.text,
    required this.hint,
    this.leading,
    this.trailingIcon = Icons.keyboard_arrow_down_rounded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = text != null && text!.trim().isNotEmpty;
    final enabled = onTap != null;
    final field = Builder(
      builder: (menuCtx) => PressableScale(
        onPressed: enabled ? () => onTap!(menuCtx) : null,
        pressedScale: 0.985,
        pressedOpacity: 0.92,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.inputFill(scheme),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  hasText ? text! : hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: hasText
                        ? AppTextColor.primary(scheme)
                        : AppTextColor.hint(scheme),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                trailingIcon,
                size: 18,
                color: AppTextColor.secondary(scheme),
              ),
            ],
          ),
        ),
      ),
    );
    return enabled ? field : Opacity(opacity: 0.5, child: field);
  }
}

/// [AppPickerField] 的只读兄弟：同壳（可选前置图标 + 文案），无箭头无点击。
class AppReadOnlyField extends StatelessWidget {
  final String text;
  final IconData? icon;

  const AppReadOnlyField({super.key, required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.inputFill(scheme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppTextColor.secondary(scheme)),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(text, style: AppType.body(scheme))),
        ],
      ),
    );
  }
}

/// 配套：把菜单弹在字段正下方、左对齐锚点，宽度跟随字段
/// （width = 字段宽 clamp(220, 屏宽-16)）。menuCtx 用 [AppPickerField.onTap]
/// 回调给的锚点 context。
void showPickerMenu(BuildContext menuCtx, List<IosMenuItem> items) {
  if (items.isEmpty) return;
  showIosMenu(
    menuCtx,
    items,
    width: _pickerMenuWidth(menuCtx),
    alignToAnchorLeft: true,
  );
}

double _pickerMenuWidth(BuildContext context) {
  final renderObject = context.findRenderObject();
  final fieldWidth =
      renderObject is RenderBox ? renderObject.size.width : 260.0;
  final screenMax = MediaQuery.sizeOf(context).width - 16;
  return fieldWidth.clamp(220.0, screenMax).toDouble();
}
