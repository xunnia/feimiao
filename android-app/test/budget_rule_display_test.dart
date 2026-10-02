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

    final festival =
        _special(3, 300, DateTime(2026, 9, 25), DateTime(2026, 9, 27));
    expect(budgetRuleSpan(festival, rules, today).text, '9月25日–27日');
    expect(
        budgetRuleSpan(festival, rules, today).state, BudgetRuleState.upcoming);
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

  test('节奏：预算第一天到昨天还没有计划，不显示；只剩不到一成仍提示', () {
    final first = DateTime(2026, 9, 1);
    BudgetMonthResult month(int spentToday) => BudgetRuleEngine.resolveMonth(
          rules: [_base(1, 3000, first)],
          spendByDay: {20260901: spentToday},
          year: 2026,
          month: 9,
          today: first,
        );
    // 第一天当天就超了：不再说「比计划少花 ¥0 · 节奏不错」。
    expect(budgetPaceText(month(20000)).text, isEmpty);
    expect(budgetPaceText(month(0)).text, isEmpty);
    // 余额提示与节奏无关，照样出。
    expect(budgetPaceText(month(280000)).text, '只剩 ¥200 啦');
    expect(budgetPaceText(month(280000)).warning, isTrue);
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
      candidate:
          _special(9, 9000, DateTime(2026, 10, 1), DateTime(2026, 10, 1)),
      today: today,
    );
    expect(tooBig.last.warning, isTrue);
    expect(tooBig.last.text, contains('比10月整月预算还多'));
  });

  test('预览：会盖掉之前那条特别安排的重叠日子', () {
    final base = _base(1, 4000, DateTime(2026, 9, 1));
    final trip = _special(2, 200, DateTime(2026, 9, 20), DateTime(2026, 9, 26),
        name: '旅行');
    final lines = budgetRulePreview(
      existing: [base, trip],
      candidate: _special(3, 300, DateTime(2026, 9, 25), DateTime(2026, 9, 27),
          name: '中秋'),
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
      '这次修改会调整5月以来的预算，已记录的账单不变。',
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

  test('历史编辑只提醒实际负责月份，不包含接替后的月份', () {
    final may = _base(1, 5000, DateTime(2026, 5, 1));
    final oct = _base(2, 6000, DateTime(2026, 10, 1));
    final rules = [may, oct];
    expect(
        budgetBaseEditWarning(
          original: may,
          existing: rules,
          amountCents: 520000,
          unit: BudgetRuleUnit.month,
          today: DateTime(2026, 10, 2),
        ),
        '这次修改会调整5月–9月的预算，已记录的账单不变。');
    final preview = budgetRulePreview(
      existing: rules,
      candidate: _base(1, 5200, may.startDate),
      today: DateTime(2026, 10, 2),
    );
    expect(preview.first.text, '9月预算 ¥5,000 → ¥5,200');
  });

  test('跨年范围带年；同月被接替从未生效的规则不误报历史影响', () {
    final old = _base(1, 5000, DateTime(2025, 12, 1));
    final takeover = _base(2, 6000, DateTime(2026, 2, 1));
    expect(
        budgetBaseEditWarning(
          original: old,
          existing: [old, takeover],
          amountCents: 520000,
          unit: BudgetRuleUnit.month,
          today: today,
        ),
        '这次修改会调整2025年12月–2026年1月的预算，已记录的账单不变。');
    final replacement = _base(2, 6000, old.startDate);
    expect(
        budgetBaseEditWarning(
          original: old,
          existing: [old, replacement],
          amountCents: 520000,
          unit: BudgetRuleUnit.month,
          today: today,
        ),
        isNull);
    expect(
        budgetRulePreview(
          existing: [old, replacement],
          candidate: _base(1, 5200, old.startDate),
          today: today,
        ).single.text,
        '这条日常预算没有生效过，修改后仍不影响任何月份');
  });

  test('整月特别安排临时覆盖：3000变1000，预览明确少了2000', () {
    final base = _base(1, 3000, DateTime(2026, 9, 1));
    final special = _special(
        2, 1000, DateTime(2026, 9, 1), DateTime(2026, 9, 30),
        unit: BudgetRuleUnit.month);
    final month = BudgetRuleEngine.resolveMonth(
      rules: [base, special],
      spendByDay: const {},
      year: 2026,
      month: 9,
      today: today,
    );
    expect(month.budgetCents, 100000);
    expect(
        BudgetRuleEngine.resolveMonth(
          rules: [base, special],
          spendByDay: const {},
          year: 2026,
          month: 10,
          today: today,
        ).budgetCents,
        300000);
    expect(
        budgetRulePreview(existing: [base], candidate: special, today: today)[1]
            .text,
        '9月一共 ¥1,000（少了 ¥2,000）');
  });

  test('编辑额外安排预览比较真实原值而非临时删除后的月金额', () {
    final base = _base(1, 3000, DateTime(2026, 9, 1));
    final old = _special(2, 300, DateTime(2026, 9, 25), DateTime(2026, 9, 27),
        funding: BudgetFunding.extra);
    final edit = _special(2, 200, old.startDate, old.endDate!,
        funding: BudgetFunding.extra);
    expect(
        budgetRulePreview(
                existing: [base, old], candidate: edit, today: today)[1]
            .text,
        startsWith('9月一共 ¥3,600（少了 ¥300）'));
  });

  test('尚未开始的日常预算也保留后续接替边界', () {
    final october = _base(1, 3000, DateTime(2026, 10, 1));
    final december = _base(2, 4000, DateTime(2026, 12, 1));
    final rules = [october, december];
    final span = budgetRuleSpan(october, rules, today);
    expect(span.state, BudgetRuleState.upcoming);
    expect(span.text, '10月起');
    expect(span.effectiveEnd, DateTime(2026, 11, 30));
    expect(
      budgetBaseEditWarning(
        original: october,
        existing: rules,
        amountCents: 320000,
        unit: BudgetRuleUnit.month,
        today: today,
      ),
      '这次修改会调整10月–11月的预算，已记录的账单不变。',
    );
  });
}
