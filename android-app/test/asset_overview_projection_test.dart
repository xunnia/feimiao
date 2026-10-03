import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/account/net_worth_snapshot.dart';
import 'package:qingji/core/assets/asset_overview_projection.dart';

ComputedNetWorthSnapshot snapshot(DateTime date,
        {int cash = 10000,
        int physical = 5000,
        int liabilities = 2000,
        int scope = 1}) =>
    ComputedNetWorthSnapshot.fromEvaluation(
      requestedAsOf: date,
      evaluation: NetWorthAsOfEvaluation(
          asOf: date,
          components: NetWorthSnapshotComponents(
              cashAssetsMinor: cash,
              investmentAssetsMinor: 0,
              physicalAssetsMinor: physical,
              receivableAssetsMinor: 0,
              liabilitiesMinor: liabilities)),
      knowledgeCutoff: date,
      timezone: 'Asia/Shanghai',
      scopeVersion: scope,
      calculationVersion: 1,
      currencyCoverage: NetWorthCurrencyCoverage.single('CNY'),
      quality: NetWorthSnapshotQuality.available,
      provisional: false,
      causes: const [NetWorthSnapshotCause.valuation],
    );

void main() {
  final now = DateTime(2026, 10, 3);
  AssetOverviewProjection project(List<ComputedNetWorthSnapshot> points,
          {AssetTrendRange range = AssetTrendRange.all}) =>
      AssetOverviewProjection(
          source: resolveNetWorthTrend(points), range: range, now: now);
  test('metric components are mutually exclusive and conserve net worth', () {
    final c = snapshot(now).components;
    expect(AssetOverviewMetric.funds.minor(c), 10000);
    expect(AssetOverviewMetric.physical.minor(c), 5000);
    expect(AssetOverviewMetric.total.minor(c), 15000);
    expect(AssetOverviewMetric.netWorth.minor(c), 13000);
  });
  test('same window drives all five charts and excludes future dates', () {
    final points = [
      snapshot(DateTime(2025, 1, 1)),
      snapshot(DateTime(2026, 7, 5)),
      snapshot(now),
      snapshot(DateTime(2026, 10, 4))
    ];
    expect(project(points).trend.points.length, 3);
    expect(
        project(points, range: AssetTrendRange.quarter).trend.points.length, 2);
  });
  test('percentage rounds to one decimal with integer cents', () {
    final p =
        project([snapshot(DateTime(2026, 7, 1)), snapshot(now, cash: 12345)]);
    expect(p.delta(AssetOverviewMetric.funds, currentMinor: 12345), 2345);
    expect(
        p.percentage(AssetOverviewMetric.funds, currentMinor: 12345), '23.5%');
    expect(
        p.percentage(AssetOverviewMetric.physical, currentMinor: 5000), '0.0%');
  });
  test('negative and zero bases are unavailable, not false zero percent', () {
    for (final base in [-100, 0]) {
      final p =
          project([snapshot(DateTime(2026, 7, 1), cash: base), snapshot(now)]);
      expect(
          p.percentage(AssetOverviewMetric.funds, currentMinor: 10000), isNull);
    }
  });
  test('scope break does not produce a cross-scope percentage', () {
    final p = project([
      snapshot(DateTime(2026, 7, 1)),
      snapshot(DateTime(2026, 8, 1), scope: 2),
      snapshot(now, scope: 2)
    ]);
    expect(p.trend.hasTrend, isTrue);
    expect(p.trend.breaks, hasLength(1));
    expect(p.delta(AssetOverviewMetric.netWorth, currentMinor: 13000), isNull);
  });
  test('old snapshot cannot be labelled as current change', () {
    final p = project([snapshot(DateTime(2026, 7, 1)), snapshot(now)]);
    expect(p.delta(AssetOverviewMetric.funds, currentMinor: 20000), isNull);
  });
  test('zero or one snapshot keeps missing state', () {
    for (final points in [
      <ComputedNetWorthSnapshot>[],
      [snapshot(now)]
    ]) {
      final p = project(points);
      expect(p.trend.hasTrend, isFalse);
      expect(
          p.percentage(AssetOverviewMetric.funds, currentMinor: 10000), isNull);
    }
  });
}
