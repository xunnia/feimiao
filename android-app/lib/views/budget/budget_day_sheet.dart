import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_clock.dart';
import '../../core/budget/budget_rule_display.dart';
import '../../core/budget/budget_rules.dart';
import '../../core/models/transaction_kind.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/settings_ui.dart';
import '../../widgets/transaction_day_list.dart';
import '../common/app_sheet.dart';
import 'budget_rule_colors.dart';

/// 某一天详情（docs/08 §6.9）：这天归哪条规则管、当天预算 / 花了 / 超了、当天账单。
Future<void> showBudgetDaySheet(
  BuildContext context, {
  required int bookId,
  required DateTime day,
}) =>
    showBlurSheet<void>(
      context,
      child: BudgetDaySheet(bookId: bookId, day: budgetDay(day)),
    );

class BudgetDaySheet extends StatelessWidget {
  final int bookId;
  final DateTime day;

  const BudgetDaySheet({super.key, required this.bookId, required this.day});

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  String _ruleLine(BudgetRule? special, BudgetRule? base) {
    if (special != null) {
      final funding = special.isExtra
          ? '额外多给'
          : base == null
              ? '额外多给'
              : '从${day.month}月预算里匀';
      return '归「${budgetRuleName(special)}」管 · $funding';
    }
    if (base != null) {
      return '归日常预算管 · ${budgetRuleAmountText(base)}';
    }
    return '这天没有预算，花的钱不算进预算';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final today = budgetDay(AppClock.now);
    final snapshot = repo.budgetRuleMonth(DateTime(day.year, day.month), bookId: bookId);
    final info = snapshot.month.days.firstWhere((d) => d.day == day);
    final future = day.isAfter(today);
    final spent = future ? 0 : repo.budgetSpendByDay(bookId)[budgetDayKey(day)] ?? 0;
    final over = info.covered ? spent - info.budgetCents : 0;
    final dayTx = future
        ? const <TransactionEntity>[]
        : [
            for (final t in repo.visibleTransactionsForBookView(bookId))
              if (t.txKind == TransactionKind.expense &&
                  t.refundOf == null &&
                  budgetDay(t.date) == day)
                t,
          ];
    final ruleColor = info.specialRule != null
        ? budgetRuleColor(info.specialRule!, scheme)
        : info.baseRule != null
            ? budgetRuleColor(info.baseRule!, scheme)
            : null;
    final screenH = MediaQuery.sizeOf(context).height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '${day.month}月${day.day}日 周${_weekdays[day.weekday - 1]}',
            onClose: () => Navigator.pop(context),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Row(
                      children: [
                        if (ruleColor != null) ...[
                          BudgetRuleDot(color: ruleColor),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            _ruleLine(info.specialRule, info.baseRule),
                            key: const ValueKey('budget-day-rule'),
                            style: AppType.secondary(scheme),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (info.covered) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _Stat(
                            label: '当天预算',
                            value: budgetYuanText(info.budgetCents),
                          ),
                          if (!future) ...[
                            const SizedBox(width: 8),
                            _Stat(label: '花了', value: budgetYuanText(spent)),
                          ],
                          if (!future && over >= 100) ...[
                            const SizedBox(width: 8),
                            _Stat(
                              label: '超了',
                              value: budgetYuanText(over),
                              color: AppColors.warning,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!future && over >= 100) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '多花的会从后面的日子里自动匀出来，不用管它',
                          key: const ValueKey('budget-day-tip'),
                          style: AppType.caption(scheme),
                        ),
                      ),
                    ],
                  ],
                  if (dayTx.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    TxDayCard(section: TxSection(day: day, items: dayTx)),
                  ] else if (!future) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('这天没有记支出', style: AppType.caption(scheme)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Stat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.card(scheme),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppType.caption(scheme)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color ?? scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
