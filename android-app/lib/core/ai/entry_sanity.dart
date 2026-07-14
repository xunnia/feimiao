import 'package:decimal/decimal.dart';

import 'natural_language_entry_parser.dart';

/// 解析结果的「兜底体检」：在入库/展示前把明显不合理的字段纠正掉，
/// 避免大模型/OCR 偶发抽风把脏数据自动存进去。纯逻辑，可单测。
///
/// 规则（保守，只动明显异常的）：
/// - 金额 ≤ 0 或大得离谱（> 1 亿）→ 视为「没识别出金额」(null)，
///   这样不会自动入库，会礼貌追问，而不是存一笔天文数字。
///   注意：退款是「负支出」，由上层单独处理，这里不针对负数（解析阶段金额本就为正）。
/// - 日期晚于今天（未来）→ 收敛到今天（记账几乎都是过去/当下，未来多是解析错误）。
/// - 置信度 clamp 到 0~1。
class EntrySanity {
  EntrySanity._();

  /// 1 亿：日常单笔不可能到这个量级，超过基本是把订单号/卡号当成了金额。
  static final Decimal maxAmount = Decimal.fromInt(100000000);

  static ParsedEntry clean(ParsedEntry e, {DateTime? now}) {
    final today = now ?? DateTime.now();

    Decimal? amt = e.amount;
    if (amt != null && (amt <= Decimal.zero || amt > maxAmount)) {
      amt = null;
    }

    var d = e.date;
    final t0 = DateTime(today.year, today.month, today.day);
    final d0 = DateTime(d.year, d.month, d.day);
    if (d0.isAfter(t0)) d = today;

    final conf = e.confidence.clamp(0.0, 1.0);

    return ParsedEntry(
      amount: amt,
      kind: e.kind,
      categoryKey: e.categoryKey,
      note: e.note,
      date: d,
      timePrecision: e.timePrecision,
      confidence: conf,
    );
  }
}
