// 预算规则模型验收用例（docs/08 §6.14）。iOS BudgetRulesTests 用同一组数字。
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_rule_calendar.dart';
import 'package:qingji/core/budget/budget_rule_engine.dart';
import 'package:qingji/core/budget/budget_rules.dart';

BudgetRule base(int yuan, BudgetRuleUnit unit, DateTime start,
        {int id = 1, int created = 1}) =>
    BudgetRule(
      id: id,
      bookId: 1,
      kind: BudgetRuleKind.base,
      amountCents: yuan * 100,
      unit: unit,
      startDate: start,
      createdMs: created,
    );

BudgetRule special(int yuan, BudgetRuleUnit unit, DateTime start, DateTime end,
        {int id = 2, int created = 2, BudgetFunding? funding}) =>
    BudgetRule(
      id: id,
      bookId: 1,
      kind: BudgetRuleKind.special,
      amountCents: yuan * 100,
      unit: unit,
      startDate: start,
      endDate: end,
      funding: funding,
      createdMs: created,
    );

BudgetMonthResult month(List<BudgetRule> rules, int y, int m,
        {Map<int, int> spend = const {},
        DateTime? today,
        List<BudgetRolloverChange> changes = const []}) =>
    BudgetRuleEngine.resolveMonth(
      rules: rules,
      rolloverChanges: changes,
      spendByDay: spend,
      year: y,
      month: m,
      today: today ?? DateTime(y, m, 1),
    );

int cents(BudgetMonthResult r, int day) => r.days[day - 1].budgetCents;

