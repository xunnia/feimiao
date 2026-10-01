import Foundation
import SwiftData
import QingJiCore

/// 旧预算 V2 的 SwiftData 表（对应安卓同名旧表）。预算规则上线后旧表只保留
/// 不再读写（docs/08 §6.12）：只给一次性迁移到 BudgetRuleRecord 和旧备份恢复用。
@Model
final class BudgetPlanRecord {
    var stableID: UUID = UUID()
    var bookID: UUID = UUID()
    var currencyCode: String = "CNY"
    var timezone: String = "device_local"
    var name: String = ""
    var roleRaw: String = "primary"
    var cadenceRaw: String = BudgetPlanCadenceV2.monthly.rawValue
    var anchorStart: Date = Date()
    var monthStartDay: Int? = nil
    var weekStart: Int? = nil
    var endInclusive: Date? = nil
    var expenseScopeJSON: String = ""
    var statusRaw: String = BudgetPlanStatusV2.active.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        stableID: UUID = UUID(),
        bookID: UUID,
        currencyCode: String = "CNY",
        timezone: String = "device_local",
        name: String = "",
        roleRaw: String = "primary",
        cadenceRaw: String = BudgetPlanCadenceV2.monthly.rawValue,
        anchorStart: Date,
        monthStartDay: Int? = nil,
        weekStart: Int? = nil,
        endInclusive: Date? = nil,
        expenseScopeJSON: String = "",
        statusRaw: String = BudgetPlanStatusV2.active.rawValue
    ) {
        self.stableID = stableID
        self.bookID = bookID
        self.currencyCode = currencyCode
        self.timezone = timezone
        self.name = name
        self.roleRaw = roleRaw
        self.cadenceRaw = cadenceRaw
        self.anchorStart = anchorStart
        self.monthStartDay = monthStartDay
        self.weekStart = weekStart
        self.endInclusive = endInclusive
        self.expenseScopeJSON = expenseScopeJSON
        self.statusRaw = statusRaw
    }
}

@Model
final class BudgetPlanRevisionRecord {
    var stableID: UUID = UUID()
    var planID: UUID = UUID()
    var effectiveCycleStart: Date = Date()
    var effectiveToCycleStart: Date? = nil
    var amountCents: Int = 0
    var categoryBudgetsJSON: String = "{}"
    var monthlyIncomeCents: Int? = nil
    var fixedTemplatesJSON: String = "[]"
    var legacySourcePeriodID: Int? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(stableID: UUID = UUID(), planID: UUID, effectiveCycleStart: Date, amountCents: Int = 0) {
        self.stableID = stableID
        self.planID = planID
        self.effectiveCycleStart = effectiveCycleStart
        self.amountCents = amountCents
    }
}

@Model
final class BudgetCycleOverrideRecord {
    var stableID: UUID = UUID()
    var planID: UUID = UUID()
    var cycleStart: Date = Date()
    var cycleEndInclusive: Date = Date()
    var targetAmountCents: Int = 0
    var categoryBudgetsJSON: String? = nil
    var inputIntentRaw: String = BudgetOverrideIntent.replaceTotal.rawValue
    var inputDeltaCents: Int? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(stableID: UUID = UUID(), planID: UUID, cycleStart: Date, cycleEndInclusive: Date, targetAmountCents: Int = 0) {
        self.stableID = stableID
        self.planID = planID
        self.cycleStart = cycleStart
        self.cycleEndInclusive = cycleEndInclusive
        self.targetAmountCents = targetAmountCents
    }
}

@Model
final class BudgetCommitmentOccurrenceRecord {
    var stableID: UUID = UUID()
    var planID: UUID = UUID()
    var revisionID: UUID = UUID()
    var templateID: String = ""
    var cycleStart: Date = Date()
    var cycleEndInclusive: Date = Date()
    var dueDate: Date = Date()
    var plannedCents: Int = 0
    var resolutionStatusRaw: String = "planned"
    var reviewReasonRaw: String = ""
    var matchedTransactionFamilyID: String? = nil
    var resolvedAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(stableID: UUID = UUID(), planID: UUID, revisionID: UUID, templateID: String, cycleStart: Date, cycleEndInclusive: Date, dueDate: Date, plannedCents: Int = 0) {
        self.stableID = stableID
        self.planID = planID
        self.revisionID = revisionID
        self.templateID = templateID
        self.cycleStart = cycleStart
        self.cycleEndInclusive = cycleEndInclusive
        self.dueDate = dueDate
        self.plannedCents = plannedCents
    }
}

@Model
final class BudgetChangeEventRecord {
    var stableID: UUID = UUID()
    var planID: UUID = UUID()
    var eventType: String = ""
    var beforeJSON: String = ""
    var afterJSON: String = ""
    var createdAt: Date = Date()

    init(stableID: UUID = UUID(), planID: UUID, eventType: String, beforeJSON: String = "", afterJSON: String = "") {
        self.stableID = stableID
        self.planID = planID
        self.eventType = eventType
        self.beforeJSON = beforeJSON
        self.afterJSON = afterJSON
    }
}
