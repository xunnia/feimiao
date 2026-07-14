const int statisticsCalculationVersion = 1;

enum MetricDateAxis {
  attribution,
  settlement,
  valuation,
  asOf,
}

enum MetricResultMode {
  live,
  frozen,
}

enum MetricStatus {
  available,
  partial,
  unavailable,
  notApplicable,
  stale,
  conflict,
}

enum MetricReasonCode {
  invalidInput,
  unsupportedCurrencyAggregation,
  unknownBookScope,
  unknownCurrency,
  unallocatedRefund,
  duplicateIdentity,
  refundExceedsOriginal,
  noBudgetPlan,
  legacyScopeAmbiguous,
  legacyOverrideWithoutPrimary,
  legacyOpenEndedOverride,
  categoryBudgetExceedsPlan,
  fixedCommitmentsUnavailable,
  windowNotStarted,
  noComparableWindow,
  metricMismatch,
  dateAxisMismatch,
  timezoneMismatch,
  bookScopeMismatch,
  currencyScopeMismatch,
  resultModeMismatch,
  classificationVersionMismatch,
  calculationVersionMismatch,
  unknownSettlementDate,
  unknownSettlementAccount,
  assumedSettlementDate,
  assumedSettlementAccount,
  invalidTransferAccounts,
}

class MetricReason {
  final MetricReasonCode code;
  final String message;
  final Map<String, Object?> details;

  MetricReason({
    required this.code,
    required this.message,
    Map<String, Object?> details = const {},
  }) : details = Map.unmodifiable(Map<String, Object?>.of(details));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetricReason &&
          code == other.code &&
          message == other.message &&
          _mapsEqual(details, other.details);

  @override
  int get hashCode {
    final keys = details.keys.toList()..sort();
    return Object.hash(
      code,
      message,
      Object.hashAll(
        keys.map((key) => Object.hash(key, details[key])),
      ),
    );
  }
}

/// A half-open metric window: [startInclusive, endExclusive).
///
/// Calendar resolvers treat the DateTime components as civil-calendar values;
/// they do not convert instants into a named timezone. Callers must project
/// boundaries into the query timezone before constructing the window and keep
/// both boundaries in the same UTC/local representation.
class MetricWindow {
  final DateTime startInclusive;
  final DateTime endExclusive;

  MetricWindow({
    required this.startInclusive,
    required this.endExclusive,
  }) {
    if (!startInclusive.isBefore(endExclusive)) {
      throw ArgumentError.value(
        endExclusive,
        'endExclusive',
        'must be after startInclusive',
      );
    }
    if (startInclusive.isUtc != endExclusive.isUtc) {
      throw ArgumentError(
        'Window boundaries must both be UTC or both use business-calendar '
        'local values.',
      );
    }
  }

  bool contains(DateTime value) =>
      !value.isBefore(startInclusive) && value.isBefore(endExclusive);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetricWindow &&
          startInclusive == other.startInclusive &&
          endExclusive == other.endExclusive;

  @override
  int get hashCode => Object.hash(startInclusive, endExclusive);
}

/// Explicit book membership plus the version of the membership policy.
class MetricBookScope {
  final List<int> bookIds;
  final int scopeVersion;

  MetricBookScope({
    required Iterable<int> bookIds,
    required this.scopeVersion,
  }) : bookIds = List.unmodifiable(_sortedUniqueInts(bookIds)) {
    if (this.bookIds.isEmpty) {
      throw ArgumentError.value(bookIds, 'bookIds', 'must not be empty');
    }
    if (scopeVersion < 1) {
      throw ArgumentError.value(
        scopeVersion,
        'scopeVersion',
        'must be positive',
      );
    }
  }

  bool contains(int bookId) => bookIds.contains(bookId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetricBookScope &&
          scopeVersion == other.scopeVersion &&
          _listsEqual(bookIds, other.bookIds);

  @override
  int get hashCode => Object.hash(scopeVersion, Object.hashAll(bookIds));
}

/// Currency codes are explicit. Direct aggregation is only valid for one code.
class MetricCurrencyScope {
  final List<String> currencyCodes;

  MetricCurrencyScope(Iterable<String> currencyCodes)
      : currencyCodes =
            List.unmodifiable(_normalizedCurrencies(currencyCodes)) {
    if (this.currencyCodes.isEmpty) {
      throw ArgumentError.value(
        currencyCodes,
        'currencyCodes',
        'must not be empty',
      );
    }
  }

