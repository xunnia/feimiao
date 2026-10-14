import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/account/liability_balance_mode.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Decimal money(String value) => Decimal.parse(value);

Decimal accountBalance(AppRepository repo, int id) => repo
    .accountBalanceOf(repo.accounts.singleWhere((account) => account.id == id));

LiabilityProfileEntity profileById(AppRepository repo, int id) =>
    repo.liabilityProfiles.singleWhere((profile) => profile.id == id);

Map<String, Object?> moneyState(AppRepository repo) => {
      'balances': {
        for (final account in repo.accounts)
          account.id: repo.accountBalanceOf(account).toString(),
      },
      'net_worth': repo.currentNetWorthBreakdown().netWorth.toString(),
      'profiles': {
        for (final profile in repo.liabilityProfiles)
          profile.id: (
            profile.uuid,
            profile.originalAmount.toString(),
            profile.currentPrincipal.toString(),
            profile.status.name,
            profile.note,
          ),
      },
      'receivables': {
        for (final asset in repo.receivableAssets)
          asset.id: (
            asset.uuid,
            asset.originalAmount.toString(),
            asset.remainingAmount.toString(),
            asset.economicStatus.name,
            asset.visibilityStatus.name,
            asset.includeInNetWorth,
            asset.endedMs,
          ),
      },
      'recoveries': [
        for (final recovery in repo.receivableRecoveries)
          (
            recovery.id,
            recovery.uuid,
            recovery.receivableAssetId,
            recovery.amount.toString(),
            recovery.recoveredMs,
            recovery.targetAccountId,
            recovery.eventId,
            recovery.transactionId,
          ),
      ],
      'transactions': [
        for (final transaction in repo.transactions)
          (
            transaction.id,
            transaction.uuid,
            transaction.txKind.name,
            transaction.amount.toString(),
            transaction.accountId,
            transaction.toAccountId,
            transaction.dateMs,
            transaction.note,
            transaction.excluded,
          ),
      ],
    };

