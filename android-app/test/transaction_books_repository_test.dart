import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/app_clock.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/data/transaction_book_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  late AppRepository repo;
  late int total, business, project, account;
  final date = DateTime(AppClock.now.year, AppClock.now.month, 1, 10);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('feimiao-membership-');
    await databaseFactory.setDatabasesPath(dir.path);
    repo = AppRepository();
    await repo.init();
    total = repo.defaultBookId;
    business = await repo.addBook(name: '生意');
    project = await repo.addBook(name: '项目 A');
    account = repo.transactionAccounts.first.id;
  });
  tearDown(() async {
    await repo.closeForTest();
    dir.deleteSync(recursive: true);
  });
  Future<int> spend({int? owner, Iterable<int>? books}) => repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        accountId: account,
        date: date,
        bookId: owner ?? total,
        bookIds: books,
      );
  Decimal sum(int book) =>
      repo.recordsForBookView(book).fold(Decimal.zero, (a, b) => a + b.amount);
  Future<void> reopen() async {
    await repo.closeForTest();
    repo = AppRepository();
    await repo.init();
  }

  test('历史账单可同时归集两个场景，总账本/账户只算一次', () async {
    final id = await spend();
    final before =
        repo.accountBalanceOf(repo.accounts.firstWhere((a) => a.id == account));
    await repo.setTransactionBooks([id, id], [business, project, business]);
    expect(sum(total), Decimal.fromInt(100));
    expect(sum(business), Decimal.fromInt(100));
    expect(sum(project), Decimal.fromInt(100));
    expect(repo.allTransactions.length, 1);
    expect(repo.recordsForBookViews([business, project]).single.amount,
        Decimal.fromInt(100));
    expect(repo.visibleTransactionsForBookViews([business, project]).length, 1);
    expect(
        repo.accountBalanceOf(repo.accounts.firstWhere((a) => a.id == account)),
        before);
    await reopen();
    expect(sum(project), Decimal.fromInt(100));
    expect(repo.transactionById(id)!.bookId, total);
  });

  test('显式移除旧归属覆盖book_id，最后一个移除仅总账本保留', () async {
    final id = await spend(owner: business);
    await repo.setTransactionBooks([id], [project], addOnly: true);
    await repo.setTransactionBooks([id], [business], removeOnly: true);
    expect(sum(business), Decimal.zero);
    expect(sum(project), Decimal.fromInt(100));
    await repo.setTransactionBooks([id], [project], removeOnly: true);
    expect(sum(total), Decimal.fromInt(100));
    expect(sum(project), Decimal.zero);
    await reopen();
    expect(sum(business), Decimal.zero);
    expect(repo.transactionById(id)!.bookId, business);
  });

  test('退款继承原单归集；预算、记录流按家族净额且不重复', () async {
    final id = await spend(owner: business);
    await repo.refundTransaction(repo.transactionById(id)!, Decimal.fromInt(30),
        settledAt: date, settlementAccountId: account);
    final refund = repo.allTransactions.singleWhere((t) => t.refundOf == id);
    await repo.setTransactionBooks([refund.id, id], [business, project]);
    expect(sum(total), Decimal.fromInt(70));
    expect(sum(project), Decimal.fromInt(70));
    expect(repo.budgetSpendByDay(project).values.single, 7000);
    await repo.switchBook(project);
    expect(repo.transactions.length, 2);
    expect(repo.visibleTransactionsForBookView(project).length, 1);
    expect(repo.allRecords.single.amount, Decimal.fromInt(70));
  });

  test('归集后再退款，也按原单集合展示', () async {
    final id = await spend();
    await repo.setTransactionBooks([id], [project]);
    await repo.refundTransaction(repo.transactionById(id)!, Decimal.fromInt(25),
        settledAt: date, settlementAccountId: account);
    expect(sum(project), Decimal.fromInt(75));
    await reopen();
    expect(sum(project), Decimal.fromInt(75));
  });

  test('新建和编辑账单多选与财务更新在同一事务', () async {
    final id = await spend(books: [business, project]);
    expect(sum(project), Decimal.fromInt(100));
    await repo.updateTransaction(
        id: id,
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(80),
        accountId: account,
        date: date,
        bookIds: [project]);
    expect(sum(business), Decimal.zero);
    expect(sum(project), Decimal.fromInt(80));
    await expectLater(
        repo.updateTransaction(
            id: id,
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(99),
            accountId: account,
            date: date,
            bookIds: [-999]),
        throwsStateError);
    expect(sum(project), Decimal.fromInt(80));
  });

  test('批量旧账失效/账本失效时整批回滚', () async {
    final id = await spend();
    await expectLater(
        repo.setTransactionBooks([id, -99], [project]), throwsStateError);
    expect(sum(project), Decimal.zero);
    await expectLater(
        repo.setTransactionBooks([id], [project, -99]), throwsStateError);
    expect(sum(project), Decimal.zero);
    await expectLater(
        repo.setTransactionBooks([id], [project],
            addOnly: true, removeOnly: true),
        throwsArgumentError);
  });

  test('删除场景只解除该关联，其他账本与原单/账户保留', () async {
    final id = await spend(owner: business, books: [business, project]);
    final before =
        repo.accountBalanceOf(repo.accounts.firstWhere((a) => a.id == account));
    await repo.deleteBook(business);
    expect(repo.transactionById(id), isNotNull);
    expect(sum(project), Decimal.fromInt(100));
    expect(sum(total), Decimal.fromInt(100));
    expect(
        repo.accountBalanceOf(repo.accounts.firstWhere((a) => a.id == account)),
        before);
    expect(repo.transactionBookIds(repo.transactionById(id)!),
        isNot(contains(business)));
  });

  test('删除当前场景写库失败时恢复关联、原账和当前选择', () async {
    final id = await spend(owner: business, books: [business, project]);
    await repo.switchBook(business);
    final rows = await repo.debugDb.query('transactions');
    final links = await repo.debugDb.query('transaction_books');
    await repo.debugDb.execute('''
      CREATE TRIGGER membership_delete_failure BEFORE INSERT ON app_settings
      WHEN NEW.key = 'current_book_id'
      BEGIN SELECT RAISE(ABORT, 'simulated failure'); END
    ''');
    await expectLater(
        repo.deleteBook(business), throwsA(isA<DatabaseException>()));
    expect(repo.currentBookId, business);
    expect(await repo.debugDb.query('transactions'), rows);
    expect(await repo.debugDb.query('transaction_books'), links);
    expect(repo.transactionById(id)!.bookIds, containsAll([business, project]));
    expect(repo.books.map((b) => b.id), contains(business));
    await repo.debugDb.execute('DROP TRIGGER membership_delete_failure');
    await reopen();
    expect(repo.currentBookId, business);
  });

  test('v50升级只新建空关联表；原行和账户逐字段等价，重复打开不重写', () async {
    final id = await spend(owner: business);
    final before = await repo.debugDb.query('transactions');
    final accounts = await repo.debugDb.query('accounts');
    await repo.closeForTest();
    final db =
        await databaseFactory.openDatabase(p.join(dir.path, 'qingji.db'));
    await db.execute('DROP TABLE transaction_books');
    await db.execute('PRAGMA user_version = 50');
    await db.close();
    repo = AppRepository();
    await repo.init();
    expect(await repo.debugDb.query('transactions'), before);
    expect(await repo.debugDb.query('accounts'), accounts);
    expect(await repo.debugDb.query('transaction_books'), isEmpty);
    expect(repo.transactionBookIds(repo.transactionById(id)!), {business});
    expect(
        File(p.join(dir.path, 'qingji.db.pre-v50.bak')).existsSync(), isTrue);
    await TransactionBookStore.ensureSchema(repo.debugDb);
    await reopen();
    expect(await repo.debugDb.query('transactions'), before);
  });

  test('旧排除开关不再隐藏账单，场景独立统计不相加成总账本', () async {
    await repo.updateBook(business, includeInTotal: false);
    await spend(owner: business);
    expect(sum(total), Decimal.fromInt(100));
    expect(sum(business), Decimal.fromInt(100));
  });

  test('原账全局删除同时清理关联，不留孤儿映射', () async {
    final id = await spend(books: [business, project]);
    await repo.deleteTransaction(id);
    expect(await repo.debugDb.query('transaction_books'), isEmpty);
    expect(sum(total), Decimal.zero);
  });

  test('CSV导入恢复多个场景；重复导入只合并关联不复制原账', () async {
    const firstUUID = '11111111111111111111111111111111';
    const secondUUID = '22222222222222222222222222222222';
    const txUUID = 'abcdefabcdefabcdefabcdefabcdefab';
    FeimiaoImportRow row(List<String> uuids, List<String> names) =>
        FeimiaoImportRow(
            uuid: txUUID,
            kind: TransactionKind.expense,
            amount: Decimal.fromInt(100),
            refunded: Decimal.zero,
            date: date,
            bookUuids: uuids,
            bookNames: names);
    final result = await repo.importFeimiaoExportRows([
      row([firstUUID, secondUUID], ['生意导入', '项目导入']),
    ]);
    expect(result.inserted, 1);
    final first = repo.books.singleWhere((b) => b.uuid == firstUUID).id;
    final second = repo.books.singleWhere((b) => b.uuid == secondUUID).id;
    expect(sum(first), Decimal.fromInt(100));
    expect(sum(second), Decimal.fromInt(100));
    await repo.importFeimiaoExportRows([
      row([firstUUID], ['生意导入'])
    ]);
    expect(repo.allTransactions.length, 1);
    expect(sum(second), Decimal.fromInt(100));
    await reopen();
    expect(sum(second), Decimal.fromInt(100));
  });

  test('旧CSV重复导入到新场景只加关联，账户不重复扣款', () async {
    final original = await spend();
    await repo.switchBook(project);
    final row = FeimiaoImportRow(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        refunded: Decimal.zero,
        date: date);
    final result = await repo.importFeimiaoExportRows([row]);
    expect(result.inserted, 0);
    expect(repo.allTransactions.length, 1);
    expect(repo.transactionById(original)!.bookIds, contains(project));
  });

  test('CSV明确空集合不继承当前场景；同名歧义整批回滚', () async {
    await repo.switchBook(project);
    final row = FeimiaoImportRow(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        refunded: Decimal.zero,
        date: date,
        bookUuids: const [],
        bookNames: const []);
    await repo.importFeimiaoExportRows([row]);
    expect(sum(project), Decimal.zero);
    expect(sum(total), Decimal.fromInt(100));
    await repo.addBook(name: '同名');
    await repo.addBook(name: '同名');
    final before = await repo.debugDb.query('transactions');
    final invalid = FeimiaoImportRow(
        uuid: '33333333333333333333333333333333',
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(50),
        refunded: Decimal.zero,
        date: date,
        bookNames: const ['同名']);
    await expectLater(
        repo.importFeimiaoExportRows([invalid]), throwsFormatException);
    expect(await repo.debugDb.query('transactions'), before);
  });

  test('完整数据库备份恢复保留关联、原始行及退款家族', () async {
    final id = await spend(books: [business, project]);
    await repo.refundTransaction(repo.transactionById(id)!, Decimal.fromInt(20),
        settledAt: date, settlementAccountId: account);
    final backup = await repo.createLocalBackupNow();
    expect(backup, isNotNull);
    await repo.setTransactionBooks([id], []);
    expect(sum(project), Decimal.zero);
    expect(await repo.restoreDatabaseFromFile(backup!.path), isTrue);
    expect(sum(project), Decimal.fromInt(80));
    expect(sum(total), Decimal.fromInt(80));
    expect(repo.allTransactions.length, 2);
  });

  test('1201笔批量归集跨SQL参数上限且失败不留下部分关联', () async {
    final ids = await repo.addTransactionDraftsAtomically([
      for (var i = 0; i < 1201; i++)
        TransactionDraft(
            kind: TransactionKind.expense,
            amount: Decimal.one,
            date: date,
            accountId: account,
            note: '批量$i'),
    ]);
    await repo.setTransactionBooks(ids, [business]);
    expect(repo.recordsForBookView(business), hasLength(1201));
    await expectLater(
        repo.setTransactionBooks([...ids, -999], [project]), throwsStateError);
    expect(repo.recordsForBookView(project), isEmpty);
    expect(repo.recordsForBookView(business), hasLength(1201));
    await repo.setTransactionBooks(ids, [project], addOnly: true);
    expect(repo.recordsForBookViews([business, project]), hasLength(1201));
    await repo.setTransactionBooks(ids, [business], removeOnly: true);
    expect(repo.recordsForBookView(business), isEmpty);
    expect(sum(project), Decimal.fromInt(1201));
    await reopen();
    expect(sum(project), Decimal.fromInt(1201));
    expect(sum(total), Decimal.fromInt(1201));
  });

  test('并发追加两个场景不丢失关联且余额不变', () async {
    final id = await spend();
    final balance =
        repo.accountBalanceOf(repo.accounts.firstWhere((a) => a.id == account));
    await Future.wait([
      repo.setTransactionBooks([id], [business], addOnly: true),
      repo.setTransactionBooks([id], [project], addOnly: true),
    ]);
    await reopen();
    expect(repo.transactionById(id)!.bookIds, containsAll([business, project]));
    expect(
        repo.accountBalanceOf(repo.accounts.firstWhere((a) => a.id == account)),
        balance);
  });

  test('iOS连字符UUID与Android紧凑UUID往返不复制账单和账本', () async {
    const compact = 'abcdefabcdefabcdefabcdefabcdefab';
    const ios = 'ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB';
    final scene = repo.books.singleWhere((b) => b.id == project);
    final sceneUuid = scene.uuid;
    final sceneIos =
        '${sceneUuid.substring(0, 8)}-${sceneUuid.substring(8, 12)}-'
        '${sceneUuid.substring(12, 16)}-${sceneUuid.substring(16, 20)}-'
        '${sceneUuid.substring(20)}';
    FeimiaoImportRow row(String uuid, String bookUuid) => FeimiaoImportRow(
        uuid: uuid,
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        refunded: Decimal.zero,
        date: date,
        bookUuids: [bookUuid],
        bookNames: [scene.name]);
    await repo.importFeimiaoExportRows([row(ios, sceneIos.toUpperCase())]);
    expect(repo.allTransactions, hasLength(1));
    expect(repo.books, hasLength(3));
    await repo.importFeimiaoExportRows([row(compact, sceneUuid)]);
    expect(repo.allTransactions, hasLength(1));
    expect(repo.books, hasLength(3));
    expect(sum(project), Decimal.fromInt(100));
  });

  test('快速启动按覆盖关联查询，移出旧来源账本不会复活', () async {
    final id = await spend(owner: business);
    await repo.setTransactionBooks([id], [project]);
    await repo.switchBook(project);
    await repo.closeForTest();
    repo = AppRepository();
    final initialization = repo.init(fastStartup: true);
    await repo.ready;
    expect(repo.currentBookId, project);
    expect(repo.transactions.map((t) => t.id), contains(id));
    await repo.finishDeferredInitialization();
    await initialization;
    await repo.switchBook(business);
    await repo.closeForTest();
    repo = AppRepository();
    final second = repo.init(fastStartup: true);
    await repo.ready;
    expect(repo.currentBookId, business);
    expect(repo.transactions.map((t) => t.id), isNot(contains(id)));
    await repo.finishDeferredInitialization();
    await second;
    expect(repo.transactions.map((t) => t.id), isNot(contains(id)));
  });

  test('归集和移出不改既有物品成本链，退款仍只冲减一次', () async {
    final id = await spend(owner: business);
    final asset = await repo.addPhysicalAssetFromTransaction(
        transactionId: id, name: '经营工具', allocatedGrossCents: 10000);
    final before = await repo.debugDb.query('asset_transaction_links');
    await repo.setTransactionBooks([id], [project]);
    expect(await repo.debugDb.query('asset_transaction_links'), before);
    await repo.refundTransaction(repo.transactionById(id)!, Decimal.fromInt(20),
        settledAt: date, settlementAccountId: account);
    expect(repo.physicalAssetDetailById(asset)!.purchasePrice,
        Decimal.fromInt(80));
    await reopen();
    expect(repo.physicalAssetDetailById(asset)!.purchasePrice,
        Decimal.fromInt(80));
    expect(sum(project), Decimal.fromInt(80));
    expect(sum(business), Decimal.zero);
  });

  test('总账单全量不扩大资产旧范围，资产来源锚点和场景资格独立', () async {
    await repo.updateBook(business, includeInTotal: false);
    final id = await spend(owner: business);
    expect(
        repo.eligiblePhysicalAssetPurchaseTransactions(bookId: total), isEmpty);
    await repo.setTransactionBooks([id], [project]);
    expect(
        repo.eligiblePhysicalAssetPurchaseTransactions(bookId: total), isEmpty);
    expect(repo.eligiblePhysicalAssetPurchaseTransactions(bookId: project),
        hasLength(1));
    expect(repo.eligiblePhysicalAssetPurchaseTransactions(bookId: business),
        hasLength(1));
    final asset = await repo.addPhysicalAssetFromTransaction(
        transactionId: id, name: '旧来源物品', allocatedGrossCents: 10000);
    expect(repo.physicalAssets.map((a) => a.id), isNot(contains(asset)));
    expect(repo.physicalAssetDetailById(asset), isNotNull);
    expect(sum(total), Decimal.fromInt(100));
  });
}
