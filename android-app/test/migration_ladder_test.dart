// 迁移阶梯测试：专门覆盖有数据变换的迁移版本。
// 纯 ADD COLUMN / CREATE TABLE 迁移风险低、不列入；
// 下列四个做了行级数据搬运/修复/删除，需显式断言。
//
// 覆盖：
//   v3  → latest : v4  account_book 创建后 transactions.book_id 回填
//   v12 → latest : v13 legacy budget 行搬入 budget_periods
//   v18 → latest : v19 退款行日期修正 + 孤儿退款行删除
//   v24 → latest : v25 recurring_rules.anchor_day 从 next_due_ms 回填
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
    tmp = Directory.systemTemp.createTempSync('qingji_migration_test_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() async {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ─────────────────────────────────────────────────────────
  // 辅助：用完整 v3 schema 建库，返回已关闭的 db path。
  // v3 是「accounts + categories + transactions（无 book_id）+ budget + app_settings」。
  // ─────────────────────────────────────────────────────────
  Future<String> _buildV3Db() async {
    final path = p.join(tmp.path, 'qingji.db');
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE accounts '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, '
            "currency_code TEXT NOT NULL DEFAULT 'CNY')",
          );
          await db.execute(
            'CREATE TABLE categories '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'key TEXT NOT NULL UNIQUE, '
            'name_zh TEXT NOT NULL, '
            'name_en TEXT NOT NULL, '
            'kind TEXT NOT NULL)',
          );
          // v4 还没有 book_id ── 关键点
          await db.execute(
            'CREATE TABLE transactions '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'kind TEXT NOT NULL, '
            'amount TEXT NOT NULL, '
            "currency_code TEXT NOT NULL DEFAULT 'CNY', "
            'category_id INTEGER, '
            'account_id INTEGER, '
            'to_account_id INTEGER, '
            "note TEXT NOT NULL DEFAULT '', "
            'date_ms INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE budget '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'amount TEXT NOT NULL, '
            'category_key TEXT)',
          );
          await db.execute(
            'CREATE TABLE app_settings '
            '(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );

          final acctId =
              await db.insert('accounts', {'name': '现金账户'});
          final catId = await db.insert('categories', {
            'key': 'dining',
            'name_zh': '食品餐饮',
            'name_en': 'Dining',
            'kind': TransactionKind.expense.toJson(),
          });
          // 两笔账单：没有 book_id 列
          final t1 = DateTime(2025, 1, 10).millisecondsSinceEpoch;
          final t2 = DateTime(2025, 2, 20).millisecondsSinceEpoch;
          await db.insert('transactions', {
            'kind': TransactionKind.expense.toJson(),
            'amount': '50.00',
            'category_id': catId,
            'account_id': acctId,
            'note': '早餐',
            'date_ms': t1,
          });
          await db.insert('transactions', {
            'kind': TransactionKind.expense.toJson(),
            'amount': '120.00',
            'category_id': catId,
            'account_id': acctId,
            'note': '午餐',
            'date_ms': t2,
          });
        },
      ),
    );
    await db.close();
    return path;
  }

  // ─────────────────────────────────────────────────────────
  // v3 → latest：v4 把所有历史账单挂到自动创建的默认账本
  // ─────────────────────────────────────────────────────────
  test('v3 → latest：v4 把历史账单 book_id 回填到默认账本', () async {
    await _buildV3Db();

    final repo = AppRepository();
    await repo.init(); // 触发 v3→42 全迁移

    // 两笔账单都应该存在，且 book_id 不为空（挂上了默认账本）
    expect(repo.transactions, hasLength(2));
    expect(repo.transactions.map((t) => t.note), containsAll(['早餐', '午餐']));

    // 验证底层 book_id 真的写进去了
    await repo.closeForTest();
    final path = p.join(tmp.path, 'qingji.db');
    final check = await databaseFactory.openDatabase(path);
    final rows = await check.query('transactions', columns: ['book_id']);
    expect(rows.every((r) => (r['book_id'] as int?) != null), isTrue,
        reason: 'v4 迁移应把所有账单挂到默认账本');
    final bookCount = Sqflite.firstIntValue(
        await check.rawQuery('SELECT COUNT(*) FROM books'));
    expect(bookCount, greaterThanOrEqualTo(1));
    // v41：老库一路升级后 transactions 应带上 order_no 列（导入退款跨批配对用）
    final columnNames = (await check.rawQuery('PRAGMA table_info(transactions)'))
        .map((r) => r['name'])
        .toSet();
    expect(columnNames, contains('order_no'));
    // v42：liability_profiles 应带上账期两列 + 借入对象列。
    final liabilityColumns =
        (await check.rawQuery('PRAGMA table_info(liability_profiles)'))
            .map((r) => r['name'])
            .toSet();
    expect(
      liabilityColumns,
      containsAll(['statement_day', 'credit_limit', 'counterparty']),
    );
    // v42：recurring_rules 应带上 to_account_id（A3 周期转账/房贷向导）。
    final recurringColumns =
        (await check.rawQuery('PRAGMA table_info(recurring_rules)'))
            .map((r) => r['name'])
            .toSet();
    expect(recurringColumns, contains('to_account_id'));
    await check.close();
  });

  // ─────────────────────────────────────────────────────────
  // v12 → latest：v13 把 legacy budget 行搬进 budget_periods
  // ─────────────────────────────────────────────────────────
  test('v12 → latest：v13 把 budget 总额与分类预算搬入 budget_periods', () async {
    final path = p.join(tmp.path, 'qingji.db');
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 12,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE accounts '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, '
            "currency_code TEXT NOT NULL DEFAULT 'CNY')",
          );
          await db.execute(
            'CREATE TABLE categories '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'key TEXT NOT NULL UNIQUE, '
            'name_zh TEXT NOT NULL, '
            'name_en TEXT NOT NULL, '
            'kind TEXT NOT NULL, '
            'parent_id INTEGER)',
          );
          await db.execute(
            'CREATE TABLE books '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            "name TEXT NOT NULL, icon TEXT NOT NULL DEFAULT '📒', "
            'sort_order INTEGER NOT NULL DEFAULT 0, '
            'created_ms INTEGER NOT NULL DEFAULT 0, '
            'starred INTEGER NOT NULL DEFAULT 0, '
            'include_in_total INTEGER NOT NULL DEFAULT 1)',
          );
          await db.execute(
            'CREATE TABLE transactions '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER, '
            'kind TEXT NOT NULL, '
            'amount TEXT NOT NULL, '
            "currency_code TEXT NOT NULL DEFAULT 'CNY', "
            'category_id INTEGER, account_id INTEGER, '
            'to_account_id INTEGER, '
            "note TEXT NOT NULL DEFAULT '', "
            'date_ms INTEGER NOT NULL, '
            "tags TEXT NOT NULL DEFAULT '', "
            'reimbursable INTEGER NOT NULL DEFAULT 0, '
            "image_path TEXT NOT NULL DEFAULT '')",
          );
          // legacy budget 表（v2 后）：一行总额 + N 行分类
          await db.execute(
            'CREATE TABLE budget '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'amount TEXT NOT NULL, '
            'category_key TEXT)',
          );
          await db.execute(
            'CREATE TABLE app_settings '
            '(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE savings_goals '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, '
            "emoji TEXT NOT NULL DEFAULT '🐷', "
            "target_amount TEXT NOT NULL DEFAULT '0', "
            "saved_amount TEXT NOT NULL DEFAULT '0', "
            'created_ms INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE tags '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, '
            'color INTEGER NOT NULL DEFAULT 4286351771)',
          );
          await db.execute(
            'CREATE TABLE chat_messages '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'role TEXT NOT NULL, '
            "text TEXT NOT NULL DEFAULT '', "
            "question TEXT NOT NULL DEFAULT '', "
            'created_ms INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE category_memory '
            '(phrase TEXT NOT NULL, kind TEXT NOT NULL, '
            'category_key TEXT NOT NULL, updated_ms INTEGER NOT NULL, '
            'PRIMARY KEY (phrase, kind))',
          );
          await db.execute(
            'CREATE TABLE recurring_rules '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER, kind TEXT NOT NULL, amount TEXT NOT NULL, '
            'category_id INTEGER, account_id INTEGER, '
            "note TEXT NOT NULL DEFAULT '', period TEXT NOT NULL, "
            'start_date_ms INTEGER NOT NULL DEFAULT 0, '
            'next_due_ms INTEGER NOT NULL, '
            'enabled INTEGER NOT NULL DEFAULT 1, '
            'anchor_day INTEGER NOT NULL DEFAULT 0, '
            'end_date_ms INTEGER, total_count INTEGER, '
            'generated_count INTEGER NOT NULL DEFAULT 0, '
            'created_ms INTEGER NOT NULL DEFAULT 0)',
          );
          await db.insert('books', {
            'name': '总账本',
            'created_ms': DateTime(2024, 1, 1).millisecondsSinceEpoch,
          });
          // legacy 总额预算行（category_key IS NULL 的行）
          await db.insert('budget', {'amount': '2000', 'category_key': null});
          // legacy 分类预算行
          await db.insert(
              'budget', {'amount': '600', 'category_key': 'dining'});
          await db.insert(
              'budget', {'amount': '200', 'category_key': 'transport'});
        },
      ),
    );
    await db.close();

    final repo = AppRepository();
    await repo.init(); // 触发 v12→42 迁移，v13 搬预算

    // v13 应该把 legacy budget 行搬成一条 budget_period
    expect(repo.budgetPeriods, hasLength(1));
    final period = repo.budgetPeriods.first;
    expect(period.total, Decimal.fromInt(2000));

    await repo.closeForTest();
    final check = await databaseFactory.openDatabase(path);
    final periodRows = await check.query('budget_periods');
    expect(periodRows, hasLength(1));
    // 分类预算应在 JSON 里
    final catBudgetsJson = periodRows.first['category_budgets'] as String;
    expect(catBudgetsJson, contains('dining'));
    expect(catBudgetsJson, contains('600'));
    await check.close();
  });

  // ─────────────────────────────────────────────────────────
  // v18 → latest：v19 修正退款日期 + 删除孤儿退款
  // ─────────────────────────────────────────────────────────
  test('v18 → latest：v19 退款日期归位到原单日期，孤儿退款行删除', () async {
    final path = p.join(tmp.path, 'qingji.db');
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 18,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE accounts '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, '
            "currency_code TEXT NOT NULL DEFAULT 'CNY')",
          );
          await db.execute(
            'CREATE TABLE categories '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'key TEXT NOT NULL UNIQUE, '
            'name_zh TEXT NOT NULL, '
            'name_en TEXT NOT NULL, '
            'kind TEXT NOT NULL, '
            'parent_id INTEGER, '
            'hidden INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE books '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            "name TEXT NOT NULL, icon TEXT NOT NULL DEFAULT '📒', "
            "cover TEXT NOT NULL DEFAULT '', "
            'sort_order INTEGER NOT NULL DEFAULT 0, '
            'created_ms INTEGER NOT NULL DEFAULT 0, '
            'starred INTEGER NOT NULL DEFAULT 0, '
            'include_in_total INTEGER NOT NULL DEFAULT 1, '
            "uuid TEXT NOT NULL DEFAULT '', "
            'updated_ms INTEGER NOT NULL DEFAULT 0)',
          );
          // v18 schema：有 excluded、uuid、updated_ms、refund_of
          await db.execute(
            'CREATE TABLE transactions '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER, '
            'kind TEXT NOT NULL, '
            'amount TEXT NOT NULL, '
            "currency_code TEXT NOT NULL DEFAULT 'CNY', "
            'category_id INTEGER, account_id INTEGER, '
            'to_account_id INTEGER, '
            "note TEXT NOT NULL DEFAULT '', "
            'date_ms INTEGER NOT NULL, '
            "tags TEXT NOT NULL DEFAULT '', "
            'reimbursable INTEGER NOT NULL DEFAULT 0, '
            "image_path TEXT NOT NULL DEFAULT '', "
            'excluded INTEGER NOT NULL DEFAULT 0, '
            "uuid TEXT NOT NULL DEFAULT '', "
            'updated_ms INTEGER NOT NULL DEFAULT 0, '
            'refund_of INTEGER)',
          );
          await db.execute(
            'CREATE TABLE budget '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'amount TEXT NOT NULL, category_key TEXT)',
          );
          // budget_periods 由 v13 创建，v18 时已存在
          await db.execute(
            'CREATE TABLE budget_periods '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER, start_ms INTEGER NOT NULL, end_ms INTEGER, '
            'recurring_monthly INTEGER NOT NULL DEFAULT 1, total TEXT NOT NULL, '
            "category_budgets TEXT NOT NULL DEFAULT '', "
            "monthly_income TEXT NOT NULL DEFAULT '', "
            "fixed_expenses TEXT NOT NULL DEFAULT '', "
            'created_ms INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE app_settings '
            '(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE savings_goals '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, '
            "emoji TEXT NOT NULL DEFAULT '🐷', "
            "target_amount TEXT NOT NULL DEFAULT '0', "
            "saved_amount TEXT NOT NULL DEFAULT '0', "
            'created_ms INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE tags '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, color INTEGER NOT NULL DEFAULT 4286351771)',
          );
          await db.execute(
            'CREATE TABLE chat_messages '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'role TEXT NOT NULL, '
            "text TEXT NOT NULL DEFAULT '', "
            "question TEXT NOT NULL DEFAULT '', "
            'created_ms INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE category_memory '
            '(phrase TEXT NOT NULL, kind TEXT NOT NULL, '
            'category_key TEXT NOT NULL, updated_ms INTEGER NOT NULL, '
            'PRIMARY KEY (phrase, kind))',
          );
          await db.execute(
            'CREATE TABLE recurring_rules '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER, kind TEXT NOT NULL, '
            'amount TEXT NOT NULL, category_id INTEGER, '
            "note TEXT NOT NULL DEFAULT '', period TEXT NOT NULL, "
            'next_due_ms INTEGER NOT NULL, '
            'enabled INTEGER NOT NULL DEFAULT 1, '
            'anchor_day INTEGER NOT NULL DEFAULT 0, '
            'created_ms INTEGER NOT NULL DEFAULT 0)',
          );

          final bookId =
              await db.insert('books', {'name': '总账本', 'created_ms': 1});
          final acctId = await db.insert('accounts', {'name': '现金'});
          final catId = await db.insert('categories', {
            'key': 'dining',
            'name_zh': '食品餐饮',
            'name_en': 'Dining',
            'kind': 'expense',
          });

          final jan15ms = DateTime(2025, 1, 15).millisecondsSinceEpoch;
          final feb1ms = DateTime(2025, 2, 1).millisecondsSinceEpoch;
          final mar1ms = DateTime(2025, 3, 1).millisecondsSinceEpoch;

          // 原单（id 必然 = 1，日期 = 1月15日）
          await db.insert('transactions', {
            'book_id': bookId,
            'kind': 'expense',
            'amount': '100.00',
            'category_id': catId,
            'account_id': acctId,
            'note': '原单',
            'date_ms': jan15ms,
          });
          // 退款行：refund_of=1，但日期错误地记成 2月1日
          await db.insert('transactions', {
            'book_id': bookId,
            'kind': 'expense',
            'amount': '-100.00',
            'category_id': catId,
            'account_id': acctId,
            'note': '退款',
            'date_ms': feb1ms,
            'refund_of': 1,
          });
          // 孤儿退款：refund_of 指向不存在的 id=9999
          await db.insert('transactions', {
            'book_id': bookId,
            'kind': 'expense',
            'amount': '-50.00',
            'category_id': catId,
            'account_id': acctId,
            'note': '孤儿退款',
            'date_ms': mar1ms,
            'refund_of': 9999,
          });
        },
      ),
    );
    await db.close();

    final repo = AppRepository();
    await repo.init(); // v18→42，v19 修日期 + 删孤儿

    // 孤儿退款被删后：原单 + 退款行 = 2 条
    expect(repo.transactions, hasLength(2));
    final notes = repo.transactions.map((t) => t.note).toSet();
    expect(notes, contains('原单'));
    expect(notes, contains('退款'));
    expect(notes, isNot(contains('孤儿退款')));

    // 退款行日期应与原单一致（1月15日）
    final refund = repo.transactions.firstWhere((t) => t.note == '退款');
    expect(refund.date.year, 2025);
    expect(refund.date.month, 1);
    expect(refund.date.day, 15);

    await repo.closeForTest();
  });

  // ─────────────────────────────────────────────────────────
  // v24 → latest：v25 从 next_due_ms 回填 anchor_day
  // ─────────────────────────────────────────────────────────
  test('v24 → latest：v25 把 anchor_day=0 的周期规则回填为到期日中的天', () async {
    final path = p.join(tmp.path, 'qingji.db');

    // 2025-03-15 12:00 local → 天数 = 15
    final nextDue15ms = DateTime(2025, 3, 15, 12).millisecondsSinceEpoch;
    final nextDue5ms = DateTime(2025, 3, 5, 12).millisecondsSinceEpoch;

    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 24,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE accounts '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, '
            "currency_code TEXT NOT NULL DEFAULT 'CNY', "
            "type TEXT NOT NULL DEFAULT 'cash', "
            "opening_balance TEXT NOT NULL DEFAULT '0', "
            'include_in_net_worth INTEGER NOT NULL DEFAULT 1, '
            "institution TEXT NOT NULL DEFAULT '', "
            'sort_order INTEGER NOT NULL DEFAULT 0, '
            'is_deleted INTEGER NOT NULL DEFAULT 0, '
            'deleted_at_ms INTEGER)',
          );
          await db.execute(
            'CREATE TABLE categories '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'key TEXT NOT NULL UNIQUE, '
            'name_zh TEXT NOT NULL, '
            'name_en TEXT NOT NULL, '
            'kind TEXT NOT NULL, '
            'parent_id INTEGER, '
            'hidden INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE books '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            "name TEXT NOT NULL, icon TEXT NOT NULL DEFAULT '📒', "
            "cover TEXT NOT NULL DEFAULT '', "
            'sort_order INTEGER NOT NULL DEFAULT 0, '
            'created_ms INTEGER NOT NULL DEFAULT 0, '
            'starred INTEGER NOT NULL DEFAULT 0, '
            'include_in_total INTEGER NOT NULL DEFAULT 1)',
          );
          await db.execute(
            'CREATE TABLE transactions '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER, kind TEXT NOT NULL, amount TEXT NOT NULL, '
            "currency_code TEXT NOT NULL DEFAULT 'CNY', "
            'category_id INTEGER, account_id INTEGER, '
            'to_account_id INTEGER, '
            "note TEXT NOT NULL DEFAULT '', "
            'date_ms INTEGER NOT NULL, '
            "tags TEXT NOT NULL DEFAULT '', "
            'reimbursable INTEGER NOT NULL DEFAULT 0, '
            "image_path TEXT NOT NULL DEFAULT '', "
            'excluded INTEGER NOT NULL DEFAULT 0, '
            "uuid TEXT NOT NULL DEFAULT '', "
            'updated_ms INTEGER NOT NULL DEFAULT 0, refund_of INTEGER)',
          );
          await db.execute(
            'CREATE TABLE budget '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'amount TEXT NOT NULL, category_key TEXT)',
          );
          // budget_periods (v13) 和 reports (v22) 在 v24 时均已存在
          await db.execute(
            'CREATE TABLE budget_periods '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER, start_ms INTEGER NOT NULL, end_ms INTEGER, '
            'recurring_monthly INTEGER NOT NULL DEFAULT 1, total TEXT NOT NULL, '
            "category_budgets TEXT NOT NULL DEFAULT '', "
            "monthly_income TEXT NOT NULL DEFAULT '', "
            "fixed_expenses TEXT NOT NULL DEFAULT '', "
            'created_ms INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS reports '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER, type TEXT NOT NULL, title TEXT NOT NULL, '
            "summary TEXT NOT NULL DEFAULT '', "
            "markdown TEXT NOT NULL DEFAULT '', "
            'period_start_ms INTEGER NOT NULL DEFAULT 0, '
            'period_end_ms INTEGER NOT NULL DEFAULT 0, '
            'created_ms INTEGER NOT NULL DEFAULT 0, '
            'pinned_ms INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE app_settings '
            '(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE savings_goals '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, '
            "emoji TEXT NOT NULL DEFAULT '🐷', "
            "target_amount TEXT NOT NULL DEFAULT '0', "
            "saved_amount TEXT NOT NULL DEFAULT '0', "
            'created_ms INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE tags '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, color INTEGER NOT NULL DEFAULT 4286351771)',
          );
          await db.execute(
            'CREATE TABLE chat_messages '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'role TEXT NOT NULL, '
            "text TEXT NOT NULL DEFAULT '', "
            "question TEXT NOT NULL DEFAULT '', "
            'created_ms INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE category_memory '
            '(phrase TEXT NOT NULL, kind TEXT NOT NULL, '
            'category_key TEXT NOT NULL, updated_ms INTEGER NOT NULL, '
            'PRIMARY KEY (phrase, kind))',
          );
          // v24 时 anchor_day 已存在（v11 建表时就有），默认 0
          await db.execute(
            'CREATE TABLE recurring_rules '
            '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER, kind TEXT NOT NULL, '
            'amount TEXT NOT NULL, category_id INTEGER, '
            'account_id INTEGER, '
            "note TEXT NOT NULL DEFAULT '', period TEXT NOT NULL, "
            'start_date_ms INTEGER NOT NULL DEFAULT 0, '
            'next_due_ms INTEGER NOT NULL, '
            'enabled INTEGER NOT NULL DEFAULT 1, '
            'anchor_day INTEGER NOT NULL DEFAULT 0, '
            'end_date_ms INTEGER, total_count INTEGER, '
            'generated_count INTEGER NOT NULL DEFAULT 0, '
            'created_ms INTEGER NOT NULL DEFAULT 0)',
          );

          final bookId = await db.insert('books', {
            'name': '总账本',
            'created_ms': DateTime(2024, 1, 1).millisecondsSinceEpoch,
          });
          // 老规则：anchor_day=0，v25 应回填为 15
          await db.insert('recurring_rules', {
            'book_id': bookId,
            'kind': 'expense',
            'amount': '300.00',
            'note': '房租',
            'period': 'monthly',
            'next_due_ms': nextDue15ms,
            'anchor_day': 0,
          });
          // 已有正确 anchor_day 的规则：v25 只改 anchor_day=0 的行
          await db.insert('recurring_rules', {
            'book_id': bookId,
            'kind': 'expense',
            'amount': '100.00',
            'note': '水电',
            'period': 'monthly',
            'next_due_ms': nextDue5ms,
            'anchor_day': 5,
          });
        },
      ),
    );
    await db.close();

    final repo = AppRepository();
    await repo.init(); // v24→42，v25 回填 anchor_day

    await repo.closeForTest();
    final check = await databaseFactory.openDatabase(path);
    final rules = await check.query('recurring_rules', orderBy: 'id');

    // 规则 1（房租）：anchor_day 应从 0 回填为 15
    expect(rules[0]['anchor_day'], 15,
        reason: 'v25 应把 anchor_day=0 的规则回填为到期日的天数');
    // 规则 2（水电）：anchor_day=5，不应被改动
    expect(rules[1]['anchor_day'], 5,
        reason: '已有正确 anchor_day 的规则不应被覆盖');

    await check.close();
  });
}
