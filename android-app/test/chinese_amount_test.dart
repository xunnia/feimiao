import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/natural_language_entry_parser.dart';

void main() {
  Decimal? amt(String s) => NaturalLanguageEntryParser.extractAmount(s);

  group('中文数字金额（离线兜底）', () {
    final cases = {
      '三十块': '30',
      '十块': '10',
      '一百二十元': '120',
      '一百二块': '120', // 口语省略
      '两块五': '2.5',
      '三块五毛': '3.5',
      '一万二块': '12000', // 万级口语
      '五十块': '50',
      '两百块': '200',
    };
    cases.forEach((text, expected) {
      test('「$text」→ $expected', () {
        expect(amt(text), Decimal.parse(expected));
      });
    });
  });

  group('阿拉伯数字仍正常', () {
    test('¥18.5 → 18.5', () => expect(amt('付了¥18.5'), Decimal.parse('18.5')));
    test('23块5 → 23.5', () => expect(amt('打车23块5'), Decimal.parse('23.5')));
    test('最后一个数字兜底', () => expect(amt('买了2杯咖啡58'), Decimal.parse('58')));
  });

  group('无金额返回 null', () {
    test('坐公交', () => expect(amt('坐公交'), isNull));
  });
}
