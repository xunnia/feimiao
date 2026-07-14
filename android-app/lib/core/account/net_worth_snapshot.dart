enum NetWorthSnapshotQuality {
  available,
  partial,
  stale,
  legacyUnverified,
  conflict,
}

extension NetWorthSnapshotQualityX on NetWorthSnapshotQuality {
  String get storageKey => switch (this) {
        NetWorthSnapshotQuality.available => 'available',
        NetWorthSnapshotQuality.partial => 'partial',
        NetWorthSnapshotQuality.stale => 'stale',
        NetWorthSnapshotQuality.legacyUnverified => 'legacy_unverified',
        NetWorthSnapshotQuality.conflict => 'conflict',
      };

  static NetWorthSnapshotQuality fromStorage(String? value) {
    for (final quality in NetWorthSnapshotQuality.values) {
      if (quality.storageKey == value) return quality;
    }
    // Unknown old rows must never silently become comparable.
    return NetWorthSnapshotQuality.legacyUnverified;
  }

  bool get isEligibleForEstimatedTrend =>
      this == NetWorthSnapshotQuality.available ||
      this == NetWorthSnapshotQuality.partial;
}

enum NetWorthSnapshotCause {
  transaction,
  refund,
  transfer,
  account,
  calibration,
  valuation,
  physicalAsset,
  receivable,
  liability,
  scope,
  historicalBackfill,
  migration,
  scheduledRebuild,
  other,
}

extension NetWorthSnapshotCauseX on NetWorthSnapshotCause {
  String get storageKey => switch (this) {
        NetWorthSnapshotCause.transaction => 'transaction',
        NetWorthSnapshotCause.refund => 'refund',
        NetWorthSnapshotCause.transfer => 'transfer',
        NetWorthSnapshotCause.account => 'account',
        NetWorthSnapshotCause.calibration => 'calibration',
        NetWorthSnapshotCause.valuation => 'valuation',
        NetWorthSnapshotCause.physicalAsset => 'physical_asset',
        NetWorthSnapshotCause.receivable => 'receivable',
        NetWorthSnapshotCause.liability => 'liability',
        NetWorthSnapshotCause.scope => 'scope',
        NetWorthSnapshotCause.historicalBackfill => 'historical_backfill',
        NetWorthSnapshotCause.migration => 'migration',
        NetWorthSnapshotCause.scheduledRebuild => 'scheduled_rebuild',
        NetWorthSnapshotCause.other => 'other',
      };

  static NetWorthSnapshotCause fromStorage(String? value) {
    for (final cause in NetWorthSnapshotCause.values) {
      if (cause.storageKey == value) return cause;
    }
    return NetWorthSnapshotCause.other;
  }
}

class NetWorthSnapshotReason {
  final String code;
  final String message;
  final Map<String, Object?> details;

  NetWorthSnapshotReason({
    required String code,
    required this.message,
    Map<String, Object?> details = const {},
  })  : code = code.trim(),
        details = Map.unmodifiable(Map<String, Object?>.of(details)) {
    if (this.code.isEmpty) {
      throw ArgumentError.value(code, 'code', 'must not be empty');
    }
  }

  Map<String, Object?> toJson() => {
        'code': code,
        'message': message,
        if (details.isNotEmpty) 'details': details,
      };
}

class NetWorthCurrencyCoverage {
  final String baseCurrency;
  final List<String> coveredCurrencies;
  final List<String> uncoveredCurrencies;

  NetWorthCurrencyCoverage({
    required String baseCurrency,
    required Iterable<String> coveredCurrencies,
    Iterable<String> uncoveredCurrencies = const [],
  })  : baseCurrency = _currency(baseCurrency),
        coveredCurrencies = List.unmodifiable(_currencies(coveredCurrencies)),
        uncoveredCurrencies =
            List.unmodifiable(_currencies(uncoveredCurrencies)) {
    if (this.baseCurrency.isEmpty) {
      throw ArgumentError.value(baseCurrency, 'baseCurrency', 'is invalid');
    }
    if (!this.coveredCurrencies.contains(this.baseCurrency)) {
      throw ArgumentError('The base currency must be covered.');
    }
    if (this
        .coveredCurrencies
        .any((currency) => this.uncoveredCurrencies.contains(currency))) {
      throw ArgumentError('Covered and uncovered currencies must be disjoint.');
    }
  }

