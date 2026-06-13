import 'package:decimal/decimal.dart';
import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';
import '../statistics/statistics_engine.dart';

/// 当月预算执行状态。
class BudgetStatus {
  final Decimal monthlyBudget;
  final Decimal spentThisMonth;
  final Decimal spentToday;

  /// 月剩余预算（可为负）。
  final Decimal remaining;

  /// 「今日可花」：(预算 − 今天之前已花) ÷ 含今天的剩余天数 − 今天已花。可为负。
  final Decimal todayAllowance;
  final bool isOverBudget;

  const BudgetStatus({
    required this.monthlyBudget,
    required this.spentThisMonth,
    required this.spentToday,
    required this.remaining,
    required this.todayAllowance,
    required this.isOverBudget,
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
          isOverBudget == other.isOverBudget;

  @override
  int get hashCode => Object.hash(
        monthlyBudget,
        spentThisMonth,
        spentToday,
        remaining,
        todayAllowance,
        isOverBudget,
      );
}

/// 预算前置提醒的核心：把「月底才知道超支」变成「今天就知道还能花多少」。
class BudgetEngine {
  BudgetEngine._();

  static BudgetStatus status({
    required Decimal monthlyBudget,
    required List<TransactionRecord> records,
    DateTime? on,
  }) {
    final date = on ?? DateTime.now();
    final today = date.day;
    final dayCount = StatisticsEngine.daysInMonth(
      year: date.year,
      month: date.month,
    );

    var spentThisMonth = Decimal.zero;
    var spentToday = Decimal.zero;

    for (final record in records) {
      if (record.kind != TransactionKind.expense) continue;
      if (record.date.year != date.year) continue;
      if (record.date.month != date.month) continue;
      spentThisMonth += record.amount;
      if (record.date.day == today) {
        spentToday += record.amount;
      }
    }

    final spentBeforeToday = spentThisMonth - spentToday;
    final remainingDaysInt = dayCount - today + 1 < 1 ? 1 : dayCount - today + 1;
    final remainingDays = Decimal.fromInt(remainingDaysInt);
    // In decimal v3, Decimal / Decimal returns Rational; convert back to Decimal
    // with sufficient scale (10 decimal places) before subtracting spentToday.
    final quotient = ((monthlyBudget - spentBeforeToday) / remainingDays)
        .toDecimal(scaleOnInfinitePrecision: 10);
    final todayAllowance = quotient - spentToday;

    return BudgetStatus(
      monthlyBudget: monthlyBudget,
      spentThisMonth: spentThisMonth,
      spentToday: spentToday,
      remaining: monthlyBudget - spentThisMonth,
      todayAllowance: todayAllowance,
      isOverBudget: spentThisMonth > monthlyBudget,
    );
  }
}
