import 'package:decimal/decimal.dart';

import '../statistics/consumption_projection.dart';
import '../statistics/metric_contract.dart';
import 'budget_period.dart';
import 'budget_plan_v2.dart';
import 'fixed_commitment.dart';

enum BudgetViewKind { cycle, calendarMonth, calendarWeek, custom }

class BudgetWindowQuery {
  final BudgetViewKind viewKind;
  final int bookId;
  final DateTime referenceDate;
  final DateTime? customEndExclusive;
  final DateTime asOf;
  final DateTime knowledgeCutoff;
  final String currencyCode;
  final String calendarTimezone;
  final int weekStart;

  BudgetWindowQuery({
    required this.viewKind,
    required this.bookId,
    required DateTime referenceDate,
    this.customEndExclusive,
    required this.asOf,
    required this.knowledgeCutoff,
    this.currencyCode = 'CNY',
    this.calendarTimezone = 'device-local',
    this.weekStart = DateTime.monday,
  }) : referenceDate = _day(referenceDate) {
    if (bookId <= 0) {
      throw ArgumentError.value(bookId, 'bookId', 'must be positive');
    }
    if (currencyCode.trim().toUpperCase() != 'CNY') {
      throw ArgumentError.value(
        currencyCode,
        'currencyCode',
        'legacy budget plans only support CNY',
      );
    }
    if (calendarTimezone.trim().isEmpty) {
      throw ArgumentError.value(
        calendarTimezone,
        'calendarTimezone',
        'must not be empty',
      );
    }
    if (weekStart < DateTime.monday || weekStart > DateTime.sunday) {
      throw ArgumentError.value(weekStart, 'weekStart', 'must be from 1 to 7');
    }
    if (viewKind == BudgetViewKind.custom) {
      final end = customEndExclusive;
      if (end == null || !this.referenceDate.isBefore(_day(end))) {
        throw ArgumentError(
          'A custom budget window requires an exclusive end after its start.',
        );
      }
    }
  }

  BudgetWindowQuery copyWith({
    BudgetViewKind? viewKind,
    int? bookId,
    DateTime? referenceDate,
    DateTime? customEndExclusive,
    DateTime? asOf,
    DateTime? knowledgeCutoff,
    String? currencyCode,
    String? calendarTimezone,
    int? weekStart,
  }) =>
      BudgetWindowQuery(
        viewKind: viewKind ?? this.viewKind,
        bookId: bookId ?? this.bookId,
        referenceDate: referenceDate ?? this.referenceDate,
        customEndExclusive: customEndExclusive ?? this.customEndExclusive,
        asOf: asOf ?? this.asOf,
        knowledgeCutoff: knowledgeCutoff ?? this.knowledgeCutoff,
        currencyCode: currencyCode ?? this.currencyCode,
        calendarTimezone: calendarTimezone ?? this.calendarTimezone,
        weekStart: weekStart ?? this.weekStart,
      );
}

class BudgetPlanSlice {
  final int planId;
  final DateTime startInclusive;
  final DateTime endExclusive;
  final int plannedCents;
  final bool legacyOverride;
  final bool ambiguousScope;

  const BudgetPlanSlice({
    required this.planId,
    required this.startInclusive,
    required this.endExclusive,
    required this.plannedCents,
    required this.legacyOverride,
    required this.ambiguousScope,
  });
}

class BudgetCycleSlice {
  final int planId;
  final DateTime cycleStart;
  final DateTime cycleEndExclusive;
  final DateTime sliceStartInclusive;
  final DateTime sliceEndExclusive;
  final int plannedCents;

  const BudgetCycleSlice({
    required this.planId,
    required this.cycleStart,
    required this.cycleEndExclusive,
    required this.sliceStartInclusive,
    required this.sliceEndExclusive,
    required this.plannedCents,
  });

  String get stableId => '$planId:${cycleStart.millisecondsSinceEpoch}:'
      '${cycleEndExclusive.millisecondsSinceEpoch}:'
      '${sliceStartInclusive.millisecondsSinceEpoch}:'
      '${sliceEndExclusive.millisecondsSinceEpoch}';
}

class BudgetCategoryResult {
  final String categoryKey;
  final int plannedCents;
  final int spentCents;

  const BudgetCategoryResult({
    required this.categoryKey,
    required this.plannedCents,
    required this.spentCents,
  });

  int get remainingCents => plannedCents - spentCents;
  double? get progress => plannedCents > 0 ? spentCents / plannedCents : null;

  Decimal get plannedAmount => budgetDecimalFromCents(plannedCents)!;
  Decimal get spentAmount => budgetDecimalFromCents(spentCents)!;
  Decimal get remainingAmount => budgetDecimalFromCents(remainingCents)!;
}

class BudgetCurrentCycleDailyStatus {
  final int planId;
  final DateTime cycleStart;
  final DateTime cycleEndExclusive;
  final int cycleTotalCents;
  final int spentBeforeTodayCents;
  final int spentTodayCents;
  final int spentThroughTodayCents;
  final int cycleRemainingCents;
  final int remainingDaysIncludingToday;
  final int todayRemainingAllowanceCents;
  final int plainBudgetDailyReferenceCents;
  final double timeProgress;

  const BudgetCurrentCycleDailyStatus({
    required this.planId,
    required this.cycleStart,
    required this.cycleEndExclusive,
    required this.cycleTotalCents,
    required this.spentBeforeTodayCents,
    required this.spentTodayCents,
    required this.spentThroughTodayCents,
    required this.cycleRemainingCents,
    required this.remainingDaysIncludingToday,
    required this.todayRemainingAllowanceCents,
    required this.plainBudgetDailyReferenceCents,
    required this.timeProgress,
  });

  Decimal get cycleTotalAmount => budgetDecimalFromCents(cycleTotalCents)!;
  Decimal get spentTodayAmount => budgetDecimalFromCents(spentTodayCents)!;
  Decimal get todayRemainingAllowanceAmount =>
      budgetDecimalFromCents(todayRemainingAllowanceCents)!;
  Decimal get plainBudgetDailyReferenceAmount =>
      budgetDecimalFromCents(plainBudgetDailyReferenceCents)!;
}

class BudgetWindowResult {
  final BudgetWindowQuery query;
  final MetricWindow viewWindow;
  final MetricStatus planStatus;
  final List<MetricReason> planReasons;
  final MetricStatus spendStatus;
  final List<MetricReason> spendReasons;
  final MetricStatus dailyStatus;
  final List<MetricReason> dailyReasons;
  final MetricStatus fixedCommitmentStatus;
  final List<MetricReason> fixedCommitmentReasons;
  final int? plannedCents;
  final int? spentCents;
  final int? remainingCents;
  final double? progress;
  final double timeProgress;
  final int excludedForeignTransactionCount;
  final List<BudgetPlanSlice> planSlices;
  final List<BudgetCycleSlice> cycleSlices;
  final List<BudgetCategoryResult> categoryResults;
  final BudgetCurrentCycleDailyStatus? currentCycleDailyStatus;
  final MetricWindow? previousCycleWindow;
  final MetricWindow? currentCycleWindow;
  final MetricWindow? nextCycleWindow;
  final int? fixedActualSpentCents;
  final int? fixedReserveCents;
  final int? discretionaryRemainingCents;

