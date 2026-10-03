import '../account/net_worth_snapshot.dart';

enum AssetTrendRange {
  quarter(90, '近3个月'),
  year(365, '近1年'),
  all(0, '全部时间');

  const AssetTrendRange(this.days, this.label);
  final int days;
  final String label;
}

enum AssetOverviewMetric {
  netWorth('净资产'),
  funds('资金资产'),
  physical('计入物品'),
  total('总资产'),
  liabilities('总负债');

  const AssetOverviewMetric(this.label);
  final String label;

  int minor(NetWorthSnapshotComponents components) => switch (this) {
        netWorth => components.netWorthMinor,
        funds => components.cashAssetsMinor +
            components.investmentAssetsMinor +
            components.receivableAssetsMinor,
        physical => components.physicalAssetsMinor,
        total => components.totalAssetsMinor,
        liabilities => components.liabilitiesMinor,
      };
}

/// Read-only projection: all five charts share the same dates and scope breaks.
class AssetOverviewProjection {
  final NetWorthTrendResult trend;

  AssetOverviewProjection({
    required NetWorthTrendResult source,
    required AssetTrendRange range,
    required DateTime now,
  }) : trend = resolveNetWorthTrend(source.points.where((point) {
          final day = DateTime(now.year, now.month, now.day);
          final date = point.lineage.asOf;
          final civilDate = DateTime(date.year, date.month, date.day);
          return !civilDate.isAfter(day) &&
              (range.days == 0 ||
                  !civilDate.isBefore(
                      DateTime(now.year, now.month, now.day - range.days)));
        }));

  int? delta(AssetOverviewMetric metric, {required int currentMinor}) {
    if (trend.points.length < 2 || trend.segments.length != 1) return null;
    final segment = trend.segments.single;
    if (segment.points.length != trend.points.length ||
        metric.minor(segment.points.last.components) != currentMinor) {
      return null;
    }
    return currentMinor - metric.minor(segment.points.first.components);
  }

  // Integer arithmetic rounds to one decimal without floating money arithmetic.
  String? percentage(AssetOverviewMetric metric, {required int currentMinor}) {
    final change = delta(metric, currentMinor: currentMinor);
    if (change == null || currentMinor <= 0) return null;
    final base = metric.minor(trend.points.first.components);
    if (base <= 0) return null;
    final tenths = (change.abs() * 1000 + base ~/ 2) ~/ base;
    return '${tenths ~/ 10}.${tenths % 10}%';
  }
}
