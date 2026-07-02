import 'package:decimal/decimal.dart';
import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';

/// 某分类在统计周期内的合计。
class CategoryTotal {
  final String name;
  final Decimal total;

  /// 占总支出（或总收入）的比例，0..1。
  final double share;
  final int count;

  const CategoryTotal({
    required this.name,
    required this.total,
    required this.share,
    required this.count,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryTotal &&
          name == other.name &&
          total == other.total &&
          share == other.share &&
          count == other.count;

  @override
  int get hashCode => Object.hash(name, total, share, count);
}

/// 单日收支合计。
class DailyTotal {
  final int day;
  final Decimal expense;
  final Decimal income;

  const DailyTotal({
    required this.day,
    required this.expense,
    required this.income,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyTotal &&
          day == other.day &&
          expense == other.expense &&
          income == other.income;

  @override
  int get hashCode => Object.hash(day, expense, income);
}

/// 月度统计结果。
class MonthlySummary {
  final int year;
  final int month;
  final Decimal totalExpense;
  final Decimal totalIncome;

  /// 按金额降序的支出分类排行。
  final List<CategoryTotal> expenseByCategory;

  /// 该月每天一条，含无消费日。
  final List<DailyTotal> dailyTotals;

  const MonthlySummary({
    required this.year,
    required this.month,
    required this.totalExpense,
    required this.totalIncome,
    required this.expenseByCategory,
    required this.dailyTotals,
  });

  Decimal get balance => totalIncome - totalExpense;
}

/// 任意日期一天的收支合计（跨月区间用，比 DailyTotal 多带完整日期）。
class DateTotal {
  final DateTime date;
  final Decimal expense;
  final Decimal income;

  const DateTotal({
    required this.date,
    required this.expense,
    required this.income,
  });
}

/// 任意日期区间统计结果（周 / 自定义维度用）。
class RangeSummary {
  /// 归一化到当天 0 点的起止日（含两端）。
  final DateTime start;
  final DateTime end;
  final Decimal totalExpense;
  final Decimal totalIncome;

  /// 按金额降序的支出分类排行。
  final List<CategoryTotal> expenseByCategory;

  /// 区间内每天一条（含无消费日，补零不断线）。
  final List<DateTotal> dailyTotals;

  const RangeSummary({
    required this.start,
    required this.end,
    required this.totalExpense,
    required this.totalIncome,
    required this.expenseByCategory,
    required this.dailyTotals,
  });

  Decimal get balance => totalIncome - totalExpense;

  int get dayCount => end.difference(start).inDays + 1;
}

/// 年度统计结果（消费年报的数据基础）。
class YearlySummary {
  final int year;
  final Decimal totalExpense;
  final Decimal totalIncome;

  /// 12 个月的支出，下标 0 = 1 月。
  final List<Decimal> monthlyExpenses;

  /// 全年支出分类排行。
  final List<CategoryTotal> expenseByCategory;

  const YearlySummary({
    required this.year,
    required this.totalExpense,
    required this.totalIncome,
    required this.monthlyExpenses,
    required this.expenseByCategory,
  });

  Decimal get balance => totalIncome - totalExpense;
}

/// 纯函数统计引擎。转账不计入收支。
class StatisticsEngine {
  StatisticsEngine._();

  static YearlySummary yearlySummary(
    List<TransactionRecord> records, {
    required int year,
  }) {
    var totalExpense = Decimal.zero;
    var totalIncome = Decimal.zero;
    final monthlyExpenses = List.filled(12, Decimal.zero, growable: false);
    // name -> (total, count)
    final categoryTotals = <String, (Decimal, int)>{};

    for (final record in records) {
      if (record.kind == TransactionKind.transfer) continue;
      if (record.date.year != year) continue;

      switch (record.kind) {
        case TransactionKind.expense:
          totalExpense += record.amount;
          final monthIndex = record.date.month - 1;
          monthlyExpenses[monthIndex] =
              monthlyExpenses[monthIndex] + record.amount;
          final name =
              record.categoryName.isEmpty ? '—' : record.categoryName;
          final prev = categoryTotals[name] ?? (Decimal.zero, 0);
          categoryTotals[name] = (prev.$1 + record.amount, prev.$2 + 1);
        case TransactionKind.income:
          totalIncome += record.amount;
        case TransactionKind.transfer:
          break;
      }
    }

    final expenseDouble = totalExpense.toDouble();
    final byCategory = categoryTotals.entries
        .map((e) => CategoryTotal(
              name: e.key,
              total: e.value.$1,
              share: expenseDouble > 0
                  ? e.value.$1.toDouble() / expenseDouble
                  : 0.0,
              count: e.value.$2,
            ))
        .toList()
      ..sort((a, b) {
        final cmp = b.total.compareTo(a.total);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });

    return YearlySummary(
      year: year,
      totalExpense: totalExpense,
      totalIncome: totalIncome,
      monthlyExpenses: List.unmodifiable(monthlyExpenses),
      expenseByCategory: List.unmodifiable(byCategory),
    );
  }

  static MonthlySummary monthlySummary(
    List<TransactionRecord> records, {
    required int year,
    required int month,
  }) {
    final monthRecords = records.where((r) {
      if (r.kind == TransactionKind.transfer) return false;
      return r.date.year == year && r.date.month == month;
    }).toList();

    var totalExpense = Decimal.zero;
    var totalIncome = Decimal.zero;
    final categoryTotals = <String, (Decimal, int)>{};
    final dailyExpense = <int, Decimal>{};
    final dailyIncome = <int, Decimal>{};

    for (final record in monthRecords) {
      final day = record.date.day;
      switch (record.kind) {
        case TransactionKind.expense:
          totalExpense += record.amount;
          dailyExpense[day] = (dailyExpense[day] ?? Decimal.zero) + record.amount;
          final name =
              record.categoryName.isEmpty ? '—' : record.categoryName;
          final prev = categoryTotals[name] ?? (Decimal.zero, 0);
          categoryTotals[name] = (prev.$1 + record.amount, prev.$2 + 1);
        case TransactionKind.income:
          totalIncome += record.amount;
          dailyIncome[day] =
              (dailyIncome[day] ?? Decimal.zero) + record.amount;
        case TransactionKind.transfer:
          break;
      }
    }

    final expenseDouble = totalExpense.toDouble();
    final byCategory = categoryTotals.entries
        .map((e) => CategoryTotal(
              name: e.key,
              total: e.value.$1,
              share: expenseDouble > 0
                  ? e.value.$1.toDouble() / expenseDouble
                  : 0.0,
              count: e.value.$2,
            ))
        .toList()
      ..sort((a, b) {
        final cmp = b.total.compareTo(a.total);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });

    final dayCount = daysInMonth(year: year, month: month);
    final daily = List.generate(
      dayCount,
      (i) {
        final d = i + 1;
        return DailyTotal(
          day: d,
          expense: dailyExpense[d] ?? Decimal.zero,
          income: dailyIncome[d] ?? Decimal.zero,
        );
      },
    );

    return MonthlySummary(
      year: year,
      month: month,
      totalExpense: totalExpense,
      totalIncome: totalIncome,
      expenseByCategory: List.unmodifiable(byCategory),
      dailyTotals: List.unmodifiable(daily),
    );
  }

  /// 任意日期区间统计（含起止两端；时间部分被忽略）。周 / 自定义维度用。
  static RangeSummary rangeSummary(
    List<TransactionRecord> records, {
    required DateTime start,
    required DateTime end,
  }) {
    var s = DateTime(start.year, start.month, start.day);
    var e = DateTime(end.year, end.month, end.day);
    if (e.isBefore(s)) {
      final tmp = s;
      s = e;
      e = tmp;
    }
    final endExclusive = e.add(const Duration(days: 1));

    var totalExpense = Decimal.zero;
    var totalIncome = Decimal.zero;
    final categoryTotals = <String, (Decimal, int)>{};
    // 天序号(距 start 的天数) -> 合计
    final dayExpense = <int, Decimal>{};
    final dayIncome = <int, Decimal>{};

    for (final record in records) {
      if (record.kind == TransactionKind.transfer) continue;
      final d = DateTime(
          record.date.year, record.date.month, record.date.day);
      if (d.isBefore(s) || !d.isBefore(endExclusive)) continue;
      final idx = d.difference(s).inDays;

      switch (record.kind) {
        case TransactionKind.expense:
          totalExpense += record.amount;
          dayExpense[idx] = (dayExpense[idx] ?? Decimal.zero) + record.amount;
          final name =
              record.categoryName.isEmpty ? '—' : record.categoryName;
          final prev = categoryTotals[name] ?? (Decimal.zero, 0);
          categoryTotals[name] = (prev.$1 + record.amount, prev.$2 + 1);
        case TransactionKind.income:
          totalIncome += record.amount;
          dayIncome[idx] = (dayIncome[idx] ?? Decimal.zero) + record.amount;
        case TransactionKind.transfer:
          break;
      }
    }

    final expenseDouble = totalExpense.toDouble();
    final byCategory = categoryTotals.entries
        .map((entry) => CategoryTotal(
              name: entry.key,
              total: entry.value.$1,
              share: expenseDouble > 0
                  ? entry.value.$1.toDouble() / expenseDouble
                  : 0.0,
              count: entry.value.$2,
            ))
        .toList()
      ..sort((a, b) {
        final cmp = b.total.compareTo(a.total);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });

    final dayCount = endExclusive.difference(s).inDays;
    final daily = List.generate(dayCount, (i) {
      return DateTotal(
        date: s.add(Duration(days: i)),
        expense: dayExpense[i] ?? Decimal.zero,
        income: dayIncome[i] ?? Decimal.zero,
      );
    });

    return RangeSummary(
      start: s,
      end: e,
      totalExpense: totalExpense,
      totalIncome: totalIncome,
      expenseByCategory: List.unmodifiable(byCategory),
      dailyTotals: List.unmodifiable(daily),
    );
  }

  /// 该月天数。
  static int daysInMonth({required int year, required int month}) {
    // DateTime(year, month + 1, 0) 的 day 即为当月最后一天。
    return DateTime(year, month + 1, 0).day;
  }
}
