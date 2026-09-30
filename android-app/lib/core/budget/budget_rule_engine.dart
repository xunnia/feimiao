/// 预算规则模型：一个月的结果、月底结余、今天约、保存前校验
/// （docs/08 §6.5–§6.7）。纯逻辑，iOS 按同一算法实现。
library;

import 'budget_rule_calendar.dart';
import 'budget_rules.dart';

/// 今天的额度：每天早上定一次，白天只做减法（§6.7）。
class BudgetTodayStatus {
  /// 今天的额度（分，已向下取整到元，≥ 0）。
  final int allowanceCents;
  final int spentTodayCents;

  /// 今天还能花 = 额度 − 今天已花；< 0 时界面写「今天多花了 ¥X」。
  final int leftTodayCents;

  /// 今天到月底，包含今天。
  final int remainingDays;

  /// 按日历预算到昨天应花 / 实际到昨天已花（节奏）。
  final int plannedBeforeTodayCents;
  final int spentBeforeTodayCents;

  const BudgetTodayStatus({
    required this.allowanceCents,
    required this.spentTodayCents,
    required this.leftTodayCents,
    required this.remainingDays,
    required this.plannedBeforeTodayCents,
    required this.spentBeforeTodayCents,
  });

  /// 比计划少花（> 0）或多花（< 0）了多少分。
  int get paceDeltaCents => plannedBeforeTodayCents - spentBeforeTodayCents;
}

class BudgetMonthResult {
  final int year;
  final int month;
  final List<BudgetDayInfo> days;

  /// 这个月每天预算之和（不含结余）。
  final int budgetCents;

  /// 从上个月带进来的结余（可为负）。
  final int carryInCents;
  final int spentCents;
  final BudgetRolloverMode rolloverMode;

  /// 只有这个月包含今天时才有。
  final BudgetTodayStatus? today;

  const BudgetMonthResult({
    required this.year,
    required this.month,
    required this.days,
    required this.budgetCents,
    required this.carryInCents,
    required this.spentCents,
    required this.rolloverMode,
    this.today,
  });

  bool get hasRules => days.any((day) => day.covered);
  int get effectiveCents => budgetCents + carryInCents;

  /// 还能花（可为负；界面负数改写「X月超出 ¥Y」）。
  int get remainingCents => effectiveCents - spentCents;
}

/// 特别安排保存前要拦下的情况（§6.5）。
enum BudgetRuleIssue { carveWithoutBase, carveExceedsBase }

typedef BudgetRuleValidation = ({BudgetRuleIssue issue, int year, int month});

/// 向下取整到元（分）。负数也向下，所以 −0.5 元 → −1 元。
int budgetFloorYuanCents(int cents) => (cents / 100).floor() * 100;

class BudgetRuleEngine {
  BudgetRuleEngine._();

  static int _monthIndex(DateTime day) => day.year * 12 + day.month - 1;

  /// [spendByDay]：yyyymmdd → 当天计入预算的支出（分）。调用方已按口径过滤
  /// （净额 > 0、计入预算、CNY、账本范围）；这里再只取有规则、且不晚于今天的日子。
  static BudgetMonthResult resolveMonth({
    required Iterable<BudgetRule> rules,
    Iterable<BudgetRolloverChange> rolloverChanges = const [],
    required Map<int, int> spendByDay,
    required int year,
    required int month,
    required DateTime today,
  }) {
    final calendar = BudgetRuleCalendar(rules);
    final changes = rolloverChanges.toList()
      ..sort((a, b) => a.monthIndex != b.monthIndex
          ? a.monthIndex.compareTo(b.monthIndex)
          : a.createdMs.compareTo(b.createdMs));
    BudgetRolloverMode modeFor(int index) {
      var mode = BudgetRolloverMode.reset;
      for (final change in changes) {
        if (change.monthIndex > index) break;
        mode = change.mode;
      }
      return mode;
    }

    final todayDay = budgetDay(today);
    final target = year * 12 + month - 1;
    final starts = [
      for (final rule in calendar.rules) _monthIndex(rule.startDate),
      for (final change in changes) change.monthIndex,
    ];
    var carry = 0;
    if (starts.isNotEmpty) {
      final first = starts.reduce((a, b) => a < b ? a : b);
      for (var index = first; index < target; index++) {
        final days = _days(calendar, index);
        final budget = days.fold(0, (sum, d) => sum + d.budgetCents);
        final spent = _spent(days, spendByDay, todayDay);
        final result = budget + carry - spent;
        carry = switch (modeFor(index + 1)) {
          BudgetRolloverMode.reset => 0,
          BudgetRolloverMode.keepSavings => result > 0 ? result : 0,
          BudgetRolloverMode.carryBoth => result,
        };
      }
    }
    if (modeFor(target) == BudgetRolloverMode.reset) carry = 0;

    final days = _days(calendar, target);
    final budget = days.fold(0, (sum, d) => sum + d.budgetCents);
    final spent = _spent(days, spendByDay, todayDay);
    final inMonth = todayDay.year == year && todayDay.month == month;
    return BudgetMonthResult(
      year: year,
      month: month,
      days: days,
      budgetCents: budget,
      carryInCents: carry,
      spentCents: spent,
      rolloverMode: modeFor(target),
      today: inMonth
          ? _todayStatus(days, spendByDay, todayDay, budget + carry)
          : null,
    );
  }

