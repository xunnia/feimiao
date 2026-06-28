import 'screenshot_layout.dart';

/// 订单列表切分（京东/淘宝/拼多多「我的订单」）。
///
/// 思路：这些平台每个订单都恰好出现一次「共N件」，是最可靠的"一单一个"锚点。
/// 用它把 OCR 行确定性地切成「一单一块」，比纯按纵向空白聚类更稳；
/// 切单时顺手把「已取消/退款/交易关闭」的整单丢掉（不是真实支出）。
/// 找不到「共N件」锚点时（如部分拼多多页），回退到纵向聚类。
class OrderListParser {
  OrderListParser._();

  static final RegExp countAnchor = RegExp(r'共\s*\d+\s*件');
  static final RegExp cancelled =
      RegExp(r'已取消|交易关闭|已关闭|交易取消|退款成功|已退款|未付款');

  /// 切成一单一块，已丢弃取消/退款单。块内按阅读顺序(top)排列。
  static List<List<OcrLine>> segment(List<OcrLine> lines) {
    final valid = lines.where((l) => l.text.trim().isNotEmpty).toList()
      ..sort((a, b) => a.top.compareTo(b.top));
    if (valid.isEmpty) return const [];

    final anchorCount = valid.where((l) => countAnchor.hasMatch(l.text)).length;

    List<List<OcrLine>> blocks;
    if (anchorCount >= 2) {
      // 以「共N件」为每单结尾切块
      blocks = [];
      var cur = <OcrLine>[];
      for (final l in valid) {
        cur.add(l);
        if (countAnchor.hasMatch(l.text)) {
          blocks.add(cur);
          cur = <OcrLine>[];
        }
      }
      // 末尾残留(页脚/优惠券/按钮，无「共N件」)直接丢弃：只保留真正含锚点的块
      blocks = blocks
          .where((b) => b.any((l) => countAnchor.hasMatch(l.text)))
          .toList();
    } else {
      blocks = ScreenshotLayout.clusterBlocks(valid);
    }

    // 丢弃已取消/退款/未付款的整单
    return blocks
        .where((b) => !cancelled.hasMatch(b.map((l) => l.text).join()))
        .toList();
  }
}
