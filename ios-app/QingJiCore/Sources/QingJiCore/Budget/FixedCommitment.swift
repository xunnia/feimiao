import Foundation

public enum FixedCommitmentResolutionStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case planned
    case matched
    case skipped
    case requiresReview = "requires_review"
}

public enum FixedCommitmentReviewReason: String, Codable, CaseIterable, Hashable, Sendable {
    case refundAfterMatch = "refund_after_match"
    case ambiguousCandidate = "ambiguous_candidate"
    case invalidScope = "invalid_scope"
    case amountConflict = "amount_conflict"
}

public enum FixedCommitmentDisplayStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case planned
    case matched
    case matchedFuture = "matched_future"
    case overdue
    case skipped
    case requiresReview = "requires_review"
}

public enum FixedCommitmentPartialReason: String, Codable, CaseIterable, Hashable, Sendable {
    case overdueCommitment = "overdue_commitment"
    case refundAfterMatch = "refund_after_match"
    case ambiguousCandidate = "ambiguous_candidate"
    case invalidScope = "invalid_scope"
    case amountConflict = "amount_conflict"
    case invalidExclusiveLink = "invalid_exclusive_link"
    case invalidStoredState = "invalid_stored_state"
}

/// 一个 revision 模板在具体预算周期中的不可变 occurrence。
public struct FixedCommitmentOccurrence: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let planID: UUID
    public let bookID: UUID
    public let currencyCode: String
    public let templateID: String
    public let cycleStart: Date
    public let cycleEnd: Date
    public let dueDate: Date
    public let plannedCents: Int
    public let resolutionStatus: FixedCommitmentResolutionStatus
    public let reviewReason: FixedCommitmentReviewReason?
    public let matchedTransactionFamilyID: String?
    public let resolvedAt: Date?

    public init(
        id: UUID,
        planID: UUID,
        bookID: UUID,
        currencyCode: String = "CNY",
        templateID: String,
        cycleStart: Date,
        cycleEnd: Date,
        dueDate: Date,
        plannedCents: Int,
        resolutionStatus: FixedCommitmentResolutionStatus = .planned,
        reviewReason: FixedCommitmentReviewReason? = nil,
        matchedTransactionFamilyID: String? = nil,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.planID = planID
        self.bookID = bookID
        self.currencyCode = currencyCode.uppercased()
        self.templateID = templateID
        self.cycleStart = Calendar.current.startOfDay(for: cycleStart)
        self.cycleEnd = Calendar.current.startOfDay(for: cycleEnd)
        self.dueDate = Calendar.current.startOfDay(for: dueDate)
        self.plannedCents = max(plannedCents, 0)
        self.resolutionStatus = resolutionStatus
        self.reviewReason = reviewReason
        self.matchedTransactionFamilyID = matchedTransactionFamilyID
        self.resolvedAt = resolvedAt
    }
}

public struct FixedCommitmentEvaluation: Equatable, Sendable {
    public let occurrence: FixedCommitmentOccurrence
    public let fixedActualSpentThroughNowCents: Int
    public let fixedReserveNotYetInSpentCents: Int
    public let displayStatus: FixedCommitmentDisplayStatus
    public let isMatchedFuture: Bool
    public let isOverdue: Bool
    public let partialReasons: Set<FixedCommitmentPartialReason>

    public init(
        occurrence: FixedCommitmentOccurrence,
        fixedActualSpentThroughNowCents: Int,
        fixedReserveNotYetInSpentCents: Int,
        displayStatus: FixedCommitmentDisplayStatus,
        isMatchedFuture: Bool,
        isOverdue: Bool,
        partialReasons: Set<FixedCommitmentPartialReason>
    ) {
        self.occurrence = occurrence
        self.fixedActualSpentThroughNowCents = fixedActualSpentThroughNowCents
        self.fixedReserveNotYetInSpentCents = fixedReserveNotYetInSpentCents
        self.displayStatus = displayStatus
        self.isMatchedFuture = isMatchedFuture
        self.isOverdue = isOverdue
        self.partialReasons = partialReasons
    }

    public var effectiveFixedCostCents: Int {
        fixedActualSpentThroughNowCents + fixedReserveNotYetInSpentCents
    }

    public var isPartial: Bool { !partialReasons.isEmpty }
}

public struct FixedCommitmentCycleSummary: Equatable, Sendable {
    public let cycleTotalCents: Int
    public let totalSpentThroughNowCents: Int
    public let fixedActualSpentThroughNowCents: Int
    public let fixedReserveNotYetInSpentCents: Int
    public let partialReasons: Set<FixedCommitmentPartialReason>

