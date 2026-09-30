// 预算页（docs/08 §6.8–§6.9）：大数字卡、日历、规则列表、月底结余、新增弹层、某一天详情。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/budget/budget_rule_engine.dart';
import 'package:qingji/core/budget/budget_rule_status.dart';
import 'package:qingji/core/budget/budget_rules.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/budget/budget_view.dart';

class _FakeRepo extends AppRepository {
  _FakeRepo({List<BudgetRule>? rules, Map<int, int>? spend})
      : rules = rules ?? [],
        spend = spend ?? {};

  final List<BudgetRule> rules;
  final Map<int, int> spend;
  BudgetRolloverMode mode = BudgetRolloverMode.reset;
  final saved = <({BudgetRuleKind kind, int amountYuan, BudgetFunding funding})>[];

  @override
  int get currentBookId => 1;

  @override
  List<BookEntity> get books => const [
        BookEntity(id: 1, name: '日常账本', icon: '📒'),
      ];

  @override
  List<BudgetRule> budgetRulesForBook(int bookId) => List.unmodifiable(rules);

  @override
  Map<int, int> budgetSpendByDay(int bookId, {DateTime? asOf}) => spend;

  @override
  BudgetRolloverMode budgetRolloverModeFor(
    int bookId, {
    required int year,
    required int month,
  }) =>
      mode;

  @override
  Future<void> setBudgetRolloverMode(int bookId, BudgetRolloverMode mode) async {
    this.mode = mode;
    notifyListeners();
  }

  @override
  BudgetRuleSnapshot budgetRuleMonth(
    DateTime month, {
    int? bookId,
    DateTime? asOf,
  }) =>
      BudgetRuleSnapshot(
        bookId: 1,
        month: BudgetRuleEngine.resolveMonth(
          rules: rules,
          spendByDay: spend,
          year: month.year,
          month: month.month,
          today: budgetDay(asOf ?? DateTime.now()),
        ),
      );

  @override
  List<TransactionRecord> recordsForBookView(int bookId) => const [];

  @override
  List<TransactionEntity> visibleTransactionsForBookView(int bookId) => const [];

  @override
  Future<int> saveBudgetRule({
    int? id,
    required int bookId,
    required BudgetRuleKind kind,
    String name = '',
    required int amountYuan,
    required BudgetRuleUnit unit,
    DateTime? startDate,
    DateTime? endDate,
    BudgetFunding funding = BudgetFunding.carve,
  }) async {
    saved.add((kind: kind, amountYuan: amountYuan, funding: funding));
    final now = DateTime.now();
    rules.add(BudgetRule(
      id: rules.length + 1,
      bookId: bookId,
      kind: kind,
      name: name,
      amountCents: amountYuan * 100,
      unit: unit,
      startDate: startDate ?? DateTime(now.year, now.month),
      endDate: endDate,
      funding: kind == BudgetRuleKind.special ? funding : null,
      createdMs: now.millisecondsSinceEpoch,
    ));
    notifyListeners();
    return rules.length;
  }
}

Finder _textContaining(String value) => find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      return text.contains(value);
    });

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monthStart = DateTime(now.year, now.month);

  Future<_FakeRepo> pump(WidgetTester tester, _FakeRepo repo) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: const MaterialApp(home: BudgetView()),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  BudgetRule base(int yuan) => BudgetRule(
        id: 1,
        bookId: 1,
        kind: BudgetRuleKind.base,
        amountCents: yuan * 100,
        unit: BudgetRuleUnit.month,
        startDate: monthStart,
        createdMs: 1,
      );

  testWidgets('没有规则：给这个月定个小目标 + 设个预算', (tester) async {
    await pump(tester, _FakeRepo());
    expect(find.text('给这个月定个小目标吧'), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-hero-create')), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-calendar-card')), findsOneWidget);
    expect(find.text('月底结余'), findsOneWidget);
    expect(find.text('每月重新开始'), findsOneWidget);
  });

  testWidgets('有日常预算：大数字、今天约、规则行', (tester) async {
    await pump(tester, _FakeRepo(rules: [base(3000)]));
    expect(find.text('${now.month}月还能花'), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-hero-amount')), findsOneWidget);
    expect(find.text('¥3,000'), findsOneWidget);
    expect(_textContaining('今天约 ¥'), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-rule-row-1')), findsOneWidget);
    expect(find.text('日常'), findsOneWidget);
    expect(_textContaining('每月 ¥3,000 · ${now.month}月起'), findsOneWidget);
    // 只有日常预算时不显示特别安排重叠说明。
    expect(find.text('日期重叠时，以后加的特别安排为准'), findsNothing);
  });

  testWidgets('超了：大字改写「X月超出」，橙色', (tester) async {
    await pump(
      tester,
      _FakeRepo(rules: [base(100)], spend: {budgetDayKey(today): 15000}),
    );
    expect(find.text('${now.month}月超出'), findsOneWidget);
    expect(find.text('¥50'), findsOneWidget);
    expect(find.text('今天多花了 ¥50 · 还剩 ${budgetDaysInMonth(now.year, now.month) - now.day + 1} 天'),
        findsOneWidget);
  });

  testWidgets('新增日常预算：填金额保存', (tester) async {
    final repo = await pump(tester, _FakeRepo());
    await tester.tap(find.byKey(const ValueKey('budget-add-rule')));
    await tester.pumpAndSettle();
    expect(find.text('新增预算'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('budget-rule-amount')),
      '4000',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('budget-rule-preview')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('budget-rule-save')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(repo.saved.single.kind, BudgetRuleKind.base);
    expect(repo.saved.single.amountYuan, 4000);
    expect(find.text('新增预算'), findsNothing);
  });

  testWidgets('选日期：没有日常预算时只能额外多给', (tester) async {
    final repo = await pump(tester, _FakeRepo());
    await tester.tap(find.byKey(const ValueKey('budget-add-rule')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选日期'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('budget-rule-range-calendar')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('budget-rule-amount')), '300');
    final day = DateTime(now.year, now.month, 1);
    await tester.tap(find.byKey(ValueKey('budget-range-day-${budgetDayKey(day)}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('budget-rule-extra-only')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('budget-rule-save')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(repo.saved.single.kind, BudgetRuleKind.special);
    expect(repo.saved.single.funding, BudgetFunding.extra);
  });

  testWidgets('月底结余：三选一，每项带例子', (tester) async {
    final repo = await pump(tester, _FakeRepo(rules: [base(3000)]));
    await tester.tap(find.byKey(const ValueKey('budget-rollover-row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('budget-rollover-keep')), findsOneWidget);
    expect(_textContaining('比如'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('budget-rollover-carry')));
    await tester.pumpAndSettle();
    expect(repo.mode, BudgetRolloverMode.carryBoth);
    expect(find.text('多退少补'), findsOneWidget);
  });

  testWidgets('点日历某一天：当天预算 / 花了 / 超了', (tester) async {
    await pump(
      tester,
      _FakeRepo(rules: [base(100)], spend: {budgetDayKey(today): 15000}),
    );
    await tester.tap(find.byKey(ValueKey('budget-day-${budgetDayKey(today)}')));
    await tester.pumpAndSettle();
    expect(find.text('当天预算'), findsOneWidget);
    expect(find.text('花了'), findsOneWidget);
    expect(find.text('超了'), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-day-tip')), findsOneWidget);
    expect(_textContaining('归日常预算管'), findsOneWidget);
  });
}
