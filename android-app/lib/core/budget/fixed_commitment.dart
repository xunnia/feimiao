/// Persistent business resolution for one fixed-commitment occurrence.
///
/// Time-dependent states such as [FixedCommitmentDisplayStatus.matchedFuture]
/// and [FixedCommitmentDisplayStatus.overdue] are deliberately not persisted.
enum FixedCommitmentResolutionStatus {
  planned('planned'),
  matched('matched'),
  skipped('skipped'),
  requiresReview('requires_review');

  const FixedCommitmentResolutionStatus(this.storageValue);

  final String storageValue;

  static FixedCommitmentResolutionStatus fromStorage(String value) {
    for (final status in values) {
      if (status.storageValue == value) return status;
    }
    throw FormatException('Unknown fixed commitment status: $value');
  }
}

enum FixedCommitmentReviewReason {
  refundAfterMatch('refund_after_match'),
  ambiguousCandidate('ambiguous_candidate'),
  invalidScope('invalid_scope'),
  amountConflict('amount_conflict');

  const FixedCommitmentReviewReason(this.storageValue);

  final String storageValue;

  static FixedCommitmentReviewReason fromStorage(String value) {
    for (final reason in values) {
      if (reason.storageValue == value) return reason;
    }
    throw FormatException('Unknown fixed commitment review reason: $value');
  }
}

/// Query-time state suitable for display.
enum FixedCommitmentDisplayStatus {
  planned,
  matched,
  matchedFuture,
  overdue,
  skipped,
  requiresReview,
}

enum FixedCommitmentPartialReason {
  overdueCommitment,
  refundAfterMatch,
  ambiguousCandidate,
  invalidScope,
  amountConflict,
  invalidExclusiveLink,
  invalidStoredState,
}

/// One immutable cycle occurrence generated from a revision template.
///
/// Amounts use integer cents. [cycleStart] and [cycleEnd] are inclusive local
/// calendar dates; business-timezone conversion happens before this core model.
class FixedCommitmentOccurrence {
  FixedCommitmentOccurrence({
    this.id,
    required this.planId,
    required this.bookId,
    String currencyCode = 'CNY',
    required this.templateId,
    required this.cycleStart,
    required this.cycleEnd,
    required this.dueDate,
    required this.plannedCents,
    this.resolutionStatus = FixedCommitmentResolutionStatus.planned,
    this.reviewReason,
    this.matchedTransactionFamilyId,
    this.resolvedMs,
  }) : currencyCode = currencyCode.toUpperCase() {
    if (planId <= 0) {
      throw ArgumentError.value(planId, 'planId', 'must be positive');
    }
    if (bookId <= 0) {
      throw ArgumentError.value(bookId, 'bookId', 'must be positive');
    }
    if (templateId.isEmpty) {
      throw ArgumentError.value(templateId, 'templateId', 'must not be empty');
    }
    if (plannedCents < 0) {
      throw ArgumentError.value(
        plannedCents,
        'plannedCents',
        'must not be negative',
      );
    }
    if (_calendarDay(cycleEnd).isBefore(_calendarDay(cycleStart))) {
      throw ArgumentError('cycleEnd must not be before cycleStart');
    }
  }

  final int? id;
  final int planId;
  final int bookId;
  final String currencyCode;
  final String templateId;
  final DateTime cycleStart;
  final DateTime cycleEnd;
  final DateTime dueDate;
  final int plannedCents;
  final FixedCommitmentResolutionStatus resolutionStatus;
  final FixedCommitmentReviewReason? reviewReason;
  final String? matchedTransactionFamilyId;
  final int? resolvedMs;
}

class FixedCommitmentEvaluation {
  const FixedCommitmentEvaluation({
    required this.occurrence,
    required this.fixedActualSpentThroughNowCents,
    required this.fixedReserveNotYetInSpentCents,
    required this.displayStatus,
    required this.isMatchedFuture,
    required this.isOverdue,
    required this.partialReasons,
  });

  final FixedCommitmentOccurrence occurrence;
  final int fixedActualSpentThroughNowCents;
  final int fixedReserveNotYetInSpentCents;
  final FixedCommitmentDisplayStatus displayStatus;
  final bool isMatchedFuture;
  final bool isOverdue;
  final Set<FixedCommitmentPartialReason> partialReasons;

  int get effectiveFixedCostCents =>
      fixedActualSpentThroughNowCents + fixedReserveNotYetInSpentCents;

  bool get isPartial => partialReasons.isNotEmpty;
}

