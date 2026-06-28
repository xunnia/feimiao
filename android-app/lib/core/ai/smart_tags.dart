import 'package:decimal/decimal.dart';

/// 「解析更聪明」的轻量识别（纯逻辑，可单测）：
/// - 报销识别：备注像因公消费就自动标「待报销」。
/// - AA 分摊：给了人数就把金额摊成「我那一份」。
class SmartTags {
  SmartTags._();

  static final RegExp _reimburse =
      RegExp(r'报销|出差|差旅|垫付|公司报|帮公司|公司的|因公|客户招待|招待费');

  /// 备注是否像「需要报销」。
  static bool isReimbursable(String text) => _reimburse.hasMatch(text);

  static final RegExp _aaWords = RegExp(r'AA|aa|均摊|平摊|分摊|各付|各自付');
  static final RegExp _people = RegExp(r'(\d+)\s*(?:个人|人)');

  /// AA 分摊：文本含 AA/均摊等且能取到人数 N(>1) 时，返回 总额/N(保留两位)；
  /// 否则原额返回（拿不准就不乱摊）。
  static Decimal aaShare(String text, Decimal total) {
    if (total <= Decimal.zero) return total;
    if (!_aaWords.hasMatch(text)) return total;
    final m = _people.firstMatch(text);
    final n = m != null ? int.tryParse(m.group(1)!) : null;
    if (n != null && n > 1) {
      return (total / Decimal.fromInt(n))
          .toDecimal(scaleOnInfinitePrecision: 2);
    }
    return total;
  }
}
