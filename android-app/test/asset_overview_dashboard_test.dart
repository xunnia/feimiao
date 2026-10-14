import 'dart:io';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/account/net_worth_snapshot.dart';
import 'package:qingji/core/account/net_worth_verified_checkpoint.dart';
import 'package:qingji/core/app_clock.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/assets/asset_overview_dashboard.dart';
import 'package:qingji/views/assets/asset_overview_style.dart';

import 'asset_overview_projection_test.dart' show snapshot;
import 'screenshot_font_support.dart';

void main() {
  setUp(MoneyFormat.resetConfig);
  setUpAll(() async {
    await loadScreenshotFonts(force: true);
    for (final entry in {
      'AssetLabels': 'assets/fonts/AssetLabels-VF.ttf',
      'AssetAmount': 'assets/fonts/Nunito-ExtraBold.ttf'
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });
  for (final size in [const Size(394, 852), const Size(320, 760)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('overview layout ${size.width} scale $scale', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final now = AppClock.now;
        final earlier = DateTime(now.year, now.month, now.day - 80);
        final components = [snapshot(earlier), snapshot(now, cash: 12345)];
        const captureKey = ValueKey('dashboard-capture');
        await tester.pumpWidget(RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light().copyWith(
                  textTheme: AppTheme.light().textTheme.apply(
                      fontFamilyFallback: const [screenshotCjkFontFamily])),
              builder: (_, child) => MediaQuery(
                  data: MediaQueryData(
                      size: size, textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: AssetOverviewDashboard(
                        breakdown: NetWorthBreakdown(
                            netWorth: Decimal.parse('153.45'),
                            totalAssets: Decimal.parse('173.45'),
                            cashAssets: Decimal.parse('123.45'),
                            physicalAssets: Decimal.fromInt(50),
                            totalLiabilities: Decimal.fromInt(20),
                            investmentAssets: Decimal.zero,
                            receivableAssets: Decimal.zero),
                        trend: resolveNetWorthTrend(components),
                        partial: false,
                        excludedCount: 0,
                      ))),
            )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final heroTitle = find.byKey(const ValueKey('asset-net-worth-title'));
        final metric = find.byKey(const ValueKey('asset-metric-funds'));
        final title = find.descendant(of: metric, matching: find.text('可动用资金'));
        final left = tester.getTopLeft(heroTitle).dx;
        expect(tester.getTopLeft(title).dx, left);
        final heroStyle = tester.widget<Text>(heroTitle).style!;
        final metricStyle = tester.widget<Text>(title).style!;
        expect(heroStyle.fontSize, 13);
        expect(metricStyle.fontSize, 12);
        expect(heroStyle.color, metricStyle.color);
        expect(heroStyle.fontFamily, metricStyle.fontFamily);
        expect(heroStyle.fontWeight, metricStyle.fontWeight);
        final chartBounds =
            tester.getRect(find.byType(AssetOverviewChart).first);
        for (final date in [earlier, now]) {
          final labelBounds =
              tester.getRect(find.text('${date.month}/${date.day}'));
          expect(labelBounds.bottom, lessThanOrEqualTo(chartBounds.bottom));
          expect(labelBounds.left, greaterThanOrEqualTo(chartBounds.left));
          expect(labelBounds.right, lessThanOrEqualTo(chartBounds.right));
        }
        final dateLabels = find.byWidgetPredicate((widget) =>
            widget is Text &&
            RegExp(r'^\d{1,2}/\d{1,2}$').hasMatch(widget.data ?? ''));
        final dateRects = dateLabels
            .evaluate()
            .map((element) => tester.getRect(find.byWidget(element.widget)))
            .toList()
          ..sort((first, last) => first.left.compareTo(last.left));
        for (var i = 1; i < dateRects.length; i++) {
          expect(dateRects[i].left,
              greaterThanOrEqualTo(dateRects[i - 1].right + 4));
        }
        final card =
            tester.getRect(find.byKey(const ValueKey('asset-net-worth-card')));
        final metrics = [
          for (final name in ['funds', 'physical', 'liabilities'])
            tester.getRect(find.byKey(ValueKey('asset-metric-$name'))),
        ];
        for (final bounds in metrics) {
          expect(bounds.left, greaterThanOrEqualTo(card.left + 16));
          expect(bounds.right, lessThanOrEqualTo(card.right - 16));
          expect(bounds.bottom, lessThanOrEqualTo(card.bottom - 16));
        }
        expect(find.byKey(const ValueKey('asset-metric-total')), findsNothing);
        expect(find.text('123.45'), findsOneWidget);
        expect(find.text('153.45'), findsOneWidget);
        expect(find.text('23.5%'), findsNothing);
        if (scale == 1 && size.width >= 394) {
          expect(metrics[0].top, metrics[1].top);
          expect(metrics[1].top, metrics[2].top);
          expect(metrics[1].left, closeTo(metrics[0].right, 0.000001));
          expect(metrics[2].left, closeTo(metrics[1].right, 0.000001));
        } else {
          for (final bounds in metrics) {
            expect(bounds.width, card.width - 33);
          }
          expect(metrics[1].top, greaterThanOrEqualTo(metrics[0].bottom));
          expect(metrics[2].top, greaterThanOrEqualTo(metrics[1].bottom));
        }
        if (Platform.environment['UPDATE_ASSET_SCREENSHOTS'] == '1') {
          final boundary = tester
              .renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            try {
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final output =
                  Platform.environment['ASSET_SCREENSHOT_OUTPUT_DIR'] ??
                      'outputs/ui_comparisons/2026-10-03-asset-overview';
              final suffix =
                  Platform.environment['ASSET_SHOT_SUFFIX'] ?? 'after';
              final file = File(
                  '$output/dashboard-${size.width.toInt()}-${scale.toInt()}-$suffix.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester
            .ensureVisible(find.byKey(const ValueKey('asset-trend-range')));
        await tester.tap(find.byKey(const ValueKey('asset-trend-range')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('近3个月').last);
        await tester.pumpAndSettle();
        expect(find.text('近3个月'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('cash strip excludes investments and receivables',
      (tester) async {
    await _pumpDashboard(tester,
        breakdown: _breakdown(
            cash: 42000,
            investment: 96000,
            receivable: 52000,
            physical: 78400,
            liabilities: 51600));
    final cash = find.byKey(const ValueKey('asset-metric-funds'));
    expect(find.descendant(of: cash, matching: find.text('42,000.00')),
        findsOneWidget);
    expect(find.text('另有投资 96,000.00'), findsOneWidget);
    expect(find.text('216,800.00'), findsOneWidget);
    expect(find.text('还没有完整核对'), findsOneWidget);
    expect(find.textContaining('区间变化'), findsNothing);
  });

  testWidgets('trend growth never masquerades as a verified change',
      (tester) async {
    final now = AppClock.now;
    await _pumpDashboard(tester,
        trend: resolveNetWorthTrend([
          snapshot(now.subtract(const Duration(days: 1)), cash: 10000),
          snapshot(now, cash: 20000),
        ]));
    expect(find.text('还没有完整核对'), findsOneWidget);
    expect(find.textContaining('↑', findRichText: true), findsNothing);
    expect(find.textContaining('两次完整核对', findRichText: true), findsNothing);
  });

  testWidgets(
      'frozen complete checkpoints supply the comparison, not current amount',
      (tester) async {
    final before = _checkpoint(1, 10000);
    final after = _checkpoint(2, 11200);
    await _pumpDashboard(tester,
        breakdown: _breakdown(cash: 999),
        lastVerifiedAt: after.header.asOf,
        verifiedComparison: compareNetWorthVerifiedCheckpoints(before, after));
    expect(find.textContaining('↑ 12', findRichText: true), findsOneWidget);
    expect(find.textContaining('两次完整核对', findRichText: true), findsOneWidget);
    expect(find.text('999.00'), findsNWidgets(2));
  });

  testWidgets(
      'incomparable checkpoints retain the last review without false delta',
      (tester) async {
    final before = _checkpoint(1, 10000);
    final after = _checkpoint(2, 11200, scope: 2);
    await _pumpDashboard(tester,
        lastVerifiedAt: after.header.asOf,
        verifiedComparison: compareNetWorthVerifiedCheckpoints(before, after));
    expect(find.textContaining('上次完整核对', findRichText: true), findsOneWidget);
    expect(find.textContaining('↑', findRichText: true), findsNothing);
    expect(find.textContaining('两次完整核对', findRichText: true), findsNothing);
  });

  testWidgets('unvalued included items show unknown, not a fabricated zero',
      (tester) async {
    await _pumpDashboard(tester, physicalPartial: true, physicalCount: 1);
    final physical = find.byKey(const ValueKey('asset-metric-physical'));
    expect(find.descendant(of: physical, matching: find.text('—')),
        findsOneWidget);
    expect(find.descendant(of: physical, matching: find.text('0.00')),
        findsNothing);
    expect(find.text('估值待确认'), findsOneWidget);
  });

  for (final excluded in [0, 2]) {
    testWidgets('no included item keeps its real zero with $excluded excluded',
        (tester) async {
      await _pumpDashboard(tester, excludedPhysicalCount: excluded);
      final physical = find.byKey(const ValueKey('asset-metric-physical'));
      expect(find.descendant(of: physical, matching: find.text('0.00')),
          findsOneWidget);
      expect(find.descendant(of: physical, matching: find.text('—')),
          findsNothing);
      expect(find.text(excluded == 0 ? '0 件' : '2 件 · 未计入'), findsOneWidget);
    });
  }

  testWidgets('review link invokes the existing review flow', (tester) async {
    var reviews = 0;
    await _pumpDashboard(tester, onReview: () => reviews++);
    await tester.tap(find.text('去核对 ›'));
    expect(reviews, 1);
    expect(tester.takeException(), isNull);
  });
}

NetWorthBreakdown _breakdown(
        {int cash = 0,
        int investment = 0,
        int receivable = 0,
        int physical = 0,
        int liabilities = 0}) =>
    NetWorthBreakdown(
      netWorth: Decimal.fromInt(
          cash + investment + receivable + physical - liabilities),
      totalAssets: Decimal.fromInt(cash + investment + receivable + physical),
      cashAssets: Decimal.fromInt(cash),
      physicalAssets: Decimal.fromInt(physical),
      totalLiabilities: Decimal.fromInt(liabilities),
      investmentAssets: Decimal.fromInt(investment),
      receivableAssets: Decimal.fromInt(receivable),
    );

NetWorthVerifiedCheckpoint _checkpoint(int day, int minor, {int scope = 1}) {
  final date = DateTime.utc(2026, 8, day, 10);
  return NetWorthVerifiedCheckpoint(
    header: NetWorthVerifiedCheckpointHeader(
      uuid: 'overview-$day',
      asOf: date,
      knowledgeCutoff: date,
      scopeVersion: scope,
      calculationVersion: 1,
      currencyCoverage: NetWorthCurrencyCoverage.single('CNY'),
      totals: NetWorthVerifiedCheckpointTotals(
          totalAssetsMinor: minor,
          totalLiabilitiesMinor: 0,
          netWorthMinor: minor),
      completeness: NetWorthVerifiedCheckpointCompleteness.complete,
      status: NetWorthVerifiedCheckpointStatus.active,
      createdAt: date,
    ),
    items: [
      NetWorthVerifiedCheckpointItem(
          objectType: 'account',
          objectUuid: 'cash',
          confirmedAmountMinor: minor,
          currencyCode: 'CNY',
          valueEffectiveAt: date,
          valueSource: 'user_confirmation',
          quality: 'confirmed')
    ],
  );
}

Future<void> _pumpDashboard(WidgetTester tester,
    {NetWorthBreakdown? breakdown,
    NetWorthTrendResult? trend,
    bool physicalPartial = false,
    int physicalCount = 0,
    int excludedPhysicalCount = 0,
    DateTime? lastVerifiedAt,
    NetWorthVerifiedCheckpointComparison? verifiedComparison,
    VoidCallback? onReview}) async {
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
          body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AssetOverviewDashboard(
                  breakdown: breakdown ?? _breakdown(),
                  trend: trend ?? resolveNetWorthTrend([]),
                  partial: physicalPartial,
                  excludedCount: excludedPhysicalCount,
                  physicalPartial: physicalPartial,
                  cashAccountCount: 2,
                  physicalCount: physicalCount,
                  excludedPhysicalCount: excludedPhysicalCount,
                  liabilityCount: 1,
                  lastVerifiedAt: lastVerifiedAt,
                  verifiedComparison: verifiedComparison,
                  onReview: onReview)))));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(
      tester.widgetList<AssetOverviewAmount>(find.byType(AssetOverviewAmount)),
      isNotEmpty);
}
