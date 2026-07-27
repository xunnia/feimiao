import 'package:decimal/decimal.dart';

import 'transaction_kind.dart';

/// 周期记账的频率。
enum RecurPeriod {
  daily,
  weekly,
  monthly,
  yearly;

  String get label => switch (this) {
        RecurPeriod.daily => '每天',
        RecurPeriod.weekly => '每周',
        RecurPeriod.monthly => '每月',
        RecurPeriod.yearly => '每年',
      };

  String toJson() => name;

  static RecurPeriod fromJson(String value) => RecurPeriod.values
      .firstWhere((e) => e.name == value, orElse: () => RecurPeriod.monthly);

  /// 在 [d] 基础上推进一个周期(月/年做月末夹取,避免 31 号溢出到下月)。
  DateTime advance(DateTime d, {int? anchorDay}) {
    switch (this) {
      case RecurPeriod.daily:
        return d.add(const Duration(days: 1));
      case RecurPeriod.weekly:
        return d.add(const Duration(days: 7));
      case RecurPeriod.monthly:
        var y = d.year;
        var m = d.month + 1;
        if (m > 12) {
          m = 1;
          y += 1;
        }
        final lastDay = DateTime(y, m + 1, 0).day;
        final targetDay = _validAnchorDay(anchorDay) ?? d.day;
        final day = targetDay < lastDay ? targetDay : lastDay;
        return DateTime(y, m, day);
      case RecurPeriod.yearly:
        final y = d.year + 1;
        final lastDay = DateTime(y, d.month + 1, 0).day;
        final targetDay = _validAnchorDay(anchorDay) ?? d.day;
        final day = targetDay < lastDay ? targetDay : lastDay;
        return DateTime(y, d.month, day);
    }
  }

  static int? _validAnchorDay(int? day) {
    if (day == null || day < 1 || day > 31) return null;
    return day;
  }

  /// 从 [firstDue] 开始预览接下来 [count] 次执行日期。
  ///
  /// 这是纯函数，供编辑页预览执行日期使用；真正入账仍由
  /// AppRepository 的到期 materialize 逻辑负责。
  List<DateTime> previewDates(
    DateTime firstDue, {
    int count = 3,
    DateTime? endDate,
  }) {
    if (count <= 0) return const [];
    final dates = <DateTime>[];
    var due = firstDue;
    final end = endDate == null
        ? null
        : DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
    final anchorDay = switch (this) {
      RecurPeriod.monthly || RecurPeriod.yearly => firstDue.day,
      _ => null,
    };
    for (var i = 0; i < count; i++) {
      if (end != null && due.isAfter(end)) break;
      dates.add(due);
      due = advance(due, anchorDay: anchorDay);
    }
    return dates;
  }
}

/// 一条周期记账规则:到期会自动生成一笔交易。
class RecurringRule {
  final int id;
  final int bookId;
  final String kind; // expense / income / transfer
  final String amountStr;
  final int? categoryId;
  final int? accountId;

  /// 仅 kind=transfer 用：转入账户（A3 房贷向导的每月自动还款走它）。
  final int? toAccountId;
  final String note;
  final String period; // RecurPeriod.name
  final int startDateMs;
  final int nextDueMs;
  final bool enabled;
  final int anchorDay;
  final int? endDateMs;
  final int? totalCount;
  final int generatedCount;

  const RecurringRule({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.amountStr,
    required this.categoryId,
    required this.accountId,
    this.toAccountId,
    required this.note,
    required this.period,
    required this.startDateMs,
    required this.nextDueMs,
    required this.enabled,
    required this.anchorDay,
    required this.endDateMs,
    required this.totalCount,
    required this.generatedCount,
  });

  Decimal get amount => Decimal.tryParse(amountStr) ?? Decimal.zero;
  TransactionKind get txKind => TransactionKind.fromJson(kind);
  RecurPeriod get recurPeriod => RecurPeriod.fromJson(period);
  DateTime get startDate => DateTime.fromMillisecondsSinceEpoch(startDateMs);
  DateTime get nextDue => DateTime.fromMillisecondsSinceEpoch(nextDueMs);
  DateTime? get endDate => endDateMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(endDateMs!);
  bool get hasCountLimit => totalCount != null && totalCount! > 0;
  bool get isCompletedByCount => hasCountLimit && generatedCount >= totalCount!;
  bool get isCompletedByDate {
    final end = endDate;
    if (end == null) return false;
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    return nextDue.isAfter(endOfDay);
  }

  bool get isCompleted => isCompletedByCount || isCompletedByDate;

  static RecurringRule fromMap(Map<String, Object?> m) => RecurringRule(
        id: m['id'] as int,
        bookId: (m['book_id'] as int?) ?? 0,
        kind: (m['kind'] as String?) ?? 'expense',
        amountStr: (m['amount'] as String?) ?? '0',
        categoryId: m['category_id'] as int?,
        accountId: m['account_id'] as int?,
        toAccountId: m['to_account_id'] as int?,
        note: (m['note'] as String?) ?? '',
        period: (m['period'] as String?) ?? 'monthly',
        startDateMs:
            (m['start_date_ms'] as int?) ?? (m['next_due_ms'] as int?) ?? 0,
        nextDueMs: (m['next_due_ms'] as int?) ?? 0,
        enabled: ((m['enabled'] as int?) ?? 1) == 1,
        anchorDay: (m['anchor_day'] as int?) ?? 0,
        endDateMs: m['end_date_ms'] as int?,
        totalCount: m['total_count'] as int?,
        generatedCount: (m['generated_count'] as int?) ?? 0,
      );
}
