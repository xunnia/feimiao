import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/assets/asset_allocation.dart';
import 'package:qingji/core/account/account_movement_projection.dart';
import 'package:qingji/core/budget/budget_plan_v2.dart';
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
    tmp = Directory.systemTemp.createTempSync('qingji_a4_repo_test_');
    await databaseFactory.setDatabasesPath(tmp.path);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppRepository> freshRepo() async {
    final repo = AppRepository();
    await repo.init();
    return repo;
  }

  Future<int> addExpense(
    AppRepository repo, {
    required String note,
    required Decimal amount,
  }) =>
      repo.addTransaction(
        kind: TransactionKind.expense,
        amount: amount,
        accountId: repo.accounts.first.id,
        note: note,
        date: DateTime(2026, 7, 13),
      );

  test('A4 持有支出不新增收支，退款按 family net，解除后恢复', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '工作站',
      currentValue: Decimal.fromInt(8000),
      purchasePrice: Decimal.fromInt(9000),
    );
    final maintenanceId = await addExpense(
      repo,
      note: '工作站清灰',
      amount: Decimal.fromInt(100),
    );
    final accessoryId = await addExpense(
      repo,
      note: '扩展坞',
      amount: Decimal.fromInt(50),
    );
    final insuranceId = await addExpense(
      repo,
      note: '设备保险',
      amount: Decimal.fromInt(25),
    );
    final beforeLinks = repo.transactions
        .map((item) => (item.id, item.txKind, item.amount))
        .toList(growable: false);

    await repo.linkPhysicalAssetCost(
      assetId: assetId,
      transactionId: maintenanceId,
      type: AssetTransactionLinkType.maintenance,
    );
    await repo.linkPhysicalAssetCost(
      assetId: assetId,
      transactionId: accessoryId,
      type: AssetTransactionLinkType.accessory,
    );
    await repo.linkPhysicalAssetCost(
      assetId: assetId,
      transactionId: insuranceId,
      type: AssetTransactionLinkType.insurance,
    );

    expect(
      repo.transactions
          .map((item) => (item.id, item.txKind, item.amount))
          .toList(growable: false),
      beforeLinks,
    );
    expect(
      repo.additionalCostLinksForAsset(assetId).map((link) => link.linkType),
      containsAll([
        AssetTransactionLinkType.maintenance,
        AssetTransactionLinkType.accessory,
        AssetTransactionLinkType.insurance,
      ]),
    );
    expect(
      repo.physicalAssetAdditionalCost(assetId).amount,
      Decimal.fromInt(175),
    );

    final maintenance = repo.transactions.singleWhere(
      (item) => item.id == maintenanceId,
    );
    await repo.refundTransaction(
      maintenance,
      Decimal.fromInt(40),
      settledAt: DateTime(2026, 7, 14),
      settlementAccountId: repo.accounts.first.id,
    );
    expect(
      repo.physicalAssetAdditionalCost(assetId).amount,
      Decimal.fromInt(135),
    );
    final exportedAfterRefund =
        jsonDecode(await repo.exportAssetTablesJson()) as Map<String, dynamic>;
    final exportedMaintenanceLink = (exportedAfterRefund['links'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (item) =>
              item['link_type'] == 'maintenance' &&
              item['transaction_id'] == maintenanceId,
        );
    expect(
      Decimal.parse(exportedMaintenanceLink['amount'].toString()),
      Decimal.fromInt(60),
    );
    final afterRefund = repo.transactions
        .map((item) => (item.id, item.txKind, item.amount, item.refundOf))
        .toList(growable: false);

    for (final transactionId in [
      maintenanceId,
      accessoryId,
      insuranceId,
    ]) {
      await repo.unlinkPhysicalAssetTransaction(
        assetId: assetId,
        transactionId: transactionId,
      );
      expect(
        repo.isTransactionLinkedAsPhysicalAssetCost(transactionId),
        isFalse,
      );
    }
    expect(repo.additionalCostLinksForAsset(assetId), isEmpty);
    expect(
      repo.physicalAssetAdditionalCost(assetId).amount,
      Decimal.zero,
    );
    expect(
      repo.transactions
          .map((item) => (item.id, item.txKind, item.amount, item.refundOf))
          .toList(growable: false),
      afterRefund,
    );
    await repo.closeForTest();
  });

  test('A4 使用次数开启、加一、撤销并跨重启保持', () async {
    var repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '相机',
      currentValue: Decimal.fromInt(5000),
    );

    await expectLater(
      repo.recordPhysicalAssetUsage(assetId),
      throwsStateError,
    );
    await repo.setPhysicalAssetUsageTracking(assetId, enabled: true);
    await repo.recordPhysicalAssetUsage(
      assetId,
      occurredAt: DateTime(2026, 7, 13, 9),
      note: '周末拍摄',
    );
    expect(repo.physicalAssetUsage(assetId).totalCount, 1);
    expect(repo.physicalAssetDetailById(assetId)!.usageTrackingEnabled, isTrue);
    await repo.closeForTest();

    repo = await freshRepo();
    expect(repo.physicalAssetUsage(assetId).totalCount, 1);
    expect(repo.physicalAssetDetailById(assetId)!.usageTrackingEnabled, isTrue);
    await repo.undoLatestPhysicalAssetUsage(assetId);
    expect(repo.physicalAssetUsage(assetId).totalCount, 0);
    expect(repo.usageEventsForAsset(assetId), hasLength(2));
    await repo.closeForTest();

    repo = await freshRepo();
    expect(repo.physicalAssetUsage(assetId).totalCount, 0);
    expect(repo.physicalAssetUsage(assetId).isExact, isTrue);
    expect(repo.usageEventsForAsset(assetId), hasLength(2));
    await repo.closeForTest();
  });

  test('A4 使用次数连续或并发撤销时每条记录最多成功一次', () async {
    final repo = await freshRepo();

    Future<int> assetWithOneUsage(String name) async {
      final assetId = await repo.addPhysicalAsset(
        name: name,
        currentValue: Decimal.fromInt(1000),
      );
      await repo.setPhysicalAssetUsageTracking(assetId, enabled: true);
      await repo.recordPhysicalAssetUsage(assetId);
      return assetId;
    }

    final sequentialAssetId = await assetWithOneUsage('顺序撤销相机');
    await repo.undoLatestPhysicalAssetUsage(sequentialAssetId);
    await expectLater(
      repo.undoLatestPhysicalAssetUsage(sequentialAssetId),
      throwsStateError,
    );
    expect(repo.usageEventsForAsset(sequentialAssetId), hasLength(2));

    final concurrentAssetId = await assetWithOneUsage('并发撤销相机');
    Future<bool> attemptUndo() async {
      try {
        await repo.undoLatestPhysicalAssetUsage(concurrentAssetId);
        return true;
      } on Object {
        return false;
      }
    }

    final outcomes = await Future.wait([attemptUndo(), attemptUndo()]);
    expect(outcomes.where((success) => success), hasLength(1));
    expect(repo.usageEventsForAsset(concurrentAssetId), hasLength(2));
    expect(repo.physicalAssetUsage(concurrentAssetId).totalCount, 0);
    expect(repo.physicalAssetUsage(concurrentAssetId).isExact, isTrue);
    await repo.closeForTest();
  });

  test('A4 存钱目标关联，删除目标后原子解除并留审计事件', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '心愿镜头',
      currentValue: Decimal.fromInt(3000),
    );
    final goalId = await repo.addSavingsGoal(
      name: '镜头基金',
      target: Decimal.fromInt(6000),
    );

    await repo.setPhysicalAssetSavingsGoal(assetId, goalId);
    expect(repo.physicalAssetDetailById(assetId)!.savingsGoalId, goalId);
    await repo.deleteSavingsGoal(goalId);

    expect(repo.savingsGoalById(goalId), isNull);
    expect(repo.physicalAssetDetailById(assetId)!.savingsGoalId, isNull);
    expect(
      repo.eventsForAsset(assetId).first.eventType,
      AssetEventType.assetSavingsGoalUnlinked,
    );
    expect(
      repo.eventsForAsset(assetId).first.note,
      contains('自动解除关联'),
    );
    await repo.closeForTest();
  });

  test('A4 存钱目标 UUID 在编辑和重启后保持稳定', () async {
    var repo = await freshRepo();
    final goalId = await repo.addSavingsGoal(
      name: '相机基金',
      target: Decimal.fromInt(8000),
      initialSaved: Decimal.fromInt(500),
    );
    final created = repo.savingsGoalById(goalId)!;
    expect(created.uuid, matches(RegExp(r'^[0-9a-f]{32}$')));
    final stableUuid = created.uuid;

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await repo.updateSavingsGoal(
      goalId,
      name: '全画幅相机基金',
      target: Decimal.fromInt(12000),
      emoji: '📷',
    );
    final updated = repo.savingsGoalById(goalId)!;
    expect(updated.uuid, stableUuid);
    expect(updated.updatedMs, greaterThanOrEqualTo(created.updatedMs));
    await repo.closeForTest();

    repo = await freshRepo();
    final restarted = repo.savingsGoalById(goalId)!;
    expect(restarted.uuid, stableUuid);
    expect(restarted.name, '全画幅相机基金');
    expect(restarted.target, Decimal.fromInt(12000));
    expect(restarted.saved, Decimal.fromInt(500));
    await repo.closeForTest();
  });

  test('A4 报废、丢失、赠送均可撤销并恢复原价值与计入状态', () async {
    final repo = await freshRepo();
    final cases = [
      (
        status: PhysicalAssetStatus.disposed,
        economic: PhysicalAssetEconomicStatus.scrapped,
        included: true,
        value: Decimal.fromInt(900),
      ),
      (
        status: PhysicalAssetStatus.lost,
        economic: PhysicalAssetEconomicStatus.lost,
        included: false,
        value: Decimal.fromInt(1800),
      ),
      (
        status: PhysicalAssetStatus.gifted,
        economic: PhysicalAssetEconomicStatus.gifted,
        included: true,
        value: Decimal.fromInt(2700),
      ),
    ];

    for (var index = 0; index < cases.length; index++) {
      final item = cases[index];
      final assetId = await repo.addPhysicalAsset(
        name: '终止状态物品 $index',
        currentValue: item.value,
        includeInNetWorth: item.included,
      );
      await repo.setPhysicalAssetStatus(
        id: assetId,
        status: item.status,
        occurredAt: DateTime(2026, 7, 13, 10 + index),
      );
      var asset = repo.physicalAssetDetailById(assetId)!;
      expect(asset.economicStatus, item.economic);
      expect(asset.currentValue, Decimal.zero);
      expect(asset.includeInNetWorth, isFalse);

      await repo.undoPhysicalAssetTerminalStatus(assetId);
      asset = repo.physicalAssetDetailById(assetId)!;
      expect(asset.economicStatus, PhysicalAssetEconomicStatus.owned);
      expect(asset.currentValue, item.value);
      expect(asset.includeInNetWorth, item.included);
      expect(asset.endedMs, isNull);
      expect(
        repo.eventsForAsset(assetId).first.eventType,
        AssetEventType.assetTerminalUndone,
      );
    }
    await repo.closeForTest();
  });

  test('A4 缺少旧终态元数据时不允许自动撤销', () async {
    var repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '旧记录相机',
      currentValue: Decimal.fromInt(2800),
      includeInNetWorth: true,
    );
    await repo.setPhysicalAssetStatus(
      id: assetId,
      status: PhysicalAssetStatus.disposed,
      occurredAt: DateTime(2026, 7, 13, 12),
    );
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    final db = await databaseFactory.openDatabase(dbPath);
    await db.update(
      'asset_events',
      {'metadata': ''},
      where: 'asset_id = ? AND asset_type = ? AND event_type = ?',
      whereArgs: [assetId, 'physical', 'asset_disposed'],
    );
    await db.close();

    repo = await freshRepo();
    expect(repo.canUndoPhysicalAssetTerminalStatus(assetId), isFalse);
    await expectLater(
      repo.undoPhysicalAssetTerminalStatus(assetId),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('缺少结束前价值或计入口径证据'),
        ),
      ),
    );
    final unchanged = repo.physicalAssetDetailById(assetId)!;
    expect(unchanged.economicStatus, PhysicalAssetEconomicStatus.scrapped);
    expect(unchanged.currentValue, Decimal.zero);
    expect(unchanged.includeInNetWorth, isFalse);
    await repo.closeForTest();
  });

  test('A4 重复结束持有时撤销选择最新创建且尚未撤销的事件', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '重复处置相机',
      currentValue: Decimal.fromInt(900),
      includeInNetWorth: true,
    );

    await repo.setPhysicalAssetStatus(
      id: assetId,
      status: PhysicalAssetStatus.disposed,
      occurredAt: DateTime(2026, 7, 13),
    );
    await repo.undoPhysicalAssetTerminalStatus(assetId);
    await repo.updatePhysicalAssetValue(
      assetId,
      Decimal.fromInt(1750),
    );
    await repo.setPhysicalAssetStatus(
      id: assetId,
      status: PhysicalAssetStatus.disposed,
      occurredAt: DateTime(2026, 7, 1),
    );

    await repo.undoPhysicalAssetTerminalStatus(assetId);
    final restored = repo.physicalAssetDetailById(assetId)!;
    expect(restored.economicStatus, PhysicalAssetEconomicStatus.owned);
    expect(restored.currentValue, Decimal.fromInt(1750));
    expect(restored.includeInNetWorth, isTrue);
    final reversedUuids = repo
        .eventsForAsset(assetId)
        .where((event) => event.eventType == AssetEventType.assetTerminalUndone)
        .map((event) => (jsonDecode(event.metadata)
                as Map<String, dynamic>)['reversal_of_event_uuid']
            .toString())
        .toSet();
    expect(reversedUuids, hasLength(2));
    expect(repo.canUndoPhysicalAssetTerminalStatus(assetId), isFalse);
    await repo.closeForTest();
  });

  test('A4 并发撤销同一结束事件最多成功一次', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '并发撤销相机',
      currentValue: Decimal.fromInt(2200),
    );
    await repo.setPhysicalAssetStatus(
      id: assetId,
      status: PhysicalAssetStatus.lost,
    );

    Future<bool> attemptUndo() async {
      try {
        await repo.undoPhysicalAssetTerminalStatus(assetId);
        return true;
      } on Object {
        return false;
      }
    }

    final outcomes = await Future.wait([attemptUndo(), attemptUndo()]);
    expect(outcomes.where((success) => success), hasLength(1));
    expect(
      repo.eventsForAsset(assetId).where(
            (event) => event.eventType == AssetEventType.assetTerminalUndone,
          ),
      hasLength(1),
    );
    expect(repo.canUndoPhysicalAssetTerminalStatus(assetId), isFalse);
    expect(
      repo.physicalAssetDetailById(assetId)!.economicStatus,
      PhysicalAssetEconomicStatus.owned,
    );
    await repo.closeForTest();
  });

  test('资产 JSON v6 保留 usage、附加成本类型并按目标名称解释映射', () async {
    var repo = await freshRepo();
    final sourceGoalId = await repo.addSavingsGoal(
      name: '相机基金',
      target: Decimal.fromInt(10000),
    );
    final assetId = await repo.addPhysicalAsset(
      name: '旅行相机',
      currentValue: Decimal.fromInt(8000),
    );
    final insuranceId = await addExpense(
      repo,
      note: '旅行相机保险',
      amount: Decimal.fromInt(40),
    );
    await repo.setPhysicalAssetUsageTracking(assetId, enabled: true);
    await repo.recordPhysicalAssetUsage(assetId, note: '第一次使用');
    await repo.setPhysicalAssetSavingsGoal(assetId, sourceGoalId);
    await repo.linkPhysicalAssetCost(
      assetId: assetId,
      transactionId: insuranceId,
      type: AssetTransactionLinkType.insurance,
    );

    final exported = await repo.exportAssetTablesJson();
    final decoded = jsonDecode(exported) as Map<String, dynamic>;
    expect(decoded['version'], 6);
    final exportedAsset = (decoded['assets'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['name'] == '旅行相机');
    expect(exportedAsset['usage_tracking_enabled'], 1);
    expect(exportedAsset['savings_goal_name'], '相机基金');
    final exportedLink = (decoded['links'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['link_type'] == 'insurance');
    final transactionUuid = exportedLink['transaction_uuid'] as String;
    expect(transactionUuid, isNotEmpty);
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    await databaseFactory.deleteDatabase(dbPath);
    repo = await freshRepo();
    await repo.addSavingsGoal(
      name: '占位目标',
      target: Decimal.fromInt(1),
    );
    final targetGoalId = await repo.addSavingsGoal(
      name: '相机基金',
      target: Decimal.fromInt(12000),
    );
    expect(targetGoalId, isNot(sourceGoalId));
    final targetTransactionId = await addExpense(
      repo,
      note: '旅行相机保险',
      amount: Decimal.fromInt(40),
    );
    await repo.closeForTest();

    final db = await databaseFactory.openDatabase(dbPath);
    await db.update(
      'transactions',
      {'uuid': transactionUuid},
      where: 'id = ?',
      whereArgs: [targetTransactionId],
    );
    await db.close();

    repo = await freshRepo();
    final result = await repo.importAssetTablesJson(exported);
    final imported = repo.globalActivePhysicalAssets.singleWhere(
      (asset) => asset.name == '旅行相机',
    );
    expect(result.usages, 1);
    expect(result.links, 1);
    expect(imported.usageTrackingEnabled, isTrue);
    expect(imported.savingsGoalId, targetGoalId);
    expect(repo.physicalAssetUsage(imported.id).totalCount, 1);
    expect(
      repo.additionalCostLinksForAsset(imported.id).single.linkType,
      AssetTransactionLinkType.insurance,
    );
    expect(
      repo.physicalAssetAdditionalCost(imported.id).amount,
      Decimal.fromInt(40),
    );
    await repo.closeForTest();
  });

  test('资产 JSON v6 遇到重名存钱目标时不猜测并报告未解析', () async {
    var repo = await freshRepo();
    final sourceGoalId = await repo.addSavingsGoal(
      name: '重名基金',
      target: Decimal.fromInt(5000),
    );
    final assetId = await repo.addPhysicalAsset(
      name: '目标关联相机',
      currentValue: Decimal.fromInt(3000),
    );
    await repo.setPhysicalAssetSavingsGoal(assetId, sourceGoalId);
    final exported = await repo.exportAssetTablesJson();
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    await databaseFactory.deleteDatabase(dbPath);
    repo = await freshRepo();
    await repo.addSavingsGoal(
      name: '重名基金',
      target: Decimal.fromInt(6000),
    );
    await repo.addSavingsGoal(
      name: '重名基金',
      target: Decimal.fromInt(7000),
    );

    final result = await repo.importAssetTablesJson(exported);
    final imported = repo.globalActivePhysicalAssets.singleWhere(
      (asset) => asset.name == '目标关联相机',
    );
    expect(result.unresolvedSavingsGoalLinks, 1);
    expect(imported.savingsGoalId, isNull);
    expect(
        repo.savingsGoals.where((goal) => goal.name == '重名基金'), hasLength(2));
    await repo.closeForTest();
  });

  test('资产 JSON 单独导入缺少交易时报告未解析关联', () async {
    var repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '离线工作站',
      currentValue: Decimal.fromInt(6000),
    );
    final maintenanceId = await addExpense(
      repo,
      note: '离线工作站维护',
      amount: Decimal.fromInt(80),
    );
    await repo.linkPhysicalAssetCost(
      assetId: assetId,
      transactionId: maintenanceId,
      type: AssetTransactionLinkType.maintenance,
    );
    final exported = await repo.exportAssetTablesJson();
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    await databaseFactory.deleteDatabase(dbPath);
    repo = await freshRepo();
    final result = await repo.importAssetTablesJson(exported);
    final imported = repo.globalActivePhysicalAssets.singleWhere(
      (asset) => asset.name == '离线工作站',
    );
    expect(result.links, 0);
    expect(result.unresolvedTransactionLinks, 1);
    expect(result.rejectedLinks, 0);
    expect(repo.additionalCostLinksForAsset(imported.id), isEmpty);
    await repo.closeForTest();
  });

  test('资产 JSON 拒绝把 additional link 关联到收入交易', () async {
    var repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '校验工作站',
      currentValue: Decimal.fromInt(6000),
    );
    final maintenanceId = await addExpense(
      repo,
      note: '校验工作站维护',
      amount: Decimal.fromInt(90),
    );
    await repo.linkPhysicalAssetCost(
      assetId: assetId,
      transactionId: maintenanceId,
      type: AssetTransactionLinkType.maintenance,
    );
    final decoded =
        jsonDecode(await repo.exportAssetTablesJson()) as Map<String, dynamic>;
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    await databaseFactory.deleteDatabase(dbPath);
    repo = await freshRepo();
    final incomeId = await repo.addTransaction(
      kind: TransactionKind.income,
      amount: Decimal.fromInt(90),
      accountId: repo.accounts.first.id,
      note: '不是持有支出',
      date: DateTime(2026, 7, 13),
    );
    final incomeUuid =
        repo.transactions.singleWhere((item) => item.id == incomeId).uuid;
    final importedLink =
        (decoded['links'] as List).cast<Map<String, dynamic>>().single;
    importedLink['transaction_uuid'] = incomeUuid;

    final result = await repo.importAssetTablesJson(jsonEncode(decoded));
    final imported = repo.globalActivePhysicalAssets.singleWhere(
      (asset) => asset.name == '校验工作站',
    );
    expect(result.links, 0);
    expect(result.unresolvedTransactionLinks, 0);
    expect(result.rejectedLinks, 1);
    expect(repo.additionalCostLinksForAsset(imported.id), isEmpty);
    await repo.closeForTest();
  });

  test('资产 JSON 跳过重复和非法 usage 撤销且不回滚整批导入', () async {
    var repo = await freshRepo();
    final firstAssetId = await repo.addPhysicalAsset(
      name: '导入相机 A',
      currentValue: Decimal.fromInt(1000),
    );
    final secondAssetId = await repo.addPhysicalAsset(
      name: '导入相机 B',
      currentValue: Decimal.fromInt(1200),
    );
    await repo.setPhysicalAssetUsageTracking(firstAssetId, enabled: true);
    await repo.setPhysicalAssetUsageTracking(secondAssetId, enabled: true);
    await repo.recordPhysicalAssetUsage(firstAssetId);
    await repo.recordPhysicalAssetUsage(secondAssetId);
    await repo.undoLatestPhysicalAssetUsage(firstAssetId);
    final decoded =
        jsonDecode(await repo.exportAssetTablesJson()) as Map<String, dynamic>;
    final usage =
        (decoded['usage_events'] as List).cast<Map<String, dynamic>>();
    final firstOriginal = usage.singleWhere(
      (event) =>
          event['asset_id'] == firstAssetId && event['reversal_of'] == null,
    );
    final secondOriginal = usage.singleWhere(
      (event) =>
          event['asset_id'] == secondAssetId && event['reversal_of'] == null,
    );
    final validReversal = usage.singleWhere(
      (event) =>
          event['asset_id'] == firstAssetId &&
          event['reversal_of'] == firstOriginal['id'],
    );
    usage.addAll([
      {
        ...validReversal,
        'id': 900001,
        'uuid': 'dddddddddddddddddddddddddddddddd',
      },
      {
        ...validReversal,
        'id': 900002,
        'uuid': 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        'asset_id': secondAssetId,
      },
      {
        ...validReversal,
        'id': 900003,
        'uuid': 'ffffffffffffffffffffffffffffffff',
        'asset_id': secondAssetId,
        'reversal_of': secondOriginal['id'],
        'reversal_of_uuid': secondOriginal['uuid'],
        'count_delta': 1,
      },
      {
        ...validReversal,
        'id': 900004,
        'uuid': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab',
        'asset_id': secondAssetId,
        'reversal_of': secondOriginal['id'],
        'reversal_of_uuid': secondOriginal['uuid'],
        'count_delta': 0,
        'occurred_ms': (secondOriginal['occurred_ms'] as int) - 1,
      },
    ]);
    final payload = jsonEncode(decoded);
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    await databaseFactory.deleteDatabase(dbPath);
    repo = await freshRepo();
    final result = await repo.importAssetTablesJson(payload);

    expect(result.assets, 2);
    expect(result.usages, 3);
    final importedFirst = repo.globalActivePhysicalAssets.singleWhere(
      (asset) => asset.name == '导入相机 A',
    );
    final importedSecond = repo.globalActivePhysicalAssets.singleWhere(
      (asset) => asset.name == '导入相机 B',
    );
    expect(repo.usageEventsForAsset(importedFirst.id), hasLength(2));
    expect(repo.physicalAssetUsage(importedFirst.id).totalCount, 0);
    expect(repo.physicalAssetUsage(importedFirst.id).isExact, isTrue);
    expect(repo.usageEventsForAsset(importedSecond.id), hasLength(1));
    expect(repo.physicalAssetUsage(importedSecond.id).totalCount, 1);
    expect(repo.physicalAssetUsage(importedSecond.id).isExact, isTrue);
    await repo.closeForTest();

    repo = await freshRepo();
    expect(repo.usageEventsForAsset(importedFirst.id), hasLength(2));
    expect(repo.physicalAssetUsage(importedFirst.id).totalCount, 0);
    expect(repo.usageEventsForAsset(importedSecond.id), hasLength(1));
    expect(repo.physicalAssetUsage(importedSecond.id).totalCount, 1);
    expect(repo.physicalAssetUsage(importedSecond.id).isExact, isTrue);
    await repo.closeForTest();
  });

  test('v38 到 v42 等价迁移保留 B2 与资产证据并初始化 A4 字段', () async {
    var repo = await freshRepo();
    final planId = await repo.addBudgetPlanV2(
      bookId: repo.currentBookId,
      name: 'v38 主预算',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 300000,
      fixedTemplates: const [
        BudgetFixedTemplateV2(
          id: 'rent',
          name: '房租',
          plannedCents: 80000,
          dueValue: 15,
        ),
      ],
      monthStartDay: 1,
      startNextCycle: false,
    );
    final plan = repo.budgetPlansV2.singleWhere((item) => item.id == planId);
    final cycle = plan.cycleFor(DateTime.now());
    await repo.upsertBudgetCycleOverrideV2(
      planId: planId,
      cycleStart: cycle.start,
      targetAmountCents: 280000,
    );
    expect(
      repo.budgetFixedOccurrencesV2For(planId, cycleStart: cycle.start),
      isNotEmpty,
    );

    final purchaseId = await addExpense(
      repo,
      note: 'v38 相机购买',
      amount: Decimal.fromInt(1000),
    );
    final warranty = DateTime(2028, 6, 30);
    final assetId = await repo.addPhysicalAsset(
      name: 'v38 相机',
      currentValue: Decimal.fromInt(1000),
      sourceType: PhysicalAssetSourceType.fromTransaction,
      sourceTransactionId: purchaseId,
      warrantyUntil: warranty,
    );
    final purchase = repo.transactions.singleWhere(
      (item) => item.id == purchaseId,
    );
    await repo.refundTransaction(
      purchase,
      Decimal.fromInt(200),
      settledAt: DateTime(2026, 7, 14),
      settlementAccountId: repo.accounts.first.id,
    );
    final legacyGoalId = await repo.addSavingsGoal(
      name: 'v38 相机基金',
      target: Decimal.fromInt(3000),
      initialSaved: Decimal.fromInt(300),
    );
    final legacyGoalCreatedMs = repo.savingsGoalById(legacyGoalId)!.createdMs;
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    var db = await databaseFactory.openDatabase(dbPath);
    final evidence = await _captureV38Evidence(
      db,
      planId: planId,
      assetId: assetId,
    );
    expect(evidence.refundAllocation, isNotEmpty);
    await _downgradeToV38(db);
    await db.close();

    repo = await freshRepo();
    expect(
        repo.budgetPlansV2.singleWhere((item) => item.id == planId).isPrimary,
        isTrue);
    expect(repo.physicalAssetDetailById(assetId)!.warrantyUntil, warranty);
    expect(
        repo.physicalAssetDetailById(assetId)!.usageTrackingEnabled, isFalse);
    expect(repo.physicalAssetDetailById(assetId)!.savingsGoalId, isNull);
    final migratedGoal = repo.savingsGoalById(legacyGoalId)!;
    expect(migratedGoal.uuid, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(migratedGoal.updatedMs, legacyGoalCreatedMs);
    await repo.closeForTest();

    db = await databaseFactory.openDatabase(dbPath);
    expect(
      Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')),
      42,
    );
    expect(
      await _captureV38Evidence(db, planId: planId, assetId: assetId),
      evidence,
    );
    final planColumns = await _columnNames(db, 'budget_plans');
    final assetColumns = await _columnNames(db, 'physical_assets');
    final usageColumns = await _columnNames(db, 'asset_usage_events');
    final goalColumns = await _columnNames(db, 'savings_goals');
    expect(planColumns, contains('expense_scope_json'));
    expect(assetColumns,
        containsAll(['usage_tracking_enabled', 'savings_goal_id']));
    expect(goalColumns, containsAll(['uuid', 'updated_ms']));
    // v42：liability_profiles 账期两列 + 借入对象列在等价迁移后仍在。
    final liabilityColumns = await _columnNames(db, 'liability_profiles');
    expect(
      liabilityColumns,
      containsAll(['statement_day', 'credit_limit', 'counterparty']),
    );
    // v42：recurring_rules 加 to_account_id（A3 周期转账/房贷向导）。
    final recurringColumns = await _columnNames(db, 'recurring_rules');
    expect(recurringColumns, contains('to_account_id'));
    expect(
      usageColumns,
      containsAll([
        'uuid',
        'asset_id',
        'count_delta',
        'reversal_of',
        'occurred_ms',
        'created_ms',
        'updated_ms',
      ]),
    );
    final migratedPlan = await db.query(
      'budget_plans',
      columns: ['expense_scope_json'],
      where: 'id = ?',
      whereArgs: [planId],
    );
    final migratedAsset = await db.query(
      'physical_assets',
      columns: ['usage_tracking_enabled', 'savings_goal_id'],
      where: 'id = ?',
      whereArgs: [assetId],
    );
    expect(migratedPlan.single['expense_scope_json'], '');
    expect(migratedAsset.single['usage_tracking_enabled'], 0);
    expect(migratedAsset.single['savings_goal_id'], isNull);
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM asset_usage_events'),
      ),
      0,
    );

    final goalRows = await db.query(
      'savings_goals',
      columns: ['uuid', 'created_ms', 'updated_ms'],
      where: 'id = ?',
      whereArgs: [legacyGoalId],
    );
    expect(goalRows.single['uuid'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(goalRows.single['updated_ms'], goalRows.single['created_ms']);

    final usageIndexes = await db.rawQuery(
      "PRAGMA index_list('asset_usage_events')",
    );
    final reversalIndex = usageIndexes.singleWhere(
      (row) => row['name'] == 'idx_asset_usage_events_reversal',
    );
    expect(reversalIndex['unique'], 1);
    expect(reversalIndex['partial'], 1);

    final originalUsageId = await db.insert('asset_usage_events', {
      'uuid': 'migration-usage-original',
      'asset_id': assetId,
      'count_delta': 1,
      'reversal_of': null,
      'occurred_ms': 1,
      'note': '',
      'created_ms': 1,
      'updated_ms': 1,
    });
    await db.insert('asset_usage_events', {
      'uuid': 'migration-usage-reversal-1',
      'asset_id': assetId,
      'count_delta': 0,
      'reversal_of': originalUsageId,
      'occurred_ms': 2,
      'note': '',
      'created_ms': 2,
      'updated_ms': 2,
    });
    await expectLater(
      db.insert('asset_usage_events', {
        'uuid': 'migration-usage-reversal-2',
        'asset_id': assetId,
        'count_delta': 0,
        'reversal_of': originalUsageId,
        'occurred_ms': 3,
        'note': '',
        'created_ms': 3,
        'updated_ms': 3,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });

  test('早期 user_version 39 启动时自修复并保留兼容前备份', () async {
    var repo = await freshRepo();
    final goalId = await repo.addSavingsGoal(
      name: '早期 v39 目标',
      target: Decimal.fromInt(5000),
    );
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    var db = await databaseFactory.openDatabase(dbPath);
    await _downgradeToV38(db);
    await db.execute('PRAGMA user_version = 39');
    await db.close();

    repo = await freshRepo();
    final repairedGoal = repo.savingsGoalById(goalId)!;
    expect(repairedGoal.uuid, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(repairedGoal.updatedMs, repairedGoal.createdMs);
    await repo.closeForTest();

    final backup = File('$dbPath.pre-v39-compat.bak');
    expect(await backup.exists(), isTrue);
    final backupDb = await openReadOnlyDatabase(backup.path);
    expect(
      (await backupDb.rawQuery('PRAGMA quick_check')).single.values.single,
      'ok',
    );
    expect(
      Sqflite.firstIntValue(await backupDb.rawQuery('PRAGMA user_version')),
      39,
    );
    expect(
        await _columnNames(backupDb, 'savings_goals'), isNot(contains('uuid')));
    await backupDb.close();

    db = await databaseFactory.openDatabase(dbPath);
    expect(
        await _columnNames(db, 'budget_plans'), contains('expense_scope_json'));
    expect(
      await _columnNames(db, 'physical_assets'),
      containsAll(['usage_tracking_enabled', 'savings_goal_id']),
    );
    expect(await _columnNames(db, 'savings_goals'),
        containsAll(['uuid', 'updated_ms']));
    expect(
      (await db.rawQuery("PRAGMA index_list('asset_usage_events')"))
          .where((row) => row['name'] == 'idx_asset_usage_events_reversal'),
      hasLength(1),
    );
    await db.close();
  });

  test('v39 兼容修复按 occurred_ms 和 id 保留最早一条重复撤销', () async {
    var repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '历史重复撤销相机',
      currentValue: Decimal.fromInt(1000),
    );
    final otherAssetId = await repo.addPhysicalAsset(
      name: '跨物品脏撤销目标',
      currentValue: Decimal.fromInt(800),
    );
    await repo.setPhysicalAssetUsageTracking(assetId, enabled: true);
    final usageId = await repo.recordPhysicalAssetUsage(
      assetId,
      occurredAt: DateTime(2026, 7, 1),
    );
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    var db = await databaseFactory.openDatabase(dbPath);
    await db.execute('DROP INDEX idx_asset_usage_events_reversal');
    await db.execute('''
      CREATE UNIQUE INDEX idx_asset_usage_events_reversal
      ON asset_usage_events(reversal_of)
      WHERE reversal_of IS NULL
    ''');
    await db.insert('asset_usage_events', {
      'uuid': 'history-reversal-cross-asset',
      'asset_id': otherAssetId,
      'count_delta': 0,
      'reversal_of': usageId,
      'occurred_ms': DateTime(2026, 7, 2).millisecondsSinceEpoch,
      'note': '更早但跨物品的无效撤销',
      'created_ms': 1,
      'updated_ms': 1,
    });
    await db.insert('asset_usage_events', {
      'uuid': 'history-reversal-earliest-valid',
      'asset_id': assetId,
      'count_delta': 0,
      'reversal_of': usageId,
      'occurred_ms': DateTime(2026, 7, 3).millisecondsSinceEpoch,
      'note': '最早的有效撤销',
      'created_ms': 2,
      'updated_ms': 2,
    });
    final laterReversalId = await db.insert('asset_usage_events', {
      'uuid': 'history-reversal-later-valid',
      'asset_id': assetId,
      'count_delta': 0,
      'reversal_of': usageId,
      'occurred_ms': DateTime(2026, 7, 4).millisecondsSinceEpoch,
      'note': '较晚的重复有效撤销',
      'created_ms': 3,
      'updated_ms': 3,
    });
    await db.insert('asset_usage_events', {
      'uuid': 'history-redo-of-removed-reversal',
      'asset_id': assetId,
      'count_delta': 0,
      'reversal_of': laterReversalId,
      'occurred_ms': DateTime(2026, 7, 5).millisecondsSinceEpoch,
      'note': '引用稍后会被去重删除的撤销',
      'created_ms': 4,
      'updated_ms': 4,
    });
    await db.close();

    repo = await freshRepo();
    expect(repo.physicalAssetUsage(assetId).totalCount, 0);
    expect(repo.physicalAssetUsage(assetId).isExact, isTrue);
    expect(repo.usageEventsForAsset(otherAssetId), isEmpty);
    await repo.closeForTest();

    db = await databaseFactory.openDatabase(dbPath);
    final reversals = await db.query(
      'asset_usage_events',
      where: 'reversal_of = ?',
      whereArgs: [usageId],
    );
    expect(reversals, hasLength(1));
    expect(reversals.single['uuid'], 'history-reversal-earliest-valid');
    await expectLater(
      db.insert('asset_usage_events', {
        'uuid': 'history-reversal-rejected',
        'asset_id': assetId,
        'count_delta': 0,
        'reversal_of': usageId,
        'occurred_ms': DateTime(2026, 7, 4).millisecondsSinceEpoch,
        'note': '',
        'created_ms': 3,
        'updated_ms': 3,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });

  test('v39 正确唯一索引下仍清理跨物品撤销并释放真实撤销能力', () async {
    var repo = await freshRepo();
    final sourceAssetId = await repo.addPhysicalAsset(
      name: '正确索引源相机',
      currentValue: Decimal.fromInt(1000),
    );
    final foreignAssetId = await repo.addPhysicalAsset(
      name: '错误占用相机',
      currentValue: Decimal.fromInt(500),
    );
    await repo.setPhysicalAssetUsageTracking(sourceAssetId, enabled: true);
    final usageId = await repo.recordPhysicalAssetUsage(
      sourceAssetId,
      occurredAt: DateTime(2026, 7, 1),
    );
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    final db = await databaseFactory.openDatabase(dbPath);
    await db.insert('asset_usage_events', {
      'uuid': 'correct-index-cross-asset-reversal',
      'asset_id': foreignAssetId,
      'count_delta': 0,
      'reversal_of': usageId,
      'occurred_ms': DateTime(2026, 7, 2).millisecondsSinceEpoch,
      'note': '旧导入遗留的跨物品撤销',
      'created_ms': 2,
      'updated_ms': 2,
    });
    await db.close();

    repo = await freshRepo();
    expect(repo.usageEventsForAsset(foreignAssetId), isEmpty);
    expect(repo.physicalAssetUsage(sourceAssetId).totalCount, 1);
    await repo.undoLatestPhysicalAssetUsage(sourceAssetId);
    expect(repo.physicalAssetUsage(sourceAssetId).totalCount, 0);
    expect(repo.physicalAssetUsage(sourceAssetId).isExact, isTrue);
    await repo.closeForTest();
  });

  test('早期 v39 partial usage 表补齐列并重建 id 主键与 UUID 唯一约束', () async {
    var repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: 'partial usage 相机',
      currentValue: Decimal.fromInt(600),
    );
    await repo.setPhysicalAssetUsageTracking(assetId, enabled: true);
    final usageId = await repo.recordPhysicalAssetUsage(
      assetId,
      occurredAt: DateTime(2026, 7, 1),
    );
    final usageUuid = repo.usageEventsForAsset(assetId).single.uuid;
    await repo.closeForTest();

    final dbPath = p.join(tmp.path, 'qingji.db');
    var db = await databaseFactory.openDatabase(dbPath);
    await db.execute(
      'ALTER TABLE asset_usage_events RENAME TO asset_usage_events_full',
    );
    await db.execute('''
      CREATE TABLE asset_usage_events (
        uuid        TEXT NOT NULL,
        asset_id    INTEGER NOT NULL,
        count_delta INTEGER NOT NULL DEFAULT 0,
        occurred_ms INTEGER NOT NULL,
        created_ms  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      INSERT INTO asset_usage_events(
        uuid, asset_id, count_delta, occurred_ms, created_ms
      )
      SELECT uuid, asset_id, count_delta, occurred_ms, created_ms
      FROM asset_usage_events_full
      WHERE id = $usageId
    ''');
    await db.execute('DROP TABLE asset_usage_events_full');
    await db.execute('PRAGMA user_version = 39');
    await db.close();

    repo = await freshRepo();
    expect(repo.physicalAssetUsage(assetId).totalCount, 1);
    expect(repo.physicalAssetUsage(assetId).isExact, isTrue);
    final repairedUsage = repo.usageEventsForAsset(assetId).single;
    expect(repairedUsage.uuid, usageUuid);
    expect(repairedUsage.note, isEmpty);
    expect(repairedUsage.updatedMs, greaterThan(0));
    await repo.closeForTest();

    db = await databaseFactory.openDatabase(dbPath);
    final info = await db.rawQuery('PRAGMA table_info(asset_usage_events)');
    expect(
      info.map((row) => row['name']).whereType<String>(),
      containsAll([
        'id',
        'uuid',
        'asset_id',
        'count_delta',
        'reversal_of',
        'occurred_ms',
        'note',
        'created_ms',
        'updated_ms',
      ]),
    );
    expect(
      info.singleWhere((row) => row['name'] == 'id')['pk'],
      1,
    );
    await expectLater(
      db.insert('asset_usage_events', {
        'uuid': usageUuid,
        'asset_id': assetId,
        'count_delta': 1,
        'reversal_of': null,
        'occurred_ms': DateTime(2026, 7, 5).millisecondsSinceEpoch,
        'note': '',
        'created_ms': 5,
        'updated_ms': 5,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });

  test('从已有账单加入物品始终继承账单日期并统一事件与估值日期', () async {
    final repo = await freshRepo();
    final transactionDate = DateTime(2024, 3, 4, 15, 30);
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(1000),
      accountId: repo.accounts.first.id,
      note: '历史电脑订单',
      date: transactionDate,
    );

    final assetId = await repo.addPhysicalAsset(
      name: '历史电脑',
      currentValue: Decimal.fromInt(800),
      sourceType: PhysicalAssetSourceType.fromTransaction,
      sourceTransactionId: transactionId,
      purchaseDate: DateTime(2026, 7, 13),
      occurredAt: DateTime(2026, 7, 12),
    );

    final asset = repo.physicalAssetDetailById(assetId)!;
    expect(asset.purchaseDate, transactionDate);
    expect(repo.eventsForAsset(assetId).single.occurredAt, transactionDate);
    expect(repo.valuationsForAsset(assetId).single.valuedAt, transactionDate);
    expect(
      repo.physicalAssetAcquisitionCost(assetId).amount,
      Decimal.fromInt(1000),
    );
    await repo.closeForTest();
  });

  test('新购买必须明确购买日期且缺失时不产生任何资产或支出', () async {
    final repo = await freshRepo();
    final beforeTransactions = repo.transactions.length;
    final beforeAssets = repo.globalActivePhysicalAssets.length;

    await expectLater(
      repo.addPhysicalAsset(
        name: '缺日期的新手机',
        currentValue: Decimal.fromInt(3000),
        purchasePrice: Decimal.fromInt(3000),
        sourceType: PhysicalAssetSourceType.newPurchaseWithAccount,
        paymentAccountId: repo.accounts.first.id,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message.toString(),
          'message',
          contains('购买日期'),
        ),
      ),
    );

    expect(repo.transactions, hasLength(beforeTransactions));
    expect(repo.globalActivePhysicalAssets, hasLength(beforeAssets));
    await repo.closeForTest();
  });

  test('账单来源物品编辑锁定原账单日期且保修按自然日校验', () async {
    final repo = await freshRepo();
    final transactionDate = DateTime(2024, 3, 4, 15, 30);
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(1000),
      accountId: repo.accounts.first.id,
      note: '相机原始订单',
      date: transactionDate,
    );
    final assetId = await repo.addPhysicalAssetFromTransaction(
      transactionId: transactionId,
      name: '订单相机',
      allocatedGrossCents: 100000,
    );

    Future<void> edit({
      DateTime? purchaseDate,
      bool clear = false,
      DateTime? warrantyUntil,
    }) async {
      final asset = repo.physicalAssetDetailById(assetId)!;
      await repo.updatePhysicalAsset(
        id: asset.id,
        name: asset.name,
        assetType: asset.assetType,
        purchasePrice: asset.purchasePrice,
        currentValue: asset.currentValue,
        currencyCode: asset.currencyCode,
        status: asset.status,
        purchaseDate: purchaseDate,
        clearPurchaseDate: clear,
        brand: asset.brand,
        model: asset.model,
        location: asset.location,
        warrantyUntil: warrantyUntil ?? asset.warrantyUntil,
        note: asset.note,
        includeInNetWorth: asset.includeInNetWorth,
      );
    }

    await edit(
      purchaseDate: DateTime(2024, 3, 4),
      warrantyUntil: DateTime(2024, 3, 4),
    );
    expect(
        repo.physicalAssetDetailById(assetId)!.purchaseDate, transactionDate);
    expect(
      repo.physicalAssetDetailById(assetId)!.warrantyUntil,
      DateTime(2024, 3, 4),
    );

    await expectLater(
      edit(warrantyUntil: DateTime(2024, 3, 3)),
      throwsA(isA<ArgumentError>()),
    );

    await expectLater(
      edit(purchaseDate: DateTime(2024, 3, 5)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      edit(clear: true),
      throwsA(isA<StateError>()),
    );
    expect(
        repo.physicalAssetDetailById(assetId)!.purchaseDate, transactionDate);
    await repo.closeForTest();
  });

  test('开启自动折旧必须明确开始日期且不会回退到今天', () async {
    final repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '待设折旧电脑',
      currentValue: Decimal.fromInt(6000),
      purchasePrice: Decimal.fromInt(6000),
    );

    await expectLater(
      repo.configurePhysicalAssetDepreciation(
        id: assetId,
        enabled: true,
        depreciationBase: Decimal.fromInt(6000),
        salvageValue: Decimal.zero,
        usefulLifeMonths: 36,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message.toString(),
          'message',
          contains('开始日期'),
        ),
      ),
    );

    final asset = repo.physicalAssetDetailById(assetId)!;
    expect(asset.depreciationStartDate, isNull);
    expect(asset.hasLinearDepreciation, isFalse);
    await repo.closeForTest();
  });

  test('账单来源物品拒绝早于原账单购买日的保修日期', () async {
    final repo = await freshRepo();
    final transactionDate = DateTime(2024, 3, 4, 15, 30);
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(1000),
      accountId: repo.accounts.first.id,
      note: '电脑原始订单',
      date: transactionDate,
    );
    final invalidWarranty = DateTime(2024, 3, 3);

    await expectLater(
      repo.addPhysicalAssetFromTransaction(
        transactionId: transactionId,
        name: '错误保修电脑 A',
        allocatedGrossCents: 100000,
        warrantyUntil: invalidWarranty,
      ),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      repo.addPhysicalAsset(
        name: '错误保修电脑 B',
        currentValue: Decimal.fromInt(800),
        sourceType: PhysicalAssetSourceType.fromTransaction,
        sourceTransactionId: transactionId,
        warrantyUntil: invalidWarranty,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(repo.globalActivePhysicalAssets, isEmpty);

    final assetId = await repo.addPhysicalAssetFromTransaction(
      transactionId: transactionId,
      name: '同日保修电脑',
      allocatedGrossCents: 100000,
      warrantyUntil: DateTime(2024, 3, 4),
    );
    expect(
      repo.physicalAssetDetailById(assetId)!.purchaseDate,
      transactionDate,
    );
    await repo.closeForTest();
  });

  test('手工购置成本未知可持久化且不会以零成本冒充精确结果', () async {
    var repo = await freshRepo();
    final assetId = await repo.addPhysicalAsset(
      name: '别人送的相机',
      currentValue: Decimal.fromInt(3000),
      purchasePrice: Decimal.fromInt(5000),
      purchasePriceKnown: false,
      sourceType: PhysicalAssetSourceType.giftReceived,
    );
    var asset = repo.physicalAssetDetailById(assetId)!;
    var cost = repo.physicalAssetAcquisitionCost(assetId);
    expect(
        asset.acquisitionCostSource, AssetAcquisitionCostSource.manualUnknown);
    expect(asset.purchasePrice, Decimal.zero);
    expect(cost.isExact, isFalse);
    expect(cost.amount, isNull);
    expect(cost.reason, contains('未知'));

    final exported =
        jsonDecode(await repo.exportAssetTablesJson()) as Map<String, dynamic>;
    final exportedAsset = (exported['assets'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['uuid'] == asset.uuid);
    expect(exportedAsset['acquisition_cost_source'], 'manual_unknown');
    await repo.closeForTest();

    repo = await freshRepo();
    asset = repo.physicalAssetDetailById(assetId)!;
    cost = repo.physicalAssetAcquisitionCost(assetId);
    expect(
        asset.acquisitionCostSource, AssetAcquisitionCostSource.manualUnknown);
    expect(cost.amount, isNull);

    await repo.updatePhysicalAsset(
      id: assetId,
      name: '别人送的相机（已核价）',
      assetType: asset.assetType,
      purchasePrice: Decimal.fromInt(2600),
      currentValue: asset.currentValue,
      currencyCode: asset.currencyCode,
      status: asset.status,
      includeInNetWorth: asset.includeInNetWorth,
      purchasePriceKnown: true,
    );
    asset = repo.physicalAssetDetailById(assetId)!;
    cost = repo.physicalAssetAcquisitionCost(assetId);
    expect(asset.acquisitionCostSource, AssetAcquisitionCostSource.manual);
    expect(cost.isExact, isTrue);
    expect(cost.amount, Decimal.fromInt(2600));

    await repo.updatePhysicalAsset(
      id: assetId,
      name: asset.name,
      assetType: asset.assetType,
      purchasePrice: Decimal.fromInt(2600),
      currentValue: asset.currentValue,
      currencyCode: asset.currencyCode,
      status: asset.status,
      includeInNetWorth: asset.includeInNetWorth,
      purchasePriceKnown: false,
    );
    asset = repo.physicalAssetDetailById(assetId)!;
    cost = repo.physicalAssetAcquisitionCost(assetId);
    expect(
        asset.acquisitionCostSource, AssetAcquisitionCostSource.manualUnknown);
    expect(asset.purchasePrice, Decimal.zero);
    expect(cost.amount, isNull);

    final defaultKnownId = await repo.addPhysicalAsset(
      name: '默认兼容物品',
      currentValue: Decimal.fromInt(321),
    );
    expect(
      repo.physicalAssetAcquisitionCost(defaultKnownId).amount,
      Decimal.fromInt(321),
    );
    await repo.closeForTest();
  });

  test('编辑物品可显式清空购买日期和保修日期并保留默认兼容语义', () async {
    final repo = await freshRepo();
    final purchaseDate = DateTime(2024, 1, 2);
    final warrantyUntil = DateTime(2027, 1, 2);
    final assetId = await repo.addPhysicalAsset(
      name: '旧笔记本',
      currentValue: Decimal.fromInt(2000),
      purchasePrice: Decimal.fromInt(6000),
      purchaseDate: purchaseDate,
      warrantyUntil: warrantyUntil,
    );
    var asset = repo.physicalAssetDetailById(assetId)!;

    await repo.updatePhysicalAsset(
      id: assetId,
      name: '旧笔记本 Pro',
      assetType: asset.assetType,
      purchasePrice: asset.purchasePrice,
      currentValue: asset.currentValue,
      currencyCode: asset.currencyCode,
      status: asset.status,
      includeInNetWorth: asset.includeInNetWorth,
    );
    asset = repo.physicalAssetDetailById(assetId)!;
    expect(asset.purchaseDate, purchaseDate);
    expect(asset.warrantyUntil, warrantyUntil);

    await repo.updatePhysicalAsset(
      id: assetId,
      name: asset.name,
      assetType: asset.assetType,
      purchasePrice: asset.purchasePrice,
      currentValue: asset.currentValue,
      currencyCode: asset.currencyCode,
      status: asset.status,
      includeInNetWorth: asset.includeInNetWorth,
      clearPurchaseDate: true,
      clearWarrantyUntil: true,
    );
    asset = repo.physicalAssetDetailById(assetId)!;
    expect(asset.purchaseDate, isNull);
    expect(asset.warrantyUntil, isNull);
    await repo.closeForTest();
  });

  test('购买订单毛额已全部分配时不再作为新增物品候选', () async {
    final repo = await freshRepo();
    final transactionId = await repo.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      accountId: repo.accounts.first.id,
      note: '键鼠套装',
      date: DateTime(2026, 7, 1),
    );
    await repo.addPhysicalAssetFromTransaction(
      transactionId: transactionId,
      name: '键盘',
      allocatedGrossCents: 6000,
    );
    await repo.addPhysicalAssetFromTransaction(
      transactionId: transactionId,
      name: '鼠标',
      allocatedGrossCents: 4000,
    );
    final original = repo.transactions.singleWhere(
      (transaction) => transaction.id == transactionId,
    );
    await repo.refundTransaction(
      original,
      Decimal.fromInt(20),
      settledAt: DateTime(2026, 7, 2),
      settlementAccountId: repo.accounts.first.id,
    );

    expect(
      repo
          .eligiblePhysicalAssetPurchaseTransactions()
          .map((candidate) => candidate.transaction.id),
      isNot(contains(transactionId)),
    );
    await repo.closeForTest();
  });

  test('A2 借入：入账转账、一次性还款日与还款闭环', () async {
    final repo = await freshRepo();
    final payerId = repo.accounts.first.id;
    final payerBefore =
        repo.accountBalanceOf(repo.accounts.singleWhere((a) => a.id == payerId));
    final profileId = await repo.addPersonalBorrow(
      counterparty: '李四',
      amount: Decimal.fromInt(500),
      toAccountId: payerId,
      dueDate: DateTime.now().add(const Duration(days: 3)),
    );
    final profile =
        repo.liabilityProfiles.singleWhere((p) => p.id == profileId);
    expect(profile.type, LiabilityProfileType.personalBorrow);
    expect(profile.counterparty, '李四');
    expect(profile.currentPrincipal, Decimal.fromInt(500));
    final loanAccount =
        repo.accounts.singleWhere((a) => a.id == profile.accountId);
    expect(loanAccount.name, '借入·李四');
    expect(loanAccount.type, AccountType.loan);
    // 入账转账双腿：借入账户 -500、入账账户 +500，钱的去向有账可查。
    expect(repo.accountBalanceOf(loanAccount), Decimal.fromInt(-500));
    expect(
      repo.accountBalanceOf(
            repo.accounts.singleWhere((a) => a.id == payerId),
          ) -
          payerBefore,
      Decimal.fromInt(500),
    );
    final inflow = repo.transfersInvolvingAccount(loanAccount.id).single;
    expect(inflow.accountId, loanAccount.id);
    expect(inflow.toAccountId, payerId);

    // 一次性还款日进「最近要还」。
    final upcoming = repo.upcomingRepayments();
    expect(upcoming.single.profile.id, profileId);
    expect(upcoming.single.daysLeft, 3);

    // 部分还款：本金递减、不编利息；还清：paidOff + 最近要还清空 + 账户归零。
    final partial = await repo.repayLiabilityProfile(
      profileId: profileId,
      amount: Decimal.fromInt(200),
      fromAccountId: payerId,
    );
    expect(partial.principalPaid, Decimal.fromInt(200));
    expect(partial.interestPaid, Decimal.zero);
    expect(
      repo.liabilityProfiles
          .singleWhere((p) => p.id == profileId)
          .currentPrincipal,
      Decimal.fromInt(300),
    );
    await repo.repayLiabilityProfile(
      profileId: profileId,
      amount: Decimal.fromInt(300),
      fromAccountId: payerId,
    );
    expect(
      repo.liabilityProfiles.singleWhere((p) => p.id == profileId).status,
      LiabilityProfileStatus.paidOff,
    );
    expect(repo.upcomingRepayments(), isEmpty);
    expect(
      repo.accountBalanceOf(
        repo.accounts.singleWhere((a) => a.id == loanAccount.id),
      ),
      Decimal.zero,
    );
    // 时间线口径：转入借入账户的两笔还款转账都查得到。
    final repayments = repo
        .transfersInvolvingAccount(loanAccount.id)
        .where((t) => t.toAccountId == loanAccount.id)
        .toList();
    expect(repayments.length, 2);
    await repo.closeForTest();
  });

  test('A2 还款超本金：差额自动记利息支出，本金转账与账户余额都对得上', () async {
    final repo = await freshRepo();
    final payerId = repo.accounts.first.id;
    final payerBefore = repo.accountBalanceOf(
      repo.accounts.singleWhere((a) => a.id == payerId),
    );
    final profileId = await repo.addPersonalBorrow(
      counterparty: '钱七',
      amount: Decimal.fromInt(500),
      toAccountId: payerId,
    );
    final profile =
        repo.liabilityProfiles.singleWhere((p) => p.id == profileId);

    // 还 520：本金只有 500，多出的 20 是利息，必须拆成单独一笔支出。
    final result = await repo.repayLiabilityProfile(
      profileId: profileId,
      amount: Decimal.fromInt(520),
      fromAccountId: payerId,
    );
    expect(result.principalPaid, Decimal.fromInt(500));
    expect(result.interestPaid, Decimal.fromInt(20));
    expect(result.transferTransactionId, isNotNull);
    expect(result.interestTransactionId, isNotNull);

    // 本金转账 = 500（不是 520）：负债账户恰好归零，档案结清。
    final loanAccount =
        repo.accounts.singleWhere((a) => a.id == profile.accountId);
    expect(repo.accountBalanceOf(loanAccount), Decimal.zero);
    expect(
      repo.liabilityProfiles.singleWhere((p) => p.id == profileId).status,
      LiabilityProfileStatus.paidOff,
    );

    // 利息 20 = 真支出（excluded=0、事件类型 interest、从还款账户出）。
    final interestTx = repo.visibleTransactions
        .singleWhere((t) => t.id == result.interestTransactionId);
    expect(interestTx.txKind, TransactionKind.expense);
    expect(interestTx.amount, Decimal.fromInt(20));
    expect(interestTx.excluded, isFalse);
    expect(interestTx.eventType, TransactionEventType.interest);
    expect(interestTx.accountId, payerId);
    expect(interestTx.note, contains('还款利息'));

    // 还款账户净变化 = +500（借入到账）- 520（还款总划扣）= -20。
    expect(
      repo.accountBalanceOf(
            repo.accounts.singleWhere((a) => a.id == payerId),
          ) -
          payerBefore,
      Decimal.fromInt(-20),
    );
    await repo.closeForTest();
  });

  test('A2 借出收回带利息：利息记真收入，撤销收回时一并删除', () async {
    final repo = await freshRepo();
    final account = repo.accounts.first;
    final assetId = await repo.addReceivableAsset(
      name: '借给张三',
      type: ReceivableAssetType.loanOut,
      originalAmount: Decimal.fromInt(1000),
    );

    // 利息>0 却不给到账账户：利息是真钱，必须拒绝。
    await expectLater(
      repo.recoverReceivableAsset(
        id: assetId,
        amount: Decimal.fromInt(1000),
        interestAmount: Decimal.fromInt(30),
      ),
      throwsArgumentError,
    );

    await repo.recoverReceivableAsset(
      id: assetId,
      amount: Decimal.fromInt(1000),
      targetAccountId: account.id,
      interestAmount: Decimal.fromInt(30),
      recoveredAt: DateTime(2026, 7, 20),
    );
    // 本金收回 1000 = excluded 形态转换；利息 30 = 真收入（进统计）。
    final interestTx = repo.visibleTransactions.singleWhere(
      (t) => t.txKind == TransactionKind.income && !t.excluded,
    );
    expect(interestTx.amount, Decimal.fromInt(30));
    // 事件类型必须是 income（不是 interest）：三套结算引擎把 interest
    // 事件一律当流出，收入行打 interest 会让账户余额反向。
    expect(interestTx.eventType, TransactionEventType.income);
    expect(interestTx.note, contains('借出利息'));
    expect(
      repo.allRecords
          .where((r) => r.kind == TransactionKind.income)
          .single
          .amount,
      Decimal.fromInt(30),
    );
    expect(repo.accountBalanceOf(account), Decimal.fromInt(1030));

    // 撤销收回：本金流水和利息流水一并删，账户余额回到 0，审计链闭合。
    await repo.undoReceivableRecovery(repo.receivableRecoveries.single.id);
    expect(repo.visibleTransactions, isEmpty);
    expect(
      repo.allRecords.where((r) => r.kind == TransactionKind.income),
      isEmpty,
    );
    expect(repo.accountBalanceOf(account), Decimal.zero);
    expect(
      repo.receivableAssets
          .singleWhere((a) => a.id == assetId)
          .remainingAmount,
      Decimal.fromInt(1000),
    );
    await repo.closeForTest();
  });

  test('A2 借入：无入账账户走期初负余额、同名对象加序号、逾期为负天数', () async {
    final repo = await freshRepo();
    final firstId = await repo.addPersonalBorrow(
      counterparty: '王五',
      amount: Decimal.fromInt(300),
    );
    final first = repo.liabilityProfiles.singleWhere((p) => p.id == firstId);
    final firstAccount =
        repo.accounts.singleWhere((a) => a.id == first.accountId);
    expect(firstAccount.name, '借入·王五');
    // 不选入账账户：不编造到账流水，欠款如实落在期初负余额上。
    expect(repo.transfersInvolvingAccount(firstAccount.id), isEmpty);
    expect(repo.accountBalanceOf(firstAccount), Decimal.fromInt(-300));

    final secondId = await repo.addPersonalBorrow(
      counterparty: '王五',
      amount: Decimal.fromInt(200),
      dueDate: DateTime.now().subtract(const Duration(days: 2)),
    );
    final second = repo.liabilityProfiles.singleWhere((p) => p.id == secondId);
    // 每笔借入独立档案+独立账户（同名加序号），日期金额不合并造假。
    expect(second.accountId, isNot(first.accountId));
    expect(
      repo.accounts.singleWhere((a) => a.id == second.accountId).name,
      '借入·王五·2',
    );
    // 逾期的一次性还款日照样出现在「最近要还」，daysLeft 为负数。
    final upcoming = repo.upcomingRepayments();
    expect(upcoming.single.profile.id, secondId);
    expect(upcoming.single.daysLeft, -2);

    await expectLater(
      repo.addPersonalBorrow(counterparty: '  ', amount: Decimal.one),
      throwsArgumentError,
    );
    await expectLater(
      repo.addPersonalBorrow(counterparty: '赵六', amount: Decimal.zero),
      throwsArgumentError,
    );
    await repo.closeForTest();
  });

  test('A3 房贷向导：一次事务建齐账户/档案/周期转账，首期当天到期立即记账', () async {
    final repo = await freshRepo();
    final payerId = await repo.addAccount(
      name: '工资卡',
      openingBalance: Decimal.fromInt(20000),
    );
    final today = DateTime.now();

    // 非法输入不落任何一件套。
    await expectLater(
      repo.createLoanWizardSetup(
        type: LiabilityProfileType.mortgage,
        name: '房贷',
        totalAmount: Decimal.fromInt(1000000),
        remainingPrincipal: Decimal.fromInt(800000),
        monthlyPayment: Decimal.zero,
        repaymentDay: today.day,
        fromAccountId: payerId,
      ),
      throwsArgumentError,
    );
    expect(repo.recurringRules, isEmpty);

    final result = await repo.createLoanWizardSetup(
      type: LiabilityProfileType.mortgage,
      name: '房贷',
      totalAmount: Decimal.fromInt(1000000),
      remainingPrincipal: Decimal.fromInt(800000),
      annualRate: Decimal.parse('3.1'),
      monthlyPayment: Decimal.fromInt(5000),
      repaymentDay: today.day,
      fromAccountId: payerId,
    );

    // 账户：loan、计入净资产。
    final loanAccount =
        repo.accounts.singleWhere((a) => a.id == result.accountId);
    expect(loanAccount.type, AccountType.loan);
    expect(loanAccount.includeInNetWorth, isTrue);

    // 档案：类型/金额/还款日/扣款账户如实入档，利率只存档展示。
    final profile = repo.liabilityProfileForAccount(result.accountId)!;
    expect(profile.id, result.profileId);
    expect(profile.type, LiabilityProfileType.mortgage);
    expect(profile.originalAmount, Decimal.fromInt(1000000));
    expect(profile.currentPrincipal, Decimal.fromInt(800000));
    expect(profile.interestRate, Decimal.parse('3.1'));
    expect(profile.repaymentDay, today.day);
    expect(profile.repaymentAccountId, payerId);

    // 周期规则：每月转账（扣款账户 → 贷款账户），锚定还款日。
    final rule = repo.recurringRules.singleWhere((r) => r.id == result.ruleId);
    expect(rule.txKind, TransactionKind.transfer);
    expect(rule.accountId, payerId);
    expect(rule.toAccountId, result.accountId);
    expect(rule.anchorDay, today.day);
    expect(rule.generatedCount, 1);

    // 还款日 = 今天 → 首期立即记账，两腿余额正确：
    // 工资卡 20000-5000，贷款账户 -800000+5000（不做本息拆分，按月供全额）。
    final tx = repo.transactions
        .singleWhere((t) => t.recurringRuleId == result.ruleId);
    expect(tx.txKind, TransactionKind.transfer);
    expect(tx.accountId, payerId);
    expect(tx.toAccountId, result.accountId);
    final payer = repo.accounts.singleWhere((a) => a.id == payerId);
    expect(repo.accountBalanceOf(payer), Decimal.fromInt(15000));
    expect(repo.accountBalanceOf(loanAccount), Decimal.fromInt(-795000));
    await repo.closeForTest();
  });
}

class _V38Evidence {
  final Map<String, Object?> plan;
  final Map<String, Object?> revision;
  final Map<String, Object?> cycleOverride;
  final Map<String, Object?> fixedOccurrence;
  final Map<String, Object?> asset;
  final Map<String, Object?> purchaseLink;
  final Map<String, Object?> refundAllocation;

  const _V38Evidence({
    required this.plan,
    required this.revision,
    required this.cycleOverride,
    required this.fixedOccurrence,
    required this.asset,
    required this.purchaseLink,
    required this.refundAllocation,
  });

  @override
  bool operator ==(Object other) =>
      other is _V38Evidence &&
      _mapsEqual(plan, other.plan) &&
      _mapsEqual(revision, other.revision) &&
      _mapsEqual(cycleOverride, other.cycleOverride) &&
      _mapsEqual(fixedOccurrence, other.fixedOccurrence) &&
      _mapsEqual(asset, other.asset) &&
      _mapsEqual(purchaseLink, other.purchaseLink) &&
      _mapsEqual(refundAllocation, other.refundAllocation);

  @override
  int get hashCode => Object.hash(
        plan.toString(),
        revision.toString(),
        cycleOverride.toString(),
        fixedOccurrence.toString(),
        asset.toString(),
        purchaseLink.toString(),
        refundAllocation.toString(),
      );
}

bool _mapsEqual(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

Future<Set<String>> _columnNames(Database db, String table) async =>
    (await db.rawQuery('PRAGMA table_info($table)'))
        .map((row) => row['name'] as String)
        .toSet();

Future<_V38Evidence> _captureV38Evidence(
  Database db, {
  required int planId,
  required int assetId,
}) async {
  Future<Map<String, Object?>> one(
    String table,
    List<String> columns, {
    String where = 'id = ?',
    required List<Object?> whereArgs,
    String? orderBy,
  }) async {
    final rows = await db.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: 1,
    );
    return Map<String, Object?>.from(rows.single);
  }

  final occurrence = await one(
    'budget_fixed_commitment_occurrences',
    const [
      'uuid',
      'plan_id',
      'revision_id',
      'template_id',
      'cycle_start_day',
      'cycle_end_day',
      'due_day',
      'planned_cents',
      'resolution_status',
      'review_reason',
      'matched_transaction_family_uuid',
      'resolved_ms',
      'created_ms',
      'updated_ms',
    ],
    where: 'plan_id = ?',
    whereArgs: [planId],
    orderBy: 'id ASC',
  );
  final link = await one(
    'asset_transaction_links',
    const [
      'uuid',
      'asset_id',
      'asset_object_type',
      'transaction_id',
      'link_type',
      'amount',
      'allocated_gross_cents',
      'allocated_refund_cents',
      'cost_quality',
      'note',
      'created_ms',
      'updated_ms',
    ],
    where:
        "asset_id = ? AND link_type IN ('source_transaction', 'purchase_transaction')",
    whereArgs: [assetId],
  );
  final refundRows = await db.query(
    'asset_refund_allocations',
    columns: const [
      'uuid',
      'asset_transaction_link_id',
      'refund_transaction_id',
      'allocated_refund_cents',
      'status',
      'created_ms',
      'updated_ms',
    ],
    where: 'asset_transaction_link_id = ?',
    whereArgs: [
      Sqflite.firstIntValue(
        await db.query(
          'asset_transaction_links',
          columns: const ['id'],
          where: 'uuid = ?',
          whereArgs: [link['uuid']],
          limit: 1,
        ),
      ),
    ],
    orderBy: 'id ASC',
    limit: 1,
  );
  return _V38Evidence(
    plan: await one(
      'budget_plans',
      const [
        'uuid',
        'book_id',
        'currency_code',
        'timezone',
        'name',
        'role',
        'cadence',
        'anchor_start_day',
        'month_start_day',
        'week_start',
        'end_day',
        'status',
        'created_ms',
        'updated_ms',
      ],
      whereArgs: [planId],
    ),
    revision: await one(
      'budget_plan_revisions',
      const [
        'uuid',
        'plan_id',
        'effective_cycle_start_day',
        'effective_to_cycle_start_day',
        'amount_cents',
        'category_budgets_json',
        'monthly_income_cents',
        'fixed_templates_json',
        'legacy_source_period_id',
        'created_ms',
        'updated_ms',
      ],
      where: 'plan_id = ?',
      whereArgs: [planId],
      orderBy: 'id ASC',
    ),
    cycleOverride: await one(
      'budget_cycle_overrides',
      const [
        'uuid',
        'plan_id',
        'cycle_start_day',
        'cycle_end_day',
        'target_amount_cents',
        'category_budgets_json',
        'input_intent',
        'input_delta_cents',
        'created_ms',
        'updated_ms',
      ],
      where: 'plan_id = ?',
      whereArgs: [planId],
    ),
    fixedOccurrence: occurrence,
    asset: await one(
      'physical_assets',
      const [
        'uuid',
        'book_id',
        'name',
        'asset_type',
        'status',
        'economic_status',
        'usage_status',
        'visibility_status',
        'inclusion_quality',
        'source_type',
        'acquisition_cost_source',
        'purchase_price',
        'current_value',
        'currency_code',
        'purchase_date_ms',
        'warranty_until_ms',
        'include_in_net_worth',
        'is_deleted',
        'ended_ms',
        'archived_ms',
        'created_ms',
        'updated_ms',
      ],
      whereArgs: [assetId],
    ),
    purchaseLink: link,
    refundAllocation: Map<String, Object?>.from(refundRows.single),
  );
}

Future<void> _downgradeToV38(Database db) async {
  await db.transaction((txn) async {
    await txn.execute('ALTER TABLE budget_plans RENAME TO budget_plans_v39');
    await txn.execute('''
      CREATE TABLE budget_plans (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid              TEXT NOT NULL UNIQUE,
        book_id           INTEGER NOT NULL,
        currency_code     TEXT NOT NULL DEFAULT 'CNY',
        timezone          TEXT NOT NULL DEFAULT 'device_local',
        name              TEXT NOT NULL DEFAULT '',
        role              TEXT NOT NULL DEFAULT 'primary',
        cadence           TEXT NOT NULL,
        anchor_start_day  INTEGER NOT NULL,
        month_start_day   INTEGER,
        week_start        INTEGER,
        end_day           INTEGER,
        status            TEXT NOT NULL DEFAULT 'active',
        created_ms        INTEGER NOT NULL,
        updated_ms        INTEGER NOT NULL
      )
    ''');
    await txn.execute('''
      INSERT INTO budget_plans(
        id,uuid,book_id,currency_code,timezone,name,role,cadence,
        anchor_start_day,month_start_day,week_start,end_day,status,
        created_ms,updated_ms
      )
      SELECT id,uuid,book_id,currency_code,timezone,name,role,cadence,
        anchor_start_day,month_start_day,week_start,end_day,status,
        created_ms,updated_ms
      FROM budget_plans_v39
    ''');
    await txn.execute('DROP TABLE budget_plans_v39');
    await txn.execute('''
      CREATE INDEX idx_budget_plans_scope
      ON budget_plans(book_id, role, status, anchor_start_day, end_day)
    ''');

    await txn.execute(
      'ALTER TABLE physical_assets RENAME TO physical_assets_v39',
    );
    await txn.execute('''
      CREATE TABLE physical_assets (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid                  TEXT NOT NULL UNIQUE,
        book_id               INTEGER,
        name                  TEXT NOT NULL,
        asset_type            TEXT NOT NULL DEFAULT 'other',
        status                TEXT NOT NULL DEFAULT 'active',
        economic_status       TEXT NOT NULL DEFAULT 'owned',
        usage_status          TEXT NOT NULL DEFAULT 'active',
        visibility_status     TEXT NOT NULL DEFAULT 'active',
        inclusion_quality     TEXT NOT NULL DEFAULT 'confirmed',
        source_type           TEXT NOT NULL DEFAULT 'historical_existing',
        acquisition_cost_source TEXT NOT NULL DEFAULT 'manual',
        purchase_price        TEXT NOT NULL DEFAULT '0',
        current_value         TEXT NOT NULL DEFAULT '0',
        currency_code         TEXT NOT NULL DEFAULT 'CNY',
        purchase_date_ms      INTEGER,
        brand                 TEXT NOT NULL DEFAULT '',
        model                 TEXT NOT NULL DEFAULT '',
        location              TEXT NOT NULL DEFAULT '',
        warranty_until_ms     INTEGER,
        photo_path            TEXT NOT NULL DEFAULT '',
        thumbnail_path        TEXT NOT NULL DEFAULT '',
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
        ended_ms              INTEGER,
        archived_ms           INTEGER,
        created_ms            INTEGER NOT NULL DEFAULT 0,
        updated_ms            INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await txn.execute('''
      INSERT INTO physical_assets(
        id,uuid,book_id,name,asset_type,status,economic_status,usage_status,
        visibility_status,inclusion_quality,source_type,
        acquisition_cost_source,purchase_price,current_value,currency_code,
        purchase_date_ms,brand,model,location,warranty_until_ms,photo_path,
        thumbnail_path,invoice_path,depreciation_method,depreciation_base,
        salvage_value,useful_life_months,depreciation_start_ms,
        depreciation_paused,note,include_in_net_worth,is_deleted,ended_ms,
        archived_ms,created_ms,updated_ms
      )
      SELECT id,uuid,book_id,name,asset_type,status,economic_status,
        usage_status,visibility_status,inclusion_quality,source_type,
        acquisition_cost_source,purchase_price,current_value,currency_code,
        purchase_date_ms,brand,model,location,warranty_until_ms,photo_path,
        thumbnail_path,invoice_path,depreciation_method,depreciation_base,
        salvage_value,useful_life_months,depreciation_start_ms,
        depreciation_paused,note,include_in_net_worth,is_deleted,ended_ms,
        archived_ms,created_ms,updated_ms
      FROM physical_assets_v39
    ''');
    await txn.execute('DROP TABLE physical_assets_v39');
    await txn.execute('''
      CREATE INDEX idx_physical_assets_book_status
      ON physical_assets(book_id, status, is_deleted)
    ''');
    await txn.execute('''
      CREATE INDEX idx_physical_assets_global_visibility
      ON physical_assets(
        is_deleted, visibility_status, economic_status, updated_ms DESC
      )
    ''');
    await txn.execute('''
      CREATE INDEX idx_physical_assets_book_visibility
      ON physical_assets(
        book_id, is_deleted, visibility_status, updated_ms DESC
      )
    ''');

    await txn.execute(
      'ALTER TABLE savings_goals RENAME TO savings_goals_v39',
    );
    await txn.execute('''
      CREATE TABLE savings_goals (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL,
        emoji         TEXT NOT NULL DEFAULT '🐷',
        target_amount TEXT NOT NULL DEFAULT '0',
        saved_amount  TEXT NOT NULL DEFAULT '0',
        created_ms    INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await txn.execute('''
      INSERT INTO savings_goals(
        id,name,emoji,target_amount,saved_amount,created_ms
      )
      SELECT id,name,emoji,target_amount,saved_amount,created_ms
      FROM savings_goals_v39
    ''');
    await txn.execute('DROP TABLE savings_goals_v39');

    await txn.execute('DROP TABLE IF EXISTS asset_usage_events');
    await txn.execute('PRAGMA user_version = 38');
  });
}
