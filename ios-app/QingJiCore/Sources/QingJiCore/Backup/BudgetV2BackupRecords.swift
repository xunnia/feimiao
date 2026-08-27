import Foundation

public struct BackupBudgetPlanV2: Codable, Equatable, Sendable {
    public var id: UUID
    public var bookID: UUID
    public var currencyCode: String
    public var timezone: String
    public var name: String
    public var role: String
    public var cadenceRaw: String
    public var anchorStart: Date
    public var monthStartDay: Int?
    public var weekStart: Int?
    public var endInclusive: Date?
    public var expenseScopeJSON: String
    public var statusRaw: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, bookID: UUID, currencyCode: String = "CNY", timezone: String = "device_local", name: String = "", role: String = "primary", cadenceRaw: String = "monthly", anchorStart: Date, monthStartDay: Int? = nil, weekStart: Int? = nil, endInclusive: Date? = nil, expenseScopeJSON: String = "", statusRaw: String = "active", createdAt: Date = .distantPast, updatedAt: Date = .distantPast) {
        self.id = id
        self.bookID = bookID
        self.currencyCode = currencyCode
        self.timezone = timezone
        self.name = name
        self.role = role
        self.cadenceRaw = cadenceRaw
        self.anchorStart = anchorStart
        self.monthStartDay = monthStartDay
        self.weekStart = weekStart
        self.endInclusive = endInclusive
        self.expenseScopeJSON = expenseScopeJSON
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupBudgetPlanRevisionV2: Codable, Equatable, Sendable {
    public var id: UUID
    public var planID: UUID
    public var effectiveCycleStart: Date
    public var effectiveToCycleStart: Date?
    public var amountCents: Int
    public var categoryBudgetsJSON: String
    public var monthlyIncomeCents: Int?
    public var fixedTemplatesJSON: String
    public var legacySourcePeriodID: Int?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, planID: UUID, effectiveCycleStart: Date, effectiveToCycleStart: Date? = nil, amountCents: Int, categoryBudgetsJSON: String = "{}", monthlyIncomeCents: Int? = nil, fixedTemplatesJSON: String = "[]", legacySourcePeriodID: Int? = nil, createdAt: Date = .distantPast, updatedAt: Date = .distantPast) {
        self.id = id
        self.planID = planID
        self.effectiveCycleStart = effectiveCycleStart
        self.effectiveToCycleStart = effectiveToCycleStart
        self.amountCents = amountCents
        self.categoryBudgetsJSON = categoryBudgetsJSON
        self.monthlyIncomeCents = monthlyIncomeCents
        self.fixedTemplatesJSON = fixedTemplatesJSON
        self.legacySourcePeriodID = legacySourcePeriodID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupBudgetCycleOverrideV2: Codable, Equatable, Sendable {
    public var id: UUID
    public var planID: UUID
    public var cycleStart: Date
    public var cycleEndInclusive: Date
    public var targetAmountCents: Int
    public var categoryBudgetsJSON: String?
    public var inputIntentRaw: String
    public var inputDeltaCents: Int?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, planID: UUID, cycleStart: Date, cycleEndInclusive: Date, targetAmountCents: Int, categoryBudgetsJSON: String? = nil, inputIntentRaw: String = "replace_total", inputDeltaCents: Int? = nil, createdAt: Date = .distantPast, updatedAt: Date = .distantPast) {
        self.id = id
        self.planID = planID
        self.cycleStart = cycleStart
        self.cycleEndInclusive = cycleEndInclusive
        self.targetAmountCents = targetAmountCents
        self.categoryBudgetsJSON = categoryBudgetsJSON
        self.inputIntentRaw = inputIntentRaw
        self.inputDeltaCents = inputDeltaCents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupBudgetCommitmentOccurrenceV2: Codable, Equatable, Sendable {
    public var id: UUID
    public var planID: UUID
    public var revisionID: UUID
    public var templateID: String
    public var cycleStart: Date
    public var cycleEndInclusive: Date
    public var dueDate: Date
    public var plannedCents: Int
    public var resolutionStatusRaw: String
    public var reviewReasonRaw: String
    public var matchedTransactionFamilyID: String?
    public var resolvedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, planID: UUID, revisionID: UUID, templateID: String, cycleStart: Date, cycleEndInclusive: Date, dueDate: Date, plannedCents: Int, resolutionStatusRaw: String = "planned", reviewReasonRaw: String = "", matchedTransactionFamilyID: String? = nil, resolvedAt: Date? = nil, createdAt: Date = .distantPast, updatedAt: Date = .distantPast) {
        self.id = id
        self.planID = planID
        self.revisionID = revisionID
        self.templateID = templateID
        self.cycleStart = cycleStart
        self.cycleEndInclusive = cycleEndInclusive
        self.dueDate = dueDate
        self.plannedCents = plannedCents
        self.resolutionStatusRaw = resolutionStatusRaw
        self.reviewReasonRaw = reviewReasonRaw
        self.matchedTransactionFamilyID = matchedTransactionFamilyID
        self.resolvedAt = resolvedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupBudgetChangeEventV2: Codable, Equatable, Sendable {
    public var id: UUID
    public var planID: UUID
    public var eventType: String
    public var beforeJSON: String
    public var afterJSON: String
    public var createdAt: Date

    public init(id: UUID, planID: UUID, eventType: String, beforeJSON: String = "", afterJSON: String = "", createdAt: Date = .distantPast) {
        self.id = id
        self.planID = planID
        self.eventType = eventType
        self.beforeJSON = beforeJSON
        self.afterJSON = afterJSON
        self.createdAt = createdAt
    }
}