  factory NetWorthCurrencyCoverage.single(String currency) =>
      NetWorthCurrencyCoverage(
        baseCurrency: currency,
        coveredCurrencies: [currency],
      );

  bool get isComplete => uncoveredCurrencies.isEmpty;

  Map<String, Object?> toJson() => {
        'base_currency': baseCurrency,
        'covered': coveredCurrencies,
        'uncovered': uncoveredCurrencies,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetWorthCurrencyCoverage &&
          baseCurrency == other.baseCurrency &&
          _listEquals(coveredCurrencies, other.coveredCurrencies) &&
          _listEquals(uncoveredCurrencies, other.uncoveredCurrencies);

  @override
  int get hashCode => Object.hash(
        baseCurrency,
        Object.hashAll(coveredCurrencies),
        Object.hashAll(uncoveredCurrencies),
      );
}

class NetWorthValuationCoverage {
  final int missingValuationCount;
  final int staleValuationCount;

  const NetWorthValuationCoverage({
    this.missingValuationCount = 0,
    this.staleValuationCount = 0,
  })  : assert(missingValuationCount >= 0),
        assert(staleValuationCount >= 0);

  Map<String, Object?> toJson() => {
        'missing_count': missingValuationCount,
        'stale_count': staleValuationCount,
      };
}

/// Mutually exclusive components. Liabilities are stored as a positive amount
/// and subtracted from assets when calculating net worth.
class NetWorthSnapshotComponents {
  final int cashAssetsMinor;
  final int investmentAssetsMinor;
  final int physicalAssetsMinor;
  final int receivableAssetsMinor;
  final int liabilitiesMinor;

  const NetWorthSnapshotComponents({
    required this.cashAssetsMinor,
    required this.investmentAssetsMinor,
    required this.physicalAssetsMinor,
    required this.receivableAssetsMinor,
    required this.liabilitiesMinor,
  });

  int get totalAssetsMinor =>
      cashAssetsMinor +
      investmentAssetsMinor +
      physicalAssetsMinor +
      receivableAssetsMinor;

  int get netWorthMinor => totalAssetsMinor - liabilitiesMinor;

  Map<String, Object?> toJson() => {
        'cash_assets_minor': cashAssetsMinor,
        'investment_assets_minor': investmentAssetsMinor,
        'physical_assets_minor': physicalAssetsMinor,
        'receivable_assets_minor': receivableAssetsMinor,
        'liabilities_minor': liabilitiesMinor,
        'total_assets_minor': totalAssetsMinor,
        'net_worth_minor': netWorthMinor,
      };
}

/// The result of an actual as-of projection. A repository adapter for today's
/// current breakdown must set [asOf] to today; it therefore cannot be relabeled
/// as a historical value by [ComputedNetWorthSnapshot.fromEvaluation].
class NetWorthAsOfEvaluation {
  final DateTime asOf;
  final NetWorthSnapshotComponents components;
  final NetWorthValuationCoverage valuationCoverage;

  NetWorthAsOfEvaluation({
    required DateTime asOf,
    required this.components,
    this.valuationCoverage = const NetWorthValuationCoverage(),
  }) : asOf = _civilDay(asOf);
}

class NetWorthSnapshotLineage {
  final DateTime asOf;
  final DateTime knowledgeCutoff;
  final String timezone;
  final String scopeKey;
  final int scopeVersion;
  final int calculationVersion;
  final NetWorthCurrencyCoverage currencyCoverage;
  final NetWorthSnapshotQuality quality;
  final List<NetWorthSnapshotReason> reasons;
  final bool provisional;
  final Set<NetWorthSnapshotCause> causes;

