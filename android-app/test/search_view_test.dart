import 'package:flutter_test/flutter_test.dart';
import 'package:decimal/decimal.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/views/search/search_view.dart';

void main() {
  tearDown(MoneyFormat.resetConfig);

  test('搜索关键词归一化：大小写与全角英数字不影响匹配', () {
    expect(normalizeSearchText('K12'), 'k12');
    expect(normalizeSearchText('Ｋ１２'), 'k12');
    expect(normalizeSearchText('  备注：Ｋ12  '), '备注:k12');
  });

  test('金额搜索 token 不被金额显示设置削弱', () {
    MoneyFormat.configure(
      decimalPlaces: 0,
      integerRoundingMode: MoneyIntegerRoundingMode.round,
    );

    final normalized = moneySearchTexts(Decimal.parse('12.50'))
        .map(normalizeSearchText)
        .toSet();
    expect(normalized, contains('¥13'));
    expect(normalized, contains('¥12.50'));
    expect(normalized, contains('12.50'));
  });

  test('金额区间标签跟随金额显示设置', () {
    MoneyFormat.configure(
      decimalPlaces: 1,
      integerRoundingMode: MoneyIntegerRoundingMode.round,
    );

    expect(
      moneyRangeLabel(Decimal.parse('12.55'), Decimal.parse('20')),
      '¥12.6~¥20.0',
    );
    expect(moneyRangeLabel(Decimal.parse('12.55'), null), '≥ ¥12.6');
    expect(moneyRangeLabel(null, Decimal.parse('20')), '≤ ¥20.0');
  });
}