  factory MetricCurrencyScope.single(String currencyCode) =>
      MetricCurrencyScope([currencyCode]);

  bool contains(String currencyCode) =>
      currencyCodes.contains(currencyCode.trim().toUpperCase());

  bool get canAggregateWithoutConversion => currencyCodes.length == 1;

  String? get singleCurrency =>
      canAggregateWithoutConversion ? currencyCodes.single : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetricCurrencyScope &&
          _listsEqual(currencyCodes, other.currencyCodes);

  @override
  int get hashCode => Object.hashAll(currencyCodes);
}

class MetricQuery {
  final String metricId;
  final MetricWindow window;
  final MetricDateAxis dateAxis;
  final String timezone;
  final MetricBookScope bookScope;
  final MetricCurrencyScope currencyScope;
  final DateTime asOf;
  final DateTime knowledgeCutoff;
  final MetricResultMode resultMode;
  final int classificationVersion;
  final int calculationVersion;

  /// [window] and calendar-based [asOf] values must already be projected into
  /// [timezone]. The timezone is part of comparability and lineage; core
  /// resolvers deliberately do not perform timezone conversion.
  MetricQuery({
    required String metricId,
    required this.window,
    required this.dateAxis,
    required String timezone,
    required this.bookScope,
    required this.currencyScope,
    required this.asOf,
    required this.knowledgeCutoff,
    this.resultMode = MetricResultMode.live,
    this.classificationVersion = 1,
    this.calculationVersion = statisticsCalculationVersion,
  })  : metricId = metricId.trim(),
        timezone = timezone.trim() {
    if (this.metricId.isEmpty) {
      throw ArgumentError.value(metricId, 'metricId', 'must not be empty');
    }
    if (this.timezone.isEmpty) {
      throw ArgumentError.value(timezone, 'timezone', 'must not be empty');
    }
    if (classificationVersion < 1) {
      throw ArgumentError.value(
        classificationVersion,
        'classificationVersion',
        'must be positive',
      );
    }
    if (calculationVersion < 1) {
      throw ArgumentError.value(
        calculationVersion,
        'calculationVersion',
        'must be positive',
      );
    }
  }

  MetricQuery copyWith({
    String? metricId,
    MetricWindow? window,
    MetricDateAxis? dateAxis,
    String? timezone,
    MetricBookScope? bookScope,
    MetricCurrencyScope? currencyScope,
    DateTime? asOf,
    DateTime? knowledgeCutoff,
    MetricResultMode? resultMode,
    int? classificationVersion,
    int? calculationVersion,
  }) =>
      MetricQuery(
        metricId: metricId ?? this.metricId,
        window: window ?? this.window,
        dateAxis: dateAxis ?? this.dateAxis,
        timezone: timezone ?? this.timezone,
        bookScope: bookScope ?? this.bookScope,
        currencyScope: currencyScope ?? this.currencyScope,
        asOf: asOf ?? this.asOf,
        knowledgeCutoff: knowledgeCutoff ?? this.knowledgeCutoff,
        resultMode: resultMode ?? this.resultMode,
        classificationVersion:
            classificationVersion ?? this.classificationVersion,
        calculationVersion: calculationVersion ?? this.calculationVersion,
      );

  /// Returns why two results cannot be compared, or null when contexts match.
  MetricReason? comparabilityIssue(MetricQuery other) {
    if (metricId != other.metricId) {
      return MetricReason(
        code: MetricReasonCode.metricMismatch,
        message: 'Metric identifiers differ.',
      );
    }
    if (dateAxis != other.dateAxis) {
      return MetricReason(
        code: MetricReasonCode.dateAxisMismatch,
        message: 'Date axes differ.',
      );
    }
    if (timezone != other.timezone) {
      return MetricReason(
        code: MetricReasonCode.timezoneMismatch,
        message: 'Business calendar timezones differ.',
      );
    }
    if (bookScope != other.bookScope) {
      return MetricReason(
        code: MetricReasonCode.bookScopeMismatch,
        message: 'Book scopes or scope versions differ.',
      );
    }
    if (currencyScope != other.currencyScope) {
      return MetricReason(
        code: MetricReasonCode.currencyScopeMismatch,
        message: 'Currency scopes differ.',
      );
    }
    if (resultMode != other.resultMode) {
      return MetricReason(
        code: MetricReasonCode.resultModeMismatch,
        message: 'Live and frozen results are not directly comparable.',
      );
    }
    if (classificationVersion != other.classificationVersion) {
      return MetricReason(
        code: MetricReasonCode.classificationVersionMismatch,
        message: 'Classification versions differ.',
      );
    }
    if (calculationVersion != other.calculationVersion) {
      return MetricReason(
        code: MetricReasonCode.calculationVersionMismatch,
        message: 'Calculation versions differ.',
      );
    }
    return null;
  }
}

class MetricLineage {
  final String resolver;
  final int calculationVersion;
  final int classificationVersion;

