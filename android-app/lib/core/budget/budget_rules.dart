/// 预算规则模型（docs/08-预算与资产方案.md §6，2026-09-30 用户定稿）。
///
/// 纯逻辑：不碰数据库和界面；iOS `BudgetRules.swift` 按同一算法实现。
/// - 预算金额一律按整数「元」计算；规则金额在库里按分存，必须是 100 的倍数。
/// - 支出按「分」传入，结果统一给「分」，方便沿用现有 Decimal 显示。
library;

enum BudgetRuleKind { base, special }

enum BudgetRuleUnit { day, week, month, year }

enum BudgetFunding { carve, extra }

enum BudgetRolloverMode { reset, keepSavings, carryBoth }

BudgetRuleUnit budgetRuleUnitFromDb(String value) => BudgetRuleUnit.values
    .firstWhere((unit) => unit.name == value, orElse: () => BudgetRuleUnit.month);

BudgetFunding? budgetFundingFromDb(String? value) => switch (value) {
      'carve' => BudgetFunding.carve,
      'extra' => BudgetFunding.extra,
      _ => null,
    };

BudgetRolloverMode budgetRolloverModeFromDb(String value) => switch (value) {
      'keep_savings' => BudgetRolloverMode.keepSavings,
      'carry_both' => BudgetRolloverMode.carryBoth,
      _ => BudgetRolloverMode.reset,
    };

String budgetRolloverModeToDb(BudgetRolloverMode mode) => switch (mode) {
      BudgetRolloverMode.reset => 'reset',
      BudgetRolloverMode.keepSavings => 'keep_savings',
      BudgetRolloverMode.carryBoth => 'carry_both',
    };

/// 只保留年月日的本地日期。
DateTime budgetDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 日期的整数键 yyyymmdd。
int budgetDayKey(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;

DateTime budgetAddDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

int budgetDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

int budgetDaysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

bool _isLeap(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// 单位对应的自然周期：一天、周一到周日、自然月、自然年。
({DateTime start, int length}) budgetNaturalPeriod(
    BudgetRuleUnit unit, DateTime day) {
  return switch (unit) {
    BudgetRuleUnit.day => (start: day, length: 1),
    BudgetRuleUnit.week => (start: budgetAddDays(day, 1 - day.weekday), length: 7),
    BudgetRuleUnit.month => (
        start: DateTime(day.year, day.month),
        length: budgetDaysInMonth(day.year, day.month)
      ),
    BudgetRuleUnit.year => (
        start: DateTime(day.year),
        length: _isLeap(day.year) ? 366 : 365
      ),
  };
}

/// 把 [total] 元平均分给 [count] 天，零头按 1 元一份从第一天起分；
/// 返回第 [index] 天（从 0 起）分到的。
int budgetEvenShare(int total, int count, int index) =>
    total ~/ count + (index < total % count ? 1 : 0);

class BudgetRule {
  final int id;
  final String uuid;
  final int bookId;
  final BudgetRuleKind kind;
  final String name;
  final int amountCents;
  final BudgetRuleUnit unit;
  final DateTime startDate;
  final DateTime? endDate;
  final BudgetFunding? funding;
  final int colorIndex;
  final int createdMs;
  final int updatedMs;
  final int? deletedMs;

  BudgetRule({
    required this.id,
    this.uuid = '',
    required this.bookId,
    required this.kind,
    this.name = '',
    required this.amountCents,
    required this.unit,
    required DateTime startDate,
    DateTime? endDate,
    this.funding,
    this.colorIndex = 0,
    required this.createdMs,
    int? updatedMs,
    this.deletedMs,
  })  : startDate = budgetDay(startDate),
        endDate = endDate == null ? null : budgetDay(endDate),
        updatedMs = updatedMs ?? createdMs;

  int get amountYuan => amountCents ~/ 100;
  bool get isBase => kind == BudgetRuleKind.base;
  bool get isDeleted => deletedMs != null;

  /// 「匀」是默认；只有明确写了 extra 才额外多给。
  bool get isExtra => funding == BudgetFunding.extra;

  bool coversDay(DateTime day) =>
      !day.isBefore(startDate) && (endDate == null || !day.isAfter(endDate!));

  /// 新建时间晚的优先；同一毫秒按 id。编辑不改变先后。
  bool outranks(BudgetRule other) => createdMs != other.createdMs
      ? createdMs > other.createdMs
      : id > other.id;
}

class BudgetRolloverChange {
  final int id;
  final String uuid;
  final int bookId;
  final int year;
  final int month;
  final BudgetRolloverMode mode;
  final int createdMs;
  final int updatedMs;

  const BudgetRolloverChange({
    required this.id,
    this.uuid = '',
    required this.bookId,
    required this.year,
    required this.month,
    required this.mode,
    required this.createdMs,
    int? updatedMs,
  }) : updatedMs = updatedMs ?? createdMs;

  int get monthIndex => year * 12 + month - 1;
}
