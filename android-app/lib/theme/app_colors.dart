import 'package:flutter/material.dart';

/// 品牌主色，与 iOS 版 Color+Semantic.swift 保持一致。
/// 中性化语义色方案：收入=蓝、支出=中性文本、警示=柔和橙。
const Color kBrandBlue = Color(0xFF2E5090);

/// 警示色（超支/负结余）：柔和橙，与 iOS warning 对齐。
const Color kWarningOrange = Color(0xFFE67E22);

/// 应用语义色（依 Brightness 区分深浅模式）。
class AppColors {
  AppColors._();

  /// 收入/正向金额 —— 品牌蓝（浅色模式）。
  static const Color incomeLightMode = kBrandBlue;

  /// 收入/正向金额 —— 浅蓝（深色模式更易读）。
  static const Color incomeDarkMode = Color(0xFF7EAAEC);

  /// 支出/普通金额 —— 跟随系统文字色（onSurface），
  /// 不在此处硬编码，直接用 Theme.of(context).colorScheme.onSurface。

  /// 警示色（超支）—— 深浅模式均用柔和橙。
  static const Color warning = kWarningOrange;

  /// 根据当前 [ColorScheme] 返回收入颜色。
  static Color income(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark ? incomeDarkMode : incomeLightMode;

  /// 支出颜色直接返回 onSurface（中性文本色）。
  static Color expense(ColorScheme scheme) => scheme.onSurface;
}

/// Material 3 ColorScheme 工厂：浅色 + 深色。
class AppTheme {
  AppTheme._();

  static ThemeData light() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrandBlue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      );

  static ThemeData dark() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrandBlue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );
}
