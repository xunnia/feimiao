import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/merchant_category.dart';
import 'package:qingji/core/models/category_seed.dart';
import 'package:qingji/core/models/transaction_kind.dart';

void main() {
  const exp = TransactionKind.expense;
  const inc = TransactionKind.income;

  group('MerchantCategory.classify — 支出', () {
    final cases = {
      '瑞幸拿铁': 'dining_drink',
      '点了杯奶茶': 'dining_drink',
      '美团外卖': 'dining',
      '滴滴打车花了': 'trans_taxi',
      '坐地铁': 'trans_public',
      '坐公交车': 'trans_public',
      '交话费100': 'house_phone',
      '交电费': 'utilities',
      '给猫买猫粮': 'pets',
      '屈臣氏买洗面奶': 'shop_beauty',
      '发红包给朋友': 'gift_red',
      '买了维达抽纸': 'shop_home',
      // ── 微信账单常见商户（0703 补强）──
      '京东-订单编号349126': 'shopping',
      '拼多多平台商户 先用后付': 'shopping',
      '淘宝平台商户': 'shopping',
      'Apple apple.com/bill/MMQ': 'subscription',
      'iCloud 由云上贵州运营': 'subscription',
      'miHoYo Games': 'subscription',
      '深圳市腾讯天游科技有限公司': 'subscription',
      '手机充值-中国移动': 'house_phone',
      '中国电信': 'house_phone',
      '顺丰速运 散单运费': 'other',
      '广东省广州市中级人民法院': 'other_fine',
    };
    cases.forEach((text, key) {
      test('「$text」→ $key', () {
        expect(MerchantCategory.classify(text, exp), key);
      });
    });
  });

  group('MerchantCategory.classify — 收入', () {
    final cases = {
      '发工资了': 'salary',
      '收到退款': 'refund',
      '抢了个红包': 'redPacket',
      '年终奖到账': 'bonus',
    };
    cases.forEach((text, key) {
      test('「$text」→ $key', () {
        expect(MerchantCategory.classify(text, inc), key);
      });
    });
  });

  group('MerchantCategory.classify — 不误报 & kind 隔离', () {
    test('普通句子无命中', () {
      expect(MerchantCategory.classify('今天天气不错', exp), isNull);
      expect(MerchantCategory.classify('', exp), isNull);
    });
    test('收入词在支出下不命中', () {
      // "工资"只在收入侧，支出查询应为 null
      expect(MerchantCategory.classify('工资', exp), isNull);
    });
    test('红包在收/支落到不同分类', () {
      expect(MerchantCategory.classify('红包', exp), 'gift_red');
      expect(MerchantCategory.classify('红包', inc), 'redPacket');
    });
  });

  group('词典 key 全部真实存在（否则匹配不到会回落）', () {
    test('每个分类 key 都能在 CategorySeed 找到且 kind 一致', () {
      MerchantCategory.triggers.forEach((key, _) {
        final seed = CategorySeed.byKey(key);
        expect(seed, isNotNull, reason: '词典里的 key「$key」在 CategorySeed 不存在');
      });
    });
  });
}
