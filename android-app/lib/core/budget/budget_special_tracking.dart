import 'budget_plan_v2.dart';

DateTime _specialDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// One expense family as seen by special tracking.
///
/// [netAmountCents] is already the family net at the requested knowledge
/// cutoff. The caller remains the single owner of attached-refund replay;
/// special tracking only applies its date and category/tag scope.
class BudgetSpecialExpenseFamilyInput {
  final String id;
  final int bookId;
  final String currencyCode;
  final DateTime attributionDate;
  final DateTime createdAt;
  final int netAmountCents;
  final bool countsInBudget;
  final String categoryKey;
  final Set<int> tagIds;

  BudgetSpecialExpenseFamilyInput({
    required String id,
    required this.bookId,
    String currencyCode = 'CNY',
    required DateTime attributionDate,
    required this.createdAt,
    required this.netAmountCents,
    this.countsInBudget = true,
    String categoryKey = '',
    Iterable<int> tagIds = const [],
  })  : id = id.trim(),
        currencyCode = currencyCode.trim().toUpperCase(),
        attributionDate = _specialDay(attributionDate),
        categoryKey = categoryKey.trim(),
        tagIds = Set.unmodifiable(tagIds.toSet()) {
    if (this.id.isEmpty || bookId <= 0 || this.currencyCode.isEmpty) {
      throw ArgumentError('Special tracking family identity is invalid.');
    }
    if (netAmountCents < 0) {
      throw ArgumentError('Special tracking family net cannot be negative.');
    }
    if (this.tagIds.any((value) => value <= 0)) {
      throw ArgumentError('Special tracking family tag IDs must be positive.');
    }
  }
}

enum BudgetSpecialResultStatus { available, conflict }

enum BudgetSpecialLifecycleStatus {
  upcoming,
  inProgress,
  ended,
  archived,
}

class BudgetSpecialCategoryResult {
  final String categoryKey;
  final int plannedCents;
  final int spentCents;

  const BudgetSpecialCategoryResult({
    required this.categoryKey,
    required this.plannedCents,
    required this.spentCents,
  });

  int get remainingCents => plannedCents - spentCents;
  double? get progress => plannedCents > 0 ? spentCents / plannedCents : null;
}

/// A single special tracker result. Results are deliberately never summed.
class BudgetSpecialTrackingResult {
  final BudgetPlanV2 plan;
  final BudgetPlanRevisionV2? revision;
  final BudgetSpecialResultStatus status;
  final String? reason;
  final BudgetSpecialLifecycleStatus lifecycleStatus;
  final int? totalCents;
  final int? spentCents;
  final int? remainingCents;
  final int matchedFamilyCount;
  final int excludedForeignFamilyCount;
  final List<BudgetSpecialCategoryResult> categoryResults;

  BudgetSpecialTrackingResult({
    required this.plan,
    required this.revision,
    required this.status,
    required this.reason,
    required this.lifecycleStatus,
    required this.totalCents,
    required this.spentCents,
    required this.remainingCents,
    required this.matchedFamilyCount,
    required this.excludedForeignFamilyCount,
    Iterable<BudgetSpecialCategoryResult> categoryResults = const [],
  }) : categoryResults = List.unmodifiable(categoryResults);

  DateTime get startInclusive => plan.anchorStart;
  DateTime get endInclusive => plan.endInclusive!;
  DateTime get endExclusive => endInclusive.add(const Duration(days: 1));
  double? get progress =>
      totalCents != null && totalCents! > 0 && spentCents != null
          ? spentCents! / totalCents!
          : null;
  bool get isOverBudget =>
      totalCents != null && spentCents != null && spentCents! > totalCents!;
  bool get isNearLimit =>
      totalCents != null &&
      totalCents! > 0 &&
      spentCents != null &&
      spentCents! <= totalCents! &&
      spentCents! * 100 >= totalCents! * 80;
}

class BudgetSpecialTrackingResolver {
  BudgetSpecialTrackingResolver._();

