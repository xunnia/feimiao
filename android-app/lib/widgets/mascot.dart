import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 吉祥物表情状态。
enum MascotMood {
  /// 首页待机：招手探头
  idle,

  /// 记账成功：举钱袋坐
  success,

  /// 超支预警：捂脸流泪
  overspend,

  /// 存钱达成：跳起爱心
  celebrate,

  /// 空状态：趴睡
  empty,

  /// 喵助手加载/思考：托腮思考
  thinking,

  /// 统计锐评/喵助手：举板指点
  report,
}

/// 吉祥物组件（蓝白英短猫）。
///
/// 当前用 emoji 占位。等 `assets/mascot/<mood>.png` 就位后，
/// TODO: 将 [_buildPlaceholder] 替换为 `Image.asset(...)` 实现。
///
/// 用法：
/// ```dart
/// Mascot(mood: MascotMood.idle, size: 64)
/// ```
class Mascot extends StatelessWidget {
  const Mascot({
    super.key,
    this.mood = MascotMood.idle,
    this.size = 48,
    this.animate = false,
  });

  final MascotMood mood;

  /// 整体尺寸（宽高相等）。
  final double size;

  /// 是否做轻微的「活着」动效（呼吸 + 浮动；thinking 态加思考摇摆）。
  /// 空状态、加载/思考态打开即可。尊重系统「减弱动效」设置。
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final child = _buildImage(context);
    if (!animate) return child;
    // 系统开启「减弱动效」时保持静止（无障碍）。
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    return MascotBreath(
      sway: mood == MascotMood.thinking ? 0.14 : 0.06,
      child: child,
    );
  }

  Widget _buildImage(BuildContext context) {
    // 优先用真猫 PNG（assets/mascot/<mood>.png）；
    // 文件还没就位 / 加载失败时回退到 emoji 占位，保证不崩。
    return Image.asset(
      'assets/mascot/${mood.name}.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 背景色：用 secondary（金）或 tertiary（粉）的浅色调
    final bgColor = switch (mood) {
      MascotMood.idle => kCatBlueGray.withValues(alpha: 0.12),
      MascotMood.success => kCatGold.withValues(alpha: 0.18),
      MascotMood.overspend => kOverspendOrange.withValues(alpha: 0.15),
      MascotMood.celebrate => kCatPink.withValues(alpha: 0.18),
      MascotMood.empty => scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      MascotMood.thinking => kCatBlueGray.withValues(alpha: 0.10),
      MascotMood.report => kCatGold.withValues(alpha: 0.12),
    };

    final emoji = switch (mood) {
      MascotMood.idle => '🐱',
      MascotMood.success => '🧧',
      MascotMood.overspend => '🙀',
      MascotMood.celebrate => '😻',
      MascotMood.empty => '😴',
      MascotMood.thinking => '🤔',
      MascotMood.report => '📋',
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji,
        style: TextStyle(fontSize: size * 0.52),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// 给任意吉祥物图片套一层轻微的「呼吸 + 浮动 + 晃头」动效。
/// 公开复用：Mascot(animate:true) 走它,首页大卡片探头猫等自定义布局也直接套。
/// [sway] 是晃头幅度(弧度系数),thinking 态用大一点。
///
/// ⚠️ 性能：**间歇呼吸**，不是永动画——呼吸 2 个来回后完全静止歇 8 秒再来。
/// 之前 `repeat()` 永不停会逼手机以 60/120fps 持续渲染 + 反复重算
/// BackdropFilter 模糊，是「打开 App 手机发烫」的元凶（2026-07-02 用户实测）。
/// 静止期间零帧渲染；再用 RepaintBoundary 把重绘圈在猫自己这一小块。
class MascotBreath extends StatefulWidget {
  const MascotBreath({
    super.key,
    required this.child,
    this.sway = 0.06,
    this.bob = -3.0,
  });

  final Widget child;
  final double sway;

  /// 上下浮动幅度(负=上浮)。贴在卡片顶边的探头猫用正值(下沉),
  /// 否则上浮会被上方边界裁掉。
  final double bob;

  @override
  State<MascotBreath> createState() => _MascotBreathState();
}

class _MascotBreathState extends State<MascotBreath>
    with SingleTickerProviderStateMixin {
  static const int _breathsPerBout = 2; // 每轮呼吸的来回数
  static const Duration _rest = Duration(seconds: 8); // 每轮之间静止时长

  late final AnimationController _c;
  Timer? _restTimer;
  int _halfCycles = 0; // 已完成的半程数（forward/reverse 各算一次）

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addStatusListener(_onStatus);
    _c.forward();
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) {
      _halfCycles++;
      _c.reverse();
    } else if (s == AnimationStatus.dismissed) {
      _halfCycles++;
      if (_halfCycles < _breathsPerBout * 2) {
        _c.forward();
      } else {
        // 一轮呼吸结束：完全停住歇一会儿（期间零帧渲染），再来下一轮。
        _restTimer = Timer(_rest, () {
          if (!mounted) return;
          _halfCycles = 0;
          _c.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_c.value); // 0..1
          final scale = 1.0 + 0.07 * t; // 呼吸放大
          final dy = widget.bob * t; // 上下浮动(默认上浮;探头猫用正值下沉)
          final angle = (t - 0.5) * widget.sway; // 轻轻晃头
          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(scale: scale, child: child),
            ),
          );
        },
      ),
    );
  }
}
