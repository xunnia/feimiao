import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_period.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/statistics/consumption_projection.dart';
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
    BudgetWindowResult resolveWindow({
      required DateTime reference,
      required DateTime asOf,
      DateTime? planEnd,
      List<ConsumptionExpenseFamily> families = const [],
    }) =>
        BudgetWindowResolver.resolve(
          query: BudgetWindowQuery(
            viewKind: BudgetViewKind.calendarMonth,
            bookId: 1,
            referenceDate: reference,
            asOf: asOf,
            knowledgeCutoff: asOf,
          ),
          periods: [
            BudgetPeriod(
              id: 1,
              bookId: 1,
              start: DateTime(2026, 1, 1),
              end: planEnd,
              total: Decimal.fromInt(3000),
            ),
          ],
          expenseFamilies: families,
        );

    ConsumptionExpenseFamily expense(
      String id,
      int amount,
      DateTime date,
    ) =>
        ConsumptionExpenseFamily(
          id: id,
          bookId: 1,
          currencyCode: 'CNY',
          attributionDate: date,
          createdAt: date,
          originalAmountMinor: amount * 100,
        );

    test('fromWindowResult uses current-cycle daily guidance', () {
      final result = resolveWindow(
        reference: DateTime(2026, 6),
        asOf: DateTime(2026, 6, 10, 23, 59),
        families: [
          expense('before', 900, DateTime(2026, 6, 5)),
          expense('today', 50, DateTime(2026, 6, 10)),
        ],
      );

      final status = BudgetEngine.fromWindowResult(result)!;

      expect(status.monthlyBudget, Decimal.fromInt(3000));
      expect(status.spentThisMonth, Decimal.fromInt(950));
      expect(status.spentToday, Decimal.fromInt(50));
      expect(status.todayAllowance, Decimal.fromInt(50));
    });

    test('fromWindowResult returns null when no budget exists', () {
      final asOf = DateTime(2026, 6, 10);
      final result = BudgetWindowResolver.resolve(
        query: BudgetWindowQuery(
          viewKind: BudgetViewKind.calendarMonth,
          bookId: 1,
          referenceDate: DateTime(2026, 6),
          asOf: asOf,
          knowledgeCutoff: asOf,
        ),
        periods: const [],
      );

      expect(BudgetEngine.fromWindowResult(result), isNull);
    });

    test('fromWindowResult uses zero daily fields for a historical plan', () {
      final result = resolveWindow(
        reference: DateTime(2026, 3),
        asOf: DateTime(2026, 7, 10),
        planEnd: DateTime(2026, 5, 31),
        families: [expense('march', 100, DateTime(2026, 3, 5))],
      );

      final status = BudgetEngine.fromWindowResult(result)!;

      expect(status.spentThisMonth, Decimal.fromInt(100));
      expect(status.spentToday, Decimal.zero);
      expect(status.todayAllowance, Decimal.zero);
    });

    test('hasDailyGuidance is true only when daily guidance exists', () {
      // 当前循环周期内：有日度引导。
      final current = resolveWindow(
        reference: DateTime(2026, 6),
        asOf: DateTime(2026, 6, 10, 23, 59),
      );
      expect(BudgetEngine.fromWindowResult(current)!.hasDailyGuidance, isTrue);

      // 历史窗口：日度字段只是 0 占位，不应画「今日可用」。
      final historical = resolveWindow(
        reference: DateTime(2026, 3),
        asOf: DateTime(2026, 7, 10),
        planEnd: DateTime(2026, 5, 31),
      );
      expect(
        BudgetEngine.fromWindowResult(historical)!.hasDailyGuidance,
        isFalse,
      );
    });

    test('one-off period only yields no daily guidance', () {
      // 只有一次性区间预算（非每月循环）时没有当前循环周期，
      // 主页不应显示「今日可用 ¥0.00」满环。
      final asOf = DateTime(2026, 6, 10);
      final result = BudgetWindowResolver.resolve(
        query: BudgetWindowQuery(
          viewKind: BudgetViewKind.calendarMonth,
          bookId: 1,
          referenceDate: DateTime(2026, 6),
          asOf: asOf,
          knowledgeCutoff: asOf,
        ),
        periods: [
          BudgetPeriod(
            id: 1,
            bookId: 1,
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 30),
            total: Decimal.fromInt(3000),
            recurringMonthly: false,
          ),
        ],
      );
      final status = BudgetEngine.fromWindowResult(result)!;
      expect(status.hasDailyGuidance, isFalse);
      expect(status.spentToday, Decimal.zero);
      expect(status.todayAllowance, Decimal.zero);
    });

    test('todayAllowance', () {
      // 6 月预算 3000；6 月 1~9 日花 900，今天（10 日）花 50。
      // 今日可花 = (3000 - 900) / 21 - 50 = 50
      final records = [
        _rec(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(900),
            date: _date(5)),
        _rec(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(50),
            date: _date(10)),
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
        _rec(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(3200),
            date: _date(8)),
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
        _rec(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(500),
            date: _date(20, month: 5)),
        _rec(
            kind: TransactionKind.income,
            amount: Decimal.fromInt(8000),
            date: _date(5)),
        _rec(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(100),
            date: _date(5)),
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
