import Foundation
import SwiftData
import QingJiCore

/// SwiftData mirrors for Android's budget V2 tables. JSON columns are kept as
/// strings because they are part of the Android contract and may gain fields
/// before the iOS UI needs to understand every one of them.
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

    var core: BudgetPlanV2 {
        let scope = (try? BudgetExpenseScopeV2(jsonString: expenseScopeJSON)) ?? BudgetExpenseScopeV2()
        return BudgetPlanV2(
            id: stableID,
            bookID: bookID,
            currencyCode: currencyCode,
            timezone: timezone,
            name: name,
            role: roleRaw,
            cadence: BudgetPlanCadenceV2(rawValue: cadenceRaw) ?? .monthly,
            anchorStart: anchorStart,
            monthStartDay: monthStartDay,
            weekStart: weekStart,
            endInclusive: endInclusive,
            expenseScope: scope,
            status: BudgetPlanStatusV2(rawValue: statusRaw) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
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

    var core: BudgetPlanRevisionV2 {
        BudgetPlanRevisionV2(
            id: stableID,
            planID: planID,
            effectiveCycleStart: effectiveCycleStart,
            effectiveToCycleStart: effectiveToCycleStart,
            amountCents: amountCents,
            categoryBudgetsCents: Self.decodeCents(categoryBudgetsJSON),
            monthlyIncomeCents: monthlyIncomeCents,
            fixedTemplates: Self.decodeTemplates(fixedTemplatesJSON),
            legacySourcePeriodID: legacySourcePeriodID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func decodeCents(_ raw: String) -> [String: Int] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.compactMapValues { value in
            if let number = value as? NSNumber { return number.intValue }
            return Int(value as? String ?? "")
        }
    }

    static func decodeTemplates(_ raw: String) -> [BudgetFixedTemplateV2] {
        guard let data = raw.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String else { return nil }
            let plannedValue = item["planned_cents"] ?? item["plannedCents"]
            let dueValue = item["due_value"] ?? item["dueValue"]
            let planned = (plannedValue as? NSNumber)?.intValue ?? Int(plannedValue as? String ?? "") ?? 0
            let due = (dueValue as? NSNumber)?.intValue ?? Int(dueValue as? String ?? "") ?? 0
            return BudgetFixedTemplateV2(id: id, name: name, plannedCents: planned, dueValue: due)
        }
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

    var core: BudgetCycleOverrideV2 {
        BudgetCycleOverrideV2(
            id: stableID,
            planID: planID,
            cycleStart: cycleStart,
            cycleEndInclusive: cycleEndInclusive,
            targetAmountCents: targetAmountCents,
            categoryBudgetsCents: categoryBudgetsJSON.map { BudgetPlanRevisionRecord.decodeCents($0) },
            inputIntent: BudgetOverrideIntent(rawValue: inputIntentRaw) ?? .replaceTotal,
            inputDeltaCents: inputDeltaCents,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
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

/// 将预算 revision 中的固定承诺物化为当前和下一周期的可审计 occurrence。
/// 和 Android 一样，重复启动只补缺失记录，不会重复生成固定承诺。
enum BudgetCommitmentStore {
    enum Error: LocalizedError {
        case occurrenceNotFound
        case planNotFound
        case transactionNotFound
        case invalidCandidate
        case invalidState

        var errorDescription: String? {
            switch self {
            case .occurrenceNotFound: return "固定承诺周期记录不存在。"
            case .planNotFound: return "预算计划不存在。"
            case .transactionNotFound: return "匹配账单不存在。"
            case .invalidCandidate: return "这笔账不在固定承诺的账本、币种或周期内，或已匹配其他承诺。"
            case .invalidState: return "这条固定承诺当前不支持该操作。"
            }
        }
    }

    @discardableResult
    static func materializeCurrent(
        in context: ModelContext,
        now: Date = Date()
    ) throws -> Int {
        let plans = try context.fetch(FetchDescriptor<BudgetPlanRecord>())
            .filter { $0.statusRaw == BudgetPlanStatusV2.active.rawValue && $0.roleRaw == "primary" }
        let revisions = try context.fetch(FetchDescriptor<BudgetPlanRevisionRecord>())
        var existing = try context.fetch(FetchDescriptor<BudgetCommitmentOccurrenceRecord>())
        var created = 0

        for planRecord in plans {
            let plan = planRecord.core
            let reference = max(Calendar.current.startOfDay(for: now), plan.anchorStart)
            let firstCycle = plan.cycle(for: reference)
            let cycles = [firstCycle, plan.cycle(for: firstCycle.endExclusive)]
            for cycle in cycles where cycle.start >= plan.anchorStart {
                if let endInclusive = plan.endInclusive,
                   cycle.start > endInclusive {
                    continue
                }
                let candidates = revisions
                    .filter { $0.core.applies(to: cycle) }
                    .sorted {
                        if $0.effectiveCycleStart != $1.effectiveCycleStart {
                            return $0.effectiveCycleStart < $1.effectiveCycleStart
                        }
                        return $0.stableID.uuidString < $1.stableID.uuidString
                    }
                guard let revision = candidates.last else { continue }
                for template in revision.core.fixedTemplates where template.plannedCents > 0 {
                    let alreadyExists = existing.contains {
                        $0.planID == plan.id &&
                        $0.templateID == template.id &&
                        Calendar.current.isDate($0.cycleStart, inSameDayAs: cycle.start)
                    }
                    guard !alreadyExists else { continue }
                    let occurrence = BudgetCommitmentOccurrenceRecord(
                        planID: plan.id,
                        revisionID: revision.stableID,
                        templateID: template.id,
                        cycleStart: cycle.start,
                        cycleEndInclusive: cycle.endInclusive,
                        dueDate: dueDate(for: plan, cycle: cycle, template: template),
                        plannedCents: template.plannedCents
                    )
                    context.insert(occurrence)
                    existing.append(occurrence)
                    created += 1
                }
            }
        }
        if created > 0 { try context.save() }
        return created
    }

    static func occurrences(
        for planID: UUID,
        cycleStart: Date? = nil,
        in context: ModelContext
    ) throws -> [BudgetCommitmentOccurrenceRecord] {
        let values = try context.fetch(FetchDescriptor<BudgetCommitmentOccurrenceRecord>(
            sortBy: [SortDescriptor(\.dueDate)]
        )).filter { $0.planID == planID }
        guard let cycleStart else { return values }
        return values.filter { Calendar.current.isDate($0.cycleStart, inSameDayAs: cycleStart) }
    }

    static func matchCandidates(
        for occurrence: BudgetCommitmentOccurrenceRecord,
        in context: ModelContext
    ) throws -> [MoneyTransaction] {
        guard occurrence.resolutionStatusRaw == FixedCommitmentResolutionStatus.planned.rawValue else {
            throw Error.invalidState
        }
        guard let plan = try context.fetch(FetchDescriptor<BudgetPlanRecord>())
            .first(where: { $0.stableID == occurrence.planID }) else {
            throw Error.planNotFound
        }
        let occurrences = try context.fetch(FetchDescriptor<BudgetCommitmentOccurrenceRecord>())
        let linkedFamilies = Set(
            occurrences.compactMap { item -> String? in
                guard item.planID == plan.stableID,
                      item.stableID != occurrence.stableID else { return nil }
                return item.matchedTransactionFamilyID
            }
        )
        let start = Calendar.current.startOfDay(for: occurrence.cycleStart)
        let end = Calendar.current.startOfDay(for: occurrence.cycleEndInclusive)
        return try context.fetch(FetchDescriptor<MoneyTransaction>(sortBy: [
            SortDescriptor(\.date, order: .reverse)
        ])).filter { transaction in
            transaction.kind == .expense &&
            transaction.amount > 0 &&
            transaction.refundOfID == nil &&
            !transaction.isExcluded &&
            transaction.book?.stableID == plan.bookID &&
            transaction.currencyCode == plan.currencyCode &&
            !linkedFamilies.contains(transaction.stableID.uuidString) &&
            Calendar.current.startOfDay(for: transaction.date) >= start &&
            Calendar.current.startOfDay(for: transaction.date) <= end
        }
    }

    static func match(
        _ occurrence: BudgetCommitmentOccurrenceRecord,
        to transaction: MoneyTransaction,
        in context: ModelContext
    ) throws {
        guard let plan = try context.fetch(FetchDescriptor<BudgetPlanRecord>())
            .first(where: { $0.stableID == occurrence.planID }) else {
            throw Error.planNotFound
        }
        guard try matchCandidates(for: occurrence, in: context)
            .contains(where: { $0.stableID == transaction.stableID }) else {
            throw Error.invalidCandidate
        }
        let now = Date()
        let previous = occurrence.matchedTransactionFamilyID ?? ""
        occurrence.resolutionStatusRaw = FixedCommitmentResolutionStatus.matched.rawValue
        occurrence.reviewReasonRaw = ""
        occurrence.matchedTransactionFamilyID = transaction.stableID.uuidString
        occurrence.resolvedAt = now
        occurrence.updatedAt = now
        context.insert(BudgetChangeEventRecord(
            planID: plan.stableID,
            eventType: "occurrence_matched",
            beforeJSON: "{\"family_id\":\"\(previous)\"}",
            afterJSON: "{\"family_id\":\"\(transaction.stableID.uuidString)\"}"
        ))
        try context.save()
    }

    static func skip(
        _ occurrence: BudgetCommitmentOccurrenceRecord,
        in context: ModelContext
    ) throws {
        try setResolution(occurrence, status: .skipped, eventType: "occurrence_skipped", in: context)
    }

    static func reset(
        _ occurrence: BudgetCommitmentOccurrenceRecord,
        in context: ModelContext
    ) throws {
        try setResolution(occurrence, status: .planned, eventType: "occurrence_reset", in: context)
    }

    static func acceptRefundReview(
        _ occurrence: BudgetCommitmentOccurrenceRecord,
        in context: ModelContext
    ) throws {
        guard occurrence.resolutionStatusRaw == FixedCommitmentResolutionStatus.requiresReview.rawValue,
              occurrence.reviewReasonRaw == FixedCommitmentReviewReason.refundAfterMatch.rawValue,
              occurrence.matchedTransactionFamilyID != nil else {
            throw Error.invalidState
        }
        occurrence.resolutionStatusRaw = FixedCommitmentResolutionStatus.matched.rawValue
        occurrence.reviewReasonRaw = ""
        let now = Date()
        occurrence.resolvedAt = now
        occurrence.updatedAt = now
        try context.save()
    }

    @discardableResult
    static func refreshRefundReviews(in context: ModelContext) throws -> Int {
        let occurrences = try context.fetch(FetchDescriptor<BudgetCommitmentOccurrenceRecord>())
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        var changed = 0
        for occurrence in occurrences {
            guard let familyID = occurrence.matchedTransactionFamilyID,
                  let rootID = UUID(uuidString: familyID),
                  let resolvedAt = occurrence.resolvedAt else { continue }
            let hasNewRefund = transactions.contains {
                $0.refundOfID == rootID && $0.createdAt > resolvedAt
            }
            if hasNewRefund,
               occurrence.resolutionStatusRaw == FixedCommitmentResolutionStatus.matched.rawValue {
                occurrence.resolutionStatusRaw = FixedCommitmentResolutionStatus.requiresReview.rawValue
                occurrence.reviewReasonRaw = FixedCommitmentReviewReason.refundAfterMatch.rawValue
                occurrence.updatedAt = Date()
                changed += 1
            } else if !hasNewRefund,
                      occurrence.resolutionStatusRaw == FixedCommitmentResolutionStatus.requiresReview.rawValue,
                      occurrence.reviewReasonRaw == FixedCommitmentReviewReason.refundAfterMatch.rawValue {
                occurrence.resolutionStatusRaw = FixedCommitmentResolutionStatus.matched.rawValue
                occurrence.reviewReasonRaw = ""
                occurrence.updatedAt = Date()
                changed += 1
            }
        }
        if changed > 0 { try context.save() }
        return changed
    }

    private static func dueDate(
        for plan: BudgetPlanV2,
        cycle: BudgetPlanCycleV2,
        template: BudgetFixedTemplateV2
    ) -> Date {
        let calendar = Calendar.current
        switch plan.cadence {
        case .weekly:
            // UI stores Monday=1 ... Sunday=7; Calendar weekday is Sunday=1.
            let dueWeekday = template.dueValue == 7 ? 1 : template.dueValue + 1
            let startWeekday = calendar.component(.weekday, from: cycle.start)
            let offset = (dueWeekday - startWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: offset, to: cycle.start) ?? cycle.start
        case .monthly:
            var components = calendar.dateComponents([.year, .month], from: cycle.start)
            components.day = min(max(template.dueValue, 1), 28)
            var due = calendar.date(from: components) ?? cycle.start
            if due < cycle.start {
                due = calendar.date(byAdding: .month, value: 1, to: due) ?? due
            }
            return due < cycle.endExclusive ? due : cycle.endInclusive
        case .oneOff:
            return cycle.start
        }
    }

    private static func setResolution(
        _ occurrence: BudgetCommitmentOccurrenceRecord,
        status: FixedCommitmentResolutionStatus,
        eventType: String,
        in context: ModelContext
    ) throws {
        guard let plan = try context.fetch(FetchDescriptor<BudgetPlanRecord>())
            .first(where: { $0.stableID == occurrence.planID }) else {
            throw Error.planNotFound
        }
        let before = occurrence.resolutionStatusRaw
        occurrence.resolutionStatusRaw = status.rawValue
        occurrence.reviewReasonRaw = ""
        occurrence.matchedTransactionFamilyID = nil
        occurrence.resolvedAt = status == .skipped ? Date() : nil
        occurrence.updatedAt = Date()
        context.insert(BudgetChangeEventRecord(
            planID: plan.stableID,
            eventType: eventType,
            beforeJSON: "{\"status\":\"\(before)\"}",
            afterJSON: "{\"status\":\"\(status.rawValue)\"}"
        ))
        try context.save()
    }
}
