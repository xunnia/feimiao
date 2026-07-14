import 'net_worth_snapshot.dart';

enum NetWorthVerifiedCheckpointCompleteness { complete, partial }

extension NetWorthVerifiedCheckpointCompletenessX
    on NetWorthVerifiedCheckpointCompleteness {
  String get storageKey => switch (this) {
        NetWorthVerifiedCheckpointCompleteness.complete => 'complete',
        NetWorthVerifiedCheckpointCompleteness.partial => 'partial',
      };

  static NetWorthVerifiedCheckpointCompleteness fromStorage(String? value) {
    return value == NetWorthVerifiedCheckpointCompleteness.complete.storageKey
        ? NetWorthVerifiedCheckpointCompleteness.complete
        : NetWorthVerifiedCheckpointCompleteness.partial;
  }
}

enum NetWorthVerifiedCheckpointStatus { active, superseded, revoked }

extension NetWorthVerifiedCheckpointStatusX
    on NetWorthVerifiedCheckpointStatus {
  String get storageKey => switch (this) {
        NetWorthVerifiedCheckpointStatus.active => 'active',
        NetWorthVerifiedCheckpointStatus.superseded => 'superseded',
        NetWorthVerifiedCheckpointStatus.revoked => 'revoked',
      };

  static NetWorthVerifiedCheckpointStatus fromStorage(String? value) {
    for (final status in NetWorthVerifiedCheckpointStatus.values) {
      if (status.storageKey == value) return status;
    }
    // Unknown persisted states must never become eligible for comparison.
    return NetWorthVerifiedCheckpointStatus.revoked;
  }
}

class NetWorthVerifiedCheckpointReason {
  final String code;
  final String message;
  final Map<String, Object?> details;

  NetWorthVerifiedCheckpointReason({
    required String code,
    required String message,
    Map<String, Object?> details = const {},
  })  : code = code.trim(),
        message = message.trim(),
        details = Map.unmodifiable(Map<String, Object?>.of(details)) {
    if (this.code.isEmpty || this.message.isEmpty) {
      throw ArgumentError('A checkpoint reason requires a code and message.');
    }
  }
}

class NetWorthVerifiedCheckpointTotals {
  final int totalAssetsMinor;
  final int totalLiabilitiesMinor;
  final int netWorthMinor;

  factory NetWorthVerifiedCheckpointTotals({
    required int totalAssetsMinor,
    required int totalLiabilitiesMinor,
    required int netWorthMinor,
  }) {
    if (totalAssetsMinor < 0 || totalLiabilitiesMinor < 0) {
      throw ArgumentError(
        'Verified asset and liability totals cannot be negative.',
      );
    }
    if (netWorthMinor != totalAssetsMinor - totalLiabilitiesMinor) {
      throw ArgumentError(
        'Verified net worth must equal assets minus liabilities.',
      );
    }
    return NetWorthVerifiedCheckpointTotals._(
      totalAssetsMinor: totalAssetsMinor,
      totalLiabilitiesMinor: totalLiabilitiesMinor,
      netWorthMinor: netWorthMinor,
    );
  }

  const NetWorthVerifiedCheckpointTotals._({
    required this.totalAssetsMinor,
    required this.totalLiabilitiesMinor,
    required this.netWorthMinor,
  });

  factory NetWorthVerifiedCheckpointTotals.checked({
    required int totalAssetsMinor,
    required int totalLiabilitiesMinor,
    required int netWorthMinor,
  }) {
    return NetWorthVerifiedCheckpointTotals(
      totalAssetsMinor: totalAssetsMinor,
      totalLiabilitiesMinor: totalLiabilitiesMinor,
      netWorthMinor: netWorthMinor,
    );
  }
}

class NetWorthVerifiedCheckpointHeader {
  final int? id;
  final String uuid;
  final DateTime asOf;
  final DateTime knowledgeCutoff;
  final int scopeVersion;
  final int calculationVersion;
  final NetWorthCurrencyCoverage currencyCoverage;
  final NetWorthVerifiedCheckpointTotals totals;
  final NetWorthVerifiedCheckpointCompleteness completeness;
  final List<NetWorthVerifiedCheckpointReason> incompletenessReasons;
  final NetWorthVerifiedCheckpointStatus status;
  final int? supersedesId;
  final DateTime createdAt;

