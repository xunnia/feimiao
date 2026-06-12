import Foundation

/// 某分类在统计周期内的合计。
public struct CategoryTotal: Equatable, Sendable {
    public let name: String
    public let total: Decimal
    /// 占总支出（或总收入）的比例，0...1。
    public let share: Double
    public let count: Int

    public init(name: String, total: Decimal, share: Double, count: Int) {
        self.name = name
        self.total = total
        self.share = share
        self.count = count
    }
}

/// 单日收支合计。
public struct DailyTotal: Equatable, Sendable {
    public let day: Int
    public let expense: Decimal
    public let income: Decimal

    public init(day: Int, expense: Decimal, income: Decimal) {
        self.day = day
        self.expense = expense
        self.income = income
    }
}

/// 月度统计结果。
public struct MonthlySummary: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let totalExpense: Decimal
    public let totalIncome: Decimal
    /// 按金额降序的支出分类排行。
    public let expenseByCategory: [CategoryTotal]
    /// 该月每天一条，含无消费日。
    public let dailyTotals: [DailyTotal]

    public var balance: Decimal { totalIncome - totalExpense }
}

/// 纯函数统计引擎。转账不计入收支。
public enum StatisticsEngine {
    public static func monthlySummary(
        of records: [TransactionRecord],
        year: Int,
        month: Int,
        calendar: Calendar = .current
    ) -> MonthlySummary {
        let monthRecords = records.filter { record in
            guard record.kind != .transfer else { return false }
            let components = calendar.dateComponents([.year, .month], from: record.date)
            return components.year == year && components.month == month
        }

        var totalExpense = Decimal(0)
        var totalIncome = Decimal(0)
        var categoryTotals: [String: (total: Decimal, count: Int)] = [:]
        var dailyExpense: [Int: Decimal] = [:]
        var dailyIncome: [Int: Decimal] = [:]

        for record in monthRecords {
            let day = calendar.component(.day, from: record.date)
            switch record.kind {
            case .expense:
                totalExpense += record.amount
                dailyExpense[day, default: 0] += record.amount
                let name = record.categoryName.isEmpty ? "—" : record.categoryName
                var entry = categoryTotals[name] ?? (0, 0)
                entry.total += record.amount
                entry.count += 1
                categoryTotals[name] = entry
            case .income:
                totalIncome += record.amount
                dailyIncome[day, default: 0] += record.amount
            case .transfer:
                break
            }
        }

        let expenseDouble = NSDecimalNumber(decimal: totalExpense).doubleValue
        let byCategory = categoryTotals
            .map { name, entry in
                CategoryTotal(
                    name: name,
                    total: entry.total,
                    share: expenseDouble > 0
                        ? NSDecimalNumber(decimal: entry.total).doubleValue / expenseDouble
                        : 0,
                    count: entry.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.name < rhs.name
            }

        let dayCount = daysInMonth(year: year, month: month, calendar: calendar)
        let daily = (1...dayCount).map { day in
            DailyTotal(day: day, expense: dailyExpense[day] ?? 0, income: dailyIncome[day] ?? 0)
        }

        return MonthlySummary(
            year: year,
            month: month,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            expenseByCategory: byCategory,
            dailyTotals: daily
        )
    }

    static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 30
        }
        return range.count
    }
}