  BudgetWindowResult({
    required this.query,
    required this.viewWindow,
    required this.planStatus,
    required Iterable<MetricReason> planReasons,
    required this.spendStatus,
    required Iterable<MetricReason> spendReasons,
    required this.dailyStatus,
    required Iterable<MetricReason> dailyReasons,
    required this.fixedCommitmentStatus,
    required Iterable<MetricReason> fixedCommitmentReasons,
    required this.plannedCents,
    required this.spentCents,
    required this.remainingCents,
    required this.progress,
    required this.timeProgress,
    required this.excludedForeignTransactionCount,
    required Iterable<BudgetPlanSlice> planSlices,
    required Iterable<BudgetCycleSlice> cycleSlices,
    required Iterable<BudgetCategoryResult> categoryResults,
    required this.currentCycleDailyStatus,
    required this.previousCycleWindow,
    required this.currentCycleWindow,
    required this.nextCycleWindow,
    this.fixedActualSpentCents,
    this.fixedReserveCents,
    this.discretionaryRemainingCents,
  })  : planReasons = List.unmodifiable(planReasons),
        spendReasons = List.unmodifiable(spendReasons),
        dailyReasons = List.unmodifiable(dailyReasons),
        fixedCommitmentReasons = List.unmodifiable(fixedCommitmentReasons),
        planSlices = List.unmodifiable(planSlices),
        cycleSlices = List.unmodifiable(cycleSlices),
        categoryResults = List.unmodifiable(categoryResults);

  DateTime get displayEndInclusive =>
      viewWindow.endExclusive.subtract(const Duration(days: 1));
  Decimal? get plannedAmount => budgetDecimalFromCents(plannedCents);
  Decimal? get spentAmount => budgetDecimalFromCents(spentCents);
  Decimal? get remainingAmount => budgetDecimalFromCents(remainingCents);
  Decimal? get plainBudgetDailyReferenceAmount => budgetDecimalFromCents(
        currentCycleDailyStatus?.plainBudgetDailyReferenceCents,
      );
  bool get hasPlan => plannedCents != null;
  bool? get isOverBudget => remainingCents == null ? null : remainingCents! < 0;
  Decimal? get fixedReserveAmount => budgetDecimalFromCents(fixedReserveCents);
  Decimal? get discretionaryRemainingAmount =>
      budgetDecimalFromCents(discretionaryRemainingCents);
}

class LegacyBudgetAdapter {
  LegacyBudgetAdapter._();

  static BudgetPeriod? effectiveOn(
    Iterable<BudgetPeriod> periods,
    DateTime day, {
    required int bookId,
    bool includeOverrides = true,
    DateTime? knowledgeCutoff,
  }) {
    BudgetPeriod? best;
    var bestRank = -1;
    for (final period in periods) {
      if (knowledgeCutoff != null &&
          period.createdMs > 0 &&
          period.createdMs > knowledgeCutoff.millisecondsSinceEpoch) {
        continue;
      }
      if (!period.covers(day)) continue;
      if (period.bookId != null && period.bookId != bookId) continue;
      if (!includeOverrides && !period.recurringMonthly) continue;
      final rank =
          (period.recurringMonthly ? 0 : 10) + (period.bookId == null ? 0 : 1);
      if (best == null ||
          rank > bestRank ||
          (rank == bestRank &&
              (period.start.isAfter(best.start) ||
                  (period.start == best.start &&
                      period.createdMs > best.createdMs)))) {
        best = period;
        bestRank = rank;
      }
    }
    return best;
  }

  static BudgetPeriod? recurringPrimaryOn(
    Iterable<BudgetPeriod> periods,
    DateTime day, {
    required int bookId,
    DateTime? knowledgeCutoff,
  }) =>
      effectiveOn(
        periods,
        day,
        bookId: bookId,
        includeOverrides: false,
        knowledgeCutoff: knowledgeCutoff,
      );
}

class BudgetWindowResolver {
  BudgetWindowResolver._();

