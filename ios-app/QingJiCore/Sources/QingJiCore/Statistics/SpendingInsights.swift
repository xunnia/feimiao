import Foundation

public struct CategorySpendingIncrease: Equatable {
    public let name: String
    public let amount: Decimal
    public let countDifference: Int
}

public struct DominantSpendingCategory: Equatable {
    public let name: String
    public let percent: Int
}

public enum SpendingProfileKind: Equatable {
    case largePurchase, monthToMonth, steadySaver, balanced, carefulRecorder
}

public struct SpendingForecast: Equatable {
    public let projected: Decimal
    public let overBy: Decimal
    public let overPercent: Int
}

public struct SpendingInsightsProjection: Equatable {
    public let totalChangePercent: Int?
    public let categoryIncrease: CategorySpendingIncrease?
    public let dominantCategory: DominantSpendingCategory?
    public let profile: SpendingProfileKind?
    public let forecast: SpendingForecast?

    public var isEmpty: Bool {
        totalChangePercent == nil && categoryIncrease == nil &&
            dominantCategory == nil && profile == nil && forecast == nil
    }
}

/// 「本月 vs 上月」对比卡的一行：两期正额分类的并集（07 D-STAT-008）。
public struct CategoryCompareRow: Equatable, Sendable {
    public let name: String
    public let current: Decimal
    public let previous: Decimal
}

/// 和顶部涨跌徽章同一对窗口（07 §14）。
public struct ComparableMonthWindows: Equatable, Sendable {
    public let current: PeriodSummary
    public let previous: PeriodSummary
    /// true = 当月还没过完，两边都截到前 N 天（上月同期）。
    public let sameProgress: Bool
}

