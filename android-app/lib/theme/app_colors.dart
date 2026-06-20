import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// 猫色板：从用户家蓝白英短猫取色
// ---------------------------------------------------------------------------

/// 主色：蓝灰毛
const Color kCatBlueGray = Color(0xFF7D8B9B);

/// 点缀/高亮：铜金眼（收入色、发送键、选中态）
const Color kCatGold = Color(0xFFF2B23C);

/// 萌点：粉鼻爪（成功/爱心）
const Color kCatPink = Color(0xFFF4A9B8);

/// 超支警示：橙
const Color kOverspendOrange = Color(0xFFFF9F68);

/// 背景：奶白胸毛
const Color kCreamWhite = Color(0xFFFFFDF7);

/// 节日点缀：钱袋金
const Color kFestivalGold = Color(0xFFF3C44B);

/// 节日点缀：红绳
const Color kFestivalRed = Color(0xFFD94B3D);

// ---------------------------------------------------------------------------
// 向后兼容别名（原名称保留，避免破坏现有调用点）
// ---------------------------------------------------------------------------

/// @deprecated 请用 kCatBlueGray。保留以兼容旧引用。
const Color kBrandBlue = kCatBlueGray;

/// @deprecated 请用 kOverspendOrange。保留以兼容旧引用。
const Color kWarningOrange = kOverspendOrange;

// ---------------------------------------------------------------------------
// 语义色
// ---------------------------------------------------------------------------

/// 应用语义色（依 Brightness 区分深浅模式）。
class AppColors {
  AppColors._();

  /// 收入/正向金额 —— 铜金（浅色模式）。
  static const Color incomeLightMode = kCatGold;

  /// 收入/正向金额 —— 略亮金（深色模式更易读）。
  static const Color incomeDarkMode = Color(0xFFF7CC6E);

  /// 支出/普通金额 —— 跟随系统文字色（onSurface），
  /// 不在此处硬编码，直接用 Theme.of(context).colorScheme.onSurface。

  /// 警示色（超支）—— 深浅模式均用柔和橙。
  static const Color warning = kOverspendOrange;

  /// 根据当前 [ColorScheme] 返回收入颜色。
  static Color income(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark ? incomeDarkMode : incomeLightMode;

  /// 支出颜色直接返回 onSurface（中性文本色）。
  static Color expense(ColorScheme scheme) => scheme.onSurface;
}

// ---------------------------------------------------------------------------
// 主题工厂
// ---------------------------------------------------------------------------

/// 全 App 页面转场：用 iOS 风（横向滑入 + 从左缘侧滑返回）。
/// 设在主题里 → 所有 MaterialPageRoute 自动生效，无需逐个跳转点改。
const PageTransitionsTheme _kIosPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
  },
);

/// Material 3 ColorScheme 工厂：浅色 + 深色。
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final cs = ColorScheme.fromSeed(
      seedColor: kCatBlueGray,
      brightness: Brightness.light,
    ).copyWith(
      primary: kCatBlueGray,
      secondary: kCatGold,
      tertiary: kCatPink,
      // 全局白底：surface 及各级 container 去掉蓝紫 tint，统一中性白/浅灰，消除断层
      surface: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF7F8FA),
      surfaceContainer: const Color(0xFFF3F4F6),
      surfaceContainerHigh: const Color(0xFFEEEFF2),
      surfaceContainerHighest: const Color(0xFFEAECEF),
    );

    return ThemeData(
      colorScheme: cs,
      scaffoldBackgroundColor: Colors.white,
      useMaterial3: true,
      pageTransitionsTheme: _kIosPageTransitions,
      // AppBar 全白、无 tint、无滚动浮起阴影，与正文背景无缝
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      // 卡片：圆角 20、低阴影
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: Colors.white,
      ),
      // FilledButton：全圆角（Stadium）
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
        ),
      ),
      // ElevatedButton：大圆角
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: const StadiumBorder(),
        ),
      ),
      // 输入框：圆角
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: kCatBlueGray.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: kCatBlueGray, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  static ThemeData dark() {
    // 暖夜深色：fromSeed dark + 暖灰 surface，primary 用略亮蓝灰、secondary 金
    final cs = ColorScheme.fromSeed(
      seedColor: kCatBlueGray,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF9DAFC0), // 略亮蓝灰
      secondary: kCatGold,
      tertiary: kCatPink,
      surface: const Color(0xFF2A2825), // 暖灰 surface
      onSurface: const Color(0xFFEDE8E0), // 暖白文字
    );

    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      pageTransitionsTheme: _kIosPageTransitions,
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: const Color(0xFF332F2C),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: const Color(0xFF9DAFC0).withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0xFF9DAFC0),
            width: 1.5,
          ),
        ),
        filled: true,
        fillColor: const Color(0xFF332F2C),
      ),
    );
  }
}