  NetWorthSnapshotLineage({
    required DateTime asOf,
    required DateTime knowledgeCutoff,
    required String timezone,
    required String scopeKey,
    required this.scopeVersion,
    required this.calculationVersion,
    required this.currencyCoverage,
    required this.quality,
    Iterable<NetWorthSnapshotReason> reasons = const [],
    required this.provisional,
    required Iterable<NetWorthSnapshotCause> causes,
  })  : asOf = _civilDay(asOf),
        knowledgeCutoff = knowledgeCutoff.toUtc(),
        timezone = timezone.trim(),
        scopeKey = scopeKey.trim(),
        reasons = List.unmodifiable(reasons),
        causes = Set.unmodifiable(Set<NetWorthSnapshotCause>.of(causes)) {
    if (this.timezone.isEmpty) {
      throw ArgumentError.value(timezone, 'timezone', 'must not be empty');
    }
    if (this.scopeKey.isEmpty) {
      throw ArgumentError.value(scopeKey, 'scopeKey', 'must not be empty');
    }
    if (scopeVersion < 1 || calculationVersion < 1) {
      throw ArgumentError('Scope and calculation versions must be positive.');
    }
    if (this.causes.isEmpty) {
      throw ArgumentError('A computed snapshot requires at least one cause.');
    }
    if (quality != NetWorthSnapshotQuality.available && this.reasons.isEmpty) {
      throw ArgumentError('$quality requires at least one quality reason.');
    }
  }

  bool get isEligibleForEstimatedTrend => quality.isEligibleForEstimatedTrend;

  NetWorthSnapshotLineage copyWith({
    DateTime? knowledgeCutoff,
    Set<NetWorthSnapshotCause>? causes,
  }) =>
      NetWorthSnapshotLineage(
        asOf: asOf,
        knowledgeCutoff: knowledgeCutoff ?? this.knowledgeCutoff,
        timezone: timezone,
        scopeKey: scopeKey,
        scopeVersion: scopeVersion,
        calculationVersion: calculationVersion,
        currencyCoverage: currencyCoverage,
        quality: quality,
        reasons: reasons,
        provisional: provisional,
        causes: causes ?? this.causes,
      );

  Map<String, Object?> toJson() => {
        'as_of': _dateKey(asOf),
        'knowledge_cutoff_ms': knowledgeCutoff.millisecondsSinceEpoch,
        'timezone': timezone,
        'scope_key': scopeKey,
        'scope_version': scopeVersion,
        'calculation_version': calculationVersion,
        'currency_coverage': currencyCoverage.toJson(),
        'quality': quality.storageKey,
        'reasons': reasons.map((reason) => reason.toJson()).toList(),
        'provisional': provisional,
        'causes': causes.map((cause) => cause.storageKey).toList()..sort(),
      };
}

class ComputedNetWorthSnapshot {
  final NetWorthSnapshotLineage lineage;
  final NetWorthSnapshotComponents components;
  final NetWorthValuationCoverage valuationCoverage;

  const ComputedNetWorthSnapshot._({
    required this.lineage,
    required this.components,
    required this.valuationCoverage,
  });

  factory ComputedNetWorthSnapshot.fromEvaluation({
    required DateTime requestedAsOf,
    required NetWorthAsOfEvaluation evaluation,
    required DateTime knowledgeCutoff,
    required String timezone,
    String scopeKey = 'global',
    required int scopeVersion,
    required int calculationVersion,
    required NetWorthCurrencyCoverage currencyCoverage,
    required NetWorthSnapshotQuality quality,
    Iterable<NetWorthSnapshotReason> reasons = const [],
    required bool provisional,
    required Iterable<NetWorthSnapshotCause> causes,
  }) {
    final requestedDay = _civilDay(requestedAsOf);
    if (requestedDay != evaluation.asOf) {
      throw StateError(
        'The requested as-of date must match the date actually evaluated. '
        'Current values cannot be relabeled as a historical snapshot.',
      );
    }
    if (quality == NetWorthSnapshotQuality.available &&
        (evaluation.valuationCoverage.missingValuationCount > 0 ||
            !currencyCoverage.isComplete)) {
      throw ArgumentError(
        'Missing valuations or currencies require partial snapshot quality.',
      );
    }
    return ComputedNetWorthSnapshot._(
      lineage: NetWorthSnapshotLineage(
        asOf: evaluation.asOf,
        knowledgeCutoff: knowledgeCutoff,
        timezone: timezone,
        scopeKey: scopeKey,
        scopeVersion: scopeVersion,
        calculationVersion: calculationVersion,
        currencyCoverage: currencyCoverage,
        quality: quality,
        reasons: reasons,
        provisional: provisional,
        causes: causes,
      ),
      components: evaluation.components,
      valuationCoverage: evaluation.valuationCoverage,
    );
  }

