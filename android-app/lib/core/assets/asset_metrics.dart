import 'package:decimal/decimal.dart';

enum AssetMetricQuality {
  exact,
  unavailable,
  conflict,
}

class AssetMetricValue<T> {
  final AssetMetricQuality quality;
  final T? value;
  final String reason;

  const AssetMetricValue._({
    required this.quality,
    this.value,
    this.reason = '',
  });

  const AssetMetricValue.exact(T value)
      : this._(quality: AssetMetricQuality.exact, value: value);

  const AssetMetricValue.unavailable(String reason)
      : this._(
          quality: AssetMetricQuality.unavailable,
          reason: reason,
        );

  const AssetMetricValue.conflict(String reason)
      : this._(
          quality: AssetMetricQuality.conflict,
          reason: reason,
        );

  bool get isExact => quality == AssetMetricQuality.exact;
}

class PhysicalAssetMetricInput {
  final Decimal netAcquisitionCost;
  final Decimal additionalNetCost;
  final Decimal currentNetValue;
  final DateTime? purchasedAt;
  final DateTime? endedAt;
  final bool isEconomicallyOwned;
  final bool hasKnownValuation;
  final bool hasComparableCurrency;
  final bool usageTrackingEnabled;
  final int usageCount;

  PhysicalAssetMetricInput({
    required this.netAcquisitionCost,
    Decimal? additionalNetCost,
    required this.currentNetValue,
    required this.purchasedAt,
    required this.endedAt,
    required this.isEconomicallyOwned,
    required this.hasKnownValuation,
    this.hasComparableCurrency = true,
    this.usageTrackingEnabled = false,
    this.usageCount = 0,
  }) : additionalNetCost = additionalNetCost ?? Decimal.zero;
}

class PhysicalAssetMetrics {
  final AssetMetricValue<int> heldDays;
  final AssetMetricValue<Decimal> cumulativeHoldingInvestment;
  final AssetMetricValue<Decimal> dailyHoldingCost;
  final AssetMetricValue<Decimal> perUseHoldingCost;
  final AssetMetricValue<Decimal> valueRetentionRatio;

  const PhysicalAssetMetrics({
    required this.heldDays,
    required this.cumulativeHoldingInvestment,
    required this.dailyHoldingCost,
    required this.perUseHoldingCost,
    required this.valueRetentionRatio,
  });
}

class AssetValuationPoint {
  final Decimal value;
  final DateTime effectiveAt;
  final bool isTermination;

  const AssetValuationPoint({
    required this.value,
    required this.effectiveAt,
    this.isTermination = false,
  });
}

class AssetValuationTrend {
  final List<AssetValuationPoint> points;
  final int ignoredFutureCount;
  final int ignoredAfterTerminationCount;

  const AssetValuationTrend({
    required this.points,
    required this.ignoredFutureCount,
    required this.ignoredAfterTerminationCount,
  });
}

PhysicalAssetMetrics resolvePhysicalAssetMetrics(
  PhysicalAssetMetricInput input, {
  DateTime? asOf,
}) {
  final now = asOf ?? DateTime.now();
  final heldDays = _heldDays(
    purchasedAt: input.purchasedAt,
    endedAt: input.isEconomicallyOwned ? null : input.endedAt,
    asOf: now,
  );

  late final AssetMetricValue<Decimal> cumulativeHoldingInvestment;
  if (!input.hasComparableCurrency) {
    cumulativeHoldingInvestment = const AssetMetricValue.unavailable('币种暂不可折算');
  } else if (input.netAcquisitionCost < Decimal.zero) {
    cumulativeHoldingInvestment = const AssetMetricValue.conflict('净购置成本不能为负');
  } else if (input.additionalNetCost < Decimal.zero) {
    cumulativeHoldingInvestment = const AssetMetricValue.conflict('附加净支出不能为负');
  } else {
    cumulativeHoldingInvestment = AssetMetricValue.exact(
      input.netAcquisitionCost + input.additionalNetCost,
    );
  }

  final dailyHoldingCost = _divideMetric(
    cumulativeHoldingInvestment,
    heldDays,
  );

  late final AssetMetricValue<Decimal> perUseHoldingCost;
  if (!input.usageTrackingEnabled) {
    perUseHoldingCost = const AssetMetricValue.unavailable('未开启使用次数');
  } else if (input.usageCount < 0) {
    perUseHoldingCost = const AssetMetricValue.conflict('使用次数不能为负');
  } else if (input.usageCount == 0) {
    perUseHoldingCost = const AssetMetricValue.unavailable('尚无使用记录');
  } else {
    perUseHoldingCost = _divideDecimalMetric(
      cumulativeHoldingInvestment,
      input.usageCount,
    );
  }

  late final AssetMetricValue<Decimal> valueRetentionRatio;
  if (!input.isEconomicallyOwned) {
    valueRetentionRatio = const AssetMetricValue.unavailable('物品已结束持有');
  } else if (!input.hasComparableCurrency) {
    valueRetentionRatio = const AssetMetricValue.unavailable('币种暂不可折算');
  } else if (!input.hasKnownValuation) {
    valueRetentionRatio = const AssetMetricValue.unavailable('当前估值未知');
  } else if (input.netAcquisitionCost <= Decimal.zero) {
    valueRetentionRatio = const AssetMetricValue.unavailable('净购置成本需大于 0');
  } else if (input.currentNetValue < Decimal.zero) {
    valueRetentionRatio = const AssetMetricValue.conflict('当前估值不能为负');
  } else {
    valueRetentionRatio = AssetMetricValue.exact(
      (input.currentNetValue / input.netAcquisitionCost)
          .toDecimal(scaleOnInfinitePrecision: 8),
    );
  }

  return PhysicalAssetMetrics(
    heldDays: heldDays,
    cumulativeHoldingInvestment: cumulativeHoldingInvestment,
    dailyHoldingCost: dailyHoldingCost,
    perUseHoldingCost: perUseHoldingCost,
    valueRetentionRatio: valueRetentionRatio,
  );
}

