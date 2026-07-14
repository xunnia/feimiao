import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/account/net_worth_snapshot.dart';

final _cny = NetWorthCurrencyCoverage.single('CNY');

ComputedNetWorthSnapshot _snapshot({
  required int day,
  int cash = 10000,
  int investments = 0,
  int physical = 0,
  int receivables = 0,
  int liabilities = 0,
  int scopeVersion = 1,
  int calculationVersion = 1,
  String timezone = 'Asia/Shanghai',
  NetWorthCurrencyCoverage? currencies,
  NetWorthSnapshotQuality quality = NetWorthSnapshotQuality.available,
  Iterable<NetWorthSnapshotCause> causes = const [
    NetWorthSnapshotCause.transaction,
  ],
  int cutoffHour = 12,
}) {
  final date = DateTime.utc(2026, 7, day);
  final requiresReason = quality != NetWorthSnapshotQuality.available;
  return ComputedNetWorthSnapshot.fromEvaluation(
    requestedAsOf: date,
    evaluation: NetWorthAsOfEvaluation(
      asOf: date,
      components: NetWorthSnapshotComponents(
        cashAssetsMinor: cash,
        investmentAssetsMinor: investments,
        physicalAssetsMinor: physical,
        receivableAssetsMinor: receivables,
        liabilitiesMinor: liabilities,
      ),
    ),
    knowledgeCutoff: DateTime.utc(2026, 7, day, cutoffHour),
    timezone: timezone,
    scopeVersion: scopeVersion,
    calculationVersion: calculationVersion,
    currencyCoverage: currencies ?? _cny,
    quality: quality,
    reasons: requiresReason
        ? [
            NetWorthSnapshotReason(
              code: quality.storageKey,
              message: 'quality marker',
            ),
          ]
        : const [],
    provisional: false,
    causes: causes,
  );
}

