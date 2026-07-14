import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/money_format.dart';

void main() {
  tearDown(MoneyFormat.resetConfig);

  group('MoneyFormat.string', () {
    // 注：去掉千分位逗号再断言，避免 CI 默认 locale 分组差异导致脆弱。
    String normalized(Decimal d) => MoneyFormat.string(d).replaceAll(',', '');

    test('CNY 固定用 ¥ 符号，两位小数', () {
      expect(MoneyFormat.string(Decimal.fromInt(1234)).startsWith('¥'), isTrue);
      expect(normalized(Decimal.fromInt(1234)), '¥1234.00');
    });

    test('小数补齐两位', () {
      expect(normalized(Decimal.parse('12.5')), '¥12.50');
      expect(normalized(Decimal.parse('0.5')), '¥0.50');
    });

    test('零金额', () {
      expect(normalized(Decimal.zero), '¥0.00');
    });

    test('支持一位小数显示', () {
      MoneyFormat.configure(
        decimalPlaces: 1,
        integerRoundingMode: MoneyIntegerRoundingMode.round,
      );

      expect(normalized(Decimal.parse('12.56')), '¥12.6');
      expect(normalized(Decimal.fromInt(12)), '¥12.0');
    });

    test('整数显示支持四舍五入', () {
      MoneyFormat.configure(
        decimalPlaces: 0,
        integerRoundingMode: MoneyIntegerRoundingMode.round,
      );

      expect(normalized(Decimal.parse('12.49')), '¥12');
      expect(normalized(Decimal.parse('12.50')), '¥13');
    });

    test('整数显示支持向上取整', () {
      MoneyFormat.configure(
        decimalPlaces: 0,
        integerRoundingMode: MoneyIntegerRoundingMode.ceil,
      );

      expect(normalized(Decimal.parse('12.01')), '¥13');
      expect(normalized(Decimal.parse('12.00')), '¥12');
    });

    test('整数显示支持向下取整', () {
      MoneyFormat.configure(
        decimalPlaces: 0,
        integerRoundingMode: MoneyIntegerRoundingMode.floor,
      );

      expect(normalized(Decimal.parse('12.99')), '¥12');
    });

    test('整数显示支持直接取整', () {
      MoneyFormat.configure(
        decimalPlaces: 0,
        integerRoundingMode: MoneyIntegerRoundingMode.truncate,
      );

      expect(normalized(Decimal.parse('12.99')), '¥12');
    });
  });

  group('MoneyFormat.toDouble', () {
    test('精确转换', () {
      expect(MoneyFormat.toDouble(Decimal.parse('3.14')), 3.14);
      expect(MoneyFormat.toDouble(Decimal.fromInt(100)), 100.0);
      expect(MoneyFormat.toDouble(Decimal.zero), 0.0);
    });
  });
}