  /// Rehydrates already persisted evidence. New calculations should always use
  /// [fromEvaluation], which guards requested and evaluated as-of dates.
  factory ComputedNetWorthSnapshot.rehydrate({
    required NetWorthSnapshotLineage lineage,
    required NetWorthSnapshotComponents components,
    required NetWorthValuationCoverage valuationCoverage,
  }) =>
      ComputedNetWorthSnapshot._(
        lineage: lineage,
        components: components,
        valuationCoverage: valuationCoverage,
      );

  int get netWorthMinor => components.netWorthMinor;
  bool get isEligibleForEstimatedTrend => lineage.isEligibleForEstimatedTrend;

  Map<String, Object?> toJson() => {
        ...lineage.toJson(),
        ...components.toJson(),
        'valuation_coverage': valuationCoverage.toJson(),
      };

  ComputedNetWorthSnapshot _withLineage(NetWorthSnapshotLineage next) =>
      ComputedNetWorthSnapshot._(
        lineage: next,
        components: components,
        valuationCoverage: valuationCoverage,
      );
}

/// Keeps the newest same-day calculation while preserving every trigger that
/// was coalesced into the day's single computed snapshot.
ComputedNetWorthSnapshot mergeSameDayComputedSnapshots(
  ComputedNetWorthSnapshot first,
  ComputedNetWorthSnapshot second,
) {
  if (first.lineage.scopeKey != second.lineage.scopeKey ||
      first.lineage.asOf != second.lineage.asOf) {
    throw ArgumentError('Only same-scope, same-day snapshots can be merged.');
  }
  final winner =
      second.lineage.knowledgeCutoff.isBefore(first.lineage.knowledgeCutoff)
          ? first
          : second;
  final causes = <NetWorthSnapshotCause>{
    ...first.lineage.causes,
    ...second.lineage.causes,
  };
  return winner._withLineage(winner.lineage.copyWith(causes: causes));
}

enum NetWorthComparabilityIssue {
  nonIncreasingAsOf,
  ineligibleQuality,
  scopeKeyMismatch,
  timezoneMismatch,
  scopeVersionMismatch,
  calculationVersionMismatch,
  currencyCoverageMismatch,
}

class NetWorthSnapshotComparability {
  final List<NetWorthComparabilityIssue> issues;

  NetWorthSnapshotComparability(Iterable<NetWorthComparabilityIssue> issues)
      : issues = List.unmodifiable(issues);

