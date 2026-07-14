import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/export/export_range.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/common/category_picker_sheet.dart';
import 'package:qingji/views/quick_add/category_grid.dart';
import 'package:qingji/views/savings/savings_goals_view.dart';
import 'package:qingji/views/settings/import_export_view.dart';
import 'package:qingji/widgets/app_buttons.dart';
import 'package:qingji/widgets/ios_form.dart';
import 'package:qingji/widgets/settings_ui.dart';

void main() {
  testWidgets('SheetHeader keeps equal edge insets and a centered title',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: SheetHeader(
                title: '表单标题',
                onClose: () {},
                actionLabel: '保存',
                onAction: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final closeRect = tester.getRect(find.byType(AppCircleButton));
    final actionRect = tester.getRect(find.byType(AppPillButton));
    final titleRect = tester.getRect(find.text('表单标题'));
    final title = tester.widget<Text>(find.text('表单标题'));

    expect(closeRect.left, 12);
    expect(closeRect.top, 12);
    expect(actionRect.right, 388);
    expect(titleRect.center.dx, 200);
    expect(title.style?.fontWeight, FontWeight.w500);
  });

  testWidgets('SettingsGroup stretches custom rows to the card width',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: SettingsGroup(
                margin: EdgeInsets.zero,
                children: [
                  SizedBox(key: ValueKey('custom-row'), height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('custom-row'))).width,
      tester.getSize(find.byType(SettingsGroup)).width,
    );
  });

  testWidgets('category picker uses the shared sheet header', (tester) async {
    final repo = AppRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showCategoryPickerSheet(
                  context,
                  kind: TransactionKind.expense,
                  title: '选择支出分类',
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(SheetHeader), findsOneWidget);
    expect(find.byType(HierarchicalCategoryPicker), findsOneWidget);
    expect(find.text('选择支出分类'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.xmark), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('savings goal editor is a labeled half-sheet form',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = AppRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: const MaterialApp(home: SavingsGoalsView()),
      ),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.byType(SheetHeader), findsOneWidget);
    expect(find.text('新建存钱目标'), findsOneWidget);
    expect(find.text('目标名称'), findsOneWidget);
    expect(find.text('目标金额'), findsOneWidget);
    expect(find.text('目标图标'), findsOneWidget);
    expect(find.byType(AppLabeledField), findsNWidgets(3));

    var save = tester.widget<AppPillButton>(find.byType(AppPillButton));
    expect(save.onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(0), '旅行基金');
    await tester.enterText(find.byType(TextField).at(1), '5000');
    await tester.pump();
    save = tester.widget<AppPillButton>(find.byType(AppPillButton));
    expect(save.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export range sheet scrolls to custom range on a short screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 7, 12, 12);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ExportRangePickerSheet(
              options: ExportRange.presets(now),
              defaultStart: DateTime(2026, 7, 1),
              defaultEnd: now,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('自定义'), findsOneWidget);
    expect(tester.getRect(find.text('自定义')).bottom, lessThanOrEqualTo(560));
    expect(tester.takeException(), isNull);
  });

  testWidgets('import and export actions use equal transparent buttons',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ImportExportView()),
    );

    final buttons = find.byType(OutlinedButton);
    expect(buttons, findsNWidgets(2));
    expect(find.text('导出'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    expect(find.text('小贴士'), findsNothing);
    expect(find.textContaining('UTF-8'), findsNothing);
    expect(tester.getSize(buttons.at(0)), tester.getSize(buttons.at(1)));
  });
}
