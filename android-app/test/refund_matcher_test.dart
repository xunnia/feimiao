import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/refund_matcher.dart';

void main() {
  final now = DateTime(2026, 7, 12, 12);

  RefundCandidate candidate({
    required int id,
    required String label,
    int amount = 100,
    int refunded = 0,
    DateTime? date,
  }) =>
      RefundCandidate(
        id: id,
        label: label,
        amount: Decimal.fromInt(amount),
        refunded: Decimal.fromInt(refunded),
        date: date ?? DateTime(2026, 6, 3),
      );

  test('唯一商户和商品强匹配时返回原订单', () {
    final result = RefundMatcher.match(
      text: '上个月淘宝买的连衣裙退款30元',
      amount: Decimal.fromInt(30),
      now: now,
      candidates: [
        candidate(id: 1, label: '淘宝买连衣裙'),
        candidate(id: 2, label: '瑞幸咖啡'),
      ],
    );

    expect(result.status, RefundMatchStatus.matched);
    expect(result.candidate?.id, 1);
    expect(result.amount, Decimal.fromInt(30));
  });

  test('两个同样强的候选保持歧义，不选择较新的那笔', () {
    final result = RefundMatcher.match(
      text: '淘宝连衣裙退款30',
      amount: Decimal.fromInt(30),
      now: now,
      candidates: [
        candidate(id: 1, label: '淘宝连衣裙'),
        candidate(id: 2, label: '淘宝连衣裙'),
      ],
    );

    expect(result.status, RefundMatchStatus.ambiguous);
    expect(result.candidates.map((item) => item.id), containsAll([1, 2]));
  });

  test('没有商户或商品匹配时不落账', () {
    final result = RefundMatcher.match(
      text: '京东耳机退款30',
      amount: Decimal.fromInt(30),
      now: now,
      candidates: [candidate(id: 1, label: '淘宝连衣裙')],
    );

    expect(result.status, RefundMatchStatus.noMatch);
    expect(result.candidate, isNull);
  });

  test('退款超过剩余可退金额时返回明确边界', () {
    final result = RefundMatcher.match(
      text: '淘宝连衣裙退款30',
      amount: Decimal.fromInt(30),
      now: now,
      candidates: [
        candidate(id: 1, label: '淘宝连衣裙', amount: 100, refunded: 80),
      ],
    );

    expect(result.status, RefundMatchStatus.exceedsRemaining);
    expect(result.candidate?.remaining, Decimal.fromInt(20));
  });

  test('退款意图缺金额时追问，不把它交给普通收入保存', () {
    final result = RefundMatcher.match(
      text: '淘宝连衣裙已经退款了',
      amount: null,
      now: now,
      candidates: [candidate(id: 1, label: '淘宝连衣裙')],
    );

    expect(result.status, RefundMatchStatus.missingAmount);
    expect(result.isRefundMutation, isTrue);
  });

  test('只有完整日期没有金额时不会把日期误认成退款金额', () {
    const text = '7月3日淘宝连衣裙那笔退款';
    final result = RefundMatcher.match(
      text: text,
      amount: RefundMatcher.extractAmount(text),
      now: now,
      candidates: [
        candidate(
          id: 1,
          label: '淘宝连衣裙',
          date: DateTime(2026, 7, 3),
        ),
      ],
    );

    expect(result.status, RefundMatchStatus.missingAmount);
  });

  test('日期与金额同时存在时只提取退款金额', () {
    expect(
      RefundMatcher.extractAmount('7月3日淘宝连衣裙退款30元'),
      Decimal.fromInt(30),
    );
  });

  test('“本月退款多少”是查询，不误判成退款写入', () {
    final result = RefundMatcher.match(
      text: '本月退款多少',
      // 即便上游错误地把“月”前数字当金额，查询词仍必须优先拦住。
      amount: Decimal.fromInt(7),
      now: now,
      candidates: [candidate(id: 1, label: '淘宝连衣裙')],
    );

    expect(result.status, RefundMatchStatus.notRefundMutation);
    expect(result.isRefundMutation, isFalse);
  });

  test('明确日期下唯一的“那笔”可以安全匹配', () {
    final result = RefundMatcher.match(
      text: '7月3日那笔退款20',
      amount: Decimal.fromInt(20),
      now: now,
      candidates: [
        candidate(id: 1, label: '早餐', date: DateTime(2026, 7, 3)),
        candidate(id: 2, label: '午饭', date: DateTime(2026, 7, 4)),
      ],
    );

    expect(result.status, RefundMatchStatus.matched);
    expect(result.candidate?.id, 1);
  });
}
