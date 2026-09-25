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

public enum SpendingInsights {
    public static func project(
        records: [TransactionRecord], current: MonthlySummary, previous: MonthlySummary,
        now: Date, monthlyBudget: Decimal?, calendar: Calendar = .current
    ) -> SpendingInsightsProjection {
        let currentTotal = NSDecimalNumber(decimal: current.totalExpense).doubleValue
        let previousTotal = NSDecimalNumber(decimal: previous.totalExpense).doubleValue
        let totalChange: Int?
        if previousTotal > 0 && currentTotal > 0 {
            let change = (currentTotal - previousTotal) / previousTotal * 100
            totalChange = abs(change) >= 10 ? Int(change.rounded()) : nil
        } else {
            totalChange = nil
        }

        var largestIncrease: CategorySpendingIncrease?
        for category in current.expenseByCategory where category.total > 0 {
            let old = previous.expenseByCategory.first { $0.name == category.name }
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
