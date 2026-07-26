import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/entry_sanity.dart';
import 'package:qingji/core/ai/natural_language_entry_parser.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/models/transaction_kind.dart';

ParsedEntry _entry({Decimal? amount, DateTime? date, double conf = 0.95}) =>
    ParsedEntry(
      amount: amount,
      kind: TransactionKind.expense,
      categoryKey: 'dining',
      note: 'x',
      date: date ?? DateTime(2026, 6, 28),
      confidence: conf,
    );

void main() {
  group('decimalToBudgetCents — 超精度金额绝不抛异常', () {
    test('2 位以内小数原样换算', () {
      expect(decimalToBudgetCents(Decimal.parse('33.33')), 3333);
      expect(decimalToBudgetCents(Decimal.parse('-12.5')), -1250);
      expect(decimalToBudgetCents(Decimal.parse('0')), 0);
    });

    test('3 位以上小数四舍五入到分（历史上这里抛 ArgumentError 会崩整个读取路径）', () {
      expect(decimalToBudgetCents(Decimal.parse('33.3333')), 3333);
      expect(decimalToBudgetCents(Decimal.parse('33.335')), 3334);
      expect(decimalToBudgetCents(Decimal.parse('1000.555')), 100056);
      expect(decimalToBudgetCents(Decimal.parse('-1000.555')), -100056);
      expect(decimalToBudgetCents(Decimal.parse('0.004')), 0);
    });
  });

  group('normalizeMoneyAmount — 入库前归一到 2 位小数', () {
    test('四舍五入', () {
      expect(normalizeMoneyAmount(Decimal.parse('33.3333')).toString(), '33.33');
      expect(normalizeMoneyAmount(Decimal.parse('33.335')).toString(), '33.34');
      expect(normalizeMoneyAmount(Decimal.parse('20')).toString(), '20');
    });
  });

  group('EntrySanity.clean — 金额与日期兜底', () {
    final now = DateTime(2026, 6, 28, 12);

    test('AA 均摊类超精度金额被归一到 2 位（100÷3 = 33.3333 → 33.33）', () {
      final cleaned =
          EntrySanity.clean(_entry(amount: Decimal.parse('33.3333')), now: now);
      expect(cleaned.amount.toString(), '33.33');
    });

    test('归一后为 0 的金额视为未识别（0.004 → null）', () {
      final cleaned =
          EntrySanity.clean(_entry(amount: Decimal.parse('0.004')), now: now);
      expect(cleaned.amount, isNull);
    });

    test('久远日期（> 400 天前）压低置信度到 0.6，强制走确认卡', () {
      final cleaned = EntrySanity.clean(
        _entry(amount: Decimal.parse('50'), date: DateTime(2020, 6, 28)),
        now: now,
      );
      expect(cleaned.confidence, 0.6);
      expect(cleaned.date, DateTime(2020, 6, 28)); // 日期保留，让用户在卡上看到并改
    });

    test('一年内的历史日期不受影响', () {
      final cleaned = EntrySanity.clean(
        _entry(amount: Decimal.parse('50'), date: DateTime(2026, 1, 1)),
        now: now,
      );
      expect(cleaned.confidence, 0.95);
    });
  });
}
