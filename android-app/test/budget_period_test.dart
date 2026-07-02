import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_period.dart';
import 'package:qingji/core/budget/budget_suggestion.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';

BudgetPeriod _p({
  int id = 1,
  int? bookId,
  required DateTime start,
  DateTime? end,
  bool recurring = true,
  required int total,
  int createdMs = 0,
}) =>
    BudgetPeriod(
      id: id,
      bookId: bookId,
      start: start,
      end: end,
      recurringMonthly: recurring,
      total: Decimal.fromInt(total),
      createdMs: createdMs,
    );

void main() {
  group('BudgetResolver.effectiveOn', () {
    test('历史月用当时生效的期间，新期间不影响过去', () {
      final periods = [
        _p(id: 1, start: DateTime(2026, 1, 1), end: DateTime(2026, 5, 31), total: 3000),
        _p(id: 2, start: DateTime(2026, 6, 1), total: 4000, createdMs: 2),
      ];
      expect(BudgetResolver.effectiveOn(periods, DateTime(2026, 3, 15))?.id, 1);
      expect(BudgetResolver.effectiveOn(periods, DateTime(2026, 7, 15))?.id, 2);
    });

    test('起始更晚的循环期间覆盖更早的（调整预算）', () {
      final periods = [
        _p(id: 1, start: DateTime(2026, 1, 1), total: 3000),
        _p(id: 2, start: DateTime(2026, 6, 1), total: 4000),
      ];
      expect(BudgetResolver.effectiveOn(periods, DateTime(2026, 7, 1))?.id, 2);
      expect(BudgetResolver.effectiveOn(periods, DateTime(2026, 5, 1))?.id, 1);
    });

    test('一次性区间优先于每月循环', () {
      final periods = [
        _p(id: 1, start: DateTime(2026, 1, 1), total: 3000),
        _p(id: 2, start: DateTime(2026, 7, 10), end: DateTime(2026, 7, 20), recurring: false, total: 5000),
      ];
      expect(BudgetResolver.effectiveOn(periods, DateTime(2026, 7, 15))?.id, 2);
      expect(BudgetResolver.effectiveOn(periods, DateTime(2026, 7, 25))?.id, 1);
    });

    test('账本过滤：别的账本的预算不生效，通用预算都生效', () {
      final periods = [
        _p(id: 1, bookId: 9, start: DateTime(2026, 1, 1), total: 3000),
        _p(id: 2, start: DateTime(2026, 1, 1), total: 2000, createdMs: 1),
      ];
      expect(
          BudgetResolver.effectiveOn(periods, DateTime(2026, 3, 1), bookId: 5)
              ?.id,
          2);
      expect(
          BudgetResolver.effectiveOn(periods, DateTime(2026, 3, 1), bookId: 9)
              ?.id,
          1);
    });

    test('没有覆盖的期间返回 null', () {
      final periods = [
        _p(id: 1, start: DateTime(2026, 6, 1), total: 3000),
      ];
      expect(BudgetResolver.effectiveOn(periods, DateTime(2026, 5, 31)), isNull);
    });
  });

  group('BudgetResolver.monthlyTotalFor', () {
    test('每月循环直接用 total', () {
      final periods = [_p(id: 1, start: DateTime(2026, 1, 1), total: 3000)];
      expect(BudgetResolver.monthlyTotalFor(periods, 2026, 7),
          Decimal.fromInt(3000));
    });

    test('一次性区间按天摊到当月', () {
      // 6/16–7/15 共 30 天 3000 元；7 月覆盖 15 天 → 1500。
      final periods = [
        _p(
            id: 1,
            start: DateTime(2026, 6, 16),
            end: DateTime(2026, 7, 15),
            recurring: false,
            total: 3000),
      ];
      final v = BudgetResolver.monthlyTotalFor(periods, 2026, 7);
      expect(v, Decimal.parse('1500.00'));
    });
  });

  group('BudgetSuggestion', () {
    test('按收入建议 = 收入 × 80%（总预算含固定支出）', () {
      expect(BudgetSuggestion.suggestFromIncome(Decimal.fromInt(10000)),
          Decimal.fromInt(8000));
      expect(BudgetSuggestion.suggestFromIncome(Decimal.zero), isNull);
    });

    test('averageMonthlySpend 只算有记录的月份、不含本月', () {
      TransactionRecord rec(int amount, DateTime date) =>
          TransactionRecord.create(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(amount),
            categoryName: '午餐',
            accountName: '',
            toAccountName: '',
            date: date,
          );
      final now = DateTime(2026, 7, 10);
      // 近 3 个月里只有 5、6 月有支出：(3000+1000)/2 = 2000。
      final records = [
        rec(3000, DateTime(2026, 6, 5)),
        rec(1000, DateTime(2026, 5, 20)),
        rec(999, DateTime(2026, 7, 3)), // 本月，不算
        rec(999, DateTime(2026, 3, 5)), // 超 3 个月，不算
      ];
      expect(BudgetSuggestion.averageMonthlySpend(records, now: now),
          Decimal.fromInt(2000));
      expect(BudgetSuggestion.averageMonthlySpend(const [], now: now), isNull);
    });

    test('historicalWeights 只算近3个月且不含本月，按顶级归并', () {
      TransactionRecord rec(int amount, String name, DateTime date) =>
          TransactionRecord.create(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(amount),
            categoryName: name,
            accountName: '',
            toAccountName: '',
            date: date,
          );
      final now = DateTime(2026, 7, 10);
      final records = [
        rec(300, '午餐', DateTime(2026, 6, 5)), // → dining
        rec(100, '奶茶', DateTime(2026, 5, 5)), // → dining
        rec(100, '打车', DateTime(2026, 4, 5)), // → transport
        rec(999, '午餐', DateTime(2026, 7, 5)), // 本月，不算
        rec(999, '午餐', DateTime(2026, 3, 5)), // 超3个月，不算
      ];
      String? topOf(String name) => switch (name) {
            '午餐' || '奶茶' => 'dining',
            '打车' => 'transport',
            _ => null,
          };
      final w = BudgetSuggestion.historicalWeights(records,
          now: now, topKeyOfName: topOf);
      expect(w['dining'], closeTo(0.8, 0.0001));
      expect(w['transport'], closeTo(0.2, 0.0001));
    });

    test('split 整元切分且合计等于总额，零头给最大头', () {
      final out = BudgetSuggestion.split(
        total: Decimal.fromInt(1000),
        weights: {'a': 0.5, 'b': 0.3, 'c': 0.2},
      );
      expect(out['a'], Decimal.fromInt(500));
      expect(out['b'], Decimal.fromInt(300));
      expect(out['c'], Decimal.fromInt(200));
      final sum = out.values.fold(Decimal.zero, (a, b) => a + b);
      expect(sum, Decimal.fromInt(1000));

      // 除不尽的情况：331/3 权重 → 零头进最大份，总和不变。
      final odd = BudgetSuggestion.split(
        total: Decimal.fromInt(100),
        weights: {'a': 1 / 3, 'b': 1 / 3, 'c': 1 / 3},
      );
      final oddSum = odd.values.fold(Decimal.zero, (a, b) => a + b);
      expect(oddSum, Decimal.fromInt(100));
    });
  });
}
