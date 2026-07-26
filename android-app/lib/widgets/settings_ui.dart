import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'app_buttons.dart';
import 'pressable_scale.dart';

/// 全局设置/弹层 UI 零件（对齐 iOS/图二：居中标题、分组白卡、发丝线分隔、iOS 开关）。
/// 「同类功能同一种设计」——所有设置类界面/弹层都走这几个，别再各写各的。

/// 统一胶囊开关（iOS 标准形态）：槽体常显——开=深色槽+白点，关=浅灰槽+白点。
/// 2026-07-10 用户点名：关闭态之前只剩一个裸灰点（槽是透明的，半透明卡上
/// 完全看不出这是个开关），改回经典「灰槽白点」。
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final dark = scheme.brightness == Brightness.dark;
    final trackColor = value
        ? (dark
            ? Colors.white.withValues(alpha: 0.92)
            : const Color(0xFF111111))
        : scheme.onSurface.withValues(alpha: dark ? 0.28 : 0.16);
    final thumbColor = value && dark ? const Color(0xFF1C1A18) : Colors.white;
    void toggle() => onChanged!(!value);
    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: enabled,
      onTap: enabled ? toggle : null,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: PressableScale(
            pressedScale: 0.96,
            onPressed: enabled ? toggle : null,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: 40,
                  height: 24,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment:
                        value ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: thumbColor,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 半屏弹层统一顶部（对齐图二）：左上角 ✕ 关闭 + 居中标题（字重 w500）
/// + 右上角可选操作按钮（保存/确认，取代占地方的底部大长条按钮）+ 可选副标题。
/// [onAction] 为 null 时操作按钮置灰不可点（表单未填完等）。
class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const sideInset = 12.0;
    const controlSize = 34.0;
    const headerHeight = controlSize + sideInset * 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: headerHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (onClose != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: sideInset),
                    child: AppCircleButton(
                      icon: CupertinoIcons.xmark,
                      iconSize: 18,
                      size: controlSize,
                      onPressed: onClose,
                    ),
                  ),
                ),
              if (actionLabel != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: sideInset),
                    child: AppPillButton(
                      key: actionKey,
                      label: actionLabel!,
                      onPressed: onAction,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.68),
              ),
            ),
          ),
      ],
    );
  }
}

/// 分组白卡：内部各行用发丝线分隔（图二那样）。传入若干 [SettingsRow]。
/// 分组白卡的标准装饰（与 [SettingsGroup] 同款）：AppColors.card 填充 +
/// 连续曲率圆角，无阴影无描边。自定义内容卡不方便直接用 SettingsGroup 时
/// 套这个，别再手写 BoxDecoration(阴影/描边/魔法圆角)。
ShapeDecoration appCardDecoration(ColorScheme scheme) => ShapeDecoration(
      color: AppColors.card(scheme),
      shape: ContinuousRectangleBorder(
        borderRadius: BorderRadius.circular(34),
      ),
    );

/// 分组白卡里的标准行分隔线（与 [SettingsGroup] 同款，左缩进 16）。
Widget appCardDivider(ColorScheme scheme) => Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );

class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets margin;
  const SettingsGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ));
      }
      rows.add(children[i]);
    }
    // 连续曲率圆角（近似 iOS 超椭圆）：视觉约 22，比普通圆角自然。
    return Container(
      margin: margin,
      decoration: ShapeDecoration(
        color: AppColors.card(scheme),
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(34),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

/// 分组白卡里的一行：可选前图标 + 标题/副标题 + 尾部部件（开关/箭头/文本）。
class SettingsRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  const SettingsRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: trailing is AppSwitch ? 4 : 13,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme(
                data: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
                child: leading!,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 走 AppType 字阶令牌（UI 标准）：标题 15.5/w500，
                  // 副标题 13 中灰——非重点降号+变灰，别再手写。
                  Text(title,
                      style: titleColor == null
                          ? AppType.rowTitle(scheme)
                          : AppType.rowTitle(scheme)
                              .copyWith(color: titleColor)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppType.secondary(scheme)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
    return trailing is AppSwitch ? MergeSemantics(child: content) : content;
  }
}

/// 分组前的灰色小标题（图二「触觉反馈何时需要」那种）。
class SettingsSectionLabel extends StatelessWidget {
  final String text;
  const SettingsSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 规格收口到 AppType.sectionLabel（UI 标准唯一出处）。
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: AppType.sectionLabel(scheme)),
      ),
    );
  }
}
