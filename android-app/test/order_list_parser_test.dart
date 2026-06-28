import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/order_list_parser.dart';
import 'package:qingji/core/ai/screenshot_layout.dart';

/// 模拟京东「我的订单」三单：单1完成、单2已取消、单3完成；每单一个「共1件」。
List<OcrLine> _jdOrders() {
  OcrLine ln(String t, double top) =>
      OcrLine(text: t, top: top, bottom: top + 30, left: 40);
  return [
    // 单1
    ln('京东大药房', 0),
    ln('999皮炎平 复方醋酸', 40),
    ln('¥17.70', 80),
    ln('共1件', 120),
    // 单2（已取消）
    ln('京东大药房', 200),
    ln('已取消', 205),
    ln('999皮炎平 大规格', 240),
    ln('¥17.90', 280),
    ln('共1件', 320),
    // 单3
    ln('麦当劳&麦咖啡', 400),
    ln('星愿相伴双人餐', 440),
    ln('¥54.90', 480),
    ln('共1件', 520),
    // 页脚噪声
    ln('恭喜您获得10元京东购物券', 600),
    ln('去领券', 640),
  ];
}

void main() {
  group('OrderListParser.segment — 按「共N件」切单 + 丢取消单', () {
    test('三单中取消单被丢，剩两单且各自商品金额配套', () {
      final blocks = OrderListParser.segment(_jdOrders());
      expect(blocks.length, 2);

      String j(List<OcrLine> b) => b.map((l) => l.text).join('｜');
      expect(j(blocks[0]), allOf(contains('皮炎平'), contains('17.70')));
      expect(j(blocks[1]), allOf(contains('麦当劳'), contains('54.90')));

      // 已取消那单(17.90)整单丢弃
      final all = blocks.expand((b) => b).map((l) => l.text).join();
      expect(all.contains('17.90'), isFalse);
      // 页脚优惠券(无「共N件」)不成单
      expect(all.contains('购物券'), isFalse);
    });

    test('渲染成分隔块文本(两单 → 一条分隔线)', () {
      final blocks = OrderListParser.segment(_jdOrders());
      final txt = ScreenshotLayout.renderBlocks(blocks);
      expect('─────'.allMatches(txt).length, 1);
    });

    test('无「共N件」锚点 → 回退纵向聚类(不报错)', () {
      final lines = [
        const OcrLine(text: '微信支付', top: 0, bottom: 30, left: 0),
        const OcrLine(text: '¥8.50', top: 38, bottom: 68, left: 0),
      ];
      final blocks = OrderListParser.segment(lines);
      expect(blocks, isNotEmpty);
    });
  });
}
