/// 预算规则结果给各处消费者用的包装（docs/08 §6.10）：主页、小组件、统计环、
/// 记账页提示、喵洞察、AI 上下文都从这里拿数，保证同一个数一致到元。
library;

import 'package:decimal/decimal.dart';

import 'budget_engine.dart';
import 'budget_rule_calendar.dart';
import 'budget_rule_engine.dart';
import 'budget_rules.dart';

Decimal budgetCentsToDecimal(int cents) =>
    (Decimal.fromInt(cents) / Decimal.fromInt(100)).toDecimal();

/// 某个账本某个月的预算结果 + 被排除的其他币种笔数。
class BudgetRuleSnapshot {
  final int bookId;
  final BudgetMonthResult month;

  /// 这个月有规则的日子里，因为不是 CNY 被排除的支出笔数。
  final int excludedForeignCount;

  const BudgetRuleSnapshot({
    required this.bookId,
    required this.month,
    this.excludedForeignCount = 0,
  });

  bool get hasBudget => month.hasRules;

  /// 实际总额（每天预算之和 + 带进来的结余）。没有规则时为 null。
  Decimal? get plannedAmount =>
      hasBudget ? budgetCentsToDecimal(month.effectiveCents) : null;
  Decimal? get spentAmount =>
      hasBudget ? budgetCentsToDecimal(month.spentCents) : null;
  Decimal? get remainingAmount =>
      hasBudget ? budgetCentsToDecimal(month.remainingCents) : null;

  /// 旧消费者（主页卡、小组件、记账页提示）用的形状。没有规则时为 null。
  ///
  /// 今日可用 = 今天还能花（今天的额度 − 今天已花，可为负），和旧口径一致；
  /// 只有这个月包含今天、且今天有规则覆盖时才有日度引导。
  BudgetStatus? get status {
    if (!hasBudget) return null;
    final today = month.today;
    // remainingDays 含今天，所以今天在 days 里的下标 = 当月天数 − remainingDays。
    final todayIndex = today == null ? -1 : month.days.length - today.remainingDays;
    final todayCovered = todayIndex >= 0 &&
        todayIndex < month.days.length &&
        month.days[todayIndex].covered;
    return BudgetStatus(
      monthlyBudget: budgetCentsToDecimal(month.effectiveCents),
      spentThisMonth: budgetCentsToDecimal(month.spentCents),
      spentToday: budgetCentsToDecimal(today?.spentTodayCents ?? 0),
      remaining: budgetCentsToDecimal(month.remainingCents),
      todayAllowance: budgetCentsToDecimal(today?.leftTodayCents ?? 0),
      isOverBudget: month.remainingCents < 0,
      hasDailyGuidance: todayCovered,
    );
  }
}

/// 保存特别安排被拦下（§6.5）：界面据此提示「改成额外多给」或「先设日常预算」。
class BudgetRuleValidationException implements Exception {
  final BudgetRuleValidation validation;
  const BudgetRuleValidationException(this.validation);

  @override
  String toString() => switch (validation.issue) {
        BudgetRuleIssue.carveWithoutBase =>
          '${validation.month}月还没有日常预算，没法从里面匀，可以改成额外多给',
        BudgetRuleIssue.carveExceedsBase =>
          '匀的钱超过了${validation.month}月的预算，可以改成额外多给',
      };
}

/// 任意日期区间的预算合计（AI 问「这周」「某几天」、周报/月报用）。
/// 不带结余：只是区间里每天日历预算之和 vs 这些日子已花。
class BudgetRuleRangeSummary {
  final DateTime startInclusive;
  final DateTime endInclusive;
  final int budgetCents;
  final int spentCents;
  final int excludedForeignCount;

  const BudgetRuleRangeSummary({
    required this.startInclusive,
    required this.endInclusive,
    required this.budgetCents,
    required this.spentCents,
    this.excludedForeignCount = 0,
  });

  bool get hasBudget => budgetCents > 0;
  int get remainingCents => budgetCents - spentCents;
  Decimal get budgetAmount => budgetCentsToDecimal(budgetCents);
  Decimal get spentAmount => budgetCentsToDecimal(spentCents);
  Decimal get remainingAmount => budgetCentsToDecimal(remainingCents);

  static BudgetRuleRangeSummary resolve({
    required Iterable<BudgetRule> rules,
    required Map<int, int> spendByDay,
    required DateTime startInclusive,
    required DateTime endInclusive,
    required DateTime today,
    int excludedForeignCount = 0,
  }) {
    final calendar = BudgetRuleCalendar(rules);
    final start = budgetDay(startInclusive);
    final end = budgetDay(endInclusive);
    final todayDay = budgetDay(today);
    var budget = 0;
    var spent = 0;
    for (var d = start; !d.isAfter(end); d = budgetAddDays(d, 1)) {
      final info = calendar.dayInfo(d);
      if (!info.covered) continue;
      budget += info.budgetCents;
      if (!d.isAfter(todayDay)) spent += spendByDay[budgetDayKey(d)] ?? 0;
    }
    return BudgetRuleRangeSummary(
      startInclusive: start,
      endInclusive: end,
      budgetCents: budget,
      spentCents: spent,
      excludedForeignCount: excludedForeignCount,
    );
  }
}
