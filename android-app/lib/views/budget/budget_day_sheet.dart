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
    final snapshot =
        repo.budgetRuleMonth(DateTime(day.year, day.month), bookId: bookId);
    final info = snapshot.month.days.firstWhere((d) => d.day == day);
    final future = day.isAfter(today);
    final spent =
        future ? 0 : repo.budgetSpendByDay(bookId)[budgetDayKey(day)] ?? 0;
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (ruleColor != null) ...[
                          BudgetRuleDot(color: ruleColor, size: 8),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            _ruleLine(info.specialRule, info.baseRule),
                            key: const ValueKey('budget-day-rule'),
                            textAlign: TextAlign.center,
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
                      child: _DayStats(
                        budgetCents: info.budgetCents,
                        spentCents: future ? null : spent,
                        overCents: !future && over >= 100 ? over : null,
                      ),
                    ),
                    if (!future && over >= 100) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: budgetSheetTileFill(scheme),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          '多花的会从后面的日子里自动匀出来，不用管它',
                          key: const ValueKey('budget-day-tip'),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppTextColor.secondary(scheme),
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (dayTx.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    // 示意图：弹层里直接一笔一行、发丝线隔开，不再套一张带日期头的
                    // 账单卡（标题已经写了日期）。仍用统一的账单行，点一下能编辑。
                    Material(
                      type: MaterialType.transparency,
                      child: Column(
                        key: const ValueKey('budget-day-tx-list'),
                        children: [
                          for (final tx in dayTx) ...[
                            Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              height: 0.5,
                              color: AppColors.hairline(scheme, strength: 1.4),
                            ),
                            TxDismissibleRow(transaction: tx),
                          ],
                        ],
                      ),
                    ),
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

/// 详情小格和提示条使用与规则表单相同的主题填充。
Color budgetSheetTileFill(ColorScheme scheme) => AppColors.sheetFill(scheme);

class _DayStats extends StatelessWidget {
  final int budgetCents;
  final int? spentCents;
  final int? overCents;

  const _DayStats({
    required this.budgetCents,
    required this.spentCents,
    required this.overCents,
  });

  @override
  Widget build(BuildContext context) {
    final values = <({String label, String value, Color? color})>[
      (label: '当天预算', value: budgetYuanText(budgetCents), color: null),
      if (spentCents != null)
        (label: '花了', value: budgetYuanText(spentCents!), color: null),
      if (overCents != null)
        (
          label: '超了',
          value: budgetYuanText(overCents!),
          color: AppColors.warning
        ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final columnWidth =
          (constraints.maxWidth - (values.length - 1) * 8) / values.length;
      final useRows = scaler.scale(13) > 18 ||
          values.any((value) {
            final painter = TextPainter(
              text:
                  TextSpan(text: value.value, style: _Stat.valueStyle(context)),
              textDirection: Directionality.of(context),
              textScaler: scaler,
            )..layout();
            final exceedsColumn = painter.width + 24 > columnWidth;
            painter.dispose();
            return exceedsColumn;
          });
      return useRows
          ? Column(
              key: const ValueKey('budget-day-stats-rows'),
              children: [
                for (var i = 0; i < values.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _Stat(
                    label: values[i].label,
                    value: values[i].value,
                    color: values[i].color,
                    horizontal: true,
                  ),
                ],
              ],
            )
          : Row(
              key: const ValueKey('budget-day-stats-columns'),
              children: [
                for (var i = 0; i < values.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      label: values[i].label,
                      value: values[i].value,
                      color: values[i].color,
                    ),
                  ),
                ],
              ],
            );
    });
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool horizontal;

  const _Stat({
    required this.label,
    required this.value,
    this.color,
    this.horizontal = false,
  });

  static TextStyle valueStyle(BuildContext context) => TextStyle(
        fontFamily: 'Nunito',
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelText = Text(
      label,
      style: TextStyle(fontSize: 13, color: AppTextColor.hint(scheme)),
    );
    final valueText = Text(
      value,
      maxLines: 1,
      style: valueStyle(context).copyWith(color: color ?? scheme.onSurface),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: budgetSheetTileFill(scheme),
        borderRadius: BorderRadius.circular(14),
      ),
      child: horizontal
          ? Row(children: [
              Expanded(child: labelText),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(fit: BoxFit.scaleDown, child: valueText),
              ),
            ])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelText,
                const SizedBox(height: 4),
                valueText,
              ],
            ),
    );
  }
}
