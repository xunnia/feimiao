import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/chat_intent.dart';

void main() {
  group('ChatIntent.isQuery — 记账识别(返回 false)', () {
    // 这些是真实翻车样例：以前"花了"被当查账词，导致反复记不上。
    const records = [
      '坐公交花了一块',
      '坐公交车花了一块',
      '今天坐公交车花了一块',
      '坐地铁花了4元',
      '今天早上去上班坐公交车花了1元',
      '奶茶 18',
      '打车二十五',
      '中午吃饭花了三十',
      '收到工资八千',
      '发红包两百',
      '充值话费一百',
    ];
    for (final r in records) {
      test('记账：「$r」', () {
        // 模拟"含阿拉伯数字时解析器能识别"；中文口语金额由模块自判。
        final hasArabic = RegExp(r'\d').hasMatch(r);
        expect(ChatIntent.isQuery(r, hasArabicAmount: hasArabic), isFalse,
            reason: '「$r」应判为记账');
      });
    }
  });

  group('ChatIntent.isQuery — 查账识别(返回 true)', () {
    const queries = [
      '这个月公交花了多少',
      '我这月餐饮花了多少钱',
      '本月最大的一笔支出是哪个',
      '帮我分析下这个月的花销',
      '吃饭和打车哪个花得多',
      '预算还剩多少',
      '这个月超支了吗',
      '消费占比怎么样',
    ];
    for (final q in queries) {
      test('查账：「$q」', () {
        final hasArabic = RegExp(r'\d').hasMatch(q);
        expect(ChatIntent.isQuery(q, hasArabicAmount: hasArabic), isTrue,
            reason: '「$q」应判为查账');
      });
    }
  });

  group('ChatIntent.hasColloquialAmount', () {
    test('识别中文口语金额', () {
      expect(ChatIntent.hasColloquialAmount('一块'), isTrue);
      expect(ChatIntent.hasColloquialAmount('两块五'), isTrue);
      expect(ChatIntent.hasColloquialAmount('十块'), isTrue);
      expect(ChatIntent.hasColloquialAmount('三十元'), isTrue);
      expect(ChatIntent.hasColloquialAmount('五毛'), isTrue);
    });
    test('普通句子不误报', () {
      expect(ChatIntent.hasColloquialAmount('坐公交'), isFalse);
      expect(ChatIntent.hasColloquialAmount('今天天气不错'), isFalse);
    });
  });

  test('空串安全 → 记账(false)', () {
    expect(ChatIntent.isQuery(''), isFalse);
    expect(ChatIntent.isQuery('   '), isFalse);
  });
}