  static BudgetWindowResult resolve({
    required BudgetWindowQuery query,
    required Iterable<BudgetPeriod> periods,
    Iterable<ConsumptionExpenseFamily> expenseFamilies = const [],
    Iterable<BudgetPlanV2> plansV2 = const [],
    Iterable<BudgetPlanRevisionV2> revisionsV2 = const [],
    Iterable<BudgetCycleOverrideV2> overridesV2 = const [],
    Iterable<FixedCommitmentOccurrence> fixedOccurrencesV2 = const [],
  }) {
    final periodList = List<BudgetPeriod>.unmodifiable(periods);
    final familyList =
        List<ConsumptionExpenseFamily>.unmodifiable(expenseFamilies);
    final planListV2 = List<BudgetPlanV2>.unmodifiable(plansV2);
    if (planListV2.any((plan) => plan.bookId == query.bookId)) {
      return _resolveHybridV2(
        query: query,
        periods: periodList,
        families: familyList,
        plans: planListV2,
        revisions: List<BudgetPlanRevisionV2>.unmodifiable(revisionsV2),
        overrides: List<BudgetCycleOverrideV2>.unmodifiable(overridesV2),
        fixedOccurrences:
            List<FixedCommitmentOccurrence>.unmodifiable(fixedOccurrencesV2),
      );
    }
    final referencePrimary = LegacyBudgetAdapter.recurringPrimaryOn(
      periodList,
      query.referenceDate,
      bookId: query.bookId,
      knowledgeCutoff: query.knowledgeCutoff,
    );
    final referenceWinner = LegacyBudgetAdapter.effectiveOn(
      periodList,
      query.referenceDate,
      bookId: query.bookId,
      knowledgeCutoff: query.knowledgeCutoff,
    );
    final window = _viewWindow(
      query,
      referencePrimary: referencePrimary,
      referenceWinner: referenceWinner,
    );

    final planReasons = <MetricReason>[];
    if (query.viewKind == BudgetViewKind.cycle &&
        referencePrimary == null &&
        referenceWinner != null &&
        !referenceWinner.recurringMonthly) {
      planReasons.add(MetricReason(
        code: MetricReasonCode.legacyOverrideWithoutPrimary,
        message: 'This legacy override has no recurring primary plan.',
        details: {'planId': referenceWinner.id},
      ));
    }
    final planSlices = <BudgetPlanSlice>[];
    final cycleSlices = <BudgetCycleSlice>[];
    final categoryPlanned = <String, int>{};
    var plannedCents = 0;
    var hasPlanDay = false;
    var planConflict = false;

    BudgetPeriod? openPlan;
    DateTime? openStart;
    var openPlanned = 0;
    _CycleBounds? openCycle;
    DateTime? openCycleStart;
    var openCyclePlanned = 0;

    void closePlan(DateTime endExclusive) {
      final plan = openPlan;
      final start = openStart;
      if (plan == null || start == null) return;
      planSlices.add(BudgetPlanSlice(
        planId: plan.id,
        startInclusive: start,
        endExclusive: endExclusive,
        plannedCents: openPlanned,
        legacyOverride: !plan.recurringMonthly,
        ambiguousScope: plan.bookId == null,
      ));
      openPlan = null;
      openStart = null;
      openPlanned = 0;
    }

    void closeCycle(DateTime endExclusive) {
      final plan = openPlan;
      final cycle = openCycle;
      final start = openCycleStart;
      if (plan == null || cycle == null || start == null) return;
      cycleSlices.add(BudgetCycleSlice(
        planId: plan.id,
        cycleStart: cycle.start,
        cycleEndExclusive: cycle.endExclusive,
        sliceStartInclusive: start,
        sliceEndExclusive: endExclusive,
        plannedCents: openCyclePlanned,
      ));
      openCycle = null;
      openCycleStart = null;
      openCyclePlanned = 0;
    }

    for (var day = window.startInclusive;
        day.isBefore(window.endExclusive);
        day = _addDays(day, 1)) {
      final plan = LegacyBudgetAdapter.effectiveOn(
        periodList,
        day,
        bookId: query.bookId,
        knowledgeCutoff: query.knowledgeCutoff,
      );
      if (plan == null) {
        closeCycle(day);
        closePlan(day);
        continue;
      }
      hasPlanDay = true;
      final cycle = _cycleFor(plan, day);
      final total = _validBudgetCents(plan.total);
      final categoryCents = <String, int>{};
      var hasInvalidCategory = false;
      for (final entry in plan.categoryBudgets.entries) {
        final value = _validBudgetCents(entry.value);
        if (value == null) {
          hasInvalidCategory = true;
          break;
        }
        categoryCents[entry.key] = value;
      }
      if (total == null || hasInvalidCategory) {
        planConflict = true;
        if (!planReasons.any((reason) =>
            reason.code == MetricReasonCode.invalidInput &&
            reason.details['planId'] == plan.id)) {
          planReasons.add(MetricReason(
            code: MetricReasonCode.invalidInput,
            message: 'Budget amounts must be non-negative integer cents.',
            details: {'planId': plan.id},
          ));
        }
        closeCycle(day);
        closePlan(day);
        continue;
      }
      final categoryTotal =
          categoryCents.values.fold<int>(0, (sum, value) => sum + value);
      if (categoryTotal > total) {
        planConflict = true;
        planReasons.add(MetricReason(
          code: MetricReasonCode.categoryBudgetExceedsPlan,
          message: 'Category budgets exceed their legacy plan total.',
          details: {'planId': plan.id},
        ));
        closeCycle(day);
        closePlan(day);
        continue;
      }
      if (plan.bookId == null &&
          !planReasons.any((reason) =>
              reason.code == MetricReasonCode.legacyScopeAmbiguous)) {
        planReasons.add(MetricReason(
          code: MetricReasonCode.legacyScopeAmbiguous,
          message: 'This legacy plan did not store an explicit book scope.',
          details: {'planId': plan.id},
        ));
      }
      if (!plan.recurringMonthly &&
          plan.end == null &&
          !planReasons.any((reason) =>
              reason.code == MetricReasonCode.legacyOpenEndedOverride)) {
        planReasons.add(MetricReason(
          code: MetricReasonCode.legacyOpenEndedOverride,
          message: 'An open-ended legacy override uses a monthly fallback.',
          details: {'planId': plan.id},
        ));
      }

      final daily = _stableDailyShare(
        total,
        start: cycle.start,
        endExclusive: cycle.endExclusive,
        day: day,
      );
      plannedCents += daily;
      for (final entry in categoryCents.entries) {
        categoryPlanned.update(
          entry.key,
          (value) =>
              value +
              _stableDailyShare(
                entry.value,
                start: cycle.start,
                endExclusive: cycle.endExclusive,
                day: day,
              ),
          ifAbsent: () => _stableDailyShare(
            entry.value,
            start: cycle.start,
            endExclusive: cycle.endExclusive,
            day: day,
          ),
        );
      }

      final samePlan = identical(openPlan, plan);
      final sameCycle = samePlan && openCycle == cycle;
      if (!sameCycle) {
        closeCycle(day);
      }
      if (!samePlan) {
        closePlan(day);
        openPlan = plan;
        openStart = day;
      }
      if (!sameCycle) {
        openCycle = cycle;
        openCycleStart = day;
      }
      openPlanned += daily;
      openCyclePlanned += daily;
    }
    closeCycle(window.endExclusive);
    closePlan(window.endExclusive);

    final projection = _project(
      query: query,
      window: window,
      families: familyList,
    );
    final projectionValue = projection.value;
    final spentCents = projectionValue?.budgetExpenseMinor;
    final spendStatus = projection.status;
    final spendReasons = projection.reasons;

    late final MetricStatus planStatus;
    int? finalPlannedCents;
    if (planConflict) {
      planStatus = MetricStatus.conflict;
      finalPlannedCents = null;
    } else if (!hasPlanDay) {
      planStatus = MetricStatus.unavailable;
      finalPlannedCents = null;
      planReasons.add(MetricReason(
        code: MetricReasonCode.noBudgetPlan,
        message: 'No legacy budget plan covers this window.',
      ));
    } else {
      planStatus =
          planReasons.isEmpty ? MetricStatus.available : MetricStatus.partial;
      finalPlannedCents = plannedCents;
    }

    final categorySpent = <String, int>{
      for (final category in projectionValue?.budgetExpenseByCategory ??
          const <ConsumptionCategoryTotal>[])
        category.categoryKey: category.amountMinor,
    };
    final categoryKeys = {...categoryPlanned.keys, ...categorySpent.keys};
    final categoryResults = [
      for (final key in categoryKeys)
        BudgetCategoryResult(
          categoryKey: key,
          plannedCents: categoryPlanned[key] ?? 0,
          spentCents: categorySpent[key] ?? 0,
        ),
    ]..sort((left, right) {
        final planned = right.plannedCents.compareTo(left.plannedCents);
        if (planned != 0) return planned;
        final spent = right.spentCents.compareTo(left.spentCents);
        if (spent != 0) return spent;
        return left.categoryKey.compareTo(right.categoryKey);
      });

    final remaining = finalPlannedCents != null && spentCents != null
        ? finalPlannedCents - spentCents
        : null;
    final progress =
        finalPlannedCents != null && finalPlannedCents > 0 && spentCents != null
            ? spentCents / finalPlannedCents
            : null;
    final dailyResolution = _currentCycleDailyStatus(
      query: query,
      periods: periodList,
      families: familyList,
    );
    final currentCycle = dailyResolution.value;
    final navigationBounds = referencePrimary == null
        ? null
        : _cycleFor(referencePrimary, query.referenceDate);
    final previousCycleWindow = navigationBounds == null
        ? null
        : _adjacentRecurringCycle(
            periods: periodList,
            query: query,
            current: navigationBounds,
            previous: true,
          );
    final nextCycleWindow = navigationBounds == null
        ? null
        : _adjacentRecurringCycle(
            periods: periodList,
            query: query,
            current: navigationBounds,
            previous: false,
          );
    final fixedReasons = [
      MetricReason(
        code: MetricReasonCode.fixedCommitmentsUnavailable,
        message: 'Legacy fixed expenses do not have due dates or occurrences.',
      ),
    ];

    return BudgetWindowResult(
      query: query,
      viewWindow: window,
      planStatus: planStatus,
      planReasons: planReasons,
      spendStatus: spendStatus,
      spendReasons: spendReasons,
      dailyStatus: dailyResolution.status,
      dailyReasons: dailyResolution.reasons,
      fixedCommitmentStatus: MetricStatus.unavailable,
      fixedCommitmentReasons: fixedReasons,
      plannedCents: finalPlannedCents,
      spentCents: spentCents,
      remainingCents: remaining,
      progress: progress,
      timeProgress: _timeProgress(window, query.asOf),
      excludedForeignTransactionCount:
          projectionValue?.excludedCurrencyEventCount ?? 0,
      planSlices: planSlices,
      cycleSlices: cycleSlices,
      categoryResults: categoryResults,
      currentCycleDailyStatus: currentCycle,
      previousCycleWindow: previousCycleWindow,
      currentCycleWindow: navigationBounds == null
          ? null
          : MetricWindow(
              startInclusive: navigationBounds.start,
              endExclusive: navigationBounds.endExclusive,
            ),
      nextCycleWindow: nextCycleWindow,
    );
  }

