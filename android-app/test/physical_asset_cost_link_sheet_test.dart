import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/views/assets/physical_asset_cost_link_sheet.dart';
import 'package:qingji/widgets/app_buttons.dart';

void main() {
  const submitKey = Key('physical-asset-cost-submit');

  Future<void> pumpSheet(
    WidgetTester tester, {
    required PhysicalAssetCostCandidateLoader loadCandidates,
    required PhysicalAssetCostLinkCallback onLink,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PhysicalAssetCostLinkSheet(
          loadCandidates: loadCandidates,
          onLink: onLink,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('搜索选择类型后确认，提交期间不会重复回调', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    int? linkedTransactionId;
    PhysicalAssetCostType? linkedType;
    await pumpSheet(
      tester,
      loadCandidates: () async => [
        PhysicalAssetCostLinkCandidateData(
          transactionId: 11,
          title: '咖啡机维修',
          date: DateTime(2026, 7, 12),
          amountCents: 12800,
          bookName: '家庭账本',
        ),
        PhysicalAssetCostLinkCandidateData(
          transactionId: 12,
          title: '旧配件支出',
          date: DateTime(2026, 7, 11),
          amountCents: 3900,
          bookName: '家庭账本',
          alreadyLinked: true,
        ),
        PhysicalAssetCostLinkCandidateData(
          transactionId: 13,
          title: '相机保险',
          date: DateTime(2026, 7, 10),
          amountCents: 26000,
          bookName: '旅行账本',
        ),
      ],
      onLink: (transactionId, costType) async {
        calls++;
        linkedTransactionId = transactionId;
        linkedType = costType;
        await pending.future;
      },
    );

    expect(
        tester.widget<AppPillButton>(find.byKey(submitKey)).onPressed, isNull);
    await tester.tap(
      find.byKey(const Key('physical-asset-cost-candidate-12')),
    );
    await tester.pump();
    expect(
        tester.widget<AppPillButton>(find.byKey(submitKey)).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('physical-asset-cost-search')),
      '咖啡机',
    );
    await tester.pump();
    expect(find.text('相机保险'), findsNothing);
    expect(find.text('候选支出 · 1'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('physical-asset-cost-candidate-11')),
    );
    await tester.tap(find.text('保险'));
    await tester.pump();

    final submit =
        tester.widget<AppPillButton>(find.byKey(submitKey)).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(calls, 1);
    expect(linkedTransactionId, 11);
    expect(linkedType, PhysicalAssetCostType.insurance);
    expect(find.text('关联中'), findsOneWidget);

    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp 候选列表可滚动且搜索空态不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpSheet(
      tester,
      loadCandidates: () async => [
        for (var i = 1; i <= 12; i++)
          PhysicalAssetCostLinkCandidateData(
            transactionId: i,
            title: '维护支出 $i',
            date: DateTime(2026, 7, i),
            amountCents: i * 100,
            bookName: '日常账本',
          ),
      ],
      onLink: (_, __) async {},
    );

    final list = find.byKey(const Key('physical-asset-cost-list'));
    final scrollable = find.descendant(
      of: list,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    expect(list, findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('维护支出 12'),
      300,
      scrollable: scrollable,
    );
    expect(find.text('维护支出 12'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('physical-asset-cost-search')),
      -300,
      scrollable: scrollable,
    );
    await tester.enterText(
      find.byKey(const Key('physical-asset-cost-search')),
      '不存在的账单',
    );
    await tester.pump();
    expect(find.text('没有匹配的支出'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有候选时显示空态', (tester) async {
    await pumpSheet(
      tester,
      loadCandidates: () async => const [],
      onLink: (_, __) async {},
    );

    expect(find.text('没有可关联的支出'), findsOneWidget);
    expect(find.text('记下一笔支出后，再回来补充物品成本。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
