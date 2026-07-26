import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/transaction_time.dart';
import 'package:qingji/views/settings/import_export_view.dart';

void main() {
  test('肥喵 CSV 把时间精度紧跟在日期列后', () {
    final header = feimiaoCsvHeaderForTest();

    expect(header.take(3), ['日期', '时间精度', '到账日期']);
  });

  test('新版肥喵 CSV 按 storageKey 往返全部时间精度', () {
    final header = feimiaoCsvHeaderForTest();
    for (final precision in TransactionTimePrecision.values) {
      final rows = parseFeimiaoRowsForTest([
        header,
        _rowFor(header, timePrecision: precision.storageKey),
      ]);

      expect(rows, isNotNull);
      expect(rows, hasLength(1));
      expect(rows!.single.timePrecision, precision);
      expect(rows.single.date, DateTime(2026, 7, 13));
    }
  });

  test('旧肥喵 CSV 缺少时间精度列时回退 legacyUnknown', () {
    final oldHeader = feimiaoCsvHeaderForTest()
        .where((column) => column != '时间精度')
        .toList(growable: false);

    final rows = parseFeimiaoRowsForTest([
      oldHeader,
      _rowFor(oldHeader),
    ]);

    expect(rows, isNotNull);
    expect(rows!.single.timePrecision, TransactionTimePrecision.legacyUnknown);
    expect(rows.single.date, DateTime(2026, 7, 13));
  });

  test('未知时间精度值安全回退 legacyUnknown', () {
    final header = feimiaoCsvHeaderForTest();

    final rows = parseFeimiaoRowsForTest([
      header,
      _rowFor(header, timePrecision: 'future_precision'),
    ]);

    expect(rows, isNotNull);
    expect(rows!.single.timePrecision, TransactionTimePrecision.legacyUnknown);
  });

  test('导出日期隐藏不可靠的午夜但保留真实午夜', () {
    final midnight = DateTime(2026, 7, 13);

    expect(
      formatFeimiaoTransactionDateForTest(
        midnight,
        TransactionTimePrecision.dateOnly,
      ),
      '2026-07-13',
    );
    expect(
      formatFeimiaoTransactionDateForTest(
        midnight,
        TransactionTimePrecision.legacyUnknown,
      ),
      '2026-07-13',
    );
    expect(
      formatFeimiaoTransactionDateForTest(
        midnight,
        TransactionTimePrecision.exact,
      ),
      '2026-07-13 00:00',
    );
    expect(
      formatFeimiaoTransactionDateForTest(
        DateTime(2026, 7, 13, 9, 6),
        TransactionTimePrecision.legacyUnknown,
      ),
      '2026-07-13 09:06',
    );
  });

  test('本 App 导出的 CSV 可跨 isolate 重新导入', () async {
    final header = feimiaoCsvHeaderForTest();
    final csv = const ListToCsvConverter().convert([
      header,
      _rowFor(
        header,
        timePrecision: TransactionTimePrecision.exact.storageKey,
      ),
    ]);

    final rows = await parseFeimiaoCsvInBackgroundForTest('\ufeff$csv');

    expect(rows, isNotNull);
    expect(rows, hasLength(1));
    expect(rows!.single.uuid, '1234567890abcdef1234567890abcdef');
    expect(rows.single.amount.toString(), '30');
    expect(rows.single.categoryKey, 'subscription');
    expect(rows.single.timePrecision, TransactionTimePrecision.exact);
  });
}

List<String> _rowFor(
  List<String> header, {
  String timePrecision = '',
}) {
  final values = <String, String>{
    '日期': '2026-07-13 00:00',
    '时间精度': timePrecision,
    '到账日期': '',
    '到账日期质量': '',
    '到账账户': '',
    '到账账户质量': '',
    '事件类型': 'expense',
    '类型': '支出',
    '分类': '虚拟充值',
    '分类Key': 'subscription',
    '净额': '30',
    '原始金额': '30',
    '已退款': '0',
    '计入收支': '是',
    '账户': '现金',
    '转入账户': '',
    '备注': '原神充值',
    '标签': '',
    '可报销': '否',
    '记录类型': '账单',
    '交易UUID': '1234567890abcdef1234567890abcdef',
    '退款归属UUID': '',
  };
  return [for (final column in header) values[column] ?? ''];
}
