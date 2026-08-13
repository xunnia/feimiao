import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_data_trimmer.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';

void main() {
  group('AiDataTrimmer', () {
    final testRecords = [
      TransactionRecord(
        id: '1',
        date: DateTime(2025, 1, 15),
        kind: TransactionKind.expense,
        amount: Decimal.parse('12345'),
        currencyCode: 'CNY',
        categoryName: '食品餐饮',
        note: '午餐外卖 13812345678',
        accountId: 1,
      ),
      TransactionRecord(
        id: '2',
        date: DateTime(2025, 1, 16),
        kind: TransactionKind.expense,
        amount: Decimal.parse('50000'),
        currencyCode: 'CNY',
        categoryName: '购物',
        note: '购物',
        accountId: 1,
      ),
      TransactionRecord(
        id: '3',
        date: DateTime(2024, 12, 20),
        kind: TransactionKind.income,
        amount: Decimal.parse('1000000'),
        currencyCode: 'CNY',
        categoryName: '工资',
        note: '工资',
        accountId: 1,
      ),
      TransactionRecord(
        id: '4',
        date: DateTime(2025, 1, 18),
        kind: TransactionKind.expense,
        amount: Decimal.parse('8000'),
        currencyCode: 'CNY',
        categoryName: '食品餐饮',
        note: '晚餐',
        accountId: 1,
      ),
    ];

    test('trimForMonthlyAnalysis 应该只返回指定月份的数据', () {
      final result = AiDataTrimmer.trimForMonthlyAnalysis(
        allRecords: testRecords,
        year: 2025,
        month: 1,
      );

      expect(result.length, 3);
      expect(result[0]['date'], '2025-01-18');
      expect(result[1]['date'], '2025-01-16');
      expect(result[2]['date'], '2025-01-15');
    });

    test('trimForMonthlyAnalysis 应该四舍五入金额到整数元', () {
      final result = AiDataTrimmer.trimForMonthlyAnalysis(
        allRecords: testRecords,
        year: 2025,
        month: 1,
      );

      expect(result[2]['amount'], 123);
      expect(result[1]['amount'], 500);
      expect(result[0]['amount'], 80);
    });

    test('trimForMonthlyAnalysis 应该脱敏手机号', () {
      final result = AiDataTrimmer.trimForMonthlyAnalysis(
        allRecords: testRecords,
        year: 2025,
        month: 1,
      );

      final noteWithPhone = result[2]['note'] as String;
      expect(noteWithPhone, contains('138****5678'));
      expect(noteWithPhone, isNot(contains('13812345678')));
    });

    test('trimForMonthlyAnalysis 应该限制最大条数', () {
      final manyRecords = List.generate(
        1000,
        (i) => TransactionRecord(
          id: 'r$i',
          date: DateTime(2025, 1, i % 28 + 1),
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(10000),
          currencyCode: 'CNY',
          categoryName: '食品餐饮',
          note: '',
          accountId: 1,
        ),
      );

      final result = AiDataTrimmer.trimForMonthlyAnalysis(
        allRecords: manyRecords,
        year: 2025,
        month: 1,
        maxRecords: 100,
      );

      expect(result.length, 100);
    });

    test('trimForCategoryAnalysis 应该只返回指定分类的数据', () {
      final result = AiDataTrimmer.trimForCategoryAnalysis(
        allRecords: testRecords,
        categoryName: '食品餐饮',
      );

      expect(result.length, 2);
      expect(result.every((r) => r['date'] != null), true);
      expect(result.every((r) => r['amount'] != null), true);
    });

    test('buildCategorySummary 应该正确汇总分类金额', () {
      final summary = AiDataTrimmer.buildCategorySummary(
        records: testRecords,
        year: 2025,
        month: 1,
      );

      expect(summary['year'], 2025);
      expect(summary['month'], 1);
      expect(summary['expense_by_category']['食品餐饮'], 123 + 80);
      expect(summary['expense_by_category']['购物'], 500);
      expect(summary['total_expense'], 123 + 500 + 80);
    });

    test('estimateTokens 应该粗略估算 token 数', () {
      final chineseText = '你好世界';
      final englishText = 'Hello World';

      final chineseTokens = AiDataTrimmer.estimateTokens(chineseText);
      final englishTokens = AiDataTrimmer.estimateTokens(englishText);

      expect(chineseTokens, greaterThan(0));
      expect(englishTokens, greaterThan(0));
      expect(chineseTokens, greaterThan(englishTokens));
    });

    test('_sanitizeNote 应该截断过长备注', () {
      final longNote = '这是一个非常长的备注' * 20;
      final record = TransactionRecord(
        id: '99',
        date: DateTime.now(),
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(10000),
        currencyCode: 'CNY',
        categoryName: '食品餐饮',
        note: longNote,
        accountId: 1,
      );

      final result = AiDataTrimmer.trimForGeneralQuery(
        allRecords: [record],
        maxRecords: 10,
      );

      final note = result[0]['note'] as String;
      expect(note.length, lessThanOrEqualTo(53));
      expect(note, endsWith('...'));
    });

    test('_sanitizeNote 不应误伤订单号中的 11 位数字', () {
      // 订单号通常是更长的数字串，不应被当作手机号脱敏
      final record = TransactionRecord(
        id: '100',
        date: DateTime.now(),
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(10000),
        currencyCode: 'CNY',
        categoryName: '购物',
        note: '订单号 123456789012345 已支付',
        accountId: 1,
      );

      final result = AiDataTrimmer.trimForGeneralQuery(
        allRecords: [record],
        maxRecords: 10,
      );

      final note = result[0]['note'] as String;
      // 15位订单号不应被脱敏
      expect(note, contains('123456789012345'));
      expect(note, isNot(contains('****')));
    });

    test('_sanitizeNote 应该脱敏独立的手机号', () {
      final record = TransactionRecord(
        id: '101',
        date: DateTime.now(),
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(10000),
        currencyCode: 'CNY',
        categoryName: '转账',
        note: '转账给 13987654321',
        accountId: 1,
      );

      final result = AiDataTrimmer.trimForGeneralQuery(
        allRecords: [record],
        maxRecords: 10,
      );

      final note = result[0]['note'] as String;
      expect(note, contains('139****4321'));
      expect(note, isNot(contains('13987654321')));
    });

    test('_sanitizeNote 不应误伤身份证号前后有数字的情况', () {
      // 如果身份证号嵌在更长的数字串中，不应脱敏
      final record = TransactionRecord(
        id: '102',
        date: DateTime.now(),
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(10000),
        currencyCode: 'CNY',
        categoryName: '其他',
        note: '编号 9110101199001011234567',
        accountId: 1,
      );

      final result = AiDataTrimmer.trimForGeneralQuery(
        allRecords: [record],
        maxRecords: 10,
      );

      final note = result[0]['note'] as String;
      // 23位数字串不应被脱敏
      expect(note, contains('9110101199001011234567'));
      expect(note, isNot(contains('********')));
    });

    test('_sanitizeNote 应该脱敏独立的身份证号', () {
      final record = TransactionRecord(
        id: '103',
        date: DateTime.now(),
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(10000),
        currencyCode: 'CNY',
        categoryName: '其他',
        note: '证件 110101199001011234',
        accountId: 1,
      );

      final result = AiDataTrimmer.trimForGeneralQuery(
        allRecords: [record],
        maxRecords: 10,
      );

      final note = result[0]['note'] as String;
      expect(note, contains('110101********1234'));
      expect(note, isNot(contains('110101199001011234')));
    });
  });
}
