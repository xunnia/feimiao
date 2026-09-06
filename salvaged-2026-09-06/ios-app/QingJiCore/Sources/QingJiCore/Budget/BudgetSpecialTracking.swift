import Foundation

/// One expense family after attached refunds have been folded into its net.
/// The app layer owns the refund replay; this resolver only applies date,
/// book, currency, and category/tag scope.
public struct BudgetSpecialExpenseFamilyInput: Equatable, Sendable {
    public let id: String
    public let bookID: UUID
    public let currencyCode: String
    public let attributionDate: Date
    public let createdAt: Date
    public let netAmountCents: Int
    public let countsInBudget: Bool
    public let categoryKey: String
    public let tagIDs: Set<Int>
    public let tagNames: Set<String>

    public init(
        id: String,
        bookID: UUID,
        currencyCode: String = "CNY",
        attributionDate: Date,
        createdAt: Date,
        netAmountCents: Int,
        countsInBudget: Bool = true,
        categoryKey: String = "",
        tagIDs: [Int] = [],
        tagNames: [String] = []
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bookID = bookID
        self.currencyCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Keep the event instant here. The resolver owns civil-day
        // normalization because its caller may use a non-device calendar.
        self.attributionDate = attributionDate
        self.createdAt = createdAt
        self.netAmountCents = max(netAmountCents, 0)
        self.countsInBudget = countsInBudget
        self.categoryKey = categoryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tagIDs = Set(tagIDs.filter { $0 > 0 })
        self.tagNames = Set(tagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    public var isValid: Bool {
        !id.isEmpty && !currencyCode.isEmpty
    }
}

public enum BudgetSpecialResultStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case available
    case conflict
}

public enum BudgetSpecialLifecycleStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case upcoming
    case inProgress = "in_progress"
    case ended
    case archived
}

public struct BudgetSpecialCategoryResult: Equatable, Sendable, Identifiable {
    public let categoryKey: String
    public let plannedCents: Int
    public let spentCents: Int

    public var id: String { categoryKey }
    public var remainingCents: Int { plannedCents - spentCents }
    public var progress: Double? {
        plannedCents > 0 ? Double(spentCents) / Double(plannedCents) : nil
    }

    public init(categoryKey: String, plannedCents: Int, spentCents: Int) {
        self.categoryKey = categoryKey
        self.plannedCents = max(plannedCents, 0)
        self.spentCents = max(spentCents, 0)
    }
}

public struct BudgetSpecialTrackingResult: Equatable, Sendable, Identifiable {
    public let plan: BudgetPlanV2
    public let revision: BudgetPlanRevisionV2?
    public let status: BudgetSpecialResultStatus
    public let reason: String?
    public let lifecycleStatus: BudgetSpecialLifecycleStatus
    public let totalCents: Int?
    public let spentCents: Int?
    public let remainingCents: Int?
    public let matchedFamilyCount: Int
    public let excludedForeignFamilyCount: Int
    public let categoryResults: [BudgetSpecialCategoryResult]
    private let calendar: Calendar

    public var id: UUID { plan.id }
    public var startInclusive: Date { calendar.startOfDay(for: plan.anchorStart) }
    public var endInclusive: Date { calendar.startOfDay(for: plan.endInclusive ?? plan.anchorStart) }
    public var endExclusive: Date {
        calendar.date(byAdding: .day, value: 1, to: endInclusive) ?? endInclusive
    }
    public var progress: Double? {
        guard let totalCents, let spentCents else { return nil }
        guard totalCents > 0 else { return nil }
        return Double(spentCents) / Double(totalCents)
    }
    public var isOverBudget: Bool {
        guard let totalCents, let spentCents else { return false }
        return spentCents > totalCents
    }
    public var isNearLimit: Bool {
        guard let totalCents, let spentCents, totalCents > 0 else { return false }
        return spentCents <= totalCents && spentCents * 100 >= totalCents * 80
    }

