import 'package:decimal/decimal.dart';

import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';

/// 预算设置的「智能建议」计算。
/// 口径（2026-07-03 修正）：总预算**含**房租等固定支出——固定支出本身也会被记账，
/// 单独扣一遍会重复计算。建议值二选一：
///   有收入 → 收入 × (1 − 储蓄率)，默认留 20% 储蓄；
///   没收入 → 近 3 个月平均月支出（记过账就能给建议）。
/// 分类明细按用户自己近 3 个月的真实消费结构分配（比按通用法则拍脑袋更贴身）。
class BudgetSuggestion {
  BudgetSuggestion._();

  /// 按收入建议总预算 = 收入 × (1 − [savingRate])，取整元。
  /// 收入不为正时返回 null。
  static Decimal? suggestFromIncome(
    Decimal income, {
    double savingRate = 0.2,
  }) {
    if (income <= Decimal.zero) return null;
    final v = income.toDouble() * (1 - savingRate);
    if (v <= 0) return null;
    return Decimal.parse(v.toStringAsFixed(0));
  }

  /// 近 [months] 个自然月（不含本月）的平均月支出，取整元。
  /// 只对有支出记录的月份取平均（刚记 1 个月的新用户也能得到靠谱建议）；
  /// 一笔支出都没有时返回 null。
  static Decimal? averageMonthlySpend(
    List<TransactionRecord> records, {
    required DateTime now,
    int months = 3,
  }) {
    final from = DateTime(now.year, now.month - months, 1);
    final to = DateTime(now.year, now.month, 1); // 不含本月
    final byMonth = <int, double>{}; // year*100+month -> 支出合计
    for (final r in records) {
      if (r.kind != TransactionKind.expense) continue;
      if (r.amount <= Decimal.zero) continue;
      final d = DateTime(r.date.year, r.date.month, 1);
      if (d.isBefore(from) || !d.isBefore(to)) continue;
      final key = d.year * 100 + d.month;
      byMonth[key] = (byMonth[key] ?? 0) + r.amount.toDouble();
    }
    if (byMonth.isEmpty) return null;
    final avg =
        byMonth.values.reduce((a, b) => a + b) / byMonth.length;
    if (avg <= 0) return null;
    return Decimal.parse(avg.toStringAsFixed(0));
  }

  /// 近 [months] 个月（不含本月）的支出结构权重：顶级分类 key -> 占比。
  /// [topKeyOfName] 把记录里的分类名映射到顶级分类 key（映射不到的忽略）。
  static Map<String, double> historicalWeights(
    List<TransactionRecord> records, {
    required DateTime now,
    required String? Function(String categoryName) topKeyOfName,
    int months = 3,
  }) {
    final from = DateTime(now.year, now.month - months, 1);
    final to = DateTime(now.year, now.month, 1); // 不含本月
    final totals = <String, double>{};
    var sum = 0.0;
    for (final r in records) {
      if (r.kind != TransactionKind.expense) continue;
      if (r.amount <= Decimal.zero) continue;
      final d = DateTime(r.date.year, r.date.month, 1);
      if (d.isBefore(from) || !d.isBefore(to)) continue;
      final key = topKeyOfName(r.categoryName);
      if (key == null) continue;
      final v = r.amount.toDouble();
      totals[key] = (totals[key] ?? 0) + v;
      sum += v;
    }
    if (sum <= 0) return const {};
    return {for (final e in totals.entries) e.key: e.value / sum};
  }

  /// 按权重把总额切成整元份：先向下取整，剩余的零头全给权重最大的那份，
  /// 保证各份之和恰好等于总额。权重为空返回空 map。
  static Map<String, Decimal> split({
    required Decimal total,
    required Map<String, double> weights,
  }) {
    if (weights.isEmpty || total <= Decimal.zero) return const {};
    final entries = weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalInt = total.toDouble().floor();
    final out = <String, Decimal>{};
    var used = 0;
    for (final e in entries) {
      final share = (totalInt * e.value).floor();
      out[e.key] = Decimal.fromInt(share);
      used += share;
    }
    // 零头给最大头。
    final leftover = totalInt - used;
    if (leftover > 0) {
      final biggest = entries.first.key;
      out[biggest] = out[biggest]! + Decimal.fromInt(leftover);
    }
    out.removeWhere((_, v) => v <= Decimal.zero);
    return out;
  }
}
