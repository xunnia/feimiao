import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/widgets/widget_card_renderer.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/widgets/glass.dart';
import 'package:qingji/widgets/home_summary_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('white preset restores the historical off-white page background', () {
    final preset = kThemePresets.singleWhere((item) => item.key == 'white');

    expect(preset.top, const Color(0xFFF7F8FA));
    expect(preset.bottom, const Color(0xFFF7F8FA));
    expect(preset.solid, isTrue);
  });

  test('Material cards do not add a second theme tint', () {
    expect(AppTheme.light().cardTheme.surfaceTintColor, Colors.transparent);
    expect(AppTheme.dark().cardTheme.surfaceTintColor, Colors.transparent);
  });

  test('budget tracks stay translucent white on colored themes', () {
    AppColors.applyTheme(
      bgTop: const Color(0xFFFAE0B0),
      bgBottom: const Color(0xFFFFFDF7),
      bgSolid: false,
      cardAlphaL: 0.40,
      cardAlphaD: 0.55,
      bgDark: const Color(0xFF211E1C),
      bgDarkTop: const Color(0xFF211E1C),
    );
    final color = AppColors.cardTrack(AppTheme.light().colorScheme);

    expect(color.r, 1);
    expect(color.g, 1);
    expect(color.b, 1);
    expect(color.a, closeTo(0.56, 0.001));
  });

  test('white theme budget tracks use a visible neutral gray', () {
    AppColors.applyTheme(
      bgTop: const Color(0xFFF7F8FA),
      bgBottom: const Color(0xFFF7F8FA),
      bgSolid: true,
      cardAlphaL: 0.40,
      cardAlphaD: 0.55,
      bgDark: const Color(0xFF211E1C),
      bgDarkTop: const Color(0xFF211E1C),
    );
    addTearDown(() {
      AppColors.applyTheme(
        bgTop: const Color(0xFFFAE0B0),
        bgBottom: const Color(0xFFFFFDF7),
        bgSolid: false,
        cardAlphaL: 0.40,
        cardAlphaD: 0.55,
        bgDark: const Color(0xFF211E1C),
        bgDarkTop: const Color(0xFF211E1C),
      );
    });

    final color = AppColors.cardTrack(AppTheme.light().colorScheme);

    expect(color.r, lessThan(1));
    expect(color.g, lessThan(1));
    expect(color.b, lessThan(1));
    expect(color.a, closeTo(0.09, 0.001));
  });

  testWidgets('home glass surface composites to the requested white tint',
      (tester) async {
    const background = Color(0xFFFAE0B0);
    const fill = Color(0x66FFFFFF);
    final rendered = await tester.runAsync(() async {
      final png = await renderWidgetToPng(
        const ColoredBox(
          color: background,
          child: Center(
            child: SizedBox(
              width: 120,
              height: 80,
              child: GlassSurface(
                blur: 0,
                fillColor: fill,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
        logicalSize: const Size(160, 120),
        pixelRatio: 1,
      );
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final offset = (60 * frame.image.width + 80) * 4;
      final color = Color.fromARGB(
        data!.getUint8(offset + 3),
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
      frame.image.dispose();
      codec.dispose();
      return color;
    });

    final expected = Color.alphaBlend(fill, background);
    const channelTolerance = 1.1 / 255;
    expect(rendered!.a, closeTo(expected.a, channelTolerance));
    expect(rendered.r, closeTo(expected.r, channelTolerance));
    expect(rendered.g, closeTo(expected.g, channelTolerance));
    expect(rendered.b, closeTo(expected.b, channelTolerance));
    expect(rendered.r, greaterThan(background.r));
    expect(rendered.g, greaterThan(background.g));
    expect(rendered.b, greaterThan(background.b));
  });

  testWidgets('home summary never uses an elevated Material Card',
      (tester) async {
    final summary = MonthlySummary(
      year: 2026,
      month: 7,
      totalExpense: Decimal.zero,
      totalIncome: Decimal.zero,
      expenseByCategory: [],
      dailyTotals: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HomeSummaryCard(
            monthDate: DateTime(2026, 7),
            isCurrentMonth: true,
            summary: summary,
            budgetStatus: null,
            budget: null,
          ),
        ),
      ),
    );

    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
    testWidgets(
        'home mascot overlaps the card edge without leaving a narrow screen',
        (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final summary = MonthlySummary(
        year: 2026,
        month: 7,
        totalExpense: Decimal.zero,
        totalIncome: Decimal.zero,
        expenseByCategory: const [],
        dailyTotals: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: HomeSummaryCard(
              monthDate: DateTime(2026, 7),
              isCurrentMonth: true,
              summary: summary,
              budgetStatus: null,
              budget: null,
            ),
          ),
        ),
      );

      final surface = tester.getRect(
        find.byKey(const ValueKey('home-summary-card-surface')),
      );
      final mascotAnchor = tester.getRect(
        find.byKey(const ValueKey('home-summary-mascot-anchor')),
      );

      // The 4dp box bleed covers the PNG's ~1.8dp transparent right inset and
      // leaves a small visual overlap with the one-pixel card outline.
      expect(mascotAnchor.right - surface.right, closeTo(4, 0.01));
      expect(mascotAnchor.right, lessThanOrEqualTo(320));
    });
  }

  // This only guards against a second Material surface tint in the software
  // renderer. OEM GPU elevation composition is covered by keeping the home
  // surface out of Material Card entirely in the test above.
  testWidgets('offscreen Material Card adds no second surface tint',
      (tester) async {
    final colors = await tester.runAsync(() async {
      final png = await renderWidgetToPng(
        const ColoredBox(
          color: Color(0xFFF7F8FA),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: ColoredBox(color: Color(0x66FFFFFF)),
              ),
              SizedBox(
                width: 120,
                height: 120,
                child: Card(
                  margin: EdgeInsets.zero,
                  color: Color(0x66FFFFFF),
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
        logicalSize: const Size(240, 120),
        pixelRatio: 1,
      );
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final image = frame.image;

      Color pixelAt(int x, int y) {
        final offset = (y * image.width + x) * 4;
        return Color.fromARGB(
          data!.getUint8(offset + 3),
          data.getUint8(offset),
          data.getUint8(offset + 1),
          data.getUint8(offset + 2),
        );
      }

      final result = (direct: pixelAt(60, 60), card: pixelAt(180, 60));
      image.dispose();
      codec.dispose();
      return result;
    });

    expect(colors, isNotNull);
    expect(colors!.card, colors.direct);
  });
}