  NetWorthVerifiedCheckpointHeader({
    this.id,
    required String uuid,
    required DateTime asOf,
    required DateTime knowledgeCutoff,
    required this.scopeVersion,
    required this.calculationVersion,
    required this.currencyCoverage,
    required this.totals,
    required this.completeness,
    Iterable<NetWorthVerifiedCheckpointReason> incompletenessReasons = const [],
    required this.status,
    this.supersedesId,
    required DateTime createdAt,
  })  : uuid = uuid.trim(),
        asOf = asOf.toUtc(),
        knowledgeCutoff = knowledgeCutoff.toUtc(),
        incompletenessReasons = List.unmodifiable(incompletenessReasons),
        createdAt = createdAt.toUtc() {
    if (this.uuid.isEmpty) {
      throw ArgumentError.value(uuid, 'uuid', 'must not be empty');
    }
    if (scopeVersion < 1 || calculationVersion < 1) {
      throw ArgumentError('Scope and calculation versions must be positive.');
    }
    if (this.knowledgeCutoff.isBefore(this.asOf)) {
      throw ArgumentError('Knowledge cutoff cannot precede the as-of time.');
    }
    if (completeness == NetWorthVerifiedCheckpointCompleteness.complete) {
      if (this.incompletenessReasons.isNotEmpty) {
        throw ArgumentError(
            'A complete checkpoint cannot have missing coverage.');
      }
      if (!currencyCoverage.isComplete) {
        throw ArgumentError(
          'Uncovered currencies require a partial verified checkpoint.',
        );
      }
    } else if (this.incompletenessReasons.isEmpty) {
      throw ArgumentError('A partial checkpoint requires at least one reason.');
    }
  }
}

class NetWorthVerifiedCheckpointItemKey {
  final String objectType;
  final String objectUuid;