class FixedCommitmentCycleSummary {
  const FixedCommitmentCycleSummary({
    required this.cycleTotalCents,
    required this.totalSpentThroughNowCents,
    required this.fixedActualSpentThroughNowCents,
    required this.fixedReserveNotYetInSpentCents,
    required this.partialReasons,
  });

  final int cycleTotalCents;
  final int totalSpentThroughNowCents;
  final int fixedActualSpentThroughNowCents;
  final int fixedReserveNotYetInSpentCents;
  final Set<FixedCommitmentPartialReason> partialReasons;

  int get effectiveFixedCostCents =>
      fixedActualSpentThroughNowCents + fixedReserveNotYetInSpentCents;

  int get variableSpentThroughNowCents =>
      totalSpentThroughNowCents - fixedActualSpentThroughNowCents;

  int get cycleRemainingCents => cycleTotalCents - totalSpentThroughNowCents;

  /// The reserve, not the whole effective fixed cost, is deducted here.
  /// Fixed actual spending is already part of [totalSpentThroughNowCents].
  int get discretionaryRemainingCents =>
      cycleRemainingCents - fixedReserveNotYetInSpentCents;

  bool get isPartial => partialReasons.isNotEmpty;
}

class FixedCommitmentCalculator {
  FixedCommitmentCalculator._();

  /// Evaluates one occurrence using the statistics contract's mutually
  /// exclusive actual/reserve truth table.
  ///
  /// [exclusiveLinked] means the link has already passed current scope,
  /// currency, cycle, revocation and uniqueness checks. [familyNetCents] is
  /// clamped to zero, matching `A = max(familyNet, 0)`.
  static FixedCommitmentEvaluation evaluate({
    required FixedCommitmentOccurrence occurrence,
    required DateTime asOf,
    required bool exclusiveLinked,
    required int familyNetCents,
    required bool attributionOccurred,
    required bool refundAfterMatchReview,
  }) {
    final skipped =
        occurrence.resolutionStatus == FixedCommitmentResolutionStatus.skipped;
    final planned = occurrence.plannedCents;
    final actualFamilyNet = familyNetCents < 0 ? 0 : familyNetCents;

    late final int actual;
    late final int reserve;
    if (skipped) {
      actual = 0;
      reserve = 0;
    } else if (!exclusiveLinked) {
      actual = 0;
      reserve = planned;
    } else if (!attributionOccurred) {
      actual = 0;
      reserve = refundAfterMatchReview
          ? _max(planned, actualFamilyNet)
          : actualFamilyNet;
    } else {
      actual = actualFamilyNet;
      reserve = refundAfterMatchReview ? _max(planned - actualFamilyNet, 0) : 0;
    }

    final isMatchedFuture = !skipped && exclusiveLinked && !attributionOccurred;
    final isOverdue = !skipped &&
        !exclusiveLinked &&
        _calendarDay(asOf).isAfter(_calendarDay(occurrence.dueDate));
    final partialReasons = <FixedCommitmentPartialReason>{};

    if (isOverdue) {
      partialReasons.add(FixedCommitmentPartialReason.overdueCommitment);
    }
    if (refundAfterMatchReview) {
      partialReasons.add(FixedCommitmentPartialReason.refundAfterMatch);
    }
    _addPersistedReviewReason(occurrence.reviewReason, partialReasons);

    final stateIssues = FixedCommitmentLinkValidator.validateStoredState(
      occurrence,
    );
    if (stateIssues.isNotEmpty ||
        refundAfterMatchReview !=
            (occurrence.reviewReason ==
                FixedCommitmentReviewReason.refundAfterMatch)) {
      partialReasons.add(FixedCommitmentPartialReason.invalidStoredState);
    }
    if (!skipped &&
        !exclusiveLinked &&
        occurrence.resolutionStatus ==
            FixedCommitmentResolutionStatus.matched) {
      partialReasons.add(FixedCommitmentPartialReason.invalidExclusiveLink);
    }

    final displayStatus = _displayStatus(
      occurrence: occurrence,
      exclusiveLinked: exclusiveLinked,
      isMatchedFuture: isMatchedFuture,
      isOverdue: isOverdue,
    );

    return FixedCommitmentEvaluation(
      occurrence: occurrence,
      fixedActualSpentThroughNowCents: actual,
      fixedReserveNotYetInSpentCents: reserve,
      displayStatus: displayStatus,
      isMatchedFuture: isMatchedFuture,
      isOverdue: isOverdue,
      partialReasons: Set.unmodifiable(partialReasons),
    );
  }