  static BudgetWindowResult _resolveHybridV2({
    required BudgetWindowQuery query,
    required List<BudgetPeriod> periods,
    required List<ConsumptionExpenseFamily> families,
    required List<BudgetPlanV2> plans,
    required List<BudgetPlanRevisionV2> revisions,
    required List<BudgetCycleOverrideV2> overrides,
    required List<FixedCommitmentOccurrence> fixedOccurrences,
  }) {
    final referenceV2 = BudgetPlanV2Resolver.resolveDay(
      day: query.referenceDate,
      bookId: query.bookId,
      knowledgeCutoff: query.knowledgeCutoff,
      plans: plans,
      revisions: revisions,
      overrides: overrides,
    );
    final legacyPrimary = LegacyBudgetAdapter.recurringPrimaryOn(
      periods,
      query.referenceDate,
      bookId: query.bookId,
      knowledgeCutoff: query.knowledgeCutoff,
    );
    final legacyWinner = LegacyBudgetAdapter.effectiveOn(
      periods,
      query.referenceDate,
      bookId: query.bookId,
      knowledgeCutoff: query.knowledgeCutoff,
    );
    final window = query.viewKind == BudgetViewKind.cycle &&
            referenceV2.status == BudgetPlanDayStatusV2.available
        ? MetricWindow(
            startInclusive: referenceV2.cycle!.start,
            endExclusive: referenceV2.cycle!.endExclusive,
          )
        : _viewWindow(
            query,
            referencePrimary: legacyPrimary,
            referenceWinner: legacyWinner,
          );
    var planned = 0;
    var hasPlan = false;
    var conflict = false;
    final planReasons = <MetricReason>[];
    final categories = <String, int>{};
    final planSlices = <BudgetPlanSlice>[];
    final cycleSlices = <BudgetCycleSlice>[];

    void addLegacyReason(MetricReason reason) {
      if (!planReasons.contains(reason)) planReasons.add(reason);
    }

    for (var day = window.startInclusive;
        day.isBefore(window.endExclusive);
        day = _addDays(day, 1)) {
      final v2 = BudgetPlanV2Resolver.resolveDay(
        day: day,
        bookId: query.bookId,
        knowledgeCutoff: query.knowledgeCutoff,
        plans: plans,
        revisions: revisions,
        overrides: overrides,
      );
      if (v2.status == BudgetPlanDayStatusV2.conflict) {
        conflict = true;
        planReasons.add(MetricReason(
          code: MetricReasonCode.invalidInput,
          message: v2.reason ?? 'Budget V2 plan conflict.',
          details: {'day': budgetCivilDayKey(day)},
        ));
        continue;
      }
      if (v2.status == BudgetPlanDayStatusV2.available) {
        hasPlan = true;
        final daily = v2.plannedCents!;
        planned += daily;
        for (final entry in v2.categoryPlannedCents.entries) {
          categories.update(entry.key, (value) => value + entry.value,
              ifAbsent: () => entry.value);
        }
        final cycle = v2.cycle!;
        planSlices.add(BudgetPlanSlice(
          planId: v2.plan!.id,
          startInclusive: day,
          endExclusive: _addDays(day, 1),
          plannedCents: daily,
          legacyOverride: false,
          ambiguousScope: false,
        ));
        cycleSlices.add(BudgetCycleSlice(
          planId: v2.plan!.id,
          cycleStart: cycle.start,
          cycleEndExclusive: cycle.endExclusive,
          sliceStartInclusive: day,
          sliceEndExclusive: _addDays(day, 1),
          plannedCents: daily,
        ));
        continue;
      }

      final cutOverToV2 = plans.any((plan) =>
          plan.bookId == query.bookId &&
          plan.createdMs <= query.knowledgeCutoff.millisecondsSinceEpoch &&
          !day.isBefore(plan.anchorStart));
      if (cutOverToV2) {
        // Once the user has confirmed a V2 primary plan, legacy rows remain
        // historical evidence only. Archiving V2 must not resurrect an old
        // open-ended legacy budget in future cycles.
        continue;
      }

      final legacy = LegacyBudgetAdapter.effectiveOn(
        periods,
        day,
        bookId: query.bookId,
        knowledgeCutoff: query.knowledgeCutoff,
      );
      if (legacy == null) continue;
      hasPlan = true;
      final total = _validBudgetCents(legacy.total);
      final legacyCategories = <String, int>{};
      var categoriesValid = true;
      for (final entry in legacy.categoryBudgets.entries) {
        final cents = _validBudgetCents(entry.value);
        if (cents == null) {
          categoriesValid = false;
          break;
        }
        legacyCategories[entry.key] = cents;
      }
      if (total == null ||
          !categoriesValid ||
          legacyCategories.values.fold<int>(0, (a, b) => a + b) > total) {
        conflict = true;
        addLegacyReason(MetricReason(
          code: MetricReasonCode.invalidInput,
          message: 'The legacy fallback contains invalid amounts.',
          details: {'planId': legacy.id},
        ));
        continue;
      }
      if (legacy.bookId == null) {
        addLegacyReason(MetricReason(
          code: MetricReasonCode.legacyScopeAmbiguous,
          message: 'This legacy plan did not store an explicit book scope.',
          details: {'planId': legacy.id},
        ));
      }
      final cycle = _cycleFor(legacy, day);
      final daily = _stableDailyShare(
        total,
        start: cycle.start,
        endExclusive: cycle.endExclusive,
        day: day,
      );
      planned += daily;
      for (final entry in legacyCategories.entries) {
        categories.update(
          entry.key,
          (value) =>
              value +
              _stableDailyShare(
                entry.value,
                start: cycle.start,
                endExclusive: cycle.endExclusive,
                day: day,
              ),
          ifAbsent: () => _stableDailyShare(
            entry.value,
            start: cycle.start,
            endExclusive: cycle.endExclusive,
            day: day,
          ),
        );
      }
      planSlices.add(BudgetPlanSlice(
        planId: legacy.id,
        startInclusive: day,
        endExclusive: _addDays(day, 1),
        plannedCents: daily,
        legacyOverride: !legacy.recurringMonthly,
        ambiguousScope: legacy.bookId == null,
      ));
      cycleSlices.add(BudgetCycleSlice(
        planId: legacy.id,
        cycleStart: cycle.start,
        cycleEndExclusive: cycle.endExclusive,
        sliceStartInclusive: day,
        sliceEndExclusive: _addDays(day, 1),
        plannedCents: daily,
      ));
    }

    final projection =
        _project(query: query, window: window, families: families);
    final spent = projection.value?.budgetExpenseMinor;
    late final MetricStatus planStatus;
    int? plannedResult;
    if (conflict) {
      planStatus = MetricStatus.conflict;
    } else if (!hasPlan) {
      planStatus = MetricStatus.unavailable;
      planReasons.add(MetricReason(
        code: MetricReasonCode.noBudgetPlan,
        message: 'No budget plan covers this window.',
      ));
    } else {
      plannedResult = planned;
      planStatus =
          planReasons.isEmpty ? MetricStatus.available : MetricStatus.partial;
    }
    final categorySpent = <String, int>{
      for (final item in projection.value?.budgetExpenseByCategory ??
          const <ConsumptionCategoryTotal>[])
        item.categoryKey: item.amountMinor,
    };
    final categoryKeys = {...categories.keys, ...categorySpent.keys};
    final categoryResults = [
      for (final key in categoryKeys)
        BudgetCategoryResult(
          categoryKey: key,
          plannedCents: categories[key] ?? 0,
          spentCents: categorySpent[key] ?? 0,
        ),
    ];
    final remaining =
        plannedResult != null && spent != null ? plannedResult - spent : null;
    final todayV2 = BudgetPlanV2Resolver.resolveDay(
      day: _day(query.asOf),
      bookId: query.bookId,
      knowledgeCutoff: query.knowledgeCutoff,
      plans: plans,
      revisions: revisions,
      overrides: overrides,
    );
    final daily = todayV2.status == BudgetPlanDayStatusV2.available
        ? _v2DailyStatus(
            query: query,
            dayResult: todayV2,
            families: families,
          )
        : _currentCycleDailyStatus(
            query: query,
            periods: periods,
            families: families,
          );

    var fixedStatus = MetricStatus.unavailable;
    final fixedReasons = <MetricReason>[];
    int? fixedActual;
    int? fixedReserve;
    int? discretionary;
    final viewingCurrentV2Cycle = query.viewKind == BudgetViewKind.cycle &&
        referenceV2.status == BudgetPlanDayStatusV2.available &&
        todayV2.status == BudgetPlanDayStatusV2.available &&
        referenceV2.plan!.id == todayV2.plan!.id &&
        referenceV2.cycle!.start == todayV2.cycle!.start;
    if (viewingCurrentV2Cycle) {
      final templates = todayV2.revision!.fixedTemplates;
      final cycle = todayV2.cycle!;
      final cycleOccurrences = fixedOccurrences
          .where((item) =>
              item.planId == todayV2.plan!.id &&
              _day(item.cycleStart) == cycle.start)
          .toList();
      if (templates.isEmpty) {
        fixedStatus = MetricStatus.available;
        fixedActual = 0;
        fixedReserve = 0;
        final cycleSpent = _project(
          query: query,
          window: MetricWindow(
            startInclusive: cycle.start,
            endExclusive: cycle.endExclusive,
          ),
          families: families,
        ).value?.budgetExpenseMinor;
        if (cycleSpent != null) {
          discretionary = todayV2.cycleTotalCents! - cycleSpent;
        }
      } else if (cycleOccurrences.length != templates.length) {
        fixedStatus = MetricStatus.partial;
        fixedReasons.add(MetricReason(
          code: MetricReasonCode.fixedCommitmentsUnavailable,
          message:
              'Some fixed commitment occurrences have not been materialized.',
        ));
      } else {
        final familyById = {for (final family in families) family.id: family};
        final evaluations = <FixedCommitmentEvaluation>[];
        for (final occurrence in cycleOccurrences) {
          final familyId = occurrence.matchedTransactionFamilyId;
          final family = familyId == null ? null : familyById[familyId];
          var exclusive = false;
          var net = 0;
          var occurred = false;
          var refundReview = occurrence.reviewReason ==
              FixedCommitmentReviewReason.refundAfterMatch;
          if (family != null) {
            exclusive = FixedCommitmentLinkValidator.validateLink(
              occurrence: occurrence,
              candidate: FixedCommitmentFamilyCandidate(
                familyId: family.id,
                bookId: query.bookId,
                currencyCode: family.currencyCode,
                attributionDate: family.attributionDate,
              ),
              existingOccurrences: cycleOccurrences,
            ).isValid;
            net = _familyNetAtCutoff(family, query.knowledgeCutoff);
            occurred = !family.attributionDate.isAfter(query.asOf);
            final resolvedMs = occurrence.resolvedMs ?? 0;
            if (family.refunds.any((refund) =>
                refund.createdAt.millisecondsSinceEpoch > resolvedMs &&
                !refund.createdAt.isAfter(query.knowledgeCutoff))) {
              refundReview = true;
            }
          }
          evaluations.add(FixedCommitmentCalculator.evaluate(
            occurrence: occurrence,
            asOf: query.asOf,
            exclusiveLinked: exclusive,
            familyNetCents: net,
            attributionOccurred: occurred,
            refundAfterMatchReview: refundReview,
          ));
        }
        final cycleProjection = _project(
          query: query,
          window: MetricWindow(
            startInclusive: cycle.start,
            endExclusive: cycle.endExclusive,
          ),
          families: families,
        );
        if (cycleProjection.value == null) {
          fixedStatus = MetricStatus.unavailable;
          fixedReasons.addAll(cycleProjection.reasons);
        } else {
          final summary = FixedCommitmentCalculator.summarizeCycle(
            cycleTotalCents: todayV2.cycleTotalCents!,
            totalSpentThroughNowCents:
                cycleProjection.value!.budgetExpenseMinor,
            occurrences: evaluations,
          );
          fixedActual = summary.fixedActualSpentThroughNowCents;
          fixedReserve = summary.fixedReserveNotYetInSpentCents;
          discretionary = summary.discretionaryRemainingCents;
          fixedStatus =
              summary.isPartial ? MetricStatus.partial : MetricStatus.available;
          for (final reason in summary.partialReasons) {
            fixedReasons.add(MetricReason(
              code: MetricReasonCode.fixedCommitmentsUnavailable,
              message: 'Fixed commitment needs review: ${reason.name}.',
              details: {'reason': reason.name},
            ));
          }
        }
      }
    } else if (query.viewKind == BudgetViewKind.cycle &&
        todayV2.status != BudgetPlanDayStatusV2.available) {
      fixedReasons.add(MetricReason(
        code: MetricReasonCode.fixedCommitmentsUnavailable,
        message: 'Legacy budgets do not have structured occurrences.',
      ));
    } else {
      fixedStatus = MetricStatus.notApplicable;
    }

    MetricWindow? previous;
    MetricWindow? current;
    MetricWindow? next;
    if (referenceV2.status == BudgetPlanDayStatusV2.available) {
      final plan = referenceV2.plan!;
      final cycle = referenceV2.cycle!;
      current = MetricWindow(
        startInclusive: cycle.start,
        endExclusive: cycle.endExclusive,
      );
      final previousCycle = plan.cycleFor(_addDays(cycle.start, -1));
      final nextCycle = plan.cycleFor(cycle.endExclusive);
      if (plan.covers(previousCycle.start)) {
        previous = MetricWindow(
          startInclusive: previousCycle.start,
          endExclusive: previousCycle.endExclusive,
        );
      }
      if (plan.covers(nextCycle.start)) {
        next = MetricWindow(
          startInclusive: nextCycle.start,
          endExclusive: nextCycle.endExclusive,
        );
      }
    }

    return BudgetWindowResult(
      query: query,
      viewWindow: window,
      planStatus: planStatus,
      planReasons: planReasons,
      spendStatus: projection.status,
      spendReasons: projection.reasons,
      dailyStatus: daily.status,
      dailyReasons: daily.reasons,
      fixedCommitmentStatus: fixedStatus,
      fixedCommitmentReasons: fixedReasons,
      plannedCents: plannedResult,
      spentCents: spent,
      remainingCents: remaining,
      progress: plannedResult != null && plannedResult > 0 && spent != null
          ? spent / plannedResult
          : null,
      timeProgress: _timeProgress(window, query.asOf),
      excludedForeignTransactionCount:
          projection.value?.excludedCurrencyEventCount ?? 0,
      planSlices: planSlices,
      cycleSlices: cycleSlices,
      categoryResults: categoryResults,
      currentCycleDailyStatus: daily.value,
      previousCycleWindow: previous,
      currentCycleWindow: current,
      nextCycleWindow: next,
      fixedActualSpentCents: fixedActual,
      fixedReserveCents: fixedReserve,
      discretionaryRemainingCents: discretionary,
    );
  }

