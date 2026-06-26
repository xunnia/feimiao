import 'package:decimal/decimal.dart';

import 'budget/budget_engine.dart';
import 'models/transaction_kind.dart';
import 'money_format.dart';
import 'statistics/statistics_engine.dart';
import '../data/app_repository.dart';

/// 喵助手的"懂你的钱"小洞察:纯本地计算,不依赖 AI。
class MeowInsights {
  MeowInsights._();

  /// 喵助手打开时主动冒的一句话(无数据返回 null)。
  /// 优先级:超预算 → 比上月多花最多的分类 → 本月花得最多 → 兜底招呼。
  static String? greeting(AppRepository repo) {
    final records = repo.allRecords;
    final now = DateTime.now();

    // 1. 超预算
    final budget = repo.monthlyBudget;
    if (budget != null && budget > Decimal.zero) {
      final bs = BudgetEngine.status(monthlyBudget: budget, records: records);
      if (bs.remaining < Decimal.zero) {
        return '这个月有点超预算啦,剩下的日子省着点喵~有啥想问的随时说。';
      }
    }

    final cur =
        StatisticsEngine.monthlySummary(records, year: now.year, month: now.month);
    final pm = DateTime(now.year, now.month - 1, 1);
    final prev =
        StatisticsEngine.monthlySummary(records, year: pm.year, month: pm.month);

    // 2. 比上月多花最多的分类
    String? gname;
    var gdelta = Decimal.zero;
    for (final c in cur.expenseByCategory) {
      if (c.total <= Decimal.zero) continue;
      var pv = Decimal.zero;
      for (final p in prev.expenseByCategory) {
        if (p.name == c.name) {
          pv = p.total;
          break;
        }
      }
      final d = c.total - pv;
      if (d > gdelta) {
        gdelta = d;
        gname = c.name;
      }
    }
    if (gname != null && gdelta.toDouble() >= 50) {
      return '注意到「$gname」比上月多花了 ${MoneyFormat.string(gdelta)} 哦,要看看吗?';
    }

    // 3. 本月花得最多
    final pos =
        cur.expenseByCategory.where((c) => c.total > Decimal.zero).toList();
    if (pos.isNotEmpty) {
      final top = pos.reduce((a, b) => a.total >= b.total ? a : b);
      return '这个月你在「${top.name}」上花得最多(${MoneyFormat.string(top.total)}),想聊聊花销就喊我~';
    }

    // 4. 兜底
    return '喵在呢~想知道这个月花得怎么样,随时问我一句。';
  }

  /// 记完一笔后,猫给一句基于数据的反馈。
  static String recordFeedback(AppRepository repo, String categoryName) {
    if (categoryName.isEmpty || categoryName == '未分类') {
      return '记好啦,喵帮你盯着~';
    }
    final now = DateTime.now();
    var todayN = 0;
    var monthN = 0;
    var monthSum = Decimal.zero;
    for (final t in repo.transactions) {
      if (t.txKind != TransactionKind.expense) continue;
      if (t.amount <= Decimal.zero) continue;
      if (t.categoryNameZh != categoryName) continue;
      if (t.date.year == now.year && t.date.month == now.month) {
        monthN++;
        monthSum += t.amount;
        if (t.date.day == now.day) todayN++;
      }
    }
    if (todayN >= 2) {
      return '今天第 $todayN 次「$categoryName」啦,喵都记下咯~';
    }
    if (monthN >= 3) {
      return '这月「$categoryName」第 $monthN 笔咯,共 ${MoneyFormat.string(monthSum)}~';
    }
    return '记好啦!「$categoryName」本月共 ${MoneyFormat.string(monthSum)}。';
  }
}
