import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_plan_v2.dart';
import 'package:qingji/core/budget/budget_special_tracking.dart';

BudgetPlanV2 _special({
  int id = 10,
  String name = '旅行追踪',
  BudgetExpenseScopeV2? scope,
  BudgetPlanStatusV2 status = BudgetPlanStatusV2.active,
}) =>
    BudgetPlanV2(
      id: id,
      uuid: 'special-$id',
      bookId: 1,
      name: name,
      role: 'special',
      cadence: BudgetPlanCadenceV2.oneOff,
      anchorStart: DateTime(2026, 10, 1),
      endInclusive: DateTime(2026, 10, 7),
      expenseScope:
          scope ?? BudgetExpenseScopeV2(categoryKeys: const ['travel']),
      status: status,
    );

BudgetPlanRevisionV2 _specialRevision(int planId, int amountCents) =>
    BudgetPlanRevisionV2(
      id: planId,
      uuid: 'revision-$planId',
      planId: planId,
      effectiveCycleStart: DateTime(2026, 10, 1),
      amountCents: amountCents,
      categoryBudgetsCents: const {'travel': 20000},
    );

BudgetSpecialExpenseFamilyInput _family({
  required String id,
  int netAmountCents = 7000,
  String currencyCode = 'CNY',
  String categoryKey = 'travel',
  Iterable<int> tagIds = const [],
  DateTime? date,
  DateTime? createdAt,
}) =>
    BudgetSpecialExpenseFamilyInput(
      id: id,
      bookId: 1,
      currencyCode: currencyCode,
      attributionDate: date ?? DateTime(2026, 10, 2),
      createdAt: createdAt ?? DateTime(2026, 10, 2, 12),
      netAmountCents: netAmountCents,
      categoryKey: categoryKey,
      tagIds: tagIds,
    );