AssetEventEntity repaymentEvent(AppRepository repo, int transactionId) {
  final event = repo.liabilityRepaymentEventForTransaction(transactionId);
  expect(event, isNotNull);
  expect(event!.eventType, AssetEventType.liabilityRepaid);
  expect(event.assetType, AssetObjectType.liability);
  return event;
}

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qingji_finance_command_test_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppRepository> freshRepo() async {
    final repo = AppRepository();
    addTearDown(repo.closeForTest);
    await repo.init();
    return repo;
  }

  Future<AppRepository> restart(AppRepository repo) async {
    await repo.closeForTest();
    return freshRepo();
  }

  Future<({int payerId, int liabilityId, int profileId})> createDebt(
    AppRepository repo, {
    String balance = '-500',
    String principal = '500',
    LiabilityBalanceMode mode = LiabilityBalanceMode.ledger,
  }) async {
    final payerId = await repo.addAccount(
      name: '测试还款账户',
      openingBalance: money('2000'),
    );
    final liabilityId = await repo.addAccount(
      name: '测试借入账户',
      type: AccountType.loan,
      openingBalance: money(balance),
    );
    final profileId = await repo.upsertLiabilityProfile(
      accountId: liabilityId,
      type: LiabilityProfileType.personalBorrow,
      originalAmount: money(principal),
      currentPrincipal: money(principal),
      repaymentAccountId: payerId,
      counterparty: '测试对象',
    );
    await repo.setAccountBalanceMode(liabilityId, mode);
    return (
      payerId: payerId,
      liabilityId: liabilityId,
      profileId: profileId,
    );
  }

  Future<({int accountId, int receivableId})> createReceivable(
    AppRepository repo,
  ) async {
    final accountId = await repo.addAccount(
      name: '权益到账账户',
      openingBalance: money('2000'),
    );
    final receivableId = await repo.addReceivableAsset(
      name: '测试借出权益',
      type: ReceivableAssetType.loanOut,
      originalAmount: money('1000'),
    );
    return (accountId: accountId, receivableId: receivableId);
  }

  Future<void> withFailureTrigger(
    String eventType,
    Future<void> Function(Database faultDb) body,
  ) async {
    final faultDb = await databaseFactory.openDatabase(
      p.join(tmp.path, 'qingji.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await faultDb.execute('''
        CREATE TRIGGER test_fail_finance_event
        BEFORE INSERT ON asset_events
        WHEN NEW.event_type = '$eventType'
        BEGIN
          SELECT RAISE(ABORT, 'forced finance event failure');
        END
      ''');
      await body(faultDb);
    } finally {
      await faultDb.execute('DROP TRIGGER IF EXISTS test_fail_finance_event');
      await faultDb.close();
    }
  }

  Future<void> removeRecoveryEvidenceFixture(
    AppRepository repo,
    ReceivableRecoveryEntity recovery,
    AssetEventEntity event,
  ) async {
    await repo.closeForTest();
    final fixtureDb = await databaseFactory.openDatabase(
      p.join(tmp.path, 'qingji.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      final transactionsBefore = await fixtureDb.query('transactions');
      await fixtureDb.delete(
        'receivable_recoveries',
        where: 'uuid = ?',
        whereArgs: [recovery.uuid],
      );
      await fixtureDb.delete(
        'asset_events',
        where: 'uuid = ?',
        whereArgs: [event.uuid],
      );
      expect(await fixtureDb.query('transactions'), transactionsBefore);
    } finally {
      await fixtureDb.close();
    }
  }

  test('存钱目标并发增加100和200保存300，重启仍在且不改变资金', () async {
    var repo = await freshRepo();
    await repo.addAccount(name: '测试现金', openingBalance: money('2000'));
    final goalId = await repo.addSavingsGoal(name: '旅行', target: money('1000'));
    final before = moneyState(repo);

    await Future.wait([
      repo.adjustSavingsGoal(goalId, money('100')),
      repo.adjustSavingsGoal(goalId, money('200')),
    ]);

    expect(repo.savingsGoalById(goalId)!.saved, money('300'));
    expect(moneyState(repo), before);
    repo = await restart(repo);
    expect(repo.savingsGoalById(goalId)!.saved, money('300'));
    expect(moneyState(repo), before);
  });

  test('存钱目标增减按分四舍五入、负值钳至零，不制造账户流水', () async {
    var repo = await freshRepo();
    await repo.addAccount(name: '测试现金', openingBalance: money('2000'));
    final goalId = await repo.addSavingsGoal(name: '设备', target: money('1000'));
    final before = moneyState(repo);

    await repo.adjustSavingsGoal(goalId, money('100.005'));
    expect(repo.savingsGoalById(goalId)!.saved, money('100.01'));
    await repo.adjustSavingsGoal(goalId, money('-0.014'));
    expect(repo.savingsGoalById(goalId)!.saved, money('100'));
    await repo.adjustSavingsGoal(goalId, money('-999.99'));
    expect(repo.savingsGoalById(goalId)!.saved, Decimal.zero);
    expect(moneyState(repo), before);
    repo = await restart(repo);
    expect(repo.savingsGoalById(goalId)!.saved, Decimal.zero);
    expect(moneyState(repo), before);
  });

  for (final balance in ['0', '200']) {
    test('旧混合口径余额$balance、本金1000拒绝还款，不写任何资金记录', () async {
      final repo = await freshRepo();
      final debt = await createDebt(
        repo,
        balance: balance,
        principal: '1000',
        mode: LiabilityBalanceMode.legacyHybrid,
      );
      final before = moneyState(repo);
      final eventIds = repo.assetEvents.map((event) => event.uuid).toList();

      await expectLater(
        repo.repayLiabilityProfile(
          profileId: debt.profileId,
          amount: money('200'),
          fromAccountId: debt.payerId,
        ),
        throwsArgumentError,
      );

      expect(moneyState(repo), before);
      expect(repo.assetEvents.map((event) => event.uuid).toList(), eventIds);
      final reopened = await restart(repo);
      expect(moneyState(reopened), before);
    });
  }

  for (final principal in ['800', '1200']) {
    test('旧混合口径欠款1000、档案$principal拒绝还款，不遗留流水', () async {
      final repo = await freshRepo();
      final debt = await createDebt(
        repo,
        balance: '-1000',
        principal: principal,
        mode: LiabilityBalanceMode.legacyHybrid,
      );
      final before = moneyState(repo);

      await expectLater(
        repo.repayLiabilityProfile(
          profileId: debt.profileId,
          amount: money('200'),
          fromAccountId: debt.payerId,
        ),
        throwsArgumentError,
      );

      expect(moneyState(repo), before);
      expect(
        repo.assetEvents.where(
            (event) => event.eventType == AssetEventType.liabilityRepaid),
        isEmpty,
      );
    });
  }

  for (final principal in ['800', '1200']) {
    test('余额口径欠款1000、档案$principal按真实本金还清，不误记利息', () async {
      final repo = await freshRepo();
      final debt =
          await createDebt(repo, balance: '-1000', principal: principal);
      final netWorthBefore = repo.currentNetWorthBreakdown().netWorth;

      final result = await repo.repayLiabilityProfile(
        profileId: debt.profileId,
        amount: money('1000'),
        fromAccountId: debt.payerId,
      );

      expect(result.principalPaid, money('1000'));
      expect(result.interestPaid, Decimal.zero);
      expect(result.interestTransactionId, isNull);
      expect(accountBalance(repo, debt.payerId), money('1000'));
      expect(accountBalance(repo, debt.liabilityId), Decimal.zero);
      expect(profileById(repo, debt.profileId).status,
          LiabilityProfileStatus.paidOff);
      expect(
        profileById(repo, debt.profileId).currentPrincipal,
        principal == '800' ? Decimal.zero : money('200'),
      );
      expect(repo.currentNetWorthBreakdown().netWorth, netWorthBefore);
    });
  }

  test('余额口径档案本金先归零但仍有真实欠款，不能标已还清', () async {
    final repo = await freshRepo();
    final debt = await createDebt(repo, balance: '-1000', principal: '100');

    final result = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('200'),
      fromAccountId: debt.payerId,
    );

    expect(result.principalPaid, money('200'));
    expect(result.interestPaid, Decimal.zero);
    expect(profileById(repo, debt.profileId).currentPrincipal, Decimal.zero);
    expect(profileById(repo, debt.profileId).status,
        LiabilityProfileStatus.active);
    expect(accountBalance(repo, debt.liabilityId), money('-800'));
  });

  test('并发还款100和200在事务内读取最新本金与余额，合计减少300', () async {
    var repo = await freshRepo();
    final debt = await createDebt(repo, balance: '-1000', principal: '1000');
    final netWorthBefore = repo.currentNetWorthBreakdown().netWorth;

    final results = await Future.wait([
      repo.repayLiabilityProfile(
        profileId: debt.profileId,
        amount: money('100'),
        fromAccountId: debt.payerId,
      ),
      repo.repayLiabilityProfile(
        profileId: debt.profileId,
        amount: money('200'),
        fromAccountId: debt.payerId,
      ),
    ]);

    expect(results.map((result) => result.interestPaid),
        everyElement(Decimal.zero));
    expect(accountBalance(repo, debt.payerId), money('1700'));
    expect(accountBalance(repo, debt.liabilityId), money('-700'));
    expect(profileById(repo, debt.profileId).currentPrincipal, money('700'));
    expect(repo.currentNetWorthBreakdown().netWorth, netWorthBefore);
    expect(
      repo.assetEvents
          .where((event) => event.eventType == AssetEventType.liabilityRepaid),
      hasLength(2),
    );
    repo = await restart(repo);
    expect(accountBalance(repo, debt.payerId), money('1700'));
    expect(accountBalance(repo, debt.liabilityId), money('-700'));
    expect(profileById(repo, debt.profileId).currentPrincipal, money('700'));
    expect(repo.currentNetWorthBreakdown().netWorth, netWorthBefore);
  });

  test('贷款资料本金归零后再次还款仍按欠款拆分，不能误记溢缴款', () async {
    var repo = await freshRepo();
    final debt = await createDebt(repo, balance: '-1000', principal: '100');
    final before = repo.currentNetWorthBreakdown().netWorth;
    await repo.repayLiabilityProfile(
        profileId: debt.profileId,
        amount: money('300'),
        fromAccountId: debt.payerId);
    repo = await restart(repo);
    final second = await repo.repayLiabilityProfile(
        profileId: debt.profileId,
        amount: money('720'),
        fromAccountId: debt.payerId);
    expect(second.principalPaid, money('700'));
    expect(second.interestPaid, money('20'));
    expect(accountBalance(repo, debt.liabilityId), Decimal.zero);
    expect(accountBalance(repo, debt.payerId), money('980'));
    expect(profileById(repo, debt.profileId).status,
        LiabilityProfileStatus.paidOff);
    expect(repo.currentNetWorthBreakdown().netWorth, before - money('20'));
    await repo.undoLiabilityRepayment(
        repaymentEvent(repo, second.transferTransactionId!).id);
    expect(accountBalance(repo, debt.liabilityId), money('-700'));
    expect(profileById(repo, debt.profileId).currentPrincipal, Decimal.zero);
    expect(profileById(repo, debt.profileId).status,
        LiabilityProfileStatus.active);
  });

  test('还520拆本金500和利息20，事件关联两笔UUID且整笔撤销恢复', () async {
    final repo = await freshRepo();
    final debt = await createDebt(repo);
    final before = moneyState(repo);

    final result = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('520'),
      fromAccountId: debt.payerId,
    );

    expect(result.principalPaid, money('500'));
    expect(result.interestPaid, money('20'));
    expect(accountBalance(repo, debt.payerId), money('1480'));
    expect(accountBalance(repo, debt.liabilityId), Decimal.zero);
    final event = repaymentEvent(repo, result.transferTransactionId!);
    expect(repaymentEvent(repo, result.interestTransactionId!).id, event.id);
    final metadata = jsonDecode(event.metadata) as Map<String, dynamic>;
    final transfer = repo.transactions
        .singleWhere((item) => item.id == result.transferTransactionId);
    final interest = repo.transactions
        .singleWhere((item) => item.id == result.interestTransactionId);
    expect(transfer.uuid, isNotEmpty);
    expect(interest.uuid, isNotEmpty);
    expect(metadata['transfer_transaction_uuid'], transfer.uuid);
    expect(metadata['interest_transaction_uuid'], interest.uuid);
    expect(metadata['profile_uuid'], profileById(repo, debt.profileId).uuid);

    await repo.undoLiabilityRepayment(event.id);

    expect(moneyState(repo), before);
    expect(
      repo.assetEvents.where(
          (item) => item.eventType == AssetEventType.liabilityRepaymentUndone),
      hasLength(1),
    );
  });

  for (final deleteInterest in [false, true]) {
    test('直接删除${deleteInterest ? '利息' : '本金'}被保护，明确撤销后恢复整次还款', () async {
      final repo = await freshRepo();
      final debt = await createDebt(repo);
      final before = moneyState(repo);
      final result = await repo.repayLiabilityProfile(
        profileId: debt.profileId,
        amount: money('520'),
        fromAccountId: debt.payerId,
      );
      final id = deleteInterest
          ? result.interestTransactionId!
          : result.transferTransactionId!;
      final afterPayment = moneyState(repo);

      await expectLater(repo.deleteTransaction(id), throwsStateError);
      expect(moneyState(repo), afterPayment);
      final event = repaymentEvent(repo, id);
      await repo.undoLiabilityRepayment(event.id);

      expect(moneyState(repo), before);
      expect(
          repo.transactions
              .any((item) => item.id == result.transferTransactionId),
          isFalse);
      expect(
          repo.transactions
              .any((item) => item.id == result.interestTransactionId),
          isFalse);
    });
  }

  for (final verifyPayer in [false, true]) {
    test('${verifyPayer ? '付款' : '负债'}账户余额核对吸收还款后拒绝撤销且资金不变', () async {
      final repo = await freshRepo();
      final debt = await createDebt(repo);
      final result = await repo.repayLiabilityProfile(
        profileId: debt.profileId,
        amount: money('520'),
        fromAccountId: debt.payerId,
      );
      final event = repaymentEvent(repo, result.transferTransactionId!);
      final accountId = verifyPayer ? debt.payerId : debt.liabilityId;
      await repo.createAccountBalanceCheckpoint(
        accountId: accountId,
        targetBalance: accountBalance(repo, accountId),
        note: '本次余额核对已包含还款',
      );
      final afterCheckpoint = moneyState(repo);

      await expectLater(
          repo.undoLiabilityRepayment(event.id), throwsStateError);

      expect(moneyState(repo), afterCheckpoint);
      expect(
          repo.transactions
              .any((item) => item.id == result.transferTransactionId),
          isTrue);
      expect(
          repo.transactions
              .any((item) => item.id == result.interestTransactionId),
          isTrue);
      expect(
        repo.assetEvents.where((item) =>
            item.eventType == AssetEventType.liabilityRepaymentUndone),
        isEmpty,
      );
    });
  }

  test('旧还款事件不能跨越后续还款撤销，按倒序撤销能逐笔恢复', () async {
    final repo = await freshRepo();
    final debt = await createDebt(repo);
    final initial = moneyState(repo);
    final first = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('100'),
      fromAccountId: debt.payerId,
    );
    final firstEvent = repaymentEvent(repo, first.transferTransactionId!);
    final afterFirst = moneyState(repo);
    final second = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('200'),
      fromAccountId: debt.payerId,
    );
    final secondEvent = repaymentEvent(repo, second.transferTransactionId!);
    final afterSecond = moneyState(repo);

    await expectLater(
        repo.undoLiabilityRepayment(firstEvent.id), throwsStateError);
    expect(moneyState(repo), afterSecond);
    await repo.undoLiabilityRepayment(secondEvent.id);
    expect(moneyState(repo), afterFirst);
    await repo.undoLiabilityRepayment(firstEvent.id);
    expect(moneyState(repo), initial);
  });

  test('重复并发撤销只有一次成功，不重复恢复本金或账户余额', () async {
    final repo = await freshRepo();
    final debt = await createDebt(repo);
    final before = moneyState(repo);
    final result = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('520'),
      fromAccountId: debt.payerId,
    );
    final event = repaymentEvent(repo, result.transferTransactionId!);
    Future<bool> tryUndo() async {
      try {
        await repo.undoLiabilityRepayment(event.id);
        return true;
      } on StateError {
        return false;
      }
    }

    final results = await Future.wait([tryUndo(), tryUndo()]);

    expect(results.where((success) => success), hasLength(1));
    expect(results.where((success) => !success), hasLength(1));
    expect(moneyState(repo), before);
    expect(
      repo.assetEvents.where(
          (item) => item.eventType == AssetEventType.liabilityRepaymentUndone),
      hasLength(1),
    );
    await expectLater(repo.undoLiabilityRepayment(event.id), throwsStateError);
    expect(moneyState(repo), before);
  });

  test('手工修改负债档案后不能用旧还款事件覆盖新数据', () async {
    final repo = await freshRepo();
    final debt = await createDebt(repo);
    final result = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('200'),
      fromAccountId: debt.payerId,
    );
    final event = repaymentEvent(repo, result.transferTransactionId!);
    await repo.upsertLiabilityProfile(
      accountId: debt.liabilityId,
      type: LiabilityProfileType.personalBorrow,
      originalAmount: money('500'),
      currentPrincipal: money('450'),
      note: '已另行核对本金',
    );
    final afterEdit = moneyState(repo);

    await expectLater(repo.undoLiabilityRepayment(event.id), throwsStateError);

    expect(moneyState(repo), afterEdit);
    expect(profileById(repo, debt.profileId).currentPrincipal, money('450'));
  });

  test('还款事件INSERT故障使本金、利息和档案同事务回滚，重启仍完整', () async {
    var repo = await freshRepo();
    final debt = await createDebt(repo);
    final before = moneyState(repo);
    final faultDb = await databaseFactory.openDatabase(
      p.join(tmp.path, 'qingji.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await faultDb.execute('''
        CREATE TRIGGER test_fail_liability_repayment_event
        BEFORE INSERT ON asset_events
        WHEN NEW.event_type = 'liability_repaid'
        BEGIN
          SELECT RAISE(ABORT, 'forced repayment event failure');
        END
      ''');

      await expectLater(
        repo.repayLiabilityProfile(
          profileId: debt.profileId,
          amount: money('520'),
          fromAccountId: debt.payerId,
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(moneyState(repo), before);
      expect(await faultDb.query('transactions'), isEmpty);
      expect(
        await faultDb.query('asset_events',
            where: 'event_type = ?', whereArgs: ['liability_repaid']),
        isEmpty,
      );
      final stored = await faultDb.query('liability_profiles',
          where: 'id = ?', whereArgs: [debt.profileId]);
      expect(Decimal.parse(stored.single['current_principal'] as String),
          money('500'));
      expect(stored.single['status'], LiabilityProfileStatus.active.storageKey);
    } finally {
      await faultDb.execute(
          'DROP TRIGGER IF EXISTS test_fail_liability_repayment_event');
      await faultDb.close();
    }
    repo = await restart(repo);
    expect(moneyState(repo), before);
    final result = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('520'),
      fromAccountId: debt.payerId,
    );
    expect(result.principalPaid, money('500'));
    expect(result.interestPaid, money('20'));
    repaymentEvent(repo, result.transferTransactionId!);
  });

  test('导入的还款事件按档案和流水UUID恢复，数字ID冲突不误挂物品', () async {
    var repo = await freshRepo();
    final debt = await createDebt(repo);
    await repo.addPhysicalAsset(name: '编号占位物品', currentValue: money('10'));
    final physicalId = await repo.addPhysicalAsset(
      name: '故意与旧事件编号冲突的物品',
      currentValue: money('20'),
    );
    expect(physicalId, isNot(debt.profileId));
    final beforePayment = moneyState(repo);
    final result = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('520'),
      fromAccountId: debt.payerId,
    );
    final originalEvent = repaymentEvent(repo, result.transferTransactionId!);
    final afterPayment = moneyState(repo);
    final transactionUuids = repo.transactions.map((item) => item.uuid).toSet();
    final payload =
        jsonDecode(await repo.exportAssetTablesJson()) as Map<String, dynamic>;
    expect(payload.containsKey('liability_profiles'), isFalse);
    expect(
        (payload['events'] as List).any((item) =>
            item['asset_type'] == AssetObjectType.liability.storageKey),
        isFalse);
    // Legacy/full-data imports may include a journal; scoped exports never do.
    (payload['events'] as List).add({
      'id': originalEvent.id,
      'uuid': originalEvent.uuid,
      'asset_id': physicalId,
      'asset_type': originalEvent.assetType.storageKey,
      'event_type': originalEvent.eventType.storageKey,
      'occurred_ms': originalEvent.occurredMs,
      'value': originalEvent.value?.toString(),
      'note': originalEvent.note,
      'metadata': originalEvent.metadata,
      'created_ms': originalEvent.createdMs,
    });

    // Only this isolated fixture loses its event row; real financial rows stay intact.
    await repo.closeForTest();
    final fixtureDb = await databaseFactory.openDatabase(
      p.join(tmp.path, 'qingji.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      final storedTransactions = await fixtureDb.query('transactions');
      await fixtureDb.delete(
        'asset_events',
        where: 'asset_type = ?',
        whereArgs: [AssetObjectType.liability.storageKey],
      );
      expect(await fixtureDb.query('transactions'), storedTransactions);
      expect(
        (await fixtureDb.query('transactions'))
            .map((row) => row['uuid'])
            .toSet(),
        transactionUuids,
      );
    } finally {
      await fixtureDb.close();
    }

    repo = await freshRepo();
    expect(
        repo.liabilityRepaymentEventForTransaction(
            result.transferTransactionId!),
        isNull);
    expect(moneyState(repo), afterPayment);
    final imported = await repo.importAssetTablesJson(jsonEncode(payload));
    expect(imported.events, 1);
    final restoredEvent = repaymentEvent(repo, result.transferTransactionId!);
    expect(restoredEvent.uuid, originalEvent.uuid);
    expect(restoredEvent.assetId, debt.profileId);
    expect(restoredEvent.assetId, isNot(physicalId));
    expect(repaymentEvent(repo, result.interestTransactionId!).id,
        restoredEvent.id);
    expect(
      repo
          .eventsForAsset(physicalId)
          .any((event) => event.uuid == originalEvent.uuid),
      isFalse,
    );
    expect(moneyState(repo), afterPayment);
    expect(
        repo.transactions.map((item) => item.uuid).toSet(), transactionUuids);

    repo = await restart(repo);
    final restartedEvent = repaymentEvent(repo, result.transferTransactionId!);
    expect(restartedEvent.uuid, originalEvent.uuid);
    final beforeRejectedDelete = moneyState(repo);
    await expectLater(repo.deleteTransaction(result.interestTransactionId!),
        throwsStateError);
    expect(moneyState(repo), beforeRejectedDelete);
    await repo.undoLiabilityRepayment(restartedEvent.id);
    expect(moneyState(repo), beforePayment);
    repo = await restart(repo);
    expect(moneyState(repo), beforePayment);
  });

  test('还款审计前后本金损坏或含厘精度时拒绝撤销，余额和流水不变', () async {
    for (final corruptedBefore in ['700', '-500', '500.001']) {
      var repo = await freshRepo();
      final debt = await createDebt(repo);
      final result = await repo.repayLiabilityProfile(
        profileId: debt.profileId,
        amount: money('200'),
        fromAccountId: debt.payerId,
      );
      final event = repaymentEvent(repo, result.transferTransactionId!);
      final metadata = jsonDecode(event.metadata) as Map<String, dynamic>;
      metadata['principal_before'] = corruptedBefore;
      await repo.closeForTest();
      final fixtureDb = await databaseFactory.openDatabase(
        p.join(tmp.path, 'qingji.db'),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await fixtureDb.update(
            'asset_events', {'metadata': jsonEncode(metadata)},
            where: 'id = ?', whereArgs: [event.id]);
      } finally {
        await fixtureDb.close();
      }
      repo = await freshRepo();
      final before = moneyState(repo);
      await expectLater(
          repo.undoLiabilityRepayment(event.id), throwsStateError);
      expect(moneyState(repo), before, reason: corruptedBefore);
      await repo.closeForTest();
      await databaseFactory.deleteDatabase(p.join(tmp.path, 'qingji.db'));
    }
  });

  test('重启后还款事件仍保护编辑、支持整笔撤销并再次持久化', () async {
    var repo = await freshRepo();
    final debt = await createDebt(repo);
    final before = moneyState(repo);
    final result = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('520'),
      fromAccountId: debt.payerId,
    );
    final eventId = repaymentEvent(repo, result.transferTransactionId!).id;
    repo = await restart(repo);
    expect(repaymentEvent(repo, result.transferTransactionId!).id, eventId);
    expect(repaymentEvent(repo, result.interestTransactionId!).id, eventId);
    final afterPayment = moneyState(repo);

    for (final transactionId in [
      result.transferTransactionId!,
      result.interestTransactionId!
    ]) {
      final transaction =
          repo.transactions.singleWhere((item) => item.id == transactionId);
      await expectLater(
        repo.updateTransaction(
          id: transactionId,
          kind: transaction.txKind,
          amount: transaction.amount + money('1'),
          accountId: transaction.accountId!,
          toAccountId: transaction.toAccountId,
          note: '不能绕过还款事件改金额',
          date: DateTime.fromMillisecondsSinceEpoch(transaction.dateMs),
        ),
        throwsStateError,
      );
      expect(moneyState(repo), afterPayment);
    }

    await repo.undoLiabilityRepayment(eventId);
    expect(moneyState(repo), before);
    repo = await restart(repo);
    expect(moneyState(repo), before);
    await expectLater(repo.undoLiabilityRepayment(eventId), throwsStateError);
    expect(moneyState(repo), before);
  });

  for (final principal in ['200', '1000']) {
    for (final interest in ['0', '20']) {
      test('权益收回本金$principal、利息$interest与撤销保持净资产守恒', () async {
        var repo = await freshRepo();
        final fixture = await createReceivable(repo);
        final before = moneyState(repo);
        final netWorthBefore = repo.currentNetWorthBreakdown().netWorth;

        await repo.recoverReceivableAsset(
          id: fixture.receivableId,
          amount: money(principal),
          interestAmount: money(interest),
          targetAccountId: fixture.accountId,
        );

        expect(
          accountBalance(repo, fixture.accountId),
          money('2000') + money(principal) + money(interest),
        );
        expect(
          repo.receivableDetailById(fixture.receivableId)!.remainingAmount,
          money('1000') - money(principal),
        );
        expect(repo.currentNetWorthBreakdown().netWorth,
            netWorthBefore + money(interest));
        final recovery = repo.receivableRecoveries.single;
        final event =
            repo.assetEvents.singleWhere((item) => item.id == recovery.eventId);
        final metadata = jsonDecode(event.metadata) as Map<String, dynamic>;
        final principalTransaction = repo.transactions.singleWhere(
          (item) => item.id == recovery.transactionId,
        );
        expect(principalTransaction.excluded, isTrue);
        expect(metadata['transaction_uuid'], principalTransaction.uuid);
        if (interest == '20') {
          final interestTransaction = repo.transactions.singleWhere(
            (item) => item.uuid == metadata['interest_transaction_uuid'],
          );
          expect(interestTransaction.amount, money('20'));
          expect(interestTransaction.excluded, isFalse);
          expect(interestTransaction.txKind, TransactionKind.income);
        }

        repo = await restart(repo);
        final restartedRecovery = repo.receivableRecoveries.singleWhere(
          (item) => item.uuid == recovery.uuid,
        );
        await repo.undoReceivableRecovery(restartedRecovery.id);
        expect(moneyState(repo), before);
        repo = await restart(repo);
        expect(moneyState(repo), before);
      });
    }
  }

  test('权益收回本金与利息先归一到分，收回撤销均逐分守恒', () async {
    final repo = await freshRepo();
    final fixture = await createReceivable(repo);
    final before = moneyState(repo);
    final netWorthBefore = repo.currentNetWorthBreakdown().netWorth;

    await repo.recoverReceivableAsset(
      id: fixture.receivableId,
      amount: money('200.005'),
      interestAmount: money('20.005'),
      targetAccountId: fixture.accountId,
    );

    expect(accountBalance(repo, fixture.accountId), money('2220.02'));
    expect(repo.receivableDetailById(fixture.receivableId)!.remainingAmount,
        money('799.99'));
    expect(repo.receivableRecoveries.single.amount, money('200.01'));
    expect(repo.currentNetWorthBreakdown().netWorth,
        netWorthBefore + money('20.01'));
    await repo.undoReceivableRecovery(repo.receivableRecoveries.single.id);
    expect(moneyState(repo), before);
  });

  test('权益收回利息流水不能单独删除或修改，确认撤销收回才整笔恢复', () async {
    final repo = await freshRepo();
    final fixture = await createReceivable(repo);
    final before = moneyState(repo);
    await repo.recoverReceivableAsset(
      id: fixture.receivableId,
      amount: money('200'),
      interestAmount: money('20'),
      targetAccountId: fixture.accountId,
    );
    final recovery = repo.receivableRecoveries.single;
    final interest = repo.transactions.singleWhere((item) => !item.excluded);
    final afterRecovery = moneyState(repo);

    await expectLater(repo.deleteTransaction(interest.id), throwsStateError);
    expect(moneyState(repo), afterRecovery);
    await expectLater(
      repo.updateTransaction(
        id: interest.id,
        kind: interest.txKind,
        amount: money('21'),
        accountId: interest.accountId!,
        note: '不能绕过收回事件改单笔利息',
        date: DateTime.fromMillisecondsSinceEpoch(interest.dateMs),
      ),
      throwsStateError,
    );
    expect(moneyState(repo), afterRecovery);
    await repo.undoReceivableRecovery(recovery.id);
    expect(moneyState(repo), before);
  });

  test('权益到账已被余额核对吸收时拒绝撤销，流水与权益均不改变', () async {
    final repo = await freshRepo();
    final fixture = await createReceivable(repo);
    await repo.recoverReceivableAsset(
      id: fixture.receivableId,
      amount: money('200'),
      interestAmount: money('20'),
      targetAccountId: fixture.accountId,
    );
    final recovery = repo.receivableRecoveries.single;
    await repo.createAccountBalanceCheckpoint(
      accountId: fixture.accountId,
      targetBalance: accountBalance(repo, fixture.accountId),
      note: '余额核对已包含本次本金及利息到账',
    );
    final afterCheckpoint = moneyState(repo);

    await expectLater(
        repo.undoReceivableRecovery(recovery.id), throwsStateError);

    expect(moneyState(repo), afterCheckpoint);
    expect(
      repo.assetEvents.where((event) =>
          event.eventType == AssetEventType.receivableRecoveryUndone),
      isEmpty,
    );
  });

  test('后补旧日期收回仍须先撤销后创建的一笔，不按回填日期倒序', () async {
    final repo = await freshRepo();
    final receivableId = await repo.addReceivableAsset(
      name: '测试回填收回顺序',
      originalAmount: money('1000'),
    );
    final before = moneyState(repo);
    await repo.recoverReceivableAsset(
      id: receivableId,
      amount: money('100'),
      recoveredAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    final firstRecoveryId = repo.receivableRecoveries.single.id;
    final afterFirst = moneyState(repo);
    await repo.recoverReceivableAsset(
      id: receivableId,
      amount: money('200'),
      recoveredAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    final secondRecoveryId = repo.receivableRecoveries
        .singleWhere(
          (item) => item.id != firstRecoveryId,
        )
        .id;
    final afterSecond = moneyState(repo);

    await expectLater(
        repo.undoReceivableRecovery(firstRecoveryId), throwsStateError);
    expect(moneyState(repo), afterSecond);
    await repo.undoReceivableRecovery(secondRecoveryId);
    expect(moneyState(repo), afterFirst);
    await repo.undoReceivableRecovery(firstRecoveryId);
    expect(moneyState(repo), before);
  });

  test('权益收回事件写入失败时，本金利息到账、剩余额与收回记录全部回滚', () async {
    var repo = await freshRepo();
    final fixture = await createReceivable(repo);
    final before = moneyState(repo);
    await withFailureTrigger('receivable_recovered', (faultDb) async {
      await expectLater(
        repo.recoverReceivableAsset(
          id: fixture.receivableId,
          amount: money('200'),
          interestAmount: money('20'),
          targetAccountId: fixture.accountId,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(moneyState(repo), before);
      expect(await faultDb.query('transactions'), isEmpty);
      expect(await faultDb.query('receivable_recoveries'), isEmpty);
      final stored = await faultDb.query('receivable_assets',
          where: 'id = ?', whereArgs: [fixture.receivableId]);
      expect(Decimal.parse(stored.single['remaining_amount'] as String),
          money('1000'));
    });
    repo = await restart(repo);
    expect(moneyState(repo), before);
  });

  test('权益撤销的最后事件写入失败时，已删流水和已改权益必须全部恢复', () async {
    var repo = await freshRepo();
    final fixture = await createReceivable(repo);
    await repo.recoverReceivableAsset(
      id: fixture.receivableId,
      amount: money('200'),
      interestAmount: money('20'),
      targetAccountId: fixture.accountId,
    );
    final recovery = repo.receivableRecoveries.single;
    final afterRecovery = moneyState(repo);
    await withFailureTrigger('receivable_recovery_undone', (faultDb) async {
      final storedTransactions = await faultDb.query('transactions');
      await expectLater(
        repo.undoReceivableRecovery(recovery.id),
        throwsA(isA<DatabaseException>()),
      );
      expect(moneyState(repo), afterRecovery);
      expect(await faultDb.query('transactions'), storedTransactions);
      expect(await faultDb.query('receivable_recoveries'), hasLength(1));
      final stored = await faultDb.query('receivable_assets',
          where: 'id = ?', whereArgs: [fixture.receivableId]);
      expect(Decimal.parse(stored.single['remaining_amount'] as String),
          money('800'));
    });
    repo = await restart(repo);
    expect(moneyState(repo), afterRecovery);
  });

  test('资产JSON收回记录的数字流水ID被篡改时仍按本金及利息UUID恢复', () async {
    var repo = await freshRepo();
    final fixture = await createReceivable(repo);
    final unrelatedId = await repo.addTransaction(
      kind: TransactionKind.income,
      amount: money('20'),
      accountId: fixture.accountId,
      note: '与收回无关的正常账单',
      date: DateTime.now(),
    );
    final beforeRecovery = moneyState(repo);
    await repo.recoverReceivableAsset(
      id: fixture.receivableId,
      amount: money('200'),
      interestAmount: money('20'),
      targetAccountId: fixture.accountId,
    );
    final recovery = repo.receivableRecoveries.single;
    final event =
        repo.assetEvents.singleWhere((item) => item.id == recovery.eventId);
    final originalMetadata = jsonDecode(event.metadata) as Map<String, dynamic>;
    final principalUuid = repo.transactions
        .singleWhere((item) => item.id == recovery.transactionId)
        .uuid;
    final interestUuid = originalMetadata['interest_transaction_uuid'];
    final transactionUuids = repo.transactions.map((item) => item.uuid).toSet();
    final afterRecovery = moneyState(repo)..remove('recoveries');
    final payload =
        jsonDecode(await repo.exportAssetTablesJson()) as Map<String, dynamic>;
    final exportedRecovery =
        (payload['recoveries'] as List).cast<Map<String, dynamic>>().single;
    expect(exportedRecovery['transaction_uuid'], principalUuid);
    exportedRecovery['transaction_id'] = unrelatedId;
    final exportedEvent =
        (payload['events'] as List).cast<Map<String, dynamic>>().singleWhere(
              (item) => item['uuid'] == event.uuid,
            );
    final damagedMetadata =
        jsonDecode(exportedEvent['metadata'] as String) as Map<String, dynamic>;
    damagedMetadata['transaction_id'] = unrelatedId;
    damagedMetadata['interest_transaction_id'] = unrelatedId;
    exportedEvent['metadata'] = jsonEncode(damagedMetadata);

    await removeRecoveryEvidenceFixture(repo, recovery, event);
    repo = await freshRepo();
    expect(repo.receivableRecoveries, isEmpty);
    await repo.importAssetTablesJson(jsonEncode(payload));
    final restored = repo.receivableRecoveries.single;
    expect(restored.uuid, recovery.uuid);
    expect(restored.transactionId, recovery.transactionId);
    expect(restored.transactionId, isNot(unrelatedId));
    final restoredEvent =
        repo.assetEvents.singleWhere((item) => item.id == restored.eventId);
    final restoredMetadata =
        jsonDecode(restoredEvent.metadata) as Map<String, dynamic>;
    expect(restoredMetadata['transaction_uuid'], principalUuid);
    expect(restoredMetadata['interest_transaction_uuid'], interestUuid);
    expect(moneyState(repo)..remove('recoveries'), afterRecovery);
    expect(
        repo.transactions.map((item) => item.uuid).toSet(), transactionUuids);

    repo = await restart(repo);
    final restartedRecovery = repo.receivableRecoveries
        .singleWhere((item) => item.uuid == recovery.uuid);
    await repo.undoReceivableRecovery(restartedRecovery.id);
    expect(moneyState(repo), beforeRecovery);
    expect(repo.transactions.single.id, unrelatedId);
    repo = await restart(repo);
    expect(moneyState(repo), beforeRecovery);
  });

  test('旧JSON利息缺UUID且裸ID指向别的账单时拒绝撤销，不误删正常账单', () async {
    var repo = await freshRepo();
    final fixture = await createReceivable(repo);
    final at = DateTime.now();
    final unrelatedId = await repo.addTransaction(
      kind: TransactionKind.income,
      amount: money('20'),
      accountId: fixture.accountId,
      note: '必须保留的无关账单',
      date: at,
    );
    await repo.recoverReceivableAsset(
      id: fixture.receivableId,
      amount: money('200'),
      interestAmount: money('20'),
      targetAccountId: fixture.accountId,
      recoveredAt: at,
    );
    final recovery = repo.receivableRecoveries.single;
    final event =
        repo.assetEvents.singleWhere((item) => item.id == recovery.eventId);
    final payload =
        jsonDecode(await repo.exportAssetTablesJson()) as Map<String, dynamic>;
    final exportedEvent =
        (payload['events'] as List).cast<Map<String, dynamic>>().singleWhere(
              (item) => item['uuid'] == event.uuid,
            );
    final legacyMetadata =
        jsonDecode(exportedEvent['metadata'] as String) as Map<String, dynamic>;
    legacyMetadata.remove('interest_transaction_uuid');
    legacyMetadata['interest_transaction_id'] = unrelatedId;
    exportedEvent['metadata'] = jsonEncode(legacyMetadata);
    final transactionUuids = repo.transactions.map((item) => item.uuid).toSet();
    final afterRecovery = moneyState(repo)..remove('recoveries');

    await removeRecoveryEvidenceFixture(repo, recovery, event);
    repo = await freshRepo();
    await repo.importAssetTablesJson(jsonEncode(payload));
    expect(moneyState(repo)..remove('recoveries'), afterRecovery);
    repo = await restart(repo);
    final beforeRejectedUndo = moneyState(repo);
    final restoredRecovery = repo.receivableRecoveries
        .singleWhere((item) => item.uuid == recovery.uuid);

    await expectLater(
        repo.undoReceivableRecovery(restoredRecovery.id), throwsStateError);

    expect(moneyState(repo), beforeRejectedUndo);
    expect(
        repo.transactions.map((item) => item.uuid).toSet(), transactionUuids);
    expect(
        repo.transactions
            .any((item) => item.id == unrelatedId && item.note == '必须保留的无关账单'),
        isTrue);
  });

  test('旧本地收回利息缺UUID时不凭同日同额流水猜撤销，导出也不补造标识', () async {
    var repo = await freshRepo();
    final fixture = await createReceivable(repo);
    final at = DateTime.now();
    final unrelatedId = await repo.addTransaction(
      kind: TransactionKind.income,
      amount: money('20'),
      accountId: fixture.accountId,
      note: '同日同额但不是收回利息',
      date: at,
    );
    await repo.recoverReceivableAsset(
      id: fixture.receivableId,
      amount: money('200'),
      interestAmount: money('20'),
      targetAccountId: fixture.accountId,
      recoveredAt: at,
    );
    final recovery = repo.receivableRecoveries.single;
    final event =
        repo.assetEvents.singleWhere((item) => item.id == recovery.eventId);
    final metadata = jsonDecode(event.metadata) as Map<String, dynamic>;
    metadata.remove('interest_transaction_uuid');
    metadata['interest_transaction_id'] = unrelatedId;
    await repo.closeForTest();
    final fixtureDb = await databaseFactory.openDatabase(
      p.join(tmp.path, 'qingji.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await fixtureDb.update('asset_events', {'metadata': jsonEncode(metadata)},
          where: 'id = ?', whereArgs: [event.id]);
    } finally {
      await fixtureDb.close();
    }
    repo = await freshRepo();
    final before = moneyState(repo);
    final payload =
        jsonDecode(await repo.exportAssetTablesJson()) as Map<String, dynamic>;
    final exported = (payload['events'] as List)
        .singleWhere((row) => row['uuid'] == event.uuid);
    expect(
        (jsonDecode(exported['metadata'] as String) as Map)
            .containsKey('interest_transaction_uuid'),
        isFalse);
    await expectLater(
        repo.undoReceivableRecovery(recovery.id), throwsStateError);
    expect(moneyState(repo), before);
    expect(repo.transactions.any((row) => row.id == unrelatedId), isTrue);
  });

  test('权益JSON账户UUID无法匹配且同名账户不唯一时，不猜到账账户', () async {
    var repo = await freshRepo();
    final fixture = await createReceivable(repo);
    await repo.recoverReceivableAsset(
      id: fixture.receivableId,
      amount: money('200'),
      targetAccountId: fixture.accountId,
    );
    final payload = await repo.exportAssetTablesJson();
    final accountName =
        repo.accounts.singleWhere((row) => row.id == fixture.accountId).name;
    await repo.closeForTest();
    await databaseFactory.deleteDatabase(p.join(tmp.path, 'qingji.db'));
    repo = await freshRepo();
    await repo.addAccount(name: accountName);
    await repo.addAccount(name: accountName);
    await repo.importAssetTablesJson(payload);
    expect(repo.receivableRecoveries.single.targetAccountId, isNull);
    expect(repo.receivableRecoveries.single.transactionId, isNull);
    expect(repo.transactions, isEmpty);
  });

  test('含还款的账本直接清空被拒绝，普通账单和物品也不得部分删除', () async {
    final repo = await freshRepo();
    final bookId = await repo.addBook(name: '有还款的账本');
    await repo.switchBook(bookId);
    final debt = await createDebt(repo);
    final physicalId =
        await repo.addPhysicalAsset(name: '同账本物品', currentValue: money('10'));
    final ordinaryId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: money('7'),
      accountId: debt.payerId,
      note: '同账本普通消费',
      date: DateTime.now(),
    );
    final result = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('520'),
      fromAccountId: debt.payerId,
    );
    final beforeWipe = moneyState(repo);
    final bookIds = repo.books.map((book) => book.id).toSet();
    final eventUuid = repaymentEvent(repo, result.transferTransactionId!).uuid;

    await expectLater(
        repo.deleteBook(bookId, moveRecordsToDefault: false), throwsStateError);

    expect(moneyState(repo), beforeWipe);
    expect(repo.books.map((book) => book.id).toSet(), bookIds);
    expect(await repo.transactionCountForBook(bookId), 3);
    expect(repo.transactions.any((item) => item.id == ordinaryId), isTrue);
    expect(
        repo.physicalAssets
            .any((asset) => asset.id == physicalId && !asset.isDeleted),
        isTrue);
    expect(repaymentEvent(repo, result.transferTransactionId!).uuid, eventUuid);
  });

  test('含还款账本可迁移到总账本，UUID关联不变且仍能整笔撤销', () async {
    var repo = await freshRepo();
    final defaultBookId = repo.defaultBookId;
    final bookId = await repo.addBook(name: '可迁移还款账本');
    await repo.switchBook(bookId);
    final debt = await createDebt(repo);
    final beforePayment = moneyState(repo);
    final result = await repo.repayLiabilityProfile(
      profileId: debt.profileId,
      amount: money('520'),
      fromAccountId: debt.payerId,
    );
    final eventUuid = repaymentEvent(repo, result.transferTransactionId!).uuid;

    await repo.deleteBook(bookId, moveRecordsToDefault: true);

    expect(repo.books.any((book) => book.id == bookId), isFalse);
    expect(await repo.transactionCountForBook(bookId), 0);
    expect(await repo.transactionCountForBook(defaultBookId), 2);
    final event = repaymentEvent(repo, result.transferTransactionId!);
    expect(event.uuid, eventUuid);
    expect(repaymentEvent(repo, result.interestTransactionId!).uuid, eventUuid);
    await repo.undoLiabilityRepayment(event.id);
    expect(moneyState(repo), beforePayment);
    repo = await restart(repo);
    expect(moneyState(repo), beforePayment);
  });
}
