import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_colors.dart';

/// 主题预设色卡（2026-07-11 用户拍板：首发 6 张，猫系低饱和）。
/// 只开放「背景 + 卡片质感」；语义色（收入铜金/预算健康绿/超支橙/主色蓝灰）永不开放，
/// 守配色铁律。
class ThemePreset {
  final String key;
  final String nameZh;

  /// 渐变顶色（intensity=1 时的最深状态）。
  final Color top;

  /// 渐变底色；solid 时就是整页纯色。
  final Color bottom;

  /// 纯色简约（不渐变）。
  final bool solid;

  /// 深色专属（暮夜）：选中即强制深色模式。
  final bool forceDark;

  /// 主题设置滑杆的可见控制色。背景色本身都很浅，直接拿来画轨道会消失，
  /// 因此这里使用同色相、但满足可见度的代表色；简约白回退主色蓝灰。
  final Color controlAccent;

  const ThemePreset({
    required this.key,
    required this.nameZh,
    required this.top,
    required this.bottom,
    this.controlAccent = kCatBlueGray,
    this.solid = false,
    this.forceDark = false,
  });
}

const List<ThemePreset> kThemePresets = [
  // 默认 = 现状暖橙，用户现有观感零变化。
  ThemePreset(
      key: 'warm',
      nameZh: '暖橙',
      top: Color(0xFFFAE0B0),
      bottom: Color(0xFFFFFDF7),
      controlAccent: kCatGold),
  ThemePreset(
      key: 'white',
      nameZh: '简约白',
      // 恢复主题系统上线前的 #F7F8FA 页面底色。半透明白卡叠在
      // 略带灰的背景上，才能形成克制而清晰的明度层级。
      top: Color(0xFFF7F8FA),
      bottom: Color(0xFFF7F8FA),
      solid: true),
  ThemePreset(
      key: 'pink',
      nameZh: '樱粉',
      top: Color(0xFFF7D9E0),
      bottom: Color(0xFFFFFDFB),
      controlAccent: Color(0xFFD48699)),
  ThemePreset(
      key: 'mint',
      nameZh: '薄荷',
      top: Color(0xFFD8EEDF),
      bottom: Color(0xFFFBFEFC),
      controlAccent: Color(0xFF6C9F7F)),
  ThemePreset(
      key: 'blue',
      nameZh: '雾蓝',
      top: Color(0xFFD9E6F2),
      bottom: Color(0xFFFBFDFF),
      controlAccent: Color(0xFF7891AC)),
  ThemePreset(
      key: 'night',
      nameZh: '暮夜',
      top: Color(0xFF23262F),
      bottom: Color(0xFF17191F),
      controlAccent: Color(0xFF8E98AA),
      forceDark: true),
];

/// 可持久化的主题偏好。旧版本还会带 `minimal` 字段；解析时兼容它，
/// 重新保存则只写当前三个真实配置项。
class AppThemePreferences {
  final String presetKey;
  final double bgIntensity;
  final double cardAlpha;

  const AppThemePreferences({
    required this.presetKey,
    required this.bgIntensity,
    required this.cardAlpha,
  });

  factory AppThemePreferences.fromJson(Map<String, dynamic> json) {
    final legacyMinimal = json['minimal'] == true;
    return AppThemePreferences(
      presetKey:
          (json['preset'] as String?) ?? (legacyMinimal ? 'white' : 'warm'),
      bgIntensity: ((json['intensity'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.0, 1.0)
          .toDouble(),
      cardAlpha: ((json['cardAlpha'] as num?)?.toDouble() ??
              (legacyMinimal ? 0.90 : 0.40))
          .clamp(0.25, 0.90)
          .toDouble(),
    );
  }

  Map<String, Object> toJson() => {
        'preset': presetKey,
        'intensity': bgIntensity,
        'cardAlpha': cardAlpha,
      };
}

/// 主题外观控制器：背景色卡 / 背景浓度 / 卡片透明度。
/// 偏好存 JSON 文件（path_provider，App 支持目录）——不动数据库、
/// 不依赖 AppRepository（避开并行开发的文件集）。
class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();

  static const _fileName = 'theme_prefs.json';

  // 默认值 = 当前线上观感。
  String presetKey = 'warm';
  double bgIntensity = 1.0; // 0~1，渐变顶色深浅
  double cardAlpha = 0.40; // 0.25~0.90，浅色卡片透明度

  ThemePreset get preset => kThemePresets.firstWhere(
        (p) => p.key == presetKey,
        orElse: () => kThemePresets.first,
      );

  /// 暮夜色卡强制深色（与系统深浅色设置正交，选它就是要夜的样子）。
  bool get forceDark => preset.forceDark;

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_fileName');
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final preferences = AppThemePreferences.fromJson(m);
        presetKey = preferences.presetKey;
        bgIntensity = preferences.bgIntensity;
        cardAlpha = preferences.cardAlpha;
      }
    } catch (_) {
      // 读不到就用默认，不拦启动。
    }
    _applyToColors();
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_fileName');
      await f.writeAsString(jsonEncode(AppThemePreferences(
        presetKey: presetKey,
        bgIntensity: bgIntensity,
        cardAlpha: cardAlpha,
      ).toJson()));
    } catch (_) {}
  }

  /// 把当前主题算成具体颜色灌进 AppColors 的运行时字段。
  void _applyToColors() {
    final p = preset;
    // 浓度：顶色向底色插值（0=几乎纯底色，1=色卡原色）。
    final top = Color.lerp(p.bottom, p.top, bgIntensity) ?? p.top;
    AppColors.applyTheme(
      bgTop: top,
      bgBottom: p.bottom,
      bgSolid: p.solid,
      cardAlphaL: cardAlpha,
      // 深色卡片跟随浅色滑杆等比抬高一档（深色底需要更实的卡才可读）。
      cardAlphaD: (cardAlpha + 0.15).clamp(0.30, 0.95).toDouble(),
      bgDark: p.forceDark ? p.bottom : const Color(0xFF211E1C),
      bgDarkTop: p.forceDark ? p.top : const Color(0xFF211E1C),
    );
  }

  void _commit() {
    _applyToColors();
    notifyListeners();
    _save();
  }

  void setPreset(String key) {
    presetKey = key;
    _commit();
  }

  void setIntensity(double v) {
    bgIntensity = v.clamp(0.0, 1.0).toDouble();
    _commit();
  }

  void setCardAlpha(double v) {
    cardAlpha = v.clamp(0.25, 0.90).toDouble();
    _commit();
  }

  void resetDefault() {
    presetKey = 'warm';
    bgIntensity = 1.0;
    cardAlpha = 0.40;
    _commit();
  }
}
