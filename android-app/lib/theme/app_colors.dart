import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

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

  /// 预算健康态——沿用预算卡最初的低饱和绿色。
  ///
  /// 预算进度表达的是「额度仍健康」，不是品牌选中态，不能跟随主题主色；
  /// 否则蓝灰主题会把健康进度误画成灰色。深色模式略提亮以保持辨识度。
  static const Color budgetHealthyLightMode = Color(0xFF7FB069);
  static const Color budgetHealthyDarkMode = Color(0xFF9AC584);

  /// 根据当前 [ColorScheme] 返回收入颜色。
  static Color income(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark ? incomeDarkMode : incomeLightMode;

  static Color budgetHealthy(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
          ? budgetHealthyDarkMode
          : budgetHealthyLightMode;

  /// 支出颜色直接返回 onSurface（中性文本色）。
  static Color expense(ColorScheme scheme) => scheme.onSurface;

  /// 全局玻璃卡片透明度**默认值**（2026-07-11 主题系统上线后，
  /// 实际生效值是下面的运行时字段，由 AppThemeController 灌入；
  /// 这里的 const 只是出厂默认=暖橙 40%）。选中态 36% 用户点名"还不错"，别动。
  /// 小组件 compact 渲染仍实心，不受主题影响。
  static const double cardAlphaLight = 0.40;
  static const double cardAlphaDark = 0.55;
  static const double selectedCardAlphaLight = 0.36;
  static const double selectedCardAlphaDark = 0.46;

  // ── 主题系统运行时字段（唯一写入口 applyTheme，别处不许改）──
  static double _cardAlphaL = cardAlphaLight;
  static double _cardAlphaD = cardAlphaDark;
  static Color _bgTop = warmBackgroundTop;
  static Color _bgBottom = warmBackgroundBottom;
  static bool _bgSolid = false;
  static Color _bgDark = const Color(0xFF211E1C);
  static Color _bgDarkTop = const Color(0xFF211E1C);

  /// 主题系统唯一写入口：AppThemeController 把算好的具体颜色灌进来。
  /// 语义色（收入铜金/预算健康绿/超支橙/主色蓝灰）不在此列——永不开放，守配色铁律。
  static void applyTheme({
    required Color bgTop,
    required Color bgBottom,
    required bool bgSolid,
    required double cardAlphaL,
    required double cardAlphaD,
    required Color bgDark,
    required Color bgDarkTop,
  }) {
    _bgTop = bgTop;
    _bgBottom = bgBottom;
    _bgSolid = bgSolid;
    _cardAlphaL = cardAlphaL;
    _cardAlphaD = cardAlphaD;
    _bgDark = bgDark;
    _bgDarkTop = bgDarkTop;
  }

  /// 卡片底色：浅色半透明白 / 深色半透明暖灰，透明度跟主题走。
  static Color card(ColorScheme scheme) => scheme.brightness == Brightness.dark
      ? const Color(0xFF332F2C).withValues(alpha: _cardAlphaD)
      : Colors.white.withValues(alpha: _cardAlphaL);

  /// 选中态卡片底色：比普通卡片更低透明度，形成轻微灰玻璃选中块。
  static Color selectedCard(ColorScheme scheme) => scheme.brightness ==
          Brightness.dark
      ? scheme.surfaceContainerHighest.withValues(alpha: selectedCardAlphaDark)
      : Colors.white.withValues(alpha: selectedCardAlphaLight);

  /// 半透明卡片上的进度底轨。彩色背景继续使用透白轨道；简约白背景
  /// 改用克制的中性灰，否则白卡、白轨和灰白页底会融成一片。
  static Color cardTrack(ColorScheme scheme) {
    if (scheme.brightness == Brightness.dark) {
      return Colors.white.withValues(alpha: 0.14);
    }
    final isNearWhiteSolid = _bgSolid && _bgBottom.computeLuminance() >= 0.90;
    return isNearWhiteSolid
        ? scheme.onSurface.withValues(alpha: 0.09)
        : Colors.white.withValues(alpha: 0.56);
  }

  /// 全 App 背景渐变（浅色模式），跟主题色卡走；出厂默认=暖橙。
  /// 纯色色卡（简约白）= 上下同色的退化渐变，调用点无需分支。
  /// 深色模式不用渐变（appBg 纯色）。
  static const Color warmBackgroundTop = Color(0xFFFAE0B0);
  static const Color warmBackgroundBottom = Color(0xFFFFFDF7);
  static LinearGradient get warmBackground => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _bgSolid ? [_bgBottom, _bgBottom] : [_bgTop, _bgBottom],
        stops: const [0.0, 0.85],
      );

  /// 顶部虚化层的染色：跟背景顶色走（灰白会把状态栏区域洗成白色）。
  static Color topFrostTint(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
          ? _bgDarkTop
          : (_bgSolid ? _bgBottom : _bgTop);

  /// 页面背景：浅色淡灰 / 深色跟主题（暮夜=冷夜黑，默认=暖黑）。
  static Color appBg(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark ? _bgDark : const Color(0xFFF7F8FA);

  /// 整页背景装饰：浅色=主题渐变、深色=主题纯色。
  /// 页面转场底/路由底一律用它，别再 const 写死。
  static BoxDecoration pageBackground(Brightness brightness) =>
      brightness == Brightness.dark
          ? BoxDecoration(color: _bgDark)
          : BoxDecoration(gradient: warmBackground);

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

/// 深色模式的页面底色（渐变只给浅色用）。
const Color kDarkPageBg = Color(0xFF211E1C);

/// iOS 式转场 + 每个路由自带不透明暖渐变底。
/// 之前渐变只铺在 MaterialApp builder（Navigator 之下）、页面全透明——
/// Cupertino 转场时新旧两页互相透视（错位感）且失去不透明页优化（卡顿）。
/// 在转场器里给每页垫一层自己的背景，转场干净、合成器也能按不透明页处理。
class _GradientCupertinoTransitionsBuilder extends PageTransitionsBuilder {
  const _GradientCupertinoTransitionsBuilder();

  static const _cupertino = CupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _cupertino.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      DecoratedBox(
        decoration: AppColors.pageBackground(
            isDark ? Brightness.dark : Brightness.light),
        child: child,
      ),
    );
  }
}

const PageTransitionsTheme _iosPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: _GradientCupertinoTransitionsBuilder(),
    TargetPlatform.iOS: _GradientCupertinoTransitionsBuilder(),
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
      // 透明：透出 MaterialApp builder 铺的全局暖渐变背景（warmBackground）。
      scaffoldBackgroundColor: Colors.transparent,
      useMaterial3: true,
      // 全局 iOS 化：返回键变 ‹ 箭头、列表滚动回弹、自适应控件转 Cupertino
      platform: TargetPlatform.iOS,
      // 所有二三级页面支持左缘右滑返回（Android 默认 Zoom 转场没有此手势）。
      pageTransitionsTheme: _iosPageTransitions,
      // 发丝分隔线（0.5px、极淡）
      dividerTheme: const DividerThemeData(
        thickness: 0.5,
        space: 0.5,
        color: Color(0x1F000000),
      ),
      // AppBar 与正文同灰、无 tint、无滚动浮起阴影，无缝衔接。
      // 全局统一返回键/标题/加号按钮：标题居中 17/w600，图标中性 onSurface 21，
      // 各页面 AppBar 从此一个样，不再各写各的。
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        // 暖渐变浅背景上状态栏图标必须深色，白字看不清（用户点名）。
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
        iconTheme: IconThemeData(color: cs.onSurface, size: 21),
        actionsIconTheme: IconThemeData(color: cs.onSurface, size: 21),
      ),
      // 卡片：圆角 20、低阴影
      cardTheme: CardThemeData(
        elevation: 1,
        // Card 默认按 elevation 叠加 primary 色调，会把半透明白卡染灰。
        // 关闭后与直接使用 AppColors.card 的设置卡保持一致。
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: AppColors.card(cs),
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
        hintStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
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
      pageTransitionsTheme: _iosPageTransitions,
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF211E1C),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        // 深色背景上状态栏图标必须浅色（和浅色主题对称，别靠默认推断）。
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
        iconTheme: IconThemeData(color: cs.onSurface, size: 21),
        actionsIconTheme: IconThemeData(color: cs.onSurface, size: 21),
      ),
      dividerTheme: const DividerThemeData(
        thickness: 0.5,
        space: 0.5,
        color: Color(0x24FFFFFF),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: AppColors.card(cs),
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
        hintStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
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
