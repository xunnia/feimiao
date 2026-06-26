import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/screenshot_layout.dart';

/// 模拟一张订单列表截图：3 张订单卡，每卡 3 行（商品名 / 划线价 / 付款金额）。
/// 卡内行距小（约 10px），卡间空白大（约 60px），高度约 30px。
List<OcrLine> _threeCards() {
  OcrLine ln(String t, double top) =>
      OcrLine(text: t, top: top, bottom: top + 30, left: 40);
  return [
    // 卡1
    ln('舒肤佳红石榴沐浴露400g+200g*2', 0),
    ln('¥35.6', 40),
    ln('7天16小时后,自动确认收货并付款 ¥32.04', 80),
    // 卡2（卡间空白 ~60）
    ln('维达超韧抽纸16包', 170),
    ln('¥22.5', 210),
    ln('7天16小时后,自动确认收货并付款 ¥15.9', 250),
    // 卡3
    ln('恒澎木浆棉百洁布8块装', 340),
    ln('¥18', 380),
    ln('7天16小时后,自动确认收货并付款 ¥11.28', 420),
  ];
}

void main() {
  group('ScreenshotLayout.clusterBlocks', () {
    test('订单列表按卡片聚成 3 块，商品与各自金额同块', () {
      final blocks = ScreenshotLayout.clusterBlocks(_threeCards());
      expect(blocks.length, 3);

      // 每块商品名与它自己的付款金额必须在一起（防错位的关键断言）
      String joined(List<OcrLine> b) => b.map((l) => l.text).join('｜');
      expect(joined(blocks[0]), allOf(contains('舒肤佳'), contains('32.04')));
      expect(joined(blocks[1]), allOf(contains('维达'), contains('15.9')));
      expect(joined(blocks[2]), allOf(contains('恒澎'), contains('11.28')));

      // 不串：第1块不应混入别的商品/金额
      expect(joined(blocks[0]), isNot(contains('维达')));
      expect(joined(blocks[0]), isNot(contains('15.9')));
    });

    test('块内按纵坐标排序（商品名在金额之前）', () {
      final blocks = ScreenshotLayout.clusterBlocks(_threeCards());
      final first = blocks[0];
      final nameIdx = first.indexWhere((l) => l.text.contains('舒肤佳'));
      final amtIdx = first.indexWhere((l) => l.text.contains('32.04'));
      expect(nameIdx, lessThan(amtIdx));
    });

    test('单行 / 空输入安全', () {
      expect(ScreenshotLayout.clusterBlocks(const []), isEmpty);
      final one = [
        const OcrLine(text: '微信支付 ¥8.5', top: 0, bottom: 30, left: 0)
      ];
      final b = ScreenshotLayout.clusterBlocks(one);
      expect(b.length, 1);
      expect(b.first.length, 1);
    });
  });

  group('ScreenshotLayout.renderBlocks', () {
    test('多块用分隔线隔开', () {
      final blocks = ScreenshotLayout.clusterBlocks(_threeCards());
      final txt = ScreenshotLayout.renderBlocks(blocks);
      expect('─────'.allMatches(txt).length, 2); // 3 块 → 2 条分隔线
      expect(txt, contains('舒肤佳'));
      expect(txt, contains('恒澎'));
    });

    test('单块不加分隔线', () {
      final one = [
        const OcrLine(text: '微信支付', top: 0, bottom: 30, left: 0),
        const OcrLine(text: '¥8.5', top: 38, bottom: 68, left: 0),
      ];
      final blocks = ScreenshotLayout.clusterBlocks(one);
      final txt = ScreenshotLayout.renderBlocks(blocks);
      expect(txt, isNot(contains('─────')));
    });

    test('cleaner 会作用到每块', () {
      final blocks = ScreenshotLayout.clusterBlocks(_threeCards());
      final txt = ScreenshotLayout.renderBlocks(
        blocks,
        cleaner: (s) => s.replaceAll('恒澎', 'XX'),
      );
      expect(txt, isNot(contains('恒澎')));
      expect(txt, contains('XX'));
    });
  });
}
