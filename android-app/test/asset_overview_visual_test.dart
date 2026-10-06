import 'dart:io';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/account/net_worth_snapshot.dart';
import 'package:qingji/core/app_clock.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/assets/asset_overview_dashboard.dart';
import 'package:qingji/views/settings/accounts_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshot_font_support.dart';
import 'asset_overview_projection_test.dart' show snapshot;

Future<void> _capture(WidgetTester tester, Key captureKey, String name) async {
  if (Platform.environment['UPDATE_ASSET_SCREENSHOTS'] != '1') return;
  final suffix = Platform.environment['ASSET_SHOT_SUFFIX'] ?? 'after';
  final output = Platform.environment['ASSET_SCREENSHOT_OUTPUT_DIR'] ??
      'outputs/ui_comparisons/2026-10-03-asset-overview';
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/$name-$suffix.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
  for (final preset in [kThemePresets.first, kThemePresets.last]) {
    testWidgets('asset overview page ${preset.key}', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('fm_asset_overview_');
      await databaseFactory.setDatabasesPath(tmp.path);
      final repo = AppRepository();
      addTearDown(() async {
        await tester.runAsync(repo.closeForTest);
        tmp.deleteSync(recursive: true);
      });
      await tester.runAsync(() async {
        await repo.init();
        await repo.addReceivableAsset(
          name: '租房押金',
          type: ReceivableAssetType.securityDeposit,
          originalAmount: Decimal.fromInt(12000),
        );
        await repo.addPhysicalAsset(
          name: '相机',
          assetType: AssetType.digital,
          currentValue: Decimal.fromInt(7840),
          purchasePrice: Decimal.fromInt(10000),
          purchaseDate: DateTime(2026, 7, 1),
        );
        await repo.setLastAssetViewTabIndex(0);
      });
      await tester.binding.setSurfaceSize(const Size(420, 912));
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
      final base = preset.forceDark ? AppTheme.dark() : AppTheme.light();
      const captureKey = ValueKey('asset-overview-capture');
      await tester.pumpWidget(RepaintBoundary(
        key: captureKey,
        child: ChangeNotifierProvider.value(
          value: repo,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: base.copyWith(
              textTheme: base.textTheme.apply(
                fontFamilyFallback: const [screenshotCjkFontFamily],
              ),
              appBarTheme: base.appBarTheme.copyWith(
                titleTextStyle: base.appBarTheme.titleTextStyle!.copyWith(
                  fontFamilyFallback: const [screenshotCjkFontFamily],
                ),
              ),
            ),
            builder: (_, child) => DecoratedBox(
              decoration: AppColors.pageBackground(base.brightness),
              child: child,
            ),
            home: const AccountsView(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('asset-overview')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, captureKey, 'page-${preset.key}');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final scenario in ['empty', 'unknown', 'narrow-large', 'history']) {
      testWidgets('overview boundary ${preset.key} $scenario', (tester) async {
        final large = scenario == 'narrow-large';
        final unknown = scenario == 'unknown';
        final history = scenario == 'history';
        final size = Size(large ? 320 : 420, 912);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        AppColors.applyTheme(
            bgTop: preset.top,
            bgBottom: preset.bottom,
            bgSolid: preset.solid,
            cardAlphaL: 0.8,
            cardAlphaD: 0.8,
            bgDark: preset.bottom,
            bgDarkTop: preset.top);
        final base = preset.forceDark ? AppTheme.dark() : AppTheme.light();
        const captureKey = ValueKey('overview-boundary-capture');
        final now = AppClock.now;
        await tester.pumpWidget(RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: base.copyWith(
                  textTheme: base.textTheme.apply(
                      fontFamilyFallback: const [screenshotCjkFontFamily])),
              builder: (_, child) => MediaQuery(
                  data: MediaQueryData(
                      size: size, textScaler: TextScaler.linear(large ? 2 : 1)),
                  child: DecoratedBox(
                      decoration: AppColors.pageBackground(base.brightness),
                      child: child)),
              home: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: AssetOverviewDashboard(
                        breakdown: NetWorthBreakdown(
                            netWorth: Decimal.parse(history
                                ? '54000'
                                : large
                                    ? '153.45'
                                    : unknown
                                        ? '400'
                                        : '0'),
                            totalAssets: Decimal.parse(history
                                ? '59000'
                                : large
                                    ? '173.45'
                                    : unknown
                                        ? '420'
                                        : '0'),
                            cashAssets: Decimal.parse(history
                                ? '52000'
                                : large
                                    ? '123.45'
                                    : unknown
                                        ? '420'
                                        : '0'),
                            physicalAssets: Decimal.fromInt(history
                                ? 7000
                                : large
                                    ? 50
                                    : 0),
                            totalLiabilities: Decimal.fromInt(history
                                ? 5000
                                : large || unknown
                                    ? 20
                                    : 0),
                            investmentAssets: Decimal.zero,
                            receivableAssets: Decimal.zero),
                        trend: resolveNetWorthTrend(history
                            ? [
                                snapshot(now.subtract(const Duration(days: 80)),
                                    cash: 4882000,
                                    physical: 784000,
                                    liabilities: 600000),
                                snapshot(now.subtract(const Duration(days: 40)),
                                    cash: 5000000,
                                    physical: 750000,
                                    liabilities: 550000),
                                snapshot(now,
                                    cash: 5200000,
                                    physical: 700000,
                                    liabilities: 500000),
                              ]
                            : large
                                ? [
                                    snapshot(
                                        now.subtract(const Duration(days: 80))),
                                    snapshot(now, cash: 12345),
                                  ]
                                : []),
                        partial: unknown,
                        excludedCount: 0,
                        physicalPartial: unknown,
                        physicalCount: unknown || large || history ? 1 : 0,
                        cashAccountCount: unknown || large || history ? 2 : 0,
                        liabilityCount: unknown || large || history ? 1 : 0,
                      ))),
            )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('asset-metric-total')), findsNothing);
        if (!large && !history) {
          expect(find.byType(AssetOverviewChart), findsNothing);
          expect(find.text('至少积累 2 个可比快照后显示趋势'), findsOneWidget);
        }
        if (history) {
          final chart = tester
              .widget<AssetOverviewChart>(find.byType(AssetOverviewChart));
          expect(chart.compact, isTrue);
          final chartData =
              tester.widget<LineChart>(find.byType(LineChart)).data;
          expect(chartData.clipData.right, isFalse);
          expect(chartData.clipData.left, isFalse);
          expect(chartData.clipData.top, isFalse);
          expect(chartData.clipData.bottom, isFalse);
          expect(chart.projection.trend.hasTrend, isTrue);
          expect(chart.projection.trend.points, hasLength(3));
          expect(chart.projection.trend.points.last.components.netWorthMinor,
              5400000);
          expect(find.text('54,000.00'), findsOneWidget);
          expect(find.textContaining('↑', findRichText: true), findsNothing);
        }
        expect(find.text('—'), unknown ? findsOneWidget : findsNothing);
        if (large) {
          final fund =
              tester.getRect(find.byKey(const ValueKey('asset-metric-funds')));
          final physical = tester
              .getRect(find.byKey(const ValueKey('asset-metric-physical')));
          expect(physical.top, greaterThanOrEqualTo(fund.bottom));
        }
        await _capture(tester, captureKey, 'overview-${preset.key}-$scenario');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
