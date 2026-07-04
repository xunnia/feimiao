// repo 层测试：用 sqflite_common_ffi 在桌面/CI 上跑真 SQLite，
// 覆盖「最不能错」的操作：建库播种、同步戳、分类合并、删账本转移、
// 隐藏过滤、v15→v16 迁移数据完好。
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_repo_test_');
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

  test('首次建库：播种账户/分类树/总账本，新账单带 uuid+updated_ms', () async {
    final repo = await freshRepo();
    expect(repo.books, isNotEmpty);
    expect(repo.accounts, isNotEmpty);
    final cats = repo.categoriesForKindRanked(TransactionKind.expense);
    expect(cats, isNotEmpty);

    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('12.5'),
      categoryId: cats.first.id,
      accountId: repo.accounts.first.id,
      note: '测试一笔',
      date: DateTime(2026, 7, 1),
    );

    await repo.closeForTest();
    final db = await databaseFactory.openDatabase(
        p.join(tmp.path, 'qingji.db'));
    final rows = await db.query('transactions');
    expect(rows, hasLength(1));
    expect((rows.first['uuid'] as String).length, 32);
    expect(rows.first['updated_ms'] as int, greaterThan(0));
    await db.close();
  });

  test('mergeCategory：账单改挂、记忆迁移、源分类删除', () async {
    final repo = await freshRepo();
    final aId = await repo.addCategory(
        key: 'test_a', nameZh: '甲', nameEn: 'A', kind: TransactionKind.expense);
    final bId = await repo.addCategory(
        key: 'test_b', nameZh: '乙', nameEn: 'B', kind: TransactionKind.expense);
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(30),
      categoryId: aId,
      accountId: repo.accounts.first.id,
      note: '瑞幸咖啡',
      date: DateTime(2026, 7, 1),
    );
    await repo.learnCategory(
        phrase: '瑞幸', kind: TransactionKind.expense, categoryKey: 'test_a');

    await repo.mergeCategory(aId, bId);

    expect(await repo.transactionCountForCategory(bId), 1);
    expect(repo.categories.where((c) => c.id == aId), isEmpty);
    expect(
        repo.recallCategoryKey('瑞幸咖啡', TransactionKind.expense), 'test_b');
    await repo.closeForTest();
  });

  test('deleteBook 转移：账单挪到总账本，账本删除', () async {
    final repo = await freshRepo();
    final defaultBookId =
        repo.books.map((b) => b.id).reduce((a, b) => a < b ? a : b);
    final travelId = await repo.addBook(name: '旅行');
    final cats = repo.categoriesForKindRanked(TransactionKind.expense);
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(500),
      categoryId: cats.first.id,
      accountId: repo.accounts.first.id,
      note: '机票',
      date: DateTime(2026, 7, 1),
      bookId: travelId,
    );
    expect(await repo.transactionCountForBook(travelId), 1);

    await repo.deleteBook(travelId, moveRecordsToDefault: true);

    expect(repo.books.where((b) => b.id == travelId), isEmpty);
    expect(await repo.transactionCountForBook(travelId), 0);
    expect(await repo.transactionCountForBook(defaultBookId), 1);
    await repo.closeForTest();
  });

  test('隐藏分类：记账面板不出现，管理页还在', () async {
    final repo = await freshRepo();
    final top = repo.categoriesForKindRanked(TransactionKind.expense).first;
    await repo.setCategoryHidden(top.id, true);

    expect(
        repo
            .categoriesForKindRanked(TransactionKind.expense)
            .where((c) => c.id == top.id),
        isEmpty);
    expect(
        repo
            .categoriesForKind(TransactionKind.expense)
            .where((c) => c.id == top.id && c.hidden),
        isNotEmpty);
    await repo.closeForTest();
  });

  test('附着式退款：净额/已退/可见列表隐藏退款行/删除级联', () async {
    final repo = await freshRepo();
    final cats = repo.categoriesForKindRanked(TransactionKind.expense);
    final id = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(80),
      categoryId: cats.first.id,
      accountId: repo.accounts.first.id,
      note: '早餐',
      date: DateTime(2026, 7, 3),
    );
    final original = repo.transactions.firstWhere((t) => t.id == id);
    await repo.refundTransaction(original, Decimal.fromInt(5));
    await repo.refundTransaction(original, Decimal.fromInt(3));

    expect(repo.refundedAmountOf(id), Decimal.fromInt(8));
    expect(repo.netAmountOf(original), Decimal.fromInt(72));
    expect(repo.refundsOf(id), hasLength(2));
    // 退款行日期 = 原订单日期（不是记账当天）——保证跨月退款不把当月算错、
    // 表头合计与列表净额一致。
    for (final r in repo.refundsOf(id)) {
      expect(r.date, DateTime(2026, 7, 3));
    }
    // 可见列表只有原账单，退款行不单独出现。
    expect(repo.visibleTransactions.where((t) => t.id == id), hasLength(1));
    expect(repo.visibleTransactions.where((t) => t.refundOf == id), isEmpty);
    // 统计口径（allRecords 含退款负数）净额对：80−5−3=72。
    final expenseSum = repo.allRecords
        .where((r) => r.kind == TransactionKind.expense)
        .fold(Decimal.zero, (a, r) => a + r.amount);
    expect(expenseSum, Decimal.fromInt(72));
    // 删原账单，退款行一起删。
    await repo.deleteTransaction(id);
    expect(repo.transactions.where((t) => t.id == id || t.refundOf == id),
        isEmpty);
    await repo.closeForTest();
  });

  test('v15 → 最新 迁移：老账单原样保留，uuid 回填，hidden 列就位', () async {
    // 手工造一个最小 v15 库（schema 抄 v15 时的 _onCreate，无 hidden/uuid/updated_ms）。
    final path = p.join(tmp.path, 'qingji.db');
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 15,
        onCreate: (db, v) async {
          await db.execute(
              "CREATE TABLE accounts (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, currency_code TEXT NOT NULL DEFAULT 'CNY')");
          await db.execute(
              'CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT NOT NULL UNIQUE, name_zh TEXT NOT NULL, name_en TEXT NOT NULL, kind TEXT NOT NULL, parent_id INTEGER)');
          await db.execute(
              "CREATE TABLE books (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, icon TEXT NOT NULL DEFAULT '📒', cover TEXT NOT NULL DEFAULT '', sort_order INTEGER NOT NULL DEFAULT 0, created_ms INTEGER NOT NULL DEFAULT 0, starred INTEGER NOT NULL DEFAULT 0, include_in_total INTEGER NOT NULL DEFAULT 1)");
          await db.execute(
              "CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER, kind TEXT NOT NULL, amount TEXT NOT NULL, currency_code TEXT NOT NULL DEFAULT 'CNY', category_id INTEGER, account_id INTEGER, to_account_id INTEGER, note TEXT NOT NULL DEFAULT '', date_ms INTEGER NOT NULL, tags TEXT NOT NULL DEFAULT '', reimbursable INTEGER NOT NULL DEFAULT 0, image_path TEXT NOT NULL DEFAULT '', excluded INTEGER NOT NULL DEFAULT 0)");
          await db.execute(
              "CREATE TABLE savings_goals (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, emoji TEXT NOT NULL DEFAULT '🐷', target_amount TEXT NOT NULL DEFAULT '0', saved_amount TEXT NOT NULL DEFAULT '0', created_ms INTEGER NOT NULL DEFAULT 0)");
          await db.execute(
              'CREATE TABLE tags (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, color INTEGER NOT NULL DEFAULT 4286351771)');
          await db.execute(
              'CREATE TABLE budget (id INTEGER PRIMARY KEY AUTOINCREMENT, category_key TEXT, amount TEXT NOT NULL)');
          await db.execute(
              "CREATE TABLE budget_periods (id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER, start_ms INTEGER NOT NULL, end_ms INTEGER, recurring_monthly INTEGER NOT NULL DEFAULT 1, total TEXT NOT NULL, category_budgets TEXT NOT NULL DEFAULT '', monthly_income TEXT NOT NULL DEFAULT '', fixed_expenses TEXT NOT NULL DEFAULT '', created_ms INTEGER NOT NULL DEFAULT 0)");
          await db.execute(
              'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          await db.execute(
              "CREATE TABLE chat_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, text TEXT NOT NULL DEFAULT '', question TEXT NOT NULL DEFAULT '', created_ms INTEGER NOT NULL)");
          await db.execute(
              'CREATE TABLE category_memory (phrase TEXT NOT NULL, kind TEXT NOT NULL, category_key TEXT NOT NULL, updated_ms INTEGER NOT NULL, PRIMARY KEY (phrase, kind))');
          await db.execute(
              "CREATE TABLE recurring_rules (id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER, kind TEXT NOT NULL, amount TEXT NOT NULL, category_id INTEGER, account_id INTEGER, note TEXT NOT NULL DEFAULT '', period TEXT NOT NULL, next_due_ms INTEGER NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, created_ms INTEGER NOT NULL DEFAULT 0)");

          // 老数据：一个账户 + 一个账本 + 一个分类 + 一笔账。
          await db.insert('accounts', {'name': '现金'});
          await db.insert('books', {'name': '总账本', 'created_ms': 1});
          final catId = await db.insert('categories', {
            'key': 'dining',
            'name_zh': '食品餐饮',
            'name_en': 'Dining',
            'kind': TransactionKind.expense.toJson(),
          });
          await db.insert('transactions', {
            'book_id': 1,
            'kind': TransactionKind.expense.toJson(),
            'amount': '88.88',
            'category_id': catId,
            'account_id': 1,
            'note': '老账单',
            'date_ms': DateTime(2026, 6, 15).millisecondsSinceEpoch,
          });
        },
      ),
    );
    await db.close();

    final repo = AppRepository();
    await repo.init(); // 触发 v15→v16 迁移

    // 老账单原样在，金额没变。
    expect(repo.transactions, hasLength(1));
    expect(repo.transactions.first.note, '老账单');
    expect(repo.transactions.first.amount, Decimal.parse('88.88'));
    // 隐藏列就位且默认可见。
    expect(repo.categories.every((c) => !c.hidden), isTrue);

    await repo.closeForTest();
    final check = await databaseFactory.openDatabase(path);
    final v = Sqflite.firstIntValue(
        await check.rawQuery('PRAGMA user_version'));
    expect(v, 19); // init 一路升到当前最新版本
    final rows = await check.query('transactions');
    expect((rows.first['uuid'] as String).length, 32); // randomblob 回填
    expect(rows.first['updated_ms'] as int, greaterThan(0));
    await check.close();
  });
}
