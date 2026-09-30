// 预算页显示文字（docs/08 §6.7–§6.9）：规则时间说明、节奏、保存前预览、改日常提示。
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_rule_display.dart';
import 'package:qingji/core/budget/budget_rule_engine.dart';
import 'package:qingji/core/budget/budget_rules.dart';

BudgetRule _base(int id, int yuan, DateTime start,
        {BudgetRuleUnit unit = BudgetRuleUnit.month}) =>
    BudgetRule(
      id: id,
      bookId: 1,
      kind: BudgetRuleKind.base,
      amountCents: yuan * 100,
      unit: unit,
      startDate: start,
      createdMs: id,
    );

BudgetRule _special(
  int id,
  int yuan,
  DateTime start,
  DateTime end, {
  String name = '',
  BudgetRuleUnit unit = BudgetRuleUnit.day,
  BudgetFunding funding = BudgetFunding.carve,
}) =>
    BudgetRule(
      id: id,
      bookId: 1,
      kind: BudgetRuleKind.special,
      name: name,
      amountCents: yuan * 100,
      unit: unit,
      startDate: start,
      endDate: end,
      funding: funding,
      createdMs: id,
    );

void main() {
  final today = DateTime(2026, 9, 18);

  test('金额千分位、单位和默认名称', () {
    expect(budgetYuanText(400000), '¥4,000');
    expect(budgetYuanText(123456789), '¥1,234,567');
    expect(budgetYuanText(-12000), '-¥120');
    expect(budgetLeftDisplayCents(-500), 0);
    expect(budgetLeftDisplayCents(184099), 184000);
    final base = _base(1, 4000, DateTime(2026, 9, 1));
    expect(budgetRuleAmountText(base), '每月 ¥4,000');
    expect(budgetRuleName(base), '日常');
    expect(
      budgetRuleName(_special(2, 300, today, today)),
      '特别安排',
    );
  });

  test('规则时间：特别安排按日期，日常预算被接走后显示起止月', () {
    final may = _base(1, 5000, DateTime(2026, 5, 1));
    final oct = _base(2, 6000, DateTime(2026, 10, 1));
    final rules = [may, oct];
    expect(budgetRuleSpan(may, rules, today).text, '5月起');
    expect(budgetRuleSpan(may, rules, today).state, BudgetRuleState.active);
    expect(budgetRuleSpan(oct, rules, today).state, BudgetRuleState.upcoming);

    final nov = DateTime(2026, 11, 2);
    final ended = budgetRuleSpan(may, rules, nov);
    expect(ended.state, BudgetRuleState.ended);
    expect(ended.text, '5月–9月');

    final festival = _special(3, 300, DateTime(2026, 9, 25), DateTime(2026, 9, 27));
    expect(budgetRuleSpan(festival, rules, today).text, '9月25日–27日');
    expect(budgetRuleSpan(festival, rules, today).state, BudgetRuleState.upcoming);
    expect(
      budgetRuleSpan(festival, rules, DateTime(2026, 9, 28)).state,
      BudgetRuleState.ended,
    );
    expect(
      budgetRulesNewestFirst(rules..add(festival)).map((r) => r.id),
      [3, 2, 1],
    );
  });

  test('节奏一句话：少花 / 多花 / 只剩不到一成', () {
    BudgetMonthResult month(int spentBeforeToday) =>
        BudgetRuleEngine.resolveMonth(
          rules: [_base(1, 3000, DateTime(2026, 9, 1))],
          spendByDay: {20260910: spentBeforeToday},
          year: 2026,
          month: 9,
          today: today,
        );
    // 9/1–9/17 按计划应花 1,700。
    expect(budgetPaceText(month(150000)).text, '比计划少花 ¥200 · 节奏不错');
    expect(budgetPaceText(month(150000)).warning, isFalse);
    expect(budgetPaceText(month(180000)).text, '比计划多花 ¥100');
    expect(budgetPaceText(month(180000)).warning, isTrue);
    expect(budgetPaceText(month(280000)).text, '只剩 ¥200 啦');
    expect(budgetPaceText(month(310000)).text, '这个月已经超出预算啦');
  });

  test('预览：中秋从 9 月预算里匀（§6.5 例）', () {
    final base = _base(1, 4000, DateTime(2026, 9, 1));
    final festival = _special(
      0,
      300,
      DateTime(2026, 9, 25),
      DateTime(2026, 9, 27),
      name: '中秋',
    );
    final lines = budgetRulePreview(
      existing: [base],
      candidate: BudgetRule(
        id: 0,
        bookId: 1,
        kind: festival.kind,
        name: festival.name,
        amountCents: festival.amountCents,
        unit: festival.unit,
        startDate: festival.startDate,
        endDate: festival.endDate,
        funding: festival.funding,
        createdMs: 99,
      ),
      today: today,
    ).map((l) => l.text).toList();
    expect(lines, [
      '这 3 天一共 ¥900，每天约 ¥300',
      '9月一共还是 ¥4,000，其余日子每天约 ¥115',
    ]);
  });

  test('预览：额外多给月总额变大；匀超了给出警示', () {
    final base = _base(1, 8000, DateTime(2026, 10, 1));
    final extra = _special(
      9,
      2000,
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 7),
      unit: BudgetRuleUnit.week,
      funding: BudgetFunding.extra,
    );
    final lines = budgetRulePreview(
      existing: [base],
      candidate: extra,
      today: today,
    ).map((l) => l.text).toList();
    expect(lines[0], '这 7 天一共 ¥2,000，每天约 ¥286');
    expect(lines[1], startsWith('10月一共 ¥10,000（多了 ¥2,000）'));

    final tooBig = budgetRulePreview(
      existing: [base],
      candidate: _special(9, 9000, DateTime(2026, 10, 1), DateTime(2026, 10, 1)),
      today: today,
    );
    expect(tooBig.last.warning, isTrue);
    expect(tooBig.last.text, contains('比10月整月预算还多'));
  });

  test('预览：会盖掉之前那条特别安排的重叠日子', () {
    final base = _base(1, 4000, DateTime(2026, 9, 1));
    final trip = _special(2, 200, DateTime(2026, 9, 20), DateTime(2026, 9, 26), name: '旅行');
    final lines = budgetRulePreview(
      existing: [base, trip],
      candidate: _special(3, 300, DateTime(2026, 9, 25), DateTime(2026, 9, 27), name: '中秋'),
      today: today,
    ).map((l) => l.text);
    expect(lines, contains('会盖掉「旅行」的 9月25日–26日'));
  });

  test('改日常预算的金额或单位才提示重算', () {
    final base = _base(1, 5000, DateTime(2026, 5, 1));
    expect(
      budgetBaseEditWarning(
        original: base,
        amountCents: 500000,
        unit: BudgetRuleUnit.month,
        today: today,
      ),
      isNull,
    );
    expect(
      budgetBaseEditWarning(
        original: base,
        amountCents: 600000,
        unit: BudgetRuleUnit.month,
        today: today,
      ),
      '5月以来的每个月都会按新金额重新计算',
    );
    expect(
      budgetBaseEditWarning(
        original: null,
        amountCents: 600000,
        unit: BudgetRuleUnit.week,
        today: today,
      ),
      isNull,
    );
  });
}
