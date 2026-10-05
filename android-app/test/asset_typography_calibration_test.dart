import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/account/net_worth_snapshot.dart';
import 'package:qingji/core/app_clock.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/assets/asset_overview_dashboard.dart';

import 'asset_overview_projection_test.dart' show snapshot;
import 'screenshot_font_support.dart';

const _output = 'outputs/ui_comparisons/2026-10-03-asset-typography';

Future<void> _capture(WidgetTester tester, Key key, String name) async {
  if (Platform.environment['UPDATE_ASSET_SCREENSHOTS'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    await loadScreenshotFonts(force: true);
    final nunito = FontLoader('Nunito');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      nunito.addFont(rootBundle.load('assets/fonts/Nunito-$weight.ttf'));
    }
    await nunito.load();
    for (final entry in {
      'AssetLabels': 'assets/fonts/AssetLabels-VF.ttf',
      'AssetAmount': 'assets/fonts/Nunito-ExtraBold.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });

  testWidgets('reference numeral candidates use actual bundled fonts',
      (tester) async {
    if (Platform.environment['ASSET_FONT_CANDIDATES'] != '1') return;
    await tester.binding.setSurfaceSize(const Size(420, 912));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const key = ValueKey('candidate-sheet');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Material(
          child: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: const Color(0xFFFAF3EC),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final size in [22.0, 22.5, 23.0])
                  SizedBox(
                    height: 72,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('metric $size / 800 / ss01',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                        Text('13.4 MB',
                            key: ValueKey('candidate-metric-$size'),
                            style: TextStyle(
                              fontFamily: 'AssetAmount',
                              fontSize: size,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [ui.FontFeature('ss01')],
                              color: Colors.black,
                              height: 1.2,
                            )),
                      ],
                    ),
                  ),
                for (final size in [40.0, 41.5, 41.75, 42.0])
                  SizedBox(
                    height: 78,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('hero $size / 800 / ss01',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                        Text('10,369',
                            key: ValueKey('candidate-hero-$size'),
                            style: TextStyle(
                              fontFamily: 'AssetAmount',
                              fontSize: size,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [ui.FontFeature('ss01')],
                              color: Colors.black,
                              height: 1.1,
                            )),
                      ],
                    ),
                  ),
                for (final size in [12.5, 13.0, 13.5])
                  SizedBox(
                    height: 60,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('label $size / 400',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                        Text('带宽',
                            key: ValueKey('candidate-label-$size'),
                            style: TextStyle(
                                fontFamily: screenshotCjkFontFamily,
                                fontSize: size,
                                fontVariations: const [
                                  ui.FontVariation('wght', 400)
                                ],
                                color: const Color(0xFF868384),
                                height: 1.35)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _capture(tester, key, 'font-candidates');
    if (Platform.environment['UPDATE_ASSET_SCREENSHOTS'] == '1') {
      final bounds = <String, List<double>>{};
      for (final (kind, sizes) in [
        ('metric', [22.0, 22.5, 23.0]),
        ('hero', [40.0, 41.5, 41.75, 42.0]),
        ('label', [12.5, 13.0, 13.5]),
      ]) {
        for (final size in sizes) {
          final rect =
              tester.getRect(find.byKey(ValueKey('candidate-$kind-$size')));
          bounds['$kind-$size'] = [rect.left, rect.top, rect.right, rect.bottom]
              .map((value) => value * 3)
              .toList();
        }
      }
      File('$_output/font-candidate-bounds.json')
          .writeAsStringSync(jsonEncode(bounds));
    }
  });

  for (final preset in [
    kThemePresets.first,
    kThemePresets[1],
    kThemePresets.last,
  ]) {
    for (final scenario in [
      (false, false, false),
      (true, false, false),
      (false, true, false),
      (false, false, true),
    ]) {
      final (partial, highContrast, longAmount) = scenario;
      testWidgets(
          'typography ${preset.key} partial $partial highContrast $highContrast long $longAmount',
          (tester) async {
        final size = Size(longAmount ? 320 : 420, 912);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        AppColors.applyTheme(
          bgTop: preset.top,
          bgBottom: preset.bottom,
          bgSolid: preset.solid,
          cardAlphaL: 0.8,
          cardAlphaD: 0.8,
          bgDark: preset.bottom,
          bgDarkTop: preset.top,
        );
        final theme = preset.forceDark ? AppTheme.dark() : AppTheme.light();
        const captureKey = ValueKey('typography-dashboard');
        final now = AppClock.now;
        final points = [
          for (var index = 0; index < 7; index++)
            snapshot(
              DateTime(now.year, now.month, now.day - 84 + index * 14),
              cash: partial ? 260000 : 700000 + index * 10000,
              physical: partial ? 0 : 210000,
              liabilities: partial ? 750748 : 45000,
              scope: partial && index > 2 ? 2 : 1,
            ),
        ];
        await tester.pumpWidget(MaterialApp(
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(size: size, highContrast: highContrast),
            child: child!,
          ),
          theme: theme.copyWith(
              textTheme: theme.textTheme
                  .apply(fontFamilyFallback: const [screenshotCjkFontFamily])),
          home: RepaintBoundary(
            key: captureKey,
            child: DecoratedBox(
              decoration: AppColors.pageBackground(theme.brightness),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: AssetOverviewDashboard(
                    breakdown: NetWorthBreakdown(
                      netWorth: Decimal.parse(longAmount
                          ? '9876543000.99'
                          : partial
                              ? '-4907.48'
                              : '9250'),
                      totalAssets: Decimal.parse(longAmount
                          ? '9876543210.99'
                          : partial
                              ? '2600'
                              : '9700'),
                      cashAssets: Decimal.parse(longAmount
                          ? '9876541110.99'
                          : partial
                              ? '2600'
                              : '7600'),
                      physicalAssets: Decimal.parse(partial ? '0' : '2100'),
                      totalLiabilities: Decimal.parse(longAmount
                          ? '210'
                          : partial
                              ? '7507.48'
                              : '450'),
                      investmentAssets: Decimal.zero,
                      receivableAssets: Decimal.zero,
                    ),
                    trend: resolveNetWorthTrend(points),
                    partial: partial,
                    excludedCount: partial ? 4 : 0,
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final mainTitle = find.byKey(const ValueKey('asset-net-worth-title'));
        final smallTitle = find.descendant(
            of: find.byKey(const ValueKey('asset-metric-funds')),
            matching: find.text('资金资产'));
        expect(tester.widget<Text>(mainTitle).style,
            tester.widget<Text>(smallTitle).style);
        final titleStyle = tester.widget<Text>(mainTitle).style!;
        expect(titleStyle.fontSize, 12.5);
        expect(
            titleStyle.fontVariations, const [ui.FontVariation('wght', 400)]);
        expect(
            titleStyle.color,
            highContrast
                ? theme.colorScheme.onSurface
                : preset.forceDark
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.65)
                    : const Color(0xFF868384));
        expect(
            tester.getTopLeft(mainTitle).dx, tester.getTopLeft(smallTitle).dx);
        final mainAmount = find.descendant(
            of: find.byKey(const ValueKey('asset-net-worth-card')),
            matching: find.byWidgetPredicate((widget) =>
                widget is Text && widget.style?.fontFamily == 'AssetAmount'));
        final mainAmountStyle = tester.widget<Text>(mainAmount).style!;
        expect(mainAmountStyle.fontSize, 41.75);
        expect(mainAmountStyle.fontWeight, FontWeight.w800);
        expect(mainAmountStyle.fontFeatures, const [ui.FontFeature('ss01')]);
        expect(
            mainAmountStyle.color,
            partial
                ? preset.forceDark
                    ? AppColors.warning
                    : Color.lerp(AppColors.warning, Colors.black, 0.4)
                : preset.forceDark
                    ? theme.colorScheme.onSurface
                    : Colors.black);
        final metric = find.byKey(const ValueKey('asset-metric-funds'));
        final amountText = find.descendant(
            of: metric,
            matching: find.byWidgetPredicate((widget) =>
                widget is Text && widget.style?.fontFamily == 'AssetAmount'));
        final amountStyle = tester.widget<Text>(amountText).style!;
        expect(amountStyle.fontSize, 22.5);
        expect(amountStyle.fontWeight, FontWeight.w800);
        expect(amountStyle.fontFeatures, const [ui.FontFeature('ss01')]);
        final card = tester.getRect(metric);
        final amount = tester.getRect(amountText);
        expect(amount.left, greaterThanOrEqualTo(card.left + 16));
        expect(amount.right, lessThanOrEqualTo(card.right - 16));
        final stage = Platform.environment['ASSET_SHOT_SUFFIX'] ?? 'after';
        await _capture(tester, captureKey,
            'dashboard-${preset.key}-${partial ? 'partial' : 'complete'}${highContrast ? '-high-contrast' : ''}${longAmount ? '-long' : ''}-$stage');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
