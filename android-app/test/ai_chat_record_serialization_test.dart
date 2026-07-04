import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/natural_language_entry_parser.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';

/// 记账卡跨重启恢复：编码→解码往返一致，坏数据不崩。
void main() {
  test('记账卡 JSON 往返：entries/cats/txnIds/saved/deleted 全一致', () {
    final entries = [
      ParsedEntry(
        amount: Decimal.parse('23.88'),
        kind: TransactionKind.expense,
        categoryKey: 'snacks',
        note: '烧烤',
        date: DateTime(2026, 7, 4),
        confidence: 0.95,
      ),
      ParsedEntry(
        amount: null, // 没认出金额的占位条目
        kind: TransactionKind.income,
        categoryKey: null,
        note: '待补金额',
        date: DateTime(2026, 7, 1),
      ),
    ];
    final json = encodeRecordCard(
      entries: entries,
      catIds: [42, null],
      txnIds: [1001, null],
      saved: true,
      feedback: '记好啦',
      deleted: {1},
    );

    final d = decodeRecordCard(json);
    expect(d.entries, hasLength(2));
    expect(d.entries[0].amount, Decimal.parse('23.88'));
    expect(d.entries[0].kind, TransactionKind.expense);
    expect(d.entries[0].categoryKey, 'snacks');
    expect(d.entries[0].note, '烧烤');
    expect(d.entries[0].date, DateTime(2026, 7, 4));
    expect(d.entries[1].amount, isNull);
    expect(d.entries[1].kind, TransactionKind.income);
    expect(d.catIds, [42, null]);
    expect(d.txnIds, [1001, null]);
    expect(d.saved, isTrue);
    expect(d.feedback, '记好啦');
    expect(d.deleted, {1});
  });

  test('坏 JSON 抛出（调用方 try/catch 跳过该卡，不崩恢复流程）', () {
    expect(() => decodeRecordCard('{不是合法json'), throwsA(anything));
  });
}
