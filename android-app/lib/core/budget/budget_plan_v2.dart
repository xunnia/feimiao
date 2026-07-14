import 'dart:convert';

enum BudgetPlanCadenceV2 { monthly, weekly, oneOff }

extension BudgetPlanCadenceV2X on BudgetPlanCadenceV2 {
  String get storageKey => switch (this) {
        BudgetPlanCadenceV2.monthly => 'monthly',
        BudgetPlanCadenceV2.weekly => 'weekly',
        BudgetPlanCadenceV2.oneOff => 'one_off',
      };

  static BudgetPlanCadenceV2 fromStorage(String? value) => switch (value) {
        'weekly' => BudgetPlanCadenceV2.weekly,
        'one_off' => BudgetPlanCadenceV2.oneOff,
        _ => BudgetPlanCadenceV2.monthly,
      };
}

/// The category/tag filter attached to a one-off special tracking plan.
///
/// Category keys refer to stable top-level expense category keys. A family
/// matches when either its category or any of its tags is selected. The JSON
/// representation is canonical so backups and future sync do not churn when
/// callers provide the same values in a different order.
class BudgetExpenseScopeV2 {
  static const empty = BudgetExpenseScopeV2._(
    categoryKeys: <String>{},
    tagIds: <int>{},
  );

  final Set<String> categoryKeys;
  final Set<int> tagIds;

  const BudgetExpenseScopeV2._({
    required this.categoryKeys,
    required this.tagIds,
  });

  factory BudgetExpenseScopeV2({
    Iterable<String> categoryKeys = const [],
    Iterable<int> tagIds = const [],
  }) {
    final normalizedCategories = categoryKeys
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final normalizedTagIds = tagIds.toSet();
    if (normalizedTagIds.any((value) => value <= 0)) {
      throw ArgumentError('Budget scope tag IDs must be positive.');
    }
    if (normalizedCategories.isEmpty && normalizedTagIds.isEmpty) {
      return empty;
    }
    return BudgetExpenseScopeV2._(
      categoryKeys: Set.unmodifiable(normalizedCategories),
      tagIds: Set.unmodifiable(normalizedTagIds),
    );
  }

  factory BudgetExpenseScopeV2.fromJson(Map<String, Object?> json) {
    final match = json['match']?.toString() ?? 'any';
    if (match != 'any') {
      throw const FormatException('Budget scope only supports match:any.');
    }
    final rawCategories = json['category_keys'];
    final rawTagIds = json['tag_ids'];
    if (rawCategories != null && rawCategories is! List) {
      throw const FormatException('category_keys must be a JSON array.');
    }
    if (rawTagIds != null && rawTagIds is! List) {
      throw const FormatException('tag_ids must be a JSON array.');
    }
    final categories = <String>[];
    for (final value in (rawCategories as List?) ?? const []) {
      if (value is! String) {
        throw const FormatException('Category keys must be strings.');
      }
      categories.add(value);
    }
    final tags = <int>[];
    for (final value in (rawTagIds as List?) ?? const []) {
      final parsed = value is int ? value : int.tryParse(value.toString());
      if (parsed == null || parsed <= 0) {
        throw const FormatException('Tag IDs must be positive integers.');
      }
      tags.add(parsed);
    }
    return BudgetExpenseScopeV2(categoryKeys: categories, tagIds: tags);
  }

  factory BudgetExpenseScopeV2.fromJsonString(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return empty;
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Budget scope must be a JSON object.');
    }
    return BudgetExpenseScopeV2.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  bool get isEmpty => categoryKeys.isEmpty && tagIds.isEmpty;
  bool get isNotEmpty => !isEmpty;

  bool matches({
    String categoryKey = '',
    Iterable<int> familyTagIds = const [],
  }) {
    final normalizedCategory = categoryKey.trim();
    if (normalizedCategory.isNotEmpty &&
        categoryKeys.contains(normalizedCategory)) {
      return true;
    }
    return familyTagIds.any(tagIds.contains);
  }