public enum SpendingInsights {
    /// 当月（没过完）= 两边各取前 N 天，N = min(今天日序, 上月天数)；
    /// 已过完的月 = 整月对整月。
    public static func comparableMonthWindows(
        records: [TransactionRecord], year: Int, month: Int,
        now: Date, calendar: Calendar = .current
    ) -> ComparableMonthWindows {
        let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1))
            ?? calendar.startOfDay(for: now)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let currentDays = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let previousDays = calendar.range(of: .day, in: .month, for: previousStart)?.count ?? 30
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let isCurrent = today.year == year && today.month == month
        let currentN = isCurrent ? min(today.day ?? 1, previousDays) : currentDays
        let previousN = isCurrent ? currentN : previousDays
        func end(_ start: Date, _ days: Int) -> Date {
            calendar.date(byAdding: .day, value: max(days, 1) - 1, to: start) ?? start
        }
        return ComparableMonthWindows(
            current: StatisticsEngine.periodSummary(of: records, start: monthStart,
                                                    end: end(monthStart, currentN), calendar: calendar),
            previous: StatisticsEngine.periodSummary(of: records, start: previousStart,
                                                     end: end(previousStart, previousN), calendar: calendar),
            sameProgress: isCurrent
        )
    }

    /// 两期正额分类的并集，按本期、再按上期金额降序取前 [limit] 个。
    /// 上月花过、本期没花的分类也要出现（07 D-STAT-008）。
    public static func compareCategoryRows(
        current: [CategoryTotal], previous: [CategoryTotal], limit: Int = 6
    ) -> [CategoryCompareRow] {
        var order: [String] = []
        var rows: [String: (current: Decimal, previous: Decimal)] = [:]
        for category in current where category.total > 0 {
            if rows[category.name] == nil { order.append(category.name) }
            rows[category.name] = (category.total, rows[category.name]?.previous ?? 0)
        }
        for category in previous where category.total > 0 {
            if rows[category.name] == nil { order.append(category.name) }
            rows[category.name] = (rows[category.name]?.current ?? 0, category.total)
        }
        let list = order.compactMap { name -> CategoryCompareRow? in
            guard let row = rows[name] else { return nil }
            return CategoryCompareRow(name: name, current: row.current, previous: row.previous)
        }
        return Array(list.sorted { lhs, rhs in
            lhs.current != rhs.current ? lhs.current > rhs.current : lhs.previous > rhs.previous
        }.prefix(limit))
    }

    /// [comparison] 传了就用它比总额和分类涨幅（和徽章同窗）；不传时退回
    /// 整月对整月（老调用方和测试）。占比和画像仍看 [current] 整月。
    public static func project(
        records: [TransactionRecord], current: MonthlySummary, previous: MonthlySummary,
        now: Date, monthlyBudget: Decimal?, calendar: Calendar = .current,
        comparison: ComparableMonthWindows? = nil
    ) -> SpendingInsightsProjection {
        let currentTotal = NSDecimalNumber(decimal: current.totalExpense).doubleValue
        let compareCurrentExpense = comparison?.current.totalExpense ?? current.totalExpense
        let comparePreviousExpense = comparison?.previous.totalExpense ?? previous.totalExpense
        let compareCurrentCategories = comparison?.current.expenseByCategory ?? current.expenseByCategory
        let comparePreviousCategories = comparison?.previous.expenseByCategory ?? previous.expenseByCategory
        let compareCurrentTotal = NSDecimalNumber(decimal: compareCurrentExpense).doubleValue
        let previousTotal = NSDecimalNumber(decimal: comparePreviousExpense).doubleValue
        let totalChange: Int?
        if previousTotal > 0 && compareCurrentTotal > 0 {
            let change = (compareCurrentTotal - previousTotal) / previousTotal * 100
            totalChange = abs(change) >= 10 ? Int(change.rounded()) : nil
        } else {
            totalChange = nil
        }

        var largestIncrease: CategorySpendingIncrease?
        for category in compareCurrentCategories where category.total > 0 {
            let old = comparePreviousCategories.first { $0.name == category.name }
            let difference = category.total - (old?.total ?? 0)
            if difference > (largestIncrease?.amount ?? 0) {
                largestIncrease = CategorySpendingIncrease(
                    name: category.name, amount: difference,
                    countDifference: category.count - (old?.count ?? 0)
                )
            }
        }
        if (largestIncrease?.amount ?? 0) < 50 { largestIncrease = nil }

        let largestCategory = current.expenseByCategory.first
        let dominant = largestCategory.flatMap { category -> DominantSpendingCategory? in
            guard category.share >= 0.45 && current.totalExpense >= 200 else { return nil }
            return DominantSpendingCategory(name: category.name,
                                            percent: Int((category.share * 100).rounded()))
        }

        let userExpenses = LedgerPolicy.userRecords(from: records).filter { record in
            guard record.kind == .expense && record.amount > 0 else { return false }
            let parts = calendar.dateComponents([.year, .month], from: record.date)
            return parts.year == current.year && parts.month == current.month
        }
        let profile: SpendingProfileKind?
        if userExpenses.count < 5 {
            profile = nil
        } else {
            let largest = userExpenses.map(\.amount).max() ?? 0
            let income = NSDecimalNumber(decimal: current.totalIncome).doubleValue
            if currentTotal > 0 && NSDecimalNumber(decimal: largest).doubleValue / currentTotal >= 0.35 {
                profile = .largePurchase
            } else if income <= 0 {
                profile = .carefulRecorder
            } else {
                let savingsRate = (income - currentTotal) / income
                profile = savingsRate < 0.05 ? .monthToMonth :
                    (savingsRate >= 0.3 ? .steadySaver : .balanced)
            }
        }

        let date = calendar.dateComponents([.year, .month, .day], from: now)
        var forecast: SpendingForecast?
        if date.year == current.year, date.month == current.month,
           let day = date.day, day >= 3, current.totalExpense > 0,
           let monthlyBudget, monthlyBudget > 0 {
            let monthStart = calendar.date(from: DateComponents(year: current.year, month: current.month, day: 1)) ?? now
            let days = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
            var raw = current.totalExpense / Decimal(day) * Decimal(days)
            var rounded = Decimal.zero
            NSDecimalRound(&rounded, &raw, 2, .plain)
            let over = rounded - monthlyBudget
            let percent = over > 0
                ? Int((NSDecimalNumber(decimal: over / monthlyBudget).doubleValue * 100).rounded()) : 0
            forecast = SpendingForecast(projected: rounded, overBy: over, overPercent: percent)
        }

        return SpendingInsightsProjection(totalChangePercent: totalChange,
                                          categoryIncrease: largestIncrease,
                                          dominantCategory: dominant,
                                          profile: profile, forecast: forecast)
    }
}