  static List<BudgetDayInfo> _days(BudgetRuleCalendar calendar, int index) {
    final year = index ~/ 12;
    final month = index % 12 + 1;
    return [
      for (var d = 1; d <= budgetDaysInMonth(year, month); d++)
        calendar.dayInfo(DateTime(year, month, d)),
    ];
  }

  static int _spent(
    List<BudgetDayInfo> days,
    Map<int, int> spendByDay,
    DateTime today,
  ) {
    var total = 0;
    for (final day in days) {
      if (!day.covered || day.day.isAfter(today)) continue;
      total += spendByDay[budgetDayKey(day.day)] ?? 0;
    }
    return total;
  }

  static BudgetTodayStatus _todayStatus(
    List<BudgetDayInfo> days,
    Map<int, int> spendByDay,
    DateTime today,
    int effectiveCents,
  ) {
    var plannedBefore = 0;
    var spentBefore = 0;
    var weight = 0;
    var todayBudget = 0;
    var spentToday = 0;
    for (final day in days) {
      final spend = day.covered ? spendByDay[budgetDayKey(day.day)] ?? 0 : 0;
      if (day.day.isBefore(today)) {
        plannedBefore += day.budgetCents;
        spentBefore += spend;
      } else {
        weight += day.budgetCents;
        if (day.day == today) {
          todayBudget = day.budgetCents;
          spentToday = spend;
        }
      }
    }
    final remainingStart = effectiveCents - spentBefore;
    var allowance = 0;
    if (remainingStart > 0 && weight > 0 && todayBudget > 0) {
      final raw = BigInt.from(remainingStart) *
          BigInt.from(todayBudget) ~/
          BigInt.from(weight);
      allowance = budgetFloorYuanCents(raw.toInt());
    }
    return BudgetTodayStatus(
      allowanceCents: allowance,
      spentTodayCents: spentToday,
      leftTodayCents: allowance - spentToday,
      remainingDays: budgetDaysInMonth(today.year, today.month) - today.day + 1,
      plannedBeforeTodayCents: plannedBefore,
      spentBeforeTodayCents: spentBefore,
    );
  }

  /// 保存特别安排前的校验（§6.5）。[candidate] 编辑时带原 id，新建时 id 可为 0。
  /// 返回 null 表示可以保存。
  static BudgetRuleValidation? validateSpecial({
    required Iterable<BudgetRule> existing,
    required BudgetRule candidate,
  }) {
    final end = candidate.endDate;
    if (candidate.isBase || end == null || candidate.isExtra) return null;
    final others = [
      for (final rule in existing)
        if (candidate.id == 0 || rule.id != candidate.id) rule
    ];
    final calendar = BudgetRuleCalendar([...others, candidate]);
    for (var d = candidate.startDate; !d.isAfter(end); d = budgetAddDays(d, 1)) {
      if (!identical(calendar.specialOwner(d), candidate)) continue;
      final base = calendar.baseOwner(d);
      if (base == null) {
        return (
          issue: BudgetRuleIssue.carveWithoutBase,
          year: d.year,
          month: d.month
        );
      }
      final slice = calendar.sliceFor(base, d);
      if (slice.carveCents > slice.baseCents) {
        final at = slice.firstCarveDay ?? d;
        return (
          issue: BudgetRuleIssue.carveExceedsBase,
          year: at.year,
          month: at.month
        );
      }
    }
    return null;
  }
}