  static _DailyResolution _v2DailyStatus({
    required BudgetWindowQuery query,
    required BudgetPlanDayResolutionV2 dayResult,
    required List<ConsumptionExpenseFamily> families,
  }) {
    final cycle = dayResult.cycle!;
    final today = _day(query.asOf);
    final cycleWindow = MetricWindow(
      startInclusive: cycle.start,
      endExclusive: cycle.endExclusive,
    );
    final through =
        _project(query: query, window: cycleWindow, families: families);
    final before = today.isAfter(cycle.start)
        ? _project(
            query: query,
            window: MetricWindow(
              startInclusive: cycle.start,
              endExclusive: today,
            ),
            families: families,
          )
        : null;
    final todayProjection = _project(
      query: query,
      window: MetricWindow(
        startInclusive: today,
        endExclusive: _addDays(today, 1),
      ),
      families: families,
    );
    if (through.value == null || todayProjection.value == null) {
      return _DailyResolution(
        value: null,
        status: MetricStatus.unavailable,
        reasons: [...through.reasons, ...todayProjection.reasons],
      );
    }
    final total = dayResult.cycleTotalCents!;
    final spentBefore = before?.value?.budgetExpenseMinor ?? 0;
    final spentToday = todayProjection.value!.budgetExpenseMinor;
    final spentThrough = through.value!.budgetExpenseMinor;
    final remainingDays = cycle.endExclusive.difference(today).inDays;
    if (remainingDays <= 0) {
      return _DailyResolution(
        value: null,
        status: MetricStatus.notApplicable,
        reasons: [
          MetricReason(
            code: MetricReasonCode.windowNotStarted,
            message: 'The active budget cycle has ended.',
          ),
        ],
      );
    }
    return _DailyResolution(
      value: BudgetCurrentCycleDailyStatus(
        planId: dayResult.plan!.id,
        cycleStart: cycle.start,
        cycleEndExclusive: cycle.endExclusive,
        cycleTotalCents: total,
        spentBeforeTodayCents: spentBefore,
        spentTodayCents: spentToday,
        spentThroughTodayCents: spentThrough,
        cycleRemainingCents: total - spentThrough,
        remainingDaysIncludingToday: remainingDays,
        todayRemainingAllowanceCents:
            _firstStableShare(total - spentBefore, remainingDays) - spentToday,
        plainBudgetDailyReferenceCents:
            _firstStableShare(total - spentThrough, remainingDays),
        timeProgress: _timeProgress(cycleWindow, query.asOf),
      ),
      status: [...through.reasons, ...todayProjection.reasons].isEmpty
          ? MetricStatus.available
          : MetricStatus.partial,
      reasons: [...through.reasons, ...todayProjection.reasons],
    );
  }

