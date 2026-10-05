import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_suggestion.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';

void main() {
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

    test('平均建议只使用人民币净额，不把外币当人民币相加', () {
      TransactionRecord rec(String amount, String currency) =>
          TransactionRecord.create(
            kind: TransactionKind.expense,
            amount: Decimal.parse(amount),
            categoryName: '午餐',
            accountName: '',
            toAccountName: '',
            date: DateTime(2026, 6, 5),
            currencyCode: currency,
          );
      expect(
          BudgetSuggestion.averageMonthlySpend([
            rec('100', 'CNY'),
            rec('900', 'USD'),
            rec('0', 'CNY'),
          ], now: DateTime(2026, 7, 10)),
          Decimal.fromInt(100));
      expect(
          BudgetSuggestion.averageMonthlySpend([rec('900', 'USD')],
              now: DateTime(2026, 7, 10)),
          isNull);
    });

    test('平均建议的整数元四舍五入边界不丢分', () {
      TransactionRecord rec(String amount, int month) =>
          TransactionRecord.create(
            kind: TransactionKind.expense,
            amount: Decimal.parse(amount),
            categoryName: '午餐',
            accountName: '',
            toAccountName: '',
            date: DateTime(2026, month, 5),
          );
      expect(
          BudgetSuggestion.averageMonthlySpend([
            rec('149.49', 5),
            rec('149.49', 6),
          ], now: DateTime(2026, 7, 10)),
          Decimal.fromInt(149));
      expect(
          BudgetSuggestion.averageMonthlySpend([
            rec('149.49', 5),
            rec('149.51', 6),
          ], now: DateTime(2026, 7, 10)),
          Decimal.fromInt(150));
    });

    test('页面建议先取整元再取整百，低额至少100，没有记录不猜数', () {
      TransactionRecord rec(String amount) => TransactionRecord.create(
            kind: TransactionKind.expense,
            amount: Decimal.parse(amount),
            date: DateTime(2026, 6, 5),
          );
      int? suggested(String amount) => BudgetSuggestion.suggestedMonthlyYuan(
            [rec(amount)],
            now: DateTime(2026, 7, 10),
          );
      expect(suggested('149.49'), 100);
      expect(suggested('149.50'), 200);
      expect(suggested('0.01'), 100);
      expect(
          BudgetSuggestion.suggestedMonthlyYuan([], now: DateTime(2026, 7, 10)),
          isNull);
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