  bool get isComparable => issues.isEmpty;
}

NetWorthSnapshotComparability compareComputedNetWorthSnapshots(
  ComputedNetWorthSnapshot earlier,
  ComputedNetWorthSnapshot later,
) {
  final issues = <NetWorthComparabilityIssue>[];
  if (!earlier.lineage.asOf.isBefore(later.lineage.asOf)) {
    issues.add(NetWorthComparabilityIssue.nonIncreasingAsOf);
  }
  if (!earlier.isEligibleForEstimatedTrend ||
      !later.isEligibleForEstimatedTrend) {
    issues.add(NetWorthComparabilityIssue.ineligibleQuality);
  }
  if (earlier.lineage.scopeKey != later.lineage.scopeKey) {
    issues.add(NetWorthComparabilityIssue.scopeKeyMismatch);
  }
  if (earlier.lineage.timezone != later.lineage.timezone) {
    issues.add(NetWorthComparabilityIssue.timezoneMismatch);
  }
  if (earlier.lineage.scopeVersion != later.lineage.scopeVersion) {
    issues.add(NetWorthComparabilityIssue.scopeVersionMismatch);
  }
  if (earlier.lineage.calculationVersion != later.lineage.calculationVersion) {
    issues.add(NetWorthComparabilityIssue.calculationVersionMismatch);
  }
  if (earlier.lineage.currencyCoverage != later.lineage.currencyCoverage) {
    issues.add(NetWorthComparabilityIssue.currencyCoverageMismatch);
  }
  return NetWorthSnapshotComparability(issues);
}

enum NetWorthChangeComponent {
  cashAssets,
  investmentAssets,
  physicalAssets,
  receivableAssets,
  liabilities,
}

class NetWorthComponentChange {
  final NetWorthChangeComponent component;
  final int rawDeltaMinor;
  final int netWorthContributionMinor;

  const NetWorthComponentChange({
    required this.component,
    required this.rawDeltaMinor,
    required this.netWorthContributionMinor,
  });
}

enum NetWorthChangeCauseGroup {
  accountEvents,
  valuationChanges,
  liabilityEvents,
  calibrationOrBackfill,
  scopeOrMigration,
  accountConfiguration,
  recalculation,
  other,
}

class NetWorthCauseSummary {
  final NetWorthChangeCauseGroup group;
  final Set<NetWorthSnapshotCause> causes;

  NetWorthCauseSummary({
    required this.group,
    required Iterable<NetWorthSnapshotCause> causes,
  }) : causes = Set.unmodifiable(Set<NetWorthSnapshotCause>.of(causes));
}

enum NetWorthRateSuppressionReason {
  zeroBaseline,
  negativeOrCrossZero,
}

class NetWorthSnapshotChange {
  final ComputedNetWorthSnapshot earlier;
  final ComputedNetWorthSnapshot later;
  final int amountDeltaMinor;
  final double? percentageChange;
  final NetWorthRateSuppressionReason? rateSuppressionReason;
  final List<NetWorthComponentChange> componentChanges;
  final List<NetWorthCauseSummary> causeSummaries;

  NetWorthSnapshotChange._({
    required this.earlier,
    required this.later,
    required this.amountDeltaMinor,
    required this.percentageChange,
    required this.rateSuppressionReason,
    required Iterable<NetWorthComponentChange> componentChanges,
    required Iterable<NetWorthCauseSummary> causeSummaries,
  })  : componentChanges = List.unmodifiable(componentChanges),
        causeSummaries = List.unmodifiable(causeSummaries);
}

NetWorthSnapshotChange _changeBetween(
  ComputedNetWorthSnapshot earlier,
  ComputedNetWorthSnapshot later,
) {
  final before = earlier.components;
  final after = later.components;
  final componentChanges = <NetWorthComponentChange>[
    _componentChange(
      NetWorthChangeComponent.cashAssets,
      before.cashAssetsMinor,
      after.cashAssetsMinor,
    ),
    _componentChange(
      NetWorthChangeComponent.investmentAssets,
      before.investmentAssetsMinor,
      after.investmentAssetsMinor,
    ),
    _componentChange(
      NetWorthChangeComponent.physicalAssets,
      before.physicalAssetsMinor,
      after.physicalAssetsMinor,
    ),
    _componentChange(
      NetWorthChangeComponent.receivableAssets,
      before.receivableAssetsMinor,
      after.receivableAssetsMinor,
    ),
    _componentChange(
      NetWorthChangeComponent.liabilities,
      before.liabilitiesMinor,
      after.liabilitiesMinor,
      subtractFromNetWorth: true,
    ),
  ];
  final delta = later.netWorthMinor - earlier.netWorthMinor;
  double? percentage;
  NetWorthRateSuppressionReason? suppression;
  if (earlier.netWorthMinor == 0) {
    suppression = NetWorthRateSuppressionReason.zeroBaseline;
  } else if (earlier.netWorthMinor < 0 || later.netWorthMinor <= 0) {
    suppression = NetWorthRateSuppressionReason.negativeOrCrossZero;
  } else {
    percentage = delta / earlier.netWorthMinor;
  }
  return NetWorthSnapshotChange._(
    earlier: earlier,
    later: later,
    amountDeltaMinor: delta,
    percentageChange: percentage,
    rateSuppressionReason: suppression,
    componentChanges: componentChanges,
    causeSummaries: _summarizeCauses(later.lineage.causes),
  );
}

class NetWorthTrendBreak {
  final ComputedNetWorthSnapshot before;
  final ComputedNetWorthSnapshot after;
  final List<NetWorthComparabilityIssue> issues;

