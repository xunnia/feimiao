import Foundation

/// Android budget V2's stable plan vocabulary. The app layer persists these
/// values as raw strings so older backups remain readable.
public enum BudgetPlanCadenceV2: String, Codable, CaseIterable, Hashable, Sendable {
    case monthly
    case weekly
    case oneOff = "one_off"
}

public enum BudgetPlanStatusV2: String, Codable, CaseIterable, Hashable, Sendable {
    case active
    case archived
}

public enum BudgetOverrideIntent: String, Codable, CaseIterable, Hashable, Sendable {
    case replaceTotal = "replace_total"
    case adjustRemaining = "adjust_remaining"
    case setRemaining = "set_remaining"
}

public struct BudgetExpenseScopeV2: Codable, Equatable, Sendable {
    public var categoryKeys: [String]
    public var tagIDs: [Int]

    public init(categoryKeys: [String] = [], tagIDs: [Int] = []) {
        self.categoryKeys = Array(Set(categoryKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
        self.tagIDs = Array(Set(tagIDs.filter { $0 > 0 })).sorted()
    }

    public var isEmpty: Bool { categoryKeys.isEmpty && tagIDs.isEmpty }

    public func matches(categoryKey: String, tagIDs familyTagIDs: some Sequence<Int>) -> Bool {
        if categoryKeys.contains(categoryKey.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return true
        }
        return familyTagIDs.contains { tagIDs.contains($0) }
    }

    public func jsonString() throws -> String {
        let payload: [String: Any] = [
            "category_keys": categoryKeys,
            "tag_ids": tagIDs,
            "match": "any"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    public init(jsonString: String) throws {
        let data = Data(jsonString.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderValueNotFound)
        }
        let categories = (object["category_keys"] as? [Any] ?? []).compactMap { $0 as? String }
        let tags = (object["tag_ids"] as? [Any] ?? []).compactMap { value -> Int? in
            if let number = value as? NSNumber { return number.intValue }
            return Int(value as? String ?? "")
        }
        self.init(categoryKeys: categories, tagIDs: tags)
    }
}

public struct BudgetFixedTemplateV2: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var plannedCents: Int
    public var dueValue: Int

    public init(id: String, name: String, plannedCents: Int, dueValue: Int) {
        self.id = id
        self.name = name
        self.plannedCents = plannedCents
        self.dueValue = dueValue
    }
}

public struct BudgetPlanV2: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var bookID: UUID
    public var currencyCode: String
    public var timezone: String
    public var name: String
    public var role: String
    public var cadence: BudgetPlanCadenceV2
    public var anchorStart: Date
    public var monthStartDay: Int?
    public var weekStart: Int?
    public var endInclusive: Date?
    public var expenseScope: BudgetExpenseScopeV2
    public var status: BudgetPlanStatusV2
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        bookID: UUID,
        currencyCode: String = "CNY",
        timezone: String = "device_local",
        name: String = "",
        role: String = "primary",
        cadence: BudgetPlanCadenceV2,
        anchorStart: Date,
        monthStartDay: Int? = nil,
        weekStart: Int? = nil,
        endInclusive: Date? = nil,
        expenseScope: BudgetExpenseScopeV2 = BudgetExpenseScopeV2(),
        status: BudgetPlanStatusV2 = .active,
        createdAt: Date = .distantPast,
        updatedAt: Date = .distantPast
    ) {
        self.id = id
        self.bookID = bookID
        self.currencyCode = currencyCode.uppercased()
        self.timezone = timezone
        self.name = name
        self.role = role.lowercased()
        self.cadence = cadence
        self.anchorStart = BudgetPlanV2.day(anchorStart)
        self.monthStartDay = monthStartDay
        self.weekStart = weekStart
        self.endInclusive = endInclusive.map { BudgetPlanV2.day($0) }
        self.expenseScope = expenseScope
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isPrimary: Bool { role == "primary" }
    public var isSpecial: Bool { role == "special" }

    public func covers(_ date: Date, calendar: Calendar = .current) -> Bool {
        let value = calendar.startOfDay(for: date)
        guard value >= calendar.startOfDay(for: anchorStart) else { return false }
        if let endInclusive {
            return value <= calendar.startOfDay(for: endInclusive)
        }
        return status != .archived
    }

    public func cycle(for date: Date, calendar: Calendar = .current) -> BudgetPlanCycleV2 {
        let value = calendar.startOfDay(for: date)
        switch cadence {
        case .oneOff:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endInclusive ?? anchorStart)) ?? value
            return BudgetPlanCycleV2(planID: id, start: calendar.startOfDay(for: anchorStart), endExclusive: end)
        case .weekly:
            let weekday = weekStart ?? calendar.component(.weekday, from: anchorStart)
            let currentWeekday = calendar.component(.weekday, from: value)
            let delta = (currentWeekday - weekday + 7) % 7
            let start = calendar.date(byAdding: .day, value: -delta, to: value) ?? value
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return BudgetPlanCycleV2(planID: id, start: start, endExclusive: end)
        case .monthly:
            let anchor = min(max(monthStartDay ?? 1, 1), 28)
            var components = calendar.dateComponents([.year, .month], from: value)
            components.day = anchor
            var start = calendar.date(from: components) ?? value
            if value < start {
                start = calendar.date(byAdding: .month, value: -1, to: start) ?? start
            }
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return BudgetPlanCycleV2(planID: id, start: start, endExclusive: end)
        }
    }

    private static func day(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}

