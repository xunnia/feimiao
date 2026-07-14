import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_special_tracking.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/views/settings/budget_special_tracking_ui.dart';

const _books = [
  BudgetSpecialBookOption(id: 1, name: '总账本', icon: '📒'),
  BudgetSpecialBookOption(id: 2, name: '旅行账本', icon: '🧳'),
];

const _categories = [
  BudgetSpecialCategoryOption(key: 'travel', name: '旅行', icon: '✈️'),
  BudgetSpecialCategoryOption(key: 'dining', name: '餐饮', icon: '🍜'),
];

const _tags = [
  BudgetSpecialTagOption(id: 7, name: '年度计划', colorValue: 0xFF8C7A5B),
];

void main() {
  setUp(MoneyFormat.resetConfig);

  Future<void> pumpSheet(
    WidgetTester tester, {
    BudgetSpecialTrackingDraft? draft,
    required BudgetSpecialTrackingSaveCallback onSave,
    Size size = const Size(360, 780),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BudgetSpecialTrackingSheet(
            books: _books,
            categories: _categories,
            tags: _tags,
            initialDraft: draft,
            onSave: onSave,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('new tracker requires scope and emits an integer-cent command',
      (tester) async {
    BudgetSpecialTrackingSaveCommand? saved;
    await pumpSheet(
      tester,
      onSave: (command) => saved = command,
      size: const Size(360, 1400),
    );

    expect(find.text('新建专项追踪'), findsOneWidget);
    expect(find.textContaining('不增加日常可花额度'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('budget-special-save')));
    await tester.pump();
    expect(find.text('请填写专项追踪名称'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('budget-special-name')),
      '国庆旅行',
    );
    await tester.enterText(
      find.byKey(const ValueKey('budget-special-total')),
      '5000.25',
    );
    final category =
        find.byKey(const ValueKey('budget-special-category-travel'));
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('budget-special-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.isEdit, isFalse);
    expect(saved!.name, '国庆旅行');
    expect(saved!.bookId, 1);
    expect(saved!.totalCents, 500025);
    expect(saved!.categoryKeys, {'travel'});
    expect(saved!.tagIds, isEmpty);
    expect(saved!.expenseScope.matches(categoryKey: 'travel'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit tracker restores dates, book, amount, and tag scope',
      (tester) async {
    BudgetSpecialTrackingSaveCommand? saved;
    await pumpSheet(
      tester,
      draft: BudgetSpecialTrackingDraft(
        planId: 42,
        name: '装修追踪',
        startInclusive: DateTime(2026, 8, 1),
        endInclusive: DateTime(2026, 9, 30),
        totalCents: 3000000,
        bookId: 2,
        tagIds: const [7],
      ),
      onSave: (command) => saved = command,
    );

    expect(find.text('编辑专项追踪'), findsOneWidget);
    expect(find.text('2026/8/1 - 2026/9/30'), findsOneWidget);
    expect(find.text('🧳 旅行账本'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('budget-special-name')),
          )
          .controller!
          .text,
      '装修追踪',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('budget-special-total')),
          )
          .controller!
          .text,
      '30000.00',
    );

    await tester.tap(find.byKey(const ValueKey('budget-special-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.planId, 42);
    expect(saved!.isEdit, isTrue);
    expect(saved!.bookId, 2);
    expect(saved!.tagIds, {7});
    expect(saved!.expenseScope.matches(familyTagIds: const [7]), isTrue);
  });

  testWidgets('single execution card shows no aggregate and exposes actions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var edited = false;
    var archived = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: BudgetSpecialTrackingCard(
              name: '国庆旅行',
              startInclusive: DateTime(2026, 10, 1),
              endInclusive: DateTime(2026, 10, 7),
              totalCents: 500000,
              spentCents: 600000,
              scopeSummary: '旅行、年度计划',
              lifecycleStatus: BudgetSpecialLifecycleStatus.inProgress,
              onEdit: () => edited = true,
              onArchive: () => archived = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('国庆旅行'), findsOneWidget);
    expect(find.text('已超支'), findsOneWidget);
    expect(find.text('已用 ¥6,000.00 / ¥5,000.00'), findsOneWidget);
    expect(find.text('已超出 ¥1,000.00'), findsOneWidget);
    expect(find.text('旅行、年度计划'), findsOneWidget);
    expect(find.textContaining('专项合计'), findsNothing);
    expect(find.textContaining('专项总额'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.tap(find.byIcon(Icons.archive_outlined));
    expect(edited, isTrue);
    expect(archived, isTrue);
  });
}
