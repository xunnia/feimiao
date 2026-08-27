import XCTest
@testable import QingJiCore

final class FixedCommitmentTests: XCTestCase {
    func testUnmatchedOccurrenceReservesPlannedAmountAndBecomesOverdue() {
        let occurrence = FixedCommitmentOccurrence(
            id: UUID(),
            planID: UUID(),
            bookID: UUID(),
            templateID: "rent",
            cycleStart: Date(timeIntervalSince1970: 1_700_000_000),
            cycleEnd: Date(timeIntervalSince1970: 1_700_086_400),
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            plannedCents: 320_000
        )
        let evaluation = FixedCommitmentCalculator.evaluate(
            occurrence: occurrence,
            asOf: Date(timeIntervalSince1970: 1_700_172_800),
            exclusiveLinked: false,
            familyNetCents: 0,
            attributionOccurred: false,
            refundAfterMatchReview: false
        )

        XCTAssertEqual(evaluation.fixedActualSpentThroughNowCents, 0)
        XCTAssertEqual(evaluation.fixedReserveNotYetInSpentCents, 320_000)
        XCTAssertEqual(evaluation.displayStatus, .overdue)
        XCTAssertTrue(evaluation.partialReasons.contains(.overdueCommitment))
    }

    func testMatchedRefundReviewKeepsRemainingReserve() {
        let occurrence = FixedCommitmentOccurrence(
            id: UUID(),
            planID: UUID(),
            bookID: UUID(),
            templateID: "rent",
            cycleStart: Date(timeIntervalSince1970: 1_700_000_000),
            cycleEnd: Date(timeIntervalSince1970: 1_700_086_400),
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            plannedCents: 100_00,
            resolutionStatus: .matched,
            matchedTransactionFamilyID: "family-1",
            resolvedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let evaluation = FixedCommitmentCalculator.evaluate(
            occurrence: occurrence,
            asOf: Date(timeIntervalSince1970: 1_700_043_200),
            exclusiveLinked: true,
            familyNetCents: 7_500,
            attributionOccurred: true,
            refundAfterMatchReview: true
        )

        XCTAssertEqual(evaluation.fixedActualSpentThroughNowCents, 7_500)
        XCTAssertEqual(evaluation.fixedReserveNotYetInSpentCents, 2_500)
        XCTAssertTrue(evaluation.partialReasons.contains(.refundAfterMatch))
    }

    func testLinkValidatorPreventsUsingOneFamilyTwice() {
        let planID = UUID()
        let bookID = UUID()
        let familyID = "family-1"
        let first = FixedCommitmentOccurrence(
            id: UUID(),
            planID: planID,
            bookID: bookID,
            templateID: "rent",
            cycleStart: Date(timeIntervalSince1970: 1_700_000_000),
            cycleEnd: Date(timeIntervalSince1970: 1_700_086_400),
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            plannedCents: 100,
            resolutionStatus: .matched,
            matchedTransactionFamilyID: familyID
        )
        let second = FixedCommitmentOccurrence(
            id: UUID(),
            planID: planID,
            bookID: bookID,
            templateID: "rent",
            cycleStart: first.cycleStart,
            cycleEnd: first.cycleEnd,
            dueDate: first.dueDate,
            plannedCents: 100
        )
        let result = FixedCommitmentLinkValidator.validateLink(
            occurrence: second,
            candidate: FixedCommitmentFamilyCandidate(
                familyID: familyID,
                bookID: bookID,
                attributionDate: first.cycleStart
            ),
            existingOccurrences: [first, second]
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains(.familyAlreadyLinkedInPlan))
    }
}