public struct BudgetPlanCycleV2: Equatable, Sendable {
    public let planID: UUID
    public let start: Date
    public let endExclusive: Date

    public init(planID: UUID, start: Date, endExclusive: Date) {
        self.planID = planID
        self.start = Calendar.current.startOfDay(for: start)
        self.endExclusive = Calendar.current.startOfDay(for: endExclusive)
    }

    public var endInclusive: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
    }

    public var dayCount: Int {
        Calendar.current.dateComponents([.day], from: start, to: endExclusive).day ?? 0
    }

    public func contains(_ date: Date) -> Bool {
        let value = Calendar.current.startOfDay(for: date)
        return value >= start && value < endExclusive
    }
}

public struct BudgetPlanRevisionV2: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var planID: UUID
    public var effectiveCycleStart: Date
    public var effectiveToCycleStart: Date?
    public var amountCents: Int
    public var categoryBudgetsCents: [String: Int]
    public var monthlyIncomeCents: Int?
    public var fixedTemplates: [BudgetFixedTemplateV2]
    public var legacySourcePeriodID: Int?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        planID: UUID,
        effectiveCycleStart: Date,
        effectiveToCycleStart: Date? = nil,
        amountCents: Int,
        categoryBudgetsCents: [String: Int] = [:],
        monthlyIncomeCents: Int? = nil,
        fixedTemplates: [BudgetFixedTemplateV2] = [],
        legacySourcePeriodID: Int? = nil,
        createdAt: Date = .distantPast,
        updatedAt: Date = .distantPast
    ) {
        self.id = id
        self.planID = planID
        self.effectiveCycleStart = Calendar.current.startOfDay(for: effectiveCycleStart)
        self.effectiveToCycleStart = effectiveToCycleStart.map { Calendar.current.startOfDay(for: $0) }
        self.amountCents = max(amountCents, 0)
        self.categoryBudgetsCents = categoryBudgetsCents.filter { $0.value >= 0 }
        self.monthlyIncomeCents = monthlyIncomeCents
        self.fixedTemplates = fixedTemplates
        self.legacySourcePeriodID = legacySourcePeriodID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func applies(to cycle: BudgetPlanCycleV2) -> Bool {
        guard cycle.planID == planID, cycle.start >= effectiveCycleStart else { return false }
        return effectiveToCycleStart == nil || cycle.start < effectiveToCycleStart!
    }
}

