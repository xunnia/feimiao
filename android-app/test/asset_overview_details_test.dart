import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/account/net_worth_snapshot.dart';
import 'package:qingji/core/account/net_worth_verified_checkpoint.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/assets/asset_overview_cards.dart';
import 'package:qingji/views/settings/accounts_view.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/settings_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshot_font_support.dart';

const _captureKey = ValueKey('asset-details-capture');

NetWorthVerifiedCheckpoint checkpoint({
  int month = 9,
  int day = 30,
  int assets = 7284000,
  int liabilities = 500000,
  bool partial = false,
  int scope = 1,
  NetWorthVerifiedCheckpointStatus status =
      NetWorthVerifiedCheckpointStatus.active,
}) {
  final date = DateTime(2026, month, day, 12);
  return NetWorthVerifiedCheckpoint(
      header: NetWorthVerifiedCheckpointHeader(
          uuid: 'checkpoint-$month-$day-$assets',
          asOf: date,
          knowledgeCutoff: date,
          scopeVersion: scope,
          calculationVersion: 1,
          currencyCoverage: NetWorthCurrencyCoverage.single('CNY'),
          totals: NetWorthVerifiedCheckpointTotals(
              totalAssetsMinor: assets,
              totalLiabilitiesMinor: liabilities,
              netWorthMinor: assets - liabilities),
          completeness: partial
              ? NetWorthVerifiedCheckpointCompleteness.partial
              : NetWorthVerifiedCheckpointCompleteness.complete,
          incompletenessReasons: partial
              ? [
                  NetWorthVerifiedCheckpointReason(
                      code: 'unconfirmed_value',
                      message: '有物品估值待确认，未确认金额不计入本次核对。'),
                  NetWorthVerifiedCheckpointReason(
                      code: 'missing_currency', message: '存在未换算的外币账户。')
                ]
              : [],
          status: status,
          createdAt: date),
      items: []);
}

NetWorthBreakdown breakdown(
    {bool single = false,
    bool zero = false,
    Decimal? cashOverride,
    Decimal? totalOverride}) {
  final cash = cashOverride ?? Decimal.fromInt(zero ? 0 : 42000);
  final investment = Decimal.fromInt(zero || single ? 0 : 10000);
  final receivable = Decimal.fromInt(zero || single ? 0 : 12000);
  final physical = Decimal.fromInt(zero || single ? 0 : 7840);
  final liabilities = Decimal.fromInt(5000);
  final total = totalOverride ?? cash + investment + receivable + physical;
  return NetWorthBreakdown(
      netWorth: total - liabilities,
      totalAssets: total,
      totalLiabilities: liabilities,
      cashAssets: cash,
      investmentAssets: investment,
      receivableAssets: receivable,
      physicalAssets: physical);
}

