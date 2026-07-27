import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/assets/credit_card_terms.dart';

void main() {
  group('CreditCardTerms.compute 输入校验', () {
    test('账单日或还款日缺失/非法 → null', () {
      final now = DateTime(2026, 3, 10);
      expect(
        CreditCardTerms.compute(
            statementDay: null, repaymentDay: 10, now: now),
        isNull,
      );
      expect(
        CreditCardTerms.compute(
            statementDay: 25, repaymentDay: null, now: now),
        isNull,
      );
      expect(
        CreditCardTerms.compute(statementDay: 0, repaymentDay: 10, now: now),
        isNull,
      );
      expect(
        CreditCardTerms.compute(statementDay: 25, repaymentDay: 32, now: now),
        isNull,
      );
    });
  });

  group('账单周期', () {
    test('周期跨月：账单日 25，今天 3/10 → 周期 2/26..3/25', () {
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 3, 10),
      )!;
      expect(terms.cycleStart, DateTime(2026, 2, 26));
      expect(terms.cycleEnd, DateTime(2026, 3, 25));
    });

    test('今天恰是账单日：消费入当期账单（周期止于今天）', () {
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 3, 25),
      )!;
      expect(terms.cycleStart, DateTime(2026, 2, 26));
      expect(terms.cycleEnd, DateTime(2026, 3, 25));
    });

    test('账单日次日开新周期：今天 3/26 → 周期 3/26..4/25', () {
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 3, 26),
      )!;
      expect(terms.cycleStart, DateTime(2026, 3, 26));
      expect(terms.cycleEnd, DateTime(2026, 4, 25));
    });

    test('短月 clamp：账单日 30，今天 2026/2/15 → 周期止 2/28（非闰年）', () {
      final terms = CreditCardTerms.compute(
        statementDay: 30,
        repaymentDay: 15,
        now: DateTime(2026, 2, 15),
      )!;
      expect(terms.cycleEnd, DateTime(2026, 2, 28));
      // 上个账单日 = 1/30，周期起 = 1/31。
      expect(terms.cycleStart, DateTime(2026, 1, 31));
    });

    test('跨年：账单日 25，今天 12/28 → 周期 12/26..次年 1/25', () {
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 12, 28),
      )!;
      expect(terms.cycleStart, DateTime(2026, 12, 26));
      expect(terms.cycleEnd, DateTime(2027, 1, 25));
      // 本期还款日在次年 2 月（还款日 10 <= 账单日 25 → 次月）。
      expect(terms.purchaseRepaymentDate, DateTime(2027, 2, 10));
    });
  });

  group('还款日归属', () {
    test('还款日 > 账单日：还款在账单当月（5 号出账 20 号还）', () {
      final terms = CreditCardTerms.compute(
        statementDay: 5,
        repaymentDay: 20,
        now: DateTime(2026, 3, 3),
      )!;
      expect(terms.cycleEnd, DateTime(2026, 3, 5));
      expect(terms.purchaseRepaymentDate, DateTime(2026, 3, 20));
    });

    test('还款日 <= 账单日：还款在账单次月（25 号出账 10 号还）', () {
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 3, 10),
      )!;
      expect(terms.purchaseRepaymentDate, DateTime(2026, 4, 10));
    });

    test('还款日 == 账单日：按次月还', () {
      final terms = CreditCardTerms.compute(
        statementDay: 15,
        repaymentDay: 15,
        now: DateTime(2026, 3, 1),
      )!;
      expect(terms.cycleEnd, DateTime(2026, 3, 15));
      expect(terms.purchaseRepaymentDate, DateTime(2026, 4, 15));
    });

    test('还款日短月 clamp：账单日 31 还款日 31 → 1/31 账单 2/28 还', () {
      final terms = CreditCardTerms.compute(
        statementDay: 31,
        repaymentDay: 31,
        now: DateTime(2026, 1, 31),
      )!;
      expect(terms.cycleEnd, DateTime(2026, 1, 31));
      expect(terms.purchaseRepaymentDate, DateTime(2026, 2, 28));
    });
  });

  group('下个还款日与免息天数', () {
    test('上期账单还款日未过 → 下个还款日是上期的，免息按本期算', () {
      // 账单日 25 还款日 10：今天 4/1，上期账单 3/25 的还款日 4/10 未到。
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 4, 1),
      )!;
      expect(terms.nextRepaymentDate, DateTime(2026, 4, 10));
      expect(terms.purchaseRepaymentDate, DateTime(2026, 5, 10));
      expect(terms.interestFreeDays, 39); // 4/1 → 5/10
    });

    test('上期还款日已过 → 下个还款日就是本期还款日', () {
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 4, 15),
      )!;
      expect(terms.nextRepaymentDate, DateTime(2026, 5, 10));
      expect(terms.nextRepaymentDate, terms.purchaseRepaymentDate);
    });

    test('今天是还款日当天：算「未过」，下个还款日 = 今天', () {
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 4, 10),
      )!;
      expect(terms.nextRepaymentDate, DateTime(2026, 4, 10));
    });

    test('免息期最长：账单日次日消费（25 出账 10 还 → 45 天）', () {
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 3, 26),
      )!;
      // 3/26 消费 → 4/25 出账 → 5/10 还款。
      expect(terms.purchaseRepaymentDate, DateTime(2026, 5, 10));
      expect(terms.interestFreeDays, 45);
    });

    test('免息期最短：账单日当天消费（25 出账 10 还 → 16 天）', () {
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 3, 25),
      )!;
      expect(terms.purchaseRepaymentDate, DateTime(2026, 4, 10));
      expect(terms.interestFreeDays, 16);
    });

    test('now 带时分秒不影响天数口径', () {
      final terms = CreditCardTerms.compute(
        statementDay: 25,
        repaymentDay: 10,
        now: DateTime(2026, 3, 25, 23, 59, 58),
      )!;
      expect(terms.interestFreeDays, 16);
      expect(terms.cycleEnd, DateTime(2026, 3, 25));
    });
  });
}