void main() {
  final sept4000 = base(4000, BudgetRuleUnit.month, DateTime(2026, 9, 1));
  final midAutumn = special(
      300, BudgetRuleUnit.day, DateTime(2026, 9, 25), DateTime(2026, 9, 27));

  test('1 每月 4000：前 10 天 134，其余 133，合计 4000', () {
    final r = month([sept4000], 2026, 9);
    expect(r.budgetCents, 400000);
    for (var d = 1; d <= 30; d++) {
      expect(cents(r, d), d <= 10 ? 13400 : 13300, reason: '9/$d');
    }
  });

  test('2 中秋匀：9 月仍 4000，中秋各 300，其余 22 天 115、5 天 114', () {
    final r = month([sept4000, midAutumn], 2026, 9);
    expect(r.budgetCents, 400000);
    for (final d in [25, 26, 27]) {
      expect(cents(r, d), 30000);
    }
    final others = [for (var d = 1; d <= 30; d++) if (d < 25 || d > 27) cents(r, d)];
    expect(others.where((c) => c == 11500).length, 22);
    expect(others.where((c) => c == 11400).length, 5);
  });

  test('3 中秋额外多给：9 月 4900', () {
    final extra = special(300, BudgetRuleUnit.day, DateTime(2026, 9, 25),
        DateTime(2026, 9, 27), funding: BudgetFunding.extra);
    expect(month([sept4000, extra], 2026, 9).budgetCents, 490000);
  });

  test('4 国庆每周 2000 匀：10 月 8000，国庆 286×5 + 285×2，其余 250', () {
    final r = month([
      base(8000, BudgetRuleUnit.month, DateTime(2026, 10, 1)),
      special(2000, BudgetRuleUnit.week, DateTime(2026, 10, 1),
          DateTime(2026, 10, 7)),
    ], 2026, 10);
    expect(r.budgetCents, 800000);
    for (var d = 1; d <= 31; d++) {
      final want = d <= 5 ? 28600 : d <= 7 ? 28500 : 25000;
      expect(cents(r, d), want, reason: '10/$d');
    }
  });

  test('5 日常预算接力、删除、全局修改', () {
    final a = base(5000, BudgetRuleUnit.month, DateTime(2026, 5, 1));
    final b = base(6000, BudgetRuleUnit.month, DateTime(2026, 10, 1),
        id: 2, created: 2);
    expect(month([a, b], 2026, 9).budgetCents, 500000);
    expect(month([a, b], 2026, 10).budgetCents, 600000);
    expect(month([a], 2026, 10).budgetCents, 500000);
    final edited = base(5200, BudgetRuleUnit.month, DateTime(2026, 5, 1));
    expect(month([edited, b], 2026, 5).budgetCents, 520000);
    expect(month([edited, b], 2026, 9).budgetCents, 520000);
  });

  test('6 每年预算：平年 36500、闰年 36600 都是每天 100', () {
    final r = month(
        [base(36500, BudgetRuleUnit.year, DateTime(2026, 1, 1))], 2026, 9);
    expect(r.days.every((d) => d.budgetCents == 10000), isTrue);
    final leap = month(
        [base(36600, BudgetRuleUnit.year, DateTime(2028, 1, 1))], 2028, 2);
    expect(leap.days.length, 29);
    expect(leap.days.every((d) => d.budgetCents == 10000), isTrue);
  });

  test('7 每周 700 跨月的一周：9/28–10/4 每天 100', () {
    final rules = [base(700, BudgetRuleUnit.week, DateTime(2026, 9, 1))];
    final sep = month(rules, 2026, 9);
    final oct = month(rules, 2026, 10);
    for (final d in [28, 29, 30]) {
      expect(cents(sep, d), 10000);
    }
    for (final d in [1, 2, 3, 4]) {
      expect(cents(oct, d), 10000);
    }
  });

  test('8 保存前校验：匀的钱超过月预算、没有日常预算', () {
    final tooMuch = special(
        2000, BudgetRuleUnit.day, DateTime(2026, 9, 25), DateTime(2026, 9, 27),
        id: 0);
    final issue = BudgetRuleEngine.validateSpecial(
        existing: [sept4000], candidate: tooMuch);
    expect(issue?.issue, BudgetRuleIssue.carveExceedsBase);
    expect(issue?.month, 9);
    expect(
        BudgetRuleEngine.validateSpecial(existing: [], candidate: tooMuch)
            ?.issue,
        BudgetRuleIssue.carveWithoutBase);
    expect(
        BudgetRuleEngine.validateSpecial(
            existing: [sept4000], candidate: midAutumn),
        isNull);
  });

  group('9 月底结余', () {
    BudgetRolloverChange mode(BudgetRolloverMode m) => BudgetRolloverChange(
        id: 1, bookId: 1, year: 2026, month: 10, mode: m, createdMs: 1);
    final oct15 = DateTime(2026, 10, 15);

    test('默认每月重新开始：不带结余', () {
      final r = month([sept4000], 2026, 10,
          spend: {20260910: 366000}, today: oct15);
      expect(r.carryInCents, 0);
      expect(r.effectiveCents, 400000);
    });

    test('省下的留给下个月：省 340 带过来，超 120 不扣', () {
      final keep = [mode(BudgetRolloverMode.keepSavings)];
      final saved = month([sept4000], 2026, 10,
          spend: {20260910: 366000}, today: oct15, changes: keep);
      expect(saved.carryInCents, 34000);
      expect(saved.effectiveCents, 434000);
      final over = month([sept4000], 2026, 10,
          spend: {20260910: 412000}, today: oct15, changes: keep);
      expect(over.carryInCents, 0);
    });

    test('多退少补：超 120 从 10 月扣；超太多继续滚到 11 月', () {
      final both = [mode(BudgetRolloverMode.carryBoth)];
      final over = month([sept4000], 2026, 10,
          spend: {20260910: 412000}, today: oct15, changes: both);
      expect(over.carryInCents, -12000);
      final huge = month([sept4000], 2026, 10,
          spend: {20260910: 900000}, today: oct15, changes: both);
      expect(huge.carryInCents, -500000);
      expect(huge.remainingCents, -100000);
      final nov = month([sept4000], 2026, 11,
          spend: {20260910: 900000}, today: DateTime(2026, 11, 15),
          changes: both);
      expect(nov.carryInCents, -100000);
    });
  });

  test('10 今天约：9/18 额度 103，花 60 还能花 43，花 200 多花 97', () {
    final today = DateTime(2026, 9, 18);
    final r = month([sept4000, midAutumn], 2026, 9,
        spend: {20260910: 216000, 20260918: 6000}, today: today);
    final t = r.today!;
    expect(t.allowanceCents, 10300);
    expect(t.leftTodayCents, 4300);
    expect(t.remainingDays, 13);
    expect(t.plannedBeforeTodayCents, 195500);
    expect(t.paceDeltaCents, -20500);
    final over = month([sept4000, midAutumn], 2026, 9,
        spend: {20260910: 216000, 20260918: 20000}, today: today);
    expect(over.today!.leftTodayCents, -9700);
  });

  test('11 没有规则覆盖的日子，支出不计入', () {
    final r = month([
      special(1500, BudgetRuleUnit.week, DateTime(2026, 10, 1),
          DateTime(2026, 10, 7), funding: BudgetFunding.extra),
    ], 2026, 10,
        spend: {20261002: 5000, 20261015: 8000}, today: DateTime(2026, 10, 31));
    expect(r.budgetCents, 150000);
    expect(r.spentCents, 5000);
    expect(r.days[14].covered, isFalse);
  });

  test('特别安排总额：每周 1500 只覆盖 5 天 → 1071', () {
    expect(
        budgetSpecialTotalYuan(special(1500, BudgetRuleUnit.week,
            DateTime(2026, 10, 1), DateTime(2026, 10, 5))),
        1071);
  });

  test('两条特别安排重叠：后建的占重叠日，月总额仍 4000', () {
    final a = special(
        300, BudgetRuleUnit.day, DateTime(2026, 9, 24), DateTime(2026, 9, 27));
    final b = special(
        200, BudgetRuleUnit.day, DateTime(2026, 9, 26), DateTime(2026, 9, 28),
        id: 3, created: 3);
    final r = month([sept4000, a, b], 2026, 9);
    expect(r.budgetCents, 400000);
    expect(cents(r, 24), 30000);
    expect(cents(r, 25), 30000);
    expect(cents(r, 26), 20000);
    expect(cents(r, 28), 20000);
    expect(cents(r, 1), 11200);
  });
}
