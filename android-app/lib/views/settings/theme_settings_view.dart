import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme_controller.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/settings_ui.dart';

/// 主题外观设置页：6 张色卡 + 背景浓度/卡片透明度滑杆。
/// 只管"氛围层"（背景+卡片质感）；语义色永不开放（配色铁律）。
class ThemeSettingsView extends StatelessWidget {
  const ThemeSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeController>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('主题外观'),
        backgroundColor: Colors.transparent,
        actions: [
          // 恢复默认（暖橙 40%）
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AppPillButton(
              label: '恢复默认',
              onPressed: theme.presetKey == 'warm' &&
                      theme.bgIntensity == 1.0 &&
                      theme.cardAlpha == 0.40
                  ? null
                  : theme.resetDefault,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Preview(),
          const SizedBox(height: 18),
          const SettingsSectionLabel('背景色卡'),
          const _PresetGrid(),
          const SizedBox(height: 18),
          if (!theme.preset.solid && !theme.forceDark) ...[
            const SettingsSectionLabel('背景浓度'),
            SettingsGroup(children: [
              _SliderRow(
                leadingIcon: CupertinoIcons.sun_min,
                trailingIcon: CupertinoIcons.sun_max_fill,
                semanticLabel: '背景浓度',
                value: theme.bgIntensity,
                min: 0,
                max: 1,
                activeColor: theme.preset.controlAccent,
                onChanged: theme.setIntensity,
              ),
            ]),
            const SizedBox(height: 18),
          ],
          const SettingsSectionLabel('卡片透明度'),
          SettingsGroup(children: [
            _SliderRow(
              leadingIcon: CupertinoIcons.square_on_square,
              trailingIcon: CupertinoIcons.square_fill_on_square_fill,
              semanticLabel: '卡片透明度',
              value: theme.cardAlpha,
              min: 0.25,
              max: 0.90,
              activeColor: theme.preset.controlAccent,
              onChanged: theme.setCardAlpha,
            ),
          ]),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '主题只改变背景与卡片质感；收入金色、超支橙色等记账语义色保持不变。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 实时预览：迷你主页（背景 + 大卡 + 两行账单卡缩影）。
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    context.watch<AppThemeController>();
    Widget miniCard(double h, double w) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: AppColors.card(scheme),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.hairline(scheme)),
          ),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 176,
        decoration: AppColors.pageBackground(scheme.brightness),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            miniCard(64, double.infinity),
            const SizedBox(height: 10),
            miniCard(30, 210),
            const SizedBox(height: 10),
            miniCard(30, 260),
          ],
        ),
      ),
    );
  }
}

class _PresetGrid extends StatelessWidget {
  const _PresetGrid();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeController>();
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < kThemePresets.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => theme.setPreset(kThemePresets[i].key),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: kThemePresets[i].solid
                            ? [kThemePresets[i].bottom, kThemePresets[i].bottom]
                            : [kThemePresets[i].top, kThemePresets[i].bottom],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.presetKey == kThemePresets[i].key
                            ? kCatGold
                            : AppColors.hairline(scheme),
                        width: theme.presetKey == kThemePresets[i].key ? 2 : 1,
                      ),
                    ),
                    child: theme.presetKey == kThemePresets[i].key
                        ? const Center(
                            child: Icon(Icons.check_rounded,
                                size: 18, color: kCatGold),
                          )
                        : null,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    kThemePresets[i].nameZh,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: theme.presetKey == kThemePresets[i].key
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final IconData leadingIcon;
  final IconData trailingIcon;
  final String semanticLabel;
  final double value;
  final double min;
  final double max;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.leadingIcon,
    required this.trailingIcon,
    required this.semanticLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
        children: [
          Icon(leadingIcon,
              size: 19, color: scheme.onSurface.withValues(alpha: 0.48)),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              label: semanticLabel,
              value: '${(value * 100).round()}%',
              child: CupertinoSlider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                activeColor: activeColor,
                thumbColor: scheme.surface,
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(trailingIcon,
              size: 21, color: scheme.onSurface.withValues(alpha: 0.48)),
        ],
      ),
    );
  }
}
