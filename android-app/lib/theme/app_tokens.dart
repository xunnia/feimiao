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

/// 文字层级颜色（2026-07-11 定稿：一律基于 onSurface 的灰阶，
/// 弃用 M3 onSurfaceVariant——那是深灰紫，看着跟黑字没区别，没有层次）。
class AppTextColor {
  AppTextColor._();

  /// 主文字：金额、标题（最深）
  static Color primary(ColorScheme s) => s.onSurface;

  /// 次要文字：说明、副标题、行尾值（= 弹窗正文 dialogBodyColor 同级）
  static Color secondary(ColorScheme s) => s.onSurface.withValues(alpha: 0.55);

  /// 辅助/最弱：脚注、占位提示
  static Color hint(ColorScheme s) => s.onSurface.withValues(alpha: 0.45);
}

/// 文字层级令牌（2026-07-11 定稿，对齐 iOS 设置页「非重点降号+变灰」原则）。
/// **新界面一律引用这里，别再裸写 TextStyle、别依赖 textTheme 默认值**——
/// 默认值是 16px 深色，说明文字和正文长一样就是"大杂烩"的根源。
/// 页面 AppBar 标题（17/w600）由全局 appBarTheme 管，不在此列。
class AppType {
  AppType._();

  /// 行标题：设置行 / 编辑块标题。
  static TextStyle rowTitle(ColorScheme s) => TextStyle(
      fontSize: 15.5, fontWeight: FontWeight.w500, color: s.onSurface);

  /// 正文。
  static TextStyle body(ColorScheme s) => TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: s.onSurface);

  /// 说明/副标题（iOS 式降号变灰）：行副标题、选项说明、弹窗正文同级。
  static TextStyle secondary(ColorScheme s) => TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: AppTextColor.secondary(s));

  /// 分组标签（管理/显示/接口…），和 SettingsSectionLabel 同规格。
  static TextStyle sectionLabel(ColorScheme s) => TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      color: s.onSurface.withValues(alpha: 0.50));

  /// 行尾值（右侧灰字：「两位小数」「已配置」）。
  static TextStyle trailingValue(ColorScheme s) => TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppTextColor.secondary(s));

  /// 脚注（页面底部整段说明，最弱一级）。
  static TextStyle caption(ColorScheme s) => TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: AppTextColor.hint(s));
}