public struct BudgetCycleOverrideV2: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var planID: UUID
    public var cycleStart: Date
    public var cycleEndInclusive: Date
    public var targetAmountCents: Int
    public var categoryBudgetsCents: [String: Int]?
    public var inputIntent: BudgetOverrideIntent
    public var inputDeltaCents: Int?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        planID: UUID,
        cycleStart: Date,
        cycleEndInclusive: Date,
        targetAmountCents: Int,
        categoryBudgetsCents: [String: Int]? = nil,
        inputIntent: BudgetOverrideIntent = .replaceTotal,
        inputDeltaCents: Int? = nil,
        createdAt: Date = .distantPast,
        updatedAt: Date = .distantPast
    ) {
        self.id = id
        self.planID = planID
        self.cycleStart = Calendar.current.startOfDay(for: cycleStart)
        self.cycleEndInclusive = Calendar.current.startOfDay(for: cycleEndInclusive)
        self.targetAmountCents = max(targetAmountCents, 0)
        self.categoryBudgetsCents = categoryBudgetsCents
        self.inputIntent = inputIntent
        self.inputDeltaCents = inputDeltaCents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum BudgetPlanDayStatusV2: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case conflict
}

public struct BudgetPlanDayResolutionV2: Equatable, Sendable {
    public let status: BudgetPlanDayStatusV2
    public let plan: BudgetPlanV2?
    public let cycle: BudgetPlanCycleV2?
    public let revision: BudgetPlanRevisionV2?
    public let override: BudgetCycleOverrideV2?
    public let plannedCents: Int?
    public let categoryPlannedCents: [String: Int]
    public let reason: String?

    public init(
        status: BudgetPlanDayStatusV2,
        plan: BudgetPlanV2? = nil,
        cycle: BudgetPlanCycleV2? = nil,
        revision: BudgetPlanRevisionV2? = nil,
        override: BudgetCycleOverrideV2? = nil,
        plannedCents: Int? = nil,
        categoryPlannedCents: [String: Int] = [:],
        reason: String? = nil
    ) {
        self.status = status
        self.plan = plan
        self.cycle = cycle
        self.revision = revision
        self.override = override
        self.plannedCents = plannedCents
        self.categoryPlannedCents = categoryPlannedCents
        self.reason = reason
    }
}

public struct BudgetPlanWindowResolutionV2: Equatable, Sendable {
    public let status: BudgetPlanDayStatusV2
    public let plannedCents: Int?
    public let categoryPlannedCents: [String: Int]
    public let planIDs: Set<UUID>
    public let reason: String?

    public init(status: BudgetPlanDayStatusV2, plannedCents: Int?, categoryPlannedCents: [String: Int], planIDs: Set<UUID>, reason: String? = nil) {
        self.status = status
        self.plannedCents = plannedCents
        self.categoryPlannedCents = categoryPlannedCents
        self.planIDs = planIDs
        self.reason = reason
    }
}