Future<void> pumpDetails(WidgetTester tester,
    {String theme = 'warm',
    String scene = 'complete',
    Size size = const Size(420, 912),
    double scale = 1,
    Widget? child}) async {
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
  final earlier = checkpoint(month: 8, day: 31, assets: 6900000);
  final latest = checkpoint(partial: scene == 'partial');
  await tester.pumpWidget(RepaintBoundary(
    key: _captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
          textTheme: base.textTheme.apply(fontFamilyFallback: const [
            screenshotCjkFontFamily,
            'NotoColorEmoji'
          ]),
          appBarTheme: base.appBarTheme.copyWith(
              titleTextStyle: base.appBarTheme.titleTextStyle!.copyWith(
                  fontFamilyFallback: const [screenshotCjkFontFamily]))),
      builder: (_, child) => MediaQuery(
          data:
              MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
          child: DecoratedBox(
              decoration: AppColors.pageBackground(base.brightness),
              child: child)),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: child ??
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    VerifiedNetWorthCard(
                        checkpoints: [earlier, latest],
                        comparison: compareNetWorthVerifiedCheckpoints(
                            earlier, latest)),
                    const SizedBox(height: 20),
                    AssetAnalysisCard(
                        partial: scene == 'partial',
                        breakdown: breakdown(
                            single: scene == 'single', zero: scene == 'zero')),
                  ]),
            ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> captureDetails(WidgetTester tester, String name) async {
  final output = Platform.environment['ASSET_DETAILS_CAPTURE_DIR'];
  if (output == null) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  final bounds = <String, List<double>>{};
  for (final type in [VerifiedNetWorthCard, AssetAnalysisCard]) {
    final finder = find.byType(type);
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder.first);
    bounds[type.toString()] = [rect.left, rect.top, rect.right, rect.bottom];
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

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadScreenshotFonts(force: true);
    final emoji = File(Platform.environment['FEIMIAO_EMOJI_FONT'] ??
        r'C:\src\xunni-codex\.tmp\flutter-audit-sdk\flutter\engine\src\flutter\txt\third_party\fonts\NotoColorEmoji.ttf');
    if (emoji.existsSync()) {
      await (FontLoader('NotoColorEmoji')
            ..addFont(
                Future.value(ByteData.sublistView(await emoji.readAsBytes()))))
          .load();
    } else if (Platform.environment['ASSET_DETAILS_CAPTURE_DIR'] != null) {
      throw StateError('改前截图的核对徽章需要真实 emoji 字体，不能用方框替代。');
    }
    for (final entry in {
      'AssetLabels': 'assets/fonts/AssetLabels-VF.ttf',
      'AssetAmount': 'assets/fonts/Nunito-ExtraBold.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });
  tearDown(MoneyFormat.resetConfig);
  for (final theme in ['warm', 'white', 'night']) {
    for (final scene in ['complete', 'partial', 'single', 'zero']) {
      testWidgets('details capture $theme $scene', (tester) async {
        await pumpDetails(tester, theme: theme, scene: scene);
        await captureDetails(tester, '$theme-$scene');
      });
    }
  }
  for (final theme in ['warm', 'night']) {
    testWidgets('details page capture $theme', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('fm_asset_details_');
      await databaseFactory.setDatabasesPath(tmp.path);
      var repo = AppRepository();
      addTearDown(() async {
        await tester.runAsync(repo.closeForTest);
        tmp.deleteSync(recursive: true);
      });
      await tester.runAsync(() async {
        await repo.init();
        await repo.addReceivableAsset(
            name: '租房押金',
            type: ReceivableAssetType.securityDeposit,
            originalAmount: Decimal.fromInt(12000));
        await repo.addPhysicalAsset(
            name: '相机',
            assetType: AssetType.digital,
            currentValue: Decimal.fromInt(7840),
            purchasePrice: Decimal.fromInt(10000),
            purchaseDate: DateTime(2026, 7, 1));
        final saved = await repo.createVerifiedNetWorthCheckpoint();
        final fixed = DateTime(2026, 10, 3, 12).millisecondsSinceEpoch;
        await repo.debugDb.update(
            'net_worth_verified_checkpoints',
            {
              'as_of_ms': fixed,
              'knowledge_cutoff_ms': fixed,
              'created_ms': fixed
            },
            where: 'id = ?',
            whereArgs: [saved.header.id]);
        await repo.setLastAssetViewTabIndex(0);
        await repo.closeForTest();
        repo.dispose();
        repo = AppRepository();
        await repo.init();
        expect(repo.verifiedNetWorthCheckpoints.single.header.asOf.toLocal(),
            DateTime(2026, 10, 3, 12));
      });
      await pumpDetails(tester,
          theme: theme,
          child: ChangeNotifierProvider.value(
              value: repo, child: const AccountsView()));
      await captureDetails(tester, '$theme-page-top');
      await tester.drag(
          find.byKey(const Key('asset-overview')), const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(find.byType(AssetAnalysisCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureDetails(tester, '$theme-page-bottom');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('details behavior empty and revoked records are hidden',
      (tester) async {
    for (final records in <List<NetWorthVerifiedCheckpoint>>[
      [],
      [checkpoint(status: NetWorthVerifiedCheckpointStatus.revoked)],
      [checkpoint(status: NetWorthVerifiedCheckpointStatus.superseded)],
    ]) {
      await pumpDetails(tester,
          child: VerifiedNetWorthCard(checkpoints: records, comparison: null));
      expect(find.text('上次核对'), findsNothing);
    }
  });
  testWidgets('details behavior repeated month does not interrupt month streak',
      (tester) async {
    await pumpDetails(tester,
        child: VerifiedNetWorthCard(checkpoints: [
          checkpoint(),
          checkpoint(day: 15),
          checkpoint(month: 8, day: 31),
          checkpoint(month: 7, day: 31)
        ], comparison: null));
    expect(find.text('连续 3 月核对'), findsOneWidget);
  });
  testWidgets(
      'details behavior unrelated null IDs cannot display an old change',
      (tester) async {
    final earlier = checkpoint(month: 8, day: 31);
    final later = checkpoint(day: 15);
    final latest = checkpoint();
    await pumpDetails(tester,
        child: VerifiedNetWorthCard(
            checkpoints: [latest],
            comparison: compareNetWorthVerifiedCheckpoints(earlier, later)));
    expect(find.textContaining('较上次完整核对'), findsNothing);
  });
  testWidgets('details behavior scope mismatch is not a growth claim',
      (tester) async {
    final earlier = checkpoint(month: 8, day: 31);
    final latest = checkpoint(scope: 2);
    await pumpDetails(tester,
        child: VerifiedNetWorthCard(
            checkpoints: [earlier, latest],
            comparison: compareNetWorthVerifiedCheckpoints(earlier, latest)));
    expect(find.text('两次核对口径不同，暂不比较变化'), findsOneWidget);
    await tester.tap(find.byTooltip('查看上次核对详情'));
    await tester.pumpAndSettle();
    expect(find.text('两次核对的资产计入范围不同，暂不比较变化。'), findsOneWidget);
    expect(find.textContaining('scope changed'), findsNothing);
  });
  for (final rounding in MoneyIntegerRoundingMode.values) {
    testWidgets(
        'details behavior negative change uses signed $rounding rounding',
        (tester) async {
      MoneyFormat.configure(decimalPlaces: 0, integerRoundingMode: rounding);
      final earlier =
          checkpoint(month: 8, day: 31, assets: 10000, liabilities: 0);
      final latest = checkpoint(assets: 9880, liabilities: 0);
      await pumpDetails(tester,
          child: VerifiedNetWorthCard(
              checkpoints: [earlier, latest],
              comparison: compareNetWorthVerifiedCheckpoints(earlier, latest)));
      final amount =
          MoneyFormat.string(Decimal.parse('-1.20')).replaceAll('¥', '').trim();
      expect(find.text('较上次完整核对 $amount'), findsOneWidget);
    });
  }
  testWidgets(
      'details behavior partial structure keeps amounts not a false 100 percent',
      (tester) async {
    await pumpDetails(tester, scene: 'partial');
    expect(find.text('部分金额待确认，占比暂不可比'), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-structure-bar')), findsNothing);
    expect(find.text('58.5%'), findsNothing);
    expect(find.text('42,000.00'), findsOneWidget);
  });
  testWidgets(
      'details behavior single bucket avoids redundant chart and duplicate total',
      (tester) async {
    await pumpDetails(tester, scene: 'single');
    expect(find.byKey(const ValueKey('asset-structure-bar')), findsNothing);
    expect(find.text('100.0%'), findsOneWidget);
    expect(find.text('总资产'), findsNothing);
  });
  testWidgets(
      'details behavior semantic rows include amount currency and share',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDetails(tester);
    try {
      final semantics = tester
          .widget<Semantics>(find.byKey(const ValueKey('asset-structure-cash')))
          .properties
          .label!;
      expect(semantics, contains('42,000.00 人民币'));
      expect(semantics, contains('58.5%'));
    } finally {
      handle.dispose();
    }
  });
  testWidgets('details behavior mismatched total never creates a chart',
      (tester) async {
    await pumpDetails(tester,
        child: AssetAnalysisCard(
            breakdown: breakdown(totalOverride: Decimal.fromInt(90000))));
    expect(find.text('金额口径待核实，占比暂不可比'), findsOneWidget);
    expect(find.byKey(const ValueKey('asset-structure-bar')), findsNothing);
    expect(find.text('42,000.00'), findsOneWidget);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('details behavior long amount fits 320px scale $scale',
        (tester) async {
      await pumpDetails(tester,
          size: const Size(320, 1000),
          scale: scale,
          child: AssetAnalysisCard(
              breakdown:
                  breakdown(cashOverride: Decimal.parse('999999999999.99'))));
      final amount = find.text('999,999,999,999.99');
      expect(amount, findsOneWidget);
      final frame =
          tester.getRect(find.byKey(const ValueKey('asset-structure-cash')));
      final text = tester.getRect(
          find.ancestor(of: amount, matching: find.byType(FittedBox)).first);
      expect(text.left, greaterThanOrEqualTo(frame.left));
      expect(text.right, lessThanOrEqualTo(frame.right));
      expect(tester.takeException(), isNull);
      await captureDetails(tester, 'long-amount-$scale');
    });
  }
  for (final theme in ['warm', 'white', 'night']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('details behavior sheet $theme 320px scale $scale',
          (tester) async {
        await pumpDetails(tester,
            theme: theme,
            scene: 'partial',
            size: const Size(320, 1000),
            scale: scale);
        await captureDetails(tester, '$theme-narrow-$scale');
        await tester.tap(find.byTooltip('查看上次核对详情'));
        await tester.pumpAndSettle();
        expect(find.text('上次核对详情'), findsOneWidget);
        expect(find.text('有物品估值待确认，未确认金额不计入本次核对。'), findsOneWidget);
        expect(find.text('存在未换算的外币账户。'), findsOneWidget);
        expect(find.text('本次核对只覆盖部分资产，暂不比较变化。'), findsOneWidget);
        expect(find.textContaining('The later checkpoint'), findsNothing);
        expect(find.text('当时总资产'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureDetails(tester, '$theme-sheet-$scale');
        await tester.tap(find
            .descendant(
                of: find.byType(SheetHeader),
                matching: find.byType(AppCircleButton))
            .first);
        await tester.pumpAndSettle();
        expect(find.text('上次核对详情'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