void main() {
  group('computed snapshot lineage', () {
    test('cannot relabel a current evaluation as a historical snapshot', () {
      final todayEvaluation = NetWorthAsOfEvaluation(
        asOf: DateTime.utc(2026, 7, 13),
        components: const NetWorthSnapshotComponents(
          cashAssetsMinor: 10000,
          investmentAssetsMinor: 0,
          physicalAssetsMinor: 0,
          receivableAssetsMinor: 0,
          liabilitiesMinor: 0,
        ),
      );

      expect(
        () => ComputedNetWorthSnapshot.fromEvaluation(
          requestedAsOf: DateTime.utc(2026, 6, 30),
          evaluation: todayEvaluation,
          knowledgeCutoff: DateTime.utc(2026, 7, 13, 12),
          timezone: 'Asia/Shanghai',
          scopeVersion: 1,
          calculationVersion: 1,
          currencyCoverage: _cny,
          quality: NetWorthSnapshotQuality.available,
          provisional: false,
          causes: const [NetWorthSnapshotCause.scheduledRebuild],
        ),
        throwsStateError,
      );
    });

    test('same-day coalescing keeps latest value and merges every cause', () {
      final morning = _snapshot(
        day: 13,
        cash: 10000,
        cutoffHour: 9,
        causes: const [NetWorthSnapshotCause.transaction],
      );
      final evening = _snapshot(
        day: 13,
        cash: 12000,
        cutoffHour: 18,
        causes: const [
          NetWorthSnapshotCause.refund,
          NetWorthSnapshotCause.valuation,
        ],
      );

      final merged = mergeSameDayComputedSnapshots(morning, evening);

      expect(merged.netWorthMinor, 12000);
      expect(merged.lineage.knowledgeCutoff, DateTime.utc(2026, 7, 13, 18));
      expect(merged.lineage.causes, {
        NetWorthSnapshotCause.transaction,
        NetWorthSnapshotCause.refund,
        NetWorthSnapshotCause.valuation,
      });
    });

    test('unknown stored quality fails closed as legacy unverified', () {
      expect(
        NetWorthSnapshotQualityX.fromStorage('future_value'),
        NetWorthSnapshotQuality.legacyUnverified,
      );
    });
  });

  group('estimated net-worth trend eligibility', () {
    test('legacy snapshot is isolated and cannot provide a second point', () {
      final legacy = _snapshot(
        day: 1,
        quality: NetWorthSnapshotQuality.legacyUnverified,
        causes: const [NetWorthSnapshotCause.migration],
      );
      final computed = _snapshot(day: 2, cash: 11000);

      final result = resolveNetWorthTrend([legacy, computed]);

      expect(result.status, NetWorthTrendStatus.insufficientEligiblePoints);
      expect(result.hasTrend, isFalse);
      expect(result.isolatedPoints, [legacy]);
      expect(result.changes, isEmpty);
      expect(result.breaks.single.issues,
          contains(NetWorthComparabilityIssue.ineligibleQuality));
    });

    test('zero or one eligible point returns an explicit empty state', () {
      final empty = resolveNetWorthTrend(const []);
      final one = resolveNetWorthTrend([_snapshot(day: 1)]);

      expect(empty.status, NetWorthTrendStatus.insufficientEligiblePoints);
      expect(one.status, NetWorthTrendStatus.insufficientEligiblePoints);
      expect(empty.hasTrend, isFalse);
      expect(one.hasTrend, isFalse);
      expect(one.changes, isEmpty);
    });

    test('stale point breaks both adjacent edges instead of being bridged', () {
      final first = _snapshot(day: 1, cash: 10000);
      final stale = _snapshot(
        day: 2,
        cash: 11000,
        quality: NetWorthSnapshotQuality.stale,
        causes: const [NetWorthSnapshotCause.historicalBackfill],
      );
      final third = _snapshot(day: 3, cash: 12000);

      final result = resolveNetWorthTrend([first, stale, third]);

      expect(result.status, NetWorthTrendStatus.noComparablePairs);
      expect(result.isolatedPoints, [stale]);
      expect(result.breaks, hasLength(2));
      expect(result.changes, isEmpty);
      expect(result.segments.map((segment) => segment.points.length), [1, 1]);
    });

    test('scope, calculation, currency and timezone changes are hard breaks',
        () {
      final base = _snapshot(day: 1);
      final scope = _snapshot(day: 2, scopeVersion: 2);
      final calculation = _snapshot(day: 2, calculationVersion: 2);
      final currency = _snapshot(
        day: 2,
        currencies: NetWorthCurrencyCoverage(
          baseCurrency: 'CNY',
          coveredCurrencies: const ['CNY'],
          uncoveredCurrencies: const ['USD'],
        ),
        quality: NetWorthSnapshotQuality.partial,
      );
      final timezone = _snapshot(day: 2, timezone: 'UTC');

      expect(
        compareComputedNetWorthSnapshots(base, scope).issues,
        contains(NetWorthComparabilityIssue.scopeVersionMismatch),
      );
      expect(
        compareComputedNetWorthSnapshots(base, calculation).issues,
        contains(NetWorthComparabilityIssue.calculationVersionMismatch),
      );
      expect(
        compareComputedNetWorthSnapshots(base, currency).issues,
        contains(NetWorthComparabilityIssue.currencyCoverageMismatch),
      );
      expect(
        compareComputedNetWorthSnapshots(base, timezone).issues,
        contains(NetWorthComparabilityIssue.timezoneMismatch),
      );
    });

    test('incompatible lineage creates segments and never emits a rate', () {
      final oldScope = _snapshot(day: 1, cash: 10000, scopeVersion: 1);
      final newScope = _snapshot(day: 2, cash: 20000, scopeVersion: 2);
      final next = _snapshot(day: 3, cash: 22000, scopeVersion: 2);

      final result = resolveNetWorthTrend([oldScope, newScope, next]);

      expect(result.status, NetWorthTrendStatus.available);
      expect(result.breaks, hasLength(1));
      expect(result.segments.map((segment) => segment.points.length), [1, 2]);
      expect(result.changes, hasLength(1));
      expect(result.changes.single.amountDeltaMinor, 2000);
      expect(
        result.changes.any((change) => change.earlier == oldScope),
        isFalse,
      );
    });
  });

  group('adjacent change explanation', () {
    test('normal positive values expose amount, rate and exact components', () {
      final earlier = _snapshot(
        day: 1,
        cash: 10000,
        investments: 2000,
        physical: 3000,
        receivables: 1000,
        liabilities: 4000,
      );
      final later = _snapshot(
        day: 2,
        cash: 10500,
        investments: 1800,
        physical: 3500,
        receivables: 900,
        liabilities: 3500,
        causes: const [
          NetWorthSnapshotCause.transaction,
          NetWorthSnapshotCause.valuation,
          NetWorthSnapshotCause.liability,
          NetWorthSnapshotCause.historicalBackfill,
        ],
      );

      final change = resolveNetWorthTrend([earlier, later]).changes.single;

      expect(earlier.netWorthMinor, 12000);
      expect(later.netWorthMinor, 13200);
      expect(change.amountDeltaMinor, 1200);
      expect(change.percentageChange, closeTo(0.1, 0.000001));
      expect(change.rateSuppressionReason, isNull);
      expect(change.componentChanges, hasLength(5));
      expect(
        change.componentChanges.fold<int>(
          0,
          (sum, item) => sum + item.netWorthContributionMinor,
        ),
        change.amountDeltaMinor,
      );
      expect(
        change.componentChanges
            .singleWhere(
              (item) => item.component == NetWorthChangeComponent.liabilities,
            )
            .netWorthContributionMinor,
        500,
      );
      expect(
          change.causeSummaries.map((summary) => summary.group),
          containsAll([
            NetWorthChangeCauseGroup.accountEvents,
            NetWorthChangeCauseGroup.valuationChanges,
            NetWorthChangeCauseGroup.liabilityEvents,
            NetWorthChangeCauseGroup.calibrationOrBackfill,
          ]));
      expect(
        change.causeSummaries.expand((summary) => summary.causes).toSet(),
        later.lineage.causes,
      );
    });

    test('negative or cross-zero net worth only reports the amount delta', () {
      final positive = _snapshot(day: 1, cash: 10000, liabilities: 5000);
      final negative = _snapshot(day: 2, cash: 5000, liabilities: 10000);

      final change = resolveNetWorthTrend([positive, negative]).changes.single;

      expect(change.amountDeltaMinor, -10000);
      expect(change.percentageChange, isNull);
      expect(
        change.rateSuppressionReason,
        NetWorthRateSuppressionReason.negativeOrCrossZero,
      );
    });

    test('zero baseline also suppresses an infinite percentage', () {
      final zero = _snapshot(day: 1, cash: 5000, liabilities: 5000);
      final positive = _snapshot(day: 2, cash: 6000, liabilities: 5000);

      final change = resolveNetWorthTrend([zero, positive]).changes.single;

      expect(change.amountDeltaMinor, 1000);
      expect(change.percentageChange, isNull);
      expect(
        change.rateSuppressionReason,
        NetWorthRateSuppressionReason.zeroBaseline,
      );
    });
  });
}
