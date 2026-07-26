import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/assets/asset_allocation.dart';
import 'package:qingji/core/models/recurring_rule.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/views/settings/accounts_view.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/settings_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_asset_view_test_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() async {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppRepository> seededGlobalRepo() async {
    final repo = AppRepository();
    await repo.init();
    final defaultBookId = repo.defaultBookId;
    final privateBookId = await repo.addBook(
      name: '不计总账本的私有账本',
      includeInTotal: false,
    );
    await repo.switchBook(privateBookId);
    await repo.addPhysicalAsset(
      name: '跨账本相机',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(600),
      purchasePrice: Decimal.fromInt(1000),
      purchaseDate: DateTime(2026, 7, 1),
    );
    await repo.addReceivableAsset(
      name: '跨账本押金',
      type: ReceivableAssetType.securityDeposit,
      originalAmount: Decimal.fromInt(1000),
    );
    await repo.switchBook(defaultBookId);
    return repo;
  }

  Future<void> pumpViewAnimations(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pumpAccountsView(
    WidgetTester tester,
    AppRepository repo, {
    TextScaler? textScaler,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          builder: textScaler == null
              ? null
              : (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: textScaler,
                    ),
                    child: child!,
                  ),
          home: const AccountsView(),
        ),
      ),
    );
    await pumpViewAnimations(tester);
  }

  Future<void> scrollLastListTo(
    WidgetTester tester,
    Finder finder, {
    double delta = 360,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollLastGridTo(
    WidgetTester tester,
    Finder finder, {
    double delta = 320,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPhysicalAssetMoreMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
  }

  Future<void> closePhysicalAssetDetail(WidgetTester tester) async {
    final detail = find.byKey(const Key('physical-asset-detail-page'));
    expect(detail, findsOneWidget);
    Navigator.of(tester.element(detail)).pop();
    await pumpViewAnimations(tester);
  }

  Future<DateTime> pickPreviousMonthDate(
    WidgetTester tester,
    Finder field,
  ) async {
    await scrollLastListTo(tester, field, delta: 260);
    await tester.tap(field);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.chevron_left).last);
    await tester.pump(const Duration(milliseconds: 250));
    final day = find.descendant(
      of: find.byKey(const ValueKey('grid')),
      matching: find.text('15'),
    );
    expect(day, findsOneWidget);
    await tester.tap(day);
    await tester.tap(find.text('确认').last);
    await tester.pumpAndSettle();

    final now = DateTime.now();
    return DateTime(now.year, now.month - 1, 15);
  }

  Future<void> waitForFormToClose(
    WidgetTester tester,
    Key formFieldKey,
  ) async {
    final formField = find.byKey(formFieldKey);
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (formField.evaluate().isEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(formField, findsNothing);
  }

  testWidgets('asset management exposes three page-local views',
      (tester) async {
    final repo = (await tester.runAsync(seededGlobalRepo))!;
    addTearDown(() => tester.runAsync(repo.closeForTest));
    await pumpAccountsView(tester, repo);

    expect(find.byKey(const Key('asset-view-segment')), findsOneWidget);
    expect(find.text('总览'), findsOneWidget);
    expect(find.text('资金'), findsOneWidget);
    expect(find.text('物品'), findsOneWidget);
    expect(find.byKey(const Key('asset-overview')), findsOneWidget);
    expect(find.byKey(const Key('asset-funds')), findsNothing);
    expect(find.byKey(const Key('asset-items')), findsNothing);

    await tester.tap(find.text('资金'));
    await pumpViewAnimations(tester);
    expect(find.byKey(const Key('asset-overview')), findsNothing);
    expect(find.byKey(const Key('asset-funds')), findsOneWidget);
    expect(find.byKey(const Key('asset-items')), findsNothing);
    expect(find.text('跨账本押金'), findsOneWidget);
    expect(find.text('跨账本相机'), findsNothing);

    await tester.tap(find.text('物品'));
    await pumpViewAnimations(tester);
    expect(find.byKey(const Key('asset-overview')), findsNothing);
    expect(find.byKey(const Key('asset-funds')), findsNothing);
    expect(find.byKey(const Key('asset-items')), findsOneWidget);
    expect(find.text('跨账本相机'), findsOneWidget);
    expect(find.text('跨账本押金'), findsNothing);
    expect(find.textContaining('/天'), findsOneWidget);
    expect(find.textContaining('数码设备 · 在用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('被定时记账占用的账户会解释原因且不会从详情归档', (tester) async {
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    final accountId = await tester.runAsync(
      () => repo.addAccount(name: '定时扣款账户'),
    );
    await tester.runAsync(
      () => repo.addRecurringRule(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(88),
        accountId: accountId,
        period: RecurPeriod.monthly,
        startDate: DateTime(2099, 1, 1),
        note: '未来固定支出',
      ),
    );

    await pumpAccountsView(tester, repo);
    await tester.tap(find.text('资金'));
    await pumpViewAnimations(tester);
    // 新账户余额为 0，默认折叠进「已清零账户」卡，先展开再点。
    await tester.tap(find.byKey(const Key('zero-balance-accounts-toggle')));
    await tester.pump();
    await tester.tap(find.text('定时扣款账户').first);
    await tester.pumpAndSettle();

    expect(
      find.text('1 个定时记账仍使用此账户，先修改或删除相关规则'),
      findsOneWidget,
    );
    // 归档动作已收进详情页右上角 ⋯ 菜单，先开菜单再点。
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('account-archive-action-$accountId')),
    );
    await tester.pump();

    expect(find.text('请先修改或删除使用此账户的定时记账'), findsOneWidget);
    expect(
      repo.activeAccounts.any((account) => account.id == accountId),
      isTrue,
    );
    expect(
      repo.archivedAccounts.any((account) => account.id == accountId),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'overview is global and removes the monthly cash-flow pseudo metric',
      (tester) async {
    final repo = (await tester.runAsync(seededGlobalRepo))!;
    addTearDown(() => tester.runAsync(repo.closeForTest));
    await pumpAccountsView(tester, repo);

    expect(repo.physicalAssets, isEmpty);
    expect(repo.receivableAssets, isEmpty);
    expect(repo.globalActivePhysicalAssets, hasLength(1));
    expect(repo.globalActiveReceivables, hasLength(1));
    expect(find.byKey(const Key('asset-overview')), findsOneWidget);
    expect(find.text('净资产'), findsOneWidget);
    expect(find.text('净资产趋势'), findsOneWidget);
    expect(find.text('自动估算'), findsOneWidget);
    expect(find.text('本月收支净额'), findsNothing);
    expect(find.textContaining('本月收支净额'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '320dp two-step purchase flow reuses one bill without duplicate expense',
      (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    await tester.runAsync(() => repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(299),
          accountId: repo.accounts.first.id,
          date: DateTime(2026, 7, 13),
          note: '机械键盘订单',
        ));
    final transactionCount = repo.transactions.length;
    await pumpAccountsView(tester, repo);

    await tester.tap(find.text('物品'));
    await pumpViewAnimations(tester);
    await tester.tap(find.byIcon(Icons.add));
    await pumpViewAnimations(tester);
    expect(find.text('从最近账单加入'), findsOneWidget);

    await tester.tap(find.text('从最近账单加入'));
    await pumpViewAnimations(tester);
    expect(find.text('机械键盘订单'), findsOneWidget);
    await tester.tap(find.text('机械键盘订单'));
    await pumpViewAnimations(tester);
    expect(find.text('填写物品信息'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('asset-purchase-name')),
      '机械键盘',
    );
    await tester.pump();
    final saveButton = tester.widget<AppPillButton>(
      find.byKey(const Key('asset-purchase-save')),
    );
    expect(saveButton.onPressed, isNotNull);
    await tester.runAsync(() async {
      saveButton.onPressed!();
      for (var attempt = 0;
          attempt < 100 && repo.globalActivePhysicalAssets.isEmpty;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await waitForFormToClose(
      tester,
      const Key('physical-asset-name'),
    );

    expect(
      repo.globalActivePhysicalAssets,
      hasLength(1),
      reason: find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .whereType<String>()
          .join(' | '),
    );
    expect(repo.globalActivePhysicalAssets.single.name, '机械键盘');
    expect(
      repo.globalActivePhysicalAssets.single.purchaseDate,
      DateTime(2026, 7, 13),
    );
    expect(repo.transactions.length, transactionCount);
    expect(tester.takeException(), isNull);
  });

  testWidgets('统一添加弹层内嵌最近账单，点行一步直达填写物品信息', (tester) async {
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    await tester.runAsync(() => repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(499),
          accountId: repo.accounts.first.id,
          date: DateTime(2026, 7, 20),
          note: '降噪耳机订单',
        ));
    await pumpAccountsView(tester, repo);

    // 总览 tab 的右上 ＋ 也开统一「添加」弹层（三个 tab 行为一致）。
    await tester.tap(find.byIcon(Icons.add));
    await pumpViewAnimations(tester);
    expect(find.text('添加账户'), findsOneWidget);
    expect(find.text('添加权益'), findsOneWidget);
    expect(find.text('新购买记账'), findsOneWidget);
    expect(find.text('从最近账单加入'), findsOneWidget);
    expect(find.text('手工补录物品'), findsOneWidget);
    // 「从最近账单加入」下方内嵌最近可加入的支出账单行。
    expect(find.text('降噪耳机订单'), findsOneWidget);

    // 点内嵌账单行一步直达「填写物品信息」表单，跳过完整账单列表。
    await tester.tap(find.text('降噪耳机订单'));
    await pumpViewAnimations(tester);
    expect(find.text('填写物品信息'), findsOneWidget);
    expect(find.byKey(const Key('asset-purchase-search')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手工补录保存历史购买日、闲置状态和未知购置成本', (tester) async {
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    await pumpAccountsView(tester, repo);

    await tester.tap(find.text('物品'));
    await pumpViewAnimations(tester);
    await tester.tap(find.byIcon(Icons.add));
    await pumpViewAnimations(tester);
    await tester.tap(find.text('手工补录物品'));
    await pumpViewAnimations(tester);

    await tester.enterText(
      find.byKey(const Key('physical-asset-name')),
      '旧相机',
    );
    await tester.enterText(
      find.byKey(const Key('physical-asset-current-value')),
      '1800',
    );
    final expectedDate = await pickPreviousMonthDate(
      tester,
      find.byKey(const Key('physical-asset-purchase-date')),
    );
    await scrollLastListTo(
      tester,
      find.byKey(const Key('physical-asset-usage-status')),
      delta: 220,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('physical-asset-usage-status')),
        matching: find.text('闲置'),
      ),
    );
    await tester.pump();

    final saveButton = tester.widget<AppPillButton>(
      find.widgetWithText(AppPillButton, '保存').last,
    );
    expect(saveButton.onPressed, isNotNull);
    await tester.runAsync(() async {
      saveButton.onPressed!();
      for (var attempt = 0;
          attempt < 100 &&
              !repo.globalActivePhysicalAssets
                  .any((asset) => asset.name == '旧相机');
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await waitForFormToClose(
      tester,
      const Key('physical-asset-name'),
    );

    final asset = repo.globalActivePhysicalAssets.singleWhere(
      (item) => item.name == '旧相机',
    );
    expect(asset.purchaseDate, expectedDate);
    expect(asset.usageStatus, PhysicalAssetUsageStatus.idle);
    expect(
      asset.acquisitionCostSource,
      AssetAcquisitionCostSource.manualUnknown,
    );
    expect(repo.physicalAssetAcquisitionCost(asset.id).amount, isNull);
    expect(repo.physicalAssetAcquisitionCost(asset.id).isExact, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('缺少购买日期的物品可从详情补录并保存', (tester) async {
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    late int assetId;
    await tester.runAsync(() async {
      assetId = await repo.addPhysicalAsset(
        name: '待补日期耳机',
        currentValue: Decimal.fromInt(600),
        purchasePrice: Decimal.fromInt(900),
      );
    });
    await pumpAccountsView(tester, repo);

    await tester.tap(find.text('物品'));
    await pumpViewAnimations(tester);
    expect(repo.physicalAssetDetailById(assetId)!.purchaseDate, isNull);
    await tester.tap(find.byKey(Key('physical-asset-card-$assetId')));
    await pumpViewAnimations(tester);
    expect(
      find.byKey(const Key('physical-asset-detail-page')),
      findsOneWidget,
    );
    await scrollLastListTo(
      tester,
      find.byKey(const Key('physical-asset-fix-purchase-date')),
      delta: 180,
    );
    expect(
      find.byKey(const Key('physical-asset-fix-purchase-date')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('physical-asset-fix-purchase-date')));
    await pumpViewAnimations(tester);
    final expectedDate = await pickPreviousMonthDate(
      tester,
      find.byKey(const Key('physical-asset-purchase-date')),
    );

    final saveButton = tester.widget<AppPillButton>(
      find.widgetWithText(AppPillButton, '保存').last,
    );
    expect(saveButton.onPressed, isNotNull);
    await tester.runAsync(() async {
      saveButton.onPressed!();
      for (var attempt = 0;
          attempt < 100 &&
              repo.physicalAssetDetailById(assetId)!.purchaseDate == null;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await waitForFormToClose(
      tester,
      const Key('physical-asset-name'),
    );

    expect(repo.physicalAssetDetailById(assetId)!.purchaseDate, expectedDate);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transaction-backed asset rejects a second editable cost',
      (tester) async {
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    late int assetId;
    await tester.runAsync(() async {
      final transactionId = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        accountId: repo.accounts.first.id,
        date: DateTime(2026, 7, 13),
        note: '锁定成本订单',
      );
      assetId = await repo.addPhysicalAssetFromTransaction(
        transactionId: transactionId,
        name: '锁定成本物品',
        allocatedGrossCents: 10000,
      );
      final asset = repo.physicalAssetDetailById(assetId)!;
      await repo.updatePhysicalAsset(
        id: asset.id,
        name: asset.name,
        assetType: asset.assetType,
        purchasePrice: Decimal.one,
        currentValue: asset.currentValue,
        currencyCode: asset.currencyCode,
        status: asset.status,
        purchaseDate: asset.purchaseDate,
        brand: asset.brand,
        model: asset.model,
        location: asset.location,
        warrantyUntil: asset.warrantyUntil,
        note: asset.note,
        includeInNetWorth: asset.includeInNetWorth,
      );
    });
    expect(
      repo.physicalAssetDetailById(assetId)!.purchasePrice,
      Decimal.fromInt(100),
    );
    expect(
      repo.physicalAssetAcquisitionCost(assetId).amount,
      Decimal.fromInt(100),
    );

    await pumpAccountsView(tester, repo);
    await tester.tap(find.text('物品'));
    await pumpViewAnimations(tester);
    await tester.tap(find.text('锁定成本物品'));
    await pumpViewAnimations(tester);

    await scrollLastListTo(tester, find.text('净购置成本'));
    expect(find.text('净购置成本'), findsOneWidget);
    expect(find.text('¥100.00'), findsAtLeastNWidgets(1));
    expect(find.text('购买价'), findsNothing);

    await openPhysicalAssetMoreMenu(tester);
    await tester.tap(find.text('编辑资料'));
    await pumpViewAnimations(tester);
    final purchaseField = tester.widget<TextField>(
      find.byKey(const Key('physical-asset-purchase-price')),
    );
    expect(purchaseField.readOnly, isTrue);
    expect(purchaseField.enableInteractiveSelection, isFalse);
    expect(purchaseField.controller!.text, '100');
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多物订单退款可从物品详情进入人工分配', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    late int keyboardId;
    late int mouseId;
    late int refundId;
    await tester.runAsync(() async {
      final accountId = repo.accounts.first.id;
      final transactionId = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        accountId: accountId,
        date: DateTime(2026, 7, 12),
        note: '桌面设备组合订单',
      );
      keyboardId = await repo.addPhysicalAssetFromTransaction(
        transactionId: transactionId,
        name: '机械键盘',
        allocatedGrossCents: 6000,
      );
      mouseId = await repo.addPhysicalAssetFromTransaction(
        transactionId: transactionId,
        name: '无线鼠标',
        allocatedGrossCents: 4000,
      );
      final original = repo.visibleTransactions.singleWhere(
        (transaction) => transaction.id == transactionId,
      );
      refundId = await repo.refundTransaction(
        original,
        Decimal.fromInt(30),
        settledAt: DateTime(2026, 7, 13),
        settlementAccountId: accountId,
      );
      expect(
        repo.transactionLinksForAsset(keyboardId).single.costQuality,
        AssetAllocationCostQuality.pendingRefundAllocation,
      );
    });
    await pumpAccountsView(tester, repo);

    await tester.tap(find.text('物品'));
    await pumpViewAnimations(tester);
    await tester.tap(find.text('机械键盘'));
    await pumpViewAnimations(tester);
    await scrollLastListTo(tester, find.text('分配退款'), delta: 320);
    expect(find.text('分配退款'), findsOneWidget);

    await tester.tap(find.text('分配退款'));
    await pumpViewAnimations(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.text('桌面设备组合订单'), findsOneWidget);
    expect(find.text('无线鼠标'), findsAtLeastNWidgets(1));

    await tester.enterText(
      find.byKey(Key('asset-refund-input-$refundId-$keyboardId')),
      '30',
    );
    await tester.pump();
    final submit = tester.widget<AppPillButton>(
      find.byKey(Key('asset-refund-submit-$refundId')),
    );
    expect(submit.onPressed, isNotNull);
    await tester.runAsync(() async {
      submit.onPressed!();
      for (var attempt = 0;
          attempt < 100 &&
              !repo.physicalAssetAcquisitionCost(keyboardId).isExact;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.physicalAssetAcquisitionCost(keyboardId).amount,
        Decimal.fromInt(30));
    expect(
        repo.physicalAssetAcquisitionCost(mouseId).amount, Decimal.fromInt(40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('A4 到期提醒在 320dp 大字模式下可读且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    late int assetId;
    late int receivableId;
    await tester.runAsync(() async {
      assetId = await repo.addPhysicalAsset(
        name: '临近保修相机',
        assetType: AssetType.digital,
        currentValue: Decimal.fromInt(800),
        purchasePrice: Decimal.fromInt(1000),
        purchaseDate: today.subtract(const Duration(days: 40)),
        warrantyUntil: today.add(const Duration(days: 5)),
      );
      receivableId = await repo.addReceivableAsset(
        name: '逾期押金',
        type: ReceivableAssetType.securityDeposit,
        originalAmount: Decimal.fromInt(500),
        dueDate: today.subtract(const Duration(days: 2)),
      );
    });
    await pumpAccountsView(
      tester,
      repo,
      textScaler: const TextScaler.linear(1.4),
    );

    expect(find.textContaining('物品保修即将到期或已过期'), findsOneWidget);
    expect(find.textContaining('权益即将到期或已逾期'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('资金'));
    await pumpViewAnimations(tester);
    expect(
      find.byKey(Key('receivable-due-$receivableId')),
      findsOneWidget,
    );
    expect(find.text('已逾期 2 天'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('物品'));
    await pumpViewAnimations(tester);
    expect(
      find.byKey(Key('physical-asset-secondary-$assetId')),
      findsOneWidget,
    );
    expect(find.text('保修还有 5 天'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('临近保修相机'));
    await pumpViewAnimations(tester);
    await scrollLastListTo(tester, find.text('保修'));
    expect(find.textContaining('还有 5 天'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('A4 关联已有支出并完成次数记录闭环', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    late int assetId;
    late int expenseId;
    await tester.runAsync(() async {
      assetId = await repo.addPhysicalAsset(
        name: '使用次数相机',
        assetType: AssetType.digital,
        currentValue: Decimal.fromInt(80),
        purchasePrice: Decimal.fromInt(100),
        purchaseDate: DateTime.now().subtract(const Duration(days: 9)),
      );
      expenseId = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(20),
        accountId: repo.accounts.first.id,
        date: DateTime.now(),
        note: '相机镜头清洁',
      );
    });
    final transactionCount = repo.transactions.length;
    await pumpAccountsView(tester, repo);

    await tester.tap(find.text('物品'));
    await pumpViewAnimations(tester);
    await tester.tap(find.text('使用次数相机'));
    await pumpViewAnimations(tester);
    await scrollLastListTo(
      tester,
      find.byKey(const Key('physical-asset-link-cost')),
    );
    await tester.tap(find.byKey(const Key('physical-asset-link-cost')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('physical-asset-cost-candidate-$expenseId')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(Key('physical-asset-cost-candidate-$expenseId')),
    );
    await tester.pump();
    final submit = tester.widget<AppPillButton>(
      find.byKey(const Key('physical-asset-cost-submit')),
    );
    expect(submit.onPressed, isNotNull);
    submit.onPressed!();
    await tester.runAsync(() async {
      for (var attempt = 0;
          attempt < 100 && repo.additionalCostLinksForAsset(assetId).isEmpty;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump(const Duration(milliseconds: 400));

    expect(repo.transactions.length, transactionCount);
    expect(
        repo.physicalAssetAdditionalCost(assetId).amount, Decimal.fromInt(20));
    expect(
      repo.additionalCostLinksForAsset(assetId).single.linkType,
      AssetTransactionLinkType.maintenance,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await scrollLastListTo(
      tester,
      find.byKey(const Key('physical-asset-usage-tracking')),
    );
    final usageSwitch = tester.widget<AppSwitch>(
      find.byKey(const Key('physical-asset-usage-tracking')),
    );
    expect(usageSwitch.onChanged, isNotNull);
    usageSwitch.onChanged!(true);
    await tester.runAsync(() async {
      for (var attempt = 0;
          attempt < 100 &&
              !repo.physicalAssetDetailById(assetId)!.usageTrackingEnabled;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
    expect(
      repo.physicalAssetDetailById(assetId)!.usageTrackingEnabled,
      isTrue,
    );
    expect(
      find.byKey(const Key('physical-asset-usage-controls')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('physical-asset-usage-add')));
    await tester.runAsync(() async {
      for (var attempt = 0;
          attempt < 100 && repo.physicalAssetUsage(assetId).totalCount != 1;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
    expect(repo.physicalAssetUsage(assetId).totalCount, 1);
    expect(find.text('累计 1 次'), findsOneWidget);

    await closePhysicalAssetDetail(tester);
    expect(
      find.byKey(Key('physical-asset-quick-use-$assetId')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(Key('physical-asset-quick-use-$assetId')));
    await tester.runAsync(() async {
      for (var attempt = 0;
          attempt < 100 && repo.physicalAssetUsage(assetId).totalCount != 2;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
    expect(repo.physicalAssetUsage(assetId).totalCount, 2);
    expect(find.text('编辑'), findsNothing);

    await tester.tap(find.text('使用次数相机'));
    await pumpViewAnimations(tester);
    await scrollLastListTo(
      tester,
      find.byKey(const Key('physical-asset-usage-undo')),
    );
    await tester.tap(find.byKey(const Key('physical-asset-usage-undo')));
    await tester.runAsync(() async {
      for (var attempt = 0;
          attempt < 100 && repo.physicalAssetUsage(assetId).totalCount != 1;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(repo.physicalAssetUsage(assetId).totalCount, 1);
    expect(repo.transactions.length, transactionCount);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('A4 存钱目标可关联解绑且三种终止状态都可撤销', (tester) async {
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    late int goalId;
    final cases = <(String, PhysicalAssetStatus)>[
      ('待撤销报废', PhysicalAssetStatus.disposed),
      ('待撤销丢失', PhysicalAssetStatus.lost),
      ('待撤销赠送', PhysicalAssetStatus.gifted),
    ];
    final assetIds = <int>[];
    await tester.runAsync(() async {
      goalId = await repo.addSavingsGoal(
        name: '旅行基金',
        target: Decimal.fromInt(3000),
        emoji: '✈️',
      );
      for (final entry in cases) {
        final id = await repo.addPhysicalAsset(
          name: entry.$1,
          currentValue: Decimal.fromInt(300),
          purchasePrice: Decimal.fromInt(500),
          purchaseDate: DateTime.now().subtract(const Duration(days: 30)),
        );
        assetIds.add(id);
        await repo.setPhysicalAssetStatus(
          id: id,
          status: entry.$2,
          occurredAt: DateTime.now(),
        );
      }
    });
    await pumpAccountsView(tester, repo);
    await tester.tap(find.text('物品'));
    await pumpViewAnimations(tester);

    await scrollLastGridTo(tester, find.text(cases.first.$1));
    await tester.tap(find.text(cases.first.$1));
    await pumpViewAnimations(tester);
    await scrollLastListTo(
      tester,
      find.byKey(const Key('physical-asset-savings-goal')),
    );
    await tester.tap(find.byKey(const Key('physical-asset-savings-goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('旅行基金'));
    await tester.runAsync(() async {
      for (var attempt = 0;
          attempt < 100 &&
              repo.physicalAssetDetailById(assetIds.first)!.savingsGoalId !=
                  goalId;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
    expect(
      repo.physicalAssetDetailById(assetIds.first)!.savingsGoalId,
      goalId,
    );
    expect(find.textContaining('已关联：'), findsOneWidget);

    await tester.tap(find.byKey(const Key('physical-asset-savings-goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解除关联'));
    await tester.runAsync(() async {
      for (var attempt = 0;
          attempt < 100 &&
              repo.physicalAssetDetailById(assetIds.first)!.savingsGoalId !=
                  null;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
    expect(
      repo.physicalAssetDetailById(assetIds.first)!.savingsGoalId,
      isNull,
    );
    await openPhysicalAssetMoreMenu(tester);
    // 终止/撤销类操作收进了「更多操作…」二级菜单。
    await tester.tap(find.text('更多操作…'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('撤销结束持有'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('撤销结束持有'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销').last);
    await tester.runAsync(() async {
      for (var attempt = 0;
          attempt < 100 &&
              repo.physicalAssetDetailById(assetIds.first)!.economicStatus !=
                  PhysicalAssetEconomicStatus.owned;
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
    expect(
      repo.physicalAssetDetailById(assetIds.first)!.economicStatus,
      PhysicalAssetEconomicStatus.owned,
    );
    await closePhysicalAssetDetail(tester);

    await tester.runAsync(() async {
      for (final assetId in assetIds.skip(1)) {
        await repo.undoPhysicalAssetTerminalStatus(assetId);
      }
    });
    for (final assetId in assetIds) {
      expect(
        repo.physicalAssetDetailById(assetId)!.economicStatus,
        PhysicalAssetEconomicStatus.owned,
      );
    }
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown reimbursement marks account and net worth as partial',
      (tester) async {
    final repo = AppRepository();
    await tester.runAsync(repo.init);
    addTearDown(() => tester.runAsync(repo.closeForTest));
    final category =
        repo.categoriesForKindRanked(TransactionKind.expense).first;
    final account = repo.accounts.first;
    const originalUuid = '99999999999999999999999999999999';
    await tester.runAsync(() => repo.importFeimiaoExportRows([
          FeimiaoImportRow(
            uuid: originalUuid,
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(100),
            refunded: Decimal.zero,
            categoryKey: category.key,
            accountName: account.name,
            note: '差旅',
            date: DateTime(2026, 6, 1),
          ),
          FeimiaoImportRow(
            uuid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            refundOfUuid: originalUuid,
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(40),
            refunded: Decimal.zero,
            categoryKey: category.key,
            accountName: account.name,
            note: '报销到账',
            date: DateTime(2026, 6, 1),
          ),
        ]));

    await pumpAccountsView(tester, repo);
    expect(find.text('净资产'), findsOneWidget);
    expect(find.text('部分金额待确认'), findsOneWidget);

    // 到账待确认属于数据口径类条目，收进右上 ⋯ 菜单的「数据待完善」弹层。
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.textContaining('数据待完善'), findsOneWidget);
    await tester.tap(find.textContaining('数据待完善'));
    await tester.pumpAndSettle();
    expect(find.textContaining('个账户的到账信息待确认'), findsOneWidget);

    // 点条目 = 关弹层并跳到资金页。
    await tester.tap(find.textContaining('个账户的到账信息待确认'));
    await tester.pumpAndSettle();
    expect(find.textContaining('· 待确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
