// 笔数口径反例测试（STATISTICS_CALCULATION_STANDARD §7.1 的 `expenseCount`）：
// 「窗口内净额为正的原始消费家族」才算一笔。
//
// 这里的每个 case 都会让「无条件 count += 1 / .length」的旧写法出错：
// 全额退款家族贡献 0 元却占一笔，于是同一批账在统计页、分类下钻页和
// 待报销页会给出互相矛盾的笔数。
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/models/transaction_record.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

TransactionRecord _record({
  required TransactionKind kind,
  required Decimal amount,
  String categoryName = '餐饮',
  required DateTime date,
}) =>
    TransactionRecord.create(
      kind: kind,
      amount: amount,
      categoryName: categoryName,
      date: date,
    );

void main() {
  group('TransactionRecord.countsAsExpenseFamily', () {
    final date = DateTime(2026, 7, 7, 12);

    test('净额为正的支出家族算一笔', () {
      expect(
        _record(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(50),
          date: date,
        ).countsAsExpenseFamily,
        isTrue,
      );
    });

    test('全额退款后净额归 0 的家族不算一笔', () {
      expect(
        _record(
          kind: TransactionKind.expense,
          amount: Decimal.zero,
          date: date,
        ).countsAsExpenseFamily,
        isFalse,
      );
    });

    test('legacy 独立负支出冲账行不算一笔正支出', () {
      expect(
        _record(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(-30),
          date: date,
        ).countsAsExpenseFamily,
        isFalse,
      );
    });

    test('收入不算支出笔数', () {
      expect(
        _record(
          kind: TransactionKind.income,
          amount: Decimal.fromInt(1000),
          categoryName: '工资',
          date: date,
        ).countsAsExpenseFamily,
        isFalse,
      );
    });
  });

  group('StatisticsEngine 分类笔数', () {
    test('净 0 家族不撑大分类笔数，但仍保留分类合计口径', () {
      final summary = StatisticsEngine.monthlySummary(
        [
          // 两笔真实消费
          _record(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(30),
            date: DateTime(2026, 7, 1, 12),
          ),
          _record(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(20),
            date: DateTime(2026, 7, 2, 12),
          ),
          // 一笔全额退款的家族：record 流里净额已经是 0
          _record(
            kind: TransactionKind.expense,
            amount: Decimal.zero,
            date: DateTime(2026, 7, 3, 12),
          ),
        ],
        year: 2026,
        month: 7,
      );

      final dining = summary.expenseByCategory.single;
      expect(dining.name, '餐饮');
      expect(dining.total, Decimal.fromInt(50));
      // 旧写法在这里会是 3。
      expect(dining.count, 2);
    });

    test('区间统计与年度统计使用同一笔数口径', () {
      final records = [
        _record(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(40),
          date: DateTime(2026, 7, 5, 12),
        ),
        _record(
          kind: TransactionKind.expense,
          amount: Decimal.zero,
          date: DateTime(2026, 7, 6, 12),
        ),
      ];

      final range = StatisticsEngine.rangeSummary(
        records,
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
      );
      final yearly = StatisticsEngine.yearlySummary(records, year: 2026);

      expect(range.expenseByCategory.single.count, 1);
      expect(yearly.expenseByCategory.single.count, 1);
    });
  });

  group('repo 层笔数与待报销口径', () {
    late Directory tmp;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('qingji_family_count_test_');
      await databaseFactory.setDatabasesPath(tmp.path);
    });

    tearDown(() async {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<AppRepository> freshRepo() async {
      final repo = AppRepository();
      await repo.init();
      return repo;
    }

    test('全额退款的家族不占笔数，部分退款的仍占一笔且按净额计', () async {
      final repo = await freshRepo();
      final accountId = repo.accounts.first.id;

      final fullyRefunded = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(500),
        accountId: accountId,
        date: DateTime(2026, 7, 7),
        note: '整单退掉',
      );
      final partiallyRefunded = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(200),
        accountId: accountId,
        date: DateTime(2026, 7, 7),
        note: '退了一部分',
      );
      await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(80),
        accountId: accountId,
        date: DateTime(2026, 7, 7),
        note: '没退',
      );

      await repo.refundTransaction(
        repo.transactions.singleWhere((t) => t.id == fullyRefunded),
        Decimal.fromInt(500),
        settledAt: DateTime(2026, 7, 8),
        settlementAccountId: accountId,
      );
      await repo.refundTransaction(
        repo.transactions.singleWhere((t) => t.id == partiallyRefunded),
        Decimal.fromInt(50),
        settledAt: DateTime(2026, 7, 8),
        settlementAccountId: accountId,
      );

      final visible = repo.visibleTransactions;
      // 三个原单都还在列表里（能看到划线原价），但只有两笔算支出。
      expect(visible.where((t) => t.refundOf == null), hasLength(3));
      expect(repo.expenseFamilyCountOf(visible), 2);

      // 金额侧不受影响：150 + 80，全额退款家族贡献 0。
      final total = visible.fold(
        Decimal.zero,
        (Decimal sum, t) => sum + repo.userAmountOf(t),
      );
      expect(total, Decimal.fromInt(230));

      await repo.closeForTest();
    });

    test('待报销列表按净额过滤和排序，报销到账后不再占一笔', () async {
      final repo = await freshRepo();
      final accountId = repo.accounts.first.id;

      // 原额更大但退款后净额更小：按原额排会排错，按原额过滤会多算一笔。
      final bigButRefunded = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(500),
        accountId: accountId,
        date: DateTime(2026, 7, 7),
        note: '大额但退了大半',
        reimbursable: true,
      );
      final smallIntact = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(200),
        accountId: accountId,
        date: DateTime(2026, 7, 7),
        note: '小额没退',
        reimbursable: true,
      );
      final fullyRefunded = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(300),
        accountId: accountId,
        date: DateTime(2026, 7, 7),
        note: '整单退掉',
        reimbursable: true,
      );

      await repo.refundTransaction(
        repo.transactions.singleWhere((t) => t.id == bigButRefunded),
        Decimal.fromInt(450),
        settledAt: DateTime(2026, 7, 8),
        settlementAccountId: accountId,
      );
      await repo.refundTransaction(
        repo.transactions.singleWhere((t) => t.id == fullyRefunded),
        Decimal.fromInt(300),
        settledAt: DateTime(2026, 7, 8),
        settlementAccountId: accountId,
      );

      final pending = repo.reimbursableTransactions;
      // 旧写法会是 3 笔（全额退款那笔原额 300 > 0 仍在列表里）。
      expect(pending, hasLength(2));
      expect(pending.map((t) => t.id), [smallIntact, bigButRefunded]);

      // 笔数和合计必须来自同一口径：2 笔 · 200 + 50。
      final total = pending.fold(
        Decimal.zero,
        (Decimal sum, t) => sum + repo.netAmountOf(t),
      );
      expect(total, Decimal.fromInt(250));
      expect(repo.expenseFamilyCountOf(pending), pending.length);

      await repo.markReimbursed(
        smallIntact,
        settledAt: DateTime(2026, 7, 9),
        settlementAccountId: accountId,
      );

      final afterReimbursement = repo.reimbursableTransactions;
      expect(afterReimbursement.map((t) => t.id), [bigButRefunded]);
      expect(
        afterReimbursement.fold(
          Decimal.zero,
          (Decimal sum, t) => sum + repo.netAmountOf(t),
        ),
        Decimal.fromInt(50),
      );

      await repo.closeForTest();
    });

    test('分类下钻的笔数与统计页分类笔数一致', () async {
      final repo = await freshRepo();
      final accountId = repo.accounts.first.id;
      final dining = repo.categories.firstWhere(
        (c) => c.parentId == null && c.key == 'dining',
      );

      final refundedId = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(120),
        categoryId: dining.id,
        accountId: accountId,
        date: DateTime(2026, 7, 7),
        note: '退掉的那顿',
      );
      await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(60),
        categoryId: dining.id,
        accountId: accountId,
        date: DateTime(2026, 7, 7),
        note: '正常那顿',
      );
      await repo.refundTransaction(
        repo.transactions.singleWhere((t) => t.id == refundedId),
        Decimal.fromInt(120),
        settledAt: DateTime(2026, 7, 8),
        settlementAccountId: accountId,
      );

      // 统计页环形图/分类排行的笔数
      final summary = StatisticsEngine.monthlySummary(
        repo.allRecords,
        year: 2026,
        month: 7,
      );
      final diningTotal = summary.expenseByCategory
          .singleWhere((c) => c.name == dining.nameZh);

      // 分类下钻页的笔数（同一批命中行）
      final drilldown = repo.visibleTransactions
          .where((t) =>
              !t.excluded &&
              t.txKind == TransactionKind.expense &&
              t.categoryId == dining.id)
          .toList();

      expect(diningTotal.count, 1);
      expect(repo.expenseFamilyCountOf(drilldown), diningTotal.count);
      // 列表本身仍然显示两行，方便看到已退掉的原单。
      expect(drilldown, hasLength(2));

      await repo.closeForTest();
    });

    test('LedgerPolicy 的实体形态与 record 形态给出同一笔数', () async {
      final repo = await freshRepo();
      final accountId = repo.accounts.first.id;

      final refundedId = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(90),
        accountId: accountId,
        date: DateTime(2026, 7, 7),
      );
      await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(40),
        accountId: accountId,
        date: DateTime(2026, 7, 7),
      );
      await repo.addTransaction(
        kind: TransactionKind.income,
        amount: Decimal.fromInt(1000),
        accountId: accountId,
        date: DateTime(2026, 7, 7),
      );
      await repo.refundTransaction(
        repo.transactions.singleWhere((t) => t.id == refundedId),
        Decimal.fromInt(90),
        settledAt: DateTime(2026, 7, 8),
        settlementAccountId: accountId,
      );

      final byEntity = repo.expenseFamilyCountOf(repo.visibleTransactions);
      final byRecord =
          repo.allRecords.where((r) => r.countsAsExpenseFamily).length;

      expect(byEntity, 1);
      expect(byRecord, byEntity);
      expect(
        repo.allRecords.where((r) => r.countsAsIncomeEvent).length,
        1,
      );

      await repo.closeForTest();
    });
  });
}
