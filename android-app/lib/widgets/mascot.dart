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
  });

  final MascotMood mood;

  /// 整体尺寸（宽高相等）。
  final double size;

  @override
  Widget build(BuildContext context) {
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
      MascotMood.idle => kCatBlueGray.withOpacity(0.12),
      MascotMood.success => kCatGold.withOpacity(0.18),
      MascotMood.overspend => kOverspendOrange.withOpacity(0.15),
      MascotMood.celebrate => kCatPink.withOpacity(0.18),
      MascotMood.empty => scheme.surfaceContainerHighest.withOpacity(0.5),
      MascotMood.thinking => kCatBlueGray.withOpacity(0.10),
      MascotMood.report => kCatGold.withOpacity(0.12),
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
