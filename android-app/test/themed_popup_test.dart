import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/common/app_sheet.dart';
import 'package:qingji/widgets/ios_dialogs.dart';
import 'package:qingji/widgets/ios_form.dart';

void _apply(ThemePreset preset, {double intensity = 1, double alpha = 0.8}) {
  AppColors.applyTheme(
    bgTop: Color.lerp(preset.bottom, preset.top, intensity)!,
    bgBottom: preset.bottom,
    bgSolid: preset.solid,
    cardAlphaL: alpha,
    cardAlphaD: (alpha + 0.15).clamp(0.3, 0.95),
    bgDark: preset.forceDark ? preset.bottom : const Color(0xFF211E1C),
    bgDarkTop: preset.forceDark ? preset.top : const Color(0xFF211E1C),
  );
}

void main() {
  tearDown(() => _apply(kThemePresets.first));
  for (final preset in kThemePresets) {
    test('${preset.key} popup and input use the same theme palette', () {
      _apply(preset);
      final theme = preset.forceDark ? AppTheme.dark() : AppTheme.light();
      final scheme = theme.colorScheme;
      final expected = preset.forceDark
          ? Color.lerp(preset.bottom, Colors.white, 0.06)!
          : preset.solid
              ? Colors.white
              : Color.lerp(preset.bottom, preset.top, 0.35)!;
      expect(scheme.surface, expected);
      expect(theme.inputDecorationTheme.fillColor, AppColors.inputFill(scheme));
      expect(AppColors.inputFill(scheme), isNot(scheme.surface));
      final card =
          scheme.surface.withValues(alpha: preset.forceDark ? 0.88 : 0.86);
      final backdrop = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.35), scheme.surface);
      final renderedCard = Color.alphaBlend(card, backdrop);
      final renderedButton =
          Color.alphaBlend(AppColors.dialogFill(scheme), renderedCard);
      expect(
          renderedButton.computeLuminance(),
          preset.forceDark
              ? greaterThan(renderedCard.computeLuminance())
              : lessThan(renderedCard.computeLuminance()));
      final foreground = scheme.onSurface.computeLuminance();
      final background = scheme.surface.computeLuminance();
      final contrast = foreground > background
          ? (foreground + 0.05) / (background + 0.05)
          : (background + 0.05) / (foreground + 0.05);
      expect(contrast, greaterThan(7));
    });
  }

  test('background intensity changes the popup without making it transparent',
      () {
    final pink = kThemePresets.singleWhere((p) => p.key == 'pink');
    _apply(pink, intensity: 0);
    final faint = AppTheme.light();
    _apply(pink);
    final strong = AppTheme.light();
    expect(faint.colorScheme.surface, pink.bottom);
    expect(strong.colorScheme.surface, isNot(faint.colorScheme.surface));
    expect(strong, isNot(faint));
    _apply(pink, alpha: 0.25);
    expect(AppTheme.light().colorScheme.surface, strong.colorScheme.surface);
    expect(AppColors.sheetFill(faint.colorScheme),
        faint.colorScheme.surfaceContainerHigh);
  });

  Future<(BuildContext, ValueNotifier<ThemeData>)> pumpApp(
      WidgetTester tester) async {
    _apply(kThemePresets.first);
    final theme = ValueNotifier(AppTheme.light());
    addTearDown(theme.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeData>(
        valueListenable: theme,
        builder: (_, theme, __) => MaterialApp(
          theme: theme,
          home: Builder(builder: (ctx) {
            context = ctx;
            return const Scaffold(body: SizedBox.expand());
          }),
        ),
      ),
    );
    return (context, theme);
  }

  for (final kind in ['confirm', 'form', 'sheet']) {
    testWidgets('open $kind repaints on theme changes and keeps input',
        (tester) async {
      final (context, theme) = await pumpApp(tester);
      final controller = TextEditingController(text: '保留文字');
      addTearDown(controller.dispose);
      final Widget content = Builder(
        builder: (ctx) => TextField(
          controller: controller,
          decoration: iosInputDecoration(ctx),
        ),
      );
      final popup = switch (kind) {
        'confirm' => showConfirmDialog(context, title: '删除？', message: '测试'),
        'form' => showIosFormDialog(context, title: '修改名称', content: content),
        _ => appSheet<void>(context,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: content,
            )),
      };
      await tester.pumpAndSettle();
      if (kind != 'confirm') {
        await tester.enterText(find.byType(TextField), '输入的文字不丢');
      }
      final colors = <Color>[];
      for (final preset in [
        kThemePresets[2],
        kThemePresets.last,
        kThemePresets[1]
      ]) {
        _apply(preset);
        theme.value = preset.forceDark ? AppTheme.dark() : AppTheme.light();
        await tester.pumpAndSettle();
        final scheme = theme.value.colorScheme;
        if (kind == 'sheet') {
          final materials = tester.widgetList<Material>(find.byType(Material));
          expect(materials.any((m) => m.color == scheme.surface), isTrue);
        } else {
          final decorations = tester
              .widgetList<Container>(find.descendant(
                of: find.byType(FrostedDialogCard),
                matching: find.byType(Container),
              ))
              .map((c) => c.decoration)
              .whereType<BoxDecoration>();
          expect(
              decorations.any((d) =>
                  d.color ==
                  scheme.surface.withValues(
                    alpha: preset.forceDark ? 0.88 : 0.86,
                  )),
              isTrue);
        }
        if (kind != 'confirm') {
          final field = tester.widget<TextField>(find.byType(TextField));
          expect(field.decoration!.fillColor, AppColors.inputFill(scheme));
          expect(controller.text, '输入的文字不丢');
        }
        colors.add(scheme.surface);
        expect(tester.takeException(), isNull);
      }
      expect(colors.toSet(), hasLength(3));
      Navigator.of(context, rootNavigator: true).pop();
      await tester.pumpAndSettle();
      await popup;
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
