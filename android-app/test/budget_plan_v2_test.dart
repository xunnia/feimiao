import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_plan_v2.dart';

BudgetPlan _monthly({int anchor = 1}) => BudgetPlan(
      id: 1,
      uuid: 'plan-1',
      bookId: 1,
      timezone: 'Asia/Shanghai',
      name: '日常预算',
      cadence: BudgetPlanCadence.monthly,
      anchorStart: DateTime(2026, 1, anchor),
      monthStartDay: anchor,
    );

BudgetPlanRevision _revision(DateTime start, int cents, {int id = 1}) =>
    BudgetPlanRevision(
      id: id,
      planId: 1,
      effectiveCycleStart: start,
      amountCents: cents,
    );

BudgetPlanDayResult _day(DateTime day,
        {BudgetPlan? plan,
        List<BudgetPlanRevision>? revisions,
        List<BudgetCycleOverride> overrides = const []}) =>
    BudgetPlanResolver.resolveDay(
      day: day,
      bookId: 1,
      plans: [plan ?? _monthly()],
      revisions: revisions ?? [_revision(DateTime(2026, 1, 1), 300000)],
      overrides: overrides,
    );

void main() {
  test('300000 cents are conserved across all 31 civil days', () {
    final sum = [
      for (var day = 1; day <= 31; day++) _day(DateTime(2026, 7, day))
    ].fold<int>(0, (sum, result) => sum + result.plannedCents!);
    expect(sum, 300000);
  });

  test('anchored month remains safe over leap day', () {
    final plan = _monthly(anchor: 15);
    final revisions = [_revision(DateTime(2026, 1, 15), 290000)];
    final cycle =
        _day(DateTime(2028, 2, 29), plan: plan, revisions: revisions).cycle!;
    expect(cycle.startInclusive, DateTime(2028, 2, 15));
    expect(cycle.endExclusive, DateTime(2028, 3, 15));
    expect(cycle.dayCount, 29);
  });

  test('weekly cycle can cross a calendar month', () {
    final plan = BudgetPlan(
      id: 1,
      uuid: 'weekly',
      bookId: 1,
      timezone: 'Asia/Shanghai',
      name: '每周预算',
      cadence: BudgetPlanCadence.weekly,
      anchorStart: DateTime(2026, 6, 29),
    );
    final result = _day(DateTime(2026, 7, 1),
        plan: plan, revisions: [_revision(DateTime(2026, 6, 29), 70000)]);
    expect(result.cycle!.startInclusive, DateTime(2026, 6, 29));
    expect(result.cycle!.endExclusive, DateTime(2026, 7, 6));
  });

  test('revision changes only at a full cycle boundary', () {
    final revisions = [
      BudgetPlanRevision(
        id: 1,
        planId: 1,
        effectiveCycleStart: DateTime(2026, 1, 1),
        effectiveToCycleStart: DateTime(2026, 8, 1),
        amountCents: 310000,
      ),
      _revision(DateTime(2026, 8, 1), 620000, id: 2),
    ];
    expect(_day(DateTime(2026, 7, 31), revisions: revisions).cycleTotalCents,
        310000);
    expect(_day(DateTime(2026, 8, 1), revisions: revisions).cycleTotalCents,
        620000);
  });

  test('cycle override is an absolute total and preserves intent as audit', () {
    final override = BudgetCycleOverride(
      id: 1,
      planId: 1,
      cycleStart: DateTime(2026, 7, 1),
      cycleEndExclusive: DateTime(2026, 8, 1),
      targetAmountCents: 330000,
      inputIntent: BudgetOverrideIntent.adjustRemaining,
      inputDeltaCents: 30000,
    );
    final results = [
      for (var day = 1; day <= 31; day++)
        _day(DateTime(2026, 7, day), overrides: [override])
    ];
    expect(results.first.cycleTotalCents, 330000);
    expect(
        results.fold<int>(0, (sum, item) => sum + item.plannedCents!), 330000);
  });

  test('cycle override created after knowledge cutoff cannot rewrite history',
      () {
    final result = BudgetPlanResolver.resolveDay(
      day: DateTime(2026, 7, 1),
      bookId: 1,
      plans: [_monthly()],
      revisions: [_revision(DateTime(2026, 1, 1), 300000)],
      overrides: [
        BudgetCycleOverride(
          id: 1,
          planId: 1,
          cycleStart: DateTime(2026, 7, 1),
          cycleEndExclusive: DateTime(2026, 8, 1),
          targetAmountCents: 330000,
          createdMs: 200,
        ),
      ],
      knowledgeCutoff: DateTime.fromMillisecondsSinceEpoch(100),
    );
    expect(result.cycleTotalCents, 300000);
  });

  test('V2 conflict fails closed instead of falling back to legacy', () {
    const legacy = BudgetPlanDayResult.conflict('legacy-marker');
    const conflict = BudgetPlanDayResult.conflict('overlapping_primary_plans');
    expect(BudgetPlanResolver.preferV2(v2: conflict, legacy: legacy), conflict);
    expect(
      BudgetPlanResolver.preferV2(
        v2: const BudgetPlanDayResult.unavailable(),
        legacy: legacy,
      ),
      legacy,
    );
  });
}
