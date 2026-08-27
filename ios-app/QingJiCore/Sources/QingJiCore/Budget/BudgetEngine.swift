import Foundation

/// 预算周期，与 Android 端的月度、周度和自定义期间保持同一语义。
public enum BudgetCycle: String, Codable, CaseIterable, Hashable, Sendable {
    case monthly
    case weekly
    case custom
}

/// 一个预算周期的左闭右开日期窗口。
public struct BudgetWindow: Equatable, Sendable {
    public let startInclusive: Date
    public let endExclusive: Date
    public let cycle: BudgetCycle

    public init(startInclusive: Date, endExclusive: Date, cycle: BudgetCycle) {
        self.startInclusive = startInclusive
        self.endExclusive = endExclusive
        self.cycle = cycle
    }
}

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
    /// 根据参考日期构造周期窗口。自定义周期的结束日期按“当天结束”处理。
    public static func window(
        cycle: BudgetCycle,
        referenceDate: Date,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        calendar: Calendar = .current
    ) -> BudgetWindow? {
        let day = calendar.startOfDay(for: referenceDate)
        switch cycle {
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: day)
            guard let start = calendar.date(from: DateComponents(
                year: components.year,
                month: components.month,
                day: 1
            )), let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return nil
            }
            return BudgetWindow(startInclusive: start, endExclusive: end, cycle: cycle)
        case .weekly:
            let weekday = calendar.component(.weekday, from: day)
            let mondayOffset = (weekday + 5) % 7
            guard let start = calendar.date(byAdding: .day, value: -mondayOffset, to: day),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else {
                return nil
            }
            return BudgetWindow(startInclusive: start, endExclusive: end, cycle: cycle)
        case .custom:
            guard let customStart, let customEnd else { return nil }
            let start = calendar.startOfDay(for: customStart)
            guard let inclusiveEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: customEnd)
            ), start < inclusiveEnd else { return nil }
            return BudgetWindow(startInclusive: start, endExclusive: inclusiveEnd, cycle: cycle)
        }
    }

    /// 任意预算窗口的执行状态；月度旧接口继续保留给旧调用方。
    public static func status(
        budget: Decimal,
        cycle: BudgetCycle,
        referenceDate: Date = Date(),
        customStart: Date? = nil,
        customEnd: Date? = nil,
        categoryKey: String? = nil,
        records: [TransactionRecord],
        calendar: Calendar = .current
    ) -> BudgetStatus {
        guard let window = window(
            cycle: cycle,
            referenceDate: referenceDate,
            customStart: customStart,
            customEnd: customEnd,
            calendar: calendar
        ) else {
            return BudgetStatus(
                monthlyBudget: budget,
                spentThisMonth: 0,
                spentToday: 0,
                remaining: budget,
                todayAllowance: budget,
                isOverBudget: false
            )
        }

        let day = calendar.startOfDay(for: referenceDate)
        let today = day < window.startInclusive
            ? window.startInclusive
            : (day >= window.endExclusive
                ? calendar.date(byAdding: .day, value: -1, to: window.endExclusive) ?? day
                : day)
        let userRecords = LedgerPolicy.userRecords(from: records)
        var spent = Decimal.zero
        var spentToday = Decimal.zero
        for record in userRecords where record.kind == .expense && record.amount > 0 {
            if let categoryKey,
               record.categoryKey != categoryKey && record.topCategoryKey != categoryKey {
                continue
            }
            let recordDay = calendar.startOfDay(for: record.date)
            guard recordDay >= window.startInclusive, recordDay < window.endExclusive else {
                continue
            }
            spent += record.amount
            if recordDay == today { spentToday += record.amount }
        }

        let spentBeforeToday = spent - spentToday
        let remainingDays = max(
            calendar.dateComponents([.day], from: today, to: window.endExclusive).day ?? 1,
            1
        )
        let todayAllowance = (budget - spentBeforeToday) / Decimal(remainingDays) - spentToday
        return BudgetStatus(
            monthlyBudget: budget,
            spentThisMonth: spent,
            spentToday: spentToday,
            remaining: budget - spent,
            todayAllowance: todayAllowance,
            isOverBudget: spent > budget
        )
    }

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

        let userRecords = LedgerPolicy.userRecords(from: records)
        var spentThisMonth = Decimal(0)
        var spentToday = Decimal(0)
        for record in userRecords where record.kind == .expense {
            let recordComponents = calendar.dateComponents([.year, .month, .day], from: record.date)
            guard recordComponents.year == components.year,
                  recordComponents.month == components.month else { continue }
            guard record.amount > 0 else { continue }
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
