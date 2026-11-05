// 已有账单编号重复的自动修复：旧版 Android 用不带种子的 Random() 生成编号，
// 两笔账单可能用着同一个编号。打开 App 时查一次，有重复就先备份，再让时间新
// 的那笔留原编号、其余按导入时同一公式换新编号；金额、日期、备注、账本、退款
// 都不动，不删除也不合并；资产凭证和余额核对里按编号找账单的地方跟着改。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/account/account_movement_projection.dart';
import 'package:qingji/core/account/liability_balance_mode.dart';
import 'package:qingji/core/budget/budget_rules.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/transaction_time.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  const markerKey = 'transaction_uuid_duplicates_checked_v1';
  const noticeKey = 'transaction_uuid_duplicates_notice_v1';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_uuid_repair_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() async {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppRepository> openRepo() async {
    final repo = AppRepository();
    await repo.init();
    return repo;
  }

  // 和导入时一样：sha256('feimiao-dup:<原编号>:<序号>') 的前 32 位。
  String derivedUuid(String root, int rank) => sha256
      .convert(utf8.encode('feimiao-dup:$root:$rank'))
      .toString()
      .substring(0, 32);

  /// 模拟旧版撞号：把 [fromId] 的编号写到 [toId] 上。[checked] 为 false 时
  /// 去掉「查过」标记，就像刚从旧版升级上来。
  Future<String> collide(
    AppRepository repo, {
    required int fromId,
    required int toId,
    bool checked = false,
  }) async {
    final db = repo.debugDb;
    final uuid = (await db.query('transactions',
            columns: ['uuid'], where: 'id = ?', whereArgs: [fromId]))
        .single['uuid'] as String;
    await db.update('transactions', {'uuid': uuid},
        where: 'id = ?', whereArgs: [toId]);
    await db.delete('app_settings',
        where: 'key IN (?, ?)', whereArgs: [markerKey, noticeKey]);
    if (checked) {
      await db.insert('app_settings', {'key': markerKey, 'value': '1'});
    }
    return uuid;
  }

  Future<Map<int, Map<String, Object?>>> rowsById(Database db) async => {
        for (final row in await db.query('transactions', orderBy: 'id'))
          row['id'] as int: row,
      };

  Future<String?> setting(AppRepository repo, String key) async =>
      (await repo.debugDb.query('app_settings',
              columns: ['value'], where: 'key = ?', whereArgs: [key]))
          .firstOrNull?['value'] as String?;

  test('两笔账单编号重复：时间新的留原编号，另一笔按导入公式换新编号，其余不动', () async {
    var repo = await openRepo();
    final account = repo.accounts.first.id;
    final lunch = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(20),
        accountId: account,
        note: '午饭',
        date: DateTime(2026, 7, 1, 12));
    final dinner = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(30),
        accountId: account,
        note: '晚饭',
        date: DateTime(2026, 7, 2, 19));
    // 编号重复的那笔是先记的午饭（id 小）；修复按时间，不按 id。
    final shared = await collide(repo, fromId: dinner, toId: lunch);
    final before = await rowsById(repo.debugDb);
    await repo.closeForTest();

    repo = await openRepo();
    final after = await rowsById(repo.debugDb);
    expect(after.keys, before.keys, reason: '不删除、不合并、不新增');
    expect(after[dinner]!['uuid'], shared, reason: '时间新的晚饭留原编号');
    expect(after[lunch]!['uuid'], derivedUuid(shared, 1),
        reason: '和导入时同一公式，导到 iOS、再导回都认得出');
    for (final id in before.keys) {
      expect({...after[id]!}..remove('uuid'), {...before[id]!}..remove('uuid'),
          reason: '只换编号，金额、日期、备注、账本、修改时间都不动');
    }
    expect(await setting(repo, noticeKey), '1', reason: '提示一次：换了 1 笔');
    expect(await setting(repo, markerKey), '1');

    // 修之前先备份，备份里还是修之前的样子。
    final backup = File(p.join(tmp.path, 'qingji.db.pre-uuid-repair.bak'));
    expect(backup.existsSync(), isTrue);
    final copy = await databaseFactory.openDatabase(backup.path);
    expect((await rowsById(copy))[lunch]!['uuid'], shared);
    await copy.close();

    // 再打开不会再改，也不会再出备份。
    backup.deleteSync();
    await repo.debugDb
        .delete('app_settings', where: 'key = ?', whereArgs: [noticeKey]);
    await repo.closeForTest();
    repo = await openRepo();
    expect(await rowsById(repo.debugDb), after);
    expect(await setting(repo, noticeKey), isNull);
    expect(backup.existsSync(), isFalse);
    await repo.closeForTest();
  });
  test('原账单编号重复时，退款只冲减它自己那笔，预算已花不少算', () async {
    var repo = await openRepo();
    final book = repo.currentBookId;
    final account = repo.accounts.first.id;
    await repo.saveBudgetRule(
      bookId: book,
      kind: BudgetRuleKind.base,
      amountYuan: 3000,
      unit: BudgetRuleUnit.month,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final big = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(100),
        accountId: account,
        note: '大的',
        date: now.subtract(const Duration(minutes: 3)));
    final small = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(50),
        accountId: account,
        note: '小的',
        date: now.subtract(const Duration(minutes: 2)));
    await repo.refundTransaction(
      repo.transactionById(big)!,
      Decimal.fromInt(30),
      settledAt: now.subtract(const Duration(minutes: 1)),
      settlementAccountId: account,
    );
    // 100 - 30 + 50
    expect(repo.budgetRuleMonth(today).spentAmount, Decimal.fromInt(120));
    await collide(repo, fromId: small, toId: big);
    await repo.closeForTest();

    // 旧版：两笔原账单同一个编号，30 元退款同时冲减了两笔，只算 90。
    repo = await openRepo();
    expect(repo.budgetRuleMonth(today).spentAmount, Decimal.fromInt(120));
    await repo.closeForTest();
  });

  for (final otherIsNewer in [true, false]) {
    test(
        '收回利息和别的账单编号重复（${otherIsNewer ? '别的账单' : '利息'}时间新）：'
        '撤销收回仍找得到利息，别的账单照常能删', () async {
      var repo = await openRepo();
      final account = repo.accounts.first;
      // 先记的咖啡 id 小，旧版按编号只取一笔时会先找到它。
      final coffee = await repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(15),
          accountId: account.id,
          note: '咖啡',
          date: DateTime(2026, 7, otherIsNewer ? 21 : 19, 9));
      final balanceBefore = repo.accountBalanceOf(repo.accounts.first);
      final assetId = await repo.addReceivableAsset(
        name: '借给张三',
        type: ReceivableAssetType.loanOut,
        originalAmount: Decimal.fromInt(1000),
      );
      await repo.recoverReceivableAsset(
        id: assetId,
        amount: Decimal.fromInt(1000),
        targetAccountId: account.id,
        interestAmount: Decimal.fromInt(30),
        recoveredAt: DateTime(2026, 7, 20),
      );
      final interest = repo.visibleTransactions
          .singleWhere((t) => t.txKind == TransactionKind.income && !t.excluded)
          .id;
      await collide(repo, fromId: interest, toId: coffee);
      await repo.closeForTest();

      repo = await openRepo();
      // 旧版：咖啡被当成收回来的利息，删不掉；撤销收回找到的是咖啡，对不上。
      expect(await repo.transactionMutationBlockReason(coffee), isNull);
      expect(await repo.transactionMutationBlockReason(interest), isNotNull);
      await repo.undoReceivableRecovery(repo.receivableRecoveries.single.id);
      expect(repo.visibleTransactions.map((t) => t.id), [coffee]);
      expect(repo.accountBalanceOf(repo.accounts.first), balanceBefore);
      await repo.closeForTest();
    });
  }

  for (final billsAreNewer in [true, false]) {
    test(
        '还款的本金转账、利息和别的账单编号重复（${billsAreNewer ? '别的账单' : '还款'}时间新）：'
        '撤销还款仍找得到两笔，别的账单照常能删', () async {
      var repo = await openRepo();
      final payer = await repo.addAccount(
          name: '测试还款账户', openingBalance: Decimal.fromInt(2000));
      final loan = await repo.addAccount(
          name: '测试借入账户',
          type: AccountType.loan,
          openingBalance: Decimal.fromInt(-500));
      final profile = await repo.upsertLiabilityProfile(
        accountId: loan,
        type: LiabilityProfileType.personalBorrow,
        originalAmount: Decimal.fromInt(500),
        currentPrincipal: Decimal.fromInt(500),
        repaymentAccountId: payer,
        counterparty: '测试对象',
      );
      await repo.setAccountBalanceMode(loan, LiabilityBalanceMode.ledger);
      final paidAt = DateTime(2026, 7, 20);
      final billAt = paidAt.add(Duration(days: billsAreNewer ? 1 : -1));
      final coffee = await repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(15),
          accountId: payer,
          note: '咖啡',
          date: billAt);
      final tea = await repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(8),
          accountId: payer,
          note: '奶茶',
          date: billAt);
      final payerBefore = repo
          .accountBalanceOf(repo.accounts.singleWhere((a) => a.id == payer));
      // 还 520：本金转账 500，利息 20。
      final paid = await repo.repayLiabilityProfile(
          profileId: profile,
          amount: Decimal.fromInt(520),
          fromAccountId: payer,
          date: paidAt);
      final transfer = paid.transferTransactionId!;
      final interest = paid.interestTransactionId!;
      await collide(repo, fromId: transfer, toId: coffee);
      await collide(repo, fromId: interest, toId: tea);
      await repo.closeForTest();

      repo = await openRepo();
      // 旧版：咖啡、奶茶被当成还款流水，删不掉。
      expect(await repo.transactionMutationBlockReason(coffee), isNull);
      expect(await repo.transactionMutationBlockReason(tea), isNull);
      expect(await repo.transactionMutationBlockReason(transfer), isNotNull);
      expect(await repo.transactionMutationBlockReason(interest), isNotNull);
      await repo.undoLiabilityRepayment(
          repo.liabilityRepaymentEventForTransaction(transfer)!.id);
      expect(repo.visibleTransactions.map((t) => t.id).toSet(), {coffee, tea});
      expect(
          repo.accountBalanceOf(
              repo.accounts.singleWhere((a) => a.id == payer)),
          payerBefore,
          reason: '撤销后回到还款前');
      await repo.closeForTest();
    });
  }
  test('余额核对吸收过的到账时间未知账单，换编号后仍算已吸收，余额不变', () async {
    var repo = await openRepo();
    final account = repo.accounts.first.id;
    final lunch = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(20),
        accountId: account,
        note: '午饭',
        date: DateTime(2026, 7, 1, 12));
    final dinner = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(30),
        accountId: account,
        note: '晚饭',
        date: DateTime(2026, 7, 2, 19));
    // 两笔都不知道哪天到账、账户已确认：核对时会被吸收。
    await repo.debugDb.update(
        'transactions',
        {
          'settled_ms': null,
          'settlement_quality': SettlementQuality.unknown.storageKey,
          'settlement_account_id': account,
          'settlement_account_quality': SettlementQuality.exact.storageKey,
        },
        where: 'id IN (?, ?)',
        whereArgs: [lunch, dinner]);
    // 撞号发生在核对之前；先标成查过，让核对在重复编号下进行。
    final shared =
        await collide(repo, fromId: dinner, toId: lunch, checked: true);
    await repo.closeForTest();
    repo = await openRepo();
    await repo.createAccountBalanceCheckpoint(
      accountId: account,
      targetBalance: Decimal.fromInt(500),
    );
    final balance = repo.accountBalanceOf(repo.accounts.first);
    expect(balance, Decimal.fromInt(500));
    await repo.debugDb
        .delete('app_settings', where: 'key = ?', whereArgs: [markerKey]);
    await repo.closeForTest();

    repo = await openRepo();
    expect(repo.accountBalanceOf(repo.accounts.first), balance);
    final covered =
        (await repo.debugDb.query('account_checkpoint_covered_unknown_events'))
            .map((row) => row['account_event_uuid'])
            .toSet();
    expect(covered, {shared, derivedUuid(shared, 1)});
    await repo.closeForTest();
  });

  test('修好以后，再导入修之前导出的表，不多出账单', () async {
    var repo = await openRepo();
    final account = repo.accounts.first;
    final category =
        repo.categoriesForKindRanked(TransactionKind.expense).first;
    final lunch = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(20),
        categoryId: category.id,
        accountId: account.id,
        note: '午饭',
        date: DateTime(2026, 7, 1, 12));
    final dinner = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(30),
        categoryId: category.id,
        accountId: account.id,
        note: '晚饭',
        date: DateTime(2026, 7, 2, 19));
    final shared = await collide(repo, fromId: dinner, toId: lunch);
    await repo.closeForTest();

    repo = await openRepo();
    FeimiaoImportRow row(String note, String amount, DateTime date) =>
        FeimiaoImportRow(
          uuid: shared,
          refundOfUuid: '',
          role: 'transaction',
          kind: TransactionKind.expense,
          amount: Decimal.parse(amount),
          refunded: Decimal.zero,
          categoryKey: category.key,
          categoryName: category.nameZh,
          accountName: account.name,
          note: note,
          date: date,
          timePrecision: TransactionTimePrecision.exact,
        );
    // 修之前导出的表：两行同一个编号，时间新的在前。
    final result = await repo.importFeimiaoExportRows([
      row('晚饭', '30', DateTime(2026, 7, 2, 19)),
      row('午饭', '20', DateTime(2026, 7, 1, 12)),
    ]);
    expect(result.inserted, 0);
    expect(result.skippedDuplicates, 2);
    expect({for (final t in repo.visibleTransactions) t.note: t.uuid},
        {'晚饭': shared, '午饭': derivedUuid(shared, 1)});
    await repo.closeForTest();
  });

  test('没有重复编号：不备份、不提示、不改任何账单，只记一次查过', () async {
    var repo = await openRepo();
    final account = repo.accounts.first.id;
    for (var i = 0; i < 3; i++) {
      await repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(10 + i),
          accountId: account,
          date: DateTime(2026, 7, 1 + i, 12));
    }
    await repo.debugDb
        .delete('app_settings', where: 'key = ?', whereArgs: [markerKey]);
    final before = await rowsById(repo.debugDb);
    await repo.closeForTest();

    repo = await openRepo();
    expect(await rowsById(repo.debugDb), before);
    expect(await setting(repo, markerKey), '1');
    expect(await setting(repo, noticeKey), isNull);
    expect(File(p.join(tmp.path, 'qingji.db.pre-uuid-repair.bak')).existsSync(),
        isFalse);
    await repo.closeForTest();
  });

  test('修复中途出错：一笔都不改，照常打开；下次打开再修好', () async {
    var repo = await openRepo();
    final account = repo.accounts.first.id;
    final ids = <int>[];
    for (final (note, day) in [('早饭', 1), ('午饭', 2), ('晚饭', 3)]) {
      ids.add(await repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.fromInt(10 * day),
          accountId: account,
          note: note,
          date: DateTime(2026, 7, day, 12)));
    }
    final shared = await collide(repo, fromId: ids[2], toId: ids[0]);
    await collide(repo, fromId: ids[2], toId: ids[1]);
    final before = await rowsById(repo.debugDb);
    await repo.closeForTest();

    // 三笔同号要换两笔；换完第一笔就出错，整批退回，一笔都不改。
    repo = AppRepository()..debugFailUuidRepairAfterFirstUpdate = true;
    await repo.init();
    expect(repo.isReady, isTrue, reason: '修不好也照常打开 App');
    expect(await rowsById(repo.debugDb), before);
    expect(await setting(repo, markerKey), 'failed:1');
    expect(await setting(repo, noticeKey), isNull);
    expect(repo.uuidDuplicatesNoticeCount, 0);
    await repo.closeForTest();

    repo = await openRepo();
    final after = await rowsById(repo.debugDb);
    expect(after.keys, before.keys);
    expect(after[ids[2]]!['uuid'], shared, reason: '时间新的晚饭留原编号');
    expect(after[ids[1]]!['uuid'], derivedUuid(shared, 1));
    expect(after[ids[0]]!['uuid'], derivedUuid(shared, 2));
    expect(await setting(repo, markerKey), '1');
    expect(repo.uuidDuplicatesNoticeCount, 2);
    await repo.closeForTest();
  });

  test('连续 3 次没修好就不再每次启动都试；不到 3 次照常再试', () async {
    var repo = await openRepo();
    final account = repo.accounts.first.id;
    final lunch = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(20),
        accountId: account,
        date: DateTime(2026, 7, 1, 12));
    final dinner = await repo.addTransaction(
        kind: TransactionKind.expense,
        amount: Decimal.fromInt(30),
        accountId: account,
        date: DateTime(2026, 7, 2, 19));
    final shared = await collide(repo, fromId: dinner, toId: lunch);
    await repo.debugDb
        .insert('app_settings', {'key': markerKey, 'value': 'failed:3'});
    final before = await rowsById(repo.debugDb);
    await repo.closeForTest();

    repo = await openRepo();
    expect(await rowsById(repo.debugDb), before);
    expect(await setting(repo, markerKey), 'failed:3');
    expect(File(p.join(tmp.path, 'qingji.db.pre-uuid-repair.bak')).existsSync(),
        isFalse);

    await repo.debugDb.update('app_settings', {'value': 'failed:2'},
        where: 'key = ?', whereArgs: [markerKey]);
    await repo.closeForTest();
    repo = await openRepo();
    final after = await rowsById(repo.debugDb);
    expect(after[dinner]!['uuid'], shared);
    expect(after[lunch]!['uuid'], derivedUuid(shared, 1));
    expect(await setting(repo, markerKey), '1');
    await repo.closeForTest();
  });
}
