import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/ai/natural_language_entry_parser.dart';

// 固定参考时间：2026-06-12 12:00（对应 Swift 测试的 now）。
final _now = DateTime(2026, 6, 12, 12);

void main() {
  group('NaturalLanguageEntryParser', () {
    test('taxi yesterday', () {
      final entry = NaturalLanguageEntryParser.parse('昨天打车23块', at: _now);
      expect(entry.amount, Decimal.fromInt(23));
      expect(entry.kind, TransactionKind.expense);
      expect(entry.categoryKey, 'transport');
      expect(entry.date.day, 11); // 昨天 = 6月11日
    });

    test('colloquial kuai amount', () {
      final entry = NaturalLanguageEntryParser.parse('午饭23块5', at: _now);
      expect(entry.amount, Decimal.parse('23.5'));
      expect(entry.categoryKey, 'dining');
    });

    test('currency symbol', () {
      final entry = NaturalLanguageEntryParser.parse('超市 ¥128.40', at: _now);
      expect(entry.amount, Decimal.parse('128.4'));
      expect(entry.categoryKey, 'groceries');
    });

    test('last number fallback', () {
      // "2杯"不是金额，应取最后的 58
      final entry = NaturalLanguageEntryParser.parse('买了2杯咖啡58', at: _now);
      expect(entry.amount, Decimal.fromInt(58));
      expect(entry.categoryKey, 'dining');
    });

    test('income salary', () {
      final entry = NaturalLanguageEntryParser.parse('发工资20000', at: _now);
      expect(entry.kind, TransactionKind.income);
      expect(entry.categoryKey, 'salary');
      expect(entry.amount, Decimal.fromInt(20000));
    });

    test('refund is income', () {
      final entry = NaturalLanguageEntryParser.parse('淘宝退款35.5元', at: _now);
      expect(entry.kind, TransactionKind.income);
      expect(entry.categoryKey, 'refund');
    });

    test('groceries beats shopping', () {
      // "买菜"应命中买菜超市而不是购物的"买"
      final entry = NaturalLanguageEntryParser.parse('买菜45', at: _now);
      expect(entry.categoryKey, 'groceries');
    });

    test('no amount', () {
      final entry = NaturalLanguageEntryParser.parse('今天吃了顿好的', at: _now);
      expect(entry.amount, isNull);
      expect(entry.categoryKey, 'dining');
    });
  });

  group('PaymentScreenshotParser', () {
    test('WeChat payment screenshot', () {
      const ocr = '''
支付成功
-88.50
老王煎饼店
支付方式 零钱
余额 12.30
''';
      expect(
        PaymentScreenshotParser.extractAmount(fromOCRText: ocr),
        Decimal.parse('88.5'),
      );
    });

    test('currency marked amount wins', () {
      const ocr = '''
订单编号 20260612001
¥1,299.00
积分 5000
''';
      expect(
        PaymentScreenshotParser.extractAmount(fromOCRText: ocr),
        Decimal.fromInt(1299),
      );
    });

    test('no amount', () {
      expect(
        PaymentScreenshotParser.extractAmount(fromOCRText: '支付失败，请重试'),
        isNull,
      );
    });
  });
}
