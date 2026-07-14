enum AssetReminderStatus {
  none,
  upcoming,
  dueToday,
  expired,
  inactive,
}

class AssetReminderState {
  final AssetReminderStatus status;
  final int? daysUntilDue;

  const AssetReminderState({
    required this.status,
    this.daysUntilDue,
  });

  bool get needsAttention =>
      status == AssetReminderStatus.upcoming ||
      status == AssetReminderStatus.dueToday ||
      status == AssetReminderStatus.expired;
}

AssetReminderState resolveAssetReminder({
  required DateTime? dueAt,
  required bool isActive,
  DateTime? asOf,
  int upcomingWindowDays = 30,
}) {
  if (upcomingWindowDays < 0) {
    throw ArgumentError.value(
      upcomingWindowDays,
      'upcomingWindowDays',
      'must not be negative',
    );
  }
  if (!isActive) {
    return const AssetReminderState(status: AssetReminderStatus.inactive);
  }
  if (dueAt == null) {
    return const AssetReminderState(status: AssetReminderStatus.none);
  }

  final today = _civilDay(asOf ?? DateTime.now());
  final dueDay = _civilDay(dueAt);
  final daysUntilDue = dueDay.difference(today).inDays;
  if (daysUntilDue < 0) {
    return AssetReminderState(
      status: AssetReminderStatus.expired,
      daysUntilDue: daysUntilDue,
    );
  }
  if (daysUntilDue == 0) {
    return const AssetReminderState(
      status: AssetReminderStatus.dueToday,
      daysUntilDue: 0,
    );
  }
  if (daysUntilDue <= upcomingWindowDays) {
    return AssetReminderState(
      status: AssetReminderStatus.upcoming,
      daysUntilDue: daysUntilDue,
    );
  }
  return AssetReminderState(
    status: AssetReminderStatus.none,
    daysUntilDue: daysUntilDue,
  );
}

AssetReminderState resolveWarrantyReminder({
  required DateTime? warrantyUntil,
  required bool isEconomicallyOwned,
  DateTime? asOf,
}) =>
    resolveAssetReminder(
      dueAt: warrantyUntil,
      isActive: isEconomicallyOwned,
      asOf: asOf,
    );

AssetReminderState resolveReceivableDueReminder({
  required DateTime? dueAt,
  required bool isCollectible,
  DateTime? asOf,
}) =>
    resolveAssetReminder(
      dueAt: dueAt,
      isActive: isCollectible,
      asOf: asOf,
    );

class AssetUsageEventPoint {
  final String id;
  final int countDelta;
  final int occurredMs;
  final int sequence;
  final String? reversalOf;

  const AssetUsageEventPoint({
    required this.id,
    required this.countDelta,
    required this.occurredMs,
    this.sequence = 0,
    this.reversalOf,
  });

  bool get isReversal => reversalOf != null;
}

class AssetUsageAggregation {
  final int totalCount;
  final List<String> issues;
  final Set<String> activeEventIds;

  const AssetUsageAggregation({
    required this.totalCount,
    required this.issues,
    required this.activeEventIds,
  });

  bool get isExact => issues.isEmpty;
}

AssetUsageAggregation aggregateAssetUsage(
  Iterable<AssetUsageEventPoint> source,
) {
  final indexed = source.indexed.toList(growable: false)
    ..sort((left, right) {
      final byTime = left.$2.occurredMs.compareTo(right.$2.occurredMs);
      if (byTime != 0) return byTime;
      final bySequence = left.$2.sequence.compareTo(right.$2.sequence);
      if (bySequence != 0) return bySequence;
      return left.$1.compareTo(right.$1);
    });
  final events = [for (final entry in indexed) entry.$2];
  final issues = <String>[];
  final uniqueEvents = <AssetUsageEventPoint>[];
  final knownIds = <String>{};

  for (final event in events) {
    final id = event.id.trim();
    if (id.isEmpty) {
      issues.add('使用事件缺少稳定 ID');
      continue;
    }
    if (!knownIds.add(id)) {
      issues.add('使用事件 ID 重复：$id');
      continue;
    }
    uniqueEvents.add(event);
  }

  final inactiveIds = <String>{};
  final activeIds = <String>{};
  final positionById = <String, int>{
    for (var i = 0; i < uniqueEvents.length; i++) uniqueEvents[i].id.trim(): i,
  };
  final reversedTargets = <String>{};
  for (final event in uniqueEvents.reversed) {
    final id = event.id.trim();
    if (inactiveIds.contains(id)) continue;
    activeIds.add(id);
    final reversalOf = event.reversalOf?.trim();
    if (reversalOf == null || reversalOf.isEmpty) continue;
    if (event.countDelta != 0) {
      issues.add('撤销事件 $id 的 countDelta 必须为 0');
    }
    if (!knownIds.contains(reversalOf)) {
      issues.add('撤销事件 $id 指向不存在的事件：$reversalOf');
      continue;
    }
    if (reversalOf == id) {
      issues.add('使用事件不能撤销自身：$id');
      continue;
    }
    if (positionById[reversalOf]! >= positionById[id]!) {
      issues.add('撤销事件 $id 只能指向更早的事件：$reversalOf');
      continue;
    }
    if (!reversedTargets.add(reversalOf)) {
      issues.add('使用事件被重复撤销：$reversalOf');
      continue;
    }
    inactiveIds.add(reversalOf);
  }

  var total = 0;
  for (final event in uniqueEvents) {
    final id = event.id.trim();
    if (!activeIds.contains(id) || event.isReversal) continue;
    final next = total + event.countDelta;
    if (next < 0) {
      issues.add('使用事件 $id 会使累计次数小于 0');
      continue;
    }
    total = next;
  }

  return AssetUsageAggregation(
    totalCount: total,
    issues: List.unmodifiable(issues),
    activeEventIds: Set.unmodifiable(activeIds),
  );
}

DateTime _civilDay(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