  static FixedCommitmentCycleSummary summarizeCycle({
    required int cycleTotalCents,
    required int totalSpentThroughNowCents,
    required Iterable<FixedCommitmentEvaluation> occurrences,
  }) {
    if (cycleTotalCents < 0) {
      throw ArgumentError.value(
        cycleTotalCents,
        'cycleTotalCents',
        'must not be negative',
      );
    }
    if (totalSpentThroughNowCents < 0) {
      throw ArgumentError.value(
        totalSpentThroughNowCents,
        'totalSpentThroughNowCents',
        'must not be negative',
      );
    }

    var actual = 0;
    var reserve = 0;
    final partialReasons = <FixedCommitmentPartialReason>{};
    for (final occurrence in occurrences) {
      actual += occurrence.fixedActualSpentThroughNowCents;
      reserve += occurrence.fixedReserveNotYetInSpentCents;
      partialReasons.addAll(occurrence.partialReasons);
    }

    return FixedCommitmentCycleSummary(
      cycleTotalCents: cycleTotalCents,
      totalSpentThroughNowCents: totalSpentThroughNowCents,
      fixedActualSpentThroughNowCents: actual,
      fixedReserveNotYetInSpentCents: reserve,
      partialReasons: Set.unmodifiable(partialReasons),
    );
  }

  static FixedCommitmentDisplayStatus _displayStatus({
    required FixedCommitmentOccurrence occurrence,
    required bool exclusiveLinked,
    required bool isMatchedFuture,
    required bool isOverdue,
  }) {
    switch (occurrence.resolutionStatus) {
      case FixedCommitmentResolutionStatus.skipped:
        return FixedCommitmentDisplayStatus.skipped;
      case FixedCommitmentResolutionStatus.requiresReview:
        return FixedCommitmentDisplayStatus.requiresReview;
      case FixedCommitmentResolutionStatus.planned:
      case FixedCommitmentResolutionStatus.matched:
        if (isMatchedFuture) {
          return FixedCommitmentDisplayStatus.matchedFuture;
        }
        if (isOverdue) return FixedCommitmentDisplayStatus.overdue;
        return exclusiveLinked
            ? FixedCommitmentDisplayStatus.matched
            : FixedCommitmentDisplayStatus.planned;
    }
  }

  static void _addPersistedReviewReason(
    FixedCommitmentReviewReason? reason,
    Set<FixedCommitmentPartialReason> target,
  ) {
    switch (reason) {
      case FixedCommitmentReviewReason.refundAfterMatch:
        target.add(FixedCommitmentPartialReason.refundAfterMatch);
        break;
      case FixedCommitmentReviewReason.ambiguousCandidate:
        target.add(FixedCommitmentPartialReason.ambiguousCandidate);
        break;
      case FixedCommitmentReviewReason.invalidScope:
        target.add(FixedCommitmentPartialReason.invalidScope);
        break;
      case FixedCommitmentReviewReason.amountConflict:
        target.add(FixedCommitmentPartialReason.amountConflict);
        break;
      case null:
        break;
    }
  }
}

class FixedCommitmentFamilyCandidate {
  const FixedCommitmentFamilyCandidate({
    required this.familyId,
    required this.bookId,
    this.currencyCode = 'CNY',
    required this.attributionDate,
    this.isRevoked = false,
  });

  final String familyId;
  final int bookId;
  final String currencyCode;
  final DateTime attributionDate;
  final bool isRevoked;
}

enum FixedCommitmentLinkIssue {
  skippedOccurrence,
  occurrenceLinkedToAnotherFamily,
  familyAlreadyLinkedInPlan,
  revokedFamily,
  bookScopeMismatch,
  currencyMismatch,
  attributionOutsideCycle,
}

class FixedCommitmentLinkValidation {
  const FixedCommitmentLinkValidation(this.issues);

  final Set<FixedCommitmentLinkIssue> issues;

  bool get isValid => issues.isEmpty;
}

enum FixedCommitmentStoredStateIssue {
  reviewReasonMissing,
  reviewReasonUnexpected,
  matchedLinkMissing,
  refundReviewLinkMissing,
  linkMustBeCleared,
}

class FixedCommitmentLinkValidator {
  FixedCommitmentLinkValidator._();

