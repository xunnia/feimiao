import 'dart:math' as math;

import 'package:decimal/decimal.dart';

import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';
import '../money_format.dart';
import 'statistics_engine.dart';

/// 消费画像结果。
class SpendingProfile {
  /// 画像名，如「稳健储蓄型」。
  final String title;
  final String emoji;

  /// 针对性建议（一句话）。
  final String advice;

  const SpendingProfile({
    required this.title,
    required this.emoji,
    required this.advice,
  });
}

/// 「AI 洞察」三件套：消费摘要 / 消费画像 / 超支预测。
/// 纯本地规则计算，不依赖大模型——没配 key 也全量可用。
class SpendingInsights {
  SpendingInsights._();

  /// 07 §14：和顶部涨跌徽章用同一对窗口。
  /// 当月（没过完）= 两边各取前 N 天，N = min(今天日序, 上月天数)；
  /// 已过完的月 = 整月对整月。返回 (本期, 上期, 是否截到同期)。
  static ({
    RangeSummary current,
    RangeSummary previous,
    bool sameProgress,
  }) comparableMonthWindows(
    List<TransactionRecord> records, {
    required int year,
    required int month,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final prevStart = DateTime(year, month - 1, 1);
    final prevDays = DateTime(year, month, 0).day;
    final curDays = DateTime(year, month + 1, 0).day;
    final isCurrent = n.year == year && n.month == month;
    final curN = isCurrent ? math.min(n.day, prevDays) : curDays;
    final prevN = isCurrent ? curN : prevDays;
    return (
      current: StatisticsEngine.rangeSummary(records,
          start: DateTime(year, month, 1), end: DateTime(year, month, curN)),
      previous: StatisticsEngine.rangeSummary(records,
          start: prevStart,
          end: DateTime(prevStart.year, prevStart.month, prevN)),
      sameProgress: isCurrent,
    );
  }

  /// ① 自动消费摘要：本期 vs 上期的显著变化，返回 0-3 条人话。
  /// 如「餐饮比上月同期多花 ¥120，多了 8 笔」。当月比上月同期（和顶部徽章
  /// 同一窗口，避免月初拿 9 天比上月整月永远显示「省了」）。
  static List<String> summaryLines(
    List<TransactionRecord> records, {
    required int year,
    required int month,
    DateTime? now,
  }) {
    final cur =
        StatisticsEngine.monthlySummary(records, year: year, month: month);
    final w = comparableMonthWindows(records,
        year: year, month: month, now: now);
    // 翻到过去的月份不写「本月」；「上月」相对当前看的月份，照样成立。
    final thisName = w.sameProgress ? '本月' : '$month月';
    final prevName = w.sameProgress ? '上月同期' : '上月';

    final lines = <String>[];
    final curTotal = w.current.totalExpense.toDouble();
    final prevTotal = w.previous.totalExpense.toDouble();

    // 总支出变化（上期有数据才比，避免除零和无意义对比）。
    if (prevTotal > 0 && curTotal > 0) {
      final pct = (curTotal - prevTotal) / prevTotal * 100;
      if (pct.abs() >= 10) {
        lines.add(pct > 0
            ? '$thisName总支出比$prevName多了 ${pct.toStringAsFixed(0)}%'
            : '$thisName总支出比$prevName省了 ${(-pct).toStringAsFixed(0)}%，不错喵');
      }
    }

    // 涨幅最大的分类（金额差 ≥ 50 才提，鸡毛蒜皮不说）。
    String? topName;
    var topDelta = Decimal.zero;
    int deltaCount = 0;
    for (final c in w.current.expenseByCategory) {
      if (c.total <= Decimal.zero) continue;
      final p = w.previous.expenseByCategory
          .where((x) => x.identity == c.identity)
          .toList();
      final prevTotalC = p.isEmpty ? Decimal.zero : p.first.total;
      final prevCount = p.isEmpty ? 0 : p.first.count;
      final d = c.total - prevTotalC;
      if (d > topDelta) {
        topDelta = d;
        topName = c.name;
        deltaCount = c.count - prevCount;
      }
    }
    if (topName != null && topDelta.toDouble() >= 50) {
      final countPart = deltaCount > 0 ? '，多了 $deltaCount 笔' : '';
      lines.add(
          '「$topName」比$prevName多花 ${MoneyFormat.string(topDelta)}$countPart');
    }

    // 最大头分类占比过高提醒（>45% 且总支出有规模）。占比看整月（截至今天）。
    final top =
        cur.expenseByCategory.isEmpty ? null : cur.expenseByCategory.first;
    if (top != null &&
        top.share >= 0.45 &&
        cur.totalExpense.toDouble() >= 200) {
      lines.add(
          '「${top.name}」占了$thisName支出的 ${(top.share * 100).round()}%，是绝对大头');
    }

    return lines.take(3).toList();
  }

  /// ② 消费画像：按结余率 / 大额集中度给用户贴一个「型」，附建议。
  /// 数据太少（本月支出不足 5 笔）返回 null，不瞎judge。
  static SpendingProfile? profile(
    List<TransactionRecord> records, {
    required int year,
    required int month,
  }) {
    final cur =
        StatisticsEngine.monthlySummary(records, year: year, month: month);
    final expenseCount = records
        .where((r) =>
            r.kind == TransactionKind.expense &&
            r.date.year == year &&
            r.date.month == month &&
            r.amount > Decimal.zero)
        .length;
    if (expenseCount < 5) return null;

    final expense = cur.totalExpense.toDouble();
    final income = cur.totalIncome.toDouble();

    // 大额冲动型：单笔最大支出占月支出 ≥ 35%。
    var maxSingle = 0.0;
    for (final r in records) {
      if (r.kind != TransactionKind.expense) continue;
      if (r.date.year != year || r.date.month != month) continue;
      final v = r.amount.toDouble();
      if (v > maxSingle) maxSingle = v;
    }
    if (expense > 0 && maxSingle / expense >= 0.35) {
      return const SpendingProfile(
        title: '大额冲动型',
        emoji: '🛍️',
        advice: '大件支出占比很高，下单前给自己留 24 小时冷静期',
      );
    }

    // 有收入数据 → 按结余率分。
    if (income > 0) {
      final saveRate = (income - expense) / income;
      if (saveRate < 0.05) {
        return const SpendingProfile(
          title: '月光型',
          emoji: '💸',
          advice: '本月几乎没结余，试试发工资先转 10% 进存钱目标',
        );
      }
      if (saveRate >= 0.3) {
        return const SpendingProfile(
          title: '稳健储蓄型',
          emoji: '🏦',
          advice: '结余率超过 30%，继续保持，可以考虑给闲钱找个去处',
        );
      }
      return const SpendingProfile(
        title: '收支平衡型',
        emoji: '⚖️',
        advice: '收支健康，把结余率再往 30% 推一把会更稳',
      );
    }

    // 没记收入 → 按消费稳定度粗分。
    return const SpendingProfile(
      title: '认真记账型',
      emoji: '📒',
      advice: '记上收入后，喵可以帮你算结余率和更准的画像',
    );
  }

  /// ③ 超支预测：按「本月日均」线性外推到月底，对比预算。
  /// 无预算 / 本月没支出 / 才刚开月（<3天）返回 null。
  /// 返回 (预测月底总支出, 与预算的差额>0=超, 提示文案)。
  static ({Decimal projected, Decimal overBy, String text})? forecast(
    List<TransactionRecord> records, {
    required Decimal? monthlyBudget,
    DateTime? now,
  }) {
    if (monthlyBudget == null || monthlyBudget <= Decimal.zero) return null;
    final n = now ?? DateTime.now();
    if (n.day < 3) return null; // 数据太少外推没意义

    var spent = Decimal.zero;
    for (final r in records) {
      if (r.kind != TransactionKind.expense) continue;
      if (r.date.year != n.year || r.date.month != n.month) continue;
      spent += r.amount;
    }
    if (spent <= Decimal.zero) return null;

    final daysTotal =
        StatisticsEngine.daysInMonth(year: n.year, month: n.month);
    final projectedDouble = spent.toDouble() / n.day * daysTotal;
    final projected = Decimal.parse(projectedDouble.toStringAsFixed(2));
    final overBy = projected - monthlyBudget;

    final String text;
    if (overBy > Decimal.zero) {
      final pct = (overBy.toDouble() / monthlyBudget.toDouble() * 100).round();
      text = '按当前速度，月底预计花 ${MoneyFormat.string(projected)}，'
          '可能超预算 ${MoneyFormat.string(overBy)}（+$pct%），悠着点喵';
    } else {
      text = '按当前速度，月底预计花 ${MoneyFormat.string(projected)}，'
          '在预算内，稳的';
    }
    return (projected: projected, overBy: overBy, text: text);
  }
}

/// 07 D-STAT-008：分类取两期正额分类的并集（上月花过、本期没花的也要出现），
/// 按本期金额、再按上期金额降序取前 6。
List<({String name, double cur, double prev})> compareCategoryRows(
  List<CategoryTotal> current,
  List<CategoryTotal> previous, {
  int limit = 6,
}) {
  final rows = <String, ({String name, double cur, double prev})>{};
  for (final c in current) {
    if (c.total <= Decimal.zero) continue;
    rows[c.identity] =
        (name: c.name, cur: MoneyFormat.toDouble(c.total), prev: 0);
  }
  for (final p in previous) {
    if (p.total <= Decimal.zero) continue;
    final old = rows[p.identity];
    rows[p.identity] = (
      name: old?.name ?? p.name,
      cur: old?.cur ?? 0,
      prev: MoneyFormat.toDouble(p.total),
    );
  }
  final list = rows.values.toList()
    ..sort((a, b) {
      final byCur = b.cur.compareTo(a.cur);
      return byCur != 0 ? byCur : b.prev.compareTo(a.prev);
    });
  return list.take(limit).toList();
}
