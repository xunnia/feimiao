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

  static RecurPeriod fromJson(String value) =>
      RecurPeriod.values.firstWhere((e) => e.name == value,
          orElse: () => RecurPeriod.monthly);

  /// 在 [d] 基础上推进一个周期(月/年做月末夹取,避免 31 号溢出到下月)。
  DateTime advance(DateTime d) {
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
        final day = d.day < lastDay ? d.day : lastDay;
        return DateTime(y, m, day);
      case RecurPeriod.yearly:
        final y = d.year + 1;
        final lastDay = DateTime(y, d.month + 1, 0).day;
        final day = d.day < lastDay ? d.day : lastDay;
        return DateTime(y, d.month, day);
    }
  }
}

/// 一条周期记账规则:到期会自动生成一笔交易。
class RecurringRule {
  final int id;
  final int bookId;
  final String kind; // expense / income
  final String amountStr;
  final int? categoryId;
  final int? accountId;
  final String note;
  final String period; // RecurPeriod.name
  final int nextDueMs;
  final bool enabled;

  const RecurringRule({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.amountStr,
    required this.categoryId,
    required this.accountId,
    required this.note,
    required this.period,
    required this.nextDueMs,
    required this.enabled,
  });

  Decimal get amount => Decimal.tryParse(amountStr) ?? Decimal.zero;
  TransactionKind get txKind => TransactionKind.fromJson(kind);
  RecurPeriod get recurPeriod => RecurPeriod.fromJson(period);
  DateTime get nextDue => DateTime.fromMillisecondsSinceEpoch(nextDueMs);

  static RecurringRule fromMap(Map<String, Object?> m) => RecurringRule(
        id: m['id'] as int,
        bookId: (m['book_id'] as int?) ?? 0,
        kind: (m['kind'] as String?) ?? 'expense',
        amountStr: (m['amount'] as String?) ?? '0',
        categoryId: m['category_id'] as int?,
        accountId: m['account_id'] as int?,
        note: (m['note'] as String?) ?? '',
        period: (m['period'] as String?) ?? 'monthly',
        nextDueMs: (m['next_due_ms'] as int?) ?? 0,
        enabled: ((m['enabled'] as int?) ?? 1) == 1,
      );
}
