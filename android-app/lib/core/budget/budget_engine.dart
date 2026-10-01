import 'package:decimal/decimal.dart';

/// 当月预算执行状态。
class BudgetStatus {
  final Decimal monthlyBudget;
  final Decimal spentThisMonth;
  final Decimal spentToday;

  /// 月剩余预算（可为负）。
  final Decimal remaining;

  /// 「今日可花」：(预算 − 今天之前已花) ÷ 含今天的剩余天数 − 今天已花。可为负。
  ///
  /// 口径说明（和预算页「往后每天可花」区分，两者同一基底不矛盾）：
  ///   今日可花 = 今天这一天的份额，扣掉今天已花；
  ///   往后每天可花 = 剩余额度 ÷ 剩余天数（预算页自算），是往后的平均。
  final Decimal todayAllowance;
  final bool isOverBudget;

  /// 是否有「今日可用」日度引导。只有一次性区间预算（无循环周期）或
  /// 历史窗口时，窗口结果里没有当前周期日度状态，此时 spentToday /
  /// todayAllowance 只是 0 占位，展示层不应画「今日可用」圆环。
  final bool hasDailyGuidance;

  const BudgetStatus({
    required this.monthlyBudget,
    required this.spentThisMonth,
    required this.spentToday,
    required this.remaining,
    required this.todayAllowance,
    required this.isOverBudget,
    this.hasDailyGuidance = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BudgetStatus &&
          monthlyBudget == other.monthlyBudget &&
          spentThisMonth == other.spentThisMonth &&
          spentToday == other.spentToday &&
          remaining == other.remaining &&
          todayAllowance == other.todayAllowance &&
          isOverBudget == other.isOverBudget &&
          hasDailyGuidance == other.hasDailyGuidance;

  @override
  int get hashCode => Object.hash(
        monthlyBudget,
        spentThisMonth,
        spentToday,
        remaining,
        todayAllowance,
        isOverBudget,
        hasDailyGuidance,
      );
}
