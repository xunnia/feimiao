import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'glass.dart';
import 'pressable_scale.dart';

/// 全局按钮标准（对齐主页顶栏 + 图五 ChatGPT 记忆页）：
/// 所有导航/操作按钮都套在**浅灰圆/胶囊**里，不再是光秃秃的图标/文字。
/// 返回键、加号、弹层 ✕、右上角保存都走这里，别再各写各的。

/// 圆形浅底图标按钮（主页 ☰/🔍 同款）。用于返回 / 加号 / ✕ 等。
class AppCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  const AppCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 38,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onPressed,
      child: SizedBox(
        width: size,
        height: size,
        child: GlassSurface(
          circle: true,
          blur: 0, // 纯色背景，省 GPU
          child: Center(
            child: Icon(icon, size: iconSize, color: scheme.onSurfaceVariant),
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
  const AppPillButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return PressableScale(
      onPressed: onPressed,
      child: GlassSurface(
        radius: 18,
        blur: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: enabled
                ? scheme.onSurface
                : scheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
