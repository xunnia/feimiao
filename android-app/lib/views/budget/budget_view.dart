import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_clock.dart';
import '../../core/budget/budget_rule_display.dart';
import '../../core/budget/budget_rules.dart';
import '../../core/budget/budget_suggestion.dart';
import '../../core/haptics.dart';
import '../../data/app_repository.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/book_switch_chip.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/settings_ui.dart';
import 'budget_calendar_card.dart';
import 'budget_day_sheet.dart';
import 'budget_hero_card.dart';
import 'budget_rule_colors.dart';
import 'budget_rule_sheet.dart';

/// 预算页（docs/08 §6.8）：大数字卡、日历、规则列表、月底结余。只按自然月看。
class BudgetView extends StatefulWidget {
  /// 打开时看哪个账本；为空用当前账本。
  final int? bookId;

  const BudgetView({super.key, this.bookId});

  @override
  State<BudgetView> createState() => _BudgetViewState();
}

class _BudgetViewState extends State<BudgetView> {
  int? _bookId;
  late DateTime _month;
  bool _showEnded = false;

  @override
  void initState() {
    super.initState();
    final now = AppClock.now;
    _month = DateTime(now.year, now.month);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bookId ??= widget.bookId ?? context.read<AppRepository>().currentBookId;
  }

  void _stepMonth(int delta) {
    Haptics.selection();
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  /// 近 3 个自然月平均支出，取整到百（元）；没有支出返回 null。
  int? _suggestionYuan(AppRepository repo, int bookId) {
    final avg = BudgetSuggestion.averageMonthlySpend(
      repo.recordsForBookView(bookId),
      now: AppClock.now,
    );
    if (avg == null) return null;
    final rounded = ((avg.toDouble() / 100).round() * 100);
    return rounded < 100 ? 100 : rounded;
  }

  void _openEditor(AppRepository repo, int bookId, {BudgetRule? rule}) {
    final hasRules = repo.budgetRulesForBook(bookId).isNotEmpty;
    showBudgetRuleSheet(
      context,
      bookId: bookId,
      rule: rule,
      suggestionYuan:
          rule == null && !hasRules ? _suggestionYuan(repo, bookId) : null,
    );
  }

  void _showBookMenu(BuildContext anchor, AppRepository repo) {
    showIosMenu(anchor, [
      for (final book in repo.books)
        IosMenuItem(
          label: '${book.icon} ${book.name}',
          icon: book.id == _bookId
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          selected: book.id == _bookId,
          onTap: () => setState(() => _bookId = book.id),
        ),
    ]);
  }

  String _rolloverName(BudgetRolloverMode mode) => switch (mode) {
        BudgetRolloverMode.reset => '每月重新开始',
        BudgetRolloverMode.keepSavings => '省下的留给下个月',
        BudgetRolloverMode.carryBoth => '多退少补',
      };

  void _showRolloverMenu(BuildContext anchor, AppRepository repo, int bookId) {
    final now = AppClock.now;
    final current =
        repo.budgetRolloverModeFor(bookId, year: now.year, month: now.month);
    final prev = DateTime(now.year, now.month - 1);
    final last = repo.budgetRuleMonth(prev, bookId: bookId).month;
    final result = last.hasRules ? last.remainingCents : null;
    final pm = prev.month;
    final cm = now.month;
    // 例子用用户自己上个月的结果；上个月没预算时举个 ¥300 的例子。
    String keepExample() {
      if (result == null) return '比如$pm月省下 ¥300，$cm月就多 ¥300；超了不扣';
      if (result > 0) {
        return '$pm月省下 ${budgetYuanText(result)}，$cm月就多 ${budgetYuanText(result)}';
      }
      return '$pm月超出 ${budgetYuanText(-result)}，只留省下的，$cm月不扣';
    }

    String carryExample() {
      if (result == null) return '比如$pm月超出 ¥120，$cm月就少 ¥120；省下的也带过来';
      if (result >= 0) {
        return '$pm月省下 ${budgetYuanText(result)}，$cm月就多 ${budgetYuanText(result)}';
      }
      return '$pm月超出 ${budgetYuanText(-result)}，$cm月就少 ${budgetYuanText(-result)}';
    }

    void pick(BudgetRolloverMode mode) {
      Haptics.selection();
      repo.setBudgetRolloverMode(bookId, mode);
    }

    showIosMenu(anchor, width: 320, [
      IosMenuItem(
        key: const ValueKey('budget-rollover-reset'),
        label: _rolloverName(BudgetRolloverMode.reset),
        icon: CupertinoIcons.arrow_clockwise,
        subtitle: '每个月从头算，上个月省下或超出都不影响',
        selected: current == BudgetRolloverMode.reset,
        onTap: () => pick(BudgetRolloverMode.reset),
      ),
      IosMenuItem(
        key: const ValueKey('budget-rollover-keep'),
        label: _rolloverName(BudgetRolloverMode.keepSavings),
        icon: CupertinoIcons.arrow_turn_down_right,
        subtitle: keepExample(),
        selected: current == BudgetRolloverMode.keepSavings,
        onTap: () => pick(BudgetRolloverMode.keepSavings),
      ),
      IosMenuItem(
        key: const ValueKey('budget-rollover-carry'),
        label: _rolloverName(BudgetRolloverMode.carryBoth),
        icon: CupertinoIcons.arrow_right_arrow_left,
        subtitle: carryExample(),
        selected: current == BudgetRolloverMode.carryBoth,
        onTap: () => pick(BudgetRolloverMode.carryBoth),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final books = repo.books;
    var bookId = _bookId ?? repo.currentBookId;
    if (!books.any((b) => b.id == bookId) && books.isNotEmpty) {
      bookId = books.first.id;
    }
    final book = books.where((b) => b.id == bookId).firstOrNull;
    final today = budgetDay(AppClock.now);
    final snapshot = bookId > 0
        ? repo.budgetRuleMonth(_month, bookId: bookId)
        : null;
    final month = snapshot?.month;
    final spend = bookId > 0 ? repo.budgetSpendByDay(bookId) : const <int, int>{};
    final rules = bookId > 0 ? repo.budgetRulesForBook(bookId) : const <BudgetRule>[];
    final nextMonth = DateTime(_month.year, _month.month + 1);
    final nextMode = bookId > 0
        ? repo.budgetRolloverModeFor(bookId,
            year: nextMonth.year, month: nextMonth.month)
        : BudgetRolloverMode.reset;
    final rolloverNow = bookId > 0
        ? repo.budgetRolloverModeFor(bookId, year: today.year, month: today.month)
        : BudgetRolloverMode.reset;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('预算'),
        actions: [
          if (book != null)
            Builder(
              builder: (anchor) => AppBookSwitchChip(
                key: const ValueKey('budget-book-chip'),
                iconText: book.icon,
                label: book.name,
                maxLabelWidth: 96,
                onPressed: () => _showBookMenu(anchor, repo),
              ),
            ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AppCircleButton(
              key: const ValueKey('budget-add-rule'),
              icon: Icons.add,
              semanticLabel: '新增预算',
              onPressed: bookId > 0 ? () => _openEditor(repo, bookId) : null,
            ),
          ),
        ],
      ),
      body: month == null
          ? Center(
              child: Text('先建一个账本再设预算', style: AppType.secondary(scheme)),
            )
          : ListView(
              key: const ValueKey('budget-view-list'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                BudgetHeroCard(
                  month: month,
                  today: today,
                  suggestionCents: month.hasRules
                      ? null
                      : switch (_suggestionYuan(repo, bookId)) {
                          final yuan? => yuan * 100,
                          null => null,
                        },
                  nextMonthMode: nextMode,
                  onCreate: () => _openEditor(repo, bookId),
                ),
                if (snapshot!.excludedForeignCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                    child: Text(
                      '有 ${snapshot.excludedForeignCount} 笔外币支出没算进预算',
                      style: AppType.caption(scheme),
                    ),
                  ),
                const SizedBox(height: 12),
                BudgetCalendarCard(
                  year: month.year,
                  month: month.month,
                  days: month.days,
                  spendByDay: spend,
                  today: today,
                  onPrev: () => _stepMonth(-1),
                  onNext: () => _stepMonth(1),
                  onTapDay: (info) =>
                      showBudgetDaySheet(context, bookId: bookId, day: info.day),
                ),
                if (rules.isNotEmpty) ..._ruleSection(scheme, repo, bookId, rules, today),
                const SizedBox(height: 12),
                SettingsGroup(
                  margin: EdgeInsets.zero,
                  children: [
                    Builder(
                      builder: (anchor) => SettingsRow(
                        key: const ValueKey('budget-rollover-row'),
                        title: '月底结余',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _rolloverName(rolloverNow),
                              style: AppType.trailingValue(scheme),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              CupertinoIcons.chevron_forward,
                              size: 18,
                              color: AppTextColor.hint(scheme),
                            ),
                          ],
                        ),
                        onTap: () => _showRolloverMenu(anchor, repo, bookId),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  List<Widget> _ruleSection(
    ColorScheme scheme,
    AppRepository repo,
    int bookId,
    List<BudgetRule> rules,
    DateTime today,
  ) {
    final sorted = budgetRulesNewestFirst(rules);
    final spans = {for (final r in sorted) r.id: budgetRuleSpan(r, rules, today)};
    final live = [
      for (final r in sorted)
        if (spans[r.id]!.state != BudgetRuleState.ended) r
    ];
    final ended = [
      for (final r in sorted)
        if (spans[r.id]!.state == BudgetRuleState.ended) r
    ];
    Widget row(BudgetRule rule) {
      final span = spans[rule.id]!;
      return SettingsRow(
        key: ValueKey('budget-rule-row-${rule.id}'),
        leading: BudgetRuleDot(color: budgetRuleColor(rule, scheme)),
        title: budgetRuleName(rule),
        subtitle: '${budgetRuleAmountText(rule)} · ${span.text}',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (span.state == BudgetRuleState.upcoming)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '即将开始',
                  style: AppType.caption(scheme).copyWith(color: scheme.primary),
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 18,
              color: AppTextColor.hint(scheme),
            ),
          ],
        ),
        onTap: () => _openEditor(repo, bookId, rule: rule),
      );
    }

    return [
      const SizedBox(height: 4),
      const SettingsSectionLabel('预算规则'),
      SettingsGroup(
        margin: EdgeInsets.zero,
        children: [
          for (final rule in live) row(rule),
          if (ended.isNotEmpty)
            SettingsRow(
              key: const ValueKey('budget-ended-toggle'),
              title: '已结束 ${ended.length} 条',
              titleColor: AppTextColor.secondary(scheme),
              trailing: Icon(
                _showEnded
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                size: 18,
                color: AppTextColor.hint(scheme),
              ),
              onTap: () => setState(() => _showEnded = !_showEnded),
            ),
          if (_showEnded) for (final rule in ended) row(rule),
        ],
      ),
      if (rules.any((r) => !r.isBase))
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
          child: Text(
            '日期重叠时，以后加的特别安排为准',
            style: AppType.caption(scheme),
          ),
        ),
    ];
  }
}
