import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/settings/backup_view.dart';
import 'package:qingji/views/settings/theme_settings_view.dart';

void main() {
  test('legacy minimal preference keeps its saved appearance and is not saved',
      () {
    final preferences = AppThemePreferences.fromJson({
      'preset': 'white',
      'intensity': 1.0,
      'cardAlpha': 0.90,
      'minimal': true,
    });

    expect(preferences.presetKey, 'white');
    expect(preferences.bgIntensity, 1.0);
    expect(preferences.cardAlpha, 0.90);
    expect(preferences.toJson(), isNot(contains('minimal')));
  });

  test('minimal-only legacy preference falls back to its former appearance',
      () {
    final preferences = AppThemePreferences.fromJson({'minimal': true});

    expect(preferences.presetKey, 'white');
    expect(preferences.bgIntensity, 1.0);
    expect(preferences.cardAlpha, 0.90);
  });

  test('backup page limits display without deleting protected files', () {
    final all = List.generate(5, (index) => File('backup-$index.bak'));

    final visible = localBackupsForDisplay(all);

    expect(visible.map((file) => file.path), [
      'backup-0.bak',
      'backup-1.bak',
      'backup-2.bak',
    ]);
    expect(all, hasLength(5));
  });

  testWidgets('six theme presets stay on one row at a narrow phone width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppThemeController>.value(
        value: AppThemeController.instance,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ThemeSettingsView(),
        ),
      ),
    );
    await tester.pump();

    final tops = [
      for (final preset in kThemePresets)
        tester.getTopLeft(find.text(preset.nameZh)).dy,
    ];
    expect(tops.reduce((a, b) => a < b ? a : b), closeTo(tops.first, 0.01));
    expect(tops.reduce((a, b) => a > b ? a : b), closeTo(tops.first, 0.01));
    expect(find.text('极简模式'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme sliders use the preset accent and iOS slider control',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppThemeController>.value(
        value: AppThemeController.instance,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ThemeSettingsView(),
        ),
      ),
    );
    await tester.pump();

    final sliders = tester.widgetList<CupertinoSlider>(
      find.byType(CupertinoSlider),
    );
    expect(sliders, hasLength(2));
    for (final slider in sliders) {
      expect(
        slider.activeColor,
        AppThemeController.instance.preset.controlAccent,
      );
    }
    final white = kThemePresets.singleWhere((preset) => preset.key == 'white');
    expect(white.controlAccent, kCatBlueGray);
  });
}
