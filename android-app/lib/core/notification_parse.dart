import 'package:decimal/decimal.dart';

import 'models/transaction_kind.dart';

/// 支付通知专用解析（自动记账用）。比通用解析更稳：
/// - 金额：挑「最像本次支付」的那个数，避开余额/可用额度。
/// - 方向：收款/到账/退款/向你转账 → 收入；其余 → 支出。
class NotificationParse {
  NotificationParse._();

  static final RegExp _amt = RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)');
  static final RegExp _yuan = RegExp(r'(\d+(?:\.\d{1,2})?)\s*元');
  static final RegExp _payCtx =
      RegExp(r'支付|付款|实付|扣款|消费|到账|收款|收钱|花');
  static final RegExp _balCtx = RegExp(r'余额|零钱|可用|额度|账户余');

  /// 从通知文本里挑出本次交易金额。
  static Decimal? pickAmount(String text) {
    final matches = _amt.allMatches(text).toList();
    if (matches.isEmpty) {
      final m = _yuan.firstMatch(text);
      return m != null ? Decimal.tryParse(m.group(1)!) : null;
    }
    final len = text.length;
    Decimal? balanceFallback; // 只剩余额可选时的兜底
    Decimal? firstNonBalance;
    for (final m in matches) {
      final val = Decimal.tryParse(m.group(1)!);
      if (val == null) continue;
      final preStart = m.start - 8 < 0 ? 0 : m.start - 8;
      final pre = text.substring(preStart, m.start);
      final postEnd = m.end + 6 > len ? len : m.end + 6;
      final post = text.substring(m.end, postEnd);
      if (_balCtx.hasMatch(pre)) {
        balanceFallback ??= val; // 像余额，先放一边
        continue;
      }
      firstNonBalance ??= val;
      // 紧挨支付词（前或后）→ 最可能是本次支付金额
      if (_payCtx.hasMatch(pre) || _payCtx.hasMatch(post)) return val;
    }
    return firstNonBalance ?? balanceFallback;
  }

  /// 收支方向：收款/到账/退款/「向你转账」→ 收入；其余 → 支出。
  static TransactionKind kindOf(String text) {
    if (RegExp(r'退款|退回').hasMatch(text)) return TransactionKind.income;
    if (RegExp(r'收款|收钱|到账|入账|向你转账|转账给你|发给你').hasMatch(text)) {
      return TransactionKind.income;
    }
    return TransactionKind.expense;
  }
}