  static int _familyNetAtCutoff(
    ConsumptionExpenseFamily family,
    DateTime cutoff,
  ) {
    if (family.createdAt.isAfter(cutoff)) return 0;
    final refunded = family.refunds
        .where((refund) => !refund.createdAt.isAfter(cutoff))
        .fold<int>(0, (sum, refund) => sum + refund.amountMinor);
    final net = family.originalAmountMinor - refunded;
    return net < 0 ? 0 : net;
  }

  static _DailyResolution _currentCycleDailyStatus({
    required BudgetWindowQuery query,
    required List<BudgetPeriod> periods,
    required List<ConsumptionExpenseFamily> families,
  }) {
    final today = _day(query.asOf);
    final primary = LegacyBudgetAdapter.recurringPrimaryOn(
      periods,
      today,
      bookId: query.bookId,
      knowledgeCutoff: query.knowledgeCutoff,
    );
    if (primary == null) {
      return _DailyResolution(
        value: null,
        status: MetricStatus.notApplicable,
        reasons: [
          MetricReason(
            code: MetricReasonCode.noBudgetPlan,
            message: 'There is no active recurring cycle for daily guidance.',
          ),
        ],
      );
    }
    final bounds = _cycleFor(primary, today);
    final qualityReasons = <MetricReason>[];
    if (primary.bookId == null) {
      qualityReasons.add(MetricReason(
        code: MetricReasonCode.legacyScopeAmbiguous,
        message: 'The active legacy cycle has no explicit book scope.',
        details: {'planId': primary.id},
      ));
    }
    var cycleTotal = 0;
    for (var day = bounds.start;
        day.isBefore(bounds.endExclusive);
        day = _addDays(day, 1)) {
      final winner = LegacyBudgetAdapter.effectiveOn(
        periods,
        day,
        bookId: query.bookId,
        knowledgeCutoff: query.knowledgeCutoff,
      );
      if (winner == null) continue;
      final allocationCycle = _cycleFor(winner, day);
      final winnerTotal = _validBudgetCents(winner.total);
      final categoryTotal = winner.categoryBudgets.values.fold<int?>(
        0,
        (sum, amount) {
          final cents = _validBudgetCents(amount);
          return sum == null || cents == null ? null : sum + cents;
        },
      );
      if (winnerTotal == null ||
          categoryTotal == null ||
          categoryTotal > winnerTotal) {
        return _DailyResolution(
          value: null,
          status: MetricStatus.conflict,
          reasons: [
            MetricReason(
              code: winnerTotal == null || categoryTotal == null
                  ? MetricReasonCode.invalidInput
                  : MetricReasonCode.categoryBudgetExceedsPlan,
              message: 'The active cycle contains an invalid budget plan.',
              details: {'planId': winner.id},
            ),
          ],
        );
      }
      if (winner.bookId == null &&
          !qualityReasons.any((reason) =>
              reason.code == MetricReasonCode.legacyScopeAmbiguous)) {
        qualityReasons.add(MetricReason(
          code: MetricReasonCode.legacyScopeAmbiguous,
          message: 'The active legacy cycle has no explicit book scope.',
          details: {'planId': winner.id},
        ));
      }
      if (!winner.recurringMonthly &&
          winner.end == null &&
          !qualityReasons.any((reason) =>
              reason.code == MetricReasonCode.legacyOpenEndedOverride)) {
        qualityReasons.add(MetricReason(
          code: MetricReasonCode.legacyOpenEndedOverride,
          message: 'The active cycle contains an open-ended legacy override.',
          details: {'planId': winner.id},
        ));
      }
      cycleTotal += _stableDailyShare(
        winnerTotal,
        start: allocationCycle.start,
        endExclusive: allocationCycle.endExclusive,
        day: day,
      );
    }

    final cycleWindow = MetricWindow(
      startInclusive: bounds.start,
      endExclusive: bounds.endExclusive,
    );
    final beforeWindow = today.isAfter(bounds.start)
        ? MetricWindow(startInclusive: bounds.start, endExclusive: today)
        : null;
    final todayWindow = MetricWindow(
      startInclusive: today,
      endExclusive: _addDays(today, 1),
    );
    final throughResult = _project(
      query: query,
      window: cycleWindow,
      families: families,
    );
    final beforeResult = beforeWindow == null
        ? null
        : _project(
            query: query,
            window: beforeWindow,
            families: families,
          );
    final todayResult = _project(
      query: query,
      window: todayWindow,
      families: families,
    );
    final projectionResults = [
      throughResult,
      if (beforeResult != null) beforeResult,
      todayResult,
    ];
    for (final result in projectionResults) {
      for (final reason in result.reasons) {
        if (!qualityReasons.contains(reason)) qualityReasons.add(reason);
      }
    }
    final failed = projectionResults.where((result) => result.value == null);
    if (failed.isNotEmpty) {
      final status =
          failed.any((result) => result.status == MetricStatus.conflict)
              ? MetricStatus.conflict
              : MetricStatus.unavailable;
      return _DailyResolution(
        value: null,
        status: status,
        reasons: qualityReasons.isEmpty
            ? [
                MetricReason(
                  code: MetricReasonCode.invalidInput,
                  message: 'Current-cycle spending could not be resolved.',
                ),
              ]
            : qualityReasons,
      );
    }
    final through = throughResult.value!;
    final before = beforeResult?.value;
    final todayValue = todayResult.value!;

    final spentBefore = before?.budgetExpenseMinor ?? 0;
    final spentToday = todayValue.budgetExpenseMinor;
    final spentThrough = through.budgetExpenseMinor;
    final remainingDays = bounds.endExclusive.difference(today).inDays;
    if (remainingDays <= 0) {
      return _DailyResolution(
        value: null,
        status: MetricStatus.notApplicable,
        reasons: [
          MetricReason(
            code: MetricReasonCode.windowNotStarted,
            message: 'The active budget cycle has already ended.',
          ),
        ],
      );
    }
    final remaining = cycleTotal - spentThrough;
    final dailyReference = _firstStableShare(remaining, remainingDays);
    final todayAllowance =
        _firstStableShare(cycleTotal - spentBefore, remainingDays) - spentToday;
    return _DailyResolution(
      value: BudgetCurrentCycleDailyStatus(
        planId: primary.id,
        cycleStart: bounds.start,
        cycleEndExclusive: bounds.endExclusive,
        cycleTotalCents: cycleTotal,
        spentBeforeTodayCents: spentBefore,
        spentTodayCents: spentToday,
        spentThroughTodayCents: spentThrough,
        cycleRemainingCents: remaining,
        remainingDaysIncludingToday: remainingDays,
        todayRemainingAllowanceCents: todayAllowance,
        plainBudgetDailyReferenceCents: dailyReference,
        timeProgress: _timeProgress(cycleWindow, query.asOf),
      ),
      status: qualityReasons.isEmpty
          ? MetricStatus.available
          : MetricStatus.partial,
      reasons: qualityReasons,
    );
  }

