import 'package:decimal/decimal.dart';
import 'transaction_kind.dart';

/// 平台无关的流水数据，用于统计、导入导出等纯逻辑场景。
class TransactionRecord {
  final String id;
  final TransactionKind kind;
  final Decimal amount;
  final String currencyCode;
  final String categoryName;
  final String accountName;

  /// 转账目标账户名，仅 kind == transfer 时有意义。
  final String toAccountName;
  final String note;
  final DateTime date;

  const TransactionRecord({
    required this.id,
    required this.kind,
    required this.amount,
    this.currencyCode = 'CNY',
    this.categoryName = '',
    this.accountName = '',
    this.toAccountName = '',
    this.note = '',
    required this.date,
  });

  /// 自动生成 ID 的工厂构造器（方便测试和内部创建）。
  factory TransactionRecord.create({
    required TransactionKind kind,
    required Decimal amount,
    String currencyCode = 'CNY',
    String categoryName = '',
    String accountName = '',
    String toAccountName = '',
    String note = '',
    required DateTime date,
  }) {
    return TransactionRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      kind: kind,
      amount: amount,
      currencyCode: currencyCode,
      categoryName: categoryName,
      accountName: accountName,
      toAccountName: toAccountName,
      note: note,
      date: date,
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
          accountName == other.accountName &&
          toAccountName == other.toAccountName &&
          note == other.note &&
          date == other.date;

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        amount,
        currencyCode,
        categoryName,
        accountName,
        toAccountName,
        note,
        date,
      );

  TransactionRecord copyWith({
    String? id,
    TransactionKind? kind,
    Decimal? amount,
    String? currencyCode,
    String? categoryName,
    String? accountName,
    String? toAccountName,
    String? note,
    DateTime? date,
  }) {
    return TransactionRecord(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      amount: amount ?? this.amount,
      currencyCode: currencyCode ?? this.currencyCode,
      categoryName: categoryName ?? this.categoryName,
      accountName: accountName ?? this.accountName,
      toAccountName: toAccountName ?? this.toAccountName,
      note: note ?? this.note,
      date: date ?? this.date,
    );
  }
}
