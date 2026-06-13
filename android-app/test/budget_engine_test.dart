import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/budget/budget_engine.dart';
import 'package:qingji/core/budget/account_balance_calculator.dart';

DateTime _date(int day, {int month = 6, int year = 2026}) =>
    DateTime(year, month, day, 12);

TransactionRecord _rec({
  required TransactionKind kind,
  required Decimal amount,
  String accountName = '',
  String toAccountName = '',
  required DateTime date,
}) =>
    TransactionRecord.create(
      kind: kind,
      amount: amount,
      accountName: accountName,
      toAccountName: toAccountName,
      date: date,
    );

void main() {
  group('BudgetEngine', () {
    test('todayAllowance', () {
      // 6 月预算 3000；6 月 1~9 日花 900，今天（10 日）花 50。
      // 今日可花 = (3000 - 900) / 21 - 50 = 50
      final records = [
        _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(900), date: _date(5)),
        _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(50), date: _date(10)),
      ];
      final status = BudgetEngine.status(
        monthlyBudget: Decimal.fromInt(3000),
        records: records,
        on: _date(10),
      );
      expect(status.spentThisMonth, Decimal.fromInt(950));
      expect(status.spentToday, Decimal.fromInt(50));
      expect(status.remaining, Decimal.fromInt(2050));
      expect(status.todayAllowance, Decimal.fromInt(50));
      expect(status.isOverBudget, isFalse);
    });

    test('over budget', () {
      final records = [
        _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(3200), date: _date(8)),
      ];
      final status = BudgetEngine.status(
        monthlyBudget: Decimal.fromInt(3000),
        records: records,
        on: _date(10),
      );
      expect(status.isOverBudget, isTrue);
      expect(status.remaining, Decimal.fromInt(-200));
      expect(status.todayAllowance < Decimal.zero, isTrue);
    });

    test('other months excluded', () {
      final records = [
        _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(500), date: _date(20, month: 5)),
        _rec(kind: TransactionKind.income, amount: Decimal.fromInt(8000), date: _date(5)),
        _rec(kind: TransactionKind.expense, amount: Decimal.fromInt(100), date: _date(5)),
      ];
      final status = BudgetEngine.status(
        monthlyBudget: Decimal.fromInt(3000),
        records: records,
        on: _date(10),
      );
      expect(status.spentThisMonth, Decimal.fromInt(100));
    });
  });

  group('AccountBalanceCalculator', () {
    test('balance with transfers', () {
      final day = DateTime.fromMillisecondsSinceEpoch(1_700_000_000 * 1000);
      final records = [
        TransactionRecord.create(kind: TransactionKind.income, amount: Decimal.fromInt(1000), accountName: '微信', date: day),
        TransactionRecord.create(kind: TransactionKind.expense, amount: Decimal.fromInt(300), accountName: '微信', date: day),
        TransactionRecord.create(kind: TransactionKind.transfer, amount: Decimal.fromInt(200), accountName: '微信', toAccountName: '银行卡', date: day),
        TransactionRecord.create(kind: TransactionKind.transfer, amount: Decimal.fromInt(50), accountName: '银行卡', toAccountName: '微信', date: day),
        TransactionRecord.create(kind: TransactionKind.expense, amount: Decimal.fromInt(999), accountName: '支付宝', date: day),
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
