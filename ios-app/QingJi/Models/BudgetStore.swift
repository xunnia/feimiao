import Foundation
import QingJiCore

/// App 层预算解析入口。所有页面先选出生效预算，再用同一个周期窗口计算状态。
enum BudgetStore {
    static func effectiveTotalBudget(
        from budgets: [Budget],
        selectedBookID: UUID?,
        fallbackBookID: UUID? = nil
    ) -> Budget? {
        let preferredBookID = selectedBookID ?? fallbackBookID
        let candidates = budgets.filter { budget in
            budget.isActive && budget.categoryKey == nil &&
            (budget.bookID == selectedBookID || budget.bookID == fallbackBookID || budget.bookID == nil)
        }
        return candidates.first(where: { $0.bookID == preferredBookID })
            ?? candidates.first(where: { $0.bookID == nil })
    }

    static func window(
        for budget: Budget,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetWindow? {
        BudgetEngine.window(
            cycle: budget.cycle,
            referenceDate: referenceDate,
            customStart: budget.periodStart,
            customEnd: budget.periodEnd,
            calendar: calendar
        )
    }

    /// Resolves a V2 plan over an arbitrary display window. The returned
    /// BudgetStatus keeps the legacy view model usable while honoring cycle
    /// revisions and one-cycle overrides.
    static func statusV2(
        plans: [BudgetPlanV2],
        revisions: [BudgetPlanRevisionV2],
        overrides: [BudgetCycleOverrideV2],
        bookID: UUID,
        records: [TransactionRecord],
        windowStart: Date,
        windowEndExclusive: Date,
        referenceDate: Date,
        knowledgeCutoff: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetStatus? {
        let start = calendar.startOfDay(for: windowStart)
        let end = calendar.startOfDay(for: windowEndExclusive)
        guard start < end else { return nil }
        // Keep the spending projection on the same book/currency and knowledge
        // snapshot as the plan resolver. Callers often pass a ledger-wide
        // collection because that is what SwiftData queries provide.
        let scopedRecords = records.filter { record in
            record.bookID == bookID &&
            record.currencyCode.uppercased() == "CNY" &&
            (record.createdAt == nil || record.createdAt! <= knowledgeCutoff)
        }
        let resolution = BudgetPlanV2Resolver.resolveWindow(
            startInclusive: start,
            endExclusive: end,
            bookID: bookID,
            knowledgeCutoff: knowledgeCutoff,
            plans: plans,
            revisions: revisions,
            overrides: overrides,
            calendar: calendar
        )
        guard resolution.status == .available,
              let plannedCents = resolution.plannedCents else {
            return nil
        }

        let planned = Decimal(plannedCents) / Decimal(100)
        let endInclusive = calendar.date(byAdding: .day, value: -1, to: end) ?? start
        let windowStatus = BudgetEngine.status(
            budget: planned,
            cycle: .custom,
            referenceDate: referenceDate,
            customStart: start,
            customEnd: endInclusive,
            records: scopedRecords,
            calendar: calendar
        )

        var todayAllowance = windowStatus.todayAllowance
        let dayResolution = BudgetPlanV2Resolver.resolveDay(
            day: referenceDate,
            bookID: bookID,
            knowledgeCutoff: knowledgeCutoff,
            plans: plans,
            revisions: revisions,
            overrides: overrides,
            calendar: calendar
        )
        if dayResolution.status == .available,
           let cycle = dayResolution.cycle,
           let revision = dayResolution.revision {
            let cycleCents = dayResolution.override?.targetAmountCents ?? revision.amountCents
            let cycleEndInclusive = cycle.endInclusive
            let cycleStatus = BudgetEngine.status(
                budget: Decimal(cycleCents) / Decimal(100),
                cycle: .custom,
                referenceDate: referenceDate,
                customStart: cycle.start,
                customEnd: cycleEndInclusive,
                records: scopedRecords,
                calendar: calendar
            )
            todayAllowance = cycleStatus.todayAllowance
        }

        return BudgetStatus(
            monthlyBudget: planned,
            spentThisMonth: windowStatus.spentThisMonth,
            spentToday: windowStatus.spentToday,
            remaining: planned - windowStatus.spentThisMonth,
            todayAllowance: todayAllowance,
            isOverBudget: windowStatus.spentThisMonth > planned
        )
    }

    static func currentStatusV2(
        plans: [BudgetPlanV2],
        revisions: [BudgetPlanRevisionV2],
        overrides: [BudgetCycleOverrideV2],
        bookID: UUID,
        records: [TransactionRecord],
        referenceDate: Date = Date(),
        knowledgeCutoff: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetStatus? {
        let day = BudgetPlanV2Resolver.resolveDay(
            day: referenceDate,
            bookID: bookID,
            knowledgeCutoff: knowledgeCutoff,
            plans: plans,
            revisions: revisions,
            overrides: overrides,
            calendar: calendar
        )
        guard day.status == .available, let cycle = day.cycle else { return nil }
        return statusV2(
            plans: plans,
            revisions: revisions,
            overrides: overrides,
            bookID: bookID,
            records: records,
            windowStart: cycle.start,
            windowEndExclusive: cycle.endExclusive,
            referenceDate: referenceDate,
            knowledgeCutoff: knowledgeCutoff,
            calendar: calendar
        )
    }

    static func status(
        for budget: Budget,
        transactions: [MoneyTransaction],
        categoryKey: String? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetStatus {
        let scopedCategoryKey = categoryKey ?? budget.categoryKey
        return BudgetEngine.status(
            budget: budget.amount,
            cycle: budget.cycle,
            referenceDate: referenceDate,
            customStart: budget.periodStart,
            customEnd: budget.periodEnd,
            categoryKey: scopedCategoryKey,
            records: transactions.map(\.record),
            calendar: calendar
        )
    }

    static func status(
        for budget: Budget,
        records: [TransactionRecord],
        categoryKey: String? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetStatus {
        let scopedCategoryKey = categoryKey ?? budget.categoryKey
        return BudgetEngine.status(
            budget: budget.amount,
            cycle: budget.cycle,
            referenceDate: referenceDate,
            customStart: budget.periodStart,
            customEnd: budget.periodEnd,
            categoryKey: scopedCategoryKey,
            records: records,
            calendar: calendar
        )
    }
}