    public init(
        plan: BudgetPlanV2,
        revision: BudgetPlanRevisionV2?,
        status: BudgetSpecialResultStatus,
        reason: String?,
        lifecycleStatus: BudgetSpecialLifecycleStatus,
        totalCents: Int?,
        spentCents: Int?,
        remainingCents: Int?,
        matchedFamilyCount: Int,
        excludedForeignFamilyCount: Int,
        categoryResults: [BudgetSpecialCategoryResult] = [],
        calendar: Calendar? = nil
    ) {
        self.plan = plan
        self.revision = revision
        self.status = status
        self.reason = reason
        self.lifecycleStatus = lifecycleStatus
        self.totalCents = totalCents
        self.spentCents = spentCents
        self.remainingCents = remainingCents
        self.matchedFamilyCount = matchedFamilyCount
        self.excludedForeignFamilyCount = excludedForeignFamilyCount
        self.categoryResults = categoryResults
        self.calendar = calendar ?? plan.businessCalendar
    }
}

public enum BudgetSpecialTrackingResolver {
    public static func resolveWindow(
        windowStartInclusive: Date,
        windowEndExclusive: Date,
        bookID: UUID,
        asOf: Date,
        knowledgeCutoff: Date,
        plans: some Sequence<BudgetPlanV2>,
        revisions: some Sequence<BudgetPlanRevisionV2>,
        expenseFamilies: some Sequence<BudgetSpecialExpenseFamilyInput>,
        currencyCode: String = "CNY",
        includeArchived: Bool = false,
        calendar: Calendar? = nil
    ) -> [BudgetSpecialTrackingResult] {
        let planList = Array(plans)
        let iterationCalendar = calendar
            ?? planList.first(where: { $0.isSpecial && $0.bookID == bookID })?.businessCalendar
            ?? Calendar.current
        let windowStart = iterationCalendar.startOfDay(for: windowStartInclusive)
        let windowEnd = iterationCalendar.startOfDay(for: windowEndExclusive)
        guard windowStart < windowEnd else { return [] }
        let expectedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !expectedCurrency.isEmpty else { return [] }

        let visiblePlans = planList.map { plan -> BudgetPlanV2 in
            // A historical query made before an archive must still see the
            // former active plan, while a current query should hide it.
            guard plan.status == .archived, plan.updatedAt > knowledgeCutoff else { return plan }
            var historical = plan
            historical.status = .active
            return historical
        }.filter { plan in
            guard plan.isSpecial,
                  plan.bookID == bookID,
                  plan.currencyCode.uppercased() == expectedCurrency,
                  plan.createdAt <= knowledgeCutoff,
                  includeArchived || plan.status != .archived,
                  let endInclusive = plan.endInclusive else { return false }
            let planCalendar = calendar ?? plan.businessCalendar
            let planStart = planCalendar.startOfDay(for: plan.anchorStart)
            let planEnd = planCalendar.startOfDay(for: endInclusive)
            let endExclusive = planCalendar.date(byAdding: .day, value: 1, to: planEnd) ?? planEnd
            return planStart < windowEnd && endExclusive > windowStart
        }.sorted {
            let leftCalendar = calendar ?? $0.businessCalendar
            let rightCalendar = calendar ?? $1.businessCalendar
            let leftStart = leftCalendar.startOfDay(for: $0.anchorStart)
            let rightStart = rightCalendar.startOfDay(for: $1.anchorStart)
            if leftStart != rightStart { return leftStart < rightStart }
            return $0.id.uuidString < $1.id.uuidString
        }

        let revisionList = Array(revisions)
        let familyList = Array(expenseFamilies)
        return visiblePlans.map {
            resolvePlan(
                plan: $0,
                asOf: asOf,
                knowledgeCutoff: knowledgeCutoff,
                revisions: revisionList,
                expenseFamilies: familyList,
                calendar: calendar
            )
        }
    }

