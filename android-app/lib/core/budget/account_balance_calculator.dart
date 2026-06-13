import 'package:decimal/decimal.dart';
import '../models/transaction_kind.dart';
import '../models/transaction_record.dart';

/// 账户账面余额计算：期初余额 + 收入 − 支出 + 转入 − 转出。
/// 「每周对账」用它和实际余额对比，差额一键补记。
class AccountBalanceCalculator {
  AccountBalanceCalculator._();

  static Decimal balance({
    required String accountName,
    required Decimal initialBalance,
    required List<TransactionRecord> records,
  }) {
    var result = initialBalance;
    for (final record in records) {
      switch (record.kind) {
        case TransactionKind.expense:
          if (record.accountName == accountName) {
            result -= record.amount;
          }
        case TransactionKind.income:
          if (record.accountName == accountName) {
            result += record.amount;
          }
        case TransactionKind.transfer:
          if (record.accountName == accountName) {
            result -= record.amount;
          }
          if (record.toAccountName == accountName) {
            result += record.amount;
          }
      }
    }
    return result;
  }
}
