import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/budget_period.dart';
import 'package:qingji/core/budget/budget_window_resolver.dart';
import 'package:qingji/core/statistics/consumption_projection.dart';
import 'package:qingji/core/statistics/metric_contract.dart';

BudgetPeriod _period({
  required int id,
  int? bookId = 1,
  required DateTime start,
  DateTime? end,
  bool recurring = true,
  required String total,
  Map<String, Decimal> categories = const {},
  int createdMs = 0,
}) =>
    BudgetPeriod(
      id: id,
      bookId: bookId,
      start: start,
      end: end,
      recurringMonthly: recurring,
      total: Decimal.parse(total),
      categoryBudgets: categories,
      createdMs: createdMs,
    );

ConsumptionExpenseFamily _expense({
  required String id,
  int? bookId = 1,
  String currency = 'CNY',
  required DateTime date,
  required int cents,
  String categoryKey = 'dining',
  List<ConsumptionRefund> refunds = const [],
}) =>
    ConsumptionExpenseFamily(
      id: id,
      bookId: bookId,
      currencyCode: currency,
      attributionDate: date,
      createdAt: date,
      originalAmountMinor: cents,
      categoryAllocations: [
        ConsumptionCategoryAllocation(
          categoryKey: categoryKey,
          categoryName: categoryKey,
          amountMinor: cents,
        ),
      ],
      refunds: refunds,
    );

BudgetWindowQuery _query({
  BudgetViewKind kind = BudgetViewKind.calendarMonth,
  DateTime? reference,
  DateTime? customEndExclusive,
  DateTime? asOf,
  DateTime? knowledgeCutoff,
}) {
  final ref = reference ?? DateTime(2026, 7, 10);
  final cutoff = asOf ?? DateTime(2026, 7, 31, 23, 59);
  return BudgetWindowQuery(
    viewKind: kind,
    bookId: 1,
    referenceDate: ref,
    customEndExclusive: customEndExclusive,
    asOf: cutoff,
    knowledgeCutoff: knowledgeCutoff ?? cutoff,
    calendarTimezone: 'Asia/Shanghai',
  );
}