  const MetricLineage({
    required this.resolver,
    required this.calculationVersion,
    required this.classificationVersion,
  });
}

class MetricResult<T> {
  final T? value;
  final MetricStatus status;
  final List<MetricReason> reasons;
  final MetricQuery query;
  final MetricLineage lineage;

  MetricResult._({
    required this.value,
    required this.status,
    required Iterable<MetricReason> reasons,
    required this.query,
    required String resolver,
  })  : reasons = List.unmodifiable(reasons),
        lineage = MetricLineage(
          resolver: resolver,
          calculationVersion: query.calculationVersion,
          classificationVersion: query.classificationVersion,
        ) {
    final hasValue = value != null;
    if ((status == MetricStatus.available ||
            status == MetricStatus.partial ||
            status == MetricStatus.stale) &&
        !hasValue) {
      throw ArgumentError('$status requires a value.');
    }
    if (status == MetricStatus.available && this.reasons.isNotEmpty) {
      throw ArgumentError('An available result cannot have quality reasons.');
    }
    if ((status == MetricStatus.partial || status == MetricStatus.stale) &&
        this.reasons.isEmpty) {
      throw ArgumentError('$status requires at least one reason.');
    }
    if ((status == MetricStatus.unavailable ||
            status == MetricStatus.notApplicable ||
            status == MetricStatus.conflict) &&
        hasValue) {
      throw ArgumentError('$status cannot carry a value.');
    }
    if ((status == MetricStatus.unavailable ||
            status == MetricStatus.notApplicable ||
            status == MetricStatus.conflict) &&
        this.reasons.isEmpty) {
      throw ArgumentError('$status requires at least one reason.');
    }
  }

  factory MetricResult.available({
    required T value,
    required MetricQuery query,
    required String resolver,
  }) =>
      MetricResult._(
        value: value,
        status: MetricStatus.available,
        reasons: const [],
        query: query,
        resolver: resolver,
      );

  factory MetricResult.partial({
    required T value,
    required Iterable<MetricReason> reasons,
    required MetricQuery query,
    required String resolver,
  }) =>
      MetricResult._(
        value: value,
        status: MetricStatus.partial,
        reasons: reasons,
        query: query,
        resolver: resolver,
      );

  factory MetricResult.stale({
    required T value,
    required Iterable<MetricReason> reasons,
    required MetricQuery query,
    required String resolver,
  }) =>
      MetricResult._(
        value: value,
        status: MetricStatus.stale,
        reasons: reasons,
        query: query,
        resolver: resolver,
      );

  factory MetricResult.unavailable({
    required Iterable<MetricReason> reasons,
    required MetricQuery query,
    required String resolver,
  }) =>
      MetricResult._(
        value: null,
        status: MetricStatus.unavailable,
        reasons: reasons,
        query: query,
        resolver: resolver,
      );

  factory MetricResult.notApplicable({
    required Iterable<MetricReason> reasons,
    required MetricQuery query,
    required String resolver,
  }) =>
      MetricResult._(
        value: null,
        status: MetricStatus.notApplicable,
        reasons: reasons,
        query: query,
        resolver: resolver,
      );

  factory MetricResult.conflict({
    required Iterable<MetricReason> reasons,
    required MetricQuery query,
    required String resolver,
  }) =>
      MetricResult._(
        value: null,
        status: MetricStatus.conflict,
        reasons: reasons,
        query: query,
        resolver: resolver,
      );

  MetricWindow get window => query.window;
  MetricBookScope get scope => query.bookScope;
  MetricCurrencyScope get currency => query.currencyScope;
  DateTime get asOf => query.asOf;
  bool get hasValue => value != null;
}

List<int> _sortedUniqueInts(Iterable<int> values) {
  final result = values.toSet().toList()..sort();
  return result;
}

List<String> _normalizedCurrencies(Iterable<String> values) {
  final result = values
      .map((value) => value.trim().toUpperCase())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return result;
}

bool _listsEqual<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

bool _mapsEqual(Map<String, Object?> left, Map<String, Object?> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
