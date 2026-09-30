/// 预算页上规则、金额的显示文字（docs/08 §6.8–§6.9）。纯逻辑，iOS 同名实现。
library;

import 'budget_rule_calendar.dart';
import 'budget_rule_engine.dart';
import 'budget_rules.dart';

/// 整数元，千分位：¥4,000。负数带负号。
String budgetYuanText(int cents) {
  final yuan = (cents / 100).floor();
  final negative = yuan < 0;
  final digits = yuan.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}¥$buffer';
}

/// 显示用的「还能花」：向下取整到元，负数不显示（§6.7）。
int budgetLeftDisplayCents(int remainingCents) =>
    remainingCents <= 0 ? 0 : budgetFloorYuanCents(remainingCents);

String budgetUnitText(BudgetRuleUnit unit) => switch (unit) {
      BudgetRuleUnit.day => '每天',
      BudgetRuleUnit.week => '每周',
      BudgetRuleUnit.month => '每月',
      BudgetRuleUnit.year => '每年',
    };

/// 「每月 ¥4,000」
String budgetRuleAmountText(BudgetRule rule) =>
    '${budgetUnitText(rule.unit)} ${budgetYuanText(rule.amountCents)}';

String budgetRuleName(BudgetRule rule) {
  final name = rule.name.trim();
  if (name.isNotEmpty) return name;
  return rule.isBase ? '日常' : '特别安排';
}

enum BudgetRuleState { active, upcoming, ended }

/// 一条规则在列表里的时间说明。
class BudgetRuleSpan {
  final BudgetRuleState state;

  /// 「10月起」「5月–9月」「9月25日–27日」
  final String text;

  /// 实际管到哪天（被后面的日常预算接走时有值）。
  final DateTime? effectiveEnd;

  const BudgetRuleSpan(this.state, this.text, {this.effectiveEnd});
}

String _monthText(DateTime day, {required bool withYear}) =>
    withYear ? '${day.year}年${day.month}月' : '${day.month}月';

String _dateRangeText(DateTime start, DateTime end, DateTime today) {
  final withYear = start.year != today.year || end.year != today.year;
  final head = withYear
      ? '${start.year}年${start.month}月${start.day}日'
      : '${start.month}月${start.day}日';
  if (start == end) return head;
  final tail = start.year != end.year
      ? '${end.year}年${end.month}月${end.day}日'
      : start.month != end.month
          ? '${end.month}月${end.day}日'
          : '${end.day}日';
  return '$head–$tail';
}

/// [rules] 是这个账本全部没删的规则（算日常预算被谁接走）。
BudgetRuleSpan budgetRuleSpan(
  BudgetRule rule,
  Iterable<BudgetRule> rules,
  DateTime today,
) {
  final day = budgetDay(today);
  if (!rule.isBase) {
    final end = rule.endDate!;
    final text = _dateRangeText(rule.startDate, end, day);
    if (day.isBefore(rule.startDate)) {
      return BudgetRuleSpan(BudgetRuleState.upcoming, text);
    }
    if (day.isAfter(end)) return BudgetRuleSpan(BudgetRuleState.ended, text);
    return BudgetRuleSpan(BudgetRuleState.active, text);
  }
  // 日常预算：后建、且开始日晚于它的那条最早在哪天接手。
  final calendar = BudgetRuleCalendar(rules);
  DateTime? takeover;
  for (final other in calendar.rules) {
    if (!other.isBase || identical(other, rule) || other.id == rule.id) continue;
    if (!other.outranks(rule)) continue;
    if (!other.startDate.isAfter(rule.startDate)) {
      // 从一开始就被接走了，一天都没管到。
      takeover = rule.startDate;
      break;
    }
    if (takeover == null || other.startDate.isBefore(takeover)) {
      takeover = other.startDate;
    }
  }
  final withYear = rule.startDate.year != day.year;
  if (takeover != null && !takeover.isAfter(rule.startDate)) {
    return BudgetRuleSpan(
      BudgetRuleState.ended,
      '没有生效过',
      effectiveEnd: budgetAddDays(rule.startDate, -1),
    );
  }
  if (takeover != null && !day.isBefore(takeover)) {
    final last = budgetAddDays(takeover, -1);
    final startText = _monthText(rule.startDate, withYear: withYear);
    final endText = _monthText(
      last,
      withYear: withYear || last.year != rule.startDate.year,
    );
    return BudgetRuleSpan(
      BudgetRuleState.ended,
      startText == endText ? startText : '$startText–$endText',
      effectiveEnd: last,
    );
  }
  final text = '${_monthText(rule.startDate, withYear: withYear)}起';
  if (day.isBefore(rule.startDate)) {
    return BudgetRuleSpan(BudgetRuleState.upcoming, text);
  }
  return BudgetRuleSpan(
    BudgetRuleState.active,
    text,
    effectiveEnd: takeover == null ? null : budgetAddDays(takeover, -1),
  );
}

