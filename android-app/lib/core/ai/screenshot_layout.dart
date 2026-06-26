/// 截图版面重建（订单列表防错位的核心）。
///
/// 背景：ML Kit OCR 出来的 `result.text` 是把所有文字按大致阅读顺序拼成的
/// 一整坨字符串，**丢掉了每行的坐标**。订单列表里每个订单是一张卡片
/// （商品名在上、付款金额在下），拼成纯文本后，某单的金额会紧挨着*下一单*的
/// 商品名，大模型据此把金额配到错误的商品上（整体偏移一位）。
///
/// 这里用每行的 boundingBox 纵坐标，把文字按「大间隙」聚成一个个订单块，
/// 块内的商品与金额天然挨在一起、绝不跨块，从根上消除错位。
///
/// 纯 Dart（不依赖 Flutter / dart:ui），坐标用普通 double 表示，便于单测。
library;

/// 一行 OCR 文本及其在图片中的位置（像素坐标，y 向下增大）。
class OcrLine {
  final String text;
  final double top;
  final double bottom;
  final double left;

  const OcrLine({
    required this.text,
    required this.top,
    required this.bottom,
    required this.left,
  });

  double get height => (bottom - top).abs();
}

class ScreenshotLayout {
  ScreenshotLayout._();

  /// 按纵向「大间隙」把行聚成块（每块≈一个订单卡）。
  ///
  /// 思路：相邻两行的纵向间距若明显大于「卡内常规行距」，就判为换卡。
  /// 阈值取自适应：`max(中位行高 * 1.2, 中位行距 * 2 + 1)`，
  /// 既能跨过卡内的小间隙、又只在明显空白处切开（偏保守，宁可少切不乱切）。
  /// 块内行按 top→left 排好序，保证阅读顺序正确。
  static List<List<OcrLine>> clusterBlocks(List<OcrLine> lines) {
    final valid = lines.where((l) => l.text.trim().isNotEmpty).toList();
    if (valid.length <= 1) return valid.isEmpty ? <List<OcrLine>>[] : [valid];

    valid.sort((a, b) => a.top.compareTo(b.top));

    // 中位行高
    final heights = valid.map((l) => l.height).where((h) => h > 0).toList()
      ..sort();
    final medH = heights.isEmpty ? 0.0 : heights[heights.length ~/ 2];

    // 相邻行的纵向间距
    final gaps = <double>[];
    for (var i = 1; i < valid.length; i++) {
      gaps.add(valid[i].top - valid[i - 1].bottom);
    }
    final sortedGaps = [...gaps]..sort();
    final medGap = sortedGaps.isEmpty ? 0.0 : sortedGaps[sortedGaps.length ~/ 2];

    final threshold = _max(medH * 1.2, medGap * 2 + 1);

    final blocks = <List<OcrLine>>[];
    var current = <OcrLine>[valid.first];
    for (var i = 1; i < valid.length; i++) {
      final gap = valid[i].top - valid[i - 1].bottom;
      if (gap > threshold) {
        blocks.add(current);
        current = <OcrLine>[valid[i]];
      } else {
        current.add(valid[i]);
      }
    }
    blocks.add(current);

    for (final b in blocks) {
      b.sort((a, c) {
        final dy = a.top.compareTo(c.top);
        if (dy != 0) return dy;
        return a.left.compareTo(c.left);
      });
    }
    return blocks;
  }

  /// 把聚好的块渲染成「块间用分隔线隔开」的文本。
  /// 单块或无块时直接返回纯文本（单笔支付页不受影响）。
  /// [cleaner] 可选：对每块文本做清噪（剔订单号/卡号等）。
  static String renderBlocks(
    List<List<OcrLine>> blocks, {
    String Function(String)? cleaner,
    String separator = '─────',
  }) {
    String bodyOf(List<OcrLine> b) {
      final raw = b.map((l) => l.text.trim()).where((t) => t.isNotEmpty).join('\n');
      final cleaned = cleaner == null ? raw : cleaner(raw);
      return cleaned.trim();
    }

    final parts = <String>[];
    for (final b in blocks) {
      final body = bodyOf(b);
      if (body.isNotEmpty) parts.add(body);
    }
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    return parts.join('\n$separator\n');
  }

  static double _max(double a, double b) => a > b ? a : b;
}
