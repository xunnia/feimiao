// 预算规则模型的仓库层测试（docs/08 §6）：真 SQLite，覆盖增删改、
// 计入预算的支出口径、账本范围、月底结余切换和 v49 → v50 迁移。
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/budget/budget_rule_status.dart';
import 'package:qingji/core/budget/budget_rules.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_budget_rules_');
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

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monthStart = DateTime(now.year, now.month);
  String dbPath() => p.join(tmp.path, 'qingji.db');

  Future<int> spend(
    AppRepository repo,
    int yuan, {
    DateTime? date,
    int? bookId,
    bool excluded = false,
  }) =>
      repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(yuan),
        accountId: repo.accounts.first.id,
        date: date ?? today.add(const Duration(hours: 9)),
        bookId: bookId ?? repo.currentBookId,
        excluded: excluded,
      );

  test('日常预算：从当月 1 号起；只算计入预算、已发生、CNY 的净支出', () async {
    var repo = await freshRepo();
    final book = repo.currentBookId;
    await repo.saveBudgetRule(
      bookId: book,
      kind: BudgetRuleKind.base,
      amountYuan: 3000,
      unit: BudgetRuleUnit.month,
    );
    final rule = repo.budgetRulesForBook(book).single;
    expect(rule.startDate, monthStart);
    expect(rule.uuid, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4')));

    final lunch = await spend(repo, 100);
    await spend(repo, 40, excluded: true);
    final foreign = await spend(repo, 9);
    await spend(repo, 50, date: today.add(const Duration(days: 1, hours: 9)));
    await repo.closeForTest();
    // App 只允许新增人民币；老数据里的外币行直接写库模拟。
    final db = await databaseFactory.openDatabase(dbPath());
    await db.update('transactions', {'currency_code': 'USD'},
        where: 'id = ?', whereArgs: [foreign]);
    await db.close();
    repo = await freshRepo();

    var month = repo.budgetRuleMonth(today);
    expect(month.plannedAmount, Decimal.fromInt(3000));
    expect(month.spentAmount, Decimal.fromInt(100));
    expect(month.excludedForeignCount, 1);
    final status = month.status!;
    expect(status.hasDailyGuidance, isTrue);
    expect(status.spentToday, Decimal.fromInt(100));

    await repo.refundTransaction(
      repo.transactionById(lunch)!,
      Decimal.fromInt(30),
      settledAt: today.add(const Duration(hours: 10)),
      settlementAccountId: repo.accounts.first.id,
    );
    month = repo.budgetRuleMonth(today);
    expect(month.spentAmount, Decimal.fromInt(70));
    await repo.closeForTest();
  });

  test('编辑不改起始月、全局生效；删除只写 deleted_ms', () async {
    final repo = await freshRepo();
    final book = repo.currentBookId;
    final id = await repo.saveBudgetRule(
      bookId: book,
      kind: BudgetRuleKind.base,
      amountYuan: 3000,
      unit: BudgetRuleUnit.month,
    );
    await repo.saveBudgetRule(
      id: id,
      bookId: book,
      kind: BudgetRuleKind.base,
      amountYuan: 3100,
      unit: BudgetRuleUnit.month,
    );
    final edited = repo.budgetRulesForBook(book).single;
    expect(edited.startDate, monthStart);
    expect(edited.amountCents, 310000);
    expect(repo.budgetRuleMonth(today).plannedAmount, Decimal.fromInt(3100));

    await repo.deleteBudgetRule(id);
    expect(repo.budgetRulesForBook(book), isEmpty);
    expect(repo.budgetRuleMonth(today).hasBudget, isFalse);
    expect(repo.budgetRuleMonth(today).status, isNull);
    await repo.closeForTest();

    final db = await databaseFactory.openDatabase(dbPath());
    final rows = await db.query('budget_rules');
    expect(rows, hasLength(1));
    expect(rows.single['deleted_ms'], isNotNull);
    await db.close();
  });

  test('特别安排：匀不下拦住；额外多给加在月总额上', () async {
    final repo = await freshRepo();
    final book = repo.currentBookId;
    await repo.saveBudgetRule(
      bookId: book,
      kind: BudgetRuleKind.base,
      amountYuan: 300,
      unit: BudgetRuleUnit.month,
    );
    await expectLater(
      repo.saveBudgetRule(
        bookId: book,
        kind: BudgetRuleKind.special,
        name: '聚会',
        amountYuan: 500,
        unit: BudgetRuleUnit.day,
        startDate: monthStart,
        endDate: monthStart.add(const Duration(days: 2)),
      ),
      throwsA(isA<BudgetRuleValidationException>()),
    );
    expect(repo.budgetRulesForBook(book), hasLength(1));

    await repo.saveBudgetRule(
      bookId: book,
      kind: BudgetRuleKind.special,
      name: '聚会',
      amountYuan: 500,
      unit: BudgetRuleUnit.day,
      startDate: monthStart,
      endDate: monthStart.add(const Duration(days: 2)),
      funding: BudgetFunding.extra,
    );
    final rules = repo.budgetRulesForBook(book);
    expect(rules, hasLength(2));
    expect(rules.map((rule) => rule.colorIndex).toSet(), hasLength(2));
    expect(repo.budgetRuleMonth(today).plannedAmount, Decimal.fromInt(1800));
    await repo.closeForTest();
  });

  test('月底结余：同一个月切换只改一行，默认每月重新开始', () async {
    final repo = await freshRepo();
    final book = repo.currentBookId;
    expect(
      repo.budgetRolloverModeFor(book, year: now.year, month: now.month),
      BudgetRolloverMode.reset,
    );
    await repo.setBudgetRolloverMode(book, BudgetRolloverMode.reset);
    await repo.setBudgetRolloverMode(book, BudgetRolloverMode.keepSavings);
    await repo.setBudgetRolloverMode(book, BudgetRolloverMode.carryBoth);
    expect(
      repo.budgetRolloverModeFor(book, year: now.year, month: now.month),
      BudgetRolloverMode.carryBoth,
    );
    final prev = DateTime(now.year, now.month - 1);
    expect(
      repo.budgetRolloverModeFor(book, year: prev.year, month: prev.month),
      BudgetRolloverMode.reset,
    );
    await repo.closeForTest();

    final db = await databaseFactory.openDatabase(dbPath());
    final rows = await db.query('budget_rollover_changes');
    expect(rows, hasLength(1));
    expect(rows.single['mode'], 'carry_both');
    await db.close();
  });

  test('总账本汇总计入总账本的支出；子账本规则不加到总账本；删账本软删规则',
      () async {
    final repo = await freshRepo();
    final total = repo.currentBookId;
    final trip = await repo.addBook(name: '旅行', includeInTotal: true);
    await repo.saveBudgetRule(
      bookId: total,
      kind: BudgetRuleKind.base,
      amountYuan: 1000,
      unit: BudgetRuleUnit.month,
    );
    await repo.saveBudgetRule(
      bookId: trip,
      kind: BudgetRuleKind.base,
      amountYuan: 400,
      unit: BudgetRuleUnit.month,
    );
    await spend(repo, 100, bookId: trip);

    final totalMonth = repo.budgetRuleMonth(today, bookId: total);
    expect(totalMonth.plannedAmount, Decimal.fromInt(1000));
    expect(totalMonth.spentAmount, Decimal.fromInt(100));
    final tripMonth = repo.budgetRuleMonth(today, bookId: trip);
    expect(tripMonth.plannedAmount, Decimal.fromInt(400));
    expect(tripMonth.spentAmount, Decimal.fromInt(100));

    await repo.deleteBook(trip, moveRecordsToDefault: true);
    expect(repo.budgetRulesForBook(trip), isEmpty);
    expect(repo.budgetRulesForBook(total), hasLength(1));
    await repo.closeForTest();
  });

  test('区间合计不带结余，只算有规则的日子', () async {
    final repo = await freshRepo();
    final book = repo.currentBookId;
    await repo.saveBudgetRule(
      bookId: book,
      kind: BudgetRuleKind.base,
      amountYuan: 70,
      unit: BudgetRuleUnit.day,
    );
    await spend(repo, 25);
    final range = repo.budgetRuleRange(
      startInclusive: monthStart.subtract(const Duration(days: 3)),
      endInclusive: today,
    );
    // 上个月那 3 天没有规则：不算预算。
    expect(range.budgetCents, 7000 * today.day);
    expect(range.spentCents, 2500);
    await repo.closeForTest();
  });

  test('v49 → v50：V2 主计划优先，其次本账本旧预算，再其次「全部账本」；已有规则跳过',
      () async {
    var repo = await freshRepo();
    final total = repo.currentBookId;
    final weekly = await repo.addBook(name: '周计划');
    final own = await repo.addBook(name: '自己的旧预算');
    final plain = await repo.addBook(name: '没设过');
    final kept = await repo.addBook(name: '已经有规则');
    final allBooksStart = DateTime(now.year - 1, 1, 1);
    final ownStart = DateTime(now.year - 1, 3, 15);
    await repo.addBudgetPeriod(start: allBooksStart, total: Decimal.fromInt(4000));
    await repo.addBudgetPeriod(
      bookId: own,
      start: ownStart,
      total: Decimal.parse('5000.4'),
    );
    await repo.addBudgetPeriod(
      bookId: weekly,
      start: ownStart,
      total: Decimal.fromInt(9999),
    );
    await repo.saveBudgetRule(
      bookId: kept,
      kind: BudgetRuleKind.base,
      amountYuan: 999,
      unit: BudgetRuleUnit.month,
    );
    await repo.closeForTest();

    final anchor = today.subtract(const Duration(days: 60));
    final anchorKey = anchor.year * 10000 + anchor.month * 100 + anchor.day;
    var db = await databaseFactory.openDatabase(dbPath());
    // 模拟升级前：只有 kept 那条规则是用户自己加的，其余都是 v49 的旧数据。
    await db.delete('budget_rules', where: 'book_id != ?', whereArgs: [kept]);
    final planId = await db.insert('budget_plans', {
      'uuid': 'plan-weekly-test',
      'book_id': weekly,
      'role': 'primary',
      'cadence': 'weekly',
      'anchor_start_day': anchorKey,
      'week_start': 1,
      'status': 'active',
      'created_ms': 1,
      'updated_ms': 1,
    });
    await db.insert('budget_plan_revisions', {
      'uuid': 'rev-weekly-test',
      'plan_id': planId,
      'effective_cycle_start_day': anchorKey,
      'amount_cents': 70050,
      'created_ms': 1,
      'updated_ms': 1,
    });
    await db.execute('PRAGMA user_version = 49');
    await db.close();

    repo = await freshRepo();
    BudgetRule only(int book) => repo.budgetRulesForBook(book).single;
    expect(only(total).amountCents, 400000);
    expect(only(total).unit, BudgetRuleUnit.month);
    expect(only(total).startDate, allBooksStart);
    expect(only(plain).amountCents, 400000);
    expect(only(own).amountCents, 500000);
    expect(only(own).startDate, DateTime(ownStart.year, ownStart.month));
    expect(only(weekly).unit, BudgetRuleUnit.week);
    expect(only(weekly).amountCents, 70100);
    expect(only(weekly).startDate, DateTime(anchor.year, anchor.month));
    expect(only(kept).amountCents, 99900);
    expect(repo.budgetRuleMonth(today, bookId: total).plannedAmount,
        Decimal.fromInt(4000));
    await repo.closeForTest();

    // 再打开一次不会重复迁移；旧表一行不删。
    repo = await freshRepo();
    expect(repo.budgetRulesForBook(total), hasLength(1));
    await repo.closeForTest();
    db = await databaseFactory.openDatabase(dbPath());
    expect(await db.query('budget_periods'), hasLength(3));
    expect(await db.query('budget_plans', where: 'id = ?', whereArgs: [planId]),
        hasLength(1));
    await db.close();
  });
}
