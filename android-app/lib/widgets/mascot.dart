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

/// 给任意吉祥物图片套一层轻微的「呼吸 + 浮动 + 晃头」循环动效。
/// 公开复用：Mascot(animate:true) 走它,首页大卡片探头猫等自定义布局也直接套。
/// [sway] 是晃头幅度(弧度系数),thinking 态用大一点。
class MascotBreath extends StatefulWidget {
  const MascotBreath({super.key, required this.child, this.sway = 0.06});

  final Widget child;
  final double sway;

  @override
  State<MascotBreath> createState() => _MascotBreathState();
}

class _MascotBreathState extends State<MascotBreath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value); // 0..1
        final scale = 1.0 + 0.07 * t; // 呼吸放大
        final dy = -3.0 * t; // 微微上浮
        final angle = (t - 0.5) * widget.sway; // 轻轻晃头
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}
