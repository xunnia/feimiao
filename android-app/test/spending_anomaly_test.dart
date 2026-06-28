import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/spending_anomaly.dart';

void main() {
  List<Decimal> amts(List<String> xs) => xs.map(Decimal.parse).toList();

  group('SpendingAnomaly.note', () {
    test('样本不足(<5) → 不提醒', () {
      expect(
          SpendingAnomaly.note(amts(['10', '10', '10', '10']), Decimal.parse('99'), '奶茶'),
          isNull);
    });
    test('明显偏高(>中位×2 且高出≥10) → 提醒', () {
      final n = SpendingAnomaly.note(
          amts(['10', '10', '10', '12', '8']), Decimal.parse('25'), '饮料酒水');
      expect(n, isNotNull);
      expect(n, contains('饮料酒水'));
    });
    test('没超阈值 → 不提醒', () {
      expect(
          SpendingAnomaly.note(
              amts(['10', '10', '10', '12', '8']), Decimal.parse('18'), '奶茶'),
          isNull);
    });
  });
}
