import 'package:decimal/decimal.dart';

import '../money_format.dart';

/// 统计页涨跌徽章的文案（07 §14）。
///
/// - 上期没有 → 不显示。
/// - 两期都是 0 → 不显示。
/// - 上期 0、本期不是 0 → 「新增 ¥X」（不显示无穷百分比）。
/// - 任一期为负（结余跨零或都为负）→ 显示金额差「↑ ¥X」，百分比会失真。
/// - 其余 → 百分比，变化不到 0.05% 不显示。
///
/// [up] 表示本期比上期多，颜色好坏由调用方按指标决定。
({String text, bool up})? deltaBadgeText({
  required Decimal current,
  required Decimal? previous,
}) {
  final base = previous;
  if (base == null) return null;
  if (base == Decimal.zero && current == Decimal.zero) return null;
  if (base == Decimal.zero) {
    final v = MoneyFormat.toDouble(current);
    return (text: '新增 ${MoneyFormat.axisLabel(v.abs())}', up: v > 0);
  }
  final cur = MoneyFormat.toDouble(current);
  final prev = MoneyFormat.toDouble(base);
  if (current < Decimal.zero || base < Decimal.zero) {
    final diff = cur - prev;
    if (diff == 0) return null;
    return (
      text: '${diff > 0 ? '↑' : '↓'} ${MoneyFormat.axisLabel(diff.abs())}',
      up: diff > 0,
    );
  }
  final pct = (cur - prev) / prev * 100;
  if (pct.abs() < 0.05) return null;
  final pctText = pct.abs() >= 10
      ? pct.abs().toStringAsFixed(0)
      : pct.abs().toStringAsFixed(1);
  return (text: '${pct > 0 ? '↑' : '↓'} $pctText%', up: pct > 0);
}