    public var effectiveFixedCostCents: Int {
        fixedActualSpentThroughNowCents + fixedReserveNotYetInSpentCents
    }

    public var variableSpentThroughNowCents: Int {
        totalSpentThroughNowCents - fixedActualSpentThroughNowCents
    }

    public var cycleRemainingCents: Int {
        cycleTotalCents - totalSpentThroughNowCents
    }

    /// 固定支出已经发生的部分已包含在总支出中，此处只扣除尚未发生的预留。
    public var discretionaryRemainingCents: Int {
        cycleRemainingCents - fixedReserveNotYetInSpentCents
    }

    public var isPartial: Bool { !partialReasons.isEmpty }
}

public enum FixedCommitmentCalculator {
    public static func evaluate(
        occurrence: FixedCommitmentOccurrence,
        asOf: Date,
        exclusiveLinked: Bool,
        familyNetCents: Int,
        attributionOccurred: Bool,
        refundAfterMatchReview: Bool
    ) -> FixedCommitmentEvaluation {
        let skipped = occurrence.resolutionStatus == .skipped
        let planned = occurrence.plannedCents
        let actualFamilyNet = max(familyNetCents, 0)

        let actual: Int
        let reserve: Int
        if skipped {
            actual = 0
            reserve = 0
        } else if !exclusiveLinked {
            actual = 0
            reserve = planned
        } else if !attributionOccurred {
            actual = 0
            reserve = refundAfterMatchReview ? max(planned, actualFamilyNet) : actualFamilyNet
        } else {
            actual = actualFamilyNet
            reserve = refundAfterMatchReview ? max(planned - actualFamilyNet, 0) : 0
        }

        let isMatchedFuture = !skipped && exclusiveLinked && !attributionOccurred
        let isOverdue = !skipped && !exclusiveLinked &&
            Calendar.current.startOfDay(for: asOf) > Calendar.current.startOfDay(for: occurrence.dueDate)
        var reasons = Set<FixedCommitmentPartialReason>()
        if isOverdue { reasons.insert(.overdueCommitment) }
        if refundAfterMatchReview { reasons.insert(.refundAfterMatch) }
        if let reviewReason = occurrence.reviewReason {
            switch reviewReason {
            case .refundAfterMatch: reasons.insert(.refundAfterMatch)
            case .ambiguousCandidate: reasons.insert(.ambiguousCandidate)
            case .invalidScope: reasons.insert(.invalidScope)
            case .amountConflict: reasons.insert(.amountConflict)
            }
        }

        let storedStateIssues = invalidStoredState(for: occurrence)
        if !storedStateIssues.isEmpty ||
            refundAfterMatchReview != (occurrence.reviewReason == .refundAfterMatch) {
            reasons.insert(.invalidStoredState)
        }
        if !skipped && !exclusiveLinked && occurrence.resolutionStatus == .matched {
            reasons.insert(.invalidExclusiveLink)
        }

        let displayStatus: FixedCommitmentDisplayStatus
        switch occurrence.resolutionStatus {
        case .skipped:
            displayStatus = .skipped
        case .requiresReview:
            displayStatus = .requiresReview
        case .planned, .matched:
            if isMatchedFuture {
                displayStatus = .matchedFuture
            } else if isOverdue {
                displayStatus = .overdue
            } else {
                displayStatus = exclusiveLinked ? .matched : .planned
            }
        }

        return FixedCommitmentEvaluation(
            occurrence: occurrence,
            fixedActualSpentThroughNowCents: actual,
            fixedReserveNotYetInSpentCents: reserve,
            displayStatus: displayStatus,
            isMatchedFuture: isMatchedFuture,
            isOverdue: isOverdue,
            partialReasons: reasons
        )
    }

    public static func summarizeCycle(
        cycleTotalCents: Int,
        totalSpentThroughNowCents: Int,
        occurrences: some Sequence<FixedCommitmentEvaluation>
    ) -> FixedCommitmentCycleSummary {
        var actual = 0
        var reserve = 0
        var reasons = Set<FixedCommitmentPartialReason>()
        for evaluation in occurrences {
            actual += evaluation.fixedActualSpentThroughNowCents
            reserve += evaluation.fixedReserveNotYetInSpentCents
            reasons.formUnion(evaluation.partialReasons)
        }
        return FixedCommitmentCycleSummary(
            cycleTotalCents: max(cycleTotalCents, 0),
            totalSpentThroughNowCents: max(totalSpentThroughNowCents, 0),
            fixedActualSpentThroughNowCents: actual,
            fixedReserveNotYetInSpentCents: reserve,
            partialReasons: reasons
        )
    }