  static MetricResult<ConsumptionProjectionValue> _project({
    required BudgetWindowQuery query,
    required MetricWindow window,
    required Iterable<ConsumptionExpenseFamily> families,
  }) =>
      ConsumptionProjection.resolve(
        query: MetricQuery(
          metricId: 'F-BUD-002',
          window: window,
          dateAxis: MetricDateAxis.attribution,
          timezone: query.calendarTimezone,
          bookScope: MetricBookScope(
            bookIds: [query.bookId],
            scopeVersion: 1,
          ),
          currencyScope: MetricCurrencyScope.single(query.currencyCode),
          asOf: query.asOf,
          knowledgeCutoff: query.knowledgeCutoff,
        ),
        expenseFamilies: families,
      );

  static MetricWindow _viewWindow(
    BudgetWindowQuery query, {
    required BudgetPeriod? referencePrimary,
    required BudgetPeriod? referenceWinner,
  }) {
    final reference = query.referenceDate;
    switch (query.viewKind) {
      case BudgetViewKind.calendarMonth:
        return MetricWindow(
          startInclusive: DateTime(reference.year, reference.month),
          endExclusive: DateTime(reference.year, reference.month + 1),
        );
      case BudgetViewKind.calendarWeek:
        final offset = (reference.weekday - query.weekStart + 7) % 7;
        final start = _addDays(reference, -offset);
        return MetricWindow(
          startInclusive: start,
          endExclusive: _addDays(start, 7),
        );
      case BudgetViewKind.custom:
        return MetricWindow(
          startInclusive: reference,
          endExclusive: _day(query.customEndExclusive!),
        );
      case BudgetViewKind.cycle:
        final plan = referencePrimary ?? referenceWinner;
        if (plan != null) {
          final cycle = _cycleFor(plan, reference);
          return MetricWindow(
            startInclusive: cycle.start,
            endExclusive: cycle.endExclusive,
          );
        }
        return MetricWindow(
          startInclusive: DateTime(reference.year, reference.month),
          endExclusive: DateTime(reference.year, reference.month + 1),
        );
    }
  }

