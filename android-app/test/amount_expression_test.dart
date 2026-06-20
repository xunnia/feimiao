import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/amount_expression.dart';

void main() {
  group('AmountExpression 基础输入', () {
    test('新建时为空、合计为 0、显示 0', () {
      final e = AmountExpression();
      expect(e.isEmpty, isTrue);
      expect(e.isCompound, isFalse);
      expect(e.value, Decimal.zero);
      expect(e.displayText, '0');
    });

    test('连续输入数字', () {
      final e = AmountExpression();
      e.insertDigit('1');
      e.insertDigit('2');
      expect(e.value, Decimal.fromInt(12));
      expect(e.displayText, '12');
      expect(e.isEmpty, isFalse);
    });

    test('小数点输入', () {
      final e = AmountExpression();
      e.insertDigit('1');
      e.insertDigit('2');
      e.insertDot();
      e.insertDigit('5');
      expect(e.value, Decimal.parse('12.5'));
      expect(e.displayText, '12.5');
    });

    test('小数最多两位，第三位被忽略', () {
      final e = AmountExpression();
      e.insertDigit('1');
      e.insertDot();
      e.insertDigit('2');
      e.insertDigit('3');
      e.insertDigit('4'); // 应被忽略
      expect(e.displayText, '1.23');
      expect(e.value, Decimal.parse('1.23'));
    });

    test('重复小数点被忽略', () {
      final e = AmountExpression();
      e.insertDigit('5');
      e.insertDot();
      e.insertDot(); // 忽略
      e.insertDigit('5');
      expect(e.displayText, '5.5');
    });

    test('前导 0 被后续数字替换', () {
      final e = AmountExpression();
      e.insertDigit('0');
      e.insertDigit('5');
      expect(e.displayText, '5');
      expect(e.value, Decimal.fromInt(5));
    });

    test('整数位最多 9 位', () {
      final e = AmountExpression();
      for (var i = 0; i < 12; i++) {
        e.insertDigit('1');
      }
      expect(e.displayText.length, 9);
      expect(e.value, Decimal.fromInt(111111111));
    });
  });

  group('AmountExpression 连加', () {
    test('两段相加得到合计', () {
      final e = AmountExpression();
      e.insertDigit('1');
      e.insertDigit('2');
      e.beginAddition();
      e.insertDigit('3');
      expect(e.isCompound, isTrue);
      expect(e.displayText, '12+3');
      expect(e.value, Decimal.fromInt(15));
    });

    test('带小数的连加', () {
      final e = AmountExpression();
      e.insertDigit('1');
      e.insertDigit('2');
      e.beginAddition();
      e.insertDigit('3');
      e.insertDot();
      e.insertDigit('5');
      expect(e.displayText, '12+3.5');
      expect(e.value, Decimal.parse('15.5'));
    });

    test('空段时 beginAddition 被忽略', () {
      final e = AmountExpression();
      e.beginAddition(); // 当前段不可解析，忽略
      expect(e.isCompound, isFalse);
      expect(e.isEmpty, isTrue);
    });
  });

  group('AmountExpression 删除与清空', () {
    test('删除最后一位', () {
      final e = AmountExpression();
      e.insertDigit('1');
      e.insertDigit('2');
      e.deleteBackward();
      expect(e.displayText, '1');
      expect(e.value, Decimal.fromInt(1));
    });

    test('在连加上删除会回退到上一段', () {
      final e = AmountExpression();
      e.insertDigit('1');
      e.insertDigit('2');
      e.beginAddition();
      e.insertDigit('3');
      e.deleteBackward(); // 删掉 "3" → 当前段空
      e.deleteBackward(); // 移除空段，回到 "12"
      expect(e.isCompound, isFalse);
      expect(e.displayText, '12');
      expect(e.value, Decimal.fromInt(12));
    });

    test('clear 后回到空状态', () {
      final e = AmountExpression();
      e.insertDigit('9');
      e.clear();
      expect(e.isEmpty, isTrue);
      expect(e.value, Decimal.zero);
    });
  });

  group('AmountExpression.loadAmount', () {
    test('去掉尾零', () {
      final e = AmountExpression();
      e.loadAmount(Decimal.parse('12.00'));
      expect(e.displayText, '12');

      final e2 = AmountExpression();
      e2.loadAmount(Decimal.parse('3.50'));
      expect(e2.displayText, '3.5');
    });

    test('0 或负数视为清空', () {
      final e = AmountExpression();
      e.loadAmount(Decimal.zero);
      expect(e.isEmpty, isTrue);

      final e2 = AmountExpression();
      e2.loadAmount(Decimal.parse('-5'));
      expect(e2.isEmpty, isTrue);
    });
  });
}
