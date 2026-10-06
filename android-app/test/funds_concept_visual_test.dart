import 'dart:io';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/app_clock.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/statistics/metric_contract.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/theme/app_theme_controller.dart';
import 'package:qingji/views/assets/asset_overview_style.dart';
import 'package:qingji/views/assets/asset_overview_cards.dart';
import 'package:qingji/views/assets/funds_tab_cards.dart';
import 'package:qingji/views/assets/funds_summary_card.dart';
import 'package:qingji/views/settings/accounts_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshot_font_support.dart';

const _captureKey = ValueKey('funds-concept-capture');
const _partialFundsText = '部分金额待确认，仅含已覆盖的人民币资金';

Future<AppRepository> _seedFunds() async {
  final repo = AppRepository();
  await repo.init();
  await repo.addAccount(
      name: '日常银行卡',
      type: AccountType.debit,
      institution: '招商银行',
      openingBalance: Decimal.fromInt(28000));
  await repo.addAccount(
      name: '备用储蓄',
      type: AccountType.savings,
      openingBalance: Decimal.fromInt(14000));
  await repo.addAccount(
      name: '长期投资',
      type: AccountType.investment,
      openingBalance: Decimal.fromInt(96000));
  await repo.addAccount(
      name: '信用卡',
      type: AccountType.credit,
      institution: '招商银行',
      openingBalance: Decimal.fromInt(-51600));
  await repo.addReceivableAsset(
      name: '房屋押金',
      type: ReceivableAssetType.rentalDeposit,
      originalAmount: Decimal.fromInt(12000));
  await repo.addReceivableAsset(
      name: '借出款',
      type: ReceivableAssetType.loanOut,
      originalAmount: Decimal.fromInt(40000));
  await repo.setLastAssetViewTabIndex(1);
  return repo;
}

Future<void> _capture(WidgetTester tester, String name,
    {String? suffixOverride}) async {
  if (Platform.environment['UPDATE_ASSET_SCREENSHOTS'] != '1') return;
  final output = Platform.environment['ASSET_SCREENSHOT_OUTPUT_DIR'] ??
      'outputs/ui_comparisons/2026-10-06-concept';
  final suffix =
      suffixOverride ?? Platform.environment['ASSET_SHOT_SUFFIX'] ?? 'after';
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/funds-$name-$suffix.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<AppRepository> _repoForTest(WidgetTester tester) async {
  final tmp = Directory.systemTemp.createTempSync('fm_funds_concept_');
  await databaseFactory.setDatabasesPath(tmp.path);
  final repo = (await tester.runAsync(_seedFunds))!;
  addTearDown(() async {
    await tester.runAsync(repo.closeForTest);
    tmp.deleteSync(recursive: true);
  });
  return repo;
}

Future<void> _reloadAssets(AppRepository repo) async {
  // Account-only reloadForTest does not refresh physical assets or valuations.
  final originalBookId = repo.currentBookId;
  final temporaryBookId =
      await repo.addBook(name: '质量验证重载', includeInTotal: false);
  await repo.switchBook(temporaryBookId);
  await repo.switchBook(originalBookId);
  await repo.deleteBook(temporaryBookId);
}

Future<void> _pumpFunds(WidgetTester tester, AppRepository repo,
    {String theme = 'warm',
    Size size = const Size(420, 912),
    double scale = 1}) async {
  final preset = kThemePresets.firstWhere((item) => item.key == theme);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  AppColors.applyTheme(
      bgTop: preset.top,
      bgBottom: preset.bottom,
      bgSolid: preset.solid,
      bgDark: preset.bottom,
      bgDarkTop: preset.top,
      cardAlphaL: 0.8,
      cardAlphaD: 0.8);
  final base = preset.forceDark ? AppTheme.dark() : AppTheme.light();
  await tester.pumpWidget(RepaintBoundary(
      key: _captureKey,
      child: ChangeNotifierProvider.value(
        value: repo,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            textTheme: base.textTheme
                .apply(fontFamilyFallback: const [screenshotCjkFontFamily]),
            appBarTheme: base.appBarTheme.copyWith(
                titleTextStyle: base.appBarTheme.titleTextStyle!.copyWith(
                    fontFamilyFallback: const [screenshotCjkFontFamily])),
          ),
          builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                  size: size, textScaler: TextScaler.linear(scale)),
              child: DecoratedBox(
                  decoration: AppColors.pageBackground(base.brightness),
                  child: child)),
          home: const AccountsView(),
        ),
      )));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('asset-funds')), findsOneWidget);
  final segment = find.byKey(const Key('asset-view-segment'));
  final visibleRect = tester.getRect(segment).deflate(3);
  for (final label in ['总览', '资金', '物品']) {
    final text = find.descendant(of: segment, matching: find.text(label));
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final rect = tester.getRect(text);
    expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width),
        lessThanOrEqualTo(paragraph.size.height + 0.01),
        reason: '$label must retain its full line height at scale $scale');
    expect(rect.top, greaterThanOrEqualTo(visibleRect.top));
    expect(rect.bottom, lessThanOrEqualTo(visibleRect.bottom));
    expect(rect.left, greaterThanOrEqualTo(visibleRect.left));
    expect(rect.right, lessThanOrEqualTo(visibleRect.right));
  }
  expect(tester.takeException(), isNull);
}