  static _CycleBounds _cycleFor(BudgetPeriod period, DateTime day) {
    if (!period.recurringMonthly) {
      if (period.end == null) {
        return _CycleBounds(
          DateTime(day.year, day.month),
          DateTime(day.year, day.month + 1),
        );
      }
      final start = _day(period.start);
      final end = _day(period.end!);
      return _CycleBounds(start, _addDays(end, 1));
    }
    return _CycleBounds(
      DateTime(day.year, day.month),
      DateTime(day.year, day.month + 1),
    );
  }

  static MetricWindow? _adjacentRecurringCycle({
    required List<BudgetPeriod> periods,
    required BudgetWindowQuery query,
    required _CycleBounds current,
    required bool previous,
  }) {
    final adjacentDay =
        previous ? _addDays(current.start, -1) : current.endExclusive;
    final adjacentPlan = LegacyBudgetAdapter.recurringPrimaryOn(
      periods,
      adjacentDay,
      bookId: query.bookId,
      knowledgeCutoff: query.knowledgeCutoff,
    );
    if (adjacentPlan == null) return null;
    final adjacent = _cycleFor(adjacentPlan, adjacentDay);
    return MetricWindow(
      startInclusive: adjacent.start,
      endExclusive: adjacent.endExclusive,
    );
  }
}

class _CycleBounds {
  final DateTime start;
  final DateTime endExclusive;

  const _CycleBounds(this.start, this.endExclusive);

  @override
  bool operator ==(Object other) =>
      other is _CycleBounds &&
      start == other.start &&
      endExclusive == other.endExclusive;

  @override
  int get hashCode => Object.hash(start, endExclusive);
}

class _DailyResolution {
  final BudgetCurrentCycleDailyStatus? value;
  final MetricStatus status;
  final List<MetricReason> reasons;

  _DailyResolution({
    required this.value,
    required this.status,
    required Iterable<MetricReason> reasons,
  }) : reasons = List.unmodifiable(reasons);
}

int decimalToBudgetCents(Decimal amount) {
  var raw = amount.toString();
  var sign = 1;
  if (raw.startsWith('-')) {
    sign = -1;
    raw = raw.substring(1);
  }
  final parts = raw.split('.');
  final whole = int.parse(parts.first.isEmpty ? '0' : parts.first);
  final fraction = parts.length > 1 ? parts[1] : '';
  if (fraction.length > 2 &&
      fraction.substring(2).split('').any((digit) => digit != '0')) {
    throw ArgumentError.value(amount, 'amount', 'must use integer cents');
  }
  final cents = int.parse(fraction.padRight(2, '0').substring(0, 2));
  return sign * (whole * 100 + cents);
}

int? _validBudgetCents(Decimal amount) {
  try {
    final cents = decimalToBudgetCents(amount);
    return cents < 0 ? null : cents;
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

Decimal? budgetDecimalFromCents(int? cents) {
  if (cents == null) return null;
  final negative = cents < 0;
  final absolute = cents.abs();
  final value = '${negative ? '-' : ''}${absolute ~/ 100}.'
      '${(absolute % 100).toString().padLeft(2, '0')}';
  return Decimal.parse(value);
}

int _stableDailyShare(
  int total, {
  required DateTime start,
  required DateTime endExclusive,
  required DateTime day,
}) {
  final days = endExclusive.difference(start).inDays;
  final index = day.difference(start).inDays;
  if (days <= 0 || index < 0 || index >= days) return 0;
  final sign = total < 0 ? -1 : 1;
  final absolute = total.abs();
  final base = absolute ~/ days;
  final remainder = absolute % days;
  return sign * (base + (index < remainder ? 1 : 0));
}

int _firstStableShare(int total, int days) {
  if (days <= 0) return 0;
  final sign = total < 0 ? -1 : 1;
  final absolute = total.abs();
  return sign * (absolute ~/ days + (absolute % days > 0 ? 1 : 0));
}

double _timeProgress(MetricWindow window, DateTime asOf) {
  final total = window.endExclusive.difference(window.startInclusive).inDays;
  if (total <= 0) return 0;
  final asOfDay = _day(asOf);
  if (asOfDay.isBefore(window.startInclusive)) return 0;
  if (!asOfDay.isBefore(window.endExclusive)) return 1;
  final elapsed = asOfDay.difference(window.startInclusive).inDays + 1;
  return (elapsed / total).clamp(0.0, 1.0);
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
DateTime _addDays(DateTime value, int days) =>
    DateTime(value.year, value.month, value.day + days);