    private static func invalidStoredState(
        for occurrence: FixedCommitmentOccurrence
    ) -> Set<FixedCommitmentPartialReason> {
        var reasons = Set<FixedCommitmentPartialReason>()
        switch occurrence.resolutionStatus {
        case .planned:
            if occurrence.matchedTransactionFamilyID != nil || occurrence.reviewReason != nil {
                reasons.insert(.invalidStoredState)
            }
        case .matched:
            if occurrence.matchedTransactionFamilyID == nil || occurrence.reviewReason != nil {
                reasons.insert(.invalidStoredState)
            }
        case .skipped:
            if occurrence.matchedTransactionFamilyID != nil || occurrence.reviewReason != nil {
                reasons.insert(.invalidStoredState)
            }
        case .requiresReview:
            if occurrence.reviewReason == nil {
                reasons.insert(.invalidStoredState)
            }
        }
        return reasons
    }
}

public struct FixedCommitmentFamilyCandidate: Equatable, Sendable {
    public let familyID: String
    public let bookID: UUID
    public let currencyCode: String
    public let attributionDate: Date
    public let isRevoked: Bool

    public init(
        familyID: String,
        bookID: UUID,
        currencyCode: String = "CNY",
        attributionDate: Date,
        isRevoked: Bool = false
    ) {
        self.familyID = familyID
        self.bookID = bookID
        self.currencyCode = currencyCode.uppercased()
        self.attributionDate = attributionDate
        self.isRevoked = isRevoked
    }
}

public enum FixedCommitmentLinkIssue: Hashable, Sendable {
    case skippedOccurrence
    case occurrenceLinkedToAnotherFamily
    case familyAlreadyLinkedInPlan
    case revokedFamily
    case bookScopeMismatch
    case currencyMismatch
    case attributionOutsideCycle
}

public struct FixedCommitmentLinkValidation: Equatable, Sendable {
    public let issues: Set<FixedCommitmentLinkIssue>
    public var isValid: Bool { issues.isEmpty }

    public init(issues: Set<FixedCommitmentLinkIssue>) {
        self.issues = issues
    }
}

public enum FixedCommitmentLinkValidator {
    public static func validateLink(
        occurrence: FixedCommitmentOccurrence,
        candidate: FixedCommitmentFamilyCandidate,
        existingOccurrences: some Sequence<FixedCommitmentOccurrence>
    ) -> FixedCommitmentLinkValidation {
        var issues = Set<FixedCommitmentLinkIssue>()
        if occurrence.resolutionStatus == .skipped {
            issues.insert(.skippedOccurrence)
        }
        if let current = occurrence.matchedTransactionFamilyID,
           current != candidate.familyID {
            issues.insert(.occurrenceLinkedToAnotherFamily)
        }
        if !isFamilyUniqueWithinPlan(
            planID: occurrence.planID,
            familyID: candidate.familyID,
            occurrences: existingOccurrences,
            excludingOccurrence: occurrence
        ) {
            issues.insert(.familyAlreadyLinkedInPlan)
        }
        if candidate.isRevoked { issues.insert(.revokedFamily) }
        if candidate.bookID != occurrence.bookID { issues.insert(.bookScopeMismatch) }
        if candidate.currencyCode != occurrence.currencyCode { issues.insert(.currencyMismatch) }
        if !attributionFallsWithinCycle(
            attributionDate: candidate.attributionDate,
            cycleStart: occurrence.cycleStart,
            cycleEnd: occurrence.cycleEnd
        ) {
            issues.insert(.attributionOutsideCycle)
        }
        return FixedCommitmentLinkValidation(issues: issues)
    }

    public static func isFamilyUniqueWithinPlan(
        planID: UUID,
        familyID: String,
        occurrences: some Sequence<FixedCommitmentOccurrence>,
        excludingOccurrence: FixedCommitmentOccurrence?
    ) -> Bool {
        for occurrence in occurrences {
            if occurrence.id == excludingOccurrence?.id { continue }
            if occurrence.planID == planID && occurrence.matchedTransactionFamilyID == familyID {
                return false
            }
        }
        return true
    }

    public static func attributionFallsWithinCycle(
        attributionDate: Date,
        cycleStart: Date,
        cycleEnd: Date
    ) -> Bool {
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: attributionDate)
        return date >= calendar.startOfDay(for: cycleStart) &&
            date <= calendar.startOfDay(for: cycleEnd)
    }
}
