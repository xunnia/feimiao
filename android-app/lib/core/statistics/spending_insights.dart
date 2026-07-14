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

  /// ① 自动消费摘要：本月 vs 上月的显著变化，返回 0-3 条人话。
  /// 如「餐饮比上月多花了 ¥120（+23%），主要是多了 8 笔」。
  static List<String> summaryLines(
    List<TransactionRecord> records, {
    required int year,
    required int month,
  }) {
    final cur =
        StatisticsEngine.monthlySummary(records, year: year, month: month);
    final pm = DateTime(year, month - 1, 1);
    final prev = StatisticsEngine.monthlySummary(records,
        year: pm.year, month: pm.month);

    final lines = <String>[];
    final curTotal = cur.totalExpense.toDouble();
    final prevTotal = prev.totalExpense.toDouble();

    // 总支出变化（上月有数据才比，避免除零和无意义对比）。
    if (prevTotal > 0 && curTotal > 0) {
      final pct = (curTotal - prevTotal) / prevTotal * 100;
      if (pct.abs() >= 10) {
        lines.add(pct > 0
            ? '本月总支出比上月多了 ${pct.toStringAsFixed(0)}%'
            : '本月总支出比上月省了 ${(-pct).toStringAsFixed(0)}%，不错喵');
      }
    }

    // 涨幅最大的分类（金额差 ≥ 50 才提，鸡毛蒜皮不说）。
    String? topName;
    var topDelta = Decimal.zero;
    int deltaCount = 0;
    for (final c in cur.expenseByCategory) {
      if (c.total <= Decimal.zero) continue;
      final p = prev.expenseByCategory
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
      lines.add('「$topName」比上月多花 ${MoneyFormat.string(topDelta)}$countPart');
    }

    // 最大头分类占比过高提醒（>45% 且总支出有规模）。
    final top =
        cur.expenseByCategory.isEmpty ? null : cur.expenseByCategory.first;
    if (top != null && top.share >= 0.45 && curTotal >= 200) {
      lines.add('「${top.name}」占了本月支出的 ${(top.share * 100).round()}%，是绝对大头');
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
