import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/statistics/comparison_window.dart';
import 'package:qingji/core/statistics/metric_contract.dart';

MetricQuery _query({
  required DateTime start,
  required DateTime end,
  required DateTime asOf,
}) =>
    MetricQuery(
      metricId: 'F-TXN-001',
      window: MetricWindow(startInclusive: start, endExclusive: end),
      dateAxis: MetricDateAxis.attribution,
      timezone: 'Asia/Shanghai',
      bookScope: MetricBookScope(bookIds: [1, 2], scopeVersion: 2),
      currencyScope: MetricCurrencyScope.single('CNY'),
      asOf: asOf,
      knowledgeCutoff: asOf,
      classificationVersion: 3,
    );

void main() {
  group('ComparisonWindowResolver calendar periods', () {
    test('unfinished month compares equal day progress', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
          asOf: DateTime.utc(2026, 7, 13, 12),
        ),
        kind: ComparisonWindowKind.calendarMonth,
      );
      final value = result.value!;

      expect(value.currentWindowComplete, isFalse);
      expect(value.currentComparableDayCount, 13);
      expect(value.previousComparableDayCount, 13);
      expect(value.qualifier, '前13天');
      expect(
        value.currentComparableQuery.window.endExclusive,
        DateTime.utc(2026, 7, 14),
      );
      expect(
        value.previousComparableQuery.window,
        MetricWindow(
          startInclusive: DateTime.utc(2026, 6, 1),
          endExclusive: DateTime.utc(2026, 6, 14),
        ),
      );
    });

    test('day 31 clips both sides to the shorter 30-day month', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
          asOf: DateTime.utc(2026, 7, 31, 12),
        ),
        kind: ComparisonWindowKind.calendarMonth,
      );
      final value = result.value!;

      expect(value.currentComparableDayCount, 30);
      expect(value.previousComparableDayCount, 30);
      expect(value.qualifier, '前30天');
      expect(
        value.currentComparableQuery.window.endExclusive,
        DateTime.utc(2026, 7, 31),
      );
      expect(
        value.previousComparableQuery.window.endExclusive,
        DateTime.utc(2026, 7, 1),
      );
    });

    test('completed month compares complete periods without relabeling', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 8, 1),
          asOf: DateTime.utc(2026, 8, 1),
        ),
        kind: ComparisonWindowKind.calendarMonth,
      );
      final value = result.value!;

      expect(value.currentWindowComplete, isTrue);
      expect(value.currentComparableDayCount, 31);
      expect(value.previousComparableDayCount, 30);
      expect(value.qualifier, isNull);
    });

    test('unfinished week compares the same weekday progress', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 13),
          end: DateTime.utc(2026, 7, 20),
          asOf: DateTime.utc(2026, 7, 15, 18),
        ),
        kind: ComparisonWindowKind.calendarWeek,
      );

      expect(result.value!.currentComparableDayCount, 3);
      expect(
        result.value!.previousComparableQuery.window,
        MetricWindow(
          startInclusive: DateTime.utc(2026, 7, 6),
          endExclusive: DateTime.utc(2026, 7, 9),
        ),
      );
    });

    test('default natural week rejects a Wednesday start', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 15),
          end: DateTime.utc(2026, 7, 22),
          asOf: DateTime.utc(2026, 7, 17),
        ),
        kind: ComparisonWindowKind.calendarWeek,
      );

      expect(result.status, MetricStatus.conflict);
      expect(result.reasons.single.code, MetricReasonCode.invalidInput);
    });

    test('configured Wednesday week accepts a Wednesday start', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 15),
          end: DateTime.utc(2026, 7, 22),
          asOf: DateTime.utc(2026, 7, 17),
        ),
        kind: ComparisonWindowKind.calendarWeek,
        weekStart: DateTime.wednesday,
      );

      expect(result.status, MetricStatus.available);
      expect(result.value!.currentComparableDayCount, 3);
    });

    test('leap day is clipped to an equal first-59-day comparison', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2024, 1, 1),
          end: DateTime.utc(2025, 1, 1),
          asOf: DateTime.utc(2024, 2, 29, 12),
        ),
        kind: ComparisonWindowKind.calendarYear,
      );
      final value = result.value!;

      expect(value.currentComparableDayCount, 59);
      expect(value.previousComparableDayCount, 59);
      expect(value.qualifier, '前59天');
      expect(
        value.currentComparableQuery.window.endExclusive,
        DateTime.utc(2024, 2, 29),
      );
      expect(
        value.previousComparableQuery.window.endExclusive,
        DateTime.utc(2023, 3, 1),
      );
    });
  });

  group('ComparisonWindowResolver custom and budget periods', () {
    test('custom N-day window uses the immediately preceding N days', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 11),
          end: DateTime.utc(2026, 7, 16),
          asOf: DateTime.utc(2026, 7, 16),
        ),
        kind: ComparisonWindowKind.custom,
      );

      expect(
        result.value!.previousComparableQuery.window,
        MetricWindow(
          startInclusive: DateTime.utc(2026, 7, 6),
          endExclusive: DateTime.utc(2026, 7, 11),
        ),
      );
    });

    test('budget cycle uses the caller-supplied previous cycle', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 15),
          end: DateTime.utc(2026, 8, 15),
          asOf: DateTime.utc(2026, 7, 20, 12),
        ),
        kind: ComparisonWindowKind.budgetCycle,
        previousBudgetCycle: MetricWindow(
          startInclusive: DateTime.utc(2026, 6, 15),
          endExclusive: DateTime.utc(2026, 7, 15),
        ),
      );

      expect(result.value!.currentComparableDayCount, 6);
      expect(result.value!.previousComparableDayCount, 6);
      expect(
        result.value!.previousComparableQuery.window.endExclusive,
        DateTime.utc(2026, 6, 21),
      );
    });

    test('future window is not applicable rather than a zero comparison', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 8, 1),
          end: DateTime.utc(2026, 9, 1),
          asOf: DateTime.utc(2026, 7, 13),
        ),
        kind: ComparisonWindowKind.calendarMonth,
      );

      expect(result.status, MetricStatus.notApplicable);
      expect(result.value, isNull);
      expect(result.reasons.single.code, MetricReasonCode.windowNotStarted);
    });

    test('budget cycle without its predecessor is a conflict', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 15),
          end: DateTime.utc(2026, 8, 15),
          asOf: DateTime.utc(2026, 7, 20),
        ),
        kind: ComparisonWindowKind.budgetCycle,
      );

      expect(result.status, MetricStatus.conflict);
      expect(result.reasons.single.code, MetricReasonCode.noComparableWindow);
    });

    test('budget cycle rejects a non-adjacent predecessor', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 15),
          end: DateTime.utc(2026, 8, 15),
          asOf: DateTime.utc(2026, 7, 20),
        ),
        kind: ComparisonWindowKind.budgetCycle,
        previousBudgetCycle: MetricWindow(
          startInclusive: DateTime.utc(2026, 6, 1),
          endExclusive: DateTime.utc(2026, 7, 1),
        ),
      );

      expect(result.status, MetricStatus.conflict);
      expect(result.reasons.single.code, MetricReasonCode.invalidInput);
    });

    test('budget cycle rejects a different DateTime representation', () {
      final result = ComparisonWindowResolver.resolve(
        query: _query(
          start: DateTime.utc(2026, 7, 15),
          end: DateTime.utc(2026, 8, 15),
          asOf: DateTime.utc(2026, 7, 20),
        ),
        kind: ComparisonWindowKind.budgetCycle,
        previousBudgetCycle: MetricWindow(
          startInclusive: DateTime(2026, 6, 15),
          endExclusive: DateTime(2026, 7, 15),
        ),
      );

      expect(result.status, MetricStatus.conflict);
      expect(result.reasons.single.code, MetricReasonCode.invalidInput);
    });
  });
}
