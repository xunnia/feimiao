import 'package:decimal/decimal.dart';
import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';

/// 某分类在统计周期内的合计。
class CategoryTotal {
  final String key;
  final String name;
  final Decimal total;

  /// 占总支出（或总收入）的比例，0..1。
  final double share;
  final int count;

  const CategoryTotal({
    this.key = '',
    required this.name,
    required this.total,
    required this.share,
    required this.count,
  });

  String get identity => key.isEmpty ? 'name:$name' : 'key:$key';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryTotal &&
          key == other.key &&
          name == other.name &&
          total == other.total &&
          share == other.share &&
          count == other.count;

  @override
  int get hashCode => Object.hash(key, name, total, share, count);
}

class _CategoryBucket {
  final String key;
  final String name;
  Decimal total;
  int count;

  _CategoryBucket({
    required this.key,
    required this.name,
    required this.total,
    required this.count,
  });
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

  int get dayCount => _calendarDaysBetween(start, end) + 1;
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

  static String _normalizedCategoryName(String raw) {
    final name = raw.trim();
    if (name.isEmpty ||
        name == '—' ||
        name == '-' ||
        name == '未分类' ||
        name == '其他支出') {
      return '其他';
    }
    return name;
  }

  static ({String identity, String key, String name}) _expenseCategory(
    TransactionRecord record,
  ) {
    final rawName = record.topCategoryName.trim().isNotEmpty
        ? record.topCategoryName
        : record.categoryName;
    final name = _normalizedCategoryName(rawName);
    final key = record.topCategoryKey.trim().isNotEmpty
        ? record.topCategoryKey.trim()
        : record.categoryKey.trim();
    return (
      identity: key.isEmpty ? 'name:$name' : 'key:$key',
      key: key,
      name: name,
    );
  }

  static void _addExpenseCategory(
    Map<String, _CategoryBucket> totals,
    TransactionRecord record,
  ) {
    final category = _expenseCategory(record);
    // 笔数只认净额为正的家族（口径标准 §7.1）：全额退款家族净额是 0，
    // 一分钱不贡献，就不该占一笔；legacy 负支出冲账行同理。金额照原样累加。
    final countsAsFamily = record.countsAsExpenseFamily ? 1 : 0;
    final bucket = totals[category.identity];
    if (bucket == null) {
      totals[category.identity] = _CategoryBucket(
        key: category.key,
        name: category.name,
        total: record.amount,
        count: countsAsFamily,
      );
      return;
    }
    bucket.total += record.amount;
    bucket.count += countsAsFamily;
  }

  static List<CategoryTotal> _buildCategoryTotals(
    Map<String, _CategoryBucket> totals,
    Decimal totalExpense,
  ) {
    final expenseDouble = totalExpense.toDouble();
    return totals.values
        .map((bucket) => CategoryTotal(
              key: bucket.key,
              name: bucket.name,
              total: bucket.total,
              share: expenseDouble > 0
                  ? bucket.total.toDouble() / expenseDouble
                  : 0.0,
              count: bucket.count,
            ))
        .toList()
      ..sort((a, b) {
        final cmp = b.total.compareTo(a.total);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });
  }

  static YearlySummary yearlySummary(
    List<TransactionRecord> records, {
    required int year,
  }) {
    var totalExpense = Decimal.zero;
    var totalIncome = Decimal.zero;
    final monthlyExpenses = List.filled(12, Decimal.zero, growable: false);
    final categoryTotals = <String, _CategoryBucket>{};

    for (final record in records) {
      if (record.kind == TransactionKind.transfer) continue;
      if (record.date.year != year) continue;

      switch (record.kind) {
        case TransactionKind.expense:
          totalExpense += record.amount;
          final monthIndex = record.date.month - 1;
          monthlyExpenses[monthIndex] =
              monthlyExpenses[monthIndex] + record.amount;
          _addExpenseCategory(categoryTotals, record);
        case TransactionKind.income:
          totalIncome += record.amount;
        case TransactionKind.transfer:
          break;
      }
    }

    final byCategory = _buildCategoryTotals(categoryTotals, totalExpense);

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
    final categoryTotals = <String, _CategoryBucket>{};
    final dailyExpense = <int, Decimal>{};
    final dailyIncome = <int, Decimal>{};

    for (final record in monthRecords) {
      final day = record.date.day;
      switch (record.kind) {
        case TransactionKind.expense:
          totalExpense += record.amount;
          dailyExpense[day] =
              (dailyExpense[day] ?? Decimal.zero) + record.amount;
          _addExpenseCategory(categoryTotals, record);
        case TransactionKind.income:
          totalIncome += record.amount;
          dailyIncome[day] = (dailyIncome[day] ?? Decimal.zero) + record.amount;
        case TransactionKind.transfer:
          break;
      }
    }

    final byCategory = _buildCategoryTotals(categoryTotals, totalExpense);

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
    final endExclusive = _addCalendarDays(e, 1);

    var totalExpense = Decimal.zero;
    var totalIncome = Decimal.zero;
    final categoryTotals = <String, _CategoryBucket>{};
    // 天序号(距 start 的天数) -> 合计
    final dayExpense = <int, Decimal>{};
    final dayIncome = <int, Decimal>{};

    for (final record in records) {
      if (record.kind == TransactionKind.transfer) continue;
      final d = DateTime(record.date.year, record.date.month, record.date.day);
      if (d.isBefore(s) || !d.isBefore(endExclusive)) continue;
      final idx = _calendarDaysBetween(s, d);

      switch (record.kind) {
        case TransactionKind.expense:
          totalExpense += record.amount;
          dayExpense[idx] = (dayExpense[idx] ?? Decimal.zero) + record.amount;
          _addExpenseCategory(categoryTotals, record);
        case TransactionKind.income:
          totalIncome += record.amount;
          dayIncome[idx] = (dayIncome[idx] ?? Decimal.zero) + record.amount;
        case TransactionKind.transfer:
          break;
      }
    }

    final byCategory = _buildCategoryTotals(categoryTotals, totalExpense);

    final dayCount = _calendarDaysBetween(s, endExclusive);
    final daily = List.generate(dayCount, (i) {
      return DateTotal(
        date: _addCalendarDays(s, i),
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

/// 日历日差值。不能用本地 DateTime 的 difference：有夏令时的时区里
/// 「差 23/25 小时」的两天 inDays 会算成 0 或 2 天。统一先归一到
/// UTC（无夏令时）再求差，天数精确。
int _calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// 日历日加减。不能用 add(Duration(days:))：夏令时切换日只有 23/25
/// 小时，加 24 小时会落到前/后一天的 23:00/01:00。用构造器让 Dart
/// 自动进位归一化，结果永远是目标日历日的 0 点。
DateTime _addCalendarDays(DateTime value, int days) =>
    DateTime(value.year, value.month, value.day + days);
