import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/amount_expression.dart';

void main() {
  group('AmountExpression', () {
    test('typing simple amount', () {
      final expr = AmountExpression();
      expr.insertDigit('1');
      expr.insertDigit('2');
      expr.insertDot();
      expr.insertDigit('5');
      expect(expr.displayText, '12.5');
      expect(expr.value, Decimal.parse('12.5'));
      expect(expr.isCompound, isFalse);
    });

    test('leading zero is replaced', () {
      final expr = AmountExpression();
      expr.insertDigit('0');
      expr.insertDigit('7');
      expect(expr.displayText, '7');
    });

    test('fraction digits limited to two', () {
      final expr = AmountExpression();
      expr.insertDigit('1');
      expr.insertDot();
      expr.insertDigit('2');
      expr.insertDigit('3');
      expr.insertDigit('4');
      expect(expr.displayText, '1.23');
    });

    test('second dot is ignored', () {
      final expr = AmountExpression();
      expr.insertDigit('3');
      expr.insertDot();
      expr.insertDot();
      expr.insertDigit('5');
      expect(expr.displayText, '3.5');
    });

    test('dot on empty field prepends zero', () {
      final expr = AmountExpression();
      expr.insertDot();
      expr.insertDigit('5');
      expect(expr.displayText, '0.5');
      expect(expr.value, Decimal.parse('0.5'));
    });

    test('addition', () {
      final expr = AmountExpression();
      expr.insertDigit('1');
      expr.insertDigit('2');
      expr.beginAddition();
      expr.insertDigit('3');
      expr.insertDot();
      expr.insertDigit('5');
      expect(expr.displayText, '12+3.5');
      expect(expr.value, Decimal.parse('15.5'));
      expect(expr.isCompound, isTrue);
    });

    test('addition requires current number', () {
      final expr = AmountExpression();
      expr.beginAddition();
      expect(expr.displayText, '0');
      expect(expr.isCompound, isFalse);
    });

    test('delete backward crosses terms', () {
      final expr = AmountExpression();
      expr.insertDigit('8');
      expr.beginAddition();
      expr.insertDigit('2');
      expr.deleteBackward(); // delete '2'
      expr.deleteBackward(); // delete empty second segment
      expect(expr.displayText, '8');
      expect(expr.isCompound, isFalse);
      expr.deleteBackward(); // delete '8'
      expect(expr.isEmpty, isTrue);
      expect(expr.value, Decimal.zero);
    });

    test('clear', () {
      final expr = AmountExpression();
      expr.insertDigit('9');
      expr.clear();
      expect(expr.isEmpty, isTrue);
      expect(expr.displayText, '0');
    });
  });
}
