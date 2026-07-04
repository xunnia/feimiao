import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/transaction_kind.dart';
import '../../core/money_format.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/transaction_day_list.dart';

/// 统计下钻页：某个分类在某段区间内的支出明细（按天分组，复用主页账单行）。
/// 从环形图 / 分类排行点分类进来。
class CategoryTxnsView extends StatelessWidget {
  final String categoryName;
  final DateTime start;
  final DateTime end;

  const CategoryTxnsView({
    super.key,
    required this.categoryName,
    required this.start,
    required this.end,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final endInclusive = DateTime(end.year, end.month, end.day, 23, 59, 59);
    final txns = repo.visibleTransactions
        .where((t) =>
            !t.excluded &&
            t.txKind == TransactionKind.expense &&
            !t.date.isBefore(DateTime(start.year, start.month, start.day)) &&
            !t.date.isAfter(endInclusive) &&
            (t.categoryNameZh.isEmpty ? '未分类' : t.categoryNameZh) ==
                categoryName)
        .toList();
    // 该分类净额合计（扣退款）。
    var total = Decimal.zero;
    for (final t in txns) {
      total += repo.netAmountOf(t);
    }
    final sections = groupTxnsByDay(txns);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(categoryName),
        centerTitle: true,
      ),
      body: txns.isEmpty
          ? Center(
              child: Text('这段时间没有「$categoryName」的记录',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Text('共 ${txns.length} 笔',
                          style:
                              TextStyle(color: scheme.onSurfaceVariant)),
                      const Spacer(),
                      Text(
                        MoneyFormat.string(total),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Nunito',
                          color: AppColors.expense(scheme),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final s in sections) TxDayCard(section: s),
              ],
            ),
    );
  }
}
