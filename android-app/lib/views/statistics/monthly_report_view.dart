import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:provider/provider.dart';

import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../core/statistics/statistics_engine.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/mascot.dart';

/// 月度报告:把当月数据算成可读结论 + 一句猫锐评。纯本地计算,不依赖 AI。
class MonthlyReportView extends StatefulWidget {
  const MonthlyReportView({super.key});

  @override
  State<MonthlyReportView> createState() => _MonthlyReportViewState();
}

class _MonthlyReportViewState extends State<MonthlyReportView> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _year == now.year && _month == now.month;
  }

  void _step(int delta) {
    final d = DateTime(_year, _month + delta, 1);
    final now = DateTime.now();
    if (d.year > now.year || (d.year == now.year && d.month > now.month)) return;
    setState(() {
      _year = d.year;
      _month = d.month;
    });
  }

  String _money(Decimal d) => MoneyFormat.string(d);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final records = repo.allRecords;

    final cur = StatisticsEngine.monthlySummary(records,
        year: _year, month: _month);
    final pm = DateTime(_year, _month - 1, 1);
    final prev =
        StatisticsEngine.monthlySummary(records, year: pm.year, month: pm.month);

    // 当月支出明细(用于最大一笔),排除退款冲账(负支出)。
    final monthExpenses = repo.transactions.where((t) {
      return t.date.year == _year &&
          t.date.month == _month &&
          t.txKind == TransactionKind.expense &&
          t.amount > Decimal.zero;
    }).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final insights = _buildInsights(cur, prev, monthExpenses);
    final (mood, comment) = _verdict(repo, cur);

    return Scaffold(
      appBar: AppBar(title: const Text('月度报告'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          // 月份切换
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_back, size: 18),
                onPressed: () => _step(-1),
              ),
              Text('$_year 年 $_month 月',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Nunito',
                      )),
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onPressed: _isCurrentMonth ? null : () => _step(1),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 猫 + 锐评
          _card(
            scheme,
            child: Row(
              children: [
                Mascot(mood: mood, size: 52, animate: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(comment,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.4)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 概览
          _card(
            scheme,
            child: Row(
              children: [
                _stat(scheme, '支出', _money(cur.totalExpense),
                    AppColors.expense(scheme)),
                _stat(scheme, '收入', _money(cur.totalIncome),
                    AppColors.income(scheme)),
                _stat(
                    scheme,
                    '结余',
                    _money(cur.balance),
                    cur.balance >= Decimal.zero
                        ? scheme.onSurface
                        : AppColors.warning),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 洞察
          _card(
            scheme,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < insights.length; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 0.5,
                        thickness: 0.5,
                        indent: 50,
                        color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  _insightRow(scheme, insights[i].$1, insights[i].$2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _buildInsights(
    MonthlySummary cur,
    MonthlySummary prev,
    List<TransactionEntity> monthExpenses,
  ) {
    final list = <(String, String)>[];

    // 环比支出
    final prevE = prev.totalExpense.toDouble();
    if (prevE > 0) {
      final pct = (cur.totalExpense.toDouble() - prevE) / prevE * 100;
      final up = pct >= 0;
      list.add((
        up ? '📈' : '📉',
        '本月支出比上月${up ? '多' : '少'} ${pct.abs().toStringAsFixed(0)}%'
      ));
    }

    // 最大一笔
    if (monthExpenses.isNotEmpty) {
      final top = monthExpenses.first;
      final name =
          top.categoryNameZh.isNotEmpty ? top.categoryNameZh : '未分类';
      list.add((
        '💸',
        '最大一笔:$name ${_money(top.amount)}(${top.date.month}/${top.date.day})'
      ));
    }

    // 花得最多的分类
    final topCats = cur.expenseByCategory
        .where((c) => c.total > Decimal.zero)
        .toList();
    if (topCats.isNotEmpty) {
      final c = topCats.first;
      list.add((
        '🏆',
        '花得最多:${c.name} ${_money(c.total)}(占 ${(c.share * 100).toStringAsFixed(0)}%)'
      ));
    }

    // 变化最大的分类(相比上月增加最多)
    String? growName;
    var growDelta = Decimal.zero;
    for (final c in topCats) {
      final prevTotal = prev.expenseByCategory
              .where((p) => p.name == c.name)
              .firstOrNull
              ?.total ??
          Decimal.zero;
      final delta = c.total - prevTotal;
      if (delta > growDelta) {
        growDelta = delta;
        growName = c.name;
      }
    }
    if (growName != null && growDelta > Decimal.zero) {
      list.add(('🔺', '$growName 比上月多花了 ${_money(growDelta)}'));
    }

    // 日均
    final days = _isCurrentMonth
        ? DateTime.now().day
        : StatisticsEngine.daysInMonth(year: _year, month: _month);
    if (days > 0 && cur.totalExpense > Decimal.zero) {
      final avg = cur.totalExpense.toDouble() / days;
      list.add(('📅', '日均支出 ¥${avg.toStringAsFixed(0)}'));
    }

    // 最能花的一天
    DailyTotal? topDay;
    for (final d in cur.dailyTotals) {
      if (topDay == null || d.expense > topDay.expense) topDay = d;
    }
    if (topDay != null && topDay.expense > Decimal.zero) {
      list.add((
        '🔥',
        '最能花的一天:$_month/${topDay.day} 花了 ${_money(topDay.expense)}'
      ));
    }

    if (list.isEmpty) {
      list.add(('🐱', '这个月还没有记录,快去记第一笔吧~'));
    }
    return list;
  }

  (MascotMood, String) _verdict(AppRepository repo, MonthlySummary cur) {
    final budget = _isCurrentMonth ? repo.monthlyBudget : null;
    if (budget != null &&
        budget > Decimal.zero &&
        cur.totalExpense > budget) {
      return (
        MascotMood.overspend,
        '这个月花得有点猛,超了预算 ${_money(cur.totalExpense - budget)},下月收收手喵~'
      );
    }
    if (cur.totalExpense <= Decimal.zero) {
      return (MascotMood.idle, '这个月还没记支出,喵先待命啦~');
    }
    if (cur.balance > Decimal.zero && cur.totalIncome > Decimal.zero) {
      return (
        MascotMood.celebrate,
        '这个月攒下了 ${_money(cur.balance)},管得不错,继续保持喵!'
      );
    }
    return (MascotMood.report, '这个月的账喵都帮你理好啦,瞅瞅下面的小结~');
  }

  // ── 小组件 ──────────────────────────────────────────────────────────────

  Widget _card(ColorScheme scheme,
      {required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _stat(ColorScheme scheme, String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontFamily: 'Nunito',
                fontSize: 15,
              )),
        ],
      ),
    );
  }

  Widget _insightRow(ColorScheme scheme, String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.35)),
          ),
        ],
      ),
    );
  }
}
