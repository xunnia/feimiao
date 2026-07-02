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

  /// 卡片底色：浅色纯白 / 深色暖灰，跟随主题，避免深色下死白。
  static Color card(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
          ? const Color(0xFF332F2C)
          : Colors.white;

  /// 页面背景：浅色淡灰 / 深色更深暖灰（比卡片暗一档，让卡片浮起来）。
  static Color appBg(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
          ? const Color(0xFF211E1C)
          : const Color(0xFFF7F8FA);

  /// 发丝描边：浅色=淡黑、深色=淡白。
  /// 别再手写 `Colors.black.withValues(alpha: 0.06)`——深色模式下会看不见。
  static Color hairline(ColorScheme scheme, {double strength = 1}) =>
      scheme.brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.10 * strength)
          : Colors.black.withValues(alpha: 0.06 * strength);

  /// 输入框填充底：浅色 iOS systemGray6 / 深色暖灰（比卡片再深一点）。
  static Color inputFill(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
          ? const Color(0xFF3B3733)
          : const Color(0xFFF2F2F7);
}

// ---------------------------------------------------------------------------
// 主题工厂
// ---------------------------------------------------------------------------

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
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      useMaterial3: true,
      // 全局 iOS 化：返回键变 ‹ 箭头、列表滚动回弹、自适应控件转 Cupertino
      platform: TargetPlatform.iOS,
      // 发丝分隔线（0.5px、极淡）
      dividerTheme: const DividerThemeData(
        thickness: 0.5,
        space: 0.5,
        color: Color(0x1F000000),
      ),
      // AppBar 与正文同灰、无 tint、无滚动浮起阴影，无缝衔接
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F8FA),
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
      scaffoldBackgroundColor: const Color(0xFF211E1C),
      useMaterial3: true,
      platform: TargetPlatform.iOS,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF211E1C),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        thickness: 0.5,
        space: 0.5,
        color: Color(0x24FFFFFF),
      ),
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