Decimal _summaryValue(WidgetTester tester) => tester
    .widget<AssetOverviewAmount>(find.descendant(
        of: find.byKey(const Key('funds-summary')),
        matching: find.byType(AssetOverviewAmount)))
    .value;

Future<void> _filter(WidgetTester tester, String kind) async {
  final filter = find.byKey(Key('funds-filter-$kind'));
  await tester.ensureVisible(filter);
  await tester.tap(filter);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Finder get _verticalScroll => find.byWidgetPredicate((widget) =>
    widget is Scrollable && widget.axisDirection == AxisDirection.down);

Future<void> _top(WidgetTester tester) async {
  await tester.drag(_verticalScroll, const Offset(0, 2000));
  await tester.pumpAndSettle();
}

bool _fundsPartial(AppRepository repo,
        {MetricResult<NetWorthBreakdown>? result}) =>
    fundsSummaryIsPartial(
        netWorthResult: result ?? repo.currentNetWorthResult(),
        physicalAssets: [
          ...repo.globalActivePhysicalAssets,
          ...repo.globalArchivedPhysicalAssets
        ],
        receivableAssets: [
          ...repo.globalActiveReceivables,
          ...repo.globalArchivedReceivables
        ]);

Future<void> _pumpSummary(
    WidgetTester tester, ThemeData theme, NetWorthBreakdown breakdown,
    {required bool partial}) async {
  const size = Size(420, 260);
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          builder: (_, child) => MediaQuery(
              data: const MediaQueryData(size: size),
              child: DecoratedBox(
                  decoration: AppColors.pageBackground(theme.brightness),
                  child: child)),
          home: Scaffold(
              backgroundColor: Colors.transparent,
              body: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FundsSummaryCard(
                          breakdown: breakdown, partial: partial)))))));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadScreenshotFonts(force: true);
    final nunito = FontLoader('Nunito');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
    ]) {
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
    for (final scenario in [
      (const Size(420, 912), 1.0),
      (const Size(320, 912), 2.0),
    ]) {
      final (size, scale) = scenario;
      testWidgets(
          'funds concept ${preset.key} ${size.width.toInt()} scale $scale',
          (tester) async {
        final repo = await _repoForTest(tester);
        expect(repo.globalActiveReceivables.length, 2);
        expect(repo.accounts.any((account) => account.name == '长期投资'), isTrue);
        await _pumpFunds(tester, repo,
            theme: preset.key, size: size, scale: scale);
        await _capture(
            tester, '${preset.key}-${size.width.toInt()}-${scale.toInt()}');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
    testWidgets('funds quality excludes physical-only issues ${preset.key}',
        (tester) async {
      final repo = await _repoForTest(tester);
      await tester.runAsync(() async {
        final id = await repo.addPhysicalAsset(
            name: '待确认相机', currentValue: Decimal.fromInt(700));
        await repo.debugDb.update(
            'physical_assets', {'inclusion_quality': 'needs_review'},
            where: 'id = ?', whereArgs: [id]);
        await repo.debugDb
            .delete('asset_valuations', where: 'asset_id = ?', whereArgs: [id]);
        await _reloadAssets(repo);
      });
      final result = repo.currentNetWorthResult();
      expect(result.status, MetricStatus.partial);
      expect(result.reasons.map((reason) => reason.details['domain']),
          containsAll(['physical_asset', 'valuation']));
      await _pumpFunds(tester, repo, theme: preset.key);
      expect(find.text(_partialFundsText), findsNothing);
      expect(_summaryValue(tester), Decimal.fromInt(138400));
      final theme = Theme.of(tester.element(find.byType(AccountsView)));
      for (final before in [true, false]) {
        await _pumpSummary(tester, theme, result.value!,
            partial: before
                ? result.status != MetricStatus.available
                : _fundsPartial(repo));
        expect(find.text(_partialFundsText),
            before ? findsOneWidget : findsNothing);
        await _capture(tester, 'quality-${preset.key}',
            suffixOverride: before ? 'before' : 'after');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('funds quality retains real account and unknown financial issues',
      (tester) async {
    final repo = await _repoForTest(tester);
    await tester.runAsync(() async {
      final category =
          repo.categoriesForKindRanked(TransactionKind.expense).first;
      final account = repo.accounts.first;
      const originalUuid = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      await repo.importFeimiaoExportRows([
        FeimiaoImportRow(
            uuid: originalUuid,
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(100),
            refunded: Decimal.zero,
            categoryKey: category.key,
            accountName: account.name,
            note: '差旅',
            date: DateTime(2026, 6, 1)),
        FeimiaoImportRow(
            uuid: 'cccccccccccccccccccccccccccccccc',
            refundOfUuid: originalUuid,
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(40),
            refunded: Decimal.zero,
            categoryKey: category.key,
            accountName: account.name,
            note: '报销到账',
            date: DateTime(2026, 6, 1)),
      ]);
      // Imported knowledge must not fall after the fixed capture clock.
      await repo.debugDb.update(
          'transactions', {'created_ms': AppClock.now.millisecondsSinceEpoch},
          where: 'uuid IN (?, ?)',
          whereArgs: [originalUuid, 'cccccccccccccccccccccccccccccccc']);
      await _reloadAssets(repo);
    });
    final result = repo.currentNetWorthResult();
    expect(result.status, MetricStatus.partial);
    expect(result.reasons.map((reason) => reason.code),
        contains(MetricReasonCode.unknownSettlementAccount));
    await _pumpFunds(tester, repo);
    expect(find.text(_partialFundsText), findsOneWidget);
    for (final details in <Map<String, Object?>>[
      {},
      {'domain': 'receivable'},
      {'account_id': repo.accounts.first.id},
      {'asset_id': 1, 'currency': 'USD'},
    ]) {
      final unknown = MetricResult<NetWorthBreakdown>.partial(
          value: result.value!,
          query: result.query,
          resolver: 'funds-quality-boundary',
          reasons: [
            MetricReason(
                code: MetricReasonCode.invalidInput,
                message: '物品文字不决定原因归属',
                details: details)
          ]);
      expect(_fundsPartial(repo, result: unknown), isTrue);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('funds foreign quality preserves receivable ID collisions',
      (tester) async {
    final repo = await _repoForTest(tester);
    late int physicalId;
    await tester.runAsync(() async {
      physicalId = await repo.addPhysicalAsset(
          name: '外币相机', currentValue: Decimal.fromInt(700));
      await repo.debugDb.update('physical_assets', {'currency_code': 'USD'},
          where: 'id = ?', whereArgs: [physicalId]);
      await _reloadAssets(repo);
    });
    final physicalOnly = repo.currentNetWorthResult();
    expect(physicalOnly.status, MetricStatus.partial);
    expect(
        physicalOnly.reasons.any((reason) =>
            reason.code == MetricReasonCode.unsupportedCurrencyAggregation &&
            reason.details['asset_id'] == physicalId &&
            !reason.details.containsKey('domain')),
        isTrue);
    await _pumpFunds(tester, repo);
    expect(find.text(_partialFundsText), findsNothing);
    expect(_summaryValue(tester), Decimal.fromInt(138400));
    expect(repo.globalActiveReceivables.any((asset) => asset.id == physicalId),
        isTrue);
    await tester.runAsync(() async {
      await repo.debugDb.update('receivable_assets', {'currency_code': 'USD'},
          where: 'id = ?', whereArgs: [physicalId]);
      await _reloadAssets(repo);
    });
    await tester.pumpAndSettle();
    expect(repo.currentNetWorthResult().status, MetricStatus.partial);
    expect(_fundsPartial(repo), isTrue);
    expect(find.text(_partialFundsText), findsOneWidget);
    expect(_summaryValue(tester), Decimal.fromInt(126400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('funds search and type filters never change global summary',
      (tester) async {
    final repo = await _repoForTest(tester);
    await _pumpFunds(tester, repo);
    final summary = _summaryValue(tester);
    expect(summary, Decimal.fromInt(138400));
    await tester.enterText(find.byKey(const Key('funds-search')), '招商');
    await tester.pumpAndSettle();
    expect(find.text('日常银行卡'), findsOneWidget);
    expect(find.text('信用卡'), findsOneWidget);
    expect(find.text('备用储蓄'), findsNothing);
    expect(find.text('长期投资'), findsNothing);
    expect(find.text('房屋押金'), findsNothing);
    expect(_summaryValue(tester), summary);
    await tester.enterText(find.byKey(const Key('funds-search')), '');
    await tester.pumpAndSettle();
    for (final (kind, names) in [
      ('accounts', ['日常银行卡', '备用储蓄']),
      ('investment', ['长期投资']),
      ('receivables', ['房屋押金', '借出款']),
      ('liabilities', ['信用卡']),
    ]) {
      await _filter(tester, kind);
      for (final name in ['日常银行卡', '备用储蓄', '长期投资', '房屋押金', '借出款', '信用卡']) {
        expect(
            find.byWidgetPredicate(
                (widget) => widget is FundsAssetRow && widget.title == name),
            names.contains(name) ? findsOneWidget : findsNothing);
      }
      expect(_summaryValue(tester), summary);
    }
    await _filter(tester, 'all');
    await tester.enterText(find.byKey(const Key('funds-search')), '完全不存在的账户');
    await tester.pumpAndSettle();
    expect(find.byType(FundsAccountBalanceTile), findsNothing);
    expect(find.byType(AssetEmptyState), findsOneWidget);
    expect(find.text('日常银行卡'), findsNothing);
    expect(find.text('借贷往来 ›'), findsNothing);
    expect(_summaryValue(tester), summary);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('funds name sort changes row order without changing money',
      (tester) async {
    final repo = await _repoForTest(tester);
    await tester.runAsync(() async {
      await repo.addAccount(
          name: 'A先账户',
          type: AccountType.debit,
          openingBalance: Decimal.fromInt(10));
      final z = await repo.addAccount(
          name: 'Z后账户',
          type: AccountType.debit,
          openingBalance: Decimal.fromInt(20));
      await repo.renameAccount(z, 'Z后账户');
    });
    await _pumpFunds(tester, repo);
    await tester.enterText(find.byKey(const Key('funds-search')), '账户');
    await tester.pumpAndSettle();
    final summary = _summaryValue(tester);
    expect(summary, Decimal.fromInt(138430));
    expect(tester.getTopLeft(find.text('Z后账户')).dy,
        lessThan(tester.getTopLeft(find.text('A先账户')).dy));
    await tester.ensureVisible(find.text('最近更新'));
    await tester.tap(find.text('最近更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('名称').last);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('A先账户')).dy,
        lessThan(tester.getTopLeft(find.text('Z后账户')).dy));
    expect(_summaryValue(tester), summary);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('funds archive view keeps current and archived rows separate',
      (tester) async {
    final repo = await _repoForTest(tester);
    await tester.runAsync(() async {
      final id = await repo.addAccount(
          name: '历史银行卡',
          type: AccountType.debit,
          openingBalance: Decimal.fromInt(500));
      await repo.archiveAccount(id);
    });
    await _pumpFunds(tester, repo);
    final summary = _summaryValue(tester);
    expect(find.text('历史银行卡'), findsNothing);
    await tester.scrollUntilVisible(find.text('已归档 1 项 ›'), 300,
        scrollable: _verticalScroll);
    await tester.tap(find.text('已归档 1 项 ›'));
    await tester.pumpAndSettle();
    await _top(tester);
    expect(find.text('历史银行卡'), findsOneWidget);
    expect(find.text('日常银行卡'), findsNothing);
    expect(find.text('长期投资'), findsNothing);
    expect(_summaryValue(tester), summary);
    await tester.tap(find.text('‹ 返回当前项目'));
    await tester.pumpAndSettle();
    expect(find.text('历史银行卡'), findsNothing);
    expect(_summaryValue(tester), summary);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
