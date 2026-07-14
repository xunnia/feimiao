import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/budget/fixed_commitment.dart';

FixedCommitmentOccurrence occurrence({
  int? id,
  int planId = 1,
  FixedCommitmentResolutionStatus status =
      FixedCommitmentResolutionStatus.planned,
  FixedCommitmentReviewReason? reason,
  String? familyId,
}) =>
    FixedCommitmentOccurrence(
      id: id,
      planId: planId,
      bookId: 7,
      templateId: 'rent',
      cycleStart: DateTime(2026, 7, 1),
      cycleEnd: DateTime(2026, 7, 31),
      dueDate: DateTime(2026, 7, 5),
      plannedCents: 10000,
      resolutionStatus: status,
      reviewReason: reason,
      matchedTransactionFamilyId: familyId,
    );

FixedCommitmentEvaluation evaluate(
  FixedCommitmentOccurrence value, {
  bool linked = false,
  int net = 0,
  bool occurred = false,
  bool refundReview = false,
  DateTime? asOf,
}) =>
    FixedCommitmentCalculator.evaluate(
      occurrence: value,
      asOf: asOf ?? DateTime(2026, 7, 4),
      exclusiveLinked: linked,
      familyNetCents: net,
      attributionOccurred: occurred,
      refundAfterMatchReview: refundReview,
    );

void main() {
  group('fixed commitment truth table', () {
    test('unmatched and overdue occurrences keep the full planned reserve', () {
      final planned = evaluate(occurrence());
      final overdue = evaluate(
        occurrence(),
        asOf: DateTime(2026, 7, 6),
      );

      expect(planned.fixedActualSpentThroughNowCents, 0);
      expect(planned.fixedReserveNotYetInSpentCents, 10000);
      expect(planned.displayStatus, FixedCommitmentDisplayStatus.planned);
      expect(overdue.fixedReserveNotYetInSpentCents, 10000);
      expect(overdue.isOverdue, isTrue);
      expect(overdue.isPartial, isTrue);
    });

    test('skipped releases both actual and reserve', () {
      final result = evaluate(
        occurrence(status: FixedCommitmentResolutionStatus.skipped),
      );
      expect(result.fixedActualSpentThroughNowCents, 0);
      expect(result.fixedReserveNotYetInSpentCents, 0);
      expect(result.displayStatus, FixedCommitmentDisplayStatus.skipped);
    });

    test('matched future stays reserved, occurred match becomes actual', () {
      final value = occurrence(
        status: FixedCommitmentResolutionStatus.matched,
        familyId: 'family-1',
      );
      final future = evaluate(value, linked: true, net: 8000);
      final occurred = evaluate(
        value,
        linked: true,
        net: 8000,
        occurred: true,
      );

      expect(future.fixedActualSpentThroughNowCents, 0);
      expect(future.fixedReserveNotYetInSpentCents, 8000);
      expect(future.isMatchedFuture, isTrue);
      expect(future.displayStatus, FixedCommitmentDisplayStatus.matchedFuture);
      expect(occurred.fixedActualSpentThroughNowCents, 8000);
      expect(occurred.fixedReserveNotYetInSpentCents, 0);
    });

    test('partial and full refunds restore the missing planned reserve', () {
      final value = occurrence(
        status: FixedCommitmentResolutionStatus.requiresReview,
        reason: FixedCommitmentReviewReason.refundAfterMatch,
        familyId: 'family-1',
      );
      final partial = evaluate(
        value,
        linked: true,
        net: 6000,
        occurred: true,
        refundReview: true,
      );
      final full = evaluate(
        value,
        linked: true,
        net: 0,
        occurred: true,
        refundReview: true,
      );
      final future = evaluate(
        value,
        linked: true,
        net: 12000,
        refundReview: true,
      );

      expect(partial.fixedActualSpentThroughNowCents, 6000);
      expect(partial.fixedReserveNotYetInSpentCents, 4000);
      expect(full.fixedActualSpentThroughNowCents, 0);
      expect(full.fixedReserveNotYetInSpentCents, 10000);
      expect(future.fixedActualSpentThroughNowCents, 0);
      expect(future.fixedReserveNotYetInSpentCents, 12000);
    });

    test('invalid exclusive link falls back to full planned reserve', () {
      final result = evaluate(
        occurrence(
          status: FixedCommitmentResolutionStatus.matched,
          familyId: 'stale-family',
        ),
        linked: false,
        net: 9000,
      );
      expect(result.fixedActualSpentThroughNowCents, 0);
      expect(result.fixedReserveNotYetInSpentCents, 10000);
      expect(
        result.partialReasons,
        contains(FixedCommitmentPartialReason.invalidExclusiveLink),
      );
    });
  });

  test('cycle discretionary remaining subtracts reserve exactly once', () {
    final fixed = evaluate(
      occurrence(
        status: FixedCommitmentResolutionStatus.requiresReview,
        reason: FixedCommitmentReviewReason.refundAfterMatch,
        familyId: 'family-1',
      ),
      linked: true,
      net: 6000,
      occurred: true,
      refundReview: true,
    );
    final summary = FixedCommitmentCalculator.summarizeCycle(
      cycleTotalCents: 100000,
      totalSpentThroughNowCents: 30000,
      occurrences: [fixed],
    );

    expect(summary.cycleRemainingCents, 70000);
    expect(summary.fixedActualSpentThroughNowCents, 6000);
    expect(summary.fixedReserveNotYetInSpentCents, 4000);
    expect(summary.discretionaryRemainingCents, 66000);
    expect(
      summary.discretionaryRemainingCents,
      summary.cycleTotalCents -
          summary.variableSpentThroughNowCents -
          summary.effectiveFixedCostCents,
    );
  });

  group('link validation', () {
    test('same family is unique within a plan but may be used by another plan',
        () {
      final existing = occurrence(
        id: 1,
        status: FixedCommitmentResolutionStatus.matched,
        familyId: 'family-1',
      );
      expect(
        FixedCommitmentLinkValidator.isFamilyUniqueWithinPlan(
          planId: 1,
          familyId: 'family-1',
          occurrences: [existing],
        ),
        isFalse,
      );
      expect(
        FixedCommitmentLinkValidator.isFamilyUniqueWithinPlan(
          planId: 2,
          familyId: 'family-1',
          occurrences: [existing],
        ),
        isTrue,
      );
    });

    test('cycle boundaries are inclusive and cross-cycle links are rejected',
        () {
      expect(
        FixedCommitmentLinkValidator.attributionFallsWithinCycle(
          attributionDate: DateTime(2026, 7, 1, 23),
          cycleStart: DateTime(2026, 7, 1),
          cycleEnd: DateTime(2026, 7, 31),
        ),
        isTrue,
      );
      final validation = FixedCommitmentLinkValidator.validateLink(
        occurrence: occurrence(),
        candidate: FixedCommitmentFamilyCandidate(
          familyId: 'august-rent',
          bookId: 7,
          attributionDate: DateTime(2026, 8, 1),
        ),
        existingOccurrences: const [],
      );
      expect(validation.isValid, isFalse);
      expect(
        validation.issues,
        contains(FixedCommitmentLinkIssue.attributionOutsideCycle),
      );
    });
  });
}
