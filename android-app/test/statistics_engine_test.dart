import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';

DateTime _date(int year, int month, int day) =>
    DateTime(year, month, day, 12);

TransactionRecord _rec({
  required TransactionKind kind,
  required Decimal amount,
  String categoryName = '',
  String accountName = '',
  String toAccountName = '',
  required DateTime date,
}) =>
    TransactionRecord.create(
      kind: kind,
      amount: amount,
      categoryName: categoryName,
      accountName: accountName,
      toAccountName: toAccountName,
      date: date,
    );

List<TransactionRecord> _makeRecords() => [
      _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(30), categoryName: '餐饮', date: _date(2026, 6, 1)),
      _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(20), categoryName: '餐饮', date: _date(2026, 6, 2)),
      _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(50), categoryName: '交通', date: _date(2026, 6, 2)),
      _rec(kind: TransactionKind.income, amount: Decimal.fromInt(1000), categoryName: '工资', date: _date(2026, 6, 10)),
      _rec(kind: TransactionKind.transfer, amount: Decimal.fromInt(500), date: _date(2026, 6, 5)),
      // 其他月份的记录应被排除
      _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(999), categoryName: '餐饮', date: _date(2026, 5, 31)),
    ];

void main() {
  group('StatisticsEngine – monthlySummary', () {
    test('totals exclude transfers and other months', () {
      final summary = StatisticsEngine.monthlySummary(
        _makeRecords(),
        year: 2026,
        month: 6,
      );
      expect(summary.totalExpense, Decimal.fromInt(100));
      expect(summary.totalIncome, Decimal.fromInt(1000));
      expect(summary.balance, Decimal.fromInt(900));
    });

    test('category ranking and share', () {
      final summary = StatisticsEngine.monthlySummary(
        _makeRecords(),
        year: 2026,
        month: 6,
      );
      expect(summary.expenseByCategory.map((c) => c.name).toList(),
          ['交通', '餐饮']);
      expect(summary.expenseByCategory[0].total, Decimal.fromInt(50));
      expect(summary.expenseByCategory[0].share, closeTo(0.5, 0.0001));
      expect(summary.expenseByCategory[1].count, 2);
    });

    test('daily totals cover whole month', () {
      final summary = StatisticsEngine.monthlySummary(
        _makeRecords(),
        year: 2026,
        month: 6,
      );
      expect(summary.dailyTotals.length, 30);
      expect(summary.dailyTotals[0].expense, Decimal.fromInt(30));  // June 1
      expect(summary.dailyTotals[1].expense, Decimal.fromInt(70));  // June 2
      expect(summary.dailyTotals[9].income, Decimal.fromInt(1000)); // June 10
      expect(summary.dailyTotals[19].expense, Decimal.zero);
    });

    test('empty month', () {
      final summary = StatisticsEngine.monthlySummary(
        [],
        year: 2026,
        month: 2,
      );
      expect(summary.totalExpense, Decimal.zero);
      expect(summary.dailyTotals.length, 28); // 2026 is not a leap year
      expect(summary.expenseByCategory, isEmpty);
    });
  });

  group('StatisticsEngine – yearlySummary', () {
    test('yearly totals and monthly buckets', () {
      final records = [
        _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(100), categoryName: '餐饮', date: _date(2026, 1, 5)),
        _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(200), categoryName: '交通', date: _date(2026, 6, 5)),
        _rec(kind: TransactionKind.income, amount: Decimal.fromInt(5000), categoryName: '工资', date: _date(2026, 6, 10)),
        // 其他年份的记录应被排除
        _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(999), categoryName: '餐饮', date: _date(2025, 3, 1)),
      ];
      final summary = StatisticsEngine.yearlySummary(records, year: 2026);
      expect(summary.totalExpense, Decimal.fromInt(300));
      expect(summary.totalIncome, Decimal.fromInt(5000));
      expect(summary.monthlyExpenses[0], Decimal.fromInt(100));  // January
      expect(summary.monthlyExpenses[5], Decimal.fromInt(200));  // June
      expect(summary.monthlyExpenses[2], Decimal.zero);           // March
      expect(summary.expenseByCategory.first?.name, '交通');
    });
  });
}
