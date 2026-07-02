import 'dart:convert';

import 'package:decimal/decimal.dart';

/// 一条「预算期间」：预算不再是一个覆盖所有月份的全局设置，
/// 而是阶段性的——工资涨了/环境变了就新建一条，历史月份仍显示当时生效的那条。
class BudgetPeriod {
  final int id;

  /// 归属账本；null = 不区分账本（对所有账本生效）。
  final int? bookId;

  /// 生效起（含），归一化到当天 0 点。
  final DateTime start;

  /// 生效止（含）；null = 不设终点。
  final DateTime? end;

  /// true = 每月循环额度（total 是每个月的预算）；
  /// false = 一次性区间总额（total 是整段期间的预算，如一次旅行）。
  final bool recurringMonthly;

  /// 总预算。
  final Decimal total;

  /// 分类预算明细：顶级分类 key -> 金额。
  final Map<String, Decimal> categoryBudgets;

  /// 设置时填的月收入（仅回显用，可空）。
  final Decimal? monthlyIncome;

  /// 设置时填的固定支出（仅回显用）：[(名称, 金额)]。
  final List<(String, Decimal)> fixedExpenses;

  final int createdMs;

  const BudgetPeriod({
    required this.id,
    this.bookId,
    required this.start,
    this.end,
    this.recurringMonthly = true,
    required this.total,
    this.categoryBudgets = const {},
    this.monthlyIncome,
    this.fixedExpenses = const [],
    this.createdMs = 0,
  });

  /// 是否覆盖某一天（忽略时间部分）。
  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(DateTime(start.year, start.month, start.day))) return false;
    final e = end;
    if (e == null) return true;
    return !d.isAfter(DateTime(e.year, e.month, e.day));
  }

  // ── 序列化（DB TEXT 列用 JSON 存明细）────────────────────────────────────

  String categoryBudgetsJson() =>
      jsonEncode({for (final e in categoryBudgets.entries) e.key: e.value.toString()});

  String fixedExpensesJson() => jsonEncode([
        for (final (name, amount) in fixedExpenses)
          {'n': name, 'a': amount.toString()},
      ]);

  static Map<String, Decimal> parseCategoryBudgets(String raw) {
    if (raw.isEmpty) return const {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, Decimal>{};
      m.forEach((k, v) {
        final d = Decimal.tryParse(v.toString());
        if (d != null && d > Decimal.zero) out[k] = d;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  static List<(String, Decimal)> parseFixedExpenses(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <(String, Decimal)>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final a = Decimal.tryParse((m['a'] ?? '').toString());
        if (a != null) out.add(((m['n'] ?? '').toString(), a));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  factory BudgetPeriod.fromMap(Map<String, Object?> m) => BudgetPeriod(
        id: m['id'] as int,
        bookId: m['book_id'] as int?,
        start: DateTime.fromMillisecondsSinceEpoch(m['start_ms'] as int),
        end: m['end_ms'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['end_ms'] as int),
        recurringMonthly: ((m['recurring_monthly'] as int?) ?? 1) == 1,
        total: Decimal.parse(m['total'] as String),
        categoryBudgets:
            parseCategoryBudgets(m['category_budgets'] as String? ?? ''),
        monthlyIncome: (m['monthly_income'] as String?)?.isNotEmpty == true
            ? Decimal.tryParse(m['monthly_income'] as String)
            : null,
        fixedExpenses:
            parseFixedExpenses(m['fixed_expenses'] as String? ?? ''),
        createdMs: (m['created_ms'] as int?) ?? 0,
      );
}

/// 生效期间解析：给一天，找出当时生效的预算期间。
class BudgetResolver {
  BudgetResolver._();

  /// 规则（越具体越优先）：
  /// 1. 只考虑覆盖该日、且账本匹配（期间不限账本 or 与 [bookId] 相同）的期间；
  /// 2. 一次性区间 > 每月循环（区间是"专款专用"更具体）；
  ///    同为一类时，账本专属 > 不限账本；
  /// 3. 仍并列取 start 最晚的；再并列取 createdMs 最新的（后设置的覆盖先设置的）。
  static BudgetPeriod? effectiveOn(
    List<BudgetPeriod> periods,
    DateTime day, {
    int? bookId,
  }) {
    BudgetPeriod? best;
    var bestRank = -1;
    for (final p in periods) {
      if (!p.covers(day)) continue;
      if (p.bookId != null && bookId != null && p.bookId != bookId) continue;
      final rank =
          (p.recurringMonthly ? 0 : 10) + (p.bookId != null ? 1 : 0);
      if (best == null ||
          rank > bestRank ||
          (rank == bestRank &&
              (p.start.isAfter(best.start) ||
                  (p.start == best.start && p.createdMs > best.createdMs)))) {
        best = p;
        bestRank = rank;
      }
    }
    return best;
  }

  /// 某个月生效的「月预算总额」：**按天重叠**求和（2026-07-03 起）。
  /// 逐天解析当天生效的期间，把该期间的日均额度累加：
  ///   每月循环 = total ÷ 当月天数；一次性区间 = total ÷ 区间总天数。
  /// 之前用「15 号代表日」，会漏掉不含 15 号的短区间（如 7/1–7/10 的旅行预算），
  /// 也算不了「循环 + 月中临时区间」的叠加月份。
  static Decimal? monthlyTotalFor(
    List<BudgetPeriod> periods,
    int year,
    int month, {
    int? bookId,
  }) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // 先数每个期间在当月「生效了几天」，再按日均折算，少做浮点累加。
    final coveredDays = <BudgetPeriod, int>{};
    for (var d = 1; d <= daysInMonth; d++) {
      final p =
          effectiveOn(periods, DateTime(year, month, d), bookId: bookId);
      if (p != null) coveredDays[p] = (coveredDays[p] ?? 0) + 1;
    }
    if (coveredDays.isEmpty) return null;

    var sum = 0.0;
    coveredDays.forEach((p, days) {
      if (p.recurringMonthly) {
        sum += p.total.toDouble() * days / daysInMonth;
      } else {
        final e = p.end;
        final totalDays = e == null
            ? daysInMonth
            : DateTime(e.year, e.month, e.day)
                    .difference(
                        DateTime(p.start.year, p.start.month, p.start.day))
                    .inDays +
                1;
        sum += p.total.toDouble() * days / (totalDays <= 0 ? 1 : totalDays);
      }
    });
    return Decimal.parse(sum.toStringAsFixed(2));
  }
}