  NetWorthTrendBreak({
    required this.before,
    required this.after,
    required Iterable<NetWorthComparabilityIssue> issues,
  }) : issues = List.unmodifiable(issues);
}

class NetWorthTrendSegment {
  final List<ComputedNetWorthSnapshot> points;
  final List<NetWorthSnapshotChange> changes;

  NetWorthTrendSegment({
    required Iterable<ComputedNetWorthSnapshot> points,
    required Iterable<NetWorthSnapshotChange> changes,
  })  : points = List.unmodifiable(points),
        changes = List.unmodifiable(changes);
}

enum NetWorthTrendStatus {
  available,
  insufficientEligiblePoints,
  noComparablePairs,
}

class NetWorthTrendResult {
  final NetWorthTrendStatus status;
  final List<ComputedNetWorthSnapshot> points;
  final List<ComputedNetWorthSnapshot> isolatedPoints;
  final List<NetWorthTrendSegment> segments;
  final List<NetWorthTrendBreak> breaks;
  final List<NetWorthSnapshotChange> changes;

  NetWorthTrendResult({
    required this.status,
    required Iterable<ComputedNetWorthSnapshot> points,
    required Iterable<ComputedNetWorthSnapshot> isolatedPoints,
    required Iterable<NetWorthTrendSegment> segments,
    required Iterable<NetWorthTrendBreak> breaks,
    required Iterable<NetWorthSnapshotChange> changes,
  })  : points = List.unmodifiable(points),
        isolatedPoints = List.unmodifiable(isolatedPoints),
        segments = List.unmodifiable(segments),
        breaks = List.unmodifiable(breaks),
        changes = List.unmodifiable(changes);