  Map<String, Object> toJson() {
    final categories = categoryKeys.toList()..sort();
    final tags = tagIds.toList()..sort();
    return {
      'category_keys': categories,
      'tag_ids': tags,
      'match': 'any',
    };
  }

  String toJsonString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BudgetExpenseScopeV2 &&
          _setsEqual(categoryKeys, other.categoryKeys) &&
          _setsEqual(tagIds, other.tagIds);

  @override
  int get hashCode {
    final categories = categoryKeys.toList()..sort();
    final tags = tagIds.toList()..sort();
    return Object.hash(Object.hashAll(categories), Object.hashAll(tags));
  }

  static bool _setsEqual<T>(Set<T> left, Set<T> right) =>
      left.length == right.length && left.containsAll(right);
}

enum BudgetPlanStatusV2 { active, archived }

enum BudgetOverrideIntent {
  replaceTotal('replace_total'),
  adjustRemaining('adjust_remaining'),
  setRemaining('set_remaining');

  const BudgetOverrideIntent(this.storageKey);
  final String storageKey;

  static BudgetOverrideIntent fromStorage(String? value) => values.firstWhere(
        (item) => item.storageKey == value,
        orElse: () => BudgetOverrideIntent.replaceTotal,
      );
}

extension BudgetPlanStatusV2X on BudgetPlanStatusV2 {
  String get storageKey =>
      this == BudgetPlanStatusV2.active ? 'active' : 'archived';

  static BudgetPlanStatusV2 fromStorage(String? value) => value == 'archived'
      ? BudgetPlanStatusV2.archived
      : BudgetPlanStatusV2.active;
}

