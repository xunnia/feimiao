import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/statistics/spending_insights.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';

DateTime _d(int y, int m, int day) => DateTime(y, m, day, 12);

TransactionRecord _rec({
  required TransactionKind kind,
  required int amount,
  String categoryName = '',
  required DateTime date,
}) =>
    TransactionRecord.create(
      kind: kind,
      amount: Decimal.fromInt(amount),
      categoryName: categoryName,
      accountName: '',
      toAccountName: '',
      date: date,
    );

void main() {
  group('StatisticsEngine.rangeSummary', () {
    final records = [
      _rec(kind: TransactionKind.expense, amount: 30, categoryName: '餐饮', date: _d(2026, 6, 29)),
      _rec(kind: TransactionKind.expense, amount: 20, categoryName: '交通', date: _d(2026, 6, 30)),
      _rec(kind: TransactionKind.expense, amount: 50, categoryName: '餐饮', date: _d(2026, 7, 1)),
      _rec(kind: TransactionKind.income, amount: 100, date: _d(2026, 7, 1)),
      _rec(kind: TransactionKind.transfer, amount: 500, date: _d(2026, 6, 30)),
      // 区间外
      _rec(kind: TransactionKind.expense, amount: 999, date: _d(2026, 6, 28)),
      _rec(kind: TransactionKind.expense, amount: 999, date: _d(2026, 7, 6)),
    ];

    test('跨月区间：含两端、排除转账和区间外', () {
      final s = StatisticsEngine.rangeSummary(records,
          start: _d(2026, 6, 29), end: _d(2026, 7, 5));
      expect(s.totalExpense, Decimal.fromInt(100));
      expect(s.totalIncome, Decimal.fromInt(100));
      expect(s.dayCount, 7);
      expect(s.dailyTotals.length, 7);
      // 第 1 天 = 6/29 支出 30
      expect(s.dailyTotals.first.date, DateTime(2026, 6, 29));
      expect(s.dailyTotals.first.expense, Decimal.fromInt(30));
      // 无消费日补零
      expect(s.dailyTotals[3].expense, Decimal.zero);
      // 分类排行：餐饮 80 在前
      expect(s.expenseByCategory.first.name, '餐饮');
      expect(s.expenseByCategory.first.total, Decimal.fromInt(80));
      expect(s.expenseByCategory.first.share, closeTo(0.8, 0.0001));
    });

    test('起止颠倒自动纠正', () {
      final s = StatisticsEngine.rangeSummary(records,
          start: _d(2026, 7, 5), end: _d(2026, 6, 29));
      expect(s.start, DateTime(2026, 6, 29));
      expect(s.totalExpense, Decimal.fromInt(100));
    });
  });

  group('SpendingInsights.summaryLines', () {
    test('比上月多花的分类和总额变化会被点名', () {
      final records = [
        // 上月：餐饮 100
        _rec(kind: TransactionKind.expense, amount: 100, categoryName: '餐饮', date: _d(2026, 5, 10)),
        // 本月：餐饮 300（+200 ≥50 触发）
        _rec(kind: TransactionKind.expense, amount: 150, categoryName: '餐饮', date: _d(2026, 6, 5)),
        _rec(kind: TransactionKind.expense, amount: 150, categoryName: '餐饮', date: _d(2026, 6, 8)),
      ];
      final lines =
          SpendingInsights.summaryLines(records, year: 2026, month: 6);
      expect(lines, isNotEmpty);
      expect(lines.join(), contains('餐饮'));
      expect(lines.join(), contains('比上月'));
    });

    test('上月无数据时不做无意义对比', () {
      final records = [
        _rec(kind: TransactionKind.expense, amount: 30, categoryName: '餐饮', date: _d(2026, 6, 5)),
      ];
      final lines =
          SpendingInsights.summaryLines(records, year: 2026, month: 6);
      // 只有涨幅类的可能命中（30 < 50 不触发），总额对比不该出现
      expect(lines.join(), isNot(contains('%')));
    });
  });

  group('SpendingInsights.profile', () {
    List<TransactionRecord> smallSpends(int n) => [
          for (var i = 0; i < n; i++)
            _rec(kind: TransactionKind.expense, amount: 50, categoryName: '餐饮', date: _d(2026, 6, i + 1)),
        ];

    test('不足 5 笔支出 → null（不瞎判断）', () {
      expect(
          SpendingInsights.profile(smallSpends(4), year: 2026, month: 6),
          isNull);
    });

    test('结余率 <5% → 月光型', () {
      final records = [
        ...smallSpends(5), // 支出 250
        _rec(kind: TransactionKind.income, amount: 255, date: _d(2026, 6, 1)),
      ];
      final p = SpendingInsights.profile(records, year: 2026, month: 6);
      expect(p?.title, '月光型');
    });

    test('结余率 ≥30% → 稳健储蓄型', () {
      final records = [
        ...smallSpends(5), // 支出 250
        _rec(kind: TransactionKind.income, amount: 1000, date: _d(2026, 6, 1)),
      ];
      final p = SpendingInsights.profile(records, year: 2026, month: 6);
      expect(p?.title, '稳健储蓄型');
    });

    test('单笔占比 ≥35% → 大额冲动型（优先于结余率）', () {
      final records = [
        ...smallSpends(5), // 250
        _rec(kind: TransactionKind.expense, amount: 400, categoryName: '数码', date: _d(2026, 6, 20)),
        _rec(kind: TransactionKind.income, amount: 5000, date: _d(2026, 6, 1)),
      ];
      final p = SpendingInsights.profile(records, year: 2026, month: 6);
      expect(p?.title, '大额冲动型');
    });

    test('没记收入 → 认真记账型兜底', () {
      final p = SpendingInsights.profile(smallSpends(6), year: 2026, month: 6);
      expect(p?.title, '认真记账型');
    });
  });

  group('SpendingInsights.forecast', () {
    test('无预算 → null', () {
      expect(
          SpendingInsights.forecast([],
              monthlyBudget: null, now: DateTime(2026, 6, 15)),
          isNull);
    });

    test('月初前两天 → null（数据太少）', () {
      final records = [
        _rec(kind: TransactionKind.expense, amount: 100, date: _d(2026, 6, 1)),
      ];
      expect(
          SpendingInsights.forecast(records,
              monthlyBudget: Decimal.fromInt(1000), now: DateTime(2026, 6, 2)),
          isNull);
    });

    test('线性外推：15 号花了 600，预算 1000 → 预测 1200 超 200', () {
      final records = [
        _rec(kind: TransactionKind.expense, amount: 600, date: _d(2026, 6, 10)),
      ];
      final f = SpendingInsights.forecast(records,
          monthlyBudget: Decimal.fromInt(1000), now: DateTime(2026, 6, 15));
      expect(f, isNotNull);
      expect(f!.projected, Decimal.parse('1200.00'));
      expect(f.overBy, Decimal.parse('200.00'));
      expect(f.text, contains('超预算'));
    });

    test('在预算内 → 稳的文案', () {
      final records = [
        _rec(kind: TransactionKind.expense, amount: 300, date: _d(2026, 6, 10)),
      ];
      final f = SpendingInsights.forecast(records,
          monthlyBudget: Decimal.fromInt(1000), now: DateTime(2026, 6, 15));
      expect(f, isNotNull);
      expect(f!.overBy <= Decimal.zero, isTrue);
      expect(f.text, contains('预算内'));
    });
  });
}
