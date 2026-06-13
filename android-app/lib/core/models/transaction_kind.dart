/// 一笔流水的类型：支出 / 收入 / 转账。
enum TransactionKind {
  expense,
  income,
  transfer;

  String toJson() => name;

  static TransactionKind fromJson(String value) =>
      TransactionKind.values.byName(value);
}