  /// Resolves every special plan intersecting [windowStartInclusive,
  /// windowEndExclusive]. Each result always uses the special plan's complete
  /// one-off date range; the browse window selects relevant trackers but never
  /// prorates their total.
  static List<BudgetSpecialTrackingResult> resolveWindow({
    required DateTime windowStartInclusive,
    required DateTime windowEndExclusive,
    required int bookId,
    required DateTime asOf,
    required DateTime knowledgeCutoff,
    required Iterable<BudgetPlanV2> plans,
    required Iterable<BudgetPlanRevisionV2> revisions,
    required Iterable<BudgetSpecialExpenseFamilyInput> expenseFamilies,
    String currencyCode = 'CNY',
    bool includeArchived = false,
  }) {
    final windowStart = _specialDay(windowStartInclusive);
    final windowEnd = _specialDay(windowEndExclusive);
    if (bookId <= 0 || !windowStart.isBefore(windowEnd)) {
      throw ArgumentError('Special tracking requires a valid book and window.');
    }
    final expectedCurrency = currencyCode.trim().toUpperCase();
    if (expectedCurrency.isEmpty) {
      throw ArgumentError('Special tracking currency cannot be empty.');
    }
    final cutoffMs = knowledgeCutoff.millisecondsSinceEpoch;
    final candidates = plans.map((plan) {
      if (plan.status == BudgetPlanStatusV2.archived &&
          plan.updatedMs > cutoffMs) {
        return BudgetPlanV2(
          id: plan.id,
          uuid: plan.uuid,
          bookId: plan.bookId,
          currencyCode: plan.currencyCode,
          timezone: plan.timezone,
          name: plan.name,
          role: plan.role,
          cadence: plan.cadence,
          anchorStart: plan.anchorStart,
          monthStartDay: plan.monthStartDay,
          weekStart: plan.weekStart,
          endInclusive: plan.endInclusive,
          expenseScope: plan.expenseScope,
          status: BudgetPlanStatusV2.active,
          createdMs: plan.createdMs,
          updatedMs: plan.updatedMs,
        );
      }
      return plan;
    }).where((plan) {
      if (!plan.isSpecial ||
          plan.bookId != bookId ||
          plan.currencyCode.toUpperCase() != expectedCurrency ||
          plan.createdMs > cutoffMs ||
          (!includeArchived && plan.status == BudgetPlanStatusV2.archived)) {
        return false;
      }
      final specialEnd = plan.endInclusive!.add(const Duration(days: 1));
      return plan.anchorStart.isBefore(windowEnd) &&
          specialEnd.isAfter(windowStart);
    }).toList()
      ..sort((left, right) {
        final start = left.anchorStart.compareTo(right.anchorStart);
        return start != 0 ? start : left.id.compareTo(right.id);
      });
    final revisionList = List<BudgetPlanRevisionV2>.unmodifiable(revisions);
    final familyList =
        List<BudgetSpecialExpenseFamilyInput>.unmodifiable(expenseFamilies);
    return List.unmodifiable([
      for (final plan in candidates)
        resolvePlan(
          plan: plan,
          asOf: asOf,
          knowledgeCutoff: knowledgeCutoff,
          revisions: revisionList,
          expenseFamilies: familyList,
        ),
    ]);
  }

