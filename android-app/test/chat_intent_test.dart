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
  group('ChatIntent.classify free chat fallback', () {
    test('casual messages are not treated as records', () {
      expect(ChatIntent.classify('你好呀'), ChatIntentKind.chat);
      expect(ChatIntent.classify('讲个笑话'), ChatIntentKind.chat);
      expect(ChatIntent.classify('今天心情不错'), ChatIntentKind.chat);
      expect(ChatIntent.classify('今天天气怎么样'), ChatIntentKind.chat);
      expect(ChatIntent.classify('你好吗？'), ChatIntentKind.chat);
      expect(ChatIntent.classify('法国人口有多少'), ChatIntentKind.chat);
      expect(
        ChatIntent.classify('给我推荐 3 部电影', hasArabicAmount: true),
        ChatIntentKind.chat,
      );
      expect(
        ChatIntent.classify('写一篇 500 字短文', hasArabicAmount: true),
        ChatIntentKind.chat,
      );
      expect(
        ChatIntent.classify('GPT-5 有什么特点', hasArabicAmount: true),
        ChatIntentKind.chat,
      );
      expect(
        ChatIntent.classify('2 的 10 次方是多少', hasArabicAmount: true),
        ChatIntentKind.chat,
      );
      expect(
        ChatIntent.classify('今天 20 度穿什么', hasArabicAmount: true),
        ChatIntentKind.chat,
      );
      expect(ChatIntent.classify('看看退款政策'), ChatIntentKind.chat);
      expect(ChatIntent.classify('总结这篇消费税文章'), ChatIntentKind.chat);
      expect(ChatIntent.classify('工资多少需要交税'), ChatIntentKind.chat);
      expect(ChatIntent.classify('预算如何制定'), ChatIntentKind.chat);
      expect(
        ChatIntent.classify('推荐 3 张信用卡', hasArabicAmount: true),
        ChatIntentKind.chat,
      );
      expect(ChatIntent.classify('推荐打车软件'), ChatIntentKind.chat);
      expect(ChatIntent.classify('怎么打车更便宜'), ChatIntentKind.chat);
      expect(ChatIntent.classify('工资是什么'), ChatIntentKind.chat);
      expect(ChatIntent.classify('红包怎么写祝福语'), ChatIntentKind.chat);
    });

    test('record semantics remain unchanged', () {
      expect(
        ChatIntent.classify('午饭 28', hasArabicAmount: true),
        ChatIntentKind.record,
      );
      expect(
        ChatIntent.classify('奶茶 18', hasArabicAmount: true),
        ChatIntentKind.record,
      );
      expect(ChatIntent.classify('打车二十五'), ChatIntentKind.record);
      expect(
        ChatIntent.classify('停车 12 元', hasArabicAmount: true),
        ChatIntentKind.record,
      );
      expect(
        ChatIntent.classify('¥88 买书', hasArabicAmount: true),
        ChatIntentKind.record,
      );
      expect(
        ChatIntent.classify('地铁 4', hasArabicAmount: true),
        ChatIntentKind.record,
      );
      expect(
        ChatIntent.classify('房租 2800', hasArabicAmount: true),
        ChatIntentKind.record,
      );
      expect(
        ChatIntent.classify('13号失业金到账2250', hasArabicAmount: true),
        ChatIntentKind.record,
      );
      expect(
        ChatIntent.classify('社保补贴到账 500', hasArabicAmount: true),
        ChatIntentKind.record,
      );
    });

    test('ledger summaries without a question mark remain queries', () {
      expect(ChatIntent.classify('本月花了多少'), ChatIntentKind.query);
      expect(ChatIntent.classify('查一下本月支出'), ChatIntentKind.query);
      expect(ChatIntent.classify('总结上个月消费'), ChatIntentKind.query);
      expect(ChatIntent.classify('看看我上周都买了什么'), ChatIntentKind.query);
      expect(ChatIntent.classify('汇总今年收入'), ChatIntentKind.query);
      expect(ChatIntent.classify('复盘本周餐饮'), ChatIntentKind.query);
    });

    test('relative-day and recent-range questions remain queries', () {
      expect(ChatIntent.classify('今天花了多少钱'), ChatIntentKind.query);
      expect(ChatIntent.classify('昨天支出多少'), ChatIntentKind.query);
      expect(ChatIntent.classify('近 7 天买了什么'), ChatIntentKind.query);
      expect(ChatIntent.classify('最近消费怎么样'), ChatIntentKind.query);
    });

    test('ledger summaries without question marks remain queries', () {
      expect(ChatIntent.classify('今天收入'), ChatIntentKind.query);
      expect(ChatIntent.classify('本周餐饮'), ChatIntentKind.query);
      expect(
        ChatIntent.classify('今天买了咖啡 20', hasArabicAmount: true),
        ChatIntentKind.record,
      );
      expect(
        ChatIntent.classify('买电脑 5000', hasArabicAmount: true),
        ChatIntentKind.record,
      );
    });

    test('purchase advice remains free chat without an amount', () {
      expect(ChatIntent.classify('我想买一台电脑'), ChatIntentKind.chat);
      expect(ChatIntent.classify('我想买什么股票'), ChatIntentKind.chat);
    });
  });
}
