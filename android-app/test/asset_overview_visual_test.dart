import 'dart:io';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/settings/accounts_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshot_font_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadScreenshotFonts();
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
      if (Platform.environment['UPDATE_ASSET_SCREENSHOTS'] == '1') {
        final suffix = Platform.environment['ASSET_SHOT_SUFFIX'] ?? 'after';
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
                'outputs/ui_comparisons/2026-10-03-asset-overview/page-${preset.key}-$suffix.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