  bool get hasTrend => status == NetWorthTrendStatus.available;
}

NetWorthTrendResult resolveNetWorthTrend(
  Iterable<ComputedNetWorthSnapshot> source,
) {
  final sorted = source.toList()
    ..sort((a, b) {
      final date = a.lineage.asOf.compareTo(b.lineage.asOf);
      if (date != 0) return date;
      final scope = a.lineage.scopeKey.compareTo(b.lineage.scopeKey);
      if (scope != 0) return scope;
      return a.lineage.knowledgeCutoff.compareTo(b.lineage.knowledgeCutoff);
    });
  final points = <ComputedNetWorthSnapshot>[];
  for (final point in sorted) {
    if (points.isNotEmpty &&
        points.last.lineage.asOf == point.lineage.asOf &&
        points.last.lineage.scopeKey == point.lineage.scopeKey) {
      points[points.length - 1] =
          mergeSameDayComputedSnapshots(points.last, point);
    } else {
      points.add(point);
    }
  }

  final isolated = points
      .where((point) => !point.isEligibleForEstimatedTrend)
      .toList(growable: false);
  final eligibleCount = points.length - isolated.length;
  final breaks = <NetWorthTrendBreak>[];
  final allChanges = <NetWorthSnapshotChange>[];
  final segments = <NetWorthTrendSegment>[];
  var segmentPoints = <ComputedNetWorthSnapshot>[];
  var segmentChanges = <NetWorthSnapshotChange>[];

  void closeSegment() {
    if (segmentPoints.isNotEmpty) {
      segments.add(NetWorthTrendSegment(
        points: segmentPoints,
        changes: segmentChanges,
      ));
      segmentPoints = <ComputedNetWorthSnapshot>[];
      segmentChanges = <NetWorthSnapshotChange>[];
    }
  }

  for (var index = 0; index < points.length; index++) {
    final current = points[index];
    if (index == 0) {
      if (current.isEligibleForEstimatedTrend) segmentPoints.add(current);
      continue;
    }
    final previous = points[index - 1];
    final comparison = compareComputedNetWorthSnapshots(previous, current);
    if (!comparison.isComparable) {
      breaks.add(NetWorthTrendBreak(
        before: previous,
        after: current,
        issues: comparison.issues,
      ));
      closeSegment();
      if (current.isEligibleForEstimatedTrend) {
        segmentPoints.add(current);
      }
      continue;
    }

    final change = _changeBetween(previous, current);
    segmentPoints.add(current);
    segmentChanges.add(change);
    allChanges.add(change);
  }
  closeSegment();

  final status = eligibleCount < 2
      ? NetWorthTrendStatus.insufficientEligiblePoints
      : allChanges.isEmpty
          ? NetWorthTrendStatus.noComparablePairs
          : NetWorthTrendStatus.available;
  return NetWorthTrendResult(
    status: status,
    points: points,
    isolatedPoints: isolated,
    segments: segments,
    breaks: breaks,
    changes: allChanges,
  );
}

NetWorthComponentChange _componentChange(
  NetWorthChangeComponent component,
  int before,
  int after, {
  bool subtractFromNetWorth = false,
}) {
  final rawDelta = after - before;
  return NetWorthComponentChange(
    component: component,
    rawDeltaMinor: rawDelta,
    netWorthContributionMinor: subtractFromNetWorth ? -rawDelta : rawDelta,
  );
}

List<NetWorthCauseSummary> _summarizeCauses(
  Iterable<NetWorthSnapshotCause> causes,
) {
  final grouped = <NetWorthChangeCauseGroup, Set<NetWorthSnapshotCause>>{};
  for (final cause in causes) {
    final group = switch (cause) {
      NetWorthSnapshotCause.transaction ||
      NetWorthSnapshotCause.refund ||
      NetWorthSnapshotCause.transfer =>
        NetWorthChangeCauseGroup.accountEvents,
      NetWorthSnapshotCause.valuation ||
      NetWorthSnapshotCause.physicalAsset ||
      NetWorthSnapshotCause.receivable =>
        NetWorthChangeCauseGroup.valuationChanges,
      NetWorthSnapshotCause.liability =>
        NetWorthChangeCauseGroup.liabilityEvents,
      NetWorthSnapshotCause.calibration ||
      NetWorthSnapshotCause.historicalBackfill =>
        NetWorthChangeCauseGroup.calibrationOrBackfill,
      NetWorthSnapshotCause.scope ||
      NetWorthSnapshotCause.migration =>
        NetWorthChangeCauseGroup.scopeOrMigration,
      NetWorthSnapshotCause.account =>
        NetWorthChangeCauseGroup.accountConfiguration,
      NetWorthSnapshotCause.scheduledRebuild =>
        NetWorthChangeCauseGroup.recalculation,
      NetWorthSnapshotCause.other => NetWorthChangeCauseGroup.other,
    };
    grouped.putIfAbsent(group, () => <NetWorthSnapshotCause>{}).add(cause);
  }
  return [
    for (final group in NetWorthChangeCauseGroup.values)
      if (grouped[group]?.isNotEmpty ?? false)
        NetWorthCauseSummary(group: group, causes: grouped[group]!),
  ];
}

DateTime _civilDay(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _currency(String value) => value.trim().toUpperCase();

List<String> _currencies(Iterable<String> values) {
  final normalized = values.map(_currency).where((value) => value.isNotEmpty);
  return (normalized.toSet().toList()..sort());
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
