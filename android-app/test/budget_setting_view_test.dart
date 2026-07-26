import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/budget/budget_period.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/core/statistics/consumption_projection.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/settings/budget_setting_view.dart';
import 'package:qingji/widgets/sliding_segment.dart';

class _ResolverRepo extends AppRepository {
  _ResolverRepo({
    this.periods = const [],
    this.expenseFamilies = const [],
  });

  final List<BudgetPeriod> periods;
  final List<ConsumptionExpenseFamily> expenseFamilies;
  BudgetWindowQuery? lastQuery;
  BudgetWindowResult? lastResult;

  @override
  int get currentBookId => 1;

  @override
  List<BookEntity> get books => const [
        BookEntity(id: 1, name: '日常账本', icon: '📒'),
      ];

  @override
  List<CategoryEntity> get categories => const [
        CategoryEntity(
          id: 1,
          key: 'dining',
          nameZh: '餐饮',
          nameEn: 'Dining',
          kindRaw: 'expense',
        ),
        CategoryEntity(
          id: 2,
          key: 'shopping',
          nameZh: '购物',
          nameEn: 'Shopping',
          kindRaw: 'expense',
        ),
      ];

  // The management list is outside these execution-card tests. Keeping it
  // empty prevents duplicate amount labels from obscuring status assertions.
  @override
  List<BudgetPeriod> get budgetPeriods => const [];

  @override
  BudgetWindowResult budgetWindow(BudgetWindowQuery query) {
    lastQuery = query;
    return lastResult = BudgetWindowResolver.resolve(
      query: query,
      periods: periods,
      expenseFamilies: expenseFamilies,
    );
  }
}

BudgetPeriod _monthlyPlan({
  String total = '3100',
  Map<String, Decimal> categories = const {},
  int? bookId = 1,
}) =>
    BudgetPeriod(
      id: 1,
      bookId: bookId,
      start: DateTime(2000, 1, 1),
      total: Decimal.parse(total),
      categoryBudgets: categories,
    );

ConsumptionExpenseFamily _expense({
  required String id,
  required DateTime date,
  required int cents,
  String currency = 'CNY',
  String categoryKey = 'dining',
}) =>
    ConsumptionExpenseFamily(
      id: id,
      bookId: 1,
      currencyCode: currency,
      attributionDate: date,
      createdAt: date,
      originalAmountMinor: cents,
      categoryAllocations: [
        ConsumptionCategoryAllocation(
          categoryKey: categoryKey,
          categoryName: categoryKey,
          amountMinor: cents,
        ),
      ],
    );

String _categoryAmountText(BudgetCategoryResult result) =>
    '${MoneyFormat.string(result.spentAmount)} / '
    '${MoneyFormat.string(result.plannedAmount)}';

Finder _textExactly(String value) => find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      return text == value;
    });