    public static func resolvePlan(
        plan: BudgetPlanV2,
        asOf: Date,
        knowledgeCutoff: Date,
        revisions: some Sequence<BudgetPlanRevisionV2>,
        expenseFamilies: some Sequence<BudgetSpecialExpenseFamilyInput>,
        calendar: Calendar? = nil
    ) -> BudgetSpecialTrackingResult {
        let resolutionCalendar = calendar ?? plan.businessCalendar
        let lifecycle = lifecycleStatus(for: plan, asOf: asOf, calendar: resolutionCalendar)
        guard plan.isSpecial, plan.cadence == .oneOff, let endInclusive = plan.endInclusive else {
            return conflict(plan: plan, lifecycle: lifecycle, reason: "专项追踪的计划类型或日期范围无效。", calendar: resolutionCalendar)
        }
        guard !plan.expenseScope.isEmpty else {
            return conflict(plan: plan, lifecycle: lifecycle, reason: "专项追踪没有消费范围。", calendar: resolutionCalendar)
        }

        let cycle = plan.cycle(for: plan.anchorStart, calendar: resolutionCalendar)
        let applicable = revisions.filter {
            $0.planID == plan.id &&
            $0.createdAt <= knowledgeCutoff &&
            $0.applies(to: cycle, calendar: resolutionCalendar)
        }.sorted {
            if $0.effectiveCycleStart != $1.effectiveCycleStart {
                return $0.effectiveCycleStart < $1.effectiveCycleStart
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let revision = applicable.last else {
            return conflict(
                plan: plan,
                lifecycle: lifecycle,
                reason: "专项追踪没有可用的额度修订。",
                calendar: resolutionCalendar
            )
        }
        if applicable.filter({ $0.effectiveCycleStart == revision.effectiveCycleStart }).count != 1 {
            return conflict(
                plan: plan,
                lifecycle: lifecycle,
                reason: "专项追踪同一生效日期存在多个额度修订。",
                calendar: resolutionCalendar
            )
        }

        var spent = 0
        var matchedCount = 0
        var excludedForeignCount = 0
        var categorySpent: [String: Int] = [:]
        let planStart = resolutionCalendar.startOfDay(for: plan.anchorStart)
        let planEnd = resolutionCalendar.startOfDay(for: endInclusive)
        for family in expenseFamilies where family.isValid {
            let familyDay = resolutionCalendar.startOfDay(for: family.attributionDate)
            guard family.bookID == plan.bookID,
                  family.countsInBudget,
                  family.createdAt <= knowledgeCutoff,
                  familyDay >= planStart,
                  familyDay <= planEnd,
                  plan.expenseScope.matches(
                    categoryKey: family.categoryKey,
                    tagIDs: family.tagIDs,
                    tagNames: family.tagNames
                  ) else { continue }
            guard family.currencyCode == plan.currencyCode.uppercased() else {
                excludedForeignCount += 1
                continue
            }
            spent += family.netAmountCents
            matchedCount += 1
            if !family.categoryKey.isEmpty {
                categorySpent[family.categoryKey, default: 0] += family.netAmountCents
            }
        }

        let categoryKeys = Set(revision.categoryBudgetsCents.keys).union(categorySpent.keys).sorted()
        return BudgetSpecialTrackingResult(
            plan: plan,
            revision: revision,
            status: .available,
            reason: nil,
            lifecycleStatus: lifecycle,
            totalCents: revision.amountCents,
            spentCents: spent,
            remainingCents: revision.amountCents - spent,
            matchedFamilyCount: matchedCount,
            excludedForeignFamilyCount: excludedForeignCount,
            categoryResults: categoryKeys.map {
                BudgetSpecialCategoryResult(
                    categoryKey: $0,
                    plannedCents: revision.categoryBudgetsCents[$0] ?? 0,
                    spentCents: categorySpent[$0] ?? 0
                )
            },
            calendar: resolutionCalendar
        )
    }

    private static func conflict(
        plan: BudgetPlanV2,
        lifecycle: BudgetSpecialLifecycleStatus,
        reason: String,
        calendar: Calendar
    ) -> BudgetSpecialTrackingResult {
        BudgetSpecialTrackingResult(
            plan: plan,
            revision: nil,
            status: .conflict,
            reason: reason,
            lifecycleStatus: lifecycle,
            totalCents: nil,
            spentCents: nil,
            remainingCents: nil,
            matchedFamilyCount: 0,
            excludedForeignFamilyCount: 0,
            calendar: calendar
        )
    }

    private static func lifecycleStatus(
        for plan: BudgetPlanV2,
        asOf: Date,
        calendar: Calendar
    ) -> BudgetSpecialLifecycleStatus {
        if plan.status == .archived { return .archived }
        let day = calendar.startOfDay(for: asOf)
        if day < calendar.startOfDay(for: plan.anchorStart) { return .upcoming }
        if let end = plan.endInclusive, day > calendar.startOfDay(for: end) { return .ended }
        return .inProgress
    }
}