void main() {
  group('BudgetWindowResolver stable legacy calendar', () {
    test('allocates integer cents once and returns the exact full-cycle total',
        () {
      final plan = _period(
        id: 1,
        start: DateTime(2026, 7, 1),
        total: '100.00',
      );
      final full = BudgetWindowResolver.resolve(
        query: _query(),
        periods: [plan],
      );
      final firstDay = BudgetWindowResolver.resolve(
        query: _query(
          kind: BudgetViewKind.custom,
          reference: DateTime(2026, 7, 1),
          customEndExclusive: DateTime(2026, 7, 2),
        ),
        periods: [plan],
      );

      expect(full.planStatus, MetricStatus.available);
      expect(full.plannedCents, 10000);
      expect(firstDay.plannedCents, 323);
      expect(
        full.cycleSlices.fold<int>(0, (sum, slice) => sum + slice.plannedCents),
        10000,
      );
    });

    test('legacy recurring start day is effective date, not a cycle anchor',
        () {
      final result = BudgetWindowResolver.resolve(
        query: _query(
          kind: BudgetViewKind.cycle,
          reference: DateTime(2026, 7, 20),
        ),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 15),
            total: '3100',
          ),
        ],
      );

      expect(result.viewWindow.startInclusive, DateTime(2026, 7, 1));
      expect(result.viewWindow.endExclusive, DateTime(2026, 8, 1));
      expect(result.plannedCents, 310000);
      expect(result.previousCycleWindow?.startInclusive, DateTime(2026, 6, 1));
      expect(result.nextCycleWindow?.endExclusive, DateTime(2026, 9, 1));
    });

    test('long-lived day-15 legacy plan keeps its natural-month golden', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 15),
            total: '3100',
          ),
        ],
      );

      expect(result.viewWindow.startInclusive, DateTime(2026, 7, 1));
      expect(result.viewWindow.endExclusive, DateTime(2026, 8, 1));
      expect(result.cycleSlices, hasLength(1));
      expect(result.plannedCents, 310000);
    });

    test('the first partial month does not invent a previous cycle', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(
          kind: BudgetViewKind.cycle,
          reference: DateTime(2026, 7, 20),
        ),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 7, 15),
            total: '3100',
          ),
        ],
      );

      expect(result.viewWindow.startInclusive, DateTime(2026, 7, 1));
      expect(result.plannedCents, 170000);
      expect(result.previousCycleWindow, isNull);
      expect(result.nextCycleWindow?.startInclusive, DateTime(2026, 8, 1));
    });

    test('one-off legacy period replaces recurring daily allocation', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 1),
            total: '3100',
          ),
          _period(
            id: 2,
            start: DateTime(2026, 7, 11),
            end: DateTime(2026, 7, 20),
            recurring: false,
            total: '2000',
          ),
        ],
      );

      expect(result.plannedCents, 410000);
      expect(result.planSlices, hasLength(3));
      expect(result.planSlices[1].legacyOverride, isTrue);
      expect(
        result.cycleSlices.map((slice) => slice.stableId).toSet(),
        hasLength(result.cycleSlices.length),
      );
    });

    test('knowledge cutoff hides plans and overrides created later', () {
      final oldCreated = DateTime(2026, 6, 1).millisecondsSinceEpoch;
      final newCreated = DateTime(2026, 8, 1).millisecondsSinceEpoch;
      final periods = [
        _period(
          id: 1,
          start: DateTime(2026, 1, 1),
          total: '1000',
          createdMs: oldCreated,
        ),
        _period(
          id: 2,
          start: DateTime(2026, 1, 1),
          total: '2000',
          createdMs: newCreated,
        ),
      ];
      final frozen = BudgetWindowResolver.resolve(
        query: _query(
          asOf: DateTime(2026, 8, 3),
          knowledgeCutoff: DateTime(2026, 7, 31, 23, 59),
        ),
        periods: periods,
      );
      final live = BudgetWindowResolver.resolve(
        query: _query(asOf: DateTime(2026, 8, 3)),
        periods: periods,
      );

      expect(frozen.plannedCents, 100000);
      expect(live.plannedCents, 200000);
    });

    test('open-ended one-off uses the legacy monthly fallback and is partial',
        () {
      final result = BudgetWindowResolver.resolve(
        query: _query(),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 7, 10),
            recurring: false,
            total: '3100',
          ),
        ],
      );

      expect(result.planStatus, MetricStatus.partial);
      expect(result.plannedCents, 220000);
      expect(
        result.planReasons.map((reason) => reason.code),
        contains(MetricReasonCode.legacyOpenEndedOverride),
      );
    });

    test('legacy null book scope stays usable but explicitly partial', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(),
        periods: [
          _period(
            id: 1,
            bookId: null,
            start: DateTime(2026, 1, 1),
            total: '3000',
          ),
        ],
      );

      expect(result.planStatus, MetricStatus.partial);
      expect(result.plannedCents, 300000);
      expect(result.dailyStatus, MetricStatus.partial);
      expect(result.currentCycleDailyStatus, isNotNull);
      expect(
        result.planReasons.map((reason) => reason.code),
        contains(MetricReasonCode.legacyScopeAmbiguous),
      );
    });

    test('one-off cycle without a primary is marked partial legacy data', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(
          kind: BudgetViewKind.cycle,
          reference: DateTime(2026, 7, 15),
        ),
        periods: [
          _period(
            id: 2,
            start: DateTime(2026, 7, 10),
            end: DateTime(2026, 7, 20),
            recurring: false,
            total: '1100',
          ),
        ],
      );

      expect(result.plannedCents, 110000);
      expect(result.planStatus, MetricStatus.partial);
      expect(
        result.planReasons.map((reason) => reason.code),
        contains(MetricReasonCode.legacyOverrideWithoutPrimary),
      );
      expect(result.dailyStatus, MetricStatus.notApplicable);
    });

    test('category totals exceeding the plan are a conflict', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 7, 1),
            total: '100',
            categories: {
              'dining': Decimal.fromInt(80),
              'shopping': Decimal.fromInt(30),
            },
          ),
        ],
      );

      expect(result.planStatus, MetricStatus.conflict);
      expect(result.plannedCents, isNull);
      expect(result.remainingCents, isNull);
      expect(result.dailyStatus, MetricStatus.conflict);
      expect(result.currentCycleDailyStatus, isNull);
    });

    test('invalid persisted amounts become conflicts instead of throwing', () {
      for (final total in ['-1', '1.001']) {
        final result = BudgetWindowResolver.resolve(
          query: _query(),
          periods: [
            _period(
              id: 1,
              start: DateTime(2026, 7, 1),
              total: total,
            ),
          ],
        );

        expect(result.planStatus, MetricStatus.conflict, reason: total);
        expect(result.plannedCents, isNull, reason: total);
        expect(
          result.planReasons.map((reason) => reason.code),
          contains(MetricReasonCode.invalidInput),
          reason: total,
        );
      }
    });
  });

  group('BudgetWindowResolver spending and honest states', () {
    test('no plan is unavailable while real spending remains visible', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(),
        periods: const [],
        expenseFamilies: [
          _expense(
            id: 'meal',
            date: DateTime(2026, 7, 2),
            cents: 2000,
          ),
        ],
      );

      expect(result.planStatus, MetricStatus.unavailable);
      expect(result.plannedCents, isNull);
      expect(result.spendStatus, MetricStatus.available);
      expect(result.spentCents, 2000);
      expect(result.remainingCents, isNull);
    });

    test('foreign expenses are excluded and make spending partial', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 1),
            total: '1000',
          ),
        ],
        expenseFamilies: [
          _expense(
            id: 'cny',
            date: DateTime(2026, 7, 2),
            cents: 2000,
          ),
          _expense(
            id: 'usd',
            currency: 'USD',
            date: DateTime(2026, 7, 3),
            cents: 3000,
          ),
        ],
      );

      expect(result.spentCents, 2000);
      expect(result.spendStatus, MetricStatus.partial);
      expect(result.excludedForeignTransactionCount, 1);
      expect(result.remainingCents, 98000);
      expect(result.dailyStatus, MetricStatus.partial);
      expect(result.currentCycleDailyStatus, isNotNull);
    });

    test('current cycle daily guidance matches the legacy monthly example', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(
          kind: BudgetViewKind.cycle,
          reference: DateTime(2026, 6, 10),
          asOf: DateTime(2026, 6, 10, 23, 59),
        ),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 1),
            total: '3000',
          ),
        ],
        expenseFamilies: [
          _expense(
            id: 'before',
            date: DateTime(2026, 6, 5),
            cents: 90000,
          ),
          _expense(
            id: 'today',
            date: DateTime(2026, 6, 10),
            cents: 5000,
          ),
        ],
      );
      final daily = result.currentCycleDailyStatus!;

      expect(daily.spentBeforeTodayCents, 90000);
      expect(daily.spentTodayCents, 5000);
      expect(daily.cycleRemainingCents, 205000);
      expect(daily.remainingDaysIncludingToday, 21);
      expect(daily.todayRemainingAllowanceCents, 5000);
      expect(daily.plainBudgetDailyReferenceCents, 9762);
      expect(result.fixedCommitmentStatus, MetricStatus.unavailable);
    });

    test('a later refund corrects the original budget window at live cutoff',
        () {
      final original = _expense(
        id: 'order',
        date: DateTime(2026, 7, 2),
        cents: 10000,
        refunds: [
          ConsumptionRefund(
            id: 'refund',
            amountMinor: 4000,
            createdAt: DateTime(2026, 8, 2),
            effectiveAt: DateTime(2026, 8, 2),
          ),
        ],
      );
      final live = BudgetWindowResolver.resolve(
        query: _query(asOf: DateTime(2026, 8, 3)),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 1),
            total: '1000',
          ),
        ],
        expenseFamilies: [original],
      );
      final frozen = BudgetWindowResolver.resolve(
        query: BudgetWindowQuery(
          viewKind: BudgetViewKind.calendarMonth,
          bookId: 1,
          referenceDate: DateTime(2026, 7),
          asOf: DateTime(2026, 8, 3),
          knowledgeCutoff: DateTime(2026, 7, 31, 23, 59),
          calendarTimezone: 'Asia/Shanghai',
        ),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 1),
            total: '1000',
          ),
        ],
        expenseFamilies: [original],
      );

      expect(live.spentCents, 6000);
      expect(frozen.spentCents, 10000);
    });

    test('category planned and spent values share the same window', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 1),
            total: '1000',
            categories: {'dining': Decimal.fromInt(600)},
          ),
        ],
        expenseFamilies: [
          _expense(
            id: 'meal',
            date: DateTime(2026, 7, 2),
            cents: 20000,
          ),
        ],
      );
      final dining = result.categoryResults.singleWhere(
        (category) => category.categoryKey == 'dining',
      );

      expect(dining.plannedCents, 60000);
      expect(dining.spentCents, 20000);
      expect(dining.remainingCents, 40000);
    });
  });

  group('BudgetWindowResolver query boundaries', () {
    test('calendar week always uses the configured natural-week start', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(
          kind: BudgetViewKind.calendarWeek,
          reference: DateTime(2026, 7, 15),
        ),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 1),
            total: '3100',
          ),
        ],
      );

      expect(result.viewWindow.startInclusive, DateTime(2026, 7, 13));
      expect(result.viewWindow.endExclusive, DateTime(2026, 7, 20));
      expect(result.plannedCents, 70000);
    });

    test('available zero is distinct from no plan', () {
      final zero = BudgetWindowResolver.resolve(
        query: _query(),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 1),
            total: '0',
          ),
        ],
      );
      final none = BudgetWindowResolver.resolve(
        query: _query(),
        periods: const [],
      );

      expect(zero.planStatus, MetricStatus.available);
      expect(zero.plannedCents, 0);
      expect(none.planStatus, MetricStatus.unavailable);
      expect(none.plannedCents, isNull);
      expect(none.isOverBudget, isNull);
    });

    test('category ordering has a stable key tie-breaker', () {
      final result = BudgetWindowResolver.resolve(
        query: _query(),
        periods: [
          _period(
            id: 1,
            start: DateTime(2026, 1, 1),
            total: '1000',
            categories: {
              'beta': Decimal.fromInt(100),
              'alpha': Decimal.fromInt(100),
            },
          ),
        ],
      );

      expect(
        result.categoryResults.map((category) => category.categoryKey),
        ['alpha', 'beta'],
      );
    });
  });
}