  static FixedCommitmentLinkValidation validateLink({
    required FixedCommitmentOccurrence occurrence,
    required FixedCommitmentFamilyCandidate candidate,
    required Iterable<FixedCommitmentOccurrence> existingOccurrences,
  }) {
    final issues = <FixedCommitmentLinkIssue>{};
    if (occurrence.resolutionStatus ==
        FixedCommitmentResolutionStatus.skipped) {
      issues.add(FixedCommitmentLinkIssue.skippedOccurrence);
    }
    final currentFamily = occurrence.matchedTransactionFamilyId;
    if (currentFamily != null && currentFamily != candidate.familyId) {
      issues.add(FixedCommitmentLinkIssue.occurrenceLinkedToAnotherFamily);
    }
    if (!isFamilyUniqueWithinPlan(
      planId: occurrence.planId,
      familyId: candidate.familyId,
      occurrences: existingOccurrences,
      excludingOccurrence: occurrence,
    )) {
      issues.add(FixedCommitmentLinkIssue.familyAlreadyLinkedInPlan);
    }
    if (candidate.isRevoked) {
      issues.add(FixedCommitmentLinkIssue.revokedFamily);
    }
    if (candidate.bookId != occurrence.bookId) {
      issues.add(FixedCommitmentLinkIssue.bookScopeMismatch);
    }
    if (candidate.currencyCode.toUpperCase() != occurrence.currencyCode) {
      issues.add(FixedCommitmentLinkIssue.currencyMismatch);
    }
    if (!attributionFallsWithinCycle(
      attributionDate: candidate.attributionDate,
      cycleStart: occurrence.cycleStart,
      cycleEnd: occurrence.cycleEnd,
    )) {
      issues.add(FixedCommitmentLinkIssue.attributionOutsideCycle);
    }

    return FixedCommitmentLinkValidation(Set.unmodifiable(issues));
  }

  static bool isFamilyUniqueWithinPlan({
    required int planId,
    required String familyId,
    required Iterable<FixedCommitmentOccurrence> occurrences,
    FixedCommitmentOccurrence? excludingOccurrence,
  }) {
    for (final occurrence in occurrences) {
      if (identical(occurrence, excludingOccurrence)) continue;
      if (excludingOccurrence?.id != null &&
          occurrence.id == excludingOccurrence!.id) {
        continue;
      }
      if (occurrence.planId == planId &&
          occurrence.matchedTransactionFamilyId == familyId) {
        return false;
      }
    }
    return true;
  }

  static bool attributionFallsWithinCycle({
    required DateTime attributionDate,
    required DateTime cycleStart,
    required DateTime cycleEnd,
  }) {
    final date = _calendarDay(attributionDate);
    final start = _calendarDay(cycleStart);
    final end = _calendarDay(cycleEnd);
    return !date.isBefore(start) && !date.isAfter(end);
  }

  static Set<FixedCommitmentStoredStateIssue> validateStoredState(
    FixedCommitmentOccurrence occurrence,
  ) {
    final issues = <FixedCommitmentStoredStateIssue>{};
    final link = occurrence.matchedTransactionFamilyId;
    final reason = occurrence.reviewReason;

    switch (occurrence.resolutionStatus) {
      case FixedCommitmentResolutionStatus.planned:
        if (link != null) {
          issues.add(FixedCommitmentStoredStateIssue.linkMustBeCleared);
        }
        if (reason != null) {
          issues.add(FixedCommitmentStoredStateIssue.reviewReasonUnexpected);
        }
        break;
      case FixedCommitmentResolutionStatus.matched:
        if (link == null) {
          issues.add(FixedCommitmentStoredStateIssue.matchedLinkMissing);
        }
        if (reason != null) {
          issues.add(FixedCommitmentStoredStateIssue.reviewReasonUnexpected);
        }
        break;
      case FixedCommitmentResolutionStatus.skipped:
        if (link != null) {
          issues.add(FixedCommitmentStoredStateIssue.linkMustBeCleared);
        }
        if (reason != null) {
          issues.add(FixedCommitmentStoredStateIssue.reviewReasonUnexpected);
        }
        break;
      case FixedCommitmentResolutionStatus.requiresReview:
        if (reason == null) {
          issues.add(FixedCommitmentStoredStateIssue.reviewReasonMissing);
        } else if (reason == FixedCommitmentReviewReason.refundAfterMatch) {
          if (link == null) {
            issues.add(FixedCommitmentStoredStateIssue.refundReviewLinkMissing);
          }
        } else if (link != null) {
          issues.add(FixedCommitmentStoredStateIssue.linkMustBeCleared);
        }
        break;
    }

    return Set.unmodifiable(issues);
  }
}

int _max(int a, int b) => a > b ? a : b;

DateTime _calendarDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);
