/// 预算规则模型：每一天分到多少（docs/08 §6.3–§6.5）。
library;

import 'budget_rules.dart';

/// 某一天的预算，以及这天归哪条规则管。
class BudgetDayInfo {
  final DateTime day;
  final int budgetCents;
  final BudgetRule? baseRule;
  final BudgetRule? specialRule;

  const BudgetDayInfo({
    required this.day,
    required this.budgetCents,
    this.baseRule,
    this.specialRule,
  });

  /// 有任何规则管这一天。没有规则的日子，支出不计入预算。
  bool get covered => baseRule != null || specialRule != null;
}

/// 一条日常预算在它的一个自然周期里（§6.5「匀」的计算单位）。
class BudgetRuleSlice {
  /// yyyymmdd → 这天最终分到的分。
  final Map<int, int> cents = {};

  /// 正常日子 + 「匀」的日子原本分到的日常金额（不含「额外多给」的日子）。
  int baseCents = 0;

  /// 这个周期里所有「匀」的特别安排拿走的钱。
  int carveCents = 0;
  DateTime? firstCarveDay;
}

/// 特别安排一共多少元：对每一天取「金额 ÷ 该单位自然周期天数」再加总，
/// 四舍五入到元。用公分母做精确整数运算，两端结果一致。
int budgetSpecialTotalYuan(BudgetRule rule) {
  final end = rule.endDate;
  if (end == null || end.isBefore(rule.startDate)) return 0;
  final counts = <int, int>{};
  for (var d = rule.startDate; !d.isAfter(end); d = budgetAddDays(d, 1)) {
    final length = budgetNaturalPeriod(rule.unit, d).length;
    counts[length] = (counts[length] ?? 0) + 1;
  }
  var lcm = 1;
  for (final length in counts.keys) {
    lcm = lcm ~/ lcm.gcd(length) * length;
  }
  var numerator = 0;
  counts.forEach((length, count) => numerator += count * (lcm ~/ length));
  return (2 * rule.amountYuan * numerator + lcm) ~/ (2 * lcm);
}

class BudgetRuleCalendar {
  BudgetRuleCalendar(Iterable<BudgetRule> rules)
      : _bases = [
          for (final rule in rules)
            if (!rule.isDeleted && rule.isBase) rule
        ],
        _specials = [
          for (final rule in rules)
            if (!rule.isDeleted && !rule.isBase && rule.endDate != null) rule
        ];

  final List<BudgetRule> _bases;
  final List<BudgetRule> _specials;
  final Map<String, BudgetRuleSlice> _slices = {};
  final Map<BudgetRule, int> _specialTotals = Map.identity();

  List<BudgetRule> get rules => [..._bases, ..._specials];

  /// 开始日 ≤ 这天的日常预算里，最后新建的那条（§6.4 接力）。
  BudgetRule? baseOwner(DateTime day) {
    BudgetRule? best;
    for (final rule in _bases) {
      if (day.isBefore(rule.startDate)) continue;
      if (best == null || rule.outranks(best)) best = rule;
    }
    return best;
  }

  /// 覆盖这天的特别安排里，最后新建的那条（§6.5）。
  BudgetRule? specialOwner(DateTime day) {
    BudgetRule? best;
    for (final rule in _specials) {
      if (!rule.coversDay(day)) continue;
      if (best == null || rule.outranks(best)) best = rule;
    }
    return best;
  }

  int specialTotalYuan(BudgetRule rule) =>
      _specialTotals.putIfAbsent(rule, () => budgetSpecialTotalYuan(rule));

  int specialShareCents(BudgetRule rule, DateTime day) {
    final count = budgetDaysBetween(rule.startDate, rule.endDate!) + 1;
    final index = budgetDaysBetween(rule.startDate, day);
    return budgetEvenShare(specialTotalYuan(rule), count, index) * 100;
  }

  BudgetDayInfo dayInfo(DateTime value) {
    final day = budgetDay(value);
    final base = baseOwner(day);
    final special = specialOwner(day);
    final cents = base != null
        ? sliceFor(base, day).cents[budgetDayKey(day)] ?? 0
        : special != null
            ? specialShareCents(special, day)
            : 0;
    return BudgetDayInfo(
      day: day,
      budgetCents: cents,
      baseRule: base,
      specialRule: special,
    );
  }

  /// [base] 在包含 [day] 的自然周期里的分配结果。
  BudgetRuleSlice sliceFor(BudgetRule base, DateTime day) {
    final period = budgetNaturalPeriod(base.unit, day);
    final key = '${identityHashCode(base)}:${budgetDayKey(period.start)}';
    return _slices.putIfAbsent(key, () {
      final slice = BudgetRuleSlice();
      final normal = <DateTime>[];
      for (var i = 0; i < period.length; i++) {
        final d = budgetAddDays(period.start, i);
        if (!identical(baseOwner(d), base)) continue;
        final share = budgetEvenShare(base.amountYuan, period.length, i) * 100;
        final special = specialOwner(d);
        final dayKey = budgetDayKey(d);
        if (special == null) {
          normal.add(d);
          slice.baseCents += share;
          slice.cents[dayKey] = share;
        } else if (special.isExtra) {
          slice.cents[dayKey] = share + specialShareCents(special, d);
        } else {
          final carve = specialShareCents(special, d);
          slice.cents[dayKey] = carve;
          slice.baseCents += share;
          slice.carveCents += carve;
          slice.firstCarveDay ??= d;
        }
      }
      // 有「匀」时，其余日子平均分剩下的钱；没有时保持原份额（不重排零头）。
      if (slice.firstCarveDay != null && normal.isNotEmpty) {
        final pool = (slice.baseCents - slice.carveCents) ~/ 100;
        final safePool = pool < 0 ? 0 : pool;
        for (var i = 0; i < normal.length; i++) {
          slice.cents[budgetDayKey(normal[i])] =
              budgetEvenShare(safePool, normal.length, i) * 100;
        }
      }
      return slice;
    });
  }
}