  NetWorthVerifiedCheckpointItemKey({
    required String objectType,
    required String objectUuid,
  })  : objectType = objectType.trim().toLowerCase(),
        objectUuid = objectUuid.trim() {
    if (this.objectType.isEmpty || this.objectUuid.isEmpty) {
      throw ArgumentError('A verified item requires an object type and UUID.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetWorthVerifiedCheckpointItemKey &&
          objectType == other.objectType &&
          objectUuid == other.objectUuid;

  @override
  int get hashCode => Object.hash(objectType, objectUuid);
}

class NetWorthVerifiedCheckpointItem {
  final NetWorthVerifiedCheckpointItemKey key;
  final int confirmedAmountMinor;
  final String currencyCode;
  final DateTime valueEffectiveAt;
  final String valueSource;
  final String quality;

  NetWorthVerifiedCheckpointItem({
    required String objectType,
    required String objectUuid,
    required this.confirmedAmountMinor,
    required String currencyCode,
    required DateTime valueEffectiveAt,
    required String valueSource,
    required String quality,
  })  : key = NetWorthVerifiedCheckpointItemKey(
          objectType: objectType,
          objectUuid: objectUuid,
        ),
        currencyCode = currencyCode.trim().toUpperCase(),
        valueEffectiveAt = valueEffectiveAt.toUtc(),
        valueSource = valueSource.trim(),
        quality = quality.trim() {
    if (this.currencyCode.isEmpty ||
        this.valueSource.isEmpty ||
        this.quality.isEmpty) {
      throw ArgumentError(
        'A verified item requires currency, value source, and quality.',
      );
    }
  }
}

class NetWorthVerifiedCheckpoint {
  final NetWorthVerifiedCheckpointHeader header;
  final List<NetWorthVerifiedCheckpointItem> items;

  NetWorthVerifiedCheckpoint({
    required this.header,
    required Iterable<NetWorthVerifiedCheckpointItem> items,
  }) : items = List.unmodifiable(items) {
    final keys = <NetWorthVerifiedCheckpointItemKey>{};
    for (final item in this.items) {
      if (!keys.add(item.key)) {
        throw ArgumentError(
          'A checkpoint cannot contain duplicate object evidence: '
          '${item.key.objectType}/${item.key.objectUuid}.',
        );
      }
    }
  }
}

enum NetWorthVerifiedComparabilityIssue {
  nonIncreasingAsOf,
  earlierNotActive,
  laterNotActive,
  earlierIncomplete,
  laterIncomplete,
  scopeVersionMismatch,
  calculationVersionMismatch,
  currencyCoverageMismatch,
}

extension NetWorthVerifiedComparabilityIssueX
    on NetWorthVerifiedComparabilityIssue {
  String get message => switch (this) {
        NetWorthVerifiedComparabilityIssue.nonIncreasingAsOf =>
          'The later checkpoint must have a later as-of time.',
        NetWorthVerifiedComparabilityIssue.earlierNotActive =>
          'The earlier checkpoint is superseded or revoked.',
        NetWorthVerifiedComparabilityIssue.laterNotActive =>
          'The later checkpoint is superseded or revoked.',
        NetWorthVerifiedComparabilityIssue.earlierIncomplete =>
          'The earlier checkpoint only covers part of net worth.',
        NetWorthVerifiedComparabilityIssue.laterIncomplete =>
          'The later checkpoint only covers part of net worth.',
        NetWorthVerifiedComparabilityIssue.scopeVersionMismatch =>
          'The net-worth inclusion scope changed between checkpoints.',
        NetWorthVerifiedComparabilityIssue.calculationVersionMismatch =>
          'The calculation contract changed between checkpoints.',
        NetWorthVerifiedComparabilityIssue.currencyCoverageMismatch =>
          'Currency coverage differs between checkpoints.',
      };
}

enum NetWorthVerifiedObjectChangeType { added, removed, changed, unchanged }

class NetWorthVerifiedObjectChange {
  final NetWorthVerifiedCheckpointItemKey key;
  final NetWorthVerifiedObjectChangeType type;
  final NetWorthVerifiedCheckpointItem? earlierItem;
  final NetWorthVerifiedCheckpointItem? laterItem;

  const NetWorthVerifiedObjectChange({
    required this.key,
    required this.type,
    required this.earlierItem,
    required this.laterItem,
  });

  int? get confirmedAmountDeltaMinor {
    final earlier = earlierItem;
    final later = laterItem;
    if (earlier == null) return later?.confirmedAmountMinor;
    if (later == null) return -earlier.confirmedAmountMinor;
    if (earlier.currencyCode != later.currencyCode) return null;
    return later.confirmedAmountMinor - earlier.confirmedAmountMinor;
  }
}

class NetWorthVerifiedCheckpointChange {
  final NetWorthVerifiedCheckpoint earlier;
  final NetWorthVerifiedCheckpoint later;
  final int totalAssetsDeltaMinor;
  final int totalLiabilitiesDeltaMinor;
  final int netWorthDeltaMinor;
  final List<NetWorthVerifiedObjectChange> objectChanges;

  NetWorthVerifiedCheckpointChange._({
    required this.earlier,
    required this.later,
    required this.totalAssetsDeltaMinor,
    required this.totalLiabilitiesDeltaMinor,
    required this.netWorthDeltaMinor,
    required Iterable<NetWorthVerifiedObjectChange> objectChanges,
  }) : objectChanges = List.unmodifiable(objectChanges);
}

class NetWorthVerifiedCheckpointComparison {
  final NetWorthVerifiedCheckpoint earlier;
  final NetWorthVerifiedCheckpoint later;
  final List<NetWorthVerifiedComparabilityIssue> issues;
  final NetWorthVerifiedCheckpointChange? change;

  NetWorthVerifiedCheckpointComparison._({
    required this.earlier,
    required this.later,
    required Iterable<NetWorthVerifiedComparabilityIssue> issues,
    required this.change,
  }) : issues = List.unmodifiable(issues);

  bool get isComparable => issues.isEmpty;
  List<String> get reasonMessages =>
      List.unmodifiable(issues.map((issue) => issue.message));
}

NetWorthVerifiedCheckpointComparison compareNetWorthVerifiedCheckpoints(
  NetWorthVerifiedCheckpoint earlier,
  NetWorthVerifiedCheckpoint later,
) {
  final issues = <NetWorthVerifiedComparabilityIssue>[];
  final earlierHeader = earlier.header;
  final laterHeader = later.header;

  if (!earlierHeader.asOf.isBefore(laterHeader.asOf)) {
    issues.add(NetWorthVerifiedComparabilityIssue.nonIncreasingAsOf);
  }
  if (earlierHeader.status != NetWorthVerifiedCheckpointStatus.active) {
    issues.add(NetWorthVerifiedComparabilityIssue.earlierNotActive);
  }
  if (laterHeader.status != NetWorthVerifiedCheckpointStatus.active) {
    issues.add(NetWorthVerifiedComparabilityIssue.laterNotActive);
  }
  if (earlierHeader.completeness !=
      NetWorthVerifiedCheckpointCompleteness.complete) {
    issues.add(NetWorthVerifiedComparabilityIssue.earlierIncomplete);
  }
  if (laterHeader.completeness !=
      NetWorthVerifiedCheckpointCompleteness.complete) {
    issues.add(NetWorthVerifiedComparabilityIssue.laterIncomplete);
  }
  if (earlierHeader.scopeVersion != laterHeader.scopeVersion) {
    issues.add(NetWorthVerifiedComparabilityIssue.scopeVersionMismatch);
  }
  if (earlierHeader.calculationVersion != laterHeader.calculationVersion) {
    issues.add(NetWorthVerifiedComparabilityIssue.calculationVersionMismatch);
  }
  if (earlierHeader.currencyCoverage != laterHeader.currencyCoverage) {
    issues.add(NetWorthVerifiedComparabilityIssue.currencyCoverageMismatch);
  }

  if (issues.isNotEmpty) {
    return NetWorthVerifiedCheckpointComparison._(
      earlier: earlier,
      later: later,
      issues: issues,
      change: null,
    );
  }

  final earlierTotals = earlierHeader.totals;
  final laterTotals = laterHeader.totals;
  return NetWorthVerifiedCheckpointComparison._(
    earlier: earlier,
    later: later,
    issues: const [],
    change: NetWorthVerifiedCheckpointChange._(
      earlier: earlier,
      later: later,
      totalAssetsDeltaMinor:
          laterTotals.totalAssetsMinor - earlierTotals.totalAssetsMinor,
      totalLiabilitiesDeltaMinor: laterTotals.totalLiabilitiesMinor -
          earlierTotals.totalLiabilitiesMinor,
      netWorthDeltaMinor:
          laterTotals.netWorthMinor - earlierTotals.netWorthMinor,
      objectChanges: _compareVerifiedItems(earlier.items, later.items),
    ),
  );
}

List<NetWorthVerifiedObjectChange> _compareVerifiedItems(
  Iterable<NetWorthVerifiedCheckpointItem> earlierItems,
  Iterable<NetWorthVerifiedCheckpointItem> laterItems,
) {
  final earlier = {for (final item in earlierItems) item.key: item};
  final later = {for (final item in laterItems) item.key: item};
  final keys = <NetWorthVerifiedCheckpointItemKey>{
    ...earlier.keys,
    ...later.keys,
  }.toList()
    ..sort((a, b) {
      final type = a.objectType.compareTo(b.objectType);
      return type != 0 ? type : a.objectUuid.compareTo(b.objectUuid);
    });

  return [
    for (final key in keys) _objectChange(key, earlier[key], later[key]),
  ];
}

NetWorthVerifiedObjectChange _objectChange(
  NetWorthVerifiedCheckpointItemKey key,
  NetWorthVerifiedCheckpointItem? earlier,
  NetWorthVerifiedCheckpointItem? later,
) {
  final type = switch ((earlier, later)) {
    (null, _) => NetWorthVerifiedObjectChangeType.added,
    (_, null) => NetWorthVerifiedObjectChangeType.removed,
    (final before?, final after?)
        when before.confirmedAmountMinor == after.confirmedAmountMinor &&
            before.currencyCode == after.currencyCode &&
            before.valueEffectiveAt == after.valueEffectiveAt &&
            before.valueSource == after.valueSource &&
            before.quality == after.quality =>
      NetWorthVerifiedObjectChangeType.unchanged,
    _ => NetWorthVerifiedObjectChangeType.changed,
  };
  return NetWorthVerifiedObjectChange(
    key: key,
    type: type,
    earlierItem: earlier,
    laterItem: later,
  );
}
