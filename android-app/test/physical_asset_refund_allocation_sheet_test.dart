import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/views/assets/physical_asset_refund_allocation_sheet.dart';
import 'package:qingji/widgets/app_buttons.dart';

void main() {
  final pending = PhysicalAssetRefundAllocationData(
    refundTransactionId: 88,
    refundCents: 4000,
    occurredAt: DateTime(2026, 7, 13),
    orderLabel: '桌面设备组合订单',
    targets: [
      const PhysicalAssetRefundAllocationTargetData(
        assetId: 1,
        assetName: '机械键盘',
        grossCents: 6000,
        totalAllocatedRefundCents: 1000,
      ),
      const PhysicalAssetRefundAllocationTargetData(
        assetId: 2,
        assetName: '无线鼠标',
        grossCents: 4000,
        totalAllocatedRefundCents: 0,
      ),
    ],
  );

  Future<void> pumpSheet(
    WidgetTester tester, {
    required PhysicalAssetRefundAllocationLoader load,
    required PhysicalAssetRefundAllocationSubmitter submit,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PhysicalAssetRefundAllocationSheet(
          load: load,
          submit: submit,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('退款金额必须完整且不超物品上限才能提交', (tester) async {
    Map<int, int>? submitted;
    var completed = false;
    var loadCount = 0;
    await pumpSheet(
      tester,
      load: () async {
        loadCount++;
        return completed ? const [] : [pending];
      },
      submit: (refundId, allocations, untracked) async {
        expect(refundId, 88);
        expect(untracked, 0);
        submitted = allocations;
        completed = true;
      },
    );

    final submitFinder = find.byKey(const Key('asset-refund-submit-88'));
    expect(tester.widget<AppPillButton>(submitFinder).onPressed, isNull);
    expect(find.text('还需分配 ¥40.00'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('asset-refund-input-88-1')),
      '51',
    );
    await tester.pump();
    expect(find.textContaining('不能超过可分配上限'), findsOneWidget);
    expect(tester.widget<AppPillButton>(submitFinder).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('asset-refund-input-88-1')),
      '30',
    );
    await tester.enterText(
      find.byKey(const Key('asset-refund-input-88-2')),
      '10',
    );
    await tester.pump();
    expect(find.text('合计 ¥40.00，可以确认'), findsOneWidget);
    expect(tester.widget<AppPillButton>(submitFinder).onPressed, isNotNull);

    final submit = tester.widget<AppPillButton>(submitFinder).onPressed!;
    await tester.runAsync(() async {
      submit();
      for (var attempt = 0;
          attempt < 50 && (!completed || loadCount < 2);
          attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(submitted, {1: 3000, 2: 1000});
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('退款可以部分归到订单未跟踪部分，超上限不能提交', (tester) async {
    // 订单 ¥100：跟踪物品毛额 ¥60、未跟踪部分 ¥40；本次退款 ¥50。
    final withUntracked = PhysicalAssetRefundAllocationData(
      refundTransactionId: 99,
      refundCents: 5000,
      occurredAt: DateTime(2026, 7, 20),
      orderLabel: '含未跟踪配件的订单',
      untrackedLimitCents: 4000,
      targets: const [
        PhysicalAssetRefundAllocationTargetData(
          assetId: 1,
          assetName: '机械键盘',
          grossCents: 6000,
          totalAllocatedRefundCents: 0,
        ),
      ],
    );
    Map<int, int>? submitted;
    int? submittedUntracked;
    var completed = false;
    await pumpSheet(
      tester,
      load: () async => completed ? const [] : [withUntracked],
      submit: (refundId, allocations, untracked) async {
        expect(refundId, 99);
        submitted = allocations;
        submittedUntracked = untracked;
        completed = true;
      },
    );

    expect(find.text('不属于已跟踪物品'), findsOneWidget);
    final submitFinder = find.byKey(const Key('asset-refund-submit-99'));

    // 未跟踪归属超过上限（¥45 > ¥40）→ 不能提交。
    await tester.enterText(
      find.byKey(const Key('asset-refund-input-99-1')),
      '10',
    );
    await tester.enterText(
      find.byKey(const Key('asset-refund-untracked-99')),
      '45',
    );
    await tester.pump();
    expect(tester.widget<AppPillButton>(submitFinder).onPressed, isNull);

    // 物品 ¥10 + 未跟踪 ¥40 = 退款 ¥50 → 可提交。
    await tester.enterText(
      find.byKey(const Key('asset-refund-untracked-99')),
      '40',
    );
    await tester.pump();
    expect(find.text('合计 ¥50.00，可以确认'), findsOneWidget);
    final submit = tester.widget<AppPillButton>(submitFinder).onPressed!;
    await tester.runAsync(() async {
      submit();
      for (var attempt = 0; attempt < 50 && !completed; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(submitted, {1: 1000});
    expect(submittedUntracked, 4000);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp 单列布局可滚动且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpSheet(
      tester,
      load: () async => [pending],
      submit: (_, __, ___) async {},
    );

    expect(
        find.byKey(const Key('asset-refund-allocation-list')), findsOneWidget);
    expect(find.text('机械键盘'), findsOneWidget);
    expect(find.text('无线鼠标'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
