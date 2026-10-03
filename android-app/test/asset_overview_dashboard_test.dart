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
import 'package:qingji/views/assets/asset_overview_dashboard.dart';

import 'asset_overview_projection_test.dart' show snapshot;
import 'screenshot_font_support.dart';

void main() {
  setUpAll(() async {
    await loadScreenshotFonts();
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
        final title = find.descendant(of: metric, matching: find.text('资金资产'));
        final left = tester.getTopLeft(heroTitle).dx;
        expect(tester.getTopLeft(title).dx, left);
        expect(tester.widget<Text>(heroTitle).style,
            tester.widget<Text>(title).style);
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
        final cardSize = tester.getSize(metric);
        if (scale == 1) {
          expect(cardSize.height, closeTo(106, size.width == 394 ? 1 : 8));
          expect(find.text('23.5%'), findsOneWidget);
        } else {
          expect(cardSize.width, size.width - 32);
        }
        if (Platform.environment['UPDATE_ASSET_SCREENSHOTS'] == '1') {
          final boundary = tester
              .renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            try {
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File(
                  'outputs/ui_comparisons/2026-10-03-asset-overview/dashboard-${size.width.toInt()}-${scale.toInt()}.png');
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
}
