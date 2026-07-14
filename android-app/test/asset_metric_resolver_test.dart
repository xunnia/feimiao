import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/assets/asset_metrics.dart';

PhysicalAssetMetricInput _input({
  Decimal? cost,
  Decimal? value,
  DateTime? purchasedAt,
  DateTime? endedAt,
  bool isOwned = true,
  bool hasKnownValuation = true,
  bool hasComparableCurrency = true,
  Decimal? additionalCost,
  bool usageTrackingEnabled = false,
  int usageCount = 0,
}) =>
    PhysicalAssetMetricInput(
      netAcquisitionCost: cost ?? Decimal.fromInt(1000),
      additionalNetCost: additionalCost ?? Decimal.zero,
      currentNetValue: value ?? Decimal.fromInt(600),
      purchasedAt: purchasedAt,
      endedAt: endedAt,
      isEconomicallyOwned: isOwned,
      hasKnownValuation: hasKnownValuation,
      hasComparableCurrency: hasComparableCurrency,
      usageTrackingEnabled: usageTrackingEnabled,
      usageCount: usageCount,
    );

void main() {
  group('physical asset held days', () {
    test('uses inclusive civil days instead of elapsed 24-hour blocks', () {
      final sameDay = resolvePhysicalAssetMetrics(
        _input(purchasedAt: DateTime(2026, 7, 13, 23, 59)),
        asOf: DateTime(2026, 7, 13, 23, 59, 30),
      );
      final acrossMidnight = resolvePhysicalAssetMetrics(
        _input(purchasedAt: DateTime(2026, 7, 12, 23, 59)),
        asOf: DateTime(2026, 7, 13, 0, 1),
      );

      expect(sameDay.heldDays.quality, AssetMetricQuality.exact);
      expect(sameDay.heldDays.value, 1);
      expect(acrossMidnight.heldDays.value, 2);
    });

    test('counts leap-day crossings by local calendar date', () {
      final result = resolvePhysicalAssetMetrics(
        _input(purchasedAt: DateTime(2024, 2, 28, 22)),
        asOf: DateTime(2024, 3, 1, 1),
      );

      expect(result.heldDays.value, 3);
    });

    test('owned items ignore archive time and keep accruing held days', () {
      final result = resolvePhysicalAssetMetrics(
        _input(
          purchasedAt: DateTime(2026, 7, 1),
          endedAt: DateTime(2026, 7, 5),
          isOwned: true,
        ),
        asOf: DateTime(2026, 7, 13),
      );

      expect(result.heldDays.value, 13);
    });

    test('terminal items stop on the terminal date, including same-day exit',
        () {
      final sameDay = resolvePhysicalAssetMetrics(
        _input(
          purchasedAt: DateTime(2026, 7, 13, 9),
          endedAt: DateTime(2026, 7, 13, 18),
          isOwned: false,
        ),
        asOf: DateTime(2026, 7, 20),
      );
      final laterExit = resolvePhysicalAssetMetrics(
        _input(
          purchasedAt: DateTime(2026, 7, 1),
          endedAt: DateTime(2026, 7, 5),
          isOwned: false,
        ),
        asOf: DateTime(2026, 7, 20),
      );

      expect(sameDay.heldDays.value, 1);
      expect(laterExit.heldDays.value, 5);
    });

    test('missing purchase date is unavailable, not a zero-day value', () {
      final result = resolvePhysicalAssetMetrics(
        _input(purchasedAt: null),
        asOf: DateTime(2026, 7, 13),
      );

      expect(result.heldDays.quality, AssetMetricQuality.unavailable);
      expect(result.heldDays.value, isNull);
      expect(result.dailyHoldingCost.quality, AssetMetricQuality.unavailable);
      expect(result.heldDays.reason, contains('购买日期'));
    });

    test('terminal date before purchase date is an explicit conflict', () {
      final result = resolvePhysicalAssetMetrics(
        _input(
          purchasedAt: DateTime(2026, 7, 10),
          endedAt: DateTime(2026, 7, 9),
          isOwned: false,
        ),
        asOf: DateTime(2026, 7, 13),
      );

      expect(result.heldDays.quality, AssetMetricQuality.conflict);
      expect(result.heldDays.value, isNull);
      expect(result.dailyHoldingCost.quality, AssetMetricQuality.conflict);
    });
  });

  group('physical asset cost and retention metrics', () {
    test('daily cost uses acquisition plus additional net expenses', () {
      final result = resolvePhysicalAssetMetrics(
        _input(
          cost: Decimal.fromInt(900),
          additionalCost: Decimal.fromInt(100),
          purchasedAt: DateTime(2026, 7, 11),
        ),
        asOf: DateTime(2026, 7, 13),
      );

      expect(
        result.cumulativeHoldingInvestment.value,
        Decimal.fromInt(1000),
      );
      expect(result.dailyHoldingCost.value, Decimal.parse('333.33333333'));
      expect(result.valueRetentionRatio.value, Decimal.parse('0.66666666'));
    });

    test('per-use cost requires opt-in and a positive usage count', () {
      final disabled = resolvePhysicalAssetMetrics(
        _input(
          purchasedAt: DateTime(2026, 7, 1),
          usageCount: 4,
        ),
      );
      final empty = resolvePhysicalAssetMetrics(
        _input(
          purchasedAt: DateTime(2026, 7, 1),
          usageTrackingEnabled: true,
        ),
      );
      final enabled = resolvePhysicalAssetMetrics(
        _input(
          cost: Decimal.fromInt(900),
          additionalCost: Decimal.fromInt(100),
          purchasedAt: DateTime(2026, 7, 1),
          usageTrackingEnabled: true,
          usageCount: 4,
        ),
      );

      expect(
          disabled.perUseHoldingCost.quality, AssetMetricQuality.unavailable);
      expect(empty.perUseHoldingCost.quality, AssetMetricQuality.unavailable);
      expect(enabled.perUseHoldingCost.value, Decimal.fromInt(250));
    });

    test('negative component or usage count is an explicit conflict', () {
      final negativeCost = resolvePhysicalAssetMetrics(
        _input(
          additionalCost: Decimal.fromInt(-1),
          purchasedAt: DateTime(2026, 7, 1),
          usageTrackingEnabled: true,
          usageCount: 1,
        ),
      );
      final negativeUsage = resolvePhysicalAssetMetrics(
        _input(
          purchasedAt: DateTime(2026, 7, 1),
          usageTrackingEnabled: true,
          usageCount: -1,
        ),
      );

      expect(
        negativeCost.cumulativeHoldingInvestment.quality,
        AssetMetricQuality.conflict,
      );
      expect(
          negativeCost.dailyHoldingCost.quality, AssetMetricQuality.conflict);
      expect(
          negativeCost.perUseHoldingCost.quality, AssetMetricQuality.conflict);
      expect(
          negativeUsage.perUseHoldingCost.quality, AssetMetricQuality.conflict);
    });

    test('daily holding cost keeps deterministic decimal precision', () {
      final result = resolvePhysicalAssetMetrics(
        _input(
          cost: Decimal.fromInt(1000),
          purchasedAt: DateTime(2026, 7, 11),
        ),
        asOf: DateTime(2026, 7, 13),
      );

      expect(result.dailyHoldingCost.quality, AssetMetricQuality.exact);
      expect(result.dailyHoldingCost.value, Decimal.parse('333.33333333'));
    });

    test('zero acquisition cost has a real zero daily value but no ratio', () {
      final result = resolvePhysicalAssetMetrics(
        _input(
          cost: Decimal.zero,
          value: Decimal.zero,
          purchasedAt: DateTime(2026, 7, 1),
        ),
        asOf: DateTime(2026, 7, 10),
      );

      expect(result.dailyHoldingCost.value, Decimal.zero);
      expect(
        result.valueRetentionRatio.quality,
        AssetMetricQuality.unavailable,
      );
      expect(result.valueRetentionRatio.value, isNull);
    });

    test('retention ratio distinguishes exact zero from unknown valuation', () {
      final exact = resolvePhysicalAssetMetrics(
        _input(
          cost: Decimal.fromInt(1000),
          value: Decimal.fromInt(600),
          purchasedAt: DateTime(2026, 7, 1),
        ),
        asOf: DateTime(2026, 7, 13),
      );
      final exactZero = resolvePhysicalAssetMetrics(
        _input(
          cost: Decimal.fromInt(1000),
          value: Decimal.zero,
          purchasedAt: DateTime(2026, 7, 1),
        ),
        asOf: DateTime(2026, 7, 13),
      );
      final unknown = resolvePhysicalAssetMetrics(
        _input(
          purchasedAt: DateTime(2026, 7, 1),
          hasKnownValuation: false,
        ),
        asOf: DateTime(2026, 7, 13),
      );

      expect(exact.valueRetentionRatio.value, Decimal.parse('0.6'));
      expect(exactZero.valueRetentionRatio.quality, AssetMetricQuality.exact);
      expect(exactZero.valueRetentionRatio.value, Decimal.zero);
      expect(
        unknown.valueRetentionRatio.quality,
        AssetMetricQuality.unavailable,
      );
      expect(unknown.valueRetentionRatio.value, isNull);
    });

    test('currency mismatch and negative valuation never produce a ratio', () {
      final currencyUnknown = resolvePhysicalAssetMetrics(
        _input(
          purchasedAt: DateTime(2026, 7, 1),
          hasComparableCurrency: false,
        ),
        asOf: DateTime(2026, 7, 13),
      );
      final invalidValue = resolvePhysicalAssetMetrics(
        _input(
          value: Decimal.fromInt(-1),
          purchasedAt: DateTime(2026, 7, 1),
        ),
        asOf: DateTime(2026, 7, 13),
      );

      expect(
        currencyUnknown.valueRetentionRatio.quality,
        AssetMetricQuality.unavailable,
      );
      expect(
        invalidValue.valueRetentionRatio.quality,
        AssetMetricQuality.conflict,
      );
    });
  });

  group('asset valuation trend', () {
    test('sorts by effective date and excludes future points', () {
      final result = resolveAssetValuationTrend(
        [
          AssetValuationPoint(
            value: Decimal.fromInt(800),
            effectiveAt: DateTime(2026, 6, 1),
          ),
          AssetValuationPoint(
            value: Decimal.fromInt(1000),
            effectiveAt: DateTime(2026, 1, 1),
          ),
          AssetValuationPoint(
            value: Decimal.fromInt(700),
            effectiveAt: DateTime(2026, 8, 1),
          ),
        ],
        asOf: DateTime(2026, 7, 13),
      );

      expect(result.points.map((point) => point.value), [
        Decimal.fromInt(1000),
        Decimal.fromInt(800),
      ]);
      expect(result.ignoredFutureCount, 1);
    });

    test('backfilled old valuation cannot replace the latest effective value',
        () {
      final result = resolveAssetValuationTrend(
        [
          AssetValuationPoint(
            value: Decimal.fromInt(900),
            effectiveAt: DateTime(2026, 6, 1),
          ),
          AssetValuationPoint(
            value: Decimal.fromInt(700),
            effectiveAt: DateTime(2026, 3, 1),
          ),
        ],
        asOf: DateTime(2026, 7, 13),
      );

      expect(result.points.last.value, Decimal.fromInt(900));
      expect(result.points.last.effectiveAt, DateTime(2026, 6, 1));
    });

    test('terminal point wins at the same instant and blocks later revival',
        () {
      final endedAt = DateTime(2026, 6, 15);
      final result = resolveAssetValuationTrend(
        [
          AssetValuationPoint(
            value: Decimal.fromInt(800),
            effectiveAt: DateTime(2026, 6, 1),
          ),
          AssetValuationPoint(
            value: Decimal.fromInt(500),
            effectiveAt: endedAt,
          ),
          AssetValuationPoint(
            value: Decimal.zero,
            effectiveAt: endedAt,
            isTermination: true,
          ),
          AssetValuationPoint(
            value: Decimal.fromInt(900),
            effectiveAt: DateTime(2026, 6, 20),
          ),
        ],
        asOf: DateTime(2026, 7, 13),
        endedAt: endedAt,
      );

      expect(result.points.last.isTermination, isTrue);
      expect(result.points.last.value, Decimal.zero);
      expect(result.ignoredAfterTerminationCount, 1);
      expect(
        result.points.any((point) => point.value == Decimal.fromInt(900)),
        isFalse,
      );
    });
  });
}
