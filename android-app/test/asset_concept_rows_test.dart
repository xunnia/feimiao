import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/assets/asset_enhancements.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/assets/asset_overview_cards.dart';
import 'package:qingji/views/assets/funds_tab_cards.dart';
import 'package:qingji/views/assets/receivable_detail_page.dart';

import 'screenshot_font_support.dart';

class _RowsRepository extends AppRepository {
  @override
  AssetReminderState dueReminderForReceivable(ReceivableAssetEntity asset,
          {DateTime? asOf}) =>
      super
          .dueReminderForReceivable(asset, asOf: asOf ?? DateTime(2026, 10, 6));
}

Future<void> _pumpRows(WidgetTester tester, Widget child,
    {Size size = const Size(420, 1000),
    double scale = 1,
    bool dark = false}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final base = dark ? AppTheme.dark() : AppTheme.light();
  await tester.pumpWidget(MaterialApp(
    theme: base.copyWith(
        textTheme: base.textTheme
            .apply(fontFamilyFallback: const [screenshotCjkFontFamily])),
    builder: (context, child) => MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16), child: child)),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => loadScreenshotFonts(force: true));
  tearDown(MoneyFormat.resetConfig);

  testWidgets('pending concept supports existing items with default action',
      (tester) async {
    var taps = 0;
    final item = AssetPendingItem(
        icon: Icons.schedule, text: '权益到期', onTap: () => taps++);
    expect(item.subtitle, isNull);
    expect(item.actionLabel, '查看');
    await _pumpRows(tester, AssetPendingCard(items: [item]));
    expect(find.text('1 项'), findsOneWidget);
    expect(find.text('查看'), findsOneWidget);
    await tester.tap(find.text('查看'));
    expect(taps, 1);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('pending concept 3 actions fit 320px $dark scale $scale',
          (tester) async {
        final tapped = <int>[];
        final items = [
          for (var i = 0; i < 3; i++)
            AssetPendingItem(
              icon: Icons.schedule,
              text: '第 ${i + 1} 项需要完善的资产信息',
              subtitle: '保留真实到期状态与资料来源，长副标题可换行',
              actionLabel: '查看并补充资料',
              onTap: () => tapped.add(i),
            ),
        ];
        await _pumpRows(tester, AssetPendingCard(items: items),
            size: const Size(320, 1600), scale: scale, dark: dark);
        expect(find.text('3 项'), findsOneWidget);
        expect(find.text('查看并补充资料'), findsNWidgets(3));
        final card = tester.getRect(find.byType(AssetPendingCard));
        for (var i = 0; i < 3; i++) {
          final action = find.text('查看并补充资料').at(i);
          final rect = tester.getRect(action);
          expect(rect.left, greaterThanOrEqualTo(card.left));
          expect(rect.right, lessThanOrEqualTo(card.right));
          await tester.ensureVisible(action);
          await tester.tap(action);
        }
        expect(tapped, [0, 1, 2]);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('receivable concept keeps status source due 320px scale $scale',
        (tester) async {
      final repo = _RowsRepository();
      addTearDown(repo.dispose);
      final amount = Decimal.parse('999999999999.99');
      final asset = ReceivableAssetEntity(
          id: 8,
          name: '给小王的长期借出款与垫付费用',
          type: ReceivableAssetType.loanOut,
          economicStatus: ReceivableEconomicStatus.partialRecovered,
          originalAmount: amount + Decimal.fromInt(100),
          remainingAmount: amount,
          counterparty: '小王',
          dueDateMs: DateTime(2026, 10, 4).millisecondsSinceEpoch);
      ReceivableAssetEntity? tapped;
      await _pumpRows(
          tester,
          ChangeNotifierProvider<AppRepository>.value(
              value: repo,
              child: ReceivableAssetGroupCard(
                  assets: [asset], onTap: (value) => tapped = value)),
          size: const Size(320, 1000),
          scale: scale);
      expect(find.byType(FundsAssetRow), findsOneWidget);
      expect(find.text('借出款 · 小王 · 部分收回'), findsOneWidget);
      final due = find.byKey(const Key('receivable-due-8'));
      expect(tester.widget<Text>(due).data, '已逾期 2 天');
      expect(tester.widget<Text>(due).style!.color, AppColors.warning);
      final title = tester.widget<Text>(find.text(asset.name));
      expect(title.style!.fontSize, 15);
      expect(title.style!.fontWeight, FontWeight.w500);
      final money = find.text(MoneyFormat.string(amount));
      expect(tester.widget<Text>(money).style!.fontSize, 15.5);
      expect(tester.widget<Text>(money).style!.fontWeight, FontWeight.w700);
      final frame = tester.getRect(find.byType(FundsAssetRow));
      final fitted = tester.getRect(
          find.ancestor(of: money, matching: find.byType(FittedBox)).first);
      expect(fitted.left, greaterThanOrEqualTo(frame.left));
      expect(fitted.right, lessThanOrEqualTo(frame.right));
      await tester.tap(find.text(asset.name));
      expect(tapped, same(asset));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('receivable concept recovered state has no false due reminder',
      (tester) async {
    final repo = _RowsRepository();
    addTearDown(repo.dispose);
    final asset = ReceivableAssetEntity(
        id: 9,
        name: '房东押金',
        type: ReceivableAssetType.rentalDeposit,
        economicStatus: ReceivableEconomicStatus.recovered,
        originalAmount: Decimal.fromInt(2000),
        remainingAmount: Decimal.zero,
        counterparty: '房东',
        dueDateMs: DateTime(2026, 10, 1).millisecondsSinceEpoch);
    await _pumpRows(
        tester,
        ChangeNotifierProvider<AppRepository>.value(
            value: repo,
            child: ReceivableAssetGroupCard(assets: [asset], onTap: (_) {})));
    expect(find.text('租房押金 · 房东 · 已收回'), findsOneWidget);
    expect(find.byKey(const Key('receivable-due-9')), findsNothing);
    expect(
        tester.widget<FundsAssetRow>(find.byType(FundsAssetRow)).muted, isTrue);
  });
}
