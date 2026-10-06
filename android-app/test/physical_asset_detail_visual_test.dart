import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/app_clock.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/assets/physical_asset_detail_page.dart';

import 'screenshot_font_support.dart';

class _DetailRepo extends AppRepository {
  final PhysicalAssetEntity asset;
  final bool exactCost;

  _DetailRepo(this.asset, {this.exactCost = true});

  @override
  PhysicalAssetEntity? physicalAssetDetailById(int id) => asset;

  @override
  PhysicalAssetAcquisitionCostResult physicalAssetAcquisitionCost(
          int assetId) =>
      PhysicalAssetAcquisitionCostResult(
        quality: exactCost
            ? PhysicalAssetAcquisitionCostQuality.exact
            : PhysicalAssetAcquisitionCostQuality.partial,
        amount: asset.purchasePrice,
        reason: exactCost ? '' : '退款分配待确认',
      );

  @override
  List<AssetValuationEntity> valuationsForAsset(int assetId) => [
        AssetValuationEntity(
          id: 1,
          assetId: assetId,
          value: asset.currentValue,
          valuedAtMs: AppClock.now.millisecondsSinceEpoch,
        ),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadScreenshotFonts(force: true);
    await (FontLoader('AssetAmount')
          ..addFont(rootBundle.load('assets/fonts/Nunito-ExtraBold.ttf')))
        .load();
  });
  final capture =
      Platform.environment['UPDATE_PHYSICAL_DETAIL_SCREENSHOTS'] == '1';
  final suffix = Platform.environment['PHYSICAL_DETAIL_SHOT_SUFFIX'] ?? 'after';
  final outDir = Platform.environment['PHYSICAL_DETAIL_SHOT_OUTPUT'] ??
      '../outputs/ui_comparisons/2026-10-06-concept';

  PhysicalAssetEntity asset({bool photo = false, bool missingDate = false}) {
    final now = AppClock.now;
    return PhysicalAssetEntity(
      id: 1,
      name: 'iPhone Air',
      assetType: AssetType.digital,
      purchasePrice: Decimal.fromInt(6999),
      currentValue: Decimal.fromInt(5800),
      depreciationBase: Decimal.zero,
      salvageValue: Decimal.zero,
      purchaseDateMs: missingDate
          ? null
          : DateTime(now.year, now.month, now.day - 92).millisecondsSinceEpoch,
      warrantyUntilMs:
          DateTime(now.year + 1, now.month, now.day).millisecondsSinceEpoch,
      brand: 'Apple',
      model: 'iPhone Air',
      location: '随身',
      note: 'P0 fixture asset',
      photoPath: photo ? File('assets/mascot/idle.webp').absolute.path : '',
    );
  }

  Future<void> pump(
    WidgetTester tester,
    PhysicalAssetEntity item, {
    Brightness brightness = Brightness.light,
    Size size = const Size(390, 844),
    double textScale = 1,
    bool exactCost = true,
  }) async {
    final repo = _DetailRepo(item, exactCost: exactCost);
    addTearDown(repo.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme =
        brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('physical-detail-capture'),
      child: ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(
              fontFamily: 'Nunito',
              fontFamilyFallback: const [screenshotCjkFontFamily],
            ),
            appBarTheme: theme.appBarTheme.copyWith(
              titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
                fontFamilyFallback: const [screenshotCjkFontFamily],
              ),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: DecoratedBox(
              decoration: AppColors.pageBackground(brightness),
              child: child,
            ),
          ),
          home: PhysicalAssetDetailPage(assetId: item.id, fallbackAsset: item),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (capture) {
      await expectLater(find.byKey(const ValueKey('physical-detail-capture')),
          matchesGoldenFile('$outDir/${name}_$suffix.png'));
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('detail ${brightness.name} keeps actual metrics',
        (tester) async {
      await pump(tester, asset(), brightness: brightness);
      expect(find.byKey(const Key('physical-asset-primary-metric')),
          findsOneWidget);
      if (suffix == 'after') {
        expect(
            find.text('已持有 93 天 · '
                '${AppClock.now.year}年${asset().purchaseDate!.month}月'
                '${asset().purchaseDate!.day}日购入'),
            findsOneWidget);
        expect(
            tester.getSize(
                find.byKey(const Key('physical-asset-photo-placeholder'))),
            const Size(68, 68));
      }
      expect(tester.takeException(), isNull);
      await shot(tester, 'physical_detail_${brightness.name}');
      if (brightness == Brightness.light && suffix == 'after') {
        await tester
            .tap(find.byKey(const Key('physical-asset-photo-placeholder')));
        await tester.pumpAndSettle();
        expect(find.text('资产凭证'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('detail narrow large text keeps actions and unavailable state',
      (tester) async {
    await pump(tester, asset(missingDate: true),
        size: const Size(320, 844), textScale: 2, exactCost: false);
    expect(tester.takeException(), isNull);
    await shot(tester, 'physical_detail_narrow_large_text');
    await tester.scrollUntilVisible(
        find.byKey(const Key('physical-asset-fix-purchase-date')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('physical-asset-fix-purchase-date')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real photo retains large preview and opens evidence',
      (tester) async {
    await pump(tester, asset(photo: true));
    final image = find.byType(Image).first;
    expect(tester.getSize(image).width, greaterThan(200));
    expect(tester.takeException(), isNull);
    await shot(tester, 'physical_detail_photo');
    if (suffix == 'after') {
      await tester.tap(image);
      await tester.pumpAndSettle();
      expect(find.text('资产凭证'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
