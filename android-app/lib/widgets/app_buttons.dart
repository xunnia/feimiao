import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'glass.dart';
import 'pressable_scale.dart';
import '../theme/app_tokens.dart';

/// 全局按钮标准（对齐主页顶栏 + 图五 ChatGPT 记忆页）：
/// 所有导航/操作按钮都套在**浅灰圆/胶囊**里，不再是光秃秃的图标/文字。
/// 返回键、加号、弹层 ✕、右上角保存都走这里，别再各写各的。

Widget _buttonHitTarget({
  required Widget child,
  required double visualSize,
  required VoidCallback? onPressed,
  String? semanticLabel,
  bool enforceMinHitTarget = true,
}) {
  final hitSize = enforceMinHitTarget && visualSize < AppHitTarget.min
      ? AppHitTarget.min
      : visualSize;
  final button = Semantics(
    container: true,
    button: true,
    enabled: onPressed != null,
    label: semanticLabel,
    onTap: onPressed,
    child: ConstrainedBox(
      constraints: BoxConstraints(minWidth: hitSize, minHeight: hitSize),
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        alignment: Alignment.center,
        child: child,
      ),
    ),
  );
  return semanticLabel == null
      ? button
      : Tooltip(message: semanticLabel, child: button);
}

String? _labelForIcon(IconData? icon) {
  if (icon == null) return null;
  if (icon == CupertinoIcons.plus || icon == Icons.add) return '添加';
  if (icon == CupertinoIcons.xmark || icon == Icons.close) return '关闭';
  if (icon == CupertinoIcons.chevron_back) return '返回';
  if (icon == CupertinoIcons.search || icon == Icons.search) return '搜索';
  if (icon == CupertinoIcons.trash || icon == Icons.delete_outline) return '删除';
  if (icon == CupertinoIcons.checkmark || icon == Icons.check) return '完成';
  if (icon == Icons.refresh_rounded) return '刷新';
  if (icon == Icons.auto_awesome_outlined) return 'AI 记账';
  return null;
}

/// 圆形浅底图标按钮（主页 ☰/🔍 同款）。用于返回 / 加号 / ✕ 等。
class AppCircleButton extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? semanticLabel;
  final bool expandHitTarget;
  const AppCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = AppControl.iconVisual,
    this.iconSize = 20,
    this.semanticLabel,
    this.expandHitTarget = true,
  }) : iconWidget = null;

  const AppCircleButton.custom({
    super.key,
    required this.iconWidget,
    required this.onPressed,
    this.size = AppControl.iconVisual,
    this.iconSize = 20,
    this.semanticLabel,
    this.expandHitTarget = true,
  }) : icon = null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _buttonHitTarget(
      visualSize: size,
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? _labelForIcon(icon),
      enforceMinHitTarget: expandHitTarget,
      child: PressableScale(
        onPressed: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: GlassSurface(
            circle: true,
            blur: 0, // 纯色背景，省 GPU
            child: Center(
              child: iconWidget ??
                  Icon(icon, size: iconSize, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact menu button used by the home header and the Chats header.
/// Keeping the three bars here prevents the two entry points from drifting.
class AppDrawerButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool expandHitTarget;

  const AppDrawerButton({
    super.key,
    required this.onPressed,
    this.expandHitTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget bar(double width) => Container(
          width: width,
          height: 1.5,
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant,
            borderRadius: BorderRadius.circular(1),
          ),
        );

    return _buttonHitTarget(
      visualSize: AppControl.iconVisual,
      onPressed: onPressed,
      semanticLabel: '打开抽屉',
      enforceMinHitTarget: expandHitTarget,
      child: PressableScale(
        onPressed: onPressed,
        child: SizedBox(
          width: AppControl.iconVisual,
          height: AppControl.iconVisual,
          child: GlassSurface(
            circle: true,
            blur: 0,
            child: Center(
              child: SizedBox(
                width: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(16),
                    const SizedBox(height: 3),
                    bar(16),
                    const SizedBox(height: 3),
                    bar(8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppCloseButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final double size;
  final String? semanticLabel;

  const AppCloseButton({
    super.key,
    required this.onPressed,
    this.size = 34,
    this.semanticLabel = '关闭',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _buttonHitTarget(
      visualSize: size,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: PressableScale(
        onPressed: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: GlassSurface(
            circle: true,
            blur: 0,
            child: Center(
              child: Icon(
                CupertinoIcons.xmark,
                size: size * 0.48,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一返回键：浅灰圆 + iOS chevron。直接当 AppBar 的 `leading` 用：
/// `AppBar(leading: const AppBackButton(), title: ...)`。
class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const AppBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppCircleButton(
        icon: CupertinoIcons.chevron_back,
        iconSize: 22,
        semanticLabel: '返回',
        onPressed: onPressed ?? () => Navigator.maybePop(context),
      ),
    );
  }
}

/// 浅灰胶囊文字按钮（图五「保存」同款）。用于弹层右上角的保存/确认操作，
/// 取代占地方的底部大长条按钮。[onPressed] 为 null 时置灰不可点。
class AppPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final Color? foregroundColor;
  final Color? fillColor;
  final Color? borderColor;
  final double height;
  final double? width;
  final EdgeInsetsGeometry padding;
  final bool loading;
  final Widget? leading;
  const AppPillButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.semanticLabel,
      this.foregroundColor,
      this.fillColor,
      this.borderColor,
      this.height = AppControl.pillHeight,
      this.width,
      this.padding = const EdgeInsets.symmetric(horizontal: 16),
      this.loading = false,
      this.leading});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final surface = SizedBox(
      width: width,
      height: height,
      child: GlassSurface(
        radius: height / 2,
        blur: 0,
        fillColor: fillColor,
        padding: padding,
        child: Center(
          child: loading
              ? SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: foregroundColor ?? scheme.onSurface,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[
                      IconTheme(
                        data: IconThemeData(
                          size: 17,
                          color: enabled
                              ? (foregroundColor ?? scheme.onSurface)
                              : scheme.onSurfaceVariant.withValues(alpha: 0.38),
                        ),
                        child: leading!,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: AppType.action(scheme).copyWith(
                        color: enabled
                            ? (foregroundColor ?? AppType.action(scheme).color)
                            : scheme.onSurfaceVariant.withValues(alpha: 0.38),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
    final button = PressableScale(
      onPressed: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          border: borderColor == null
              ? null
              : Border.all(color: borderColor!, width: 0.8),
        ),
        child: width == null ? IntrinsicWidth(child: surface) : surface,
      ),
    );
    return _buttonHitTarget(
      visualSize: height,
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      child: button,
    );
  }
}