void main() {
  test('expense scope JSON is canonical and category/tag matching uses OR', () {
    final scope = BudgetExpenseScopeV2(
      categoryKeys: const ['travel', ' dining ', 'travel'],
      tagIds: const [9, 2, 9],
    );

    expect(
      scope.toJsonString(),
      '{"category_keys":["dining","travel"],"tag_ids":[2,9],"match":"any"}',
    );
    expect(BudgetExpenseScopeV2.fromJsonString(scope.toJsonString()), scope);
    expect(scope.matches(categoryKey: 'travel'), isTrue);
    expect(
        scope.matches(categoryKey: 'other', familyTagIds: const [9]), isTrue);
    expect(
        scope.matches(categoryKey: 'other', familyTagIds: const [7]), isFalse);
    expect(BudgetExpenseScopeV2.fromJsonString('{}').isEmpty, isTrue);
    expect(
      () => BudgetExpenseScopeV2.fromJsonString('{"match":"all"}'),
      throwsFormatException,
    );
  });

  test('one_off cadence round-trips and validates special date/scope', () {
    expect(
      BudgetPlanCadenceV2X.fromStorage('one_off'),
      BudgetPlanCadenceV2.oneOff,
    );
    expect(BudgetPlanCadenceV2.oneOff.storageKey, 'one_off');

    final plan = _special();
    final cycle = plan.cycleFor(DateTime(2026, 10, 4));
    expect(cycle.start, DateTime(2026, 10, 1));
    expect(cycle.endExclusive, DateTime(2026, 10, 8));
    expect(cycle.dayCount, 7);
    expect(plan.covers(DateTime(2026, 10, 1)), isTrue);
    expect(plan.covers(DateTime(2026, 10, 7, 23)), isTrue);
    expect(plan.covers(DateTime(2026, 10, 8)), isFalse);

    expect(
      () => BudgetPlanV2(
        id: 99,
        uuid: 'invalid-special',
        bookId: 1,
        role: 'special',
        cadence: BudgetPlanCadenceV2.oneOff,
        anchorStart: DateTime(2026, 10, 7),
        endInclusive: DateTime(2026, 10, 1),
        expenseScope: BudgetExpenseScopeV2(tagIds: const [1]),
      ),
      throwsArgumentError,
    );
    expect(
      () => BudgetPlanV2(
        id: 100,
        uuid: 'missing-scope',
        bookId: 1,
        role: 'special',
        cadence: BudgetPlanCadenceV2.oneOff,
        anchorStart: DateTime(2026, 10, 1),
        endInclusive: DateTime(2026, 10, 7),
      ),
      throwsArgumentError,
    );
  });

  test('overlapping special trackers independently observe the same family',
      () {
    final categoryPlan = _special(id: 10);
    final tagPlan = _special(
      id: 20,
      name: '年度计划追踪',
      scope: BudgetExpenseScopeV2(tagIds: const [7]),
    );
    final results = BudgetSpecialTrackingResolver.resolveWindow(
      windowStartInclusive: DateTime(2026, 10, 1),
      windowEndExclusive: DateTime(2026, 10, 2),
      bookId: 1,
      asOf: DateTime(2026, 10, 3),
      knowledgeCutoff: DateTime(2026, 10, 31),
      plans: [categoryPlan, tagPlan],
      revisions: [
        _specialRevision(10, 50000),
        _specialRevision(20, 60000),
      ],
      expenseFamilies: [
        // The supplied amount is already 10000 gross - 3000 refund.
        _family(id: 'shared-refunded-family', tagIds: const [7]),
        // Outside the one-day browse window but inside the full special range.
        _family(
          id: 'tag-only-later',
          netAmountCents: 3000,
          categoryKey: 'other',
          tagIds: const [7],
          date: DateTime(2026, 10, 5),
        ),
        _family(
          id: 'foreign',
          currencyCode: 'USD',
          tagIds: const [7],
        ),
      ],
    );

    expect(results, hasLength(2));
    final category = results.singleWhere((item) => item.plan.id == 10);
    final tag = results.singleWhere((item) => item.plan.id == 20);
    expect(category.spentCents, 7000);
    expect(tag.spentCents, 10000);
    expect(category.matchedFamilyCount, 1);
    expect(tag.matchedFamilyCount, 2);
    expect(category.excludedForeignFamilyCount, 1);
    expect(tag.excludedForeignFamilyCount, 1);
    expect(category.remainingCents, 43000);
    expect(tag.remainingCents, 50000);
  });

  test('special plans never participate in the primary day resolver', () {
    final primary = BudgetPlanV2(
      id: 1,
      uuid: 'primary',
      bookId: 1,
      cadence: BudgetPlanCadenceV2.monthly,
      anchorStart: DateTime(2026, 1, 1),
      monthStartDay: 1,
    );
    final primaryRevision = BudgetPlanRevisionV2(
      id: 1,
      uuid: 'primary-revision',
      planId: 1,
      effectiveCycleStart: DateTime(2026, 1, 1),
      amountCents: 310000,
    );
    final withSpecial = BudgetPlanV2Resolver.resolveDay(
      day: DateTime(2026, 10, 2),
      bookId: 1,
      knowledgeCutoff: DateTime(2026, 10, 31),
      plans: [primary, _special()],
      revisions: [primaryRevision, _specialRevision(10, 50000)],
      overrides: const [],
    );
    final primaryOnly = BudgetPlanV2Resolver.resolveDay(
      day: DateTime(2026, 10, 2),
      bookId: 1,
      knowledgeCutoff: DateTime(2026, 10, 31),
      plans: [primary],
      revisions: [primaryRevision],
      overrides: const [],
    );

    expect(withSpecial.status, BudgetPlanDayStatusV2.available);
    expect(withSpecial.plan!.id, 1);
    expect(withSpecial.plannedCents, primaryOnly.plannedCents);
    expect(withSpecial.cycleTotalCents, primaryOnly.cycleTotalCents);
  });

  test('knowledge cutoff, archive visibility, and missing revision are honest',
      () {
    final active = _special();
    final archived = _special(id: 20, status: BudgetPlanStatusV2.archived);
    final common = (
      windowStartInclusive: DateTime(2026, 10, 1),
      windowEndExclusive: DateTime(2026, 11, 1),
      bookId: 1,
      asOf: DateTime(2026, 10, 3),
      knowledgeCutoff: DateTime(2026, 10, 3),
    );
    final visible = BudgetSpecialTrackingResolver.resolveWindow(
      windowStartInclusive: common.windowStartInclusive,
      windowEndExclusive: common.windowEndExclusive,
      bookId: common.bookId,
      asOf: common.asOf,
      knowledgeCutoff: common.knowledgeCutoff,
      plans: [active, archived],
      revisions: [_specialRevision(10, 50000), _specialRevision(20, 50000)],
      expenseFamilies: [
        _family(
          id: 'known-later',
          createdAt: DateTime(2026, 10, 4),
        ),
      ],
    );
    expect(visible, hasLength(1));
    expect(visible.single.spentCents, 0);

    final includingArchived = BudgetSpecialTrackingResolver.resolveWindow(
      windowStartInclusive: common.windowStartInclusive,
      windowEndExclusive: common.windowEndExclusive,
      bookId: common.bookId,
      asOf: common.asOf,
      knowledgeCutoff: common.knowledgeCutoff,
      plans: [active, archived],
      revisions: [_specialRevision(20, 50000)],
      expenseFamilies: const [],
      includeArchived: true,
    );
    expect(includingArchived, hasLength(2));
    expect(
      includingArchived.singleWhere((item) => item.plan.id == 10).status,
      BudgetSpecialResultStatus.conflict,
    );
    expect(
      includingArchived
          .singleWhere((item) => item.plan.id == 20)
          .lifecycleStatus,
      BudgetSpecialLifecycleStatus.archived,
    );
  });
}
