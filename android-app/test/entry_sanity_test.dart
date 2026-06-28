import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/entry_sanity.dart';
import 'package:qingji/core/ai/natural_language_entry_parser.dart';
import 'package:qingji/core/models/transaction_kind.dart';

ParsedEntry _mk({Decimal? amount, DateTime? date, double conf = 0.9}) =>
    ParsedEntry(
      amount: amount,
      kind: TransactionKind.expense,
      categoryKey: 'dining',
      note: 'x',
      date: date ?? DateTime(2026, 6, 28),
      confidence: conf,
    );

void main() {
  final now = DateTime(2026, 6, 28, 12);

  group('EntrySanity.clean — 金额', () {
    test('金额≤0 → 视为未识别(null)', () {
      expect(EntrySanity.clean(_mk(amount: Decimal.zero), now: now).amount,
          isNull);
    });
    test('金额大得离谱(>1亿) → null', () {
      expect(
          EntrySanity.clean(_mk(amount: Decimal.parse('999999999')), now: now)
              .amount,
          isNull);
    });
    test('正常金额保留', () {
      expect(
          EntrySanity.clean(_mk(amount: Decimal.parse('25.5')), now: now)
              .amount,
          Decimal.parse('25.5'));
    });
  });

  group('EntrySanity.clean — 日期', () {
    test('未来日期 → 收敛到今天', () {
      final r = EntrySanity.clean(
          _mk(amount: Decimal.one, date: DateTime(2026, 7, 1)),
          now: now);
      expect(r.date.year, 2026);
      expect(r.date.month, 6);
      expect(r.date.day, 28);
    });
    test('过去/今天日期保留', () {
      final r = EntrySanity.clean(
          _mk(amount: Decimal.one, date: DateTime(2026, 6, 20)),
          now: now);
      expect(r.date, DateTime(2026, 6, 20));
    });
  });

  test('置信度 clamp 到 0~1', () {
    expect(EntrySanity.clean(_mk(amount: Decimal.one, conf: 1.8), now: now).confidence,
        1.0);
    expect(
        EntrySanity.clean(_mk(amount: Decimal.one, conf: -0.5), now: now)
            .confidence,
        0.0);
  });
}
