import Foundation

/// 当月预算执行状态。
public struct BudgetStatus: Equatable, Sendable {
    public let monthlyBudget: Decimal
    public let spentThisMonth: Decimal
    public let spentToday: Decimal
    /// 月剩余预算（可为负）。
    public let remaining: Decimal
    /// 「今日可花」：(预算 − 今天之前已花) ÷ 含今天的剩余天数 − 今天已花。可为负。
    public let todayAllowance: Decimal
    public let isOverBudget: Bool

    public init(
        monthlyBudget: Decimal,
        spentThisMonth: Decimal,
        spentToday: Decimal,
        remaining: Decimal,
        todayAllowance: Decimal,
        isOverBudget: Bool
    ) {
        self.monthlyBudget = monthlyBudget
        self.spentThisMonth = spentThisMonth
        self.spentToday = spentToday
        self.remaining = remaining
        self.todayAllowance = todayAllowance
        self.isOverBudget = isOverBudget
    }
}

/// 预算前置提醒的核心：把「月底才知道超支」变成「今天就知道还能花多少」。
public enum BudgetEngine {
    public static func status(
        monthlyBudget: Decimal,
        records: [TransactionRecord],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetStatus {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let today = components.day ?? 1
        let dayCount = StatisticsEngine.daysInMonth(
            year: components.year ?? 2000,
            month: components.month ?? 1,
            calendar: calendar
        )

        var spentThisMonth = Decimal(0)
        var spentToday = Decimal(0)
        for record in records where record.kind == .expense {
            let recordComponents = calendar.dateComponents([.year, .month, .day], from: record.date)
            guard recordComponents.year == components.year,
                  recordComponents.month == components.month else { continue }
            spentThisMonth += record.amount
            if recordComponents.day == today {
                spentToday += record.amount
            }
        }

        let spentBeforeToday = spentThisMonth - spentToday
        let remainingDays = Decimal(max(dayCount - today + 1, 1))
        let todayAllowance = (monthlyBudget - spentBeforeToday) / remainingDays - spentToday

        return BudgetStatus(
            monthlyBudget: monthlyBudget,
            spentThisMonth: spentThisMonth,
            spentToday: spentToday,
            remaining: monthlyBudget - spentThisMonth,
            todayAllowance: todayAllowance,
            isOverBudget: spentThisMonth > monthlyBudget
        )
    }
}
