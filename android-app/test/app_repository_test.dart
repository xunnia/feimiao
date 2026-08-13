// repo 层测试：用 sqflite_common_ffi 在桌面/CI 上跑真 SQLite，
// 覆盖「最不能错」的操作：建库播种、同步戳、分类合并、删账本转移、
// 隐藏过滤、v15→v16 迁移数据完好。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/account/account_movement_projection.dart';
import 'package:qingji/core/account/net_worth_snapshot.dart';
import 'package:qingji/core/account/net_worth_verified_checkpoint.dart';
import 'package:qingji/core/assets/asset_allocation.dart';
import 'package:qingji/core/backup/backup_package_codec.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/budget/budget_plan_v2.dart';
import 'package:qingji/core/budget/fixed_commitment.dart';
import 'package:qingji/core/import/bill_import.dart';
import 'package:qingji/core/ai/report_execution_fence.dart';
import 'package:qingji/core/money_format.dart';
import 'package:qingji/core/models/category_icon_style.dart';
import 'package:qingji/core/models/recurring_rule.dart';
import 'package:qingji/core/models/transaction_card_display.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/statistics/statistics_engine.dart';
import 'package:qingji/core/statistics/metric_contract.dart';
import 'package:qingji/core/transaction_time.dart';
import 'package:qingji/core/widgets/widget_snapshot_service.dart';
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

  /// Builds a complete current database, then reconstructs only the two tables
  /// whose schema changed in v33 with their exact v32 columns. This keeps the
  /// migration fixture small without pretending a v33 asset table is legacy.
  Future<void> installV32ArchivedAssetFixture() async {
    final seeded = await freshRepo();
    final bookId = seeded.defaultBookId;
    await seeded.closeForTest();

    final db = await databaseFactory.openDatabase(
      p.join(tmp.path, 'qingji.db'),
    );
    await db.transaction((txn) async {
      for (final table in [
        'asset_transaction_links',
        'asset_valuations',
        'receivable_recoveries',
        'asset_events',
      ]) {
        await txn.delete(table);
      }
      await txn.execute('DROP TABLE receivable_assets');
      await txn.execute('DROP TABLE physical_assets');
      await txn.execute('''
        CREATE TABLE physical_assets (
          id                    INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid                  TEXT NOT NULL UNIQUE,
          book_id               INTEGER,
          name                  TEXT NOT NULL,
          asset_type            TEXT NOT NULL DEFAULT 'other',
          status                TEXT NOT NULL DEFAULT 'active',
          source_type           TEXT NOT NULL DEFAULT 'historical_existing',
          purchase_price        TEXT NOT NULL DEFAULT '0',
          current_value         TEXT NOT NULL DEFAULT '0',
          currency_code         TEXT NOT NULL DEFAULT 'CNY',
          purchase_date_ms      INTEGER,
          brand                 TEXT NOT NULL DEFAULT '',
          model                 TEXT NOT NULL DEFAULT '',
          location              TEXT NOT NULL DEFAULT '',
          warranty_until_ms     INTEGER,
          photo_path            TEXT NOT NULL DEFAULT '',
          invoice_path          TEXT NOT NULL DEFAULT '',
          depreciation_method   TEXT NOT NULL DEFAULT '',
          depreciation_base     TEXT NOT NULL DEFAULT '0',
          salvage_value         TEXT NOT NULL DEFAULT '0',
          useful_life_months    INTEGER NOT NULL DEFAULT 0,
          depreciation_start_ms INTEGER,
          depreciation_paused   INTEGER NOT NULL DEFAULT 0,
          note                  TEXT NOT NULL DEFAULT '',
          include_in_net_worth  INTEGER NOT NULL DEFAULT 1,
          is_deleted            INTEGER NOT NULL DEFAULT 0,
          created_ms            INTEGER NOT NULL DEFAULT 0,
          updated_ms            INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await txn.execute('''
        CREATE TABLE receivable_assets (
          id                    INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid                  TEXT NOT NULL UNIQUE,
          book_id               INTEGER,
          name                  TEXT NOT NULL,
          receivable_type       TEXT NOT NULL DEFAULT 'other',
          status                TEXT NOT NULL DEFAULT 'active',
          original_amount       TEXT NOT NULL DEFAULT '0',
          remaining_amount      TEXT NOT NULL DEFAULT '0',
          currency_code         TEXT NOT NULL DEFAULT 'CNY',
          counterparty          TEXT NOT NULL DEFAULT '',
          due_date_ms           INTEGER,
          include_in_net_worth  INTEGER NOT NULL DEFAULT 1,
          note                  TEXT NOT NULL DEFAULT '',
          is_deleted            INTEGER NOT NULL DEFAULT 0,
          created_ms            INTEGER NOT NULL DEFAULT 0,
          updated_ms            INTEGER NOT NULL DEFAULT 0
        )
      ''');

      Future<void> physical({
        required int id,
        required String name,
        required String status,
        required String value,
        required bool included,
      }) async {
        await txn.insert('physical_assets', {
          'id': id,
          'uuid': id.toString().padLeft(32, '0'),
          'book_id': bookId,
          'name': name,
          'asset_type': 'collectibles',
          'status': status,
          'source_type': 'historical_existing',
          'purchase_price': value,
          'current_value': value,
          'currency_code': 'CNY',
          'purchase_date_ms': DateTime(2025, 1, 1).millisecondsSinceEpoch,
          'include_in_net_worth': included ? 1 : 0,
          'created_ms': 10,
          'updated_ms': 20,
        });
      }

      Future<void> receivable({
        required int id,
        required String name,
        required String status,
        required String original,
        required String remaining,
        required bool included,
      }) async {
        await txn.insert('receivable_assets', {
          'id': id,
          'uuid': id.toString().padLeft(32, '0'),
          'book_id': bookId,
          'name': name,
          'receivable_type': 'rental_deposit',
          'status': status,
          'original_amount': original,
          'remaining_amount': remaining,
          'currency_code': 'CNY',
          'include_in_net_worth': included ? 1 : 0,
          'created_ms': 10,
          'updated_ms': 20,
        });
      }

      Future<int> event({
        required int id,
        required int assetId,
        required String assetType,
        required String eventType,
        required DateTime occurredAt,
        String value = '',
      }) async {
        return txn.insert('asset_events', {
          'id': id,
          'uuid': 'e${id.toString().padLeft(31, '0')}',
          'asset_id': assetId,
          'asset_type': assetType,
          'event_type': eventType,
          'occurred_ms': occurredAt.millisecondsSinceEpoch,
          'value': value,
          'created_ms': occurredAt.millisecondsSinceEpoch,
        });
      }

      await physical(
        id: 100,
        name: 'v32 active physical',
        status: 'active',
        value: '3000',
        included: true,
      );
      await physical(
        id: 101,
        name: 'v32 archived physical',
        status: 'archived',
        value: '900',
        included: false,
      );
      await receivable(
        id: 200,
        name: 'v32 active receivable',
        status: 'active',
        original: '1000',
        remaining: '1000',
        included: true,
      );
      await receivable(
        id: 201,
        name: 'legacy archived active',
        status: 'archived',
        original: '2000',
        remaining: '2000',
        included: false,
      );
      await receivable(
        id: 202,
        name: 'legacy archived partial',
        status: 'archived',
        original: '2000',
        remaining: '1500',
        included: false,
      );
      await receivable(
        id: 203,
        name: 'legacy archived recovered',
        status: 'archived',
        original: '2000',
        remaining: '0',
        included: false,
      );
      await receivable(
        id: 204,
        name: 'legacy archived lost',
        status: 'archived',
        original: '2000',
        remaining: '0',
        included: false,
      );
      await receivable(
        id: 205,
        name: 'legacy archived unknown',
        status: 'archived',
        original: '2000',
        remaining: '0',
        included: false,
      );
      await receivable(
        id: 206,
        name: 'legacy archived conflict',
        status: 'archived',
        original: '2000',
        remaining: '1200',
        included: false,
      );

      final archivedAt = DateTime(2026, 7, 1, 12);
      final partialAt = DateTime(2026, 5, 10, 12);
      final recoveredAt = DateTime(2026, 5, 11, 12);
      final lostAt = DateTime(2026, 5, 12, 12);
      final conflictAt = DateTime(2026, 5, 13, 12);
      await event(
        id: 1001,
        assetId: 101,
        assetType: 'physical',
        eventType: 'asset_archived',
        occurredAt: archivedAt,
      );
      for (final id in [201, 202, 203, 204, 205, 206]) {
        await event(
          id: 2000 + id,
          assetId: id,
          assetType: 'receivable',
          eventType: 'receivable_archived',
          occurredAt: archivedAt,
        );
      }
      final partialEventId = await event(
        id: 3002,
        assetId: 202,
        assetType: 'receivable',
        eventType: 'receivable_recovered',
        occurredAt: partialAt,
        value: '500',
      );
      final recoveredEventId = await event(
        id: 3003,
        assetId: 203,
        assetType: 'receivable',
        eventType: 'receivable_recovered',
        occurredAt: recoveredAt,
        value: '2000',
      );
      await event(
        id: 3004,
        assetId: 204,
        assetType: 'receivable',
        eventType: 'receivable_lost',
        occurredAt: lostAt,
        value: '0',
      );
      final conflictEventId = await event(
        id: 3006,
        assetId: 206,
        assetType: 'receivable',
        eventType: 'receivable_recovered',
        occurredAt: conflictAt,
        value: '500',
      );

      Future<void> recovery({
        required int id,
        required int assetId,
        required String amount,
        required DateTime recoveredAt,
        required int eventId,
      }) async {
        await txn.insert('receivable_recoveries', {
          'id': id,
          'uuid': 'r${id.toString().padLeft(31, '0')}',
          'receivable_asset_id': assetId,
          'amount': amount,
          'recovered_ms': recoveredAt.millisecondsSinceEpoch,
          'event_id': eventId,
          'created_ms': recoveredAt.millisecondsSinceEpoch,
        });
      }

      await recovery(
        id: 4002,
        assetId: 202,
        amount: '500',
        recoveredAt: partialAt,
        eventId: partialEventId,
      );
      await recovery(
        id: 4003,
        assetId: 203,
        amount: '2000',
        recoveredAt: recoveredAt,
        eventId: recoveredEventId,
      );
      await recovery(
        id: 4006,
        assetId: 206,
        amount: '500',
        recoveredAt: conflictAt,
        eventId: conflictEventId,
      );
      await txn.insert('asset_valuations', {
        'id': 5001,
        'uuid': 'v${5001.toString().padLeft(31, '0')}',
        'asset_id': 101,
        'value': '900',
        'source': 'opening',
        'valued_at_ms': DateTime(2025, 1, 1).millisecondsSinceEpoch,
        'created_ms': 10,
      });
    });
    await db.execute('PRAGMA user_version = 32');
    await db.close();
  }

  /// Builds a complete current database, then restores only transactions to
  /// the exact v33 shape so the v34 settlement migration runs against every
  /// legacy event family without fabricating unrelated old schemas.
  Future<void> installV33TransactionSettlementFixture() async {
    final seeded = await freshRepo();
    final bookId = seeded.defaultBookId;
    await seeded.closeForTest();

    final db = await databaseFactory.openDatabase(
      p.join(tmp.path, 'qingji.db'),
    );
    await db.transaction((txn) async {
      await txn.delete('asset_transaction_links');
      await txn.delete('receivable_recoveries');
      await txn.execute('DROP TABLE transactions');
      await txn.execute('''
        CREATE TABLE transactions (
          id                INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id           INTEGER,
          kind              TEXT NOT NULL,
          amount            TEXT NOT NULL,
          currency_code     TEXT NOT NULL DEFAULT 'CNY',
          category_id       INTEGER REFERENCES categories(id),
          account_id        INTEGER REFERENCES accounts(id),
          to_account_id     INTEGER REFERENCES accounts(id),
          note              TEXT NOT NULL DEFAULT '',
          date_ms           INTEGER NOT NULL,
          tags              TEXT NOT NULL DEFAULT '',
          reimbursable      INTEGER NOT NULL DEFAULT 0,
          image_path        TEXT NOT NULL DEFAULT '',
          recurring_rule_id INTEGER,
          excluded          INTEGER NOT NULL DEFAULT 0,
          uuid              TEXT NOT NULL DEFAULT '',
          updated_ms        INTEGER NOT NULL DEFAULT 0,
          refund_of         INTEGER
        )
      ''');

      final secondAccountId = await txn.insert('accounts', {
        'name': '工资卡',
        'currency_code': 'CNY',
        'type': 'debit',
        'opening_balance': '0',
      });
      final firstAccountId = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT MIN(id) FROM accounts'),
      )!;

      Future<void> legacyTransaction({
        required int id,
        required String kind,
        required String amount,
        required DateTime date,
        required int? accountId,
        int? toAccountId,
        String note = '',
        int? refundOf,
        bool excluded = false,
      }) async {
        await txn.insert('transactions', {
          'id': id,
          'book_id': bookId,
          'kind': kind,
          'amount': amount,
          'currency_code': 'CNY',
          'account_id': accountId,
          'to_account_id': toAccountId,
          'note': note,
          'date_ms': date.millisecondsSinceEpoch,
          'excluded': excluded ? 1 : 0,
          'uuid': 't${id.toString().padLeft(31, '0')}',
          'updated_ms': 900000 + id,
          'refund_of': refundOf,
        });
      }

      await legacyTransaction(
        id: 1,
        kind: 'expense',
        amount: '100.25',
        date: DateTime(2026, 6, 10),
        accountId: firstAccountId,
        note: '普通支出',
      );
      await legacyTransaction(
        id: 2,
        kind: 'income',
        amount: '200.50',
        date: DateTime(2026, 6, 11),
        accountId: secondAccountId,
        note: '普通收入',
      );
      await legacyTransaction(
        id: 3,
        kind: 'transfer',
        amount: '50',
        date: DateTime(2026, 6, 12),
        accountId: firstAccountId,
        toAccountId: secondAccountId,
        note: '转账',
        excluded: true,
      );
      await legacyTransaction(
        id: 4,
        kind: 'expense',
        amount: '-10',
        date: DateTime(2026, 6, 10),
        accountId: firstAccountId,
        note: '退款',
        refundOf: 1,
      );
      await legacyTransaction(
        id: 5,
        kind: 'expense',
        amount: '-20',
        date: DateTime(2026, 6, 10),
        accountId: firstAccountId,
        note: '报销到账',
        refundOf: 1,
      );
      await legacyTransaction(
        id: 6,
        kind: 'expense',
        amount: '3000',
        date: DateTime(2026, 6, 13),
        accountId: firstAccountId,
        note: '购买相机',
        excluded: true,
      );
      await legacyTransaction(
        id: 7,
        kind: 'income',
        amount: '1800',
        date: DateTime(2026, 6, 14),
        accountId: secondAccountId,
        note: '出售相机',
        excluded: true,
      );
      await legacyTransaction(
        id: 8,
        kind: 'income',
        amount: '500',
        date: DateTime(2026, 6, 15),
        accountId: secondAccountId,
        note: '押金收回',
        excluded: true,
      );
      await legacyTransaction(
        id: 9,
        kind: 'expense',
        amount: '-5.75',
        date: DateTime(2026, 6, 16),
        accountId: firstAccountId,
        note: '历史调整',
      );

      await txn.insert('asset_transaction_links', {
        'uuid': 'l${1.toString().padLeft(31, '0')}',
        'asset_id': 1001,
        'transaction_id': 6,
        'link_type': 'purchase_transaction',
        'amount': '3000',
      });
      await txn.insert('asset_transaction_links', {
        'uuid': 'l${2.toString().padLeft(31, '0')}',
        'asset_id': 1001,
        'transaction_id': 7,
        'link_type': 'sale_account_movement',
        'amount': '1800',
      });
      await txn.insert('receivable_recoveries', {
        'uuid': 'r${1.toString().padLeft(31, '0')}',
        'receivable_asset_id': 2001,
        'amount': '500',
        'recovered_ms': DateTime(2026, 6, 15).millisecondsSinceEpoch,
        'target_account_id': secondAccountId,
        'transaction_id': 8,
      });
    });
    await db.execute('PRAGMA user_version = 33');
    await db.close();
  }

  test('budget window keeps no-plan distinct from a zero budget', () async {
    final repo = await freshRepo();

    final result = repo.budgetForCalendarMonth(
      DateTime(2026, 7),
      asOf: DateTime(2026, 7, 10, 23, 59),
    );

    expect(result.plannedAmount, isNull);
    expect(repo.budgetTotalFor(2026, 7), isNull);
    await repo.closeForTest();
  });

  test('budget window resolves the plan that covered a historical month',
      () async {
    final repo = await freshRepo();
    final bookId = repo.currentBookId;
    await repo.addBudgetPeriod(
      bookId: bookId,
      start: DateTime(2026, 1, 1),
      end: DateTime(2026, 5, 31),
      total: Decimal.fromInt(3000),
    );
    await repo.addBudgetPeriod(
      bookId: bookId,
      start: DateTime(2026, 6, 1),
      total: Decimal.fromInt(4000),
    );

    final march = repo.budgetForCalendarMonth(
      DateTime(2026, 3),
      asOf: DateTime(2026, 7, 10),
    );
    final july = repo.budgetForCalendarMonth(
      DateTime(2026, 7),
      asOf: DateTime(2026, 7, 10),
    );

    expect(march.plannedAmount, Decimal.fromInt(3000));
    expect(july.plannedAmount, Decimal.fromInt(4000));
    await repo.closeForTest();
  });

  test('budgetWindow uses the explicitly requested book view', () async {
    final repo = await freshRepo();
    final defaultBookId = repo.currentBookId;
    final travelBookId = await repo.addBook(
      name: '预算测试旅行',
      includeInTotal: false,
    );
    await repo.addBudgetPeriod(
      bookId: travelBookId,
      start: DateTime(2026, 1, 1),
      total: Decimal.fromInt(1000),
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 5),
      bookId: travelBookId,
    );
    final asOf = DateTime(2026, 7, 10, 23, 59);
    final knowledgeCutoff = DateTime.now();

    final travel = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.calendarMonth,
      bookId: travelBookId,
      referenceDate: DateTime(2026, 7),
      asOf: asOf,
      knowledgeCutoff: knowledgeCutoff,
    ));
    final defaultView = repo.budgetForCalendarMonth(
      DateTime(2026, 7),
      bookId: defaultBookId,
      asOf: asOf,
    );

    expect(travel.plannedAmount, Decimal.fromInt(1000));
    expect(travel.spentAmount, Decimal.fromInt(100));
    expect(defaultView.plannedAmount, isNull);
    expect(defaultView.spentAmount, Decimal.zero);
    await repo.closeForTest();
  });

  test('currentBudgetCycle exposes resolver today allowance', () async {
    final repo = await freshRepo();
    final bookId = repo.currentBookId;
    await repo.addBudgetPeriod(
      bookId: bookId,
      start: DateTime(2026, 1, 1),
      total: Decimal.fromInt(3000),
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(900),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 6, 5),
      bookId: bookId,
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(50),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 6, 10),
      bookId: bookId,
    );

    final result = repo.currentBudgetCycle(
      bookId: bookId,
      now: DateTime(2026, 6, 10, 23, 59),
    );

    expect(result.currentCycleDailyStatus?.spentTodayCents, 5000);
    expect(result.currentCycleDailyStatus?.todayRemainingAllowanceCents, 5000);
    await repo.closeForTest();
  });

  test('money display settings persist across repository restarts', () async {
    final repo = await freshRepo();
    await repo.setMoneyDecimalPlaces(0);
    await repo.setMoneyIntegerRoundingMode(MoneyIntegerRoundingMode.ceil);
    expect(repo.moneyDecimalPlaces, 0);
    expect(repo.moneyIntegerRoundingMode, MoneyIntegerRoundingMode.ceil);
    expect(
      MoneyFormat.string(Decimal.parse('12.01')).replaceAll(',', ''),
      endsWith('13'),
    );
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.moneyDecimalPlaces, 0);
    expect(
      reopened.moneyIntegerRoundingMode,
      MoneyIntegerRoundingMode.ceil,
    );
    expect(
      MoneyFormat.string(Decimal.parse('12.01')).replaceAll(',', ''),
      endsWith('13'),
    );
    await reopened.closeForTest();
    MoneyFormat.resetConfig();
  });

  test('category icon style persists across repository restarts', () async {
    final repo = await freshRepo();
    expect(repo.categoryIconStyle, CategoryIconStyle.filled);

    await repo.setCategoryIconStyle(CategoryIconStyle.line);
    expect(repo.categoryIconStyle, CategoryIconStyle.line);
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.categoryIconStyle, CategoryIconStyle.line);
    await reopened.closeForTest();
  });

  test('transaction and chat display preferences persist with safe defaults',
      () async {
    final repo = await freshRepo();
    expect(
      repo.transactionCardDisplayMode,
      TransactionCardDisplayMode.contentFirst,
    );
    expect(
      repo.userMessageBubbleStyle,
      UserMessageBubbleStyle.followCardOpacity,
    );

    await repo.setTransactionCardDisplayMode(
      TransactionCardDisplayMode.categoryFirst,
    );
    await repo.setUserMessageBubbleStyle(UserMessageBubbleStyle.fixedGray);
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(
      reopened.transactionCardDisplayMode,
      TransactionCardDisplayMode.categoryFirst,
    );
    expect(reopened.userMessageBubbleStyle, UserMessageBubbleStyle.fixedGray);
    await reopened.closeForTest();

    final db =
        await databaseFactory.openDatabase(p.join(tmp.path, 'qingji.db'));
    await db.insert(
      'app_settings',
      {'key': 'transaction_card_display_mode', 'value': 'legacy_unknown'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'app_settings',
      {'key': 'user_message_bubble_style', 'value': 'legacy_unknown'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.close();

    final legacy = AppRepository();
    await legacy.init();
    expect(
      legacy.transactionCardDisplayMode,
      TransactionCardDisplayMode.contentFirst,
    );
    expect(
      legacy.userMessageBubbleStyle,
      UserMessageBubbleStyle.followCardOpacity,
    );
    await legacy.closeForTest();
  });

  test('profile nickname and avatar path persist across repository restarts',
      () async {
    final repo = await freshRepo();
    final docs = Directory(p.join(tmp.path, 'docs'))..createSync();
    final avatarBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    await repo.setProfileNickname('肥喵主人');
    final avatarPath = await repo.saveProfileAvatarBytes(
      avatarBytes,
      documentsDir: docs,
    );

    expect(repo.profileNickname, '肥喵主人');
    expect(repo.profileAvatarPath, avatarPath);
    expect(p.basename(avatarPath), 'avatar.png');
    expect(File(avatarPath).readAsBytesSync(), avatarBytes);
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.profileNickname, '肥喵主人');
    expect(reopened.profileAvatarPath, avatarPath);
    expect(File(reopened.profileAvatarPath).existsSync(), isTrue);
    await reopened.closeForTest();
  });

  test('本机备份列表只读取不清理旧备份', () async {
    final repo = await freshRepo();
    final now = DateTime(2026, 7, 7, 12);
    for (var i = 0; i < 5; i++) {
      final f = File(p.join(
        tmp.path,
        'qingji.db.manual-20260707-12000$i.bak',
      ));
      await f.writeAsString('backup-$i');
      await f.setLastModified(now.add(Duration(minutes: i)));
    }

    final files = await repo.localBackupFiles();

    expect(files, hasLength(5));
    expect(files.map((f) => p.basename(f.path)), [
      'qingji.db.manual-20260707-120004.bak',
      'qingji.db.manual-20260707-120003.bak',
      'qingji.db.manual-20260707-120002.bak',
      'qingji.db.manual-20260707-120001.bak',
      'qingji.db.manual-20260707-120000.bak',
    ]);
    expect(
      File(p.join(tmp.path, 'qingji.db.manual-20260707-120000.bak'))
          .existsSync(),
      isTrue,
    );
    expect(
      File(p.join(tmp.path, 'qingji.db.manual-20260707-120001.bak'))
          .existsSync(),
      isTrue,
    );
    await repo.closeForTest();
  });

  test('新建备份后保留迁移前备份且手动备份只留最新 3 份', () async {
    final repo = await freshRepo();
    final now = DateTime(2026, 7, 7, 12);
    final preMigration = File(p.join(tmp.path, 'qingji.db.pre-v20.bak'));
    await preMigration.writeAsString('pre-v20');
    await preMigration.setLastModified(now.subtract(const Duration(days: 3)));

    for (var i = 0; i < 4; i++) {
      final f = File(p.join(
        tmp.path,
        'qingji.db.manual-20260707-12000$i.bak',
      ));
      await f.writeAsString('manual-$i');
      await f.setLastModified(now.add(Duration(minutes: i)));
    }

    final created = await repo.createLocalBackupNow();

    expect(created, isNotNull);
    expect(preMigration.existsSync(), isTrue);
    final manualBackups = Directory(tmp.path)
        .listSync()
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith('qingji.db.manual-') &&
            p.basename(f.path).endsWith('.bak'))
        .toList();
    expect(manualBackups, hasLength(3));
    expect(
      File(p.join(tmp.path, 'qingji.db.manual-20260707-120000.bak'))
          .existsSync(),
      isFalse,
    );
    expect(
      File(p.join(tmp.path, 'qingji.db.manual-20260707-120001.bak'))
          .existsSync(),
      isFalse,
    );
    await repo.closeForTest();
  });

  test('新建备份后自动和手动备份各自独立保留 3 份', () async {
    final repo = await freshRepo();
    final now = DateTime(2026, 7, 7, 12);

    for (var i = 0; i < 4; i++) {
      final manual = File(p.join(
        tmp.path,
        'qingji.db.manual-20260707-12000$i.bak',
      ));
      await manual.writeAsString('manual-$i');
      await manual.setLastModified(now.add(Duration(minutes: i)));

      final auto = File(p.join(
        tmp.path,
        'qingji.db.auto-2026070$i.bak',
      ));
      await auto.writeAsString('auto-$i');
      await auto.setLastModified(now.add(Duration(hours: i)));
    }

    final created = await repo.createLocalBackupNow();

    expect(created, isNotNull);
    final backupFiles = Directory(tmp.path).listSync().whereType<File>();
    final manualCount = backupFiles
        .where((f) => p.basename(f.path).startsWith('qingji.db.manual-'))
        .length;
    final autoCount = backupFiles
        .where((f) => p.basename(f.path).startsWith('qingji.db.auto-'))
        .length;
    expect(manualCount, 3);
    expect(autoCount, 3);
    expect(
      File(p.join(tmp.path, 'qingji.db.manual-20260707-120000.bak'))
          .existsSync(),
      isFalse,
    );
    expect(
      File(p.join(tmp.path, 'qingji.db.auto-20260700.bak')).existsSync(),
      isFalse,
    );
    await repo.closeForTest();
  });

  test('本机备份是一致性快照并包含刚提交的账单', () async {
    final repo = await freshRepo();
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('18.8'),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 10),
      note: '刚写入的账单',
    );

    final backup = await repo.createLocalBackupNow();
    expect(backup, isNotNull);
    final snapshot = await openReadOnlyDatabase(backup!.path);
    expect(
      Sqflite.firstIntValue(await snapshot.rawQuery(
        "SELECT COUNT(*) FROM transactions WHERE note = '刚写入的账单'",
      )),
      1,
    );
    expect(
      (await snapshot.rawQuery('PRAGMA quick_check')).first.values.first,
      'ok',
    );
    await snapshot.close();
    await repo.closeForTest();
  });

  test('旧 SQLite checkpoint 复制兜底生成可读且包含最新提交的快照', () async {
    final repo = await freshRepo();
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('26.8'),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 11),
      note: '旧 SQLite 备份兜底',
    );

    final backup = await repo.createCheckpointDatabaseCopyForTest(
      p.join(tmp.path, 'legacy-checkpoint-copy.bak'),
    );
    final snapshot = await openReadOnlyDatabase(backup.path);
    expect(
      Sqflite.firstIntValue(await snapshot.rawQuery(
        "SELECT COUNT(*) FROM transactions WHERE note = '旧 SQLite 备份兜底'",
      )),
      1,
    );
    expect(
      (await snapshot.rawQuery('PRAGMA quick_check')).first.values.first,
      'ok',
    );
    await snapshot.close();
    await repo.closeForTest();
  });

  test('无效数据库恢复失败时保留当前数据且连接仍可继续写入', () async {
    final repo = await freshRepo();
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(10),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 10),
      note: '恢复前数据',
    );
    final invalid = File(p.join(tmp.path, 'invalid.db'));
    await invalid.writeAsString('not a sqlite database');

    expect(await repo.restoreDatabaseFromFile(invalid.path), isFalse);
    expect(repo.transactions.where((t) => t.note == '恢复前数据'), hasLength(1));
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 10),
      note: '恢复失败后仍可写',
    );
    expect(repo.transactions, hasLength(2));
    await repo.closeForTest();
  });

  test('当前库损坏成垃圾字节后仍能用完好备份恢复', () async {
    final repo = await freshRepo();
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(10),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 10),
      note: '备份内数据',
    );
    final backup = await repo.createLocalBackupNow();
    expect(backup, isNotNull);
    await repo.closeForTest();

    // 模拟当前库损坏：整个文件写成垃圾字节。
    final dbPath = p.join(tmp.path, 'qingji.db');
    await File(dbPath).writeAsString('this is not a sqlite database at all');

    final broken = AppRepository();
    // 损坏库上 init 失败是预期行为；这里只关心之后的恢复
    // 不能被「恢复前安全副本做不出来」卡死。
    try {
      await broken.init();
    } catch (_) {}

    expect(await broken.restoreDatabaseFromFile(backup!.path), isTrue);
    expect(
      broken.transactions.where((t) => t.note == '备份内数据'),
      hasLength(1),
    );
    await broken.closeForTest();
  });

  test('有效数据库恢复会回到快照且不会保留快照后的流水', () async {
    final repo = await freshRepo();
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(10),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 10),
      note: '快照内',
    );
    final backup = await repo.createLocalBackupNow();
    expect(backup, isNotNull);
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 10),
      note: '快照后',
    );

    expect(await repo.restoreDatabaseFromFile(backup!.path), isTrue);
    expect(repo.transactions.where((t) => t.note == '快照内'), hasLength(1));
    expect(repo.transactions.where((t) => t.note == '快照后'), isEmpty);
    await repo.closeForTest();
  });

  test('恢复后旧 AI 报告租约不能写入复用同一整数 ID 的新任务', () async {
    final repo = await freshRepo();
    final backup = await repo.createLocalBackupNow();
    expect(backup, isNotNull);

    final oldJob = await repo.createReportJob(
      question: '旧数据库里的报告',
      type: 'monthly',
      title: '旧报告',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
    );
    final oldLease = (await repo.acquireReportGenerationLease()).bind(
      jobId: oldJob.id,
      jobUuid: oldJob.uuid,
    );

    expect(await repo.restoreDatabaseFromFile(backup!.path), isTrue);
    final restoredJob = await repo.createReportJob(
      question: '恢复快照后的报告',
      type: 'monthly',
      title: '新报告',
      periodStart: DateTime(2026, 7, 1),
      periodEnd: DateTime(2026, 7, 31),
    );
    expect(restoredJob.id, oldJob.id, reason: '测试必须覆盖 SQLite 整数 ID 复用');
    expect(restoredJob.uuid, isNot(oldJob.uuid));

    await expectLater(
      repo.guardReportGeneration(
        oldLease,
        () => repo.updateReportJob(
          oldJob.id,
          expectedUuid: oldJob.uuid,
          status: 'completed',
        ),
      ),
      throwsA(isA<ReportGenerationInvalidated>()),
    );
    expect((await repo.reportJobById(restoredJob.id))!.status, 'queued');
    await repo.closeForTest();
  });

  test('恢复后立即收敛到期周期账、自动折旧和最终净资产快照', () async {
    final repo = await freshRepo();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final depreciationStart = DateTime(now.year - 1, now.month, now.day);
    final assetId = await repo.addPhysicalAsset(
      name: '恢复后折旧电脑',
      currentValue: Decimal.fromInt(2400),
      purchasePrice: Decimal.fromInt(2400),
      purchaseDate: depreciationStart,
    );
    await repo.configurePhysicalAssetDepreciation(
      id: assetId,
      enabled: true,
      depreciationBase: Decimal.fromInt(2400),
      salvageValue: Decimal.zero,
      usefulLifeMonths: 24,
      startAt: depreciationStart,
    );
    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: repo.accounts.first.id,
      period: RecurPeriod.monthly,
      startDate: DateTime(2099, 1, 1),
      totalCount: 1,
      note: '恢复后到期扣款',
    );
    final ruleId = repo.recurringRules.single.id;
    final backup = await repo.createLocalBackupNow();
    expect(backup, isNotNull);

    final backupDb = await databaseFactory.openDatabase(
      backup!.path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await backupDb.update(
      'recurring_rules',
      {
        'start_date_ms': today.millisecondsSinceEpoch,
        'next_due_ms': today.millisecondsSinceEpoch,
        'anchor_day': today.day,
        'generated_count': 0,
      },
      where: 'id = ?',
      whereArgs: [ruleId],
    );
    await backupDb.close();
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(999),
      accountId: repo.accounts.first.id,
      date: today,
      note: '恢复时应消失的现场流水',
    );

    expect(await repo.restoreDatabaseFromFile(backup.path), isTrue);
    expect(
      repo.transactions.where((item) => item.note == '恢复时应消失的现场流水'),
      isEmpty,
    );
    final recurring = repo.transactions.singleWhere(
      (item) => item.recurringRuleId == ruleId,
    );
    expect(recurring.note, '恢复后到期扣款');
    expect(repo.recurringRules.single.generatedCount, 1);
    final recurringAccount = repo.accounts.singleWhere(
      (account) => account.id == recurring.accountId,
    );
    expect(repo.accountBalanceOf(recurringAccount), Decimal.fromInt(-100));
    final asset = repo.physicalAssetDetailById(assetId)!;
    expect(asset.currentValue, Decimal.fromInt(1200));
    expect(
      repo.valuationsForAsset(assetId).first.source,
      AssetValueSource.autoDepreciation,
    );
    final finalNetWorth = repo.currentNetWorthResult().value!.netWorth;
    expect(finalNetWorth, Decimal.fromInt(1100));
    final todayKey = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final snapshot = repo.netWorthSnapshots.firstWhere(
      (item) => item.isComputed && item.snapshotDate == todayKey,
    );
    expect(snapshot.netWorth, finalNetWorth);
    expect(snapshot.physicalAssets, Decimal.fromInt(1200));
    expect(snapshot.cashAssets, Decimal.zero);
    expect(snapshot.totalLiabilities, Decimal.fromInt(100));
    await repo.closeForTest();
  });

  test('完整备份 package v2 会原子恢复数据库、收据和资产媒体', () async {
    final repo = await freshRepo();
    final documents =
        await Directory(p.join(tmp.path, 'documents')).create(recursive: true);
    final temporary = await Directory(p.join(tmp.path, 'package_tmp'))
        .create(recursive: true);
    final receipt = File(p.join(documents.path, 'receipts', 'receipt.jpg'));
    final original =
        File(p.join(documents.path, 'asset_media', 'originals', 'asset.jpg'));
    final thumbnail =
        File(p.join(documents.path, 'asset_media', 'thumbnails', 'asset.png'));
    await receipt.parent.create(recursive: true);
    await original.parent.create(recursive: true);
    await thumbnail.parent.create(recursive: true);
    await receipt.writeAsBytes([1, 2, 3]);
    await original.writeAsBytes([4, 5, 6]);
    await thumbnail.writeAsBytes([7, 8, 9]);

    final purchaseId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 13),
      note: '备份内购买',
      imagePath: receipt.path,
    );
    await repo.addPhysicalAssetFromTransaction(
      transactionId: purchaseId,
      name: '备份内相机',
      allocatedGrossCents: 10000,
      photoPath: original.path,
      thumbnailPath: thumbnail.path,
    );
    final package = await repo.exportBackupPackage(
      temporaryDirectory: temporary,
      documentsDirectory: documents,
    );
    final leakedExportDirectories = await temporary
        .list()
        .where((entry) =>
            entry is Directory &&
            p.basename(entry.path).startsWith('feimiao_backup_'))
        .toList();
    expect(leakedExportDirectories, isEmpty);

    await receipt.writeAsBytes([99]);
    await original.delete();
    await thumbnail.writeAsBytes([88]);
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(5),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 13),
      note: '备份后流水',
    );

    expect(
      await repo.restoreBackupPackage(
        package.path,
        temporaryDirectory: temporary,
        documentsDirectory: documents,
      ),
      isTrue,
    );
    expect(repo.transactions.where((item) => item.note == '备份后流水'), isEmpty);
    expect(await receipt.readAsBytes(), [1, 2, 3]);
    expect(await original.readAsBytes(), [4, 5, 6]);
    expect(await thumbnail.readAsBytes(), [7, 8, 9]);
    final restoredAsset = repo.globalActivePhysicalAssets.single;
    expect(restoredAsset.photoPath, original.path);
    expect(restoredAsset.thumbnailPath, thumbnail.path);
    await repo.closeForTest();
  });

  test(
      'backup package rollback preserves live data at every activation boundary',
      () async {
    final repo = await freshRepo();
    final documents = await Directory(p.join(tmp.path, 'rollback_documents'))
        .create(recursive: true);
    final temporary = await Directory(p.join(tmp.path, 'rollback_tmp'))
        .create(recursive: true);
    final receipt = File(p.join(documents.path, 'receipts', 'receipt.jpg'));
    final original =
        File(p.join(documents.path, 'asset_media', 'originals', 'asset.jpg'));
    await receipt.parent.create(recursive: true);
    await original.parent.create(recursive: true);
    await receipt.writeAsBytes([1, 2, 3]);
    await original.writeAsBytes([4, 5, 6]);
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(10),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 13),
      note: 'backup state',
    );
    final package = await repo.exportBackupPackage(
      temporaryDirectory: temporary,
      documentsDirectory: documents,
    );

    await receipt.writeAsBytes([91, 92]);
    await original.writeAsBytes([93, 94]);
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 13),
      note: 'live state',
    );

    for (final failurePoint in const [
      'before_database_install',
      'before_receipts_install',
      'before_asset_media_install',
      'before_database_open',
    ]) {
      final restored = await repo.restoreBackupPackage(
        package.path,
        temporaryDirectory: temporary,
        documentsDirectory: documents,
        onRestoreStep: (step) {
          if (step == failurePoint) throw StateError(failurePoint);
        },
      );
      expect(restored, isFalse, reason: failurePoint);
      expect(await receipt.readAsBytes(), [91, 92], reason: failurePoint);
      expect(await original.readAsBytes(), [93, 94], reason: failurePoint);
      expect(
        repo.transactions.where((item) => item.note == 'live state'),
        hasLength(1),
        reason: failurePoint,
      );
      final leakedWorkDirectories = await temporary
          .list()
          .where((entry) =>
              entry is Directory &&
              p.basename(entry.path).startsWith('feimiao_restore_'))
          .toList();
      expect(leakedWorkDirectories, isEmpty, reason: failurePoint);
      final leakedStagingEntries = await tmp
          .list(recursive: true, followLinks: false)
          .where((entry) => p.basename(entry.path).contains('.restore-new-'))
          .toList();
      expect(leakedStagingEntries, isEmpty, reason: failurePoint);
    }
    await repo.closeForTest();
  });

  test('备份包合法但包内数据库是垃圾字节时干净失败，不裸穿异常', () async {
    final repo = await freshRepo();
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(10),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 13),
      note: '恢复前数据',
    );
    final documents = await Directory(p.join(tmp.path, 'bad_pkg_docs'))
        .create(recursive: true);
    final temporary = await Directory(p.join(tmp.path, 'bad_pkg_tmp'))
        .create(recursive: true);
    // 合法 zip + 校验和都对，但 database 项是垃圾字节；带上收据触发
    // 「打开包内库改写附件路径」那条路径。
    final packageBytes = BackupPackageCodec.encode(
      files: {
        'database/qingji.db':
            Uint8List.fromList(utf8.encode('not a sqlite database')),
        'receipts/fake.jpg': Uint8List.fromList([1, 2, 3]),
      },
      databaseVersion: 1,
      createdAt: DateTime(2026, 7, 20),
    );
    final packageFile = File(p.join(tmp.path, 'bad_package.zip'));
    await packageFile.writeAsBytes(packageBytes, flush: true);

    expect(
      await repo.restoreBackupPackage(
        packageFile.path,
        temporaryDirectory: temporary,
        documentsDirectory: documents,
      ),
      isFalse,
    );
    // 当前数据原样保留，连接仍可继续写入。
    expect(repo.transactions.where((t) => t.note == '恢复前数据'), hasLength(1));
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(5),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 13),
      note: '失败后仍可写',
    );
    expect(repo.transactions.where((t) => t.note == '失败后仍可写'), hasLength(1));
    await repo.closeForTest();
  });

  test('首次建库：播种账户/分类树/总账本，新账单带 uuid+updated_ms', () async {
    final repo = await freshRepo();
    expect(repo.books, isNotEmpty);
    expect(repo.accounts, isNotEmpty);
    final cats = repo
        .categoriesForKind(TransactionKind.expense)
        .where((c) => c.parentId == null)
        .toList();
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
    final db =
        await databaseFactory.openDatabase(p.join(tmp.path, 'qingji.db'));
    final rows = await db.query('transactions');
    expect(rows, hasLength(1));
    expect((rows.first['uuid'] as String).length, 32);
    expect(rows.first['updated_ms'] as int, greaterThan(0));
    await db.close();
  });

  test('账户资产字段：资料可更新，但期初余额建立后不可静默重写', () async {
    final repo = await freshRepo();
    final id = await repo.addAccount(
      name: '招商银行',
      currencyCode: 'CNY',
      type: AccountType.debit,
      openingBalance: Decimal.parse('1200.50'),
      includeInNetWorth: false,
      institution: '招商',
    );

    var account = repo.accounts.firstWhere((a) => a.id == id);
    expect(account.type, AccountType.debit);
    expect(account.openingBalance, Decimal.parse('1200.50'));
    expect(account.includeInNetWorth, isFalse);
    expect(account.institution, '招商');

    await repo.updateAccount(
      id: id,
      name: '招商储蓄卡',
      currencyCode: 'CNY',
      type: AccountType.savings,
      openingBalance: Decimal.parse('3000'),
      includeInNetWorth: true,
      institution: '招商银行',
    );
    account = repo.accounts.firstWhere((a) => a.id == id);
    expect(account.name, '招商储蓄卡');
    expect(account.type, AccountType.savings);
    expect(account.openingBalance, Decimal.parse('1200.50'));
    expect(account.includeInNetWorth, isTrue);
    expect(account.institution, '招商银行');
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    final persisted = reopened.accounts.firstWhere((a) => a.id == id);
    expect(persisted.type, AccountType.savings);
    expect(persisted.openingBalance, Decimal.parse('1200.50'));
    expect(persisted.includeInNetWorth, isTrue);
    expect(persisted.institution, '招商银行');
    await reopened.closeForTest();
  });

  test('A3 绝对余额校准吸收锚点前补录，锚点后流水继续累计且可撤销', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(
      name: '校准账户',
      openingBalance: Decimal.fromInt(100),
    );
    final account = repo.accounts.firstWhere((item) => item.id == accountId);
    final checkpointId = await repo.createAccountBalanceCheckpoint(
      accountId: accountId,
      targetBalance: Decimal.fromInt(500),
      note: '实际余额',
    );

    await repo.addTransaction(
      kind: TransactionKind.income,
      amount: Decimal.fromInt(80),
      accountId: accountId,
      date: DateTime(2025, 1, 1),
      note: '后补旧流水',
    );
    expect(repo.accountBalanceOf(account), Decimal.fromInt(500));

    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      accountId: accountId,
      date: DateTime.now(),
      note: '校准后支出',
    );
    expect(repo.accountBalanceOf(account), Decimal.fromInt(480));

    await repo.reverseAccountBalanceCheckpoint(checkpointId);
    expect(repo.accountBalanceOf(account), Decimal.fromInt(160));
    await repo.closeForTest();
  });

  test('A3 账户归档只改变可见性，非零余额仍计入净资产', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(
      name: '待归档账户',
      openingBalance: Decimal.fromInt(888),
    );
    final before = repo.currentNetWorthBreakdown().netWorth;

    await repo.archiveAccount(accountId);
    expect(repo.activeAccounts.any((item) => item.id == accountId), isFalse);
    expect(repo.archivedAccounts.any((item) => item.id == accountId), isTrue);
    expect(repo.currentNetWorthBreakdown().netWorth, before);

    await repo.restoreArchivedAccount(accountId);
    expect(repo.activeAccounts.any((item) => item.id == accountId), isTrue);
    expect(repo.currentNetWorthBreakdown().netWorth, before);
    await repo.closeForTest();
  });

  test('A3 verified checkpoint 冻结证据，后续记账不会改写旧核对', () async {
    final repo = await freshRepo();
    final account = repo.accounts.first;
    final first = await repo.createVerifiedNetWorthCheckpoint();
    expect(
      first.header.completeness,
      NetWorthVerifiedCheckpointCompleteness.complete,
    );
    final frozenNetWorth = first.header.totals.netWorthMinor;
    final frozenItems = first.items
        .map((item) => (
              item.key.objectType,
              item.key.objectUuid,
              item.confirmedAmountMinor
            ))
        .toList();

    await repo.addTransaction(
      kind: TransactionKind.income,
      amount: Decimal.fromInt(50),
      accountId: account.id,
      date: DateTime.now(),
      note: '核对后的收入',
    );
    final second = await repo.createVerifiedNetWorthCheckpoint();
    final reloadedFirst = repo.verifiedNetWorthCheckpoints
        .firstWhere((item) => item.header.id == first.header.id);
    expect(reloadedFirst.header.totals.netWorthMinor, frozenNetWorth);
    expect(
      reloadedFirst.items
          .map((item) => (
                item.key.objectType,
                item.key.objectUuid,
                item.confirmedAmountMinor
              ))
          .toList(),
      frozenItems,
    );
    expect(second.header.totals.netWorthMinor, frozenNetWorth + 5000);
    expect(repo.latestVerifiedNetWorthComparison?.change?.netWorthDeltaMinor,
        5000);
    await repo.closeForTest();
  });

  test('B2 V2 计划按完整周期应用 revision，本周期 override 保存绝对值', () async {
    final repo = await freshRepo();
    final now = DateTime.now();
    final bookId = repo.currentBookId;
    final planId = await repo.addBudgetPlanV2(
      bookId: bookId,
      name: '日常预算',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 310000,
      categoryBudgetsCents: const {'dining': 100000},
      monthStartDay: 1,
      startNextCycle: false,
    );
    var current = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: now,
      asOf: now,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(current.plannedCents, 310000);

    final plan = repo.budgetPlansV2.firstWhere((item) => item.id == planId);
    final currentCycle = plan.cycleFor(now);
    await repo.addBudgetPlanRevisionV2(
      planId: planId,
      totalCents: 620000,
      effectiveCycleStart: currentCycle.endExclusive,
    );
    current = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: now,
      asOf: now,
      knowledgeCutoff: DateTime.now(),
    ));
    final next = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: currentCycle.endExclusive,
      asOf: currentCycle.endExclusive,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(current.plannedCents, 310000);
    expect(next.plannedCents, 620000);

    final futureBrowse = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: currentCycle.endExclusive,
      asOf: now,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(
        futureBrowse.currentCycleDailyStatus?.cycleStart, currentCycle.start);
    expect(futureBrowse.fixedCommitmentStatus, MetricStatus.notApplicable);
    expect(futureBrowse.discretionaryRemainingCents, isNull);

    await repo.upsertBudgetCycleOverrideV2(
      planId: planId,
      cycleStart: currentCycle.start,
      targetAmountCents: 330000,
      categoryBudgetsCents: const {'dining': 100000},
      inputIntent: BudgetOverrideIntent.adjustRemaining,
      inputDeltaCents: 20000,
    );
    final overridden = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: now,
      asOf: now,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(overridden.plannedCents, 330000);
    await repo.closeForTest();
  });

  test('B2 固定支出 actual 与 reserve 互斥，部分退款后差额继续预留', () async {
    final repo = await freshRepo();
    final now = DateTime.now();
    final bookId = repo.currentBookId;
    final accountId = repo.accounts.first.id;
    final dueDay = now.day.clamp(1, 28);
    final planId = await repo.addBudgetPlanV2(
      bookId: bookId,
      name: '含固定支出预算',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 100000,
      monthStartDay: 1,
      startNextCycle: false,
      fixedTemplates: [
        BudgetFixedTemplateV2(
          id: 'rent',
          name: '房租',
          plannedCents: 10000,
          dueValue: dueDay,
        ),
      ],
    );
    final plan = repo.budgetPlansV2.firstWhere((item) => item.id == planId);
    final cycle = plan.cycleFor(now);
    final occurrence = repo
        .budgetFixedOccurrencesV2For(planId, cycleStart: cycle.start)
        .single;
    var before = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: now,
      asOf: now,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(before.fixedReserveCents, 10000);
    expect(before.discretionaryRemainingCents, 90000);

    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: accountId,
      bookId: bookId,
      date: now,
      note: '房租',
    );
    final transaction =
        repo.transactions.firstWhere((item) => item.id == transactionId);
    await repo.matchBudgetFixedOccurrence(
      occurrence.id,
      transaction.uuid,
    );
    final matched = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: now,
      asOf: DateTime.now(),
      knowledgeCutoff: DateTime.now(),
    ));
    expect(matched.spentCents, 10000);
    expect(matched.fixedActualSpentCents, 10000);
    expect(matched.fixedReserveCents, 0);
    expect(matched.discretionaryRemainingCents, 90000);

    await repo.refundTransaction(
      transaction,
      Decimal.fromInt(30),
      settledAt: DateTime.now(),
      settlementAccountId: accountId,
    );
    final refunded = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: now,
      asOf: DateTime.now(),
      knowledgeCutoff: DateTime.now(),
    ));
    expect(refunded.spentCents, 7000);
    expect(refunded.fixedActualSpentCents, 7000);
    expect(refunded.fixedReserveCents, 3000);
    expect(refunded.discretionaryRemainingCents, 90000);
    expect(refunded.fixedCommitmentStatus, MetricStatus.partial);

    await repo.acceptBudgetFixedRefundReview(occurrence.id);
    final secondRefundId = await repo.refundTransaction(
      transaction,
      Decimal.fromInt(10),
      settledAt: DateTime.now(),
      settlementAccountId: accountId,
    );
    expect(
      repo
          .budgetFixedOccurrencesV2For(planId, cycleStart: cycle.start)
          .single
          .occurrence
          .reviewReason,
      FixedCommitmentReviewReason.refundAfterMatch,
    );
    await repo.deleteTransaction(secondRefundId);
    final afterUndo = repo
        .budgetFixedOccurrencesV2For(planId, cycleStart: cycle.start)
        .single;
    expect(afterUndo.resolutionStatus, FixedCommitmentResolutionStatus.matched);
    expect(afterUndo.occurrence.reviewReason, isNull);
    await repo.closeForTest();
  });

  test('A3 过期物品估值必须明确接受后才能形成完整核对', () async {
    final repo = await freshRepo();
    final oldDate = DateTime.now().subtract(const Duration(days: 120));
    await repo.addPhysicalAsset(
      name: '旧估值相机',
      currentValue: Decimal.fromInt(3000),
      purchaseDate: oldDate,
      occurredAt: oldDate,
    );
    expect(repo.stalePhysicalValuationCount(), 1);
    final partial = await repo.createVerifiedNetWorthCheckpoint();
    expect(
      partial.header.completeness,
      NetWorthVerifiedCheckpointCompleteness.partial,
    );
    expect(
      partial.header.incompletenessReasons
          .any((reason) => reason.code == 'stale_valuation_not_accepted'),
      isTrue,
    );
    final accepted = await repo.createVerifiedNetWorthCheckpoint(
      acceptStaleValuations: true,
    );
    expect(
      accepted.header.completeness,
      NetWorthVerifiedCheckpointCompleteness.complete,
    );
    expect(
      accepted.items
          .firstWhere((item) => item.key.objectType == 'physical_asset')
          .quality,
      'accepted_stale',
    );
    await repo.closeForTest();
  });

  test('A3 unknown-date 转账按账户双腿覆盖，校准后不重复加减', () async {
    var repo = await freshRepo();
    final sourceId = await repo.addAccount(name: '转出账户');
    final targetId = await repo.addAccount(name: '转入账户');
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.transfer,
      amount: Decimal.fromInt(10),
      accountId: sourceId,
      toAccountId: targetId,
      date: DateTime.now(),
      note: '待确认日期转账',
    );
    await repo.closeForTest();

    final db =
        await databaseFactory.openDatabase(p.join(tmp.path, 'qingji.db'));
    await db.update(
      'transactions',
      {
        'settled_ms': null,
        'settlement_quality': SettlementQuality.unknown.storageKey,
        'settlement_account_quality':
            SettlementQuality.userConfirmed.storageKey,
      },
      where: 'id = ?',
      whereArgs: [transactionId],
    );
    await db.close();

    repo = AppRepository();
    await repo.init();
    var source = repo.accounts.firstWhere((item) => item.id == sourceId);
    var target = repo.accounts.firstWhere((item) => item.id == targetId);
    expect(repo.accountBalanceOf(source), Decimal.fromInt(-10));
    expect(repo.accountBalanceOf(target), Decimal.fromInt(10));
    await repo.createAccountBalanceCheckpoint(
      accountId: sourceId,
      targetBalance: Decimal.fromInt(-10),
    );
    await repo.createAccountBalanceCheckpoint(
      accountId: targetId,
      targetBalance: Decimal.fromInt(10),
    );
    source = repo.accounts.firstWhere((item) => item.id == sourceId);
    target = repo.accounts.firstWhere((item) => item.id == targetId);
    expect(repo.accountBalanceOf(source), Decimal.fromInt(-10));
    expect(repo.accountBalanceOf(target), Decimal.fromInt(10));
    await repo.closeForTest();
  });

  test('B2 V2 从生效日切断旧预算，归档后不会在未来复活 legacy', () async {
    final repo = await freshRepo();
    final now = DateTime.now();
    final bookId = repo.currentBookId;
    await repo.addBudgetPeriod(
      bookId: bookId,
      start: DateTime(2000, 1, 1),
      recurringMonthly: true,
      total: Decimal.fromInt(1000),
    );
    final planId = await repo.addBudgetPlanV2(
      bookId: bookId,
      name: 'V2 切换',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 200000,
      monthStartDay: 1,
      startNextCycle: false,
    );
    final plan = repo.budgetPlansV2.firstWhere((item) => item.id == planId);
    final current = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: now,
      asOf: now,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(current.plannedCents, 200000);

    await repo.archiveBudgetPlanV2(planId);
    final futureDate = plan.cycleFor(now).endExclusive;
    final future = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: futureDate,
      asOf: futureDate,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(future.planStatus, MetricStatus.unavailable);
    expect(future.plannedCents, isNull);
    await repo.closeForTest();
  });

  test('B2 下周期计划不会锁死本周期预算，并在边界日无冲突接续', () async {
    final repo = await freshRepo();
    final now = DateTime.now();
    final bookId = repo.currentBookId;
    final futurePlanId = await repo.addBudgetPlanV2(
      bookId: bookId,
      name: '下周期计划',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 200000,
      monthStartDay: 1,
      startNextCycle: true,
    );
    final futurePlan =
        repo.budgetPlansV2.firstWhere((item) => item.id == futurePlanId);

    final beforeBridge = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: now,
      asOf: now,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(beforeBridge.planStatus, MetricStatus.unavailable);

    final bridgePlanId = await repo.addBudgetPlanV2(
      bookId: bookId,
      name: '本周期计划',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 100000,
      monthStartDay: 1,
      startNextCycle: false,
    );
    final bridgePlan =
        repo.budgetPlansV2.firstWhere((item) => item.id == bridgePlanId);
    expect(
      bridgePlan.endInclusive,
      futurePlan.anchorStart.subtract(const Duration(days: 1)),
    );

    final current = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: now,
      asOf: now,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(current.planStatus, MetricStatus.available);
    expect(current.plannedCents, 100000);

    final future = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: futurePlan.anchorStart,
      asOf: futurePlan.anchorStart,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(future.planStatus, MetricStatus.available);
    expect(future.plannedCents, 200000);
    expect(future.planSlices.map((slice) => slice.planId).toSet(), {
      futurePlanId,
    });
    await repo.closeForTest();
  });

  test('B2 已覆盖本周期的主计划仍禁止重复创建', () async {
    final repo = await freshRepo();
    final bookId = repo.currentBookId;
    await repo.addBudgetPlanV2(
      bookId: bookId,
      name: '当前计划',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 100000,
      monthStartDay: 1,
      startNextCycle: false,
    );

    await expectLater(
      repo.addBudgetPlanV2(
        bookId: bookId,
        name: '重复计划',
        cadence: BudgetPlanCadenceV2.monthly,
        totalCents: 200000,
        monthStartDay: 1,
        startNextCycle: false,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('这个周期已有主预算记录'),
        ),
      ),
    );
    await repo.closeForTest();
  });

  test('B2 未生效计划可安全归档，结束日不会早于开始日', () async {
    var repo = await freshRepo();
    final bookId = repo.currentBookId;
    final planId = await repo.addBudgetPlanV2(
      bookId: bookId,
      name: '尚未生效',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 100000,
      monthStartDay: 1,
      startNextCycle: true,
    );
    await repo.archiveBudgetPlanV2(planId);
    var plan = repo.budgetPlansV2.firstWhere((item) => item.id == planId);
    expect(plan.status, BudgetPlanStatusV2.archived);
    expect(plan.endInclusive, isNull);
    await repo.closeForTest();

    repo = AppRepository();
    await repo.init();
    plan = repo.budgetPlansV2.firstWhere((item) => item.id == planId);
    expect(plan.status, BudgetPlanStatusV2.archived);
    expect(plan.endInclusive, isNull);
    final future = repo.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: plan.anchorStart,
      asOf: plan.anchorStart,
      knowledgeCutoff: DateTime.now(),
    ));
    expect(future.planStatus, MetricStatus.unavailable);
    await repo.closeForTest();
  });

  test('B2 已归档周期保留历史且不会允许同周期重复主计划', () async {
    final repo = await freshRepo();
    final bookId = repo.currentBookId;
    final planId = await repo.addBudgetPlanV2(
      bookId: bookId,
      name: '本周期历史',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 100000,
      monthStartDay: 1,
      startNextCycle: false,
    );
    await repo.archiveBudgetPlanV2(planId);

    await expectLater(
      repo.addBudgetPlanV2(
        bookId: bookId,
        name: '同周期重复',
        cadence: BudgetPlanCadenceV2.monthly,
        totalCents: 200000,
        monthStartDay: 1,
        startNextCycle: false,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await repo.addBudgetPlanV2(
        bookId: bookId,
        name: '下周期接续',
        cadence: BudgetPlanCadenceV2.monthly,
        totalCents: 200000,
        monthStartDay: 1,
        startNextCycle: true,
      ),
      greaterThan(0),
    );
    await repo.closeForTest();
  });

  test('B2 下周期 revision 可重复保存并同步预生成 occurrence', () async {
    var repo = await freshRepo();
    final now = DateTime.now();
    final planId = await repo.addBudgetPlanV2(
      bookId: repo.currentBookId,
      name: '修订同步',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 100000,
      monthStartDay: 1,
      startNextCycle: false,
      fixedTemplates: const [
        BudgetFixedTemplateV2(
          id: 'rent',
          name: '房租',
          plannedCents: 10000,
          dueValue: 1,
        ),
      ],
    );
    final firstPlan =
        repo.budgetPlansV2.firstWhere((item) => item.id == planId);
    final nextStart = firstPlan.cycleFor(now).endExclusive;
    await repo.closeForTest();

    repo = AppRepository();
    await repo.init();
    expect(
      repo
          .budgetFixedOccurrencesV2For(planId, cycleStart: nextStart)
          .single
          .plannedCents,
      10000,
    );
    await repo.addBudgetPlanRevisionV2(
      planId: planId,
      totalCents: 120000,
      effectiveCycleStart: nextStart,
      fixedTemplates: const [
        BudgetFixedTemplateV2(
          id: 'rent',
          name: '房租',
          plannedCents: 12000,
          dueValue: 2,
        ),
      ],
    );
    final revisionId = await repo.addBudgetPlanRevisionV2(
      planId: planId,
      totalCents: 130000,
      effectiveCycleStart: nextStart,
      fixedTemplates: const [
        BudgetFixedTemplateV2(
          id: 'rent',
          name: '房租',
          plannedCents: 13000,
          dueValue: 3,
        ),
      ],
    );
    final revisions = repo
        .budgetPlanRevisionsV2For(planId)
        .where((item) => item.effectiveCycleStart == nextStart)
        .toList();
    expect(revisions, hasLength(1));
    expect(revisions.single.id, revisionId);
    final occurrence =
        repo.budgetFixedOccurrencesV2For(planId, cycleStart: nextStart).single;
    expect(occurrence.revisionId, revisionId);
    expect(occurrence.plannedCents, 13000);
    expect(occurrence.dueDate.day, 3);
    await repo.closeForTest();
  });

  test('B2 恢复备份后立即物化当前与下一周期 occurrence', () async {
    final repo = await freshRepo();
    final planId = await repo.addBudgetPlanV2(
      bookId: repo.currentBookId,
      name: '恢复后物化',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 100000,
      monthStartDay: 1,
      startNextCycle: false,
      fixedTemplates: const [
        BudgetFixedTemplateV2(
          id: 'rent',
          name: '房租',
          plannedCents: 10000,
          dueValue: 1,
        ),
      ],
    );
    final plan = repo.budgetPlansV2.firstWhere((item) => item.id == planId);
    final nextStart = plan.cycleFor(DateTime.now()).endExclusive;
    expect(
      repo.budgetFixedOccurrencesV2For(planId, cycleStart: nextStart),
      isEmpty,
    );
    final backup = await repo.createLocalBackupNow();
    expect(backup, isNotNull);
    expect(await repo.restoreDatabaseFromFile(backup!.path), isTrue);
    expect(
      repo.budgetFixedOccurrencesV2For(planId, cycleStart: nextStart),
      hasLength(1),
    );
    await repo.closeForTest();
  });

  test('v39 to v40 adds time precision without rewriting transaction time',
      () async {
    var repo = await freshRepo();
    final originalDate = DateTime(2024, 3, 8);
    final id = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('18.50'),
      accountId: repo.accounts.first.id,
      note: 'legacy midnight',
      date: originalDate,
      timePrecision: TransactionTimePrecision.exact,
    );
    await repo.closeForTest();

    final path = p.join(tmp.path, 'qingji.db');
    final oldDb = await databaseFactory.openDatabase(path);
    await oldDb.execute(
      'ALTER TABLE transactions DROP COLUMN time_precision',
    );
    await oldDb.execute('PRAGMA user_version = 39');
    await oldDb.close();

    repo = AppRepository();
    await repo.init();
    final migrated = repo.transactionById(id)!;
    expect(migrated.dateMs, originalDate.millisecondsSinceEpoch);
    expect(
      migrated.timePrecision,
      TransactionTimePrecision.legacyUnknown,
    );
    await repo.closeForTest();

    final check = await databaseFactory.openDatabase(path);
    final columns = await check.rawQuery('PRAGMA table_info(transactions)');
    final precision =
        columns.firstWhere((row) => row['name'] == 'time_precision');
    expect(precision['notnull'], 1);
    expect(precision['dflt_value'], "'legacy_unknown'");
    expect(
      Sqflite.firstIntValue(await check.rawQuery('PRAGMA user_version')),
      43,
    );
    await check.close();
  });

  test('v36 → v40：旧账户不伪造期初时间，legacy hidden 与旧预算保留', () async {
    var repo = await freshRepo();
    await repo.addBudgetPeriod(
      bookId: repo.currentBookId,
      start: DateTime(2000, 1, 1),
      total: Decimal.fromInt(1000),
    );
    await repo.closeForTest();
    final path = p.join(tmp.path, 'qingji.db');
    final db = await databaseFactory.openDatabase(path);
    await db.execute('''
      CREATE TABLE accounts_v36 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        currency_code TEXT NOT NULL DEFAULT 'CNY',
        type TEXT NOT NULL DEFAULT 'cash',
        opening_balance TEXT NOT NULL DEFAULT '0',
        include_in_net_worth INTEGER NOT NULL DEFAULT 1,
        institution TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at_ms INTEGER
      )
    ''');
    await db.execute('''
      INSERT INTO accounts_v36(
        id,name,currency_code,type,opening_balance,include_in_net_worth,
        institution,sort_order,is_deleted,deleted_at_ms
      )
      SELECT id,name,currency_code,type,opening_balance,include_in_net_worth,
        institution,sort_order,is_deleted,deleted_at_ms FROM accounts
    ''');
    await db.insert('accounts_v36', {
      'name': '旧删除账户',
      'opening_balance': '99',
      'is_deleted': 1,
    });
    await db.execute('DROP TABLE accounts');
    await db.execute('ALTER TABLE accounts_v36 RENAME TO accounts');
    for (final table in [
      'account_checkpoint_covered_unknown_events',
      'account_balance_checkpoints',
      'net_worth_verified_checkpoint_items',
      'net_worth_verified_checkpoints',
      'budget_fixed_commitment_occurrences',
      'budget_cycle_overrides',
      'budget_plan_revisions',
      'budget_change_events',
      'budget_plans',
    ]) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
    await db.execute('PRAGMA user_version = 36');
    await db.close();

    repo = AppRepository();
    await repo.init();
    expect(repo.budgetPeriods, hasLength(1));
    expect(repo.accounts.any((item) => item.name == '旧删除账户'), isFalse);
    expect(repo.accounts.first.openingBalanceEffectiveMs, isNull);
    expect(
      repo.accounts.first.openingBalanceQuality,
      AccountOpeningBalanceQuality.legacyUnknown,
    );
    await repo.closeForTest();

    final check = await databaseFactory.openDatabase(path);
    final hidden = await check.query(
      'accounts',
      where: 'name = ?',
      whereArgs: ['旧删除账户'],
      limit: 1,
    );
    expect(hidden.single['status'], AccountStatus.legacyHidden.storageKey);
    expect(
      Sqflite.firstIntValue(
        await check.rawQuery('SELECT COUNT(*) FROM budget_plans'),
      ),
      0,
    );
    expect(
      Sqflite.firstIntValue(await check.rawQuery('PRAGMA user_version')),
      43,
    );
    await check.close();
  });

  test('统计卡片旧配置迁移：移除废弃余量图，保留本月进度卡', () async {
    final repo = await freshRepo();
    await repo.closeForTest();

    final path = p.join(tmp.path, 'qingji.db');
    final db = await databaseFactory.openDatabase(path);
    await db.insert(
      'app_settings',
      {
        'key': 'stat_cards',
        'value': 'insights,pace,battery,budget,budget_cat,ring'
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['stat_cards_config_version'],
    );
    await db.close();

    final migrated = AppRepository();
    await migrated.init();
    expect(migrated.statCardOrder, ['insights', 'battery', 'ring']);
    await migrated.setStatCardOrder(
        ['insights', 'pace', 'battery', 'budget', 'budget_cat', 'ring']);
    await migrated.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.statCardOrder, ['insights', 'battery', 'ring']);
    await reopened.closeForTest();
  });

  test('统计卡片配置：显式全关后重启不恢复默认', () async {
    final repo = await freshRepo();
    expect(repo.hasStatCardOrderConfig, isFalse);
    expect(repo.statCardOrder, isEmpty);

    await repo.setStatCardOrder([]);
    expect(repo.hasStatCardOrderConfig, isTrue);
    expect(repo.statCardOrder, isEmpty);
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.hasStatCardOrderConfig, isTrue);
    expect(reopened.statCardOrder, isEmpty);
    await reopened.closeForTest();
  });

  test('自动记账通知事件跨重试和重启只生成一笔流水', () async {
    final repo = await freshRepo();
    final firstId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('2.50'),
      accountId: repo.accounts.first.id,
      note: '第一次确认',
      date: DateTime(2026, 7, 11, 8),
      autoRecordSourceId: 'notification-event-1',
    );
    final retriedId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('99.00'),
      accountId: repo.accounts.first.id,
      note: '不应重复写入',
      date: DateTime(2026, 7, 11, 8, 1),
      autoRecordSourceId: 'notification-event-1',
    );

    expect(retriedId, firstId);
    expect(repo.transactions, hasLength(1));
    expect(repo.transactions.single.note, '第一次确认');
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    final afterRestartId = await reopened.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.parse('10.00'),
      accountId: reopened.accounts.first.id,
      note: '重启后也不应重复写入',
      date: DateTime(2026, 7, 11, 8, 2),
      autoRecordSourceId: 'notification-event-1',
    );
    expect(afterRestartId, firstId);
    expect(reopened.transactions, hasLength(1));
    await reopened.closeForTest();
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
    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      categoryId: aId,
      accountId: repo.accounts.first.id,
      period: RecurPeriod.monthly,
      startDate: DateTime(2099, 1, 1),
      note: '分类合并定时规则',
    );
    await repo.addBudgetPeriod(
      start: DateTime(2026, 1, 1),
      total: Decimal.fromInt(1000),
      categoryBudgets: {
        'test_a': Decimal.fromInt(100),
        'test_b': Decimal.fromInt(50),
      },
    );

    await repo.mergeCategory(aId, bId);

    expect(await repo.transactionCountForCategory(bId), 1);
    expect(repo.categories.where((c) => c.id == aId), isEmpty);
    expect(repo.recallCategoryKey('瑞幸咖啡', TransactionKind.expense), 'test_b');
    expect(repo.recurringRules.single.categoryId, bId);
    expect(repo.budgetPeriods.single.categoryBudgets['test_a'], isNull);
    expect(
      repo.budgetPeriods.single.categoryBudgets['test_b'],
      Decimal.fromInt(150),
    );
    await repo.closeForTest();
  });

  test('deleteCategory 会阻止删除仍被定时规则或分类预算使用的分类', () async {
    final repo = await freshRepo();
    final categoryId = await repo.addCategory(
      key: 'protected_category',
      nameZh: '受保护分类',
      nameEn: 'Protected',
      kind: TransactionKind.expense,
    );
    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      categoryId: categoryId,
      accountId: repo.accounts.first.id,
      period: RecurPeriod.monthly,
      startDate: DateTime(2099, 1, 1),
    );

    await expectLater(
      repo.deleteCategory(categoryId),
      throwsA(isA<StateError>()),
    );
    expect(repo.categories.where((c) => c.id == categoryId), hasLength(1));
    await repo.closeForTest();
  });

  test('定时记账：月末起始日写入 anchorDay，重启后仍按原日锚定', () async {
    final repo = await freshRepo();
    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.parse('88.88'),
      accountId: repo.accounts.first.id,
      period: RecurPeriod.monthly,
      startDate: DateTime(2099, 1, 31),
      note: 'monthly rent',
    );

    expect(repo.recurringRules, hasLength(1));
    expect(repo.recurringRules.single.anchorDay, 31);
    expect(repo.recurringRules.single.nextDue, DateTime(2099, 1, 31));
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.recurringRules, hasLength(1));
    expect(reopened.recurringRules.single.anchorDay, 31);
    expect(
      RecurPeriod.monthly.previewDates(
        reopened.recurringRules.single.nextDue,
        count: 4,
      ),
      [
        DateTime(2099, 1, 31),
        DateTime(2099, 2, 28),
        DateTime(2099, 3, 31),
        DateTime(2099, 4, 30),
      ],
    );
    await reopened.closeForTest();
  });

  test('定时记账支持转账：到期生成转账流水两腿余额正确，缺转入账户则拒绝', () async {
    final repo = await freshRepo();
    final fromId = await repo.addAccount(
      name: '转出账户',
      openingBalance: Decimal.fromInt(500),
    );
    final toId = await repo.addAccount(name: '转入账户');

    // 转账规则必须有转入账户，且不能与转出账户相同。
    await expectLater(
      repo.addRecurringRule(
        kind: TransactionKind.transfer,
        amount: Decimal.fromInt(100),
        accountId: fromId,
        period: RecurPeriod.monthly,
        startDate: DateTime(2099, 1, 1),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repo.addRecurringRule(
        kind: TransactionKind.transfer,
        amount: Decimal.fromInt(100),
        accountId: fromId,
        toAccountId: fromId,
        period: RecurPeriod.monthly,
        startDate: DateTime(2099, 1, 1),
      ),
      throwsArgumentError,
    );
    expect(repo.recurringRules, isEmpty);

    // 起始日已过 → 立即补记一笔转账（materialize 的 transfer 执行路径）。
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    await repo.addRecurringRule(
      kind: TransactionKind.transfer,
      amount: Decimal.fromInt(100),
      accountId: fromId,
      toAccountId: toId,
      period: RecurPeriod.monthly,
      startDate: yesterday,
      note: '房贷还款',
    );
    final rule = repo.recurringRules.single;
    expect(rule.txKind, TransactionKind.transfer);
    expect(rule.toAccountId, toId);
    expect(rule.generatedCount, 1);

    final tx =
        repo.transactions.singleWhere((t) => t.recurringRuleId == rule.id);
    expect(tx.txKind, TransactionKind.transfer);
    expect(tx.accountId, fromId);
    expect(tx.toAccountId, toId);
    expect(tx.categoryId, isNull);

    final fromAccount =
        repo.accounts.singleWhere((account) => account.id == fromId);
    final toAccount =
        repo.accounts.singleWhere((account) => account.id == toId);
    expect(repo.accountBalanceOf(fromAccount), Decimal.fromInt(400));
    expect(repo.accountBalanceOf(toAccount), Decimal.fromInt(100));
    await repo.closeForTest();
  });

  test('账户仍被定时规则引用时不能归档，停用规则也不会绕过保护', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(name: '定时扣款账户');
    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: accountId,
      period: RecurPeriod.monthly,
      startDate: DateTime(2099, 1, 1),
      note: '未来房租',
    );
    final ruleId = repo.recurringRules.single.id;
    await repo.setRecurringEnabled(ruleId, false);

    await expectLater(
      repo.archiveAccount(accountId),
      throwsA(isA<StateError>()),
    );
    expect(
        repo.activeAccounts.any((account) => account.id == accountId), isTrue);

    await repo.deleteRecurringRule(ruleId);
    await repo.archiveAccount(accountId);
    expect(
      repo.archivedAccounts.any((account) => account.id == accountId),
      isTrue,
    );
    await repo.closeForTest();
  });

  test('失效账户的到期定时规则不会改扣其他账户或推进进度', () async {
    var repo = await freshRepo();
    final accountId = await repo.addAccount(name: '后来失效的定时账户');
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(66),
      accountId: accountId,
      period: RecurPeriod.daily,
      startDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
      note: '不能改扣默认账户',
    );
    final ruleId = repo.recurringRules.single.id;
    await repo.closeForTest();

    final todayRaw = DateTime.now();
    final today = DateTime(todayRaw.year, todayRaw.month, todayRaw.day);
    final db =
        await databaseFactory.openDatabase(p.join(tmp.path, 'qingji.db'));
    await db.update(
      'accounts',
      {
        'status': AccountStatus.archived.storageKey,
        'archived_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [accountId],
    );
    await db.update(
      'recurring_rules',
      {
        'next_due_ms': today.millisecondsSinceEpoch,
        'generated_count': 0,
        'enabled': 1,
      },
      where: 'id = ?',
      whereArgs: [ruleId],
    );
    await db.close();

    repo = await freshRepo();
    final rule = repo.recurringRules.single;
    expect(rule.nextDue, today);
    expect(rule.generatedCount, 0);
    expect(
      repo.transactions
          .where((transaction) => transaction.recurringRuleId == ruleId),
      isEmpty,
    );
    expect(
      repo.archivedAccounts.any((account) => account.id == accountId),
      isTrue,
    );
    await repo.closeForTest();
  });

  test('归档与新增或修改定时规则并发时不会留下悬空账户引用', () async {
    final repo = await freshRepo();
    final futureDate = DateTime(2099, 1, 1);

    Future<bool> succeeds(Future<void> Function() action) async {
      try {
        await action();
        return true;
      } catch (_) {
        return false;
      }
    }

    final newRuleAccountId = await repo.addAccount(name: '并发新增目标账户');
    final addRace = await Future.wait([
      succeeds(() => repo.archiveAccount(newRuleAccountId)),
      succeeds(() => repo.addRecurringRule(
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(10),
            accountId: newRuleAccountId,
            period: RecurPeriod.monthly,
            startDate: futureDate,
            note: '并发新增规则',
          )),
    ]);
    expect(addRace.where((result) => result), hasLength(1));

    final sourceAccountId = repo.transactionAccounts.first.id;
    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      accountId: sourceAccountId,
      period: RecurPeriod.monthly,
      startDate: futureDate,
      note: '并发修改规则',
    );
    final updateRule = repo.recurringRules.singleWhere(
      (rule) => rule.note == '并发修改规则',
    );
    final updateTargetId = await repo.addAccount(name: '并发修改目标账户');
    final updateRace = await Future.wait([
      succeeds(() => repo.archiveAccount(updateTargetId)),
      succeeds(() => repo.updateRecurringRule(
            id: updateRule.id,
            kind: updateRule.txKind,
            amount: updateRule.amount,
            categoryId: updateRule.categoryId,
            accountId: updateTargetId,
            bookId: updateRule.bookId,
            note: updateRule.note,
            period: updateRule.recurPeriod,
            nextDue: updateRule.nextDue,
            startDate: updateRule.startDate,
            endDate: updateRule.endDate,
            totalCount: updateRule.totalCount,
          )),
    ]);
    expect(updateRace.where((result) => result), hasLength(1));
    await repo.closeForTest();

    final db =
        await databaseFactory.openDatabase(p.join(tmp.path, 'qingji.db'));
    final dangling = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*)
      FROM recurring_rules r
      INNER JOIN accounts a ON a.id = r.account_id
      WHERE a.status = 'archived'
    '''));
    expect(dangling, 0);
    await db.close();
  });

  test('定时记账：记录次数会阻止分期账单无限生成', () async {
    final repo = await freshRepo();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 4, 1);

    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.parse('100'),
      accountId: repo.accounts.first.id,
      period: RecurPeriod.monthly,
      startDate: start,
      totalCount: 3,
      note: '电脑分期',
    );

    final rule = repo.recurringRules.single;
    expect(rule.generatedCount, 3);
    expect(rule.totalCount, 3);
    expect(rule.isCompletedByCount, isTrue);
    expect(rule.nextDue, DateTime(start.year, start.month + 3, 1));
    expect(repo.transactions, hasLength(3));
    expect(
        repo.transactions.every((t) => t.recurringRuleId == rule.id), isTrue);
    expect(
      repo.transactions.every(
        (t) => t.timePrecision == TransactionTimePrecision.dateOnly,
      ),
      isTrue,
    );
    expect(
      repo.transactions.map((t) => t.date).toSet(),
      {
        start,
        DateTime(start.year, start.month + 1, 1),
        DateTime(start.year, start.month + 2, 1),
      },
    );
    await repo.closeForTest();
  });

  test('定时记账：结束日期包含当天且不会继续生成', () async {
    final repo = await freshRepo();
    final todayRaw = DateTime.now();
    final today = DateTime(todayRaw.year, todayRaw.month, todayRaw.day);
    final start = today.subtract(const Duration(days: 3));
    final end = today.subtract(const Duration(days: 1));

    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.parse('12.5'),
      accountId: repo.accounts.first.id,
      period: RecurPeriod.daily,
      startDate: start,
      endDate: end,
      note: '短期通勤',
    );

    final rule = repo.recurringRules.single;
    expect(rule.generatedCount, 3);
    expect(rule.endDate, end);
    expect(rule.isCompletedByDate, isTrue);
    expect(rule.nextDue, today);
    expect(repo.transactions, hasLength(3));
    expect(
      repo.transactions.map((t) => t.date).toSet(),
      {
        start,
        start.add(const Duration(days: 1)),
        end,
      },
    );
    await repo.closeForTest();
  });

  test('定时记账：可指定账本，生成账单落到目标账本', () async {
    final repo = await freshRepo();
    final travelId = await repo.addBook(name: '旅行');
    final todayRaw = DateTime.now();
    final today = DateTime(todayRaw.year, todayRaw.month, todayRaw.day);

    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.parse('66'),
      accountId: repo.accounts.first.id,
      bookId: travelId,
      period: RecurPeriod.daily,
      startDate: today,
      totalCount: 1,
      note: '旅行日费',
    );

    expect(await repo.transactionCountForBook(travelId), 1);
    expect(repo.recurringRules, isEmpty);

    await repo.switchBook(travelId);

    expect(repo.recurringRules, hasLength(1));
    expect(repo.recurringRules.single.bookId, travelId);
    expect(repo.transactions, hasLength(1));
    expect(repo.transactions.single.note, '旅行日费');
    expect(repo.transactions.single.recurringRuleId,
        repo.recurringRules.single.id);
    expect(
      repo.netWorthSnapshots.first.netWorth,
      repo.currentNetWorthResult().value!.netWorth,
    );
    expect(
      repo.netWorthSnapshots.first.toComputedSnapshot().lineage.causes,
      contains(NetWorthSnapshotCause.scheduledRebuild),
    );
    await repo.closeForTest();
  });

  test('定时记账：规则进度回退后重试不会重复生成同一期流水', () async {
    final repo = await freshRepo();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.parse('39.9'),
      accountId: repo.accounts.first.id,
      period: RecurPeriod.daily,
      startDate: today,
      totalCount: 1,
      note: '幂等测试',
    );
    final ruleId = repo.recurringRules.single.id;
    expect(repo.transactions, hasLength(1));
    await repo.closeForTest();

    final db =
        await databaseFactory.openDatabase(p.join(tmp.path, 'qingji.db'));
    await db.update(
      'recurring_rules',
      {
        'next_due_ms': today.millisecondsSinceEpoch,
        'generated_count': 0,
      },
      where: 'id = ?',
      whereArgs: [ruleId],
    );
    await db.close();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.transactions, hasLength(1));
    expect(reopened.recurringRules.single.generatedCount, 1);
    expect(reopened.recurringRules.single.nextDue,
        today.add(const Duration(days: 1)));
    await reopened.closeForTest();
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

  test('deleteBook 转移会同步迁移预算、定时规则、报告和资产', () async {
    final repo = await freshRepo();
    final defaultBookId = repo.currentBookId;
    final travelId = await repo.addBook(name: '旅行', includeInTotal: false);
    await repo.switchBook(travelId);
    await repo.addRecurringRule(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: repo.accounts.first.id,
      period: RecurPeriod.monthly,
      startDate: DateTime(2099, 1, 1),
      note: '旅行定时账',
    );
    await repo.addBudgetPeriod(
      bookId: travelId,
      start: DateTime(2026, 1, 1),
      total: Decimal.fromInt(1000),
    );
    await repo.addPhysicalAsset(
      name: '旅行相机',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(2000),
      sourceType: PhysicalAssetSourceType.historicalExisting,
    );
    await repo.addReceivableAsset(
      name: '旅行押金',
      originalAmount: Decimal.fromInt(500),
    );
    await repo.addReport(
      type: 'monthly',
      title: '旅行月报',
      summary: 'summary',
      markdown: '# report',
    );
    await repo.switchBook(defaultBookId);

    await repo.deleteBook(travelId, moveRecordsToDefault: true);

    expect(repo.recurringRules.single.bookId, defaultBookId);
    expect(repo.budgetPeriods.single.bookId, defaultBookId);
    expect(repo.physicalAssets.single.bookId, defaultBookId);
    expect(repo.receivableAssets.single.bookId, defaultBookId);
    expect(repo.reports.single.bookId, defaultBookId);
    await repo.closeForTest();
  });

  test('deleteBook 连数据删除后会同步刷新当天净资产快照', () async {
    final repo = await freshRepo();
    final doomedBookId = await repo.addBook(name: '待删除账本');
    await repo.switchBook(doomedBookId);
    await repo.addPhysicalAsset(
      name: '待删除物品',
      assetType: AssetType.other,
      currentValue: Decimal.fromInt(300),
      sourceType: PhysicalAssetSourceType.historicalExisting,
    );
    await repo.addReceivableAsset(
      name: '待删除权益',
      originalAmount: Decimal.fromInt(200),
    );
    expect(
      repo.currentNetWorthResult().value!.netWorth,
      isNot(Decimal.zero),
    );

    await repo.deleteBook(doomedBookId, moveRecordsToDefault: false);

    expect(repo.physicalAssets, isEmpty);
    expect(repo.receivableAssets, isEmpty);
    expect(
      repo.netWorthSnapshots.first.netWorth,
      repo.currentNetWorthResult().value!.netWorth,
    );
    expect(
      repo.netWorthSnapshots.first.toComputedSnapshot().lineage.causes,
      containsAll({
        NetWorthSnapshotCause.physicalAsset,
        NetWorthSnapshotCause.receivable,
      }),
    );
    await repo.closeForTest();
  });

  test('账户余额跨全部账本计算，不受当前账本或总账本开关影响', () async {
    final repo = await freshRepo();
    final account = repo.accounts.first;
    final privateBookId = await repo.addBook(
      name: '不计入总账本',
      includeInTotal: false,
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(80),
      accountId: account.id,
      date: DateTime(2026, 7, 10),
      bookId: privateBookId,
    );

    expect(repo.visibleTransactions, isEmpty);
    expect(repo.accountBalanceOf(account), Decimal.fromInt(-80));
    await repo.switchBook(privateBookId);
    expect(repo.accountBalanceOf(account), Decimal.fromInt(-80));
    await repo.closeForTest();
  });

  test('新增账户和流水只接受 CNY，既有外币不会混入人民币净资产', () async {
    final repo = await freshRepo();
    final cnyAccountId = repo.accounts.first.id;
    await expectLater(
      repo.addAccount(name: '美元账户', currencyCode: 'USD'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      repo.addTransaction(
        kind: TransactionKind.income,
        amount: Decimal.fromInt(10),
        currencyCode: 'USD',
        accountId: repo.accounts.first.id,
        date: DateTime(2026, 7, 10),
      ),
      throwsA(isA<UnsupportedError>()),
    );
    await repo.closeForTest();

    final db =
        await databaseFactory.openDatabase(p.join(tmp.path, 'qingji.db'));
    final usdAccountId = await db.insert('accounts', {
      'name': '历史美元账户',
      'currency_code': 'USD',
      'type': AccountType.cash.storageKey,
      'opening_balance': '12',
      'include_in_net_worth': 1,
      'institution': '',
      'sort_order': 99,
      'is_deleted': 0,
    });
    await db.close();

    final reopened = await freshRepo();
    expect(reopened.accounts.map((a) => a.id), contains(usdAccountId));
    expect(
      reopened.transactionAccounts.map((a) => a.id),
      isNot(contains(usdAccountId)),
    );
    await expectLater(
      reopened.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(1),
        accountId: usdAccountId,
        date: DateTime(2026, 7, 10),
      ),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      reopened.addTransaction(
        kind: TransactionKind.transfer,
        amount: Decimal.fromInt(1),
        accountId: cnyAccountId,
        toAccountId: usdAccountId,
        date: DateTime(2026, 7, 10),
      ),
      throwsA(isA<ArgumentError>()),
    );
    await reopened.closeForTest();
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

  test('桌面小组件快照：本月进度对比按同期天数计算', () async {
    final repo = await freshRepo();
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;
    final accountId = repo.accounts.first.id;

    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(30),
      categoryId: cat.id,
      accountId: accountId,
      note: '本月同期',
      date: DateTime(2026, 7, 7),
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(10),
      categoryId: cat.id,
      accountId: accountId,
      note: '六月同期',
      date: DateTime(2026, 6, 5),
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      categoryId: cat.id,
      accountId: accountId,
      note: '五月同期',
      date: DateTime(2026, 5, 7),
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(999),
      categoryId: cat.id,
      accountId: accountId,
      note: '六月非同期',
      date: DateTime(2026, 6, 8),
    );

    final snapshot = FeimiaoWidgetSnapshotBuilder.build(
      repo,
      now: DateTime(2026, 7, 7, 12),
    );

    expect(snapshot.paceCaption, '截至7月7日');
    expect(snapshot.monthExpenseText, '¥30.00');
    expect(snapshot.paceAverageText, '¥15.00');
    expect(snapshot.paceThisProgress, 100);
    expect(snapshot.paceAverageProgress, 50);
    final json = snapshot.toJson();
    expect(json['schemaVersion'], 2);
    final modules = json['modules'] as Map<String, Object?>;
    final pace = modules['pace'] as Map<String, Object?>;
    final average = pace['average'] as Map<String, Object?>;
    final current = pace['current'] as Map<String, Object?>;
    final chart = pace['chart'] as Map<String, Object?>;
    final months = chart['months'] as List<Object?>;
    expect(pace['title'], '截至7月7日');
    expect(average['label'], '平均');
    expect(average['amountText'], '¥15.00');
    expect(current['label'], '本月');
    expect(current['amountText'], '¥30.00');
    expect(months, hasLength(7));
    expect((months.last as Map<String, Object?>)['label'], '7月');
    expect((months.last as Map<String, Object?>)['isCurrent'], isTrue);
    await repo.closeForTest();
  });

  test('桌面小组件快照：有预算时输出预算剩余、支出和收入', () async {
    final repo = await freshRepo();
    final expenseCat =
        repo.categoriesForKindRanked(TransactionKind.expense).first;
    final incomeCat =
        repo.categoriesForKindRanked(TransactionKind.income).first;
    final accountId = repo.accounts.first.id;

    await repo.addBudgetPeriod(
      start: DateTime(2026, 7, 1),
      total: Decimal.fromInt(100),
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(30),
      categoryId: expenseCat.id,
      accountId: accountId,
      note: '本月支出',
      date: DateTime(2026, 7, 7),
    );
    await repo.addTransaction(
      kind: TransactionKind.income,
      amount: Decimal.fromInt(20),
      categoryId: incomeCat.id,
      accountId: accountId,
      note: '本月收入',
      date: DateTime(2026, 7, 7),
    );

    final snapshot = FeimiaoWidgetSnapshotBuilder.build(
      repo,
      now: DateTime(2026, 7, 7, 12),
    );

    expect(snapshot.budgetTitle, '预算剩余');
    expect(snapshot.budgetText, '¥70.00');
    expect(snapshot.monthExpenseText, '¥30.00');
    expect(snapshot.monthIncomeText, '¥20.00');
    expect(snapshot.budgetHint, '已用 ¥30.00 / ¥100.00');
    expect(snapshot.budgetProgress, 30);
    final modules = snapshot.toJson()['modules'] as Map<String, Object?>;
    final overview = modules['overview'] as Map<String, Object?>;
    final primary = overview['primary'] as Map<String, Object?>;
    final secondary = overview['secondary'] as List<Object?>;
    final progress = overview['progress'] as Map<String, Object?>;
    expect(overview['mode'], 'budget');
    expect(primary['label'], '预算剩余');
    expect(primary['amountText'], '¥70.00');
    expect((secondary.first as Map<String, Object?>)['label'], '支出');
    expect(progress['visible'], isTrue);
    expect(progress['value'], 30);
    await repo.closeForTest();
  });

  test('桌面小组件快照：分类排行输出百分比进度条数值', () async {
    final repo = await freshRepo();
    final cats = repo
        .categoriesForKind(TransactionKind.expense)
        .where((c) => c.parentId == null)
        .toList();
    final accountId = repo.accounts.first.id;

    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(30),
      categoryId: cats[0].id,
      accountId: accountId,
      note: '分类 A',
      date: DateTime(2026, 7, 7),
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(10),
      categoryId: cats[1].id,
      accountId: accountId,
      note: '分类 B',
      date: DateTime(2026, 7, 7),
    );

    final snapshot = FeimiaoWidgetSnapshotBuilder.build(
      repo,
      now: DateTime(2026, 7, 7, 12),
    );

    expect(snapshot.categories, hasLength(2));
    expect(snapshot.categories[0].percentText, '75%');
    expect(snapshot.categories[0].progress, 75);
    expect(snapshot.categories[1].percentText, '25%');
    expect(snapshot.categories[1].progress, 25);
    final modules = snapshot.toJson()['modules'] as Map<String, Object?>;
    final categories = modules['categories'] as Map<String, Object?>;
    final items = categories['items'] as List<Object?>;
    expect(categories['title'], '分类与支出活动');
    expect(categories['showAllText'], '查看所有');
    expect(items, hasLength(2));
    expect((items.first as Map<String, Object?>)['count'], 1);
    expect((items.first as Map<String, Object?>)['colorValue'], isA<int>());
    await repo.closeForTest();
  });

  test('统计与小组件把同一一级分类的二级账单按退款净额统一聚合', () async {
    final repo = await freshRepo();
    final childrenByParent = <int, List<CategoryEntity>>{};
    for (final category in repo.categoriesForKind(TransactionKind.expense)) {
      final parentId = category.parentId;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(category);
      }
    }
    final children =
        childrenByParent.values.firstWhere((items) => items.length >= 2);
    final parent =
        repo.categories.singleWhere((c) => c.id == children.first.parentId);
    final accountId = repo.accounts.first.id;

    final firstId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(30),
      categoryId: children[0].id,
      accountId: accountId,
      note: '二级分类 A',
      date: DateTime(2026, 7, 7),
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      categoryId: children[1].id,
      accountId: accountId,
      note: '二级分类 B',
      date: DateTime(2026, 7, 7),
    );
    await repo.refundTransaction(
      repo.transactions.singleWhere((t) => t.id == firstId),
      Decimal.fromInt(10),
      settledAt: DateTime(2026, 7, 8),
      settlementAccountId: accountId,
    );

    final summary = StatisticsEngine.monthlySummary(
      repo.allRecords,
      year: 2026,
      month: 7,
    );
    final snapshot = FeimiaoWidgetSnapshotBuilder.build(
      repo,
      now: DateTime(2026, 7, 7, 12),
    );

    expect(summary.expenseByCategory, hasLength(1));
    expect(summary.expenseByCategory.single.key, parent.key);
    expect(summary.expenseByCategory.single.name, parent.nameZh);
    expect(summary.expenseByCategory.single.total, Decimal.fromInt(40));
    expect(snapshot.categories, hasLength(1));
    expect(snapshot.categories.single.name, parent.nameZh);
    expect(snapshot.categories.single.amountText, '¥40.00');
    expect(snapshot.categories.single.count, 2);
    await repo.closeForTest();
  });

  test('桌面小组件快照：附着式退款按净额输出', () async {
    final repo = await freshRepo();
    final cat = repo
        .categoriesForKind(TransactionKind.expense)
        .where((c) => c.parentId == null)
        .first;
    final accountId = repo.accounts.first.id;

    final id = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      categoryId: cat.id,
      accountId: accountId,
      note: '带退款支出',
      date: DateTime(2026, 7, 7),
    );
    final original = repo.transactions.singleWhere((t) => t.id == id);
    await repo.refundTransaction(
      original,
      Decimal.fromInt(40),
      settledAt: DateTime(2026, 7, 8),
      settlementAccountId: accountId,
    );

    final snapshot = FeimiaoWidgetSnapshotBuilder.build(
      repo,
      now: DateTime(2026, 7, 7, 12),
    );

    expect(snapshot.monthExpenseText, '¥60.00');
    expect(snapshot.todayExpenseText, '¥60.00');
    expect(snapshot.categories, hasLength(1));
    expect(snapshot.categories.first.amountText, '¥60.00');
    expect(snapshot.categories.first.percentText, '100%');

    final modules = snapshot.toJson()['modules'] as Map<String, Object?>;
    final pace = modules['pace'] as Map<String, Object?>;
    final current = pace['current'] as Map<String, Object?>;
    expect(current['amountText'], '¥60.00');
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
    final firstRefundId = await repo.refundTransaction(
      original,
      Decimal.fromInt(5),
      settledAt: DateTime(2026, 7, 8),
      settlementAccountId: original.accountId!,
    );
    final secondRefundId = await repo.refundTransaction(
      original,
      Decimal.fromInt(3),
      settledAt: DateTime(2026, 7, 9),
      settlementAccountId: original.accountId!,
    );

    expect(repo.refundedAmountOf(id), Decimal.fromInt(8));
    expect(repo.netAmountOf(original), Decimal.fromInt(72));
    expect(repo.refundsOf(id), hasLength(2));
    expect(
      repo.refundsOf(id).map((refund) => refund.id),
      containsAll([firstRefundId, secondRefundId]),
    );
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

  test('退款保留原订单归属，按真实到账日和不同账户投影', () async {
    final repo = await freshRepo();
    final paymentAccount = repo.accounts.first;
    final receivingAccountId = await repo.addAccount(
      name: '退款到账卡',
      type: AccountType.debit,
    );
    final category =
        repo.categoriesForKindRanked(TransactionKind.expense).first;
    final replacementCategory = repo
        .categoriesForKindRanked(TransactionKind.expense)
        .firstWhere((item) => item.id != category.id);
    final originalId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      categoryId: category.id,
      accountId: paymentAccount.id,
      note: '六月订单',
      date: DateTime(2026, 6, 20),
    );
    final original = repo.transactions.singleWhere((t) => t.id == originalId);
    final settledAt = DateTime(2026, 7, 12);
    final refundId = await repo.refundTransaction(
      original,
      Decimal.fromInt(30),
      settledAt: settledAt,
      settlementAccountId: receivingAccountId,
    );

    var refund = repo.transactions.singleWhere((t) => t.id == refundId);
    expect(refund.refundOf, originalId);
    expect(refund.eventType, TransactionEventType.refund);
    expect(refund.date, DateTime(2026, 6, 20));
    expect(refund.settledAt, settledAt);
    expect(refund.accountId, paymentAccount.id);
    expect(refund.settlementAccountId, receivingAccountId);
    expect(refund.settlementQuality, SettlementQuality.userConfirmed);
    expect(
      refund.settlementAccountQuality,
      SettlementQuality.userConfirmed,
    );
    final receivingAccount =
        repo.accounts.singleWhere((item) => item.id == receivingAccountId);
    expect(
      repo.accountBalanceResultOf(receivingAccount).value!.balance,
      Decimal.fromInt(30),
    );

    await repo.updateTransaction(
      id: originalId,
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      categoryId: replacementCategory.id,
      accountId: paymentAccount.id,
      note: '修正原订单归属',
      date: DateTime(2026, 6, 25),
    );
    refund = repo.transactions.singleWhere((t) => t.id == refundId);
    expect(refund.categoryId, replacementCategory.id);
    expect(refund.date, DateTime(2026, 6, 25));
    expect(refund.settledAt, settledAt);
    expect(refund.settlementAccountId, receivingAccountId);

    await repo.deleteTransaction(refundId);
    expect(repo.transactions.where((t) => t.id == refundId), isEmpty);
    expect(repo.refundedAmountOf(originalId), Decimal.zero);
    expect(
      repo.accountBalanceResultOf(receivingAccount).value!.balance,
      Decimal.zero,
    );
    await repo.closeForTest();
  });

  test('报销可到工资卡，不回填原信用卡为到账账户', () async {
    final repo = await freshRepo();
    final creditAccountId = await repo.addAccount(
      name: '原信用卡',
      type: AccountType.credit,
    );
    final salaryAccountId = await repo.addAccount(
      name: '工资卡',
      type: AccountType.debit,
    );
    final originalId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(88),
      accountId: creditAccountId,
      note: '六月差旅',
      date: DateTime(2026, 6, 18),
      reimbursable: true,
    );
    final settledAt = DateTime(2026, 7, 12);

    await repo.markReimbursed(
      originalId,
      settledAt: settledAt,
      settlementAccountId: salaryAccountId,
    );

    final original = repo.transactions.singleWhere((t) => t.id == originalId);
    final reimbursement = repo.refundsOf(originalId).single;
    expect(original.reimbursable, isFalse);
    expect(repo.netAmountOf(original), Decimal.zero);
    expect(reimbursement.eventType, TransactionEventType.reimbursement);
    expect(reimbursement.date, DateTime(2026, 6, 18));
    expect(reimbursement.settledAt, settledAt);
    expect(reimbursement.accountId, creditAccountId);
    expect(reimbursement.settlementAccountId, salaryAccountId);
    expect(
      repo.accountBalanceOf(
        repo.accounts.singleWhere((item) => item.id == salaryAccountId),
      ),
      Decimal.fromInt(88),
    );
    expect(
      repo.accountBalanceOf(
        repo.accounts.singleWhere((item) => item.id == creditAccountId),
      ),
      Decimal.fromInt(-88),
    );
    await repo.closeForTest();
  });

  test('markReimbursed 对资产关联账单可用：净额归零、报销行落库', () async {
    final repo = await freshRepo();
    final account = repo.accounts.first;
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;
    await repo.addPhysicalAsset(
      name: '公司报销的显示器',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(2000),
      purchasePrice: Decimal.fromInt(2000),
      sourceType: PhysicalAssetSourceType.newPurchaseWithAccount,
      paymentAccountId: account.id,
      purchaseCategoryId: cat.id,
      purchaseDate: DateTime(2026, 7, 1),
      occurredAt: DateTime(2026, 7, 1),
    );
    final purchase = repo.visibleTransactions.single;

    // 与 refundTransaction 对齐：资产关联账单也能报销（挂冲减行不动原单），
    // 以前开头的 _assertTransactionMutable 会把这条路径整个堵死。
    await repo.markReimbursed(
      purchase.id,
      settledAt: DateTime(2026, 7, 20),
      settlementAccountId: account.id,
    );

    final original =
        repo.transactions.singleWhere((t) => t.id == purchase.id);
    expect(original.reimbursable, isFalse);
    expect(repo.netAmountOf(original), Decimal.zero);
    final reimbursement = repo.refundsOf(purchase.id).single;
    expect(reimbursement.eventType, TransactionEventType.reimbursement);
    await repo.closeForTest();
  });

  test('撤销报销：删除报销冲减行后原单回到待报销列表', () async {
    final repo = await freshRepo();
    final id = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(66),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 2),
      note: '待报销打车',
      reimbursable: true,
    );
    await repo.markReimbursed(
      id,
      settledAt: DateTime(2026, 7, 15),
      settlementAccountId: repo.accounts.first.id,
    );
    expect(repo.reimbursableTransactions, isEmpty);
    final reimbursementRow = repo.refundsOf(id).single;

    await repo.deleteTransaction(reimbursementRow.id);

    final original = repo.transactions.singleWhere((t) => t.id == id);
    expect(original.reimbursable, isTrue);
    expect(repo.netAmountOf(original), Decimal.fromInt(66));
    expect(repo.reimbursableTransactions.map((t) => t.id), contains(id));
    await repo.closeForTest();
  });

  test('退款和报销拒绝不存在的到账账户', () async {
    final repo = await freshRepo();
    final originalId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(50),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 6, 18),
      reimbursable: true,
    );
    final original = repo.transactions.singleWhere((t) => t.id == originalId);

    await expectLater(
      repo.refundTransaction(
        original,
        Decimal.fromInt(10),
        settledAt: DateTime(2026, 7, 12),
        settlementAccountId: 999999,
      ),
      throwsArgumentError,
    );
    await expectLater(
      repo.markReimbursed(
        originalId,
        settledAt: DateTime(2026, 7, 12),
        settlementAccountId: 999999,
      ),
      throwsArgumentError,
    );
    expect(repo.refundsOf(originalId), isEmpty);
    expect(repo.transactions.single.reimbursable, isTrue);
    await repo.closeForTest();
  });

  test('常规账单增删改和退款只增量回读，不触发全表重载', () async {
    final repo = await freshRepo();
    final categories = repo.categoriesForKindRanked(TransactionKind.expense);
    final baseline = repo.transactionFullReloadCount;

    final id = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      categoryId: categories.first.id,
      accountId: repo.accounts.first.id,
      note: '增量同步测试',
      date: DateTime(2026, 7, 4),
    );
    expect(repo.transactionFullReloadCount, baseline);
    expect(repo.transactions.singleWhere((t) => t.id == id).amount,
        Decimal.fromInt(100));

    await repo.setTransactionCategory(id, categories.last.id);
    expect(repo.transactionFullReloadCount, baseline);
    expect(repo.transactions.singleWhere((t) => t.id == id).categoryId,
        categories.last.id);

    await repo.updateTransaction(
      id: id,
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(120),
      categoryId: categories.last.id,
      accountId: repo.accounts.first.id,
      note: '增量同步测试-已编辑',
      date: DateTime(2026, 7, 5),
    );
    expect(repo.transactionFullReloadCount, baseline);
    final edited = repo.transactions.singleWhere((t) => t.id == id);
    expect(edited.amount, Decimal.fromInt(120));
    expect(edited.note, '增量同步测试-已编辑');

    await repo.refundTransaction(
      edited,
      Decimal.fromInt(20),
      settledAt: DateTime(2026, 7, 8),
      settlementAccountId: edited.accountId!,
    );
    expect(repo.transactionFullReloadCount, baseline);
    expect(repo.refundedAmountOf(id), Decimal.fromInt(20));
    expect(repo.netAmountOf(repo.transactions.singleWhere((t) => t.id == id)),
        Decimal.fromInt(100));

    await repo.deleteTransaction(id);
    expect(repo.transactionFullReloadCount, baseline);
    expect(repo.transactions.where((t) => t.id == id || t.refundOf == id),
        isEmpty);
    await repo.closeForTest();
  });

  test('账单导入：无订单号退款按商户挂回原单，不显示独立负数', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;
    final result = await repo.importReviewedBillBatch(
      accountId: accountId,
      rows: [
        (
          row: ImportedBillRow(
            date: DateTime(2026, 7, 3),
            kind: TransactionKind.expense,
            category: '',
            note: '美团 · 美团订单-26070311200700',
            amount: Decimal.parse('150.17'),
            merchant: '美团',
            product: '美团订单-26070311200700',
          ),
          categoryKey: cat.key,
        ),
      ],
      refunds: [
        ImportedBillRow(
          date: DateTime(2026, 7, 3),
          kind: TransactionKind.expense,
          category: '',
          note: '退款',
          amount: Decimal.parse('9.16'),
          merchant: '美团',
          product: '退款',
          isRefund: true,
        ),
        ImportedBillRow(
          date: DateTime(2026, 7, 3),
          kind: TransactionKind.income,
          category: 'refund',
          note: 'refund',
          amount: Decimal.parse('0.39'),
          isRefund: true,
        ),
      ],
    );

    expect(result.inserted, 1);
    expect(result.refundsAttached, 2);
    expect(repo.visibleTransactions, hasLength(1));
    final original = repo.visibleTransactions.single;
    expect(repo.refundedAmountOf(original.id), Decimal.parse('9.55'));
    expect(repo.netAmountOf(original), Decimal.parse('140.62'));
    expect(
        repo.transactions.where((t) => t.amount < Decimal.zero), hasLength(2));
    expect(repo.visibleTransactions.where((t) => t.amount < Decimal.zero),
        isEmpty);
    await repo.closeForTest();
  });

  test('refundTransaction rejects over-refund at repository boundary',
      () async {
    final repo = await freshRepo();
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;
    final id = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(80),
      categoryId: cat.id,
      accountId: repo.accounts.first.id,
      note: 'ticket',
      date: DateTime(2026, 7, 3),
    );
    final original = repo.transactions.firstWhere((t) => t.id == id);

    await repo.refundTransaction(
      original,
      Decimal.fromInt(70),
      settledAt: DateTime(2026, 7, 8),
      settlementAccountId: original.accountId!,
    );
    await expectLater(
      repo.refundTransaction(
        original,
        Decimal.fromInt(11),
        settledAt: DateTime(2026, 7, 9),
        settlementAccountId: original.accountId!,
      ),
      throwsA(isA<StateError>()),
    );

    expect(repo.refundedAmountOf(id), Decimal.fromInt(70));
    expect(repo.netAmountOf(original), Decimal.fromInt(10));
    expect(repo.refundsOf(id), hasLength(1));
    expect(repo.allRecords.single.amount, Decimal.fromInt(10));
    await repo.closeForTest();
  });

  test('并发退款不能合计超过原账单金额', () async {
    final repo = await freshRepo();
    final id = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 1),
    );
    final original = repo.transactions.singleWhere((t) => t.id == id);

    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        repo
            .refundTransaction(
              original,
              Decimal.fromInt(60),
              settledAt: DateTime(2026, 7, 8),
              settlementAccountId: original.accountId!,
            )
            .then((_) => true)
            .catchError((_) => false),
    ]);

    expect(results.where((ok) => ok), hasLength(1));
    expect(repo.refundedAmountOf(id), Decimal.fromInt(60));
    expect(repo.refundsOf(id), hasLength(1));
    await repo.closeForTest();
  });

  test('已有退款的账单不能改类型或把金额改到退款额以下', () async {
    final repo = await freshRepo();
    final id = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 1),
    );
    final original = repo.transactions.singleWhere((t) => t.id == id);
    await repo.refundTransaction(
      original,
      Decimal.fromInt(70),
      settledAt: DateTime(2026, 7, 8),
      settlementAccountId: original.accountId!,
    );

    Future<void> update(TransactionKind kind, Decimal amount) =>
        repo.updateTransaction(
          id: id,
          kind: kind,
          amount: amount,
          accountId: repo.accounts.first.id,
          date: DateTime(2026, 7, 2),
        );

    await expectLater(
      update(TransactionKind.income, Decimal.fromInt(100)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      update(TransactionKind.expense, Decimal.fromInt(69)),
      throwsA(isA<StateError>()),
    );
    await update(TransactionKind.expense, Decimal.fromInt(80));
    expect(repo.transactions.singleWhere((t) => t.id == id).amount,
        Decimal.fromInt(80));
    expect(repo.refundedAmountOf(id), Decimal.fromInt(70));
    await repo.closeForTest();
  });

  test('账单导入：同文件内完全相同账单按真实笔数导入，重复导入才跳过', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    final publicTransport = repo.categories
        .where(
            (c) => c.kind == TransactionKind.expense && c.key == 'trans_public')
        .first;
    final rows = <({ImportedBillRow row, String? categoryKey})>[
      (
        row: ImportedBillRow(
          date: DateTime(2026, 6, 28),
          kind: TransactionKind.expense,
          category: '公共交通',
          note: '公交',
          amount: Decimal.parse('1'),
        ),
        categoryKey: publicTransport.key,
      ),
      (
        row: ImportedBillRow(
          date: DateTime(2026, 6, 28),
          kind: TransactionKind.expense,
          category: '公共交通',
          note: '地铁',
          amount: Decimal.parse('2.5'),
        ),
        categoryKey: publicTransport.key,
      ),
      (
        row: ImportedBillRow(
          date: DateTime(2026, 6, 28),
          kind: TransactionKind.expense,
          category: '公共交通',
          note: '玩偶',
          amount: Decimal.parse('88.2'),
        ),
        categoryKey: publicTransport.key,
      ),
      (
        row: ImportedBillRow(
          date: DateTime(2026, 6, 28),
          kind: TransactionKind.expense,
          category: '公共交通',
          note: '地铁',
          amount: Decimal.parse('2.5'),
        ),
        categoryKey: publicTransport.key,
      ),
    ];

    final firstImport = await repo.importReviewedBillBatch(
      accountId: accountId,
      rows: rows,
      refunds: const [],
    );

    expect(firstImport.inserted, 4);
    expect(firstImport.skippedDuplicates, 0);
    expect(repo.visibleTransactions, hasLength(4));
    expect(
      repo.visibleTransactions
          .where((t) => t.note == '地铁' && t.amount == Decimal.parse('2.5')),
      hasLength(2),
    );

    final secondImport = await repo.importReviewedBillBatch(
      accountId: accountId,
      rows: rows,
      refunds: const [],
    );

    expect(secondImport.inserted, 0);
    expect(secondImport.skippedDuplicates, 4);
    expect(repo.visibleTransactions, hasLength(4));
    expect(
      repo.visibleTransactions
          .where((t) => t.note == '地铁' && t.amount == Decimal.parse('2.5')),
      hasLength(2),
    );
    await repo.closeForTest();
  });

  test('bill import keeps oversized refund away from original expense',
      () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;

    final result = await repo.importReviewedBillBatch(
      accountId: accountId,
      rows: [
        (
          row: ImportedBillRow(
            date: DateTime(2026, 7, 3),
            kind: TransactionKind.expense,
            category: '',
            note: 'merchant order',
            amount: Decimal.fromInt(100),
            merchant: 'merchant',
            product: 'order',
            orderNo: 'order-1',
          ),
          categoryKey: cat.key,
        ),
      ],
      refunds: [
        ImportedBillRow(
          date: DateTime(2026, 7, 3),
          kind: TransactionKind.expense,
          category: '',
          note: 'refund',
          amount: Decimal.fromInt(120),
          merchant: 'merchant',
          product: 'refund',
          orderNo: 'order-1',
          isRefund: true,
        ),
      ],
    );

    expect(result.inserted, 1);
    expect(result.refundsAttached, 0);
    expect(result.unresolvedRefunds, 1);
    final original = repo.visibleTransactions
        .singleWhere((t) => t.txKind == TransactionKind.expense);
    expect(repo.refundedAmountOf(original.id), Decimal.zero);
    expect(repo.netAmountOf(original), Decimal.fromInt(100));
    expect(
      repo.visibleTransactions.where((t) => t.txKind == TransactionKind.income),
      isEmpty,
    );
    await repo.closeForTest();
  });

  test('账单导入：同批多笔退款不双重扣减，两笔都挂上净额正确', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;

    final result = await repo.importReviewedBillBatch(
      accountId: accountId,
      rows: [
        (
          row: ImportedBillRow(
            date: DateTime(2026, 7, 3),
            kind: TransactionKind.expense,
            category: '',
            note: 'merchant order',
            amount: Decimal.fromInt(100),
            merchant: 'merchant',
            product: 'order',
            orderNo: 'order-multi-refund',
          ),
          categoryKey: cat.key,
        ),
      ],
      refunds: [
        ImportedBillRow(
          date: DateTime(2026, 7, 4),
          kind: TransactionKind.expense,
          category: '',
          note: 'refund-40',
          amount: Decimal.fromInt(40),
          merchant: 'merchant',
          orderNo: 'order-multi-refund',
          isRefund: true,
        ),
        ImportedBillRow(
          date: DateTime(2026, 7, 5),
          kind: TransactionKind.expense,
          category: '',
          note: 'refund-30',
          amount: Decimal.fromInt(30),
          merchant: 'merchant',
          orderNo: 'order-multi-refund',
          isRefund: true,
        ),
      ],
    );

    expect(result.inserted, 1);
    expect(result.refundsAttached, 2);
    expect(result.unresolvedRefunds, 0);
    final original = repo.visibleTransactions
        .singleWhere((t) => t.txKind == TransactionKind.expense);
    expect(repo.refundsOf(original.id), hasLength(2));
    expect(repo.refundedAmountOf(original.id), Decimal.fromInt(70));
    expect(repo.netAmountOf(original), Decimal.fromInt(30));
    // 第二笔退款不能因双重扣减被误判成收入兜底行。
    expect(
      repo.visibleTransactions.where((t) => t.txKind == TransactionKind.income),
      isEmpty,
    );
    await repo.closeForTest();
  });

  test('账单导入：退款单独一批也能靠订单号挂回历史原单', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;

    final first = await repo.importReviewedBillBatch(
      accountId: accountId,
      rows: [
        (
          row: ImportedBillRow(
            date: DateTime(2026, 6, 20),
            kind: TransactionKind.expense,
            category: '',
            note: '六月的订单',
            amount: Decimal.fromInt(100),
            merchant: '某店铺',
            product: '商品',
            orderNo: 'cross-batch-order-1',
          ),
          categoryKey: cat.key,
        ),
      ],
      refunds: const [],
    );
    expect(first.inserted, 1);

    // 第二批只有退款：商户留空让启发式配不上，只能靠 order_no 落库配对。
    final second = await repo.importReviewedBillBatch(
      accountId: accountId,
      rows: const [],
      refunds: [
        ImportedBillRow(
          date: DateTime(2026, 7, 10),
          kind: TransactionKind.expense,
          category: '',
          note: '退款',
          amount: Decimal.fromInt(25),
          orderNo: 'cross-batch-order-1',
          isRefund: true,
        ),
      ],
    );

    expect(second.refundsAttached, 1);
    expect(second.unresolvedRefunds, 0);
    final original = repo.visibleTransactions
        .singleWhere((t) => t.txKind == TransactionKind.expense);
    expect(repo.refundedAmountOf(original.id), Decimal.fromInt(25));
    expect(repo.netAmountOf(original), Decimal.fromInt(75));
    await repo.closeForTest();
  });

  test('账单导入：配不上原单的退款按收入入库，不再静默丢弃', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;

    final result = await repo.importReviewedBillBatch(
      accountId: accountId,
      rows: const [],
      refunds: [
        ImportedBillRow(
          date: DateTime(2026, 7, 6),
          kind: TransactionKind.expense,
          category: '',
          note: '陌生商户退款成功',
          amount: Decimal.parse('12.34'),
          merchant: '陌生商户',
          orderNo: 'no-such-order',
          isRefund: true,
        ),
      ],
    );

    expect(result.refundsAttached, 0);
    expect(result.unresolvedRefunds, 1);
    expect(result.inserted, 1);
    final income = repo.visibleTransactions.single;
    expect(income.txKind, TransactionKind.income);
    expect(income.amount, Decimal.parse('12.34'));
    expect(income.note, '陌生商户退款成功');
    // 分类落在收入侧「退款报销」。
    final catKey =
        repo.categories.firstWhere((c) => c.id == income.categoryId).key;
    expect(catKey, 'refund');
    await repo.closeForTest();
  });

  test('账单导入：商户名同分并列的退款拒绝模糊配对，走收入兜底', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;

    // 同商户、同日两笔原单：无订单号退款对它们打分完全相同（并列），
    // 强行挑第一个就是赌，赌错=退款错挂到别的订单上。
    final result = await repo.importReviewedBillBatch(
      accountId: accountId,
      rows: [
        (
          row: ImportedBillRow(
            date: DateTime(2026, 7, 3),
            kind: TransactionKind.expense,
            category: '',
            note: '京东 · 订单A',
            amount: Decimal.parse('120.00'),
            merchant: '京东',
            product: '订单A',
          ),
          categoryKey: cat.key,
        ),
        (
          row: ImportedBillRow(
            date: DateTime(2026, 7, 3),
            kind: TransactionKind.expense,
            category: '',
            note: '京东 · 订单B',
            amount: Decimal.parse('80.00'),
            merchant: '京东',
            product: '订单B',
          ),
          categoryKey: cat.key,
        ),
      ],
      refunds: [
        ImportedBillRow(
          date: DateTime(2026, 7, 3),
          kind: TransactionKind.expense,
          category: '',
          note: '退款',
          amount: Decimal.parse('50.00'),
          merchant: '京东',
          product: '退款',
          isRefund: true,
        ),
      ],
    );

    expect(result.refundsAttached, 0);
    expect(result.unresolvedRefunds, 1);
    // 两笔支出 + 一笔兜底收入。
    expect(result.inserted, 3);
    final expenses = repo.visibleTransactions
        .where((t) => t.txKind == TransactionKind.expense)
        .toList();
    expect(expenses, hasLength(2));
    for (final expense in expenses) {
      expect(repo.refundedAmountOf(expense.id), Decimal.zero);
    }
    final income = repo.visibleTransactions
        .singleWhere((t) => t.txKind == TransactionKind.income);
    expect(income.amount, Decimal.parse('50.00'));
    await repo.closeForTest();
  });

  test('肥喵导出恢复：保留原始金额和已退款关系', () async {
    final repo = await freshRepo();
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;
    final account = repo.accounts.first;

    final result = await repo.importFeimiaoExportRows([
      FeimiaoImportRow(
        uuid: '11111111111111111111111111111111',
        kind: TransactionKind.expense,
        amount: Decimal.parse('150.17'),
        refunded: Decimal.parse('9.55'),
        categoryKey: cat.key,
        categoryName: cat.nameZh,
        accountName: account.name,
        note: '美团订单',
        date: DateTime(2026, 7, 3),
        timePrecision: TransactionTimePrecision.exact,
      ),
    ]);

    expect(result.inserted, 1);
    expect(result.refundsAttached, 1);
    expect(repo.visibleTransactions, hasLength(1));
    final original = repo.visibleTransactions.single;
    expect(original.uuid, '11111111111111111111111111111111');
    expect(original.amount, Decimal.parse('150.17'));
    expect(original.timePrecision, TransactionTimePrecision.exact);
    expect(repo.refundedAmountOf(original.id), Decimal.parse('9.55'));
    expect(repo.netAmountOf(original), Decimal.parse('140.62'));
    expect(repo.refundsOf(original.id), hasLength(1));
    expect(
      repo.refundsOf(original.id).single.timePrecision,
      TransactionTimePrecision.exact,
    );
    expect(repo.refundsOf(original.id).single.settledMs, isNull);
    expect(
      repo.refundsOf(original.id).single.settlementQuality,
      SettlementQuality.unknown,
    );
    expect(
      repo.netWorthSnapshots.first.netWorth,
      repo.currentNetWorthResult().value!.netWorth,
    );
    expect(
      repo.netWorthSnapshots.first.toComputedSnapshot().lineage.causes,
      containsAll({
        NetWorthSnapshotCause.transaction,
        NetWorthSnapshotCause.refund,
      }),
    );
    expect(repo.visibleTransactions.where((t) => t.refundOf != null), isEmpty);

    final duplicate = await repo.importFeimiaoExportRows([
      FeimiaoImportRow(
        uuid: '11111111111111111111111111111111',
        kind: TransactionKind.expense,
        amount: Decimal.parse('150.17'),
        refunded: Decimal.parse('9.55'),
        categoryKey: cat.key,
        categoryName: cat.nameZh,
        accountName: account.name,
        note: '美团订单',
        date: DateTime(2026, 7, 3),
        timePrecision: TransactionTimePrecision.exact,
      ),
    ]);
    expect(duplicate.inserted, 0);
    expect(duplicate.skippedDuplicates, 1);
    expect(repo.visibleTransactions, hasLength(1));
    await repo.closeForTest();
  });

  test('肥喵导出恢复：保留跨月退款的到账日期、账户和证据质量', () async {
    final repo = await freshRepo();
    final category =
        repo.categoriesForKindRanked(TransactionKind.expense).first;
    final paymentAccount = repo.accounts.first;
    const originalUuid = '44444444444444444444444444444444';

    final result = await repo.importFeimiaoExportRows([
      FeimiaoImportRow(
        uuid: originalUuid,
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        refunded: Decimal.zero,
        categoryKey: category.key,
        accountName: paymentAccount.name,
        settlementAccountName: paymentAccount.name,
        settledAt: DateTime(2026, 6, 3, 12),
        settlementQuality: SettlementQuality.exact,
        settlementAccountQuality: SettlementQuality.exact,
        eventType: TransactionEventType.expense,
        note: '六月订单',
        date: DateTime(2026, 6, 3, 12),
      ),
      FeimiaoImportRow(
        uuid: '55555555555555555555555555555555',
        refundOfUuid: originalUuid,
        role: '退款',
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(30),
        refunded: Decimal.zero,
        categoryKey: category.key,
        accountName: paymentAccount.name,
        settlementAccountName: '工资卡',
        settledAt: DateTime(2026, 7, 5, 9, 30),
        settlementQuality: SettlementQuality.userConfirmed,
        settlementAccountQuality: SettlementQuality.userConfirmed,
        eventType: TransactionEventType.refund,
        note: '商家退款',
        date: DateTime(2026, 6, 3, 12),
      ),
    ]);

    expect(result.inserted, 1);
    expect(result.refundsAttached, 1);
    final original = repo.visibleTransactions.single;
    final refund = repo.refundsOf(original.id).single;
    expect(refund.date, DateTime(2026, 6, 3, 12));
    expect(refund.settledAt, DateTime(2026, 7, 5, 9, 30));
    expect(refund.settlementQuality, SettlementQuality.userConfirmed);
    expect(refund.settlementAccountQuality, SettlementQuality.userConfirmed);
    expect(refund.eventType, TransactionEventType.refund);
    final salaryAccount =
        repo.accounts.singleWhere((account) => account.name == '工资卡');
    expect(refund.settlementAccountId, salaryAccount.id);
    expect(repo.accountBalanceOf(salaryAccount), Decimal.fromInt(30));
    await repo.closeForTest();
  });

  test('旧 CSV 报销保持未知账户，并可由用户补确认到账信息', () async {
    final repo = await freshRepo();
    final category =
        repo.categoriesForKindRanked(TransactionKind.expense).first;
    final paymentAccount = repo.accounts.first;
    const originalUuid = '66666666666666666666666666666666';
    final salaryAccountId = await repo.addAccount(
      name: '报销收款卡',
      type: AccountType.debit,
    );

    await repo.importFeimiaoExportRows([
      FeimiaoImportRow(
        uuid: originalUuid,
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        refunded: Decimal.zero,
        categoryKey: category.key,
        accountName: paymentAccount.name,
        note: '差旅',
        date: DateTime(2026, 6, 2),
      ),
      FeimiaoImportRow(
        uuid: '77777777777777777777777777777777',
        refundOfUuid: originalUuid,
        role: '退款',
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(30),
        refunded: Decimal.zero,
        categoryKey: category.key,
        accountName: paymentAccount.name,
        note: '报销到账',
        date: DateTime(2026, 6, 2),
      ),
    ]);

    final original = repo.visibleTransactions.single;
    var reimbursement = repo.refundsOf(original.id).single;
    expect(reimbursement.eventType, TransactionEventType.reimbursement);
    expect(reimbursement.settledMs, isNull);
    expect(reimbursement.settlementQuality, SettlementQuality.unknown);
    expect(reimbursement.settlementAccountId, isNull);
    expect(
      reimbursement.settlementAccountQuality,
      SettlementQuality.unknown,
    );
    expect(repo.accountBalanceOf(paymentAccount), Decimal.fromInt(-100));

    await repo.confirmTransactionSettlement(
      reimbursement.id,
      settledAt: DateTime(2026, 7, 8),
      settlementAccountId: salaryAccountId,
    );
    reimbursement = repo.refundsOf(original.id).single;
    expect(reimbursement.settledAt, DateTime(2026, 7, 8));
    expect(
      reimbursement.settlementQuality,
      SettlementQuality.userConfirmed,
    );
    expect(reimbursement.settlementAccountId, salaryAccountId);
    expect(
      reimbursement.settlementAccountQuality,
      SettlementQuality.userConfirmed,
    );
    final salaryAccount =
        repo.accounts.singleWhere((account) => account.id == salaryAccountId);
    expect(repo.accountBalanceOf(salaryAccount), Decimal.fromInt(30));
    expect(repo.accountBalanceOf(paymentAccount), Decimal.fromInt(-100));
    await repo.closeForTest();
  });

  test('普通编辑保留旧账单的结算证据质量', () async {
    final repo = await freshRepo();
    final category =
        repo.categoriesForKindRanked(TransactionKind.expense).first;
    final account = repo.accounts.first;
    await repo.importFeimiaoExportRows([
      FeimiaoImportRow(
        uuid: '88888888888888888888888888888888',
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(50),
        refunded: Decimal.zero,
        categoryKey: category.key,
        accountName: account.name,
        note: '旧账单',
        date: DateTime(2026, 5, 1),
      ),
    ]);
    var transaction = repo.visibleTransactions.single;
    expect(transaction.settlementQuality, SettlementQuality.legacyAssumed);
    expect(
      transaction.settlementAccountQuality,
      SettlementQuality.legacyAssumed,
    );

    await repo.updateTransaction(
      id: transaction.id,
      kind: transaction.txKind,
      amount: transaction.amount,
      categoryId: transaction.categoryId,
      accountId: transaction.accountId!,
      note: '只改备注',
      date: DateTime(2026, 5, 2),
    );
    transaction = repo.visibleTransactions.single;
    expect(transaction.note, '只改备注');
    expect(transaction.date, DateTime(2026, 5, 2));
    expect(transaction.settledAt, DateTime(2026, 5, 1));
    expect(transaction.settlementQuality, SettlementQuality.legacyAssumed);
    expect(
      transaction.settlementAccountQuality,
      SettlementQuality.legacyAssumed,
    );
    await repo.closeForTest();
  });

  test('历史账单所属账户归档后仍可只改备注和日期', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(name: '已归档历史账户');
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      accountId: accountId,
      note: '归档前备注',
      date: DateTime(2026, 4, 1),
    );
    await repo.archiveAccount(accountId);

    await repo.updateTransaction(
      id: transactionId,
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(20),
      accountId: accountId,
      note: '归档后修正备注',
      date: DateTime(2026, 4, 2),
    );

    final edited = repo.visibleTransactions.single;
    expect(edited.accountId, accountId);
    expect(edited.settlementAccountId, accountId);
    expect(edited.note, '归档后修正备注');
    expect(edited.date, DateTime(2026, 4, 2));
    await repo.closeForTest();
  });

  test('归档账户上的普通历史账单不能新改成转账', () async {
    final repo = await freshRepo();
    final sourceId = await repo.addAccount(name: '已归档转出账户');
    final targetId = await repo.addAccount(name: '有效转入账户');
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(30),
      accountId: sourceId,
      note: '原本是普通支出',
      date: DateTime(2026, 4, 1),
    );
    await repo.archiveAccount(sourceId);

    await expectLater(
      repo.updateTransaction(
        id: transactionId,
        kind: TransactionKind.transfer,
        amount: Decimal.fromInt(30),
        accountId: sourceId,
        toAccountId: targetId,
        note: '不应改成转账',
        date: DateTime(2026, 4, 1),
      ),
      throwsArgumentError,
    );
    final unchanged = repo.transactionById(transactionId)!;
    expect(unchanged.txKind, TransactionKind.expense);
    expect(unchanged.toAccountId, isNull);
    await repo.closeForTest();
  });

  test('普通账转为转账会在事务内重新验证源账户而非信任旧缓存', () async {
    final repo = await freshRepo();
    final source = repo.accounts.first;
    final targetId = await repo.addAccount(name: '有效转入账户');
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(30),
      accountId: source.id,
      note: '缓存仍显示账户有效',
      date: DateTime(2026, 4, 1),
    );

    final directDb = await databaseFactory.openDatabase(
      p.join(tmp.path, 'qingji.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await directDb.update(
      'accounts',
      {
        'status': AccountStatus.archived.storageKey,
        'archived_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [source.id],
    );
    await directDb.close();
    expect(
      repo.accounts
          .singleWhere((account) => account.id == source.id)
          .isArchived,
      isFalse,
    );

    await expectLater(
      repo.updateTransaction(
        id: transactionId,
        kind: TransactionKind.transfer,
        amount: Decimal.fromInt(30),
        accountId: source.id,
        toAccountId: targetId,
        note: '不应绕过事务内校验',
        date: DateTime(2026, 4, 1),
      ),
      throwsArgumentError,
    );
    final unchanged = repo.transactionById(transactionId)!;
    expect(unchanged.txKind, TransactionKind.expense);
    expect(unchanged.toAccountId, isNull);
    await repo.closeForTest();
  });

  test('编辑账单更换账户会同步真实结算账户和余额归属', () async {
    final repo = await freshRepo();
    final source = repo.accounts.first;
    final targetId = await repo.addAccount(name: '编辑后的扣款账户');
    final target =
        repo.accounts.singleWhere((account) => account.id == targetId);
    final category =
        repo.categoriesForKindRanked(TransactionKind.expense).first;
    await repo.importFeimiaoExportRows([
      FeimiaoImportRow(
        uuid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1',
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(50),
        refunded: Decimal.zero,
        categoryKey: category.key,
        accountName: source.name,
        note: '待更换账户的旧账单',
        date: DateTime(2026, 5, 1),
      ),
    ]);
    final original = repo.visibleTransactions.single;
    expect(original.settlementAccountQuality, SettlementQuality.legacyAssumed);
    expect(repo.accountBalanceOf(source), Decimal.fromInt(-50));
    expect(repo.accountBalanceOf(target), Decimal.zero);

    await repo.updateTransaction(
      id: original.id,
      kind: TransactionKind.expense,
      amount: original.amount,
      categoryId: original.categoryId,
      accountId: targetId,
      note: original.note,
      date: original.date,
    );

    final edited = repo.visibleTransactions.single;
    expect(edited.accountId, targetId);
    expect(edited.settlementAccountId, targetId);
    expect(
      edited.settlementAccountQuality,
      SettlementQuality.userConfirmed,
    );
    expect(repo.accountBalanceOf(source), Decimal.zero);
    expect(repo.accountBalanceOf(target), Decimal.fromInt(-50));
    await repo.closeForTest();
  });

  test('普通账单改为转账会确认转出账户并正确投影转入账户', () async {
    final repo = await freshRepo();
    final source = repo.accounts.first;
    final targetId = await repo.addAccount(name: '转账目标账户');
    final target =
        repo.accounts.singleWhere((account) => account.id == targetId);
    await repo.importFeimiaoExportRows([
      FeimiaoImportRow(
        uuid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2',
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(75),
        refunded: Decimal.zero,
        accountName: source.name,
        note: '改为内部转账',
        date: DateTime(2026, 5, 2),
      ),
    ]);
    final original = repo.visibleTransactions.single;
    expect(original.settlementAccountQuality, SettlementQuality.legacyAssumed);

    await repo.updateTransaction(
      id: original.id,
      kind: TransactionKind.transfer,
      amount: original.amount,
      accountId: source.id,
      toAccountId: targetId,
      note: original.note,
      date: original.date,
      excluded: true,
    );

    final edited = repo.visibleTransactions.single;
    expect(edited.txKind, TransactionKind.transfer);
    expect(edited.eventType, TransactionEventType.transfer);
    expect(edited.settlementAccountId, source.id);
    expect(
      edited.settlementAccountQuality,
      SettlementQuality.userConfirmed,
    );
    expect(edited.toAccountId, targetId);
    expect(repo.accountBalanceOf(source), Decimal.fromInt(-75));
    expect(repo.accountBalanceOf(target), Decimal.fromInt(75));
    await repo.closeForTest();
  });

  test('肥喵 CSV 恢复保留转入账户、标签和可报销状态', () async {
    final repo = await freshRepo();

    final result = await repo.importFeimiaoExportRows([
      FeimiaoImportRow(
        uuid: '33333333333333333333333333333333',
        kind: TransactionKind.transfer,
        amount: Decimal.parse('520.30'),
        refunded: Decimal.zero,
        accountName: '工资卡',
        toAccountName: '旅行基金',
        tagNames: const ['旅行', '年度计划'],
        reimbursable: true,
        note: '转入旅行预算',
        date: DateTime(2026, 7, 4),
      ),
    ]);

    expect(result.inserted, 1);
    final transaction = repo.visibleTransactions.single;
    expect(transaction.accountName, '工资卡');
    expect(transaction.toAccountName, '旅行基金');
    expect(transaction.reimbursable, isTrue);
    expect(
      transaction.tagIds.map(repo.tagName).whereType<String>().toSet(),
      {'旅行', '年度计划'},
    );
    expect(repo.accounts.map((account) => account.name), contains('工资卡'));
    expect(repo.accounts.map((account) => account.name), contains('旅行基金'));
    await repo.closeForTest();
  });

  test('feimiao csv restore skips refund amount beyond original amount',
      () async {
    final repo = await freshRepo();
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;
    final account = repo.accounts.first;

    final result = await repo.importFeimiaoExportRows([
      FeimiaoImportRow(
        uuid: '22222222222222222222222222222222',
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        refunded: Decimal.fromInt(120),
        categoryKey: cat.key,
        categoryName: cat.nameZh,
        accountName: account.name,
        note: 'oversized refund',
        date: DateTime(2026, 7, 3),
      ),
    ]);

    expect(result.inserted, 1);
    expect(result.refundsAttached, 0);
    expect(result.skippedDuplicates, 1);
    final original = repo.visibleTransactions.single;
    expect(repo.refundedAmountOf(original.id), Decimal.zero);
    expect(repo.netAmountOf(original), Decimal.fromInt(100));
    await repo.closeForTest();
  });

  test('报告文档：独立持久化，可按类型读取，重启后仍保留', () async {
    final repo = await freshRepo();
    final reportId = await repo.addReport(
      type: 'monthly',
      title: '2026年6月消费月报',
      summary: '6月支出结构需要关注餐饮和固定支出。',
      markdown: '# 2026年6月消费月报\n\n## 摘要\n6月支出结构需要关注餐饮和固定支出。',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
    );

    final report = await repo.getReport(reportId);
    expect(report, isNotNull);
    expect(report!.type, 'monthly');
    expect(report.title, '2026年6月消费月报');
    expect(report.markdown, contains('## 摘要'));
    expect(await repo.loadReports(type: 'monthly'), hasLength(1));
    expect(await repo.loadReports(type: 'weekly'), isEmpty);
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    expect(reopened.reports, hasLength(1));
    expect(reopened.reports.single.title, '2026年6月消费月报');
    await reopened.closeForTest();
  });

  test('报告文档：删除报告会清理喵助手里的报告卡片引用', () async {
    final repo = await freshRepo();
    final reportId = await repo.addReport(
      type: 'monthly',
      title: '2026年6月消费月报',
      summary: '6月支出结构需要关注餐饮和固定支出。',
      markdown: '# 2026年6月消费月报',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
    );
    await repo.addChatMessage(
      role: 'report',
      text: '{"reportId":$reportId,"title":"2026年6月消费月报"}',
    );
    await repo.addChatMessage(role: 'assistant', text: '普通回复不能被误删');

    await repo.deleteReport(reportId);

    expect(await repo.getReport(reportId), isNull);
    final messages = await repo.loadChatMessages();
    expect(messages.where((m) => m['role'] == 'report'), isEmpty);
    expect(messages.where((m) => m['text'] == '普通回复不能被误删'), hasLength(1));
    await repo.closeForTest();
  });

  test('报告任务跨重启保留进度，完成后不再进入恢复队列', () async {
    final repo = await freshRepo();
    final job = await repo.createReportJob(
      question: '生成 6 月月报',
      type: 'monthly',
      title: '2026年6月消费月报',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
      bookId: repo.currentBook!.id,
    );
    await repo.updateReportJob(job.id, status: 'running', stage: 'generate');
    await repo.closeForTest();

    final reopened = AppRepository();
    await reopened.init();
    final pending = await reopened.pendingReportJobs();
    expect(pending, hasLength(1));
    expect(pending.single.id, job.id);
    expect(pending.single.stage, 'generate');
    await reopened.updateReportJob(
      job.id,
      status: 'completed',
      stage: 'save',
      reportId: 123,
    );
    expect(await reopened.pendingReportJobs(), isEmpty);
    await reopened.closeForTest();
  });

  test('报告任务 ID 相同但 UUID 不匹配时拒绝更新和完成', () async {
    final repo = await freshRepo();
    final job = await repo.createReportJob(
      question: '生成安全报告',
      type: 'monthly',
      title: 'UUID 防串写报告',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
    );
    const wrongUuid = 'ffffffffffffffffffffffffffffffff';

    await expectLater(
      repo.updateReportJob(
        job.id,
        expectedUuid: wrongUuid,
        status: 'running',
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repo.completeReportJob(
        jobId: job.id,
        expectedJobUuid: wrongUuid,
        summary: '不应保存',
        markdown: '# 不应保存',
      ),
      throwsA(isA<StateError>()),
    );
    expect((await repo.reportJobById(job.id))?.status, 'queued');
    expect(repo.reports, isEmpty);
    expect(
      (await repo.loadChatMessages()).where((row) => row['role'] == 'report'),
      isEmpty,
    );

    await repo.updateReportJob(
      job.id,
      expectedUuid: job.uuid,
      status: 'running',
    );
    final report = await repo.completeReportJob(
      jobId: job.id,
      expectedJobUuid: job.uuid,
      summary: '正确 UUID 已保存',
      markdown: '# 正确 UUID 已保存',
    );
    expect(report.summary, '正确 UUID 已保存');
    expect((await repo.reportJobById(job.id))?.status, 'completed');
    await repo.closeForTest();
  });

  test('后台报告完成事务可安全重试且只生成一份报告和聊天卡', () async {
    final repo = await freshRepo();
    final job = await repo.createReportJob(
      question: '生成 6 月月报',
      type: 'monthly',
      title: '2026年6月消费月报',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
      bookId: repo.currentBook!.id,
    );

    final first = await repo.completeReportJob(
      jobId: job.id,
      summary: '后台生成摘要',
      markdown: '# 2026年6月消费月报\n\n## 摘要\n后台生成摘要',
    );
    final retried = await repo.completeReportJob(
      jobId: job.id,
      summary: '重复执行不应覆盖',
      markdown: '# 不应生成第二份',
    );

    expect(retried.id, first.id);
    expect(repo.reports, hasLength(1));
    expect(repo.reports.single.summary, '后台生成摘要');
    final reportMessages = (await repo.loadChatMessages())
        .where((row) => row['role'] == 'report')
        .toList();
    expect(reportMessages, hasLength(1));
    expect(reportMessages.single['text'], contains('后台生成摘要'));
    final completed = await repo.reportJobById(job.id);
    expect(completed?.status, 'completed');
    expect(completed?.reportId, first.id);
    await repo.closeForTest();
  });

  test('报告重新生成更新持久聊天摘要，并始终可读取原账本数据', () async {
    final repo = await freshRepo();
    final originalBookId = await repo.addBook(
      name: '原报告账本',
      includeInTotal: false,
    );
    final otherBookId = await repo.addBook(
      name: '当前账本',
      includeInTotal: false,
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(88),
      accountId: repo.accounts.first.id,
      bookId: originalBookId,
      note: '只属于原报告账本',
      date: DateTime(2026, 6, 8),
    );
    await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(66),
      accountId: repo.accounts.first.id,
      bookId: otherBookId,
      note: '另一个账本',
      date: DateTime(2026, 6, 9),
    );
    final reportId = await repo.addReport(
      type: 'monthly',
      title: '原账本月报',
      summary: '旧摘要',
      markdown: '# 旧报告',
      periodStart: DateTime(2026, 6, 1),
      periodEnd: DateTime(2026, 6, 30),
      bookId: originalBookId,
    );
    await repo.addChatMessage(
      role: 'report',
      text: '{"reportId":$reportId,"summary":"旧摘要"}',
      question: '生成月报',
    );
    await repo.switchBook(otherBookId);

    final originalRecords = repo.recordsForBookView(originalBookId);
    expect(originalRecords, hasLength(1));
    expect(originalRecords.single.note, '只属于原报告账本');
    expect(repo.recordsForBookView(otherBookId).single.note, '另一个账本');

    await repo.updateReportContent(
      reportId,
      summary: '新摘要',
      markdown: '# 新报告',
    );
    final messages = await repo.loadChatMessages();
    final reportMessage =
        messages.singleWhere((row) => row['role'] == 'report');
    expect(reportMessage['text'], contains('新摘要'));
    expect(reportMessage['text'], isNot(contains('旧摘要')));
    await repo.closeForTest();
  });

  test('资产 P1：历史补录只增加实物资产，不生成普通收支', () async {
    final repo = await freshRepo();
    final beforeTx = repo.transactions.length;

    final id = await repo.addPhysicalAsset(
      name: '旧电脑',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(3000),
      purchasePrice: Decimal.fromInt(6000),
      sourceType: PhysicalAssetSourceType.historicalExisting,
      note: '开账前已有',
    );

    expect(repo.transactions.length, beforeTx);
    final asset = repo.physicalAssets.singleWhere((a) => a.id == id);
    expect(asset.currentValue, Decimal.fromInt(3000));
    expect(asset.countsInNetWorth, isTrue);
    expect(repo.physicalAssetNetWorthTotal, Decimal.fromInt(3000));
    expect(repo.assetEvents.where((e) => e.assetId == id), hasLength(1));
    expect(
        repo.assetEvents.single.eventType, AssetEventType.openingAssetImport);
    expect(repo.assetValuations.where((v) => v.assetId == id), hasLength(1));
    await repo.closeForTest();
  });

  test('资产 P1：新购买同时记账会生成支出和资产关联', () async {
    final repo = await freshRepo();
    final account = repo.accounts.first;
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;
    final purchaseDate = DateTime(2024, 3, 4, 15, 30);

    final assetId = await repo.addPhysicalAsset(
      name: '新手机',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(5000),
      purchasePrice: Decimal.fromInt(5000),
      sourceType: PhysicalAssetSourceType.newPurchaseWithAccount,
      paymentAccountId: account.id,
      purchaseCategoryId: cat.id,
      purchaseDate: purchaseDate,
      occurredAt: DateTime(2026, 7, 13),
      note: '买手机',
    );

    expect(repo.visibleTransactions, hasLength(1));
    final tx = repo.visibleTransactions.single;
    expect(tx.txKind, TransactionKind.expense);
    expect(tx.amount, Decimal.fromInt(5000));
    expect(tx.excluded, isFalse);
    expect(tx.date, purchaseDate);
    final asset = repo.physicalAssets.singleWhere((item) => item.id == assetId);
    expect(asset.purchaseDate, purchaseDate);
    expect(repo.eventsForAsset(assetId).single.occurredAt, purchaseDate);
    expect(repo.valuationsForAsset(assetId).single.valuedAt, purchaseDate);
    expect(repo.assetTransactionLinks, hasLength(1));
    expect(repo.assetTransactionLinks.single.assetId, assetId);
    expect(repo.assetTransactionLinks.single.transactionId, tx.id);
    expect(
      repo.assetTransactionLinks.single.linkType,
      AssetTransactionLinkType.purchaseTransaction,
    );
    expect(repo.physicalAssetNetWorthTotal, Decimal.fromInt(5000));
    await repo.closeForTest();
  });

  test('资产 P1：从已有账单加入资产不重复生成流水', () async {
    final repo = await freshRepo();
    final account = repo.accounts.first;
    final cat = repo.categoriesForKindRanked(TransactionKind.expense).first;
    final txId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(8000),
      categoryId: cat.id,
      accountId: account.id,
      note: '电脑',
      date: DateTime(2026, 7, 1),
    );
    final beforeTx = repo.transactions.length;

    final assetId = await repo.addPhysicalAsset(
      name: '电脑',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(6500),
      sourceType: PhysicalAssetSourceType.fromTransaction,
      sourceTransactionId: txId,
    );

    expect(repo.transactions.length, beforeTx);
    expect(repo.assetTransactionLinks, hasLength(1));
    expect(repo.assetTransactionLinks.single.assetId, assetId);
    expect(repo.assetTransactionLinks.single.transactionId, txId);
    expect(
      repo.assetTransactionLinks.single.linkType,
      AssetTransactionLinkType.sourceTransaction,
    );
    expect(repo.assetEvents.single.eventType,
        AssetEventType.createdFromTransaction);
    await repo.closeForTest();
  });

  test('资产 P1：出售资产只影响账户流水，不进入普通收入统计', () async {
    final repo = await freshRepo();
    final account = repo.accounts.first;
    final assetId = await repo.addPhysicalAsset(
      name: '旧相机',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(2000),
      sourceType: PhysicalAssetSourceType.historicalExisting,
    );

    await repo.sellPhysicalAsset(
      id: assetId,
      saleAmount: Decimal.fromInt(1200),
      saleFee: Decimal.fromInt(100),
      accountId: account.id,
      note: '卖掉旧相机',
    );

    final asset = repo.physicalAssets.singleWhere((a) => a.id == assetId);
    expect(asset.status, PhysicalAssetStatus.sold);
    expect(asset.currentValue, Decimal.zero);
    expect(asset.includeInNetWorth, isFalse);
    final saleTx = repo.visibleTransactions.singleWhere(
      (t) => t.txKind == TransactionKind.income,
    );
    expect(saleTx.amount, Decimal.fromInt(1100));
    expect(saleTx.excluded, isTrue);
    expect(saleTx.eventType, TransactionEventType.assetSale);
    expect(saleTx.settlementAccountId, account.id);
    expect(repo.accountBalanceOf(account), Decimal.fromInt(1100));
    expect(repo.allRecords.where((r) => r.kind == TransactionKind.income),
        isEmpty);
    expect(
      repo.assetTransactionLinks
          .singleWhere(
            (link) =>
                link.linkType == AssetTransactionLinkType.saleAccountMovement,
          )
          .transactionId,
      saleTx.id,
    );

    await repo.undoPhysicalAssetSale(assetId);
    final restored = repo.physicalAssets.singleWhere((a) => a.id == assetId);
    expect(restored.status, PhysicalAssetStatus.active);
    expect(restored.currentValue, Decimal.fromInt(2000));
    expect(restored.includeInNetWorth, isTrue);
    expect(repo.transactions.where((t) => t.id == saleTx.id), isEmpty);
    expect(repo.assetTransactionLinks, isEmpty);
    expect(repo.accountBalanceOf(account), Decimal.zero);
    expect(repo.eventsForAsset(assetId).first.eventType,
        AssetEventType.assetSaleUndone);
    await repo.closeForTest();
  });

  test('资产关联流水不能绕过资产生命周期直接编辑或删除', () async {
    final repo = await freshRepo();
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(3000),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 1),
      note: '相机订单',
    );
    await repo.addPhysicalAsset(
      name: '相机',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(2800),
      purchasePrice: Decimal.fromInt(3000),
      sourceType: PhysicalAssetSourceType.fromTransaction,
      sourceTransactionId: transactionId,
    );

    await expectLater(
      repo.updateTransaction(
        id: transactionId,
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(2500),
        accountId: repo.accounts.first.id,
        date: DateTime(2026, 7, 1),
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repo.deleteTransaction(transactionId),
      throwsA(isA<StateError>()),
    );
    expect(repo.transactions.where((t) => t.id == transactionId), hasLength(1));
    expect(repo.assetTransactionLinks, hasLength(1));

    await repo.unlinkPhysicalAssetTransaction(
      assetId: repo.physicalAssets.single.id,
      transactionId: transactionId,
    );
    await repo.updateTransaction(
      id: transactionId,
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(2500),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 1),
    );
    expect(repo.assetTransactionLinks, isEmpty);
    expect(repo.transactions.single.amount, Decimal.fromInt(2500));
    await repo.closeForTest();
  });

  test('资产普通编辑不能绕过生命周期，且不会清空未展示日期', () async {
    final repo = await freshRepo();
    final purchaseDate = DateTime(2025, 1, 2);
    final warrantyUntil = DateTime(2028, 1, 2);
    final assetId = await repo.addPhysicalAsset(
      name: '电脑',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(5000),
      purchasePrice: Decimal.fromInt(6000),
      purchaseDate: purchaseDate,
      warrantyUntil: warrantyUntil,
    );
    final asset = repo.physicalAssets.single;

    await expectLater(
      repo.updatePhysicalAsset(
        id: assetId,
        name: asset.name,
        assetType: asset.assetType,
        purchasePrice: asset.purchasePrice,
        currentValue: asset.currentValue,
        currencyCode: asset.currencyCode,
        status: PhysicalAssetStatus.sold,
        includeInNetWorth: true,
      ),
      throwsA(isA<StateError>()),
    );
    await repo.updatePhysicalAsset(
      id: assetId,
      name: '电脑 Pro',
      assetType: asset.assetType,
      purchasePrice: asset.purchasePrice,
      currentValue: Decimal.fromInt(4800),
      currencyCode: asset.currencyCode,
      status: asset.status,
      includeInNetWorth: true,
    );
    final updated = repo.physicalAssets.single;
    expect(updated.purchaseDate, purchaseDate);
    expect(updated.warrantyUntil, warrantyUntil);
    expect(repo.valuationsForAsset(assetId).first.value, Decimal.fromInt(4800));
    await expectLater(
      repo.updatePhysicalAssetValue(assetId, Decimal.fromInt(-1)),
      throwsArgumentError,
    );
    await repo.closeForTest();
  });

  test('资产 A0：物品归档和恢复只改变 visibility，净资产逐分不变', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '收藏手办',
      assetType: AssetType.collectibles,
      currentValue: Decimal.fromInt(900),
      sourceType: PhysicalAssetSourceType.historicalExisting,
    );
    final before = repo.physicalAssetDetailById(assetId)!;
    final beforeBreakdown = repo.currentNetWorthBreakdown();

    await repo.archivePhysicalAsset(assetId);
    var asset = repo.physicalAssetDetailById(assetId)!;
    expect(asset.visibilityStatus, AssetVisibilityStatus.archived);
    expect(asset.currentValue, Decimal.fromInt(900));
    expect(asset.includeInNetWorth, before.includeInNetWorth);
    expect(asset.economicStatus, before.economicStatus);
    expect(asset.usageStatus, before.usageStatus);
    expect(asset.countsInNetWorth, isTrue);
    expect(repo.physicalAssetNetWorthTotal, Decimal.fromInt(900));
    expect(repo.currentNetWorthBreakdown().netWorth, beforeBreakdown.netWorth);
    expect(repo.globalActivePhysicalAssets, isNot(contains(asset)));
    expect(repo.globalArchivedPhysicalAssets.map((item) => item.id),
        contains(assetId));

    await repo.restorePhysicalAsset(assetId);
    asset = repo.physicalAssetDetailById(assetId)!;
    expect(asset.visibilityStatus, AssetVisibilityStatus.active);
    expect(asset.currentValue, Decimal.fromInt(900));
    expect(asset.includeInNetWorth, before.includeInNetWorth);
    expect(asset.economicStatus, before.economicStatus);
    expect(asset.usageStatus, before.usageStatus);
    expect(asset.countsInNetWorth, isTrue);
    expect(repo.physicalAssetNetWorthTotal, Decimal.fromInt(900));
    expect(repo.currentNetWorthBreakdown().netWorth, beforeBreakdown.netWorth);
    expect(repo.eventsForAsset(assetId).map((e) => e.eventType),
        contains(AssetEventType.assetUnarchived));
    await repo.closeForTest();
  });

  test('资产 A0：未结权益归档和恢复保留 include、经济状态与净资产', () async {
    final repo = await freshRepo();
    final assetId = await repo.addReceivableAsset(
      name: '未退租房押金',
      type: ReceivableAssetType.rentalDeposit,
      originalAmount: Decimal.fromInt(1500),
      includeInNetWorth: true,
    );
    final before = repo.receivableDetailById(assetId)!;
    final beforeBreakdown = repo.currentNetWorthBreakdown();

    await repo.archiveReceivableAsset(assetId);
    var asset = repo.receivableDetailById(assetId)!;
    expect(asset.visibilityStatus, AssetVisibilityStatus.archived);
    expect(asset.remainingAmount, before.remainingAmount);
    expect(asset.includeInNetWorth, isTrue);
    expect(asset.economicStatus, before.economicStatus);
    expect(asset.countsInNetWorth, isTrue);
    expect(
      repo.currentNetWorthBreakdown().netWorth,
      beforeBreakdown.netWorth,
    );
    expect(repo.globalArchivedReceivables.map((item) => item.id),
        contains(assetId));

    await repo.restoreReceivableAsset(assetId);
    asset = repo.receivableDetailById(assetId)!;
    expect(asset.visibilityStatus, AssetVisibilityStatus.active);
    expect(asset.remainingAmount, before.remainingAmount);
    expect(asset.includeInNetWorth, isTrue);
    expect(asset.economicStatus, before.economicStatus);
    expect(
      repo.currentNetWorthBreakdown().netWorth,
      beforeBreakdown.netWorth,
    );
    await repo.closeForTest();
  });

  test('资产 A0：终止物品归档和恢复不会复活经济价值', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '遗失相机',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(3200),
      purchasePrice: Decimal.fromInt(5000),
      includeInNetWorth: true,
    );
    final lostAt = DateTime(2026, 7, 8, 10);
    await repo.setPhysicalAssetStatus(
      id: assetId,
      status: PhysicalAssetStatus.lost,
      occurredAt: lostAt,
      note: '遗失',
    );
    final terminal = repo.physicalAssetDetailById(assetId)!;
    expect(terminal.economicStatus, PhysicalAssetEconomicStatus.lost);
    expect(terminal.currentValue, Decimal.zero);
    expect(terminal.includeInNetWorth, isFalse);
    expect(terminal.endedAt, lostAt);

    await repo.archivePhysicalAsset(assetId);
    var archived = repo.physicalAssetDetailById(assetId)!;
    expect(archived.visibilityStatus, AssetVisibilityStatus.archived);
    expect(archived.economicStatus, PhysicalAssetEconomicStatus.lost);
    expect(archived.currentValue, Decimal.zero);
    expect(archived.includeInNetWorth, isFalse);
    expect(archived.endedAt, lostAt);

    await repo.restorePhysicalAsset(assetId);
    archived = repo.physicalAssetDetailById(assetId)!;
    expect(archived.visibilityStatus, AssetVisibilityStatus.active);
    expect(archived.economicStatus, PhysicalAssetEconomicStatus.lost);
    expect(archived.currentValue, Decimal.zero);
    expect(archived.includeInNetWorth, isFalse);
    expect(archived.countsInNetWorth, isFalse);
    expect(repo.physicalAssetNetWorthTotal, Decimal.zero);
    await repo.closeForTest();
  });

  test('资产 P1：导出导入按唯一 ID 恢复，同名同金额资产不会合并', () async {
    final repo = await freshRepo();
    await repo.addPhysicalAsset(
      name: '金条',
      assetType: AssetType.valuables,
      currentValue: Decimal.fromInt(1000),
      sourceType: PhysicalAssetSourceType.historicalExisting,
    );
    await repo.addPhysicalAsset(
      name: '金条',
      assetType: AssetType.valuables,
      currentValue: Decimal.fromInt(1000),
      sourceType: PhysicalAssetSourceType.historicalExisting,
    );
    final json = await repo.exportAssetTablesJson();
    await repo.closeForTest();
    File(p.join(tmp.path, 'qingji.db')).deleteSync();

    final restored = await freshRepo();
    final result = await restored.importAssetTablesJson(json);
    expect(result.assets, 2);
    expect(
      restored.physicalAssets.where(
          (a) => a.name == '金条' && a.currentValue == Decimal.fromInt(1000)),
      hasLength(2),
    );
    expect(restored.assetEvents, hasLength(2));
    expect(restored.assetValuations, hasLength(2));
    await restored.closeForTest();
  });

  test('资产 P2：权益资产按剩余金额计入净资产', () async {
    final repo = await freshRepo();
    final assetId = await repo.addReceivableAsset(
      name: '租房押金',
      type: ReceivableAssetType.rentalDeposit,
      originalAmount: Decimal.fromInt(2000),
      counterparty: '房东',
      dueDate: DateTime(2026, 12, 31),
    );

    final asset = repo.receivableAssets.singleWhere((a) => a.id == assetId);
    expect(asset.remainingAmount, Decimal.fromInt(2000));
    expect(asset.countsInNetWorth, isTrue);
    expect(repo.receivableAssetNetWorthTotal, Decimal.fromInt(2000));
    final breakdown = repo.currentNetWorthBreakdown();
    expect(breakdown.receivableAssets, Decimal.fromInt(2000));
    expect(breakdown.netWorth, Decimal.fromInt(2000));
    expect(repo.eventsForReceivableAsset(assetId).single.eventType,
        AssetEventType.receivableCreated);
    await repo.closeForTest();
  });

  test('资产 P2：部分收回只转换资产形态，不进入普通收入', () async {
    final repo = await freshRepo();
    final account = repo.accounts.first;
    final assetId = await repo.addReceivableAsset(
      name: '租房押金',
      type: ReceivableAssetType.rentalDeposit,
      originalAmount: Decimal.fromInt(2000),
    );
    final before = repo.currentNetWorthBreakdown();
    expect(before.netWorth, Decimal.fromInt(2000));

    await repo.recoverReceivableAsset(
      id: assetId,
      amount: Decimal.fromInt(500),
      targetAccountId: account.id,
      note: '退回一部分押金',
      recoveredAt: DateTime(2026, 7, 7),
    );

    final asset = repo.receivableAssets.singleWhere((a) => a.id == assetId);
    expect(asset.status, ReceivableAssetStatus.partialRecovered);
    expect(asset.remainingAmount, Decimal.fromInt(1500));
    expect(repo.receivableRecoveries, hasLength(1));
    expect(repo.receivableRecoveries.single.amount, Decimal.fromInt(500));
    final movement = repo.visibleTransactions.singleWhere(
      (t) => t.txKind == TransactionKind.income,
    );
    expect(movement.amount, Decimal.fromInt(500));
    expect(movement.excluded, isTrue);
    expect(movement.eventType, TransactionEventType.receivableRecovery);
    expect(movement.settlementAccountId, account.id);
    expect(repo.accountBalanceOf(account), Decimal.fromInt(500));
    expect(repo.allRecords.where((r) => r.kind == TransactionKind.income),
        isEmpty);
    final after = repo.currentNetWorthBreakdown();
    expect(after.cashAssets, Decimal.fromInt(500));
    expect(after.receivableAssets, Decimal.fromInt(1500));
    expect(after.netWorth, before.netWorth);

    final recoveryId = repo.receivableRecoveries.single.id;
    await repo.undoReceivableRecovery(recoveryId);
    final restored = repo.receivableAssets.singleWhere((a) => a.id == assetId);
    expect(restored.remainingAmount, Decimal.fromInt(2000));
    expect(restored.status, ReceivableAssetStatus.active);
    expect(repo.receivableRecoveries, isEmpty);
    expect(repo.visibleTransactions, isEmpty);
    expect(repo.accountBalanceOf(account), Decimal.zero);
    expect(repo.eventsForReceivableAsset(assetId).first.eventType,
        AssetEventType.receivableRecoveryUndone);
    await repo.closeForTest();
  });

  test('资产 A0：全局列表和跨账本详情不随当前账本切换', () async {
    final repo = await freshRepo();
    final defaultBookId = repo.currentBookId;
    final privateBookId = await repo.addBook(
      name: '私有资产账本',
      includeInTotal: false,
    );
    await repo.switchBook(privateBookId);
    final physicalId = await repo.addPhysicalAsset(
      name: '收藏品',
      currentValue: Decimal.fromInt(1200),
    );
    final receivableId = await repo.addReceivableAsset(
      name: '私有账本押金',
      type: ReceivableAssetType.securityDeposit,
      originalAmount: Decimal.fromInt(300),
    );
    expect(
        repo.currentNetWorthBreakdown().physicalAssets, Decimal.fromInt(1200));
    expect(
        repo.currentNetWorthBreakdown().receivableAssets, Decimal.fromInt(300));
    await repo.switchBook(defaultBookId);
    expect(repo.physicalAssets, isEmpty);
    expect(repo.receivableAssets, isEmpty);
    expect(
        repo.currentNetWorthBreakdown().physicalAssets, Decimal.fromInt(1200));
    expect(
        repo.currentNetWorthBreakdown().receivableAssets, Decimal.fromInt(300));
    expect(repo.globalActivePhysicalAssets.map((asset) => asset.id),
        contains(physicalId));
    expect(repo.globalActiveReceivables.map((asset) => asset.id),
        contains(receivableId));
    expect(repo.physicalAssetDetailById(physicalId)?.name, '收藏品');
    expect(
      repo.receivableDetailById(receivableId)?.name,
      '私有账本押金',
    );
    expect(repo.eventsForAsset(physicalId), isNotEmpty);
    expect(repo.valuationsForAsset(physicalId), isNotEmpty);
    expect(repo.eventsForReceivableAsset(receivableId), isNotEmpty);
    await repo.closeForTest();
  });

  test('当前账本资产包不泄露其他账本资产、全局快照或负债', () async {
    var repo = await freshRepo();
    await repo.addPhysicalAsset(
      name: '总账本电脑',
      currentValue: Decimal.fromInt(5000),
    );
    final loanAccountId = await repo.addAccount(
      name: '来源房贷账户',
      type: AccountType.loan,
    );
    await repo.upsertLiabilityProfile(
      accountId: loanAccountId,
      type: LiabilityProfileType.mortgage,
      originalAmount: Decimal.fromInt(100000),
      currentPrincipal: Decimal.fromInt(80000),
    );
    expect(repo.netWorthSnapshots, isNotEmpty);
    expect(repo.liabilityProfiles, isNotEmpty);

    final privateBookId = await repo.addBook(
      name: '私有资产导出账本',
      includeInTotal: false,
    );
    await repo.switchBook(privateBookId);
    await repo.addPhysicalAsset(
      name: '私有账本相机',
      currentValue: Decimal.fromInt(3000),
    );

    final payload = await repo.exportAssetTablesJson();
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    expect(
      (decoded['assets'] as List)
          .cast<Map<String, dynamic>>()
          .map((asset) => asset['name']),
      ['私有账本相机'],
    );
    expect(decoded.containsKey('net_worth_snapshots'), isFalse);
    expect(decoded.containsKey('liability_profiles'), isFalse);
    await repo.closeForTest();

    await databaseFactory.deleteDatabase(p.join(tmp.path, 'qingji.db'));
    repo = await freshRepo();
    final targetLoanId = await repo.addAccount(
      name: '接收方房贷账户',
      type: AccountType.loan,
    );
    await repo.upsertLiabilityProfile(
      accountId: targetLoanId,
      type: LiabilityProfileType.mortgage,
      originalAmount: Decimal.fromInt(900000),
      currentPrincipal: Decimal.fromInt(700000),
    );

    final result = await repo.importAssetTablesJson(payload);
    expect(result.assets, 1);
    expect(result.snapshots, 0);
    expect(result.liabilities, 0);
    expect(repo.physicalAssets.single.name, '私有账本相机');
    expect(repo.liabilityProfiles.single.accountId, targetLoanId);
    expect(
      repo.liabilityProfiles.single.currentPrincipal,
      Decimal.fromInt(700000),
    );
    await repo.closeForTest();
  });

  test('资产 P2：全部收回后权益资产不再计入净资产', () async {
    final repo = await freshRepo();
    final account = repo.accounts.first;
    final assetId = await repo.addReceivableAsset(
      name: '借给朋友',
      type: ReceivableAssetType.loanOut,
      originalAmount: Decimal.fromInt(800),
    );

    await repo.recoverReceivableAsset(
      id: assetId,
      amount: Decimal.fromInt(800),
      targetAccountId: account.id,
    );

    final asset = repo.receivableAssets.singleWhere((a) => a.id == assetId);
    expect(asset.status, ReceivableAssetStatus.recovered);
    expect(asset.remainingAmount, Decimal.zero);
    expect(asset.countsInNetWorth, isFalse);
    final breakdown = repo.currentNetWorthBreakdown();
    expect(breakdown.cashAssets, Decimal.fromInt(800));
    expect(breakdown.receivableAssets, Decimal.zero);
    expect(breakdown.netWorth, Decimal.fromInt(800));
    await repo.closeForTest();
  });

  test('资产 P2：权益资产导出导入按唯一 ID 恢复，同名同金额不会合并', () async {
    final repo = await freshRepo();
    await repo.addReceivableAsset(
      name: '押金',
      type: ReceivableAssetType.securityDeposit,
      originalAmount: Decimal.fromInt(1000),
    );
    await repo.addReceivableAsset(
      name: '押金',
      type: ReceivableAssetType.securityDeposit,
      originalAmount: Decimal.fromInt(1000),
    );
    final json = await repo.exportAssetTablesJson();
    await repo.closeForTest();
    File(p.join(tmp.path, 'qingji.db')).deleteSync();

    final restored = await freshRepo();
    final result = await restored.importAssetTablesJson(json);
    expect(result.receivables, 2);
    expect(
      restored.receivableAssets.where(
          (a) => a.name == '押金' && a.remainingAmount == Decimal.fromInt(1000)),
      hasLength(2),
    );
    expect(
        restored.assetEvents
            .where((e) => e.assetType == AssetObjectType.receivable),
        hasLength(2));
    await restored.closeForTest();
  });

  test('旧版资产 JSON 仍按账户名恢复收回记录和负债档案', () async {
    final repo = await freshRepo();
    final receivableTargetId = await repo.addAccount(
      name: 'Asset target account',
      type: AccountType.savings,
      openingBalance: Decimal.zero,
    );
    final liabilityAccountId = await repo.addAccount(
      name: 'Mortgage account',
      type: AccountType.loan,
      openingBalance: Decimal.zero,
    );
    final repaymentAccountId = await repo.addAccount(
      name: 'Repayment card',
      type: AccountType.debit,
      openingBalance: Decimal.zero,
    );
    final receivableId = await repo.addReceivableAsset(
      name: 'Deposit',
      type: ReceivableAssetType.securityDeposit,
      originalAmount: Decimal.fromInt(1000),
    );
    await repo.recoverReceivableAsset(
      id: receivableId,
      amount: Decimal.fromInt(200),
      targetAccountId: receivableTargetId,
      recoveredAt: DateTime(2026, 7, 7),
    );
    await repo.upsertLiabilityProfile(
      accountId: liabilityAccountId,
      type: LiabilityProfileType.mortgage,
      originalAmount: Decimal.fromInt(100000),
      currentPrincipal: Decimal.fromInt(80000),
      repaymentAccountId: repaymentAccountId,
    );
    final decoded =
        jsonDecode(await repo.exportAssetTablesJson()) as Map<String, dynamic>;
    expect(decoded.containsKey('liability_profiles'), isFalse);
    expect(decoded.containsKey('net_worth_snapshots'), isFalse);
    decoded['net_worth_snapshots'] = [
      {
        'scope_key': 'global',
        'snapshot_date': '2025-01-01',
        'total_assets': '120000',
        'total_liabilities': '80000',
        'net_worth': '40000',
        'cash_assets': '40000',
        'investment_assets': '0',
        'physical_assets': '0',
        'receivable_assets': '0',
        'snapshot_type': 'legacy_unverified',
        'lineage_key': 'legacy:asset-export',
        'quality': 'legacy_unverified',
        'created_ms': DateTime(2025, 1, 1).millisecondsSinceEpoch,
      },
    ];
    decoded['liability_profiles'] = [
      {
        'uuid': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1',
        'account_id': liabilityAccountId,
        'account_name': 'Mortgage account',
        'liability_type': 'mortgage',
        'original_amount': '100000',
        'current_principal': '80000',
        'interest_rate': '0',
        'repayment_day': null,
        'repayment_account_id': repaymentAccountId,
        'repayment_account_name': 'Repayment card',
        'start_date_ms': null,
        'end_date_ms': null,
        'status': 'active',
        'note': '',
        'created_ms': DateTime(2026, 7, 1).millisecondsSinceEpoch,
        'updated_ms': DateTime(2026, 7, 1).millisecondsSinceEpoch,
      },
    ];
    final legacyJson = jsonEncode(decoded);
    await repo.closeForTest();
    File(p.join(tmp.path, 'qingji.db')).deleteSync();

    final restored = await freshRepo();
    await restored.addAccount(
      name: 'Wrong 1',
      type: AccountType.cash,
      openingBalance: Decimal.zero,
    );
    await restored.addAccount(
      name: 'Wrong 2',
      type: AccountType.cash,
      openingBalance: Decimal.zero,
    );
    await restored.addAccount(
      name: 'Wrong 3',
      type: AccountType.cash,
      openingBalance: Decimal.zero,
    );
    final restoredTargetId = await restored.addAccount(
      name: 'Asset target account',
      type: AccountType.savings,
      openingBalance: Decimal.zero,
    );
    final restoredLiabilityAccountId = await restored.addAccount(
      name: 'Mortgage account',
      type: AccountType.loan,
      openingBalance: Decimal.zero,
    );
    final restoredRepaymentAccountId = await restored.addAccount(
      name: 'Repayment card',
      type: AccountType.debit,
      openingBalance: Decimal.zero,
    );

    final result = await restored.importAssetTablesJson(legacyJson);

    expect(result.recoveries, 1);
    expect(result.snapshots, 1);
    expect(result.liabilities, 1);
    expect(
      restored.netWorthSnapshots
          .any((snapshot) => snapshot.snapshotDate == '2025-01-01'),
      isTrue,
    );
    expect(
        restored.receivableRecoveries.single.targetAccountId, restoredTargetId);
    final profile = restored.liabilityProfiles.single;
    expect(profile.accountId, restoredLiabilityAccountId);
    expect(profile.repaymentAccountId, restoredRepaymentAccountId);
    await restored.closeForTest();
  });

  test('资产 P3：负债档案保存还款信息，正余额账户用本金补充负债', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(
      name: '房贷',
      type: AccountType.loan,
      openingBalance: Decimal.zero,
      includeInNetWorth: true,
    );

    await repo.upsertLiabilityProfile(
      accountId: accountId,
      type: LiabilityProfileType.mortgage,
      originalAmount: Decimal.fromInt(1000000),
      currentPrincipal: Decimal.fromInt(780000),
      interestRate: Decimal.parse('3.2'),
      repaymentDay: 15,
      status: LiabilityProfileStatus.active,
    );

    final profile = repo.liabilityProfileForAccount(accountId)!;
    expect(profile.type, LiabilityProfileType.mortgage);
    expect(profile.currentPrincipal, Decimal.fromInt(780000));
    expect(profile.nextRepaymentDate(now: DateTime(2026, 7, 7)),
        DateTime(2026, 7, 15));
    final breakdown = repo.currentNetWorthBreakdown();
    expect(breakdown.totalLiabilities, Decimal.fromInt(780000));
    expect(breakdown.netWorth, Decimal.fromInt(-780000));
    await repo.closeForTest();
  });

  test('资产 P3：账户负余额已计负债时，负债档案不重复计入', () async {
    final repo = await freshRepo();
    final accountId = await repo.addAccount(
      name: '信用卡',
      type: AccountType.credit,
      openingBalance: Decimal.fromInt(-3000),
      includeInNetWorth: true,
    );

    await repo.upsertLiabilityProfile(
      accountId: accountId,
      type: LiabilityProfileType.creditCard,
      originalAmount: Decimal.fromInt(3000),
      currentPrincipal: Decimal.fromInt(3000),
      repaymentDay: 8,
    );

    final breakdown = repo.currentNetWorthBreakdown();
    expect(breakdown.totalLiabilities, Decimal.fromInt(3000));
    expect(breakdown.netWorth, Decimal.fromInt(-3000));
    await repo.closeForTest();
  });

  test('资产 P4：手动更新当前价值会暂停自动折旧', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '相机',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(1200),
      purchasePrice: Decimal.fromInt(1200),
      purchaseDate: DateTime(2026, 1, 1),
    );

    await repo.configurePhysicalAssetDepreciation(
      id: assetId,
      enabled: true,
      depreciationBase: Decimal.fromInt(1200),
      salvageValue: Decimal.zero,
      usefulLifeMonths: 12,
      startAt: DateTime(2026, 1, 1),
    );
    await repo.updatePhysicalAssetValue(
      assetId,
      Decimal.fromInt(900),
      valuedAt: DateTime(2026, 3, 1),
    );

    var asset = repo.physicalAssets.singleWhere((a) => a.id == assetId);
    expect(asset.currentValue, Decimal.fromInt(900));
    expect(asset.depreciationPaused, isTrue);
    final changed = await repo.applyPhysicalAssetDepreciation(
      asOf: DateTime(2026, 7, 1),
    );
    asset = repo.physicalAssets.singleWhere((a) => a.id == assetId);
    expect(changed, 0);
    expect(asset.currentValue, Decimal.fromInt(900));
    await repo.closeForTest();
  });

  test('资产 P4：线性折旧按完整月份更新价值并写历史', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '笔记本',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(1200),
      purchasePrice: Decimal.fromInt(1200),
      purchaseDate: DateTime(2026, 1, 1),
    );
    await repo.configurePhysicalAssetDepreciation(
      id: assetId,
      enabled: true,
      depreciationBase: Decimal.fromInt(1200),
      salvageValue: Decimal.zero,
      usefulLifeMonths: 12,
      startAt: DateTime(2026, 1, 1),
    );

    final changed = await repo.applyPhysicalAssetDepreciation(
      asOf: DateTime(2026, 7, 1),
    );

    final asset = repo.physicalAssets.singleWhere((a) => a.id == assetId);
    expect(changed, 1);
    expect(asset.currentValue, Decimal.fromInt(600));
    expect(
      repo.valuationsForAsset(assetId).first.source,
      AssetValueSource.autoDepreciation,
    );
    expect(
      repo.eventsForAsset(assetId).map((e) => e.eventType),
      contains(AssetEventType.autoDepreciationApplied),
    );
    await repo.closeForTest();
  });

  test('资产 P4：自动折旧不会低于残值', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '音箱',
      assetType: AssetType.appliance,
      currentValue: Decimal.fromInt(1200),
      purchasePrice: Decimal.fromInt(1200),
    );
    await repo.configurePhysicalAssetDepreciation(
      id: assetId,
      enabled: true,
      depreciationBase: Decimal.fromInt(1200),
      salvageValue: Decimal.fromInt(300),
      usefulLifeMonths: 12,
      startAt: DateTime(2026, 1, 1),
    );

    await repo.applyPhysicalAssetDepreciation(asOf: DateTime(2028, 1, 1));

    final asset = repo.physicalAssets.singleWhere((a) => a.id == assetId);
    expect(asset.currentValue, Decimal.fromInt(300));
    expect(repo.physicalAssetNetWorthTotal, Decimal.fromInt(300));
    await repo.closeForTest();
  });

  test('资产 A0：archived-owned 仍会折旧，visibility 不影响估值', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '旧手机',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(1000),
      purchasePrice: Decimal.fromInt(1000),
      purchaseDate: DateTime(2026, 1, 1),
    );
    await repo.configurePhysicalAssetDepreciation(
      id: assetId,
      enabled: true,
      depreciationBase: Decimal.fromInt(1000),
      salvageValue: Decimal.zero,
      usefulLifeMonths: 10,
      startAt: DateTime(2026, 1, 1),
    );
    await repo.archivePhysicalAsset(assetId);

    final changed = await repo.applyPhysicalAssetDepreciation(
      asOf: DateTime(2026, 7, 1),
    );

    final asset = repo.physicalAssets.singleWhere((a) => a.id == assetId);
    expect(changed, 1);
    expect(asset.visibilityStatus, AssetVisibilityStatus.archived);
    expect(asset.economicStatus, PhysicalAssetEconomicStatus.owned);
    expect(asset.includeInNetWorth, isTrue);
    expect(asset.currentValue, Decimal.fromInt(400));
    expect(repo.physicalAssetNetWorthTotal, Decimal.fromInt(400));
    await repo.closeForTest();
  });

  test('资产 P4：导出导入保留凭证和折旧配置', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '主力电脑',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(8000),
      purchasePrice: Decimal.fromInt(10000),
      purchaseDate: DateTime(2026, 1, 1),
    );
    await repo.updatePhysicalAssetEvidence(
      assetId,
      photoPath: '/assets/macbook.jpg',
      thumbnailPath: '/assets/macbook-thumb.jpg',
      invoicePath: '/assets/invoice.pdf',
    );
    await repo.configurePhysicalAssetDepreciation(
      id: assetId,
      enabled: true,
      depreciationBase: Decimal.fromInt(10000),
      salvageValue: Decimal.fromInt(1000),
      usefulLifeMonths: 36,
      startAt: DateTime(2026, 1, 1),
    );
    final json = await repo.exportAssetTablesJson();
    await repo.closeForTest();
    File(p.join(tmp.path, 'qingji.db')).deleteSync();

    final restored = await freshRepo();
    final result = await restored.importAssetTablesJson(json);

    expect(result.assets, 1);
    final asset = restored.physicalAssets.singleWhere((a) => a.name == '主力电脑');
    expect(asset.photoPath, '/assets/macbook.jpg');
    expect(asset.thumbnailPath, '/assets/macbook-thumb.jpg');
    expect(asset.invoicePath, '/assets/invoice.pdf');
    expect(asset.depreciationMethod, 'linear');
    expect(asset.depreciationBase, Decimal.fromInt(10000));
    expect(asset.salvageValue, Decimal.fromInt(1000));
    expect(asset.usefulLifeMonths, 36);
    expect(asset.depreciationPaused, isFalse);
    await restored.closeForTest();
  });

  test('资产导出 v4 往返保留独立状态字段和净资产口径', () async {
    final repo = await freshRepo();
    final physicalId = await repo.addPhysicalAsset(
      name: 'v4 archived camera',
      assetType: AssetType.digital,
      currentValue: Decimal.fromInt(900),
      purchasePrice: Decimal.fromInt(1200),
      includeInNetWorth: true,
    );
    final receivableId = await repo.addReceivableAsset(
      name: 'v4 archived deposit',
      type: ReceivableAssetType.securityDeposit,
      originalAmount: Decimal.fromInt(1000),
      includeInNetWorth: true,
    );
    await repo.archivePhysicalAsset(physicalId);
    await repo.archiveReceivableAsset(receivableId);
    final before = repo.currentNetWorthBreakdown();

    final json = await repo.exportAssetTablesJson();
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['format'], 'feimiao-assets');
    expect(decoded['version'], 6);
    final exportedPhysical =
        (decoded['assets'] as List).cast<Map<String, dynamic>>().single;
    final exportedReceivable = (decoded['receivable_assets'] as List)
        .cast<Map<String, dynamic>>()
        .single;
    expect(exportedPhysical['economic_status'], 'owned');
    expect(exportedPhysical['usage_status'], 'active');
    expect(exportedPhysical['visibility_status'], 'archived');
    expect(exportedPhysical['inclusion_quality'], 'confirmed');
    expect(exportedPhysical['include_in_net_worth'], 1);
    expect(exportedPhysical['ended_ms'], isNull);
    expect(exportedPhysical['archived_ms'], isNotNull);
    expect(exportedReceivable['economic_status'], 'active');
    expect(exportedReceivable['visibility_status'], 'archived');
    expect(exportedReceivable['inclusion_quality'], 'confirmed');
    expect(exportedReceivable['include_in_net_worth'], 1);
    expect(exportedReceivable['ended_ms'], isNull);
    expect(exportedReceivable['archived_ms'], isNotNull);
    await repo.closeForTest();

    File(p.join(tmp.path, 'qingji.db')).deleteSync();
    final restored = await freshRepo();
    final result = await restored.importAssetTablesJson(json);
    expect(result.assets, 1);
    expect(result.receivables, 1);

    final physical = restored.globalArchivedPhysicalAssets.single;
    expect(physical.name, 'v4 archived camera');
    expect(physical.economicStatus, PhysicalAssetEconomicStatus.owned);
    expect(physical.usageStatus, PhysicalAssetUsageStatus.active);
    expect(physical.visibilityStatus, AssetVisibilityStatus.archived);
    expect(physical.inclusionQuality, AssetInclusionQuality.confirmed);
    expect(physical.includeInNetWorth, isTrue);
    expect(physical.currentValue, Decimal.fromInt(900));
    expect(physical.endedMs, isNull);
    expect(physical.archivedMs, isNotNull);
    final receivable = restored.globalArchivedReceivables.single;
    expect(receivable.name, 'v4 archived deposit');
    expect(receivable.economicStatus, ReceivableEconomicStatus.active);
    expect(receivable.visibilityStatus, AssetVisibilityStatus.archived);
    expect(receivable.inclusionQuality, AssetInclusionQuality.confirmed);
    expect(receivable.includeInNetWorth, isTrue);
    expect(receivable.remainingAmount, Decimal.fromInt(1000));
    expect(receivable.endedMs, isNull);
    expect(receivable.archivedMs, isNotNull);
    final after = restored.currentNetWorthBreakdown();
    expect(after.physicalAssets, before.physicalAssets);
    expect(after.receivableAssets, before.receivableAssets);
    expect(after.netWorth, before.netWorth);
    await restored.closeForTest();
  });

  test('资产 A2：账户活动按真实结算账户投影且转账拆成双腿', () async {
    final repo = await freshRepo();
    final source = repo.accounts.first;
    final targetId = await repo.addAccount(name: '储蓄账户');
    final target = repo.accounts.singleWhere((item) => item.id == targetId);
    await repo.addTransaction(
      kind: TransactionKind.transfer,
      amount: Decimal.fromInt(88),
      accountId: source.id,
      toAccountId: target.id,
      date: DateTime(2026, 7, 13),
      note: '转入储蓄',
      excluded: true,
    );

    final sourceActivity = repo.accountActivitiesFor(source.id);
    final targetActivity = repo.accountActivitiesFor(target.id);
    expect(sourceActivity.single.signedAmountMinor, -8800);
    expect(targetActivity.single.signedAmountMinor, 8800);
    expect(sourceActivity.single.bookName, isNotEmpty);
    await repo.closeForTest();
  });

  test('资产 A2：当前快照保留 lineage，历史日期写入被拒绝', () async {
    final repo = await freshRepo();
    final beforeCutoff = repo.netWorthSnapshots.first.knowledgeCutoffMs;
    await repo.addTransaction(
      kind: TransactionKind.income,
      amount: Decimal.fromInt(200),
      accountId: repo.accounts.first.id,
      date: DateTime.now(),
      note: '快照测试',
    );
    final result = repo.currentNetWorthResult();
    expect(result.value, isNotNull);

    final automatic = repo.netWorthSnapshots.first;
    expect(automatic.knowledgeCutoffMs, greaterThanOrEqualTo(beforeCutoff));
    expect(
      automatic.toComputedSnapshot().lineage.causes,
      contains(NetWorthSnapshotCause.transaction),
    );
    expect(automatic.timezone, startsWith('device_local@UTC'));

    await repo.recordNetWorthSnapshot();
    final snapshot = repo.netWorthSnapshots.first;
    expect(snapshot.snapshotType, 'computed_snapshot');
    expect(snapshot.quality, isNot(NetWorthSnapshotQuality.legacyUnverified));
    expect(snapshot.knowledgeCutoffMs, greaterThan(0));
    expect(snapshot.lineageKey, contains('calc='));
    expect(snapshot.toComputedSnapshot().lineage.currencyCoverage.baseCurrency,
        'CNY');

    expect(
      () => repo.recordNetWorthSnapshot(
        date: DateTime.now().subtract(const Duration(days: 30)),
      ),
      throwsStateError,
    );
    await repo.closeForTest();
  });

  test('v35 → v36：旧净资产快照降级为 legacy unverified 且不参与趋势', () async {
    final seeded = await freshRepo();
    await seeded.closeForTest();
    final path = p.join(tmp.path, 'qingji.db');
    final db = await databaseFactory.openDatabase(path);
    await db.update(
      'net_worth_snapshots',
      {
        'snapshot_date': '2026-07-12',
        'snapshot_type': 'computed_snapshot',
        'quality': 'available',
      },
    );
    await db.execute('PRAGMA user_version = 35');
    await db.close();

    final migrated = await freshRepo();
    final legacy = migrated.netWorthSnapshots.singleWhere(
      (snapshot) => snapshot.snapshotDate == '2026-07-12',
    );
    expect(legacy.snapshotType, 'legacy_unverified');
    expect(legacy.quality, NetWorthSnapshotQuality.legacyUnverified);
    expect(legacy.toComputedSnapshot().isEligibleForEstimatedTrend, isFalse);
    expect(
      migrated.netWorthEstimatedTrend.status,
      NetWorthTrendStatus.insufficientEligiblePoints,
    );
    await migrated.closeForTest();
  });

  test('资产 A1：单物退款自动分配，删除退款逐笔回滚且退货可撤销', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: accountId,
      date: DateTime(2026, 7, 1),
      note: '单物订单',
    );
    final assetId = await repo.addPhysicalAssetFromTransaction(
      transactionId: transactionId,
      name: '耳机',
      allocatedGrossCents: 10000,
      photoPath: '/managed/original.jpg',
      thumbnailPath: '/managed/thumb.jpg',
    );
    var original = repo.visibleTransactions.singleWhere(
      (transaction) => transaction.id == transactionId,
    );
    final firstRefundId = await repo.refundTransaction(
      original,
      Decimal.fromInt(30),
      settledAt: DateTime(2026, 7, 2),
      settlementAccountId: accountId,
    );

    var cost = repo.physicalAssetAcquisitionCost(assetId);
    expect(cost.isExact, isTrue);
    expect(cost.amount, Decimal.fromInt(70));
    expect(repo.transactionLinksForAsset(assetId).single.allocatedRefundCents,
        3000);
    expect(repo.physicalAssetDetailById(assetId)!.thumbnailPath,
        '/managed/thumb.jpg');

    await repo.deleteTransaction(firstRefundId);
    cost = repo.physicalAssetAcquisitionCost(assetId);
    expect(cost.isExact, isTrue);
    expect(cost.amount, Decimal.fromInt(100));
    expect(
        repo.transactionLinksForAsset(assetId).single.allocatedRefundCents, 0);

    original = repo.visibleTransactions.singleWhere(
      (transaction) => transaction.id == transactionId,
    );
    final fullRefundId = await repo.refundTransaction(
      original,
      Decimal.fromInt(100),
      settledAt: DateTime(2026, 7, 3),
      settlementAccountId: accountId,
    );
    await repo.returnPhysicalAsset(
      assetId: assetId,
      returnedAt: DateTime(2026, 7, 3),
    );
    expect(repo.physicalAssetDetailById(assetId)!.economicStatus,
        PhysicalAssetEconomicStatus.returned);
    expect(repo.deleteTransaction(fullRefundId), throwsStateError);
    expect(repo.physicalAssetAcquisitionCost(assetId).amount, Decimal.zero);
    expect(repo.physicalAssetDetailById(assetId)!.economicStatus,
        PhysicalAssetEconomicStatus.returned);
    await repo.undoPhysicalAssetReturn(assetId);
    expect(repo.physicalAssetDetailById(assetId)!.economicStatus,
        PhysicalAssetEconomicStatus.owned);
    await repo.closeForTest();
  });

  test('资产 A1：多物退款保持 pending，人工分配后恢复 exact', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: accountId,
      date: DateTime(2026, 7, 1),
      note: '多物订单',
    );
    final firstAssetId = await repo.addPhysicalAssetFromTransaction(
      transactionId: transactionId,
      name: '键盘',
      allocatedGrossCents: 6000,
    );
    final secondAssetId = await repo.addPhysicalAssetFromTransaction(
      transactionId: transactionId,
      name: '鼠标',
      allocatedGrossCents: 4000,
    );
    final original = repo.visibleTransactions.singleWhere(
      (transaction) => transaction.id == transactionId,
    );
    final refundId = await repo.refundTransaction(
      original,
      Decimal.fromInt(30),
      settledAt: DateTime(2026, 7, 2),
      settlementAccountId: accountId,
    );

    expect(
      repo.transactionLinksForAsset(firstAssetId).single.costQuality,
      AssetAllocationCostQuality.pendingRefundAllocation,
    );
    expect(repo.physicalAssetAcquisitionCost(firstAssetId).isExact, isFalse);
    final pending =
        await repo.pendingPhysicalAssetRefundAllocationsForAsset(firstAssetId);
    expect(pending, hasLength(1));
    expect(pending.single.refundTransactionId, refundId);
    expect(pending.single.refundCents, 3000);
    expect(pending.single.targets, hasLength(2));

    await repo.allocatePhysicalAssetRefund(
      refundTransactionId: refundId,
      allocationsByAssetId: {firstAssetId: 3000, secondAssetId: 0},
    );
    expect(repo.transactionLinksForAsset(firstAssetId).single.costQuality,
        AssetAllocationCostQuality.exact);
    expect(repo.transactionLinksForAsset(secondAssetId).single.costQuality,
        AssetAllocationCostQuality.exact);
    expect(repo.physicalAssetAcquisitionCost(firstAssetId).amount,
        Decimal.fromInt(30));
    expect(repo.physicalAssetAcquisitionCost(secondAssetId).amount,
        Decimal.fromInt(40));
    final firstAsset = repo.physicalAssetDetailById(firstAssetId)!;
    await repo.updatePhysicalAsset(
      id: firstAssetId,
      name: firstAsset.name,
      assetType: firstAsset.assetType,
      purchasePrice: Decimal.fromInt(999),
      currentValue: firstAsset.currentValue,
      currencyCode: firstAsset.currencyCode,
      status: firstAsset.status,
      purchaseDate: firstAsset.purchaseDate,
      brand: firstAsset.brand,
      model: firstAsset.model,
      location: firstAsset.location,
      warrantyUntil: firstAsset.warrantyUntil,
      note: firstAsset.note,
      includeInNetWorth: firstAsset.includeInNetWorth,
    );
    expect(
      repo.physicalAssetDetailById(firstAssetId)!.purchasePrice,
      Decimal.fromInt(30),
    );
    expect(
      repo.physicalAssetAcquisitionCost(firstAssetId).amount,
      Decimal.fromInt(30),
    );
    expect(
      await repo.pendingPhysicalAssetRefundAllocationsForAsset(firstAssetId),
      isEmpty,
    );
    await repo.closeForTest();
  });

  test('资产 A1：退款可归属订单未跟踪部分，物品成本不被污染', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    // 订单 ¥100 只跟踪一件 ¥60 的物品，剩 ¥40 是没入库的配件。
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: accountId,
      date: DateTime(2026, 7, 1),
      note: '混合订单退配件',
    );
    final assetId = await repo.addPhysicalAssetFromTransaction(
      transactionId: transactionId,
      name: '显示器',
      allocatedGrossCents: 6000,
    );
    final original = repo.visibleTransactions
        .singleWhere((transaction) => transaction.id == transactionId);
    // 退掉的是未跟踪的配件 ¥40：以前只能错摊到显示器或永远卡在待分配。
    final refundId = await repo.refundTransaction(
      original,
      Decimal.fromInt(40),
      settledAt: DateTime(2026, 7, 2),
      settlementAccountId: accountId,
    );
    final pending =
        await repo.pendingPhysicalAssetRefundAllocationsForAsset(assetId);
    expect(pending.single.untrackedLimitCents, 4000);

    await repo.allocatePhysicalAssetRefund(
      refundTransactionId: refundId,
      allocationsByAssetId: {assetId: 0},
      untrackedCents: 4000,
    );
    expect(repo.transactionLinksForAsset(assetId).single.costQuality,
        AssetAllocationCostQuality.exact);
    expect(repo.physicalAssetAcquisitionCost(assetId).amount,
        Decimal.fromInt(60));
    expect(
      await repo.pendingPhysicalAssetRefundAllocationsForAsset(assetId),
      isEmpty,
    );

    // 未跟踪容量已用完（¥40/¥40）：第二笔退款再想归未跟踪要被拒绝。
    final refund2 = await repo.refundTransaction(
      repo.visibleTransactions
          .singleWhere((transaction) => transaction.id == transactionId),
      Decimal.fromInt(20),
      settledAt: DateTime(2026, 7, 3),
      settlementAccountId: accountId,
    );
    await expectLater(
      repo.allocatePhysicalAssetRefund(
        refundTransactionId: refund2,
        allocationsByAssetId: {assetId: 0},
        untrackedCents: 2000,
      ),
      throwsStateError,
    );
    // 分给物品则正常走通，净成本 60-20=40。
    await repo.allocatePhysicalAssetRefund(
      refundTransactionId: refund2,
      allocationsByAssetId: {assetId: 2000},
    );
    expect(repo.physicalAssetAcquisitionCost(assetId).amount,
        Decimal.fromInt(40));
    expect(repo.transactionLinksForAsset(assetId).single.costQuality,
        AssetAllocationCostQuality.exact);
    await repo.closeForTest();
  });

  test('资产 A2：净资产计入政策变化会提升 scope version 并重算当天快照', () async {
    final repo = await freshRepo();
    final account = repo.accounts.first;
    final before = repo.netWorthSnapshots.first.scopeVersion;

    await repo.updateAccount(
      id: account.id,
      name: account.name,
      currencyCode: account.currencyCode,
      type: account.type,
      openingBalance: account.openingBalance,
      includeInNetWorth: false,
      institution: account.institution,
    );

    final after = repo.netWorthSnapshots.first;
    expect(after.scopeVersion, before + 1);
    expect(
      after.toComputedSnapshot().lineage.causes,
      contains(NetWorthSnapshotCause.scope),
    );
    await repo.closeForTest();
  });

  test('资产 A1：混合订单只跟踪部分物品仍可精确确认全额退货', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: accountId,
      date: DateTime(2026, 7, 1),
      note: '混合订单',
    );
    final assetId = await repo.addPhysicalAssetFromTransaction(
      transactionId: transactionId,
      name: '耐用品',
      allocatedGrossCents: 6000,
    );
    expect(repo.physicalAssetAcquisitionCost(assetId).isExact, isTrue);
    expect(
      repo.physicalAssetAcquisitionCost(assetId).amount,
      Decimal.fromInt(60),
    );
    final original = repo.visibleTransactions.singleWhere(
      (transaction) => transaction.id == transactionId,
    );
    await repo.refundTransaction(
      original,
      Decimal.fromInt(60),
      settledAt: DateTime(2026, 7, 2),
      settlementAccountId: accountId,
    );
    expect(repo.physicalAssetAcquisitionCost(assetId).isExact, isTrue);
    expect(repo.physicalAssetAcquisitionCost(assetId).amount, Decimal.zero);
    await repo.returnPhysicalAsset(assetId: assetId);
    expect(
      repo.physicalAssetDetailById(assetId)!.economicStatus,
      PhysicalAssetEconomicStatus.returned,
    );
    await repo.closeForTest();
  });

  test('资产 A1：解除购置账单会反转退款审计并固化手工成本', () async {
    final repo = await freshRepo();
    final accountId = repo.accounts.first.id;
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: accountId,
      date: DateTime(2026, 7, 1),
      note: '可解除订单',
    );
    final assetId = await repo.addPhysicalAssetFromTransaction(
      transactionId: transactionId,
      name: '可解除物品',
      allocatedGrossCents: 6000,
    );
    final original = repo.visibleTransactions.singleWhere(
      (transaction) => transaction.id == transactionId,
    );
    final refundId = await repo.refundTransaction(
      original,
      Decimal.fromInt(20),
      settledAt: DateTime(2026, 7, 2),
      settlementAccountId: accountId,
    );
    await repo.allocatePhysicalAssetRefund(
      refundTransactionId: refundId,
      allocationsByAssetId: {assetId: 2000},
    );

    await repo.unlinkPhysicalAssetTransaction(
      assetId: assetId,
      transactionId: transactionId,
    );
    expect(repo.transactionLinksForAsset(assetId), isEmpty);
    final cost = repo.physicalAssetAcquisitionCost(assetId);
    expect(cost.isExact, isTrue);
    expect(cost.amount, Decimal.fromInt(40));
    await repo.deleteTransaction(transactionId);
    expect(repo.physicalAssetDetailById(assetId), isNotNull);
    expect(
        repo.physicalAssetAcquisitionCost(assetId).amount, Decimal.fromInt(40));
    await repo.closeForTest();
  });

  test('v32 → latest：archived 资产按证据迁移且净值逐分守恒', () async {
    await installV32ArchivedAssetFixture();
    final path = p.join(tmp.path, 'qingji.db');
    final beforeDb = await databaseFactory.openDatabase(path);
    expect(
      Sqflite.firstIntValue(
        await beforeDb.rawQuery('PRAGMA user_version'),
      ),
      32,
    );
    final beforeEventCount = Sqflite.firstIntValue(
      await beforeDb.rawQuery('SELECT COUNT(*) FROM asset_events'),
    );
    final beforeRecoveryCount = Sqflite.firstIntValue(
      await beforeDb.rawQuery('SELECT COUNT(*) FROM receivable_recoveries'),
    );
    final beforeValuationCount = Sqflite.firstIntValue(
      await beforeDb.rawQuery('SELECT COUNT(*) FROM asset_valuations'),
    );
    await beforeDb.close();

    final repo = AppRepository();
    await repo.init();

    final activePhysical = repo.physicalAssetDetailById(100)!;
    expect(activePhysical.economicStatus, PhysicalAssetEconomicStatus.owned);
    expect(activePhysical.usageStatus, PhysicalAssetUsageStatus.active);
    expect(activePhysical.visibilityStatus, AssetVisibilityStatus.active);
    expect(activePhysical.inclusionQuality, AssetInclusionQuality.confirmed);

    final archivedPhysical = repo.physicalAssetDetailById(101)!;
    expect(archivedPhysical.currentValue, Decimal.fromInt(900));
    expect(archivedPhysical.includeInNetWorth, isFalse);
    expect(
      archivedPhysical.economicStatus,
      PhysicalAssetEconomicStatus.owned,
    );
    expect(
      archivedPhysical.usageStatus,
      PhysicalAssetUsageStatus.unknown,
    );
    expect(
      archivedPhysical.visibilityStatus,
      AssetVisibilityStatus.archived,
    );
    expect(
      archivedPhysical.inclusionQuality,
      AssetInclusionQuality.needsReview,
    );
    expect(archivedPhysical.endedMs, isNull);
    expect(
      archivedPhysical.archivedAt,
      DateTime(2026, 7, 1, 12),
    );
    expect(repo.globalArchivedPhysicalAssets.map((asset) => asset.id), [101]);

    final receivables = {
      for (final asset in repo.globalArchivedReceivables) asset.id: asset,
    };
    expect(receivables.keys, containsAll([201, 202, 203, 204, 205, 206]));
    expect(
      receivables[201]!.economicStatus,
      ReceivableEconomicStatus.active,
    );
    expect(
      receivables[202]!.economicStatus,
      ReceivableEconomicStatus.partialRecovered,
    );
    expect(
      receivables[203]!.economicStatus,
      ReceivableEconomicStatus.recovered,
    );
    expect(
      receivables[204]!.economicStatus,
      ReceivableEconomicStatus.lost,
    );
    expect(
      receivables[205]!.economicStatus,
      ReceivableEconomicStatus.unknown,
    );
    expect(
      receivables[206]!.economicStatus,
      ReceivableEconomicStatus.unknown,
    );
    for (final asset in receivables.values) {
      expect(asset.visibilityStatus, AssetVisibilityStatus.archived);
      expect(asset.inclusionQuality, AssetInclusionQuality.needsReview);
      expect(asset.includeInNetWorth, isFalse);
      expect(asset.archivedAt, DateTime(2026, 7, 1, 12));
    }
    expect(receivables[201]!.endedMs, isNull);
    expect(receivables[202]!.endedMs, isNull);
    expect(receivables[203]!.endedAt, DateTime(2026, 5, 11, 12));
    expect(receivables[204]!.endedAt, DateTime(2026, 5, 12, 12));
    expect(receivables[205]!.endedMs, isNull);
    expect(receivables[206]!.endedMs, isNull);

    final breakdown = repo.currentNetWorthBreakdown();
    expect(breakdown.physicalAssets, Decimal.fromInt(3000));
    expect(breakdown.receivableAssets, Decimal.fromInt(1000));
    expect(breakdown.netWorth, Decimal.fromInt(4000));
    expect(repo.eventsForAsset(101), hasLength(1));
    expect(repo.valuationsForAsset(101), hasLength(1));
    expect(repo.recoveriesForReceivableAsset(202), hasLength(1));
    await repo.closeForTest();

    final check = await databaseFactory.openDatabase(path);
    expect(
      Sqflite.firstIntValue(await check.rawQuery('PRAGMA user_version')),
      43,
    );
    final physicalColumns =
        (await check.rawQuery('PRAGMA table_info(physical_assets)'))
            .map((row) => row['name'])
            .toSet();
    final receivableColumns =
        (await check.rawQuery('PRAGMA table_info(receivable_assets)'))
            .map((row) => row['name'])
            .toSet();
    expect(
      physicalColumns,
      containsAll([
        'economic_status',
        'usage_status',
        'visibility_status',
        'inclusion_quality',
        'ended_ms',
        'archived_ms',
      ]),
    );
    expect(
      receivableColumns,
      containsAll([
        'economic_status',
        'visibility_status',
        'inclusion_quality',
        'ended_ms',
        'archived_ms',
      ]),
    );
    expect(
      Sqflite.firstIntValue(
        await check.rawQuery('SELECT COUNT(*) FROM asset_events'),
      ),
      beforeEventCount,
    );
    expect(
      Sqflite.firstIntValue(
        await check.rawQuery('SELECT COUNT(*) FROM receivable_recoveries'),
      ),
      beforeRecoveryCount,
    );
    expect(
      Sqflite.firstIntValue(
        await check.rawQuery('SELECT COUNT(*) FROM asset_valuations'),
      ),
      beforeValuationCount,
    );
    await check.close();

    final reopened = await freshRepo();
    expect(
      reopened.receivableDetailById(205)!.economicStatus,
      ReceivableEconomicStatus.unknown,
    );
    expect(reopened.currentNetWorthBreakdown().netWorth, Decimal.fromInt(4000));
    await reopened.closeForTest();
  });

  test('v33 → v34：交易到账维度按事件证据迁移且不伪造数据', () async {
    await installV33TransactionSettlementFixture();
    final path = p.join(tmp.path, 'qingji.db');
    const preservedColumns = <String>[
      'id',
      'book_id',
      'kind',
      'amount',
      'currency_code',
      'account_id',
      'to_account_id',
      'note',
      'date_ms',
      'uuid',
      'updated_ms',
      'refund_of',
    ];

    final beforeDb = await databaseFactory.openDatabase(path);
    expect(
      Sqflite.firstIntValue(await beforeDb.rawQuery('PRAGMA user_version')),
      33,
    );
    final beforeRows = await beforeDb.query(
      'transactions',
      columns: preservedColumns,
      orderBy: 'id ASC',
    );
    expect(beforeRows, hasLength(9));
    await beforeDb.close();

    final repo = AppRepository();
    await repo.init();

    expect(repo.transactions, hasLength(9));
    TransactionEntity transaction(int id) =>
        repo.transactions.singleWhere((item) => item.id == id);

    expect(transaction(1).eventType, TransactionEventType.expense);
    expect(transaction(2).eventType, TransactionEventType.income);
    expect(transaction(3).eventType, TransactionEventType.transfer);
    expect(transaction(4).eventType, TransactionEventType.refund);
    expect(transaction(5).eventType, TransactionEventType.reimbursement);
    expect(transaction(6).eventType, TransactionEventType.assetPurchase);
    expect(transaction(7).eventType, TransactionEventType.assetSale);
    expect(
      transaction(8).eventType,
      TransactionEventType.receivableRecovery,
    );
    expect(transaction(9).eventType, TransactionEventType.legacyAdjustment);

    for (final id in [1, 2, 3, 6, 7, 8, 9]) {
      final item = transaction(id);
      expect(item.settledMs, item.dateMs, reason: 'legacy row $id date');
      expect(
        item.settlementQuality,
        SettlementQuality.legacyAssumed,
        reason: 'legacy row $id date quality',
      );
      expect(item.settlementAccountId, item.accountId);
      expect(
        item.settlementAccountQuality,
        SettlementQuality.legacyAssumed,
      );
    }
    final transfer = transaction(3);
    expect(transfer.accountId, isNotNull);
    expect(transfer.toAccountId, isNotNull);
    expect(transfer.toAccountId, isNot(transfer.accountId));

    final merchantRefund = transaction(4);
    expect(merchantRefund.settledMs, isNull);
    expect(merchantRefund.settlementQuality, SettlementQuality.unknown);
    expect(merchantRefund.settlementAccountId, merchantRefund.accountId);
    expect(
      merchantRefund.settlementAccountQuality,
      SettlementQuality.legacyAssumed,
    );

    final reimbursement = transaction(5);
    expect(reimbursement.settledMs, isNull);
    expect(reimbursement.settlementQuality, SettlementQuality.unknown);
    expect(reimbursement.settlementAccountId, isNull);
    expect(
      reimbursement.settlementAccountQuality,
      SettlementQuality.unknown,
    );
    expect(repo.transactions.every((item) => item.createdMs == 0), isTrue);
    await repo.closeForTest();

    final check = await databaseFactory.openDatabase(path);
    expect(
      Sqflite.firstIntValue(await check.rawQuery('PRAGMA user_version')),
      43,
    );
    final afterRows = await check.query(
      'transactions',
      columns: preservedColumns,
      orderBy: 'id ASC',
    );
    expect(afterRows, beforeRows);
    expect(
      Sqflite.firstIntValue(
        await check.rawQuery('SELECT COUNT(*) FROM transactions'),
      ),
      9,
    );
    final migratedRows = await check.query(
      'transactions',
      columns: [
        'id',
        'created_ms',
        'updated_ms',
        'event_type',
        'settled_ms',
        'settlement_quality',
        'settlement_account_id',
        'settlement_account_quality',
      ],
      orderBy: 'id ASC',
    );
    for (final row in migratedRows) {
      expect(row['created_ms'], 0);
      expect(row['created_ms'], isNot(row['updated_ms']));
    }
    expect(
      migratedRows.map((row) => row['event_type']),
      [
        'expense',
        'income',
        'transfer',
        'refund',
        'reimbursement',
        'asset_purchase',
        'asset_sale',
        'receivable_recovery',
        'legacy_adjustment',
      ],
    );
    await check.close();
  });

  test('deleteTag 从账单摘除标签并 bump updated_ms', () async {
    final repo = await freshRepo();
    final tagId = await repo.addTag(name: '出差', colorValue: 0xFF123456);
    final keepTagId = await repo.addTag(name: '保留', colorValue: 0xFF654321);
    final txId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(30),
      accountId: repo.accounts.first.id,
      date: DateTime(2026, 7, 1),
      tagIds: [tagId, keepTagId],
      note: '带标签',
    );
    final dbPath = p.join(tmp.path, 'qingji.db');
    // repo 的库还开着：读侧连接必须 singleInstance:false，否则 sqflite 单实例
    // 复用会把 repo 的连接一起 close 掉，后面 deleteTag 报 database_closed。
    final before = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final beforeMs = Sqflite.firstIntValue(await before.rawQuery(
      'SELECT updated_ms FROM transactions WHERE id = ?',
      [txId],
    ))!;
    await before.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await repo.deleteTag(tagId);

    expect(repo.tags.where((t) => t.id == tagId), isEmpty);
    final tx = repo.transactions.singleWhere((t) => t.id == txId);
    expect(tx.tagIds, [keepTagId]);
    // 标签被摘除的账单要同步 bump 同步戳，不留「内容变了戳没变」的行。
    final after = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final afterMs = Sqflite.firstIntValue(await after.rawQuery(
      'SELECT updated_ms FROM transactions WHERE id = ?',
      [txId],
    ))!;
    await after.close();
    expect(afterMs, greaterThan(beforeMs));
    await repo.closeForTest();
  });

  test('v13 预算搬迁失败后启动自愈会把老预算搬进 budget_periods', () async {
    final seeded = await freshRepo();
    expect(seeded.budgetPeriods, isEmpty);
    await seeded.closeForTest();

    // 模拟「v13 搬迁 try/catch 吞了异常」后的库：旧 budget 表有数据、
    // budget_periods 空、自愈标记不存在。
    final db = await databaseFactory.openDatabase(p.join(tmp.path, 'qingji.db'));
    await db.execute(
        'CREATE TABLE IF NOT EXISTS budget (id INTEGER PRIMARY KEY AUTOINCREMENT, category_key TEXT, amount TEXT NOT NULL)');
    await db.insert('budget', {'category_key': null, 'amount': '3000'});
    await db.insert('budget', {'category_key': 'dining', 'amount': '800'});
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['v13_budget_migration_checked'],
    );
    await db.close();

    final repo = await freshRepo();
    final period = repo.budgetPeriods.single;
    expect(period.total, Decimal.fromInt(3000));
    expect(period.categoryBudgets['dining'], Decimal.fromInt(800));
    expect(period.recurringMonthly, isTrue);
    await repo.closeForTest();

    // 自愈是一次性的：已有预算期间后再启动不会重复搬。
    final again = await freshRepo();
    expect(again.budgetPeriods, hasLength(1));
    await again.closeForTest();
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
    await repo.init(); // 触发 v15→当前最新迁移

    // 老账单原样在，金额没变。
    expect(repo.transactions, hasLength(1));
    expect(repo.transactions.first.note, '老账单');
    expect(repo.transactions.first.amount, Decimal.parse('88.88'));
    // 隐藏列就位且默认可见。
    expect(repo.categories.every((c) => !c.hidden), isTrue);

    await repo.closeForTest();
    final check = await databaseFactory.openDatabase(path);
    final v =
        Sqflite.firstIntValue(await check.rawQuery('PRAGMA user_version'));
    expect(v, 43); // init 一路升到当前最新版本
    final tableNames = (await check
            .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'])
        .toSet();
    expect(tableNames, contains('reports'));
    expect(tableNames, contains('physical_assets'));
    expect(tableNames, contains('asset_events'));
    expect(tableNames, contains('asset_valuations'));
    expect(tableNames, contains('asset_transaction_links'));
    expect(tableNames, contains('receivable_assets'));
    expect(tableNames, contains('receivable_recoveries'));
    expect(tableNames, contains('account_balance_checkpoints'));
    expect(
      tableNames,
      contains('account_checkpoint_covered_unknown_events'),
    );
    expect(tableNames, contains('net_worth_verified_checkpoints'));
    expect(tableNames, contains('net_worth_verified_checkpoint_items'));
    expect(tableNames, contains('budget_plans'));
    expect(tableNames, contains('budget_plan_revisions'));
    expect(tableNames, contains('budget_cycle_overrides'));
    expect(tableNames, contains('budget_fixed_commitment_occurrences'));
    final accountColumns = (await check.rawQuery('PRAGMA table_info(accounts)'))
        .map((row) => row['name'])
        .toSet();
    expect(
      accountColumns,
      containsAll([
        'uuid',
        'opening_balance_effective_ms',
        'opening_balance_quality',
        'status',
        'archived_ms',
      ]),
    );
    expect(tableNames, contains('net_worth_snapshots'));
    expect(tableNames, contains('liability_profiles'));
    // v42：账期两列 + 借入对象列就位。
    final liabilityColumnNames =
        (await check.rawQuery('PRAGMA table_info(liability_profiles)'))
            .map((row) => row['name'])
            .toSet();
    expect(
      liabilityColumnNames,
      containsAll(['statement_day', 'credit_limit', 'counterparty']),
    );
    expect(tableNames, contains('recurring_occurrences'));
    expect(tableNames, contains('auto_record_occurrences'));
    expect(tableNames, contains('report_jobs'));
    final netWorthColumnNames =
        (await check.rawQuery('PRAGMA table_info(net_worth_snapshots)'))
            .map((row) => row['name'])
            .toSet();
    expect(netWorthColumnNames, contains('scope_key'));
    final reportColumnNames =
        (await check.rawQuery('PRAGMA table_info(reports)'))
            .map((r) => r['name'])
            .toSet();
    expect(reportColumnNames, contains('pinned_ms'));
    final accountColumnNames =
        (await check.rawQuery('PRAGMA table_info(accounts)'))
            .map((r) => r['name'])
            .toSet();
    expect(
      accountColumnNames,
      containsAll([
        'is_deleted',
        'deleted_at_ms',
        'type',
        'opening_balance',
        'include_in_net_worth',
        'institution',
        'sort_order',
      ]),
    );
    final recurringColumnNames =
        (await check.rawQuery('PRAGMA table_info(recurring_rules)'))
            .map((r) => r['name'])
            .toSet();
    expect(
      recurringColumnNames,
      containsAll([
        'anchor_day',
        'start_date_ms',
        'end_date_ms',
        'total_count',
        'generated_count',
      ]),
    );
    final transactionColumnNames =
        (await check.rawQuery('PRAGMA table_info(transactions)'))
            .map((r) => r['name'])
            .toSet();
    expect(transactionColumnNames, contains('recurring_rule_id'));
    final eventColumnNames =
        (await check.rawQuery('PRAGMA table_info(asset_events)'))
            .map((r) => r['name'])
            .toSet();
    expect(eventColumnNames, contains('asset_type'));
    final physicalAssetColumnNames =
        (await check.rawQuery('PRAGMA table_info(physical_assets)'))
            .map((r) => r['name'])
            .toSet();
    expect(
      physicalAssetColumnNames,
      containsAll([
        'photo_path',
        'invoice_path',
        'depreciation_method',
        'depreciation_base',
        'salvage_value',
        'useful_life_months',
        'depreciation_start_ms',
        'depreciation_paused',
      ]),
    );
    final rows = await check.query('transactions');
    expect((rows.first['uuid'] as String).length, 32); // randomblob 回填
    expect(rows.first['updated_ms'] as int, greaterThan(0));
    await check.close();
  });

  group('游离退款归并：只在高置信匹配时挂回原单', () {
    // 直接往库里塞「游离行」（模拟 v17 前老版本的独立冲账行），
    // 再重开 repo 让 init 里的归并跑一遍。
    Future<int> insertLegacyRow(Map<String, Object?> values) async {
      final db =
          await databaseFactory.openDatabase(p.join(tmp.path, 'qingji.db'));
      final id = await db.insert('transactions', values);
      await db.close();
      return id;
    }

    Future<Map<String, Object?>> rawRow(int id) async {
      final db =
          await databaseFactory.openDatabase(p.join(tmp.path, 'qingji.db'));
      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      await db.close();
      return rows.single;
    }

    test('金额精确且唯一 → 挂回原单、日期归位、净额归零', () async {
      var repo = await freshRepo();
      final bookId =
          repo.books.map((b) => b.id).reduce((a, b) => a < b ? a : b);
      final cats = repo.categoriesForKindRanked(TransactionKind.expense);
      final accountId = repo.accounts.first.id;
      final origId = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.parse('150'),
        categoryId: cats.first.id,
        accountId: accountId,
        note: '原订单',
        date: DateTime(2026, 6, 1),
      );
      await repo.closeForTest();

      await insertLegacyRow({
        'book_id': bookId,
        'kind': 'expense',
        'amount': '-150',
        'category_id': null, // 分类对不上也行：金额精确 = 强信号
        'account_id': accountId,
        'note': '',
        'date_ms': DateTime(2026, 6, 20).millisecondsSinceEpoch,
      });

      repo = await freshRepo();
      final orig = repo.transactions.firstWhere((t) => t.id == origId);
      expect(repo.netAmountOf(orig), Decimal.zero);
      final refunds = repo.refundsOf(origId);
      expect(refunds, hasLength(1));
      expect(refunds.single.date, DateTime(2026, 6, 1)); // 日期归属原订单
      await repo.closeForTest();
    });

    test('多候选但只有一笔同分类 → 挂对那笔，不误挂', () async {
      var repo = await freshRepo();
      final bookId =
          repo.books.map((b) => b.id).reduce((a, b) => a < b ? a : b);
      final cats = repo.categoriesForKindRanked(TransactionKind.expense);
      final accountId = repo.accounts.first.id;
      final catA = cats[0].id;
      final catB = cats[1].id;
      final origA = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.parse('150'),
        categoryId: catA,
        accountId: accountId,
        note: '同分类原单',
        date: DateTime(2026, 6, 1),
      );
      await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.parse('200'),
        categoryId: catB,
        accountId: accountId,
        note: '别的分类大额单',
        date: DateTime(2026, 6, 1),
      );
      await repo.closeForTest();

      await insertLegacyRow({
        'book_id': bookId,
        'kind': 'expense',
        'amount': '-30', // 部分退款：金额谁都装得下，但分类只匹配 A
        'category_id': catA,
        'account_id': accountId,
        'note': '退款',
        'date_ms': DateTime(2026, 6, 10).millisecondsSinceEpoch,
      });

      repo = await freshRepo();
      expect(repo.refundsOf(origA), hasLength(1));
      final orig = repo.transactions.firstWhere((t) => t.id == origA);
      expect(repo.netAmountOf(orig), Decimal.parse('120'));
      await repo.closeForTest();
    });

    test('两笔同额原单有歧义 → 原样保留不猜', () async {
      var repo = await freshRepo();
      final bookId =
          repo.books.map((b) => b.id).reduce((a, b) => a < b ? a : b);
      final cats = repo.categoriesForKindRanked(TransactionKind.expense);
      final accountId = repo.accounts.first.id;
      for (var i = 0; i < 2; i++) {
        await repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.parse('100'),
          categoryId: cats.first.id,
          accountId: accountId,
          note: '同额单$i',
          date: DateTime(2026, 6, 1),
        );
      }
      await repo.closeForTest();

      final refundId = await insertLegacyRow({
        'book_id': bookId,
        'kind': 'expense',
        'amount': '-100',
        'category_id': cats.first.id,
        'account_id': accountId,
        'note': '退款',
        'date_ms': DateTime(2026, 6, 2).millisecondsSinceEpoch,
      });

      repo = await freshRepo();
      await repo.closeForTest();
      final row = await rawRow(refundId);
      expect(row['refund_of'], isNull); // 两个候选都匹配 → 不敢挂
    });

    test('收入行和带正经备注的负数行一律不动', () async {
      var repo = await freshRepo();
      final bookId =
          repo.books.map((b) => b.id).reduce((a, b) => a < b ? a : b);
      final cats = repo.categoriesForKindRanked(TransactionKind.expense);
      final accountId = repo.accounts.first.id;
      await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.parse('500'),
        categoryId: cats.first.id,
        accountId: accountId,
        note: '同账户支出',
        date: DateTime(2026, 6, 1),
      );
      await repo.closeForTest();

      // 用户记的收入（哪怕备注带「退回」）不能被吃掉变成退款冲减。
      final incomeId = await insertLegacyRow({
        'book_id': bookId,
        'kind': 'income',
        'amount': '500',
        'category_id': null,
        'account_id': accountId,
        'note': '押金退回',
        'date_ms': DateTime(2026, 6, 1).millisecondsSinceEpoch,
      });
      // 备注不像退款的负数行是用户有意为之，也不猜。
      final manualId = await insertLegacyRow({
        'book_id': bookId,
        'kind': 'expense',
        'amount': '-500',
        'category_id': null,
        'account_id': accountId,
        'note': '手工冲账调整',
        'date_ms': DateTime(2026, 6, 1).millisecondsSinceEpoch,
      });

      repo = await freshRepo();
      await repo.closeForTest();
      final income = await rawRow(incomeId);
      expect(income['kind'], 'income');
      expect(income['refund_of'], isNull);
      expect(income['amount'], '500');
      final manual = await rawRow(manualId);
      expect(manual['refund_of'], isNull);
      expect(manual['note'], '手工冲账调整');
    });
  });
}