  static BudgetSpecialTrackingResult resolvePlan({
    required BudgetPlanV2 plan,
    required DateTime asOf,
    required DateTime knowledgeCutoff,
    required Iterable<BudgetPlanRevisionV2> revisions,
    required Iterable<BudgetSpecialExpenseFamilyInput> expenseFamilies,
  }) {
    if (!plan.isSpecial || plan.cadence != BudgetPlanCadenceV2.oneOff) {
      throw ArgumentError('Special tracking can only resolve special plans.');
    }
    final lifecycle = _lifecycle(plan, asOf);
    final cycle = plan.cycleFor(plan.anchorStart);
    final applicableRevisions = revisions
        .where((revision) =>
            revision.planId == plan.id &&
            revision.createdMs <= knowledgeCutoff.millisecondsSinceEpoch &&
            revision.appliesTo(cycle))
        .toList()
      ..sort((left, right) {
        final effective =
            left.effectiveCycleStart.compareTo(right.effectiveCycleStart);
        return effective != 0 ? effective : left.id.compareTo(right.id);
      });
    if (applicableRevisions.isEmpty) {
      return _conflict(
        plan: plan,
        lifecycle: lifecycle,
        reason: 'The special tracking plan has no applicable revision.',
      );
    }
    final revision = applicableRevisions.last;
    final sameEffective = applicableRevisions.where((candidate) =>
        candidate.effectiveCycleStart == revision.effectiveCycleStart);
    if (sameEffective.length != 1) {
      return _conflict(
        plan: plan,
        lifecycle: lifecycle,
        reason: 'More than one special revision starts on the same date.',
      );
    }

    var spent = 0;
    var matchedCount = 0;
    var excludedForeignCount = 0;
    final categorySpent = <String, int>{};
    for (final family in expenseFamilies) {
      if (family.bookId != plan.bookId ||
          !family.countsInBudget ||
          family.createdAt.isAfter(knowledgeCutoff) ||
          family.attributionDate.isBefore(plan.anchorStart) ||
          family.attributionDate.isAfter(plan.endInclusive!) ||
          !plan.expenseScope.matches(
            categoryKey: family.categoryKey,
            familyTagIds: family.tagIds,
          )) {
        continue;
      }
      if (family.currencyCode != plan.currencyCode.toUpperCase()) {
        excludedForeignCount += 1;
        continue;
      }
      spent += family.netAmountCents;
      matchedCount += 1;
      if (family.categoryKey.isNotEmpty) {
        categorySpent.update(
          family.categoryKey,
          (value) => value + family.netAmountCents,
          ifAbsent: () => family.netAmountCents,
        );
      }
    }
    final categoryKeys = {
      ...revision.categoryBudgetsCents.keys,
      ...categorySpent.keys,
    }.toList()
      ..sort();
    return BudgetSpecialTrackingResult(
      plan: plan,
      revision: revision,
      status: BudgetSpecialResultStatus.available,
      reason: null,
      lifecycleStatus: lifecycle,
      totalCents: revision.amountCents,
      spentCents: spent,
      remainingCents: revision.amountCents - spent,
      matchedFamilyCount: matchedCount,
      excludedForeignFamilyCount: excludedForeignCount,
      categoryResults: [
        for (final key in categoryKeys)
          BudgetSpecialCategoryResult(
            categoryKey: key,
            plannedCents: revision.categoryBudgetsCents[key] ?? 0,
            spentCents: categorySpent[key] ?? 0,
          ),
      ],
    );
  }

  static BudgetSpecialTrackingResult _conflict({
    required BudgetPlanV2 plan,
    required BudgetSpecialLifecycleStatus lifecycle,
    required String reason,
  }) =>
      BudgetSpecialTrackingResult(
        plan: plan,
        revision: null,
        status: BudgetSpecialResultStatus.conflict,
        reason: reason,
        lifecycleStatus: lifecycle,
        totalCents: null,
        spentCents: null,
        remainingCents: null,
        matchedFamilyCount: 0,
        excludedForeignFamilyCount: 0,
      );

  static BudgetSpecialLifecycleStatus _lifecycle(
    BudgetPlanV2 plan,
    DateTime asOf,
  ) {
    if (plan.status == BudgetPlanStatusV2.archived) {
      return BudgetSpecialLifecycleStatus.archived;
    }
    final day = _specialDay(asOf);
    if (day.isBefore(plan.anchorStart)) {
      return BudgetSpecialLifecycleStatus.upcoming;
    }
    if (day.isAfter(plan.endInclusive!)) {
      return BudgetSpecialLifecycleStatus.ended;
    }
    return BudgetSpecialLifecycleStatus.inProgress;
  }
}
