import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_plan_v2.dart';
import 'package:qingji/core/budget/budget_special_tracking.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  AppRepository? openRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory =
        Directory.systemTemp.createTempSync('feimiao_special_repo_test_');
    await databaseFactory.setDatabasesPath(temporaryDirectory.path);
  });

  tearDown(() async {
    final repository = openRepository;
    openRepository = null;
    if (repository != null) {
      await repository.closeForTest();
    }
    try {
      temporaryDirectory.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppRepository> openFreshRepository() async {
    final repository = AppRepository();
    await repository.init();
    openRepository = repository;
    return repository;
  }

  BudgetWindowResult currentPrimaryResult(
    AppRepository repository,
    int bookId,
    DateTime reference,
  ) {
    final queryTime = DateTime.now().add(const Duration(seconds: 1));
    return repository.budgetWindow(BudgetWindowQuery(
      viewKind: BudgetViewKind.cycle,
      bookId: bookId,
      referenceDate: reference,
      asOf: queryTime,
      knowledgeCutoff: queryTime,
    ));
  }

  List<BudgetSpecialTrackingResult> specialResults(
    AppRepository repository,
    int bookId,
    DateTime reference, {
    bool includeArchived = false,
    DateTime? windowStartInclusive,
    DateTime? windowEndExclusive,
    DateTime? asOf,
    DateTime? knowledgeCutoff,
  }) {
    final queryTime = DateTime.now().add(const Duration(seconds: 1));
    return repository.budgetSpecialTrackings(
      bookId: bookId,
      windowStartInclusive:
          windowStartInclusive ?? reference.subtract(const Duration(days: 10)),
      windowEndExclusive:
          windowEndExclusive ?? reference.add(const Duration(days: 11)),
      asOf: asOf ?? queryTime,
      knowledgeCutoff: knowledgeCutoff ?? queryTime,
      includeArchived: includeArchived,
    );
  }

  test(
      'B3 special tracking persists beside primary, observes OR scope and refunds, and archives without changing primary',
      () async {
    var repository = await openFreshRepository();
    final reference = DateTime.now();
    final day = DateTime(reference.year, reference.month, reference.day);
    final bookId = repository.currentBookId;
    final accountId = repository.accounts.first.id;
    final dining = repository.categories.firstWhere(
      (category) => category.key == 'dining',
    );
    final tagId = await repository.addTag(
      name: '年度计划',
      colorValue: 0xFF8C7A5B,
    );

    final primaryPlanId = await repository.addBudgetPlanV2(
      bookId: bookId,
      name: '日常主预算',
      cadence: BudgetPlanCadenceV2.monthly,
      totalCents: 1000000,
      monthStartDay: 1,
      startNextCycle: false,
      fixedTemplates: [
        BudgetFixedTemplateV2(
          id: 'rent',
          name: '房租',
          plannedCents: 100000,
          dueValue: reference.day.clamp(1, 28),
        ),
      ],
    );
    final taggedTransactionId = await repository.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(100),
      categoryId: dining.id,
      accountId: accountId,
      date: day,
      tagIds: [tagId],
      bookId: bookId,
      note: '旅行餐费',
    );
    await repository.addTransaction(
      kind: TransactionKind.expense,
      amount: Decimal.fromInt(50),
      categoryId: dining.id,
      accountId: accountId,
      date: day,
      bookId: bookId,
      note: '普通餐费',
    );

    final beforeSpecial = currentPrimaryResult(repository, bookId, day);
    expect(beforeSpecial.plannedCents, 1000000);
    expect(beforeSpecial.spentCents, 15000);
    expect(beforeSpecial.currentCycleDailyStatus, isNotNull);
    expect(beforeSpecial.fixedReserveCents, 100000);
    final primarySnapshot = (
      planned: beforeSpecial.plannedCents,
      spent: beforeSpecial.spentCents,
      todayAllowance:
          beforeSpecial.currentCycleDailyStatus!.todayRemainingAllowanceCents,
      fixedReserve: beforeSpecial.fixedReserveCents,
    );

    final categorySpecialId = await repository.saveBudgetSpecialTrackingV2(
      bookId: bookId,
      name: '餐饮专项追踪',
      startInclusive: day.subtract(const Duration(days: 2)),
      endInclusive: day.add(const Duration(days: 2)),
      totalCents: 50000,
      expenseScope: BudgetExpenseScopeV2(
        categoryKeys: const ['dining'],
      ),
    );
    final tagSpecialId = await repository.saveBudgetSpecialTrackingV2(
      bookId: bookId,
      name: '年度计划追踪',
      startInclusive: day.subtract(const Duration(days: 2)),
      endInclusive: day.add(const Duration(days: 2)),
      totalCents: 60000,
      // A family matches this mixed scope by category OR tag. The seeded
      // transaction is dining, so only its selected tag can match here.
      expenseScope: BudgetExpenseScopeV2(
        categoryKeys: const ['shopping'],
        tagIds: [tagId],
      ),
    );

    final plansById = {
      for (final plan in repository.budgetPlansV2) plan.id: plan,
    };
    expect(plansById[primaryPlanId]!.isPrimary, isTrue);
    expect(plansById[categorySpecialId]!.isSpecial, isTrue);
    expect(plansById[tagSpecialId]!.isSpecial, isTrue);
    expect(
      plansById[categorySpecialId]!.covers(day) &&
          plansById[tagSpecialId]!.covers(day) &&
          plansById[primaryPlanId]!.covers(day),
      isTrue,
      reason: 'primary and multiple special trackers may overlap',
    );

    final afterSpecial = currentPrimaryResult(repository, bookId, day);
    expect(afterSpecial.plannedCents, primarySnapshot.planned);
    expect(afterSpecial.spentCents, primarySnapshot.spent);
    expect(
      afterSpecial.currentCycleDailyStatus!.todayRemainingAllowanceCents,
      primarySnapshot.todayAllowance,
    );
    expect(afterSpecial.fixedReserveCents, primarySnapshot.fixedReserve);

    var trackers = specialResults(repository, bookId, day);
    expect(trackers, hasLength(2));
    expect(
      trackers
          .singleWhere((item) => item.plan.id == categorySpecialId)
          .spentCents,
      15000,
      reason: 'category scope observes both dining families',
    );
    expect(
      trackers.singleWhere((item) => item.plan.id == tagSpecialId).spentCents,
      10000,
      reason: 'mixed scope observes the tagged family through OR semantics',
    );

    final taggedTransaction = repository.transactions.firstWhere(
      (transaction) => transaction.id == taggedTransactionId,
    );
    await repository.refundTransaction(
      taggedTransaction,
      Decimal.fromInt(30),
      settledAt: DateTime.now(),
      settlementAccountId: accountId,
    );
    trackers = specialResults(repository, bookId, day);
    expect(
      trackers
          .singleWhere((item) => item.plan.id == categorySpecialId)
          .spentCents,
      12000,
      reason: 'category tracker uses the attached-refund family net',
    );
    expect(
      trackers.singleWhere((item) => item.plan.id == tagSpecialId).spentCents,
      7000,
      reason: 'tag tracker uses the same attached-refund family net',
    );

    await repository.archiveBudgetPlanV2(categorySpecialId);
    expect(specialResults(repository, bookId, day), hasLength(1));
    final history = specialResults(
      repository,
      bookId,
      day,
      includeArchived: true,
    );
    expect(history, hasLength(2));
    expect(
      history
          .singleWhere((item) => item.plan.id == categorySpecialId)
          .lifecycleStatus,
      BudgetSpecialLifecycleStatus.archived,
    );

    await repository.closeForTest();
    openRepository = null;
    repository = await openFreshRepository();

    final persistedTagPlan = repository.budgetSpecialPlansV2.singleWhere(
      (plan) => plan.id == tagSpecialId,
    );
    expect(persistedTagPlan.anchorStart, day.subtract(const Duration(days: 2)));
    expect(persistedTagPlan.endInclusive, day.add(const Duration(days: 2)));
    expect(persistedTagPlan.expenseScope.categoryKeys, {'shopping'});
    expect(persistedTagPlan.expenseScope.tagIds, {tagId});
    expect(
      repository.budgetPlanRevisionsV2For(tagSpecialId).single.amountCents,
      60000,
    );
    final afterRestart = specialResults(repository, bookId, day);
    expect(afterRestart, hasLength(1));
    expect(afterRestart.single.plan.id, tagSpecialId);
    expect(afterRestart.single.totalCents, 60000);
    expect(afterRestart.single.spentCents, 7000);
    expect(
      specialResults(
        repository,
        bookId,
        day,
        includeArchived: true,
      ),
      hasLength(2),
    );
  });

  test('B3 编辑新建 active successor，knowledge cutoff 恢复旧范围和额度，归档前仍为 active',
      () async {
    var repository = await openFreshRepository();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final bookId = repository.currentBookId;
    final dining = repository.categories.firstWhere(
      (category) => category.key == 'dining',
    );
    final shopping = repository.categories.firstWhere(
      (category) => category.key == 'shopping',
    );
    final oldStart = day.subtract(const Duration(days: 20));
    final oldEnd = day.subtract(const Duration(days: 15));
    final newStart = day.add(const Duration(days: 15));
    final newEnd = day.add(const Duration(days: 20));

    final oldPlanId = await repository.saveBudgetSpecialTrackingV2(
      bookId: bookId,
      name: '旧餐饮专项',
      startInclusive: oldStart,
      endInclusive: oldEnd,
      totalCents: 50000,
      expenseScope: BudgetExpenseScopeV2(
        categoryKeys: [dining.key],
      ),
    );
    final original = repository.budgetPlansV2.singleWhere(
      (plan) => plan.id == oldPlanId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final newPlanId = await repository.saveBudgetSpecialTrackingV2(
      planId: oldPlanId,
      bookId: bookId,
      name: '新购物专项',
      startInclusive: newStart,
      endInclusive: newEnd,
      totalCents: 90000,
      expenseScope: BudgetExpenseScopeV2(
        categoryKeys: [shopping.key],
      ),
    );
    expect(newPlanId, isNot(oldPlanId));
    final plansById = {
      for (final plan in repository.budgetPlansV2) plan.id: plan,
    };
    final superseded = plansById[oldPlanId]!;
    final successor = plansById[newPlanId]!;
    expect(superseded.status, BudgetPlanStatusV2.archived);
    expect(successor.status, BudgetPlanStatusV2.active);
    expect(successor.createdMs, greaterThan(original.createdMs));
    expect(superseded.updatedMs, successor.createdMs);

    final beforeEdit = DateTime.fromMillisecondsSinceEpoch(
      successor.createdMs - 1,
    );
    final afterEdit = DateTime.fromMillisecondsSinceEpoch(
      successor.createdMs + 1,
    );
    final broadStart = oldStart.subtract(const Duration(days: 1));
    final broadEnd = newEnd.add(const Duration(days: 2));

    List<BudgetSpecialTrackingResult> at(DateTime cutoff) => specialResults(
          repository,
          bookId,
          day,
          windowStartInclusive: broadStart,
          windowEndExclusive: broadEnd,
          asOf: day,
          knowledgeCutoff: cutoff,
        );

    var historical = at(beforeEdit);
    expect(historical, hasLength(1));
    expect(historical.single.plan.id, oldPlanId);
    expect(historical.single.plan.status, BudgetPlanStatusV2.active);
    expect(historical.single.plan.name, '旧餐饮专项');
    expect(historical.single.plan.anchorStart, oldStart);
    expect(historical.single.plan.endInclusive, oldEnd);
    expect(historical.single.plan.expenseScope.categoryKeys, {dining.key});
    expect(historical.single.totalCents, 50000);

    var current = at(afterEdit);
    expect(current, hasLength(1));
    expect(current.single.plan.id, newPlanId);
    expect(current.single.plan.status, BudgetPlanStatusV2.active);
    expect(current.single.plan.name, '新购物专项');
    expect(current.single.plan.anchorStart, newStart);
    expect(current.single.plan.endInclusive, newEnd);
    expect(current.single.plan.expenseScope.categoryKeys, {shopping.key});
    expect(current.single.totalCents, 90000);

    expect(
      specialResults(
        repository,
        bookId,
        oldStart,
        windowStartInclusive: oldStart,
        windowEndExclusive: oldEnd.add(const Duration(days: 1)),
        asOf: oldStart,
        knowledgeCutoff: afterEdit,
      ),
      isEmpty,
      reason: '编辑后的视图不能继续占用旧日期范围',
    );
    expect(
      specialResults(
        repository,
        bookId,
        newStart,
        windowStartInclusive: newStart,
        windowEndExclusive: newEnd.add(const Duration(days: 1)),
        asOf: newStart,
        knowledgeCutoff: beforeEdit,
      ),
      isEmpty,
      reason: '编辑前的 knowledge cutoff 不能提前看到 successor',
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await repository.archiveBudgetPlanV2(newPlanId);
    final archivedSuccessor = repository.budgetPlansV2.singleWhere(
      (plan) => plan.id == newPlanId,
    );
    final beforeArchive = DateTime.fromMillisecondsSinceEpoch(
      archivedSuccessor.updatedMs - 1,
    );
    final afterArchive = DateTime.fromMillisecondsSinceEpoch(
      archivedSuccessor.updatedMs + 1,
    );
    final preArchive = at(beforeArchive);
    expect(preArchive, hasLength(1));
    expect(preArchive.single.plan.id, newPlanId);
    expect(preArchive.single.plan.status, BudgetPlanStatusV2.active);
    expect(at(afterArchive), isEmpty);
    expect(
      specialResults(
        repository,
        bookId,
        day,
        includeArchived: true,
        windowStartInclusive: broadStart,
        windowEndExclusive: broadEnd,
        asOf: day,
        knowledgeCutoff: afterArchive,
      ).singleWhere((result) => result.plan.id == newPlanId).lifecycleStatus,
      BudgetSpecialLifecycleStatus.archived,
    );

    await repository.closeForTest();
    openRepository = null;
    repository = await openFreshRepository();

    historical = specialResults(
      repository,
      bookId,
      day,
      windowStartInclusive: broadStart,
      windowEndExclusive: broadEnd,
      asOf: day,
      knowledgeCutoff: beforeEdit,
    );
    expect(historical, hasLength(1));
    expect(historical.single.plan.id, oldPlanId);
    expect(historical.single.plan.status, BudgetPlanStatusV2.active);
    expect(historical.single.totalCents, 50000);

    current = specialResults(
      repository,
      bookId,
      day,
      windowStartInclusive: broadStart,
      windowEndExclusive: broadEnd,
      asOf: day,
      knowledgeCutoff: beforeArchive,
    );
    expect(current, hasLength(1));
    expect(current.single.plan.id, newPlanId);
    expect(current.single.plan.status, BudgetPlanStatusV2.active);
    expect(current.single.totalCents, 90000);
    expect(
      specialResults(
        repository,
        bookId,
        day,
        windowStartInclusive: broadStart,
        windowEndExclusive: broadEnd,
        asOf: day,
        knowledgeCutoff: afterArchive,
      ),
      isEmpty,
    );
  });

  test('B3 分类合并迁移专项 scope，仍被引用的分类和标签禁止删除并跨重启保持', () async {
    var repository = await openFreshRepository();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final bookId = repository.currentBookId;
    final dining = repository.categories.firstWhere(
      (category) => category.key == 'dining',
    );
    final shopping = repository.categories.firstWhere(
      (category) => category.key == 'shopping',
    );
    final tagId = await repository.addTag(
      name: '专项标签',
      colorValue: 0xFF8C7A5B,
    );
    final planId = await repository.saveBudgetSpecialTrackingV2(
      bookId: bookId,
      name: '分类迁移专项',
      startInclusive: day.subtract(const Duration(days: 1)),
      endInclusive: day.add(const Duration(days: 1)),
      totalCents: 30000,
      expenseScope: BudgetExpenseScopeV2(
        categoryKeys: [dining.key],
        tagIds: [tagId],
      ),
    );

    await expectLater(repository.deleteCategory(dining.id), throwsStateError);
    await expectLater(repository.deleteTag(tagId), throwsStateError);

    await repository.mergeCategory(dining.id, shopping.id);
    var plan = repository.budgetPlansV2.singleWhere(
      (item) => item.id == planId,
    );
    expect(plan.expenseScope.categoryKeys, {shopping.key});
    expect(plan.expenseScope.categoryKeys, isNot(contains(dining.key)));
    expect(plan.expenseScope.tagIds, {tagId});
    await expectLater(
      repository.deleteCategory(shopping.id),
      throwsStateError,
    );
    await expectLater(repository.deleteTag(tagId), throwsStateError);

    await repository.closeForTest();
    openRepository = null;
    repository = await openFreshRepository();

    plan = repository.budgetPlansV2.singleWhere((item) => item.id == planId);
    expect(plan.expenseScope.categoryKeys, {shopping.key});
    expect(plan.expenseScope.tagIds, {tagId});
    await expectLater(
      repository.deleteCategory(shopping.id),
      throwsStateError,
    );
    await expectLater(repository.deleteTag(tagId), throwsStateError);
  });
}