/// 规则列表排序：新建时间倒序（§6.8）。
List<BudgetRule> budgetRulesNewestFirst(Iterable<BudgetRule> rules) =>
    rules.toList()..sort((a, b) => b.outranks(a) ? 1 : (a.outranks(b) ? -1 : 0));

/// 节奏一句话（§6.7）。
({String text, bool warning}) budgetPaceText(BudgetMonthResult month) {
  final today = month.today;
  if (today == null) return (text: '', warning: false);
  final remaining = month.remainingCents;
  if (month.effectiveCents > 0 && remaining < month.effectiveCents / 10) {
    return remaining <= 0
        ? (text: '这个月已经超出预算啦', warning: true)
        : (text: '只剩 ${budgetYuanText(budgetFloorYuanCents(remaining))} 啦', warning: true);
  }
  final delta = today.paceDeltaCents;
  if (delta >= 0) {
    return (
      text: '比计划少花 ${budgetYuanText(budgetFloorYuanCents(delta))} · 节奏不错',
      warning: false,
    );
  }
  return (
    text: '比计划多花 ${budgetYuanText(budgetFloorYuanCents(-delta))}',
    warning: true,
  );
}

/// 保存前预览里的一行。[warning] 用警示橙。
class BudgetRulePreviewLine {
  final String text;
  final bool warning;
  const BudgetRulePreviewLine(this.text, {this.warning = false});
}

/// 「每天约 ¥N」：平均到每天，四舍五入到元。
String _perDay(int cents, int days) =>
    budgetYuanText(days <= 0 ? 0 : ((cents / days) / 100).round() * 100);

