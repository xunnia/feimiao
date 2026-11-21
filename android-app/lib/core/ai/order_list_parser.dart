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
  static final RegExp cancelled = RegExp(r'已取消|交易关闭|已关闭|交易取消|退款成功|已退款|未付款');
  static final RegExp _priceHint =
      RegExp(r'[¥￥]\s*\d+(?:\.\d{1,2})?|\d+\.\d{2}');
  static final RegExp _partialRefundHint = RegExp(r'已退款\s*[¥￥]?\s*\d|部分退款');

  static bool _isCancelledOrder(List<OcrLine> block) {
    for (final line in block) {
      final t = line.text.trim();
      if (t.isEmpty) continue;
      if (_partialRefundHint.hasMatch(t)) continue;
      // 仅把短状态行/状态标签视为整单取消，避免误杀长横幅提示或「申请退款」按钮。
      if (t.length <= 16 && cancelled.hasMatch(t) && !t.contains('申请退款')) {
        return true;
      }
    }
    return false;
  }

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
      // 末尾残留若本身包含价格（如屏底最后一单的「共N件」被截在屏外）且有至少两行，保留给上层解析；
      // 纯页脚/按钮残留（无价格）直接丢弃。
      if (cur.length >= 2 && cur.any((l) => _priceHint.hasMatch(l.text))) {
        blocks.add(cur);
      }
    } else {
      blocks = ScreenshotLayout.clusterBlocks(valid);
    }

    // 丢弃已取消/全额退款/未付款的整单
    return blocks.where((b) => !_isCancelledOrder(b)).toList();
  }
}
