import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/settings/import_export_view.dart';

void main() {
  const books = [
    BookEntity(id: 1, uuid: 'total', name: '总账本'),
    BookEntity(id: 2, uuid: 'business', name: '生意'),
    BookEntity(id: 3, uuid: 'project', name: '项目, A|"秋季"'),
  ];

  test('导出两场景保留UUID与名称配对，总账本不进入关联', () {
    final cells = feimiaoBookAssociationCellsForTest(
      books: books,
      bookIds: [3, 1, 2, 3],
      defaultBookId: 1,
    );
    expect(jsonDecode(cells.uuids), ['business', 'project']);
    expect(jsonDecode(cells.names), ['生意', '项目, A|"秋季"']);
  });

  test('仅总账本显式导出空数组，而非省略关联信息', () {
    final cells = feimiaoBookAssociationCellsForTest(
      books: books,
      bookIds: [1],
      defaultBookId: 1,
    );
    expect(cells.uuids, '[]');
    expect(cells.names, '[]');
    final imported = _parse({'账本UUID': cells.uuids, '账本名称': cells.names});
    expect(imported.bookUuids, isEmpty);
    expect(imported.bookNames, isEmpty);
  });

  test('CSV跨isolate保留特殊字符与多个场景关联', () async {
    final cells = feimiaoBookAssociationCellsForTest(
      books: books,
      bookIds: [2, 3],
      defaultBookId: 1,
    );
    final header = feimiaoCsvHeaderForTest();
    final csv = const ListToCsvConverter().convert([
      header,
      _row(header, {'账本UUID': cells.uuids, '账本名称': cells.names}),
    ]);
    final rows = await parseFeimiaoCsvInBackgroundForTest('\ufeff$csv');
    expect(rows!.single.bookUuids, ['business', 'project']);
    expect(rows.single.bookNames, ['生意', '项目, A|"秋季"']);
    expect(rows.single.uuid, 'purchase');
    expect(rows.single.amount.toString(), '100');
  });

  test('旧CSV无关联字段保持null，不能解释成移除既有场景', () {
    final header = feimiaoCsvHeaderForTest()
        .where((name) => name != '账本UUID' && name != '账本名称')
        .toList();
    final row = parseFeimiaoRowsForTest([header, _row(header, {})])!.single;
    expect(row.bookUuids, isNull);
    expect(row.bookNames, isNull);
  });

  test('可选列空白保持未知，名称相同但UUID不同仍保留两条供事务判定', () {
    final blank = _parse({});
    expect(blank.bookUuids, isNull);
    expect(blank.bookNames, isNull);
    final duplicatedNames = _parse({
      '账本UUID': '["uuid-a","uuid-b"]',
      '账本名称': '["项目","项目"]',
    });
    expect(duplicatedNames.bookUuids, ['uuid-a', 'uuid-b']);
    expect(duplicatedNames.bookNames, ['项目', '项目']);
  });

  test('iOS可选关联的JSON null按旧格式处理而不是显式移出', () {
    final row = _parse({'账本UUID': 'null', '账本名称': 'null'});
    expect(row.bookUuids, isNull);
    expect(row.bookNames, isNull);
  });

  test('只有名称列的文件保留名称，不猜测或伪造UUID', () {
    final header =
        feimiaoCsvHeaderForTest().where((name) => name != '账本UUID').toList();
    final row = parseFeimiaoRowsForTest([
      header,
      _row(header, {'账本名称': '["生意"]'}),
    ])!
        .single;
    expect(row.bookUuids, isNull);
    expect(row.bookNames, ['生意']);
  });

  test('无效JSON、非数组、非字符串项和不配对数组拒绝导入', () {
    for (final value in ['not-json', '{}', '[1]', '[null]']) {
      expect(() => _parse({'账本UUID': value}), throwsFormatException);
    }
    expect(
      () => _parse({'账本UUID': '["business"]', '账本名称': '[]'}),
      throwsFormatException,
    );
  });

  test('丢失账本元数据时拒绝导出，避免静默丢掉关联', () {
    expect(
      () => feimiaoBookAssociationCellsForTest(
        books: books,
        bookIds: [2, 99],
        defaultBookId: 1,
      ),
      throwsFormatException,
    );
  });
}

FeimiaoImportRow _parse(Map<String, String> values) {
  final header = feimiaoCsvHeaderForTest();
  return parseFeimiaoRowsForTest([header, _row(header, values)])!.single;
}

List<String> _row(List<String> header, Map<String, String> values) {
  final all = {
    '日期': '2026-10-23',
    '类型': '支出',
    '净额': '100',
    '原始金额': '100',
    '已退款': '0',
    '计入收支': '是',
    '交易UUID': 'purchase',
    ...values,
  };
  return [for (final name in header) all[name] ?? ''];
}