int budgetCivilDayKey(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;

DateTime budgetCivilDayFromKey(int key) {
  final year = key ~/ 10000;
  final month = (key ~/ 100) % 100;
  final day = key % 100;
  final value = DateTime(year, month, day);
  if (value.year != year || value.month != month || value.day != day) {
    throw FormatException('Invalid civil day key: $key');
  }
  return value;
}

DateTime _budgetDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class BudgetFixedTemplateV2 {
  final String id;
  final String name;
  final int plannedCents;
  final int dueValue;

  const BudgetFixedTemplateV2({
    required this.id,
    required this.name,
    required this.plannedCents,
    required this.dueValue,
  });
}

class BudgetPlanV2 {
  final int id;
  final String uuid;
  final int bookId;
  final String currencyCode;
  final String timezone;
  final String name;
  final String role;
  final BudgetPlanCadenceV2 cadence;
  final DateTime anchorStart;
  final int? monthStartDay;
  final int? weekStart;
  final DateTime? endInclusive;
  final BudgetExpenseScopeV2 expenseScope;
  final BudgetPlanStatusV2 status;
  final int createdMs;
  final int updatedMs;

  BudgetPlanV2({
    required this.id,
    required this.uuid,
    required this.bookId,
    this.currencyCode = 'CNY',
    this.timezone = 'device_local',
    this.name = '',
    String role = 'primary',
    required this.cadence,
    required DateTime anchorStart,
    this.monthStartDay,
    int? weekStart,
    DateTime? endInclusive,
    BudgetExpenseScopeV2? expenseScope,
    this.status = BudgetPlanStatusV2.active,
    this.createdMs = 0,
    this.updatedMs = 0,
  })  : role = role.trim().toLowerCase(),
        anchorStart = _budgetDay(anchorStart),
        endInclusive = endInclusive == null ? null : _budgetDay(endInclusive),
        expenseScope = expenseScope ?? BudgetExpenseScopeV2.empty,
        weekStart = cadence == BudgetPlanCadenceV2.weekly
            ? (weekStart ?? anchorStart.weekday)
            : weekStart {
    if (id < 0 || bookId <= 0 || uuid.trim().isEmpty) {
      throw ArgumentError('Budget plan requires a valid id, UUID, and book.');
    }
    if (currencyCode.toUpperCase() != 'CNY') {
      throw ArgumentError('Budget V2 currently supports CNY only.');
    }
    if (this.role != 'primary' && this.role != 'special') {
      throw ArgumentError('Budget plan role must be primary or special.');
    }
    if (this.endInclusive != null &&
        this.endInclusive!.isBefore(this.anchorStart)) {
      throw ArgumentError('Budget plan end cannot precede its start.');
    }
    if (cadence == BudgetPlanCadenceV2.monthly) {
      final value = monthStartDay;
      if (value == null || value < 1 || value > 28) {
        throw ArgumentError('Monthly start day must be from 1 to 28.');
      }
    } else if (cadence == BudgetPlanCadenceV2.weekly) {
      final value = this.weekStart;
      if (value == null || value < DateTime.monday || value > DateTime.sunday) {
        throw ArgumentError('Week start must be from Monday to Sunday.');
      }
    }
    if (this.role == 'special') {
      if (cadence != BudgetPlanCadenceV2.oneOff ||
          this.endInclusive == null ||
          this.expenseScope.isEmpty) {
        throw ArgumentError(
          'Special tracking requires one_off cadence, an end date, and scope.',
        );
      }
    } else if (cadence == BudgetPlanCadenceV2.oneOff) {
      throw ArgumentError('A one_off plan must use the special role.');
    }
  }

  bool get isPrimary => role == 'primary';
  bool get isSpecial => role == 'special';

  bool covers(DateTime day) {
    final value = _budgetDay(day);
    if (value.isBefore(anchorStart)) {
      return false;
    }
    if (status == BudgetPlanStatusV2.archived && endInclusive == null) {
      return false;
    }
    final end = endInclusive;
    return end == null || !value.isAfter(_budgetDay(end));
  }

  BudgetPlanCycleV2 cycleFor(DateTime day) {
    final value = _budgetDay(day);
    if (cadence == BudgetPlanCadenceV2.oneOff) {
      return BudgetPlanCycleV2(
        planId: id,
        start: anchorStart,
        endExclusive: endInclusive!.add(const Duration(days: 1)),
      );
    }
    if (cadence == BudgetPlanCadenceV2.weekly) {
      final delta = (value.weekday - weekStart! + 7) % 7;
      final start = value.subtract(Duration(days: delta));
      return BudgetPlanCycleV2(
        planId: id,
        start: start,
        endExclusive: start.add(const Duration(days: 7)),
      );
    }
    final anchor = monthStartDay!;
    var start = DateTime(value.year, value.month, anchor);
    if (value.isBefore(start)) {
      start = DateTime(value.year, value.month - 1, anchor);
    }
    return BudgetPlanCycleV2(
      planId: id,
      start: start,
      endExclusive: DateTime(start.year, start.month + 1, anchor),
    );
  }
}

class BudgetPlanCycleV2 {
  final int planId;
  final DateTime start;
  final DateTime endExclusive;

  const BudgetPlanCycleV2({
    required this.planId,
    required this.start,
    required this.endExclusive,
  });

  int get dayCount => endExclusive.difference(start).inDays;
  DateTime get startInclusive => start;
  DateTime get endInclusive => endExclusive.subtract(const Duration(days: 1));
  int get startDayKey => budgetCivilDayKey(start);
  int get endDayKey => budgetCivilDayKey(endInclusive);

  bool contains(DateTime day) {
    final value = _budgetDay(day);
    return !value.isBefore(start) && value.isBefore(endExclusive);
  }
}

class BudgetPlanRevisionV2 {
  final int id;
  final String uuid;
  final int planId;
  final DateTime effectiveCycleStart;
  final DateTime? effectiveToCycleStart;
  final int amountCents;
  final Map<String, int> categoryBudgetsCents;
  final int? monthlyIncomeCents;
  final List<BudgetFixedTemplateV2> fixedTemplates;
  final int? legacySourcePeriodId;
  final int createdMs;
  final int updatedMs;

  BudgetPlanRevisionV2({
    required this.id,
    this.uuid = 'local-revision',
    required this.planId,
    required DateTime effectiveCycleStart,
    this.effectiveToCycleStart,
    required this.amountCents,
    Map<String, int> categoryBudgetsCents = const {},
    this.monthlyIncomeCents,
    List<BudgetFixedTemplateV2> fixedTemplates = const [],
    this.legacySourcePeriodId,
    this.createdMs = 0,
    this.updatedMs = 0,
  })  : effectiveCycleStart = _budgetDay(effectiveCycleStart),
        categoryBudgetsCents = Map.unmodifiable(categoryBudgetsCents),
        fixedTemplates = List.unmodifiable(fixedTemplates) {
    if (id < 0 || planId <= 0 || uuid.trim().isEmpty || amountCents < 0) {
      throw ArgumentError('Invalid budget revision.');
    }
    if (categoryBudgetsCents.values.any((value) => value < 0) ||
        categoryBudgetsCents.values.fold<int>(0, (a, b) => a + b) >
            amountCents) {
      throw ArgumentError('Category budgets must fit inside the total.');
    }
  }

  bool appliesTo(BudgetPlanCycleV2 cycle) {
    if (cycle.planId != planId || cycle.start.isBefore(effectiveCycleStart)) {
      return false;
    }
    final end = effectiveToCycleStart;
    return end == null || cycle.start.isBefore(_budgetDay(end));
  }
}

class BudgetCycleOverrideV2 {
  final int id;
  final String uuid;
  final int planId;
  final DateTime cycleStart;
  final DateTime cycleEndInclusive;
  final int targetAmountCents;
  final Map<String, int>? categoryBudgetsCents;
  final BudgetOverrideIntent inputIntent;
  final int? inputDeltaCents;
  final int createdMs;
  final int updatedMs;

  BudgetCycleOverrideV2({
    required this.id,
    this.uuid = 'local-override',
    required this.planId,
    required DateTime cycleStart,
    DateTime? cycleEndInclusive,
    DateTime? cycleEndExclusive,
    required this.targetAmountCents,
    this.categoryBudgetsCents,
    this.inputIntent = BudgetOverrideIntent.replaceTotal,
    this.inputDeltaCents,
    this.createdMs = 0,
    this.updatedMs = 0,
  })  : cycleStart = _budgetDay(cycleStart),
        cycleEndInclusive = _budgetDay(
          cycleEndInclusive ??
              cycleEndExclusive!.subtract(const Duration(days: 1)),
        ) {
    if (cycleEndInclusive == null && cycleEndExclusive == null) {
      throw ArgumentError('Override requires a cycle end.');
    }
    if (targetAmountCents < 0) {
      throw ArgumentError('Override target cannot be negative.');
    }
    final categories = categoryBudgetsCents;
    if (categories != null &&
        categories.values.fold<int>(0, (a, b) => a + b) > targetAmountCents) {
      throw ArgumentError('Override categories exceed the target.');
    }
  }
}

enum BudgetPlanDayStatusV2 { available, unavailable, conflict }

class BudgetPlanDayResolutionV2 {
  final BudgetPlanDayStatusV2 status;
  final BudgetPlanV2? plan;
  final BudgetPlanCycleV2? cycle;
  final BudgetPlanRevisionV2? revision;
  final BudgetCycleOverrideV2? override;
  final int? plannedCents;
  final Map<String, int> categoryPlannedCents;
  final String? reason;

  const BudgetPlanDayResolutionV2({
    required this.status,
    this.plan,
    this.cycle,
    this.revision,
    this.override,
    this.plannedCents,
    this.categoryPlannedCents = const {},
    this.reason,
  });

  const BudgetPlanDayResolutionV2.unavailable()
      : this(status: BudgetPlanDayStatusV2.unavailable);

  const BudgetPlanDayResolutionV2.conflict(String reason)
      : this(status: BudgetPlanDayStatusV2.conflict, reason: reason);

  int? get cycleTotalCents =>
      override?.targetAmountCents ?? revision?.amountCents;
}

typedef BudgetPlanCadence = BudgetPlanCadenceV2;
typedef BudgetPlan = BudgetPlanV2;
typedef BudgetPlanCycle = BudgetPlanCycleV2;
typedef BudgetPlanRevision = BudgetPlanRevisionV2;
typedef BudgetCycleOverride = BudgetCycleOverrideV2;
typedef BudgetPlanDayResult = BudgetPlanDayResolutionV2;

class BudgetPlanWindowResolutionV2 {
  final BudgetPlanDayStatusV2 status;
  final int? plannedCents;
  final Map<String, int> categoryPlannedCents;
  final Set<int> planIds;
  final String? reason;

  const BudgetPlanWindowResolutionV2({
    required this.status,
    required this.plannedCents,
    required this.categoryPlannedCents,
    required this.planIds,
    this.reason,
  });
}

class BudgetPlanV2Resolver {
  static BudgetPlanDayResolutionV2 resolveDay({
    required DateTime day,
    required int bookId,
    required DateTime knowledgeCutoff,
    required Iterable<BudgetPlanV2> plans,
    required Iterable<BudgetPlanRevisionV2> revisions,
    required Iterable<BudgetCycleOverrideV2> overrides,
  }) {
    final value = _budgetDay(day);
    final candidates = plans
        .where((plan) =>
            plan.bookId == bookId &&
            plan.role == 'primary' &&
            plan.currencyCode.toUpperCase() == 'CNY' &&
            plan.createdMs <= knowledgeCutoff.millisecondsSinceEpoch &&
            plan.covers(value))
        .toList();
    if (candidates.isEmpty) {
      return const BudgetPlanDayResolutionV2(
        status: BudgetPlanDayStatusV2.unavailable,
      );
    }
    if (candidates.length != 1) {
      return const BudgetPlanDayResolutionV2(
        status: BudgetPlanDayStatusV2.conflict,
        reason: 'More than one primary budget plan covers this day.',
      );
    }
    final plan = candidates.single;
    final cycle = plan.cycleFor(value);
    final applicableRevisions = revisions
        .where((revision) =>
            revision.planId == plan.id &&
            revision.createdMs <= knowledgeCutoff.millisecondsSinceEpoch &&
            revision.appliesTo(cycle))
        .toList()
      ..sort((a, b) {
        final effective =
            a.effectiveCycleStart.compareTo(b.effectiveCycleStart);
        return effective != 0 ? effective : a.id.compareTo(b.id);
      });
    if (applicableRevisions.isEmpty) {
      return BudgetPlanDayResolutionV2(
        status: BudgetPlanDayStatusV2.conflict,
        plan: plan,
        cycle: cycle,
        reason: 'The active cycle has no revision.',
      );
    }
    final revision = applicableRevisions.last;
    final sameEffective = applicableRevisions.where((candidate) =>
        candidate.effectiveCycleStart == revision.effectiveCycleStart);
    if (sameEffective.length != 1) {
      return BudgetPlanDayResolutionV2(
        status: BudgetPlanDayStatusV2.conflict,
        plan: plan,
        cycle: cycle,
        reason: 'More than one revision starts on this cycle.',
      );
    }
    final cycleOverrides = overrides
        .where((item) =>
            item.planId == plan.id &&
            item.cycleStart == cycle.start &&
            item.createdMs <= knowledgeCutoff.millisecondsSinceEpoch)
        .toList();
    if (cycleOverrides.length > 1) {
      return BudgetPlanDayResolutionV2(
        status: BudgetPlanDayStatusV2.conflict,
        plan: plan,
        cycle: cycle,
        revision: revision,
        reason: 'More than one override targets this cycle.',
      );
    }
    final cycleOverride = cycleOverrides.firstOrNull;
    final total = cycleOverride?.targetAmountCents ?? revision.amountCents;
    final categories =
        cycleOverride?.categoryBudgetsCents ?? revision.categoryBudgetsCents;
    if (categories.values.fold<int>(0, (a, b) => a + b) > total) {
      return BudgetPlanDayResolutionV2(
        status: BudgetPlanDayStatusV2.conflict,
        plan: plan,
        cycle: cycle,
        revision: revision,
        override: cycleOverride,
        reason: 'Inherited category budgets exceed the cycle target.',
      );
    }
    final offset = value.difference(cycle.start).inDays;
    return BudgetPlanDayResolutionV2(
      status: BudgetPlanDayStatusV2.available,
      plan: plan,
      cycle: cycle,
      revision: revision,
      override: cycleOverride,
      plannedCents: stableBudgetDailyShare(total, cycle.dayCount, offset),
      categoryPlannedCents: {
        for (final entry in categories.entries)
          entry.key: stableBudgetDailyShare(
            entry.value,
            cycle.dayCount,
            offset,
          ),
      },
    );
  }

  static BudgetPlanWindowResolutionV2 resolveWindow({
    required DateTime startInclusive,
    required DateTime endExclusive,
    required int bookId,
    required DateTime knowledgeCutoff,
    required Iterable<BudgetPlanV2> plans,
    required Iterable<BudgetPlanRevisionV2> revisions,
    required Iterable<BudgetCycleOverrideV2> overrides,
  }) {
    final start = _budgetDay(startInclusive);
    final end = _budgetDay(endExclusive);
    var total = 0;
    var any = false;
    final categories = <String, int>{};
    final planIds = <int>{};
    for (var day = start;
        day.isBefore(end);
        day = day.add(const Duration(days: 1))) {
      final result = resolveDay(
        day: day,
        bookId: bookId,
        knowledgeCutoff: knowledgeCutoff,
        plans: plans,
        revisions: revisions,
        overrides: overrides,
      );
      if (result.status == BudgetPlanDayStatusV2.conflict) {
        return BudgetPlanWindowResolutionV2(
          status: BudgetPlanDayStatusV2.conflict,
          plannedCents: null,
          categoryPlannedCents: const {},
          planIds: planIds,
          reason: result.reason,
        );
      }
      if (result.status != BudgetPlanDayStatusV2.available) continue;
      any = true;
      total += result.plannedCents!;
      planIds.add(result.plan!.id);
      for (final entry in result.categoryPlannedCents.entries) {
        categories.update(entry.key, (value) => value + entry.value,
            ifAbsent: () => entry.value);
      }
    }
    return BudgetPlanWindowResolutionV2(
      status: any
          ? BudgetPlanDayStatusV2.available
          : BudgetPlanDayStatusV2.unavailable,
      plannedCents: any ? total : null,
      categoryPlannedCents: Map.unmodifiable(categories),
      planIds: Set.unmodifiable(planIds),
    );
  }
}

class BudgetPlanResolver {
  static BudgetPlanDayResult resolveDay({
    required DateTime day,
    required int bookId,
    required Iterable<BudgetPlan> plans,
    required Iterable<BudgetPlanRevision> revisions,
    required Iterable<BudgetCycleOverride> overrides,
    DateTime? knowledgeCutoff,
  }) =>
      BudgetPlanV2Resolver.resolveDay(
        day: day,
        bookId: bookId,
        knowledgeCutoff: knowledgeCutoff ?? DateTime(9999, 12, 31),
        plans: plans,
        revisions: revisions,
        overrides: overrides,
      );

  static BudgetPlanDayResult preferV2({
    required BudgetPlanDayResult v2,
    required BudgetPlanDayResult legacy,
  }) =>
      v2.status == BudgetPlanDayStatusV2.unavailable ? legacy : v2;
}

int stableBudgetDailyShare(int totalCents, int dayCount, int dayOffset) {
  if (totalCents < 0 ||
      dayCount <= 0 ||
      dayOffset < 0 ||
      dayOffset >= dayCount) {
    throw ArgumentError('Invalid stable daily budget allocation input.');
  }
  final quotient = totalCents ~/ dayCount;
  final remainder = totalCents % dayCount;
  return quotient + (dayOffset < remainder ? 1 : 0);
}
