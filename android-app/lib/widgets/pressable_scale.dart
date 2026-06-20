import 'package:flutter/widgets.dart';

import '../core/haptics.dart';

/// iOS 风「按压」交互组件。
///
/// 取代 Material 水波纹（InkWell）：按下时整体**轻微缩小 + 变暗**，松手回弹，
/// 不扩散涟漪——这是 iOS 触感的核心观感。可选触感反馈（默认 selection）。
///
/// 用法：把原来 `InkWell` / `GestureDetector` 包裹的可点元素换成它即可，
/// 形状/圆角/底色全部保留（可爱风不动），只换「按下去的反应」。
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.pressedOpacity = 0.88,
    this.haptic = Haptic.selection,
    this.duration = const Duration(milliseconds: 110),
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// 按下时缩放到的比例（0.96 ≈ iOS 系统按钮手感）。
  final double pressedScale;

  /// 按下时透明度。
  final double pressedOpacity;

  /// 点按触感类型；传 null 表示不振动（如调用方已自行处理触感）。
  final Haptic? haptic;

  final Duration duration;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null || widget.onLongPress != null;

  void _setDown(bool v) {
    if (_enabled && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setDown(true),
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      onTap: widget.onPressed == null
          ? null
          : () {
              if (widget.haptic != null) Haptics.of(widget.haptic!);
              widget.onPressed!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              Haptics.medium();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _down ? widget.pressedOpacity : 1.0,
          duration: widget.duration,
          child: widget.child,
        ),
      ),
    );
  }
}