public enum BudgetPlanV2Resolver {
    public static func resolveDay(
        day: Date,
        bookID: UUID,
        knowledgeCutoff: Date,
        plans: some Sequence<BudgetPlanV2>,
        revisions: some Sequence<BudgetPlanRevisionV2>,
        overrides: some Sequence<BudgetCycleOverrideV2>,
        calendar: Calendar = .current
    ) -> BudgetPlanDayResolutionV2 {
        let value = calendar.startOfDay(for: day)
        let candidates = plans.filter {
            $0.bookID == bookID && $0.isPrimary && $0.currencyCode == "CNY" &&
            $0.createdAt <= knowledgeCutoff && $0.covers(value, calendar: calendar)
        }
        guard candidates.count == 1, let plan = candidates.first else {
            return BudgetPlanDayResolutionV2(
                status: candidates.isEmpty ? .unavailable : .conflict,
                reason: candidates.isEmpty ? nil : "同一天有多个主预算计划覆盖。"
            )
        }
        let cycle = plan.cycle(for: value, calendar: calendar)
        let applicable = revisions.filter {
            $0.planID == plan.id && $0.createdAt <= knowledgeCutoff && $0.applies(to: cycle)
        }.sorted {
            $0.effectiveCycleStart == $1.effectiveCycleStart
                ? $0.id.uuidString < $1.id.uuidString
                : $0.effectiveCycleStart < $1.effectiveCycleStart
        }
        guard let revision = applicable.last else {
            return BudgetPlanDayResolutionV2(status: .conflict, plan: plan, cycle: cycle, reason: "当前预算周期缺少额度修订。")
        }
        if applicable.filter({ $0.effectiveCycleStart == revision.effectiveCycleStart }).count != 1 {
            return BudgetPlanDayResolutionV2(status: .conflict, plan: plan, cycle: cycle, reason: "同一生效周期存在多个额度修订。")
        }
        let matchingOverrides = overrides.filter {
            $0.planID == plan.id && $0.cycleStart == cycle.start && $0.createdAt <= knowledgeCutoff
        }
        guard matchingOverrides.count <= 1 else {
            return BudgetPlanDayResolutionV2(status: .conflict, plan: plan, cycle: cycle, revision: revision, reason: "同一预算周期存在多个覆盖值。")
        }
        let override = matchingOverrides.first
        let total = override?.targetAmountCents ?? revision.amountCents
        let categories = override?.categoryBudgetsCents ?? revision.categoryBudgetsCents
        guard categories.values.reduce(0, +) <= total else {
            return BudgetPlanDayResolutionV2(status: .conflict, plan: plan, cycle: cycle, revision: revision, override: override, reason: "分类预算合计超过周期总额。")
        }
        let offset = calendar.dateComponents([.day], from: cycle.start, to: value).day ?? 0
        return BudgetPlanDayResolutionV2(
            status: .available,
            plan: plan,
            cycle: cycle,
            revision: revision,
            override: override,
            plannedCents: stableBudgetDailyShare(total, dayCount: cycle.dayCount, dayOffset: offset),
            categoryPlannedCents: categories.mapValues {
                stableBudgetDailyShare($0, dayCount: cycle.dayCount, dayOffset: offset)
            }
        )
    }

    public static func resolveWindow(
        startInclusive: Date,
        endExclusive: Date,
        bookID: UUID,
        knowledgeCutoff: Date,
        plans: some Sequence<BudgetPlanV2>,
        revisions: some Sequence<BudgetPlanRevisionV2>,
        overrides: some Sequence<BudgetCycleOverrideV2>,
        calendar: Calendar = .current
    ) -> BudgetPlanWindowResolutionV2 {
        var day = calendar.startOfDay(for: startInclusive)
        let end = calendar.startOfDay(for: endExclusive)
        var total = 0
        var any = false
        var categories: [String: Int] = [:]
        var planIDs = Set<UUID>()
        while day < end {
            let result = resolveDay(day: day, bookID: bookID, knowledgeCutoff: knowledgeCutoff, plans: plans, revisions: revisions, overrides: overrides, calendar: calendar)
            if result.status == .conflict {
                return BudgetPlanWindowResolutionV2(status: .conflict, plannedCents: nil, categoryPlannedCents: [:], planIDs: planIDs, reason: result.reason)
            }
            if result.status == .available {
                any = true
                total += result.plannedCents ?? 0
                if let planID = result.plan?.id { planIDs.insert(planID) }
                for (key, value) in result.categoryPlannedCents { categories[key, default: 0] += value }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
        }
        return BudgetPlanWindowResolutionV2(status: any ? .available : .unavailable, plannedCents: any ? total : nil, categoryPlannedCents: categories, planIDs: planIDs, reason: nil)
    }
}

public func stableBudgetDailyShare(_ totalCents: Int, dayCount: Int, dayOffset: Int) -> Int {
    guard totalCents >= 0, dayCount > 0, dayOffset >= 0, dayOffset < dayCount else {
        return 0
    }
    let quotient = totalCents / dayCount
    let remainder = totalCents % dayCount
    return quotient + (dayOffset < remainder ? 1 : 0)
}
