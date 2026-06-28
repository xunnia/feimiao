import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/smart_tags.dart';

void main() {
  group('SmartTags.isReimbursable', () {
    test('出差/报销/垫付 → true', () {
      expect(SmartTags.isReimbursable('出差打车'), isTrue);
      expect(SmartTags.isReimbursable('帮公司垫付了餐费'), isTrue);
      expect(SmartTags.isReimbursable('客户招待'), isTrue);
    });
    test('普通消费 → false', () {
      expect(SmartTags.isReimbursable('买奶茶'), isFalse);
      expect(SmartTags.isReimbursable('坐公交'), isFalse);
    });
  });

  group('SmartTags.aaShare', () {
    Decimal d(String s) => Decimal.parse(s);
    test('给了人数 → 摊成我那份', () {
      expect(SmartTags.aaShare('4个人AA', d('200')), d('50'));
      expect(SmartTags.aaShare('3人均摊300', d('300')), d('100'));
    });
    test('没说 AA → 原额', () {
      expect(SmartTags.aaShare('和朋友吃饭200', d('200')), d('200'));
    });
    test('AA 但没给人数 → 原额(不瞎猜)', () {
      expect(SmartTags.aaShare('几个人AA', d('200')), d('200'));
    });
    test('金额非正 → 原样', () {
      expect(SmartTags.aaShare('4人AA', Decimal.zero), Decimal.zero);
    });
  });
}
