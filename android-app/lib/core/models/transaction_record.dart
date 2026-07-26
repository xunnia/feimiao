import 'package:decimal/decimal.dart';

import '../transaction_time.dart';
import 'transaction_kind.dart';

/// 平台无关的流水数据，用于统计、导入导出等纯逻辑场景。
class TransactionRecord {
  final String id;
  final TransactionKind kind;
  final Decimal amount;
  final String currencyCode;
  final String categoryName;
  final String categoryKey;
  final String topCategoryName;
  final String topCategoryKey;
  final int? accountId;
  final String accountName;

  /// 转账目标账户名，仅 kind == transfer 时有意义。
  final int? toAccountId;
  final String toAccountName;
  final String note;
  final DateTime date;
  final TransactionTimePrecision timePrecision;

  const TransactionRecord({
    required this.id,
    required this.kind,
    required this.amount,
    this.currencyCode = 'CNY',
    this.categoryName = '',
    this.categoryKey = '',
    this.topCategoryName = '',
    this.topCategoryKey = '',
    this.accountId,
    this.accountName = '',
    this.toAccountId,
    this.toAccountName = '',
    this.note = '',
    required this.date,
    this.timePrecision = TransactionTimePrecision.legacyUnknown,
  });

  /// 笔数口径（STATISTICS_CALCULATION_STANDARD §7.1 的 `expenseCount`）：
  /// **净额为正的原始消费家族**才算一笔。record 流的 [amount] 已经是净额，
  /// 所以全额退款家族在这里是 0、legacy 独立负支出是负数，两者都不占笔数。
  ///
  /// 凡是要显示「N 笔支出」的地方一律走这里，别自己 `.length`——否则同一批账
  /// 在不同页面会给出不同笔数。实体形态（[TransactionEntity]）请用
  /// `LedgerPolicy.countsAsExpenseFamily`，两者是同一条规则的两种形状。
  bool get countsAsExpenseFamily =>
      kind == TransactionKind.expense && amount > Decimal.zero;

  /// 收入笔数：计入普通收入、金额为正的收入事件。
  bool get countsAsIncomeEvent =>
      kind == TransactionKind.income && amount > Decimal.zero;

  /// 自动生成 ID 的工厂构造器（方便测试和内部创建）。
  factory TransactionRecord.create({
    required TransactionKind kind,
    required Decimal amount,
    String currencyCode = 'CNY',
    String categoryName = '',
    String categoryKey = '',
    String topCategoryName = '',
    String topCategoryKey = '',
    int? accountId,
    String accountName = '',
    int? toAccountId,
    String toAccountName = '',
    String note = '',
    required DateTime date,
    TransactionTimePrecision timePrecision =
        TransactionTimePrecision.legacyUnknown,
  }) {
    return TransactionRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      kind: kind,
      amount: amount,
      currencyCode: currencyCode,
      categoryName: categoryName,
      categoryKey: categoryKey,
      topCategoryName: topCategoryName,
      topCategoryKey: topCategoryKey,
      accountId: accountId,
      accountName: accountName,
      toAccountId: toAccountId,
      toAccountName: toAccountName,
      note: note,
      date: date,
      timePrecision: timePrecision,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionRecord &&
          id == other.id &&
          kind == other.kind &&
          amount == other.amount &&
          currencyCode == other.currencyCode &&
          categoryName == other.categoryName &&
          categoryKey == other.categoryKey &&
          topCategoryName == other.topCategoryName &&
          topCategoryKey == other.topCategoryKey &&
          accountId == other.accountId &&
          accountName == other.accountName &&
          toAccountId == other.toAccountId &&
          toAccountName == other.toAccountName &&
          note == other.note &&
          date == other.date &&
          timePrecision == other.timePrecision;

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        amount,
        currencyCode,
        categoryName,
        categoryKey,
        topCategoryName,
        topCategoryKey,
        accountId,
        accountName,
        toAccountId,
        toAccountName,
        note,
        date,
        timePrecision,
      );

  TransactionRecord copyWith({
    String? id,
    TransactionKind? kind,
    Decimal? amount,
    String? currencyCode,
    String? categoryName,
    String? categoryKey,
    String? topCategoryName,
    String? topCategoryKey,
    int? accountId,
    String? accountName,
    int? toAccountId,
    String? toAccountName,
    String? note,
    DateTime? date,
    TransactionTimePrecision? timePrecision,
  }) {
    return TransactionRecord(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      amount: amount ?? this.amount,
      currencyCode: currencyCode ?? this.currencyCode,
      categoryName: categoryName ?? this.categoryName,
      categoryKey: categoryKey ?? this.categoryKey,
      topCategoryName: topCategoryName ?? this.topCategoryName,
      topCategoryKey: topCategoryKey ?? this.topCategoryKey,
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
      toAccountId: toAccountId ?? this.toAccountId,
      toAccountName: toAccountName ?? this.toAccountName,
      note: note ?? this.note,
      date: date ?? this.date,
      timePrecision: timePrecision ?? this.timePrecision,
    );
  }
}