/// 保存前的预览（§6.5）：这段一共多少、每天约多少、这个月总额、其余日子每天约
/// 多少、会盖掉哪条特别安排的哪几天。[existing] 是这个账本没删的全部规则，
/// [candidate] 编辑时带原 id、新建时 id 为 0。
List<BudgetRulePreviewLine> budgetRulePreview({
  required Iterable<BudgetRule> existing,
  required BudgetRule candidate,
  required DateTime today,
}) {
  final day = budgetDay(today);
  final others = [
    for (final rule in existing)
      if (!rule.isDeleted && (candidate.id == 0 || rule.id != candidate.id)) rule
  ];
  final rules = [...others, candidate];
  BudgetMonthResult resolve(List<BudgetRule> set, int year, int month) =>
      BudgetRuleEngine.resolveMonth(
        rules: set,
        spendByDay: const {},
        year: year,
        month: month,
        today: day,
      );

  if (candidate.isBase) {
    final at = candidate.startDate.isAfter(day) ? candidate.startDate : day;
    final month = resolve(rules, at.year, at.month);
    final plain = [
      for (final d in month.days)
        if (d.specialRule == null && identical(d.baseRule, candidate)) d
    ];
    return [
      BudgetRulePreviewLine('${at.month}月一共 ${budgetYuanText(month.budgetCents)}'),
      if (plain.isNotEmpty)
        BudgetRulePreviewLine(
          '平时每天约 ${_perDay(plain.fold(0, (s, d) => s + d.budgetCents), plain.length)}',
        ),
    ];
  }

  final end = candidate.endDate!;
  final count = budgetDaysBetween(candidate.startDate, end) + 1;
  final total = budgetSpecialTotalYuan(candidate) * 100;
  final lines = <BudgetRulePreviewLine>[
    BudgetRulePreviewLine(
      count == 1
          ? '这一天 ${budgetYuanText(total)}'
          : '这 $count 天一共 ${budgetYuanText(total)}，每天约 ${_perDay(total, count)}',
    ),
  ];

  final issue = BudgetRuleEngine.validateSpecial(
    existing: others,
    candidate: candidate,
  );
  if (issue != null) {
    lines.add(BudgetRulePreviewLine(
      BudgetRuleValidationText.of(issue),
      warning: true,
    ));
    return lines;
  }

  // 涉及的每个月（最多列 3 个）。
  final firstIndex = candidate.startDate.year * 12 + candidate.startDate.month - 1;
  final lastIndex = end.year * 12 + end.month - 1;
  for (var index = firstIndex; index <= lastIndex && index < firstIndex + 3; index++) {
    final year = index ~/ 12;
    final m = index % 12 + 1;
    final after = resolve(rules, year, m);
    final before = resolve(others, year, m);
    final added = after.budgetCents - before.budgetCents;
    final rest = [
      for (final d in after.days)
        if (d.specialRule == null && d.baseRule != null) d
    ];
    final restText = rest.isEmpty
        ? ''
        : '，其余日子每天约 ${_perDay(rest.fold(0, (s, d) => s + d.budgetCents), rest.length)}';
    lines.add(BudgetRulePreviewLine(
      added == 0
          ? '$m月一共还是 ${budgetYuanText(after.budgetCents)}$restText'
          : '$m月一共 ${budgetYuanText(after.budgetCents)}（多了 ${budgetYuanText(added)}）$restText',
    ));
  }
  if (lastIndex >= firstIndex + 3) {
    lines.add(const BudgetRulePreviewLine('后面几个月照同样的方法算'));
  }

  // 会盖掉哪条特别安排的哪几天。
  final oldCalendar = BudgetRuleCalendar(others);
  final newCalendar = BudgetRuleCalendar(rules);
  final covered = <BudgetRule, List<DateTime>>{};
  for (var d = candidate.startDate; !d.isAfter(end); d = budgetAddDays(d, 1)) {
    if (!identical(newCalendar.specialOwner(d), candidate)) continue;
    final previous = oldCalendar.specialOwner(d);
    if (previous != null) covered.putIfAbsent(previous, () => []).add(d);
  }
  for (final entry in covered.entries) {
    final days = entry.value;
    lines.add(BudgetRulePreviewLine(
      '会盖掉「${budgetRuleName(entry.key)}」的 ${_dateRangeText(days.first, days.last, day)}',
    ));
  }
  return lines;
}

/// 校验不通过时给用户看的话（和 [BudgetRuleValidationException] 同一套）。
class BudgetRuleValidationText {
  BudgetRuleValidationText._();

  static String of(BudgetRuleValidation validation) =>
      switch (validation.issue) {
        BudgetRuleIssue.carveWithoutBase =>
          '${validation.month}月还没有日常预算，没法从里面匀，可以改成额外多给',
        BudgetRuleIssue.carveExceedsBase =>
          '比${validation.month}月整月预算还多，其余日子会分不到钱，可以改成额外多给',
      };
}

/// 改日常预算的金额或单位时，保存前的提示（§6.4）；没改就返回 null。
String? budgetBaseEditWarning({
  required BudgetRule? original,
  required int amountCents,
  required BudgetRuleUnit unit,
  required DateTime today,
}) {
  if (original == null || !original.isBase) return null;
  if (original.amountCents == amountCents && original.unit == unit) return null;
  final start = original.startDate;
  final head = start.year != today.year
      ? '${start.year}年${start.month}月'
      : '${start.month}月';
  return '$head以来的每个月都会按新金额重新计算';
}