void main() {
  Future<AppRepository> pumpBudgetPage(
    WidgetTester tester, {
    Size size = const Size(320, 800),
    AppRepository? repository,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = repository ?? _ResolverRepo();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: const MaterialApp(home: BudgetSettingView()),
      ),
    );
    await tester.pump();
    return repo;
  }

  testWidgets('browse book, four windows, and date navigation stay separate',
      (tester) async {
    await pumpBudgetPage(tester);

    expect(find.byKey(const ValueKey('budget-book-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-window-segment')), findsOneWidget);
    expect(find.text('查看账本'), findsOneWidget);
    expect(find.text('本周期'), findsWidgets);
    expect(find.text('月'), findsOneWidget);
    expect(find.text('周'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);

    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    final before = tester.widget<Text>(
      find.byKey(const ValueKey('budget-window-label')),
    );
    expect(before.data, contains('月'));

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    final after = tester.widget<Text>(
      find.byKey(const ValueKey('budget-window-label')),
    );
    expect(after.data, isNot(before.data));
    expect(tester.takeException(), isNull);
  });

  testWidgets('new V2 editor separates cadence from browse windows',
      (tester) async {
    await pumpBudgetPage(tester, size: const Size(360, 760));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常预算'));
    await tester.pumpAndSettle();

    expect(find.text('新建预算'), findsOneWidget);
    expect(find.text('每月'), findsOneWidget);
    expect(find.text('每周'), findsOneWidget);
    expect(find.text('下周期生效'), findsOneWidget);
    expect(find.text('本周期生效'), findsOneWidget);
    expect(
      tester
          .widget<SlidingSegment<bool>>(
            find.byKey(const ValueKey('budget-start-cycle-segment')),
          )
          .value,
      isFalse,
    );
    expect(find.text('一次性期间（旧模式）'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add menu opens the independent special tracking form',
      (tester) async {
    await pumpBudgetPage(tester, size: const Size(360, 760));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('专项追踪'));
    await tester.pumpAndSettle();

    expect(find.text('新建专项追踪'), findsOneWidget);
    expect(find.text('专项只观察所选支出，不增加日常可花额度'), findsOneWidget);
    expect(find.text('固定支出'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no plan keeps real window spending without fake budget values',
      (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final repo = _ResolverRepo(
      expenseFamilies: [
        _expense(id: 'meal', date: today, cents: 12345),
      ],
    );

    await pumpBudgetPage(tester, repository: repo);

    expect(find.text('这段时间还没有日常预算，可用右上角 + 新建计划。'), findsOneWidget);
    expect(
      _textExactly(
        '已发生支出 ${MoneyFormat.string(Decimal.parse('123.45'))}',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('剩余 '), findsNothing);
    expect(find.textContaining('预算进度'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('available result drives totals, daily reference, and categories',
      (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final repo = _ResolverRepo(
      periods: [
        _monthlyPlan(
          categories: {'dining': Decimal.fromInt(620)},
        ),
      ],
      expenseFamilies: [
        _expense(id: 'meal', date: today, cents: 20000),
      ],
    );

    await pumpBudgetPage(tester, repository: repo);
    final result = repo.lastResult!;
    final dining = result.categoryResults.singleWhere(
      (item) => item.categoryKey == 'dining',
    );

    expect(find.text('本周期预算'), findsOneWidget);
    expect(
      find.text('剩余 ${MoneyFormat.string(result.remainingAmount!)}'),
      findsOneWidget,
    );
    expect(find.textContaining('剩余预算日均参考'), findsOneWidget);
    expect(find.text('分类执行'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text(_categoryAmountText(dining)), findsOneWidget);
    expect(find.textContaining('预算进度'), findsOneWidget);
  });

  testWidgets('partial CNY result stays visible and explains exclusions',
      (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final repo = _ResolverRepo(
      periods: [_monthlyPlan(total: '1000')],
      expenseFamilies: [
        _expense(id: 'cny', date: today, cents: 2000),
        _expense(
          id: 'usd',
          date: today,
          cents: 3000,
          currency: 'USD',
        ),
      ],
    );

    await pumpBudgetPage(tester, repository: repo);
    final result = repo.lastResult!;

    expect(
      find.text('剩余 ${MoneyFormat.string(result.remainingAmount!)}'),
      findsOneWidget,
    );
    expect(find.textContaining('已排除 1 笔非 CNY 支出'), findsOneWidget);
    expect(find.text('分类执行'), findsOneWidget);
  });

  testWidgets('conflicting plan hides false remaining and category execution',
      (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final repo = _ResolverRepo(
      periods: [
        _monthlyPlan(
          total: '100',
          categories: {
            'dining': Decimal.fromInt(80),
            'shopping': Decimal.fromInt(30),
          },
        ),
      ],
      expenseFamilies: [
        _expense(id: 'meal', date: today, cents: 1500),
      ],
    );

    await pumpBudgetPage(tester, repository: repo);

    expect(find.text('预算计划有冲突'), findsOneWidget);
    expect(find.textContaining('不展示伪精确剩余'), findsOneWidget);
    expect(
      _textExactly(
        '已发生支出 ${MoneyFormat.string(Decimal.fromInt(15))}',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('剩余 '), findsNothing);
    expect(find.textContaining('预算进度'), findsNothing);
    expect(find.text('分类执行'), findsNothing);
  });

  testWidgets('historical month and week use their own resolver windows',
      (tester) async {
    final repo = _ResolverRepo(periods: [_monthlyPlan()]);
    await pumpBudgetPage(tester, repository: repo);

    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    final monthReference = repo.lastQuery!.referenceDate;
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    final previousMonthReference = repo.lastQuery!.referenceDate;

    expect(repo.lastQuery!.viewKind, BudgetViewKind.calendarMonth);
    expect(
      previousMonthReference,
      DateTime(monthReference.year, monthReference.month - 1),
    );
    expect(find.text('自然月预算'), findsOneWidget);

    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    final weekReference = repo.lastQuery!.referenceDate;
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(repo.lastQuery!.viewKind, BudgetViewKind.calendarWeek);
    expect(
      repo.lastQuery!.referenceDate,
      weekReference.subtract(const Duration(days: 7)),
    );
    expect(find.text('本周参考额度'), findsOneWidget);
  });

  testWidgets('cycle arrows follow resolver-provided adjacent cycles',
      (tester) async {
    final repo = _ResolverRepo(periods: [_monthlyPlan()]);
    await pumpBudgetPage(tester, repository: repo);
    final initial = repo.lastResult!;

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(
      repo.lastQuery!.referenceDate,
      initial.previousCycleWindow!.startInclusive,
    );
    final previous = repo.lastResult!;

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(
      repo.lastQuery!.referenceDate,
      previous.nextCycleWindow!.startInclusive,
    );
  });

  testWidgets('category row changes from whole month to whole week values',
      (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final repo = _ResolverRepo(
      periods: [
        _monthlyPlan(
          categories: {'dining': Decimal.fromInt(620)},
        ),
      ],
      expenseFamilies: [
        _expense(id: 'meal', date: today, cents: 2000),
      ],
    );
    await pumpBudgetPage(tester, repository: repo);

    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    final monthDining = repo.lastResult!.categoryResults.singleWhere(
      (item) => item.categoryKey == 'dining',
    );
    final monthText = _categoryAmountText(monthDining);
    expect(find.text(monthText), findsOneWidget);

    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    final weekDining = repo.lastResult!.categoryResults.singleWhere(
      (item) => item.categoryKey == 'dining',
    );
    final weekText = _categoryAmountText(weekDining);

    expect(weekText, isNot(monthText));
    expect(find.text(weekText), findsOneWidget);
    expect(find.text(monthText), findsNothing);
  });

  testWidgets('B1 execution card omits deferred reserve terminology',
      (tester) async {
    final repo = _ResolverRepo(periods: [_monthlyPlan()]);
    await pumpBudgetPage(tester, repository: repo);

    expect(find.textContaining('固定支出预留'), findsNothing);
    expect(find.textContaining('安全可花'), findsNothing);
    expect(find.textContaining('可自由安排'), findsNothing);
  });
}