AssetMetricValue<Decimal> _divideMetric(
  AssetMetricValue<Decimal> numerator,
  AssetMetricValue<int> denominator,
) {
  if (numerator.quality == AssetMetricQuality.conflict) {
    return AssetMetricValue.conflict(numerator.reason);
  }
  if (denominator.quality == AssetMetricQuality.conflict) {
    return AssetMetricValue.conflict(denominator.reason);
  }
  if (numerator.quality == AssetMetricQuality.unavailable) {
    return AssetMetricValue.unavailable(numerator.reason);
  }
  if (denominator.quality == AssetMetricQuality.unavailable) {
    return AssetMetricValue.unavailable(denominator.reason);
  }
  return _divideDecimalMetric(numerator, denominator.value!);
}

AssetMetricValue<Decimal> _divideDecimalMetric(
  AssetMetricValue<Decimal> numerator,
  int denominator,
) {
  if (numerator.quality == AssetMetricQuality.conflict) {
    return AssetMetricValue.conflict(numerator.reason);
  }
  if (numerator.quality == AssetMetricQuality.unavailable) {
    return AssetMetricValue.unavailable(numerator.reason);
  }
  return AssetMetricValue.exact(
    (numerator.value! / Decimal.fromInt(denominator))
        .toDecimal(scaleOnInfinitePrecision: 8),
  );
}

AssetValuationTrend resolveAssetValuationTrend(
  Iterable<AssetValuationPoint> source, {
  DateTime? asOf,
  DateTime? endedAt,
}) {
  final cutoff = asOf ?? DateTime.now();
  var ignoredFutureCount = 0;
  var ignoredAfterTerminationCount = 0;
  final accepted = <AssetValuationPoint>[];

  for (final point in source) {
    if (point.effectiveAt.isAfter(cutoff)) {
      ignoredFutureCount++;
      continue;
    }
    if (endedAt != null &&
        point.effectiveAt.isAfter(endedAt) &&
        !point.isTermination) {
      ignoredAfterTerminationCount++;
      continue;
    }
    accepted.add(point);
  }

  accepted.sort((a, b) {
    final time = a.effectiveAt.compareTo(b.effectiveAt);
    if (time != 0) return time;
    if (a.isTermination == b.isTermination) return 0;
    return a.isTermination ? 1 : -1;
  });

  return AssetValuationTrend(
    points: List.unmodifiable(accepted),
    ignoredFutureCount: ignoredFutureCount,
    ignoredAfterTerminationCount: ignoredAfterTerminationCount,
  );
}

AssetMetricValue<int> _heldDays({
  required DateTime? purchasedAt,
  required DateTime? endedAt,
  required DateTime asOf,
}) {
  if (purchasedAt == null) {
    return const AssetMetricValue.unavailable('购买日期未知');
  }

  final start = _calendarDay(purchasedAt);
  final end = _calendarDay(endedAt ?? asOf);
  if (end.isBefore(start)) {
    return const AssetMetricValue.conflict('结束日期早于购买日期');
  }
  return AssetMetricValue.exact(end.difference(start).inDays + 1);
}

DateTime _calendarDay(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
