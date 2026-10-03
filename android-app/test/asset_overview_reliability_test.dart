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
import 'package:qingji/core/assets/asset_overview_projection.dart';
import 'package:qingji/core/money_cents.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/assets/asset_overview_dashboard.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/settings_ui.dart';

import 'asset_overview_projection_test.dart' show snapshot;
import 'screenshot_font_support.dart';

const _captureKey = ValueKey('asset-reliability-capture');

Future<void> _pump(WidgetTester tester, List<ComputedNetWorthSnapshot> points,
    {String theme = 'warm',
    Size size = const Size(420, 912),
    double scale = 1,
    bool partial = false}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final preset = kThemePresets.firstWhere((p) => p.key == theme);
  AppColors.applyTheme(
      bgTop: preset.top,
      bgBottom: preset.bottom,
      bgSolid: preset.solid,
      bgDark: preset.bottom,
      bgDarkTop: preset.top,
      cardAlphaL: 0.8,
      cardAlphaD: 0.8);
  final base = preset.forceDark ? AppTheme.dark() : AppTheme.light();
  final c = points.last.components;
  Decimal amount(int minor) => budgetDecimalFromCents(minor)!;
  await tester.pumpWidget(RepaintBoundary(
    key: _captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
          textTheme: base.textTheme
              .apply(fontFamilyFallback: const [screenshotCjkFontFamily])),
      builder: (_, child) => MediaQuery(
          data:
              MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
          child: DecoratedBox(
              decoration: AppColors.pageBackground(base.brightness),
              child: child)),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AssetOverviewDashboard(
            breakdown: NetWorthBreakdown(
                netWorth: amount(c.netWorthMinor),
                totalAssets: amount(c.totalAssetsMinor),
                cashAssets: amount(c.cashAssetsMinor),
                physicalAssets: amount(c.physicalAssetsMinor),
                totalLiabilities: amount(c.liabilitiesMinor),
                investmentAssets: amount(c.investmentAssetsMinor),
                receivableAssets: amount(c.receivableAssetsMinor)),
            trend: resolveNetWorthTrend(points),
            partial: partial,
            excludedCount: partial ? 2 : 0,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

List<String> _dateLabels(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((t) =>
        RegExp(r'^\d{1,2}/\d{1,2}$|^\d{4}\n\d{1,2}/\d{1,2}$').hasMatch(t))
    .toList();

void main() {
  setUpAll(() async {
    await loadScreenshotFonts(force: true);
    for (final entry in {
      'AssetLabels': 'assets/fonts/AssetLabels-VF.ttf',
      'AssetAmount': 'assets/fonts/Nunito-ExtraBold.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });
  tearDown(MoneyFormat.resetConfig);
  final now = AppClock.now;
  final day = DateTime(now.year, now.month, now.day);
  for (final days in [1, 2, 4, 80]) {
    testWidgets('$days day history has unique date labels', (tester) async {
      await _pump(tester, [
        snapshot(day.subtract(Duration(days: days))),
        snapshot(day, cash: 11000)
      ]);
      final labels = _dateLabels(tester);
      expect(labels, isNotEmpty);
      expect(labels.toSet().length, labels.length);
      expect(labels, contains('${day.month}/${day.day}'));
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets('cross-year dates are distinct at 320px scale $scale',
        (tester) async {
      await _pump(
          tester,
          [
            snapshot(DateTime(2025, 12, 31)),
            snapshot(DateTime(2026, 1, 1), cash: 11000)
          ],
          size: const Size(320, 900),
          scale: scale);
      expect(_dateLabels(tester), ['2025\n12/31', '2026\n1/1']);
      final chart = tester.getRect(find.byType(AssetOverviewChart).first);
      final rects =
          _dateLabels(tester).map((t) => tester.getRect(find.text(t))).toList();
      expect(rects.last.left, greaterThanOrEqualTo(rects.first.right + 4));
      for (final rect in rects) {
        expect(rect.left, greaterThanOrEqualTo(chart.left));
        expect(rect.right, lessThanOrEqualTo(chart.right));
        expect(rect.bottom, lessThanOrEqualTo(chart.bottom));
      }
    });
  }
  for (final mode in MoneyIntegerRoundingMode.values) {
    testWidgets('negative change uses signed $mode rounding', (tester) async {
      MoneyFormat.configure(decimalPlaces: 0, integerRoundingMode: mode);
      await _pump(tester, [
        snapshot(day.subtract(const Duration(days: 1))),
        snapshot(day, cash: 9880)
      ]);
      final expected =
          MoneyFormat.string(Decimal.parse('-1.20')).replaceAll('¥', '').trim();
      expect(find.text('区间变化 $expected'), findsOneWidget);
    });
  }
  testWidgets('reader summaries include each metric endpoint and quality',
      (tester) async {
    final handle = tester.ensureSemantics();
    final points = [
      snapshot(day.subtract(const Duration(days: 80))),
      snapshot(day.subtract(const Duration(days: 40)), scope: 2),
      snapshot(day, cash: 11000, scope: 2)
    ];
    await _pump(tester, points);
    try {
      for (final metric in AssetOverviewMetric.values) {
        final chart = find.byWidgetPredicate(
            (w) => w is AssetOverviewChart && w.metric == metric);
        final label = tester
            .widget<Semantics>(find
                .descendant(of: chart, matching: find.byType(Semantics))
                .first)
            .properties
            .label!;
        expect(label, contains(metric.label));
        expect(label, contains('${day.year}年${day.month}月${day.day}日'));
        expect(
            label,
            contains(MoneyFormat.string(budgetDecimalFromCents(
                metric.minor(points.last.components))!)));
        expect(label, contains('1处断点'));
        expect(label, contains('非收益率'));
      }
    } finally {
      handle.dispose();
    }
  });
  testWidgets('quality explanation is accessible and uses real evidence',
      (tester) async {
    await _pump(
        tester,
        [
          snapshot(day.subtract(const Duration(days: 1)), missingValuations: 1),
          snapshot(day, cash: 11000, missingValuations: 1)
        ],
        partial: true);
    await tester.tap(find.byTooltip('估算与数据说明'));
    await tester.pumpAndSettle();
    expect(find.textContaining('估值待确认'), findsWidgets);
    expect(find.textContaining('2 项未计入'), findsWidgets);
    expect(find.textContaining('不能把补齐估值当作增长'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final theme in ['warm', 'night']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('quality sheet opens and closes $theme scale $scale',
          (tester) async {
        await _pump(
            tester,
            [
              snapshot(day.subtract(const Duration(days: 1)),
                  missingValuations: 1),
              snapshot(day, missingValuations: 1),
            ],
            theme: theme,
            scale: scale,
            size: const Size(320, 900),
            partial: true);
        await tester.tap(find.byTooltip('估算与数据说明'));
        await tester.pumpAndSettle();
        expect(find.text('估算与数据说明'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final sheet = find.byType(SheetHeader);
        await tester.tap(find
            .descendant(of: sheet, matching: find.byType(AppCircleButton))
            .first);
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(find.byTooltip('估算与数据说明'), findsOneWidget);
      });
    }
  }
  for (final theme in ['warm', 'white', 'night']) {
    for (final partial in [false, true]) {
      testWidgets('asset reliability capture $theme partial=$partial',
          (tester) async {
        await _pump(
            tester,
            [
              snapshot(day.subtract(const Duration(days: 80)),
                  cash: 4882000, physical: 784000, liabilities: 600000),
              snapshot(day.subtract(const Duration(days: 40)),
                  cash: 5000000,
                  physical: 750000,
                  liabilities: 550000,
                  missingValuations: partial ? 1 : 0),
              snapshot(day,
                  cash: 5200000, physical: 700000, liabilities: 500000),
            ],
            theme: theme,
            partial: partial);
        await _capture(tester, '$theme-${partial ? 'partial' : 'complete'}');
        if (partial &&
            Platform.environment['ASSET_CAPTURE_EXPLANATIONS'] == '1') {
          await tester.tap(find.byTooltip('估算与数据说明'));
          await tester.pumpAndSettle();
          await _capture(tester, '$theme-explanation');
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
  testWidgets('asset reliability capture short-history', (tester) async {
    await _pump(tester, [
      snapshot(day.subtract(const Duration(days: 1))),
      snapshot(day, cash: 11000)
    ]);
    await _capture(tester, 'short-history');
  });
  testWidgets('asset reliability capture negative-floor', (tester) async {
    MoneyFormat.configure(
        decimalPlaces: 0, integerRoundingMode: MoneyIntegerRoundingMode.floor);
    await _pump(tester, [
      snapshot(day.subtract(const Duration(days: 1))),
      snapshot(day, cash: 9880)
    ]);
    await _capture(tester, 'negative-floor');
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['ASSET_RELIABILITY_CAPTURE_DIR'];
  if (output == null) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  final bounds = <String, List<double>>{};
  for (final key in [
    'asset-net-worth-card',
    'asset-trend-range',
    'asset-metric-funds',
    'asset-metric-liabilities'
  ]) {
    final rect = tester.getRect(find.byKey(ValueKey(key)));
    bounds[key] = [rect.left, rect.top, rect.right, rect.bottom];
  }
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      await File('$output/$name.json').writeAsString(jsonEncode(bounds));
    } finally {
      image.dispose();
    }
  });
}
