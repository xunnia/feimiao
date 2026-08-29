import Foundation
import QingJiCore

/// App 层预算解析入口。所有页面先选出生效预算，再用同一个周期窗口计算状态。
enum BudgetStore {
    static func effectiveTotalBudget(
        from budgets: [Budget],
        selectedBookID: UUID?
    ) -> Budget? {
        let candidates = budgets.filter { budget in
            budget.isActive && budget.categoryKey == nil &&
            (budget.bookID == selectedBookID || budget.bookID == nil)
        }
        return candidates.first(where: { $0.bookID == selectedBookID })
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
