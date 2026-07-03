import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/bill_categorizer.dart';
import 'package:qingji/core/models/transaction_kind.dart';

void main() {
  const exp = TransactionKind.expense;

  CatGuess c({String merchant = '', String product = '', String note = ''}) =>
      BillCategorizer.classify(
          merchant: merchant, product: product, note: note, kind: exp);

  group('normalizeMerchant 剥噪声', () {
    final cases = {
      '京东-订单编号349126': '京东',
      '拼多多平台商户': '拼多多',
      '京东商城平台商户': '京东',
      '美团订单-26061211200700001309588461': '美团',
      '恒兴广告-刘生': '恒兴广告-刘生', // 没有数字尾巴，保留
    };
    cases.forEach((raw, want) {
      test('「$raw」→「$want」', () {
        expect(BillCategorizer.normalizeMerchant(raw).trim(), want);
      });
    });
  });

  group('商品优先于商户（平台商户尤其）', () {
    test('美团 + 电影票商品 → 电影（商品赢，不是平台默认餐饮）', () {
      final g = c(merchant: '美团', product: '电影票');
      expect(g.key, 'ent_movie');
      expect(g.confidence, CatConfidence.high);
    });
    test('顺丰 + 散单运费 → 其他（商品命中运费）', () {
      final g = c(merchant: '顺丰速运', product: '散单运费-顺丰速运');
      expect(g.key, 'other');
    });
  });

  group('平台商户落安全的顶级默认（中置信）', () {
    test('京东无有效商品 → 购物消费', () {
      final g = c(merchant: '京东', product: '订单付款', note: '京东 · 订单付款');
      expect(g.key, 'shopping');
      expect(g.confidence, CatConfidence.medium);
    });
    test('拼多多平台商户 → 购物消费', () {
      final g = c(merchant: '拼多多平台商户', product: '', note: '拼多多平台商户 · 先用后付');
      expect(g.key, 'shopping');
    });
    test('美团无商品明细 → 餐饮（平台默认）', () {
      final g = c(merchant: '美团', product: '', note: '美团');
      expect(g.key, 'dining');
    });
  });

  group('决定性商户用商户名（高置信）', () {
    test('中国电信 → 话费', () {
      final g = c(merchant: '中国电信', product: '', note: '中国电信');
      expect(g.key, 'house_phone');
      expect(g.confidence, CatConfidence.high);
    });
    test('miHoYo Games → 虚拟充值', () {
      final g = c(merchant: 'miHoYo Games', product: '', note: 'miHoYo Games');
      expect(g.key, 'subscription');
    });
    test('luckin coffee 订单付款 → 饮料', () {
      final g = c(merchant: 'luckin coffee', product: '订单付款');
      expect(g.key, 'dining_drink');
    });
  });

  group('拿不准就交给用户', () {
    test('个人转账无线索 → 无', () {
      final g = c(merchant: 'M&X*^O^*', product: '', note: 'M&X*^O^* · 转账备注:微信转账');
      expect(g.key, isNull);
    });
  });

  group('learnKeyFor：决定性学商户、平台不学', () {
    test('决定性商户返回商户主体', () {
      expect(BillCategorizer.learnKeyFor('顺丰速运'), '顺丰速运');
      expect(BillCategorizer.learnKeyFor('中国电信'), '中国电信');
    });
    test('平台商户返回 null（不错学 京东→子类）', () {
      expect(BillCategorizer.learnKeyFor('京东-订单编号349126'), isNull);
      expect(BillCategorizer.learnKeyFor('拼多多平台商户'), isNull);
    });
  });
}
