import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/account_balance_calculator.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';

void main() {
  group('AccountBalanceCalculator', () {
    test('balance with transfers', () {
      final day = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
      final records = [
        TransactionRecord.create(
            kind: TransactionKind.income,
            amount: Decimal.fromInt(1000),
            accountName: '微信',
            date: day),
        TransactionRecord.create(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(300),
            accountName: '微信',
            date: day),
        TransactionRecord.create(
            kind: TransactionKind.transfer,
            amount: Decimal.fromInt(200),
            accountName: '微信',
            toAccountName: '银行卡',
            date: day),
        TransactionRecord.create(
            kind: TransactionKind.transfer,
            amount: Decimal.fromInt(50),
            accountName: '银行卡',
            toAccountName: '微信',
            date: day),
        TransactionRecord.create(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(999),
            accountName: '支付宝',
            date: day),
      ];
      final balance = AccountBalanceCalculator.balance(
        accountName: '微信',
        initialBalance: Decimal.fromInt(100),
        records: records,
      );
      // 100 + 1000 - 300 - 200 + 50 = 650
      expect(balance, Decimal.fromInt(650));
    });
  });
}
