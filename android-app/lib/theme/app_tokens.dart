import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// 设计令牌（Design Tokens）
///
/// 全 App 统一的圆角 / 间距 / 动效 / 文字层级，避免到处手写魔法数字。
/// 颜色仍走 `app_colors.dart` 的猫系色板与 ColorScheme。
/// ─────────────────────────────────────────────────────────────────────────

/// 圆角令牌。轻记偏大圆角 = 更萌（保留我们既有风格，不照搬商务 16/20）。
class AppRadius {
  AppRadius._();

  /// 小标签 / 角标
  static const double xs = 8;

  /// chip / 小按钮
  static const double sm = 12;

  /// 列表项 / 中卡
  static const double md = 16;

  /// 卡片
  static const double lg = 20;

  /// 主输入卡 / 大卡（萌感大圆角）
  static const double xl = 28;

  /// 全圆（胶囊 / 头像）
  static const double pill = 999;
}

/// 间距令牌（4 的倍数体系）。
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// 动效时长与曲线令牌。原则：快、轻、不挡操作。
class AppMotion {
  AppMotion._();

  /// 点击反馈 / 小元素
  static const Duration fast = Duration(milliseconds: 120);

  /// 常规过渡（卡片淡入等）
  static const Duration normal = Duration(milliseconds: 250);

  /// 较大过渡（数字 count-up、入列）
  static const Duration smooth = Duration(milliseconds: 400);

  /// 确认弹一下
  static const Duration bounce = Duration(milliseconds: 180);

  /// 入场
  static const Curve enter = Curves.easeOut;

  /// 退场
  static const Curve exit = Curves.easeIn;

  /// 确认 / 强调（轻微回弹）
  static const Curve spring = Curves.easeOutBack;
}

/// 字重令牌。
class AppWeight {
  AppWeight._();

  /// 金额 / 强调主数字
  static const FontWeight emphasis = FontWeight.w700;

  /// 标题 / 主信息
  static const FontWeight title = FontWeight.w600;

  /// 正文
  static const FontWeight body = FontWeight.w400;
}

/// 文字层级颜色（随深浅模式自适应；对应 GPT 建议的 #111/#666/#999 三级）。
class AppTextColor {
  AppTextColor._();

  /// 主文字：金额、标题（最深）
  static Color primary(ColorScheme s) => s.onSurface;

  /// 次要文字：分类名等
  static Color secondary(ColorScheme s) => s.onSurfaceVariant;

  /// 辅助/最弱：备注、交易对方、占位提示
  static Color hint(ColorScheme s) => s.onSurfaceVariant.withValues(alpha: 0.6);
}
