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

/// 一天在任意统计区间内的收支合计。
///
/// 月度报表为了兼容既有 UI 使用日号；周和自定义区间需要保留完整日期，
/// 因此单独提供这个跨月份也不会歧义的结果类型。
public struct PeriodDailyTotal: Equatable, Sendable {
    public let date: Date
    public let expense: Decimal
    public let income: Decimal

    public init(date: Date, expense: Decimal, income: Decimal) {
        self.date = date
        self.expense = expense
        self.income = income
    }
}

/// 周或自定义日期区间的统计结果。
public struct PeriodSummary: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let totalExpense: Decimal
    public let totalIncome: Decimal
    public let expenseByCategory: [CategoryTotal]
    public let dailyTotals: [PeriodDailyTotal]

    public init(
        start: Date,
        end: Date,
        totalExpense: Decimal,
        totalIncome: Decimal,
        expenseByCategory: [CategoryTotal],
        dailyTotals: [PeriodDailyTotal]
    ) {
        self.start = start
        self.end = end
        self.totalExpense = totalExpense
        self.totalIncome = totalIncome
        self.expenseByCategory = expenseByCategory
        self.dailyTotals = dailyTotals
    }

    public var balance: Decimal { totalIncome - totalExpense }
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

/// 年度统计结果（消费年报的数据基础）。
public struct YearlySummary: Equatable, Sendable {
    public let year: Int
    public let totalExpense: Decimal
    public let totalIncome: Decimal
    /// 12 个月的支出，下标 0 = 1 月。
    public let monthlyExpenses: [Decimal]
    /// 全年支出分类排行。
    public let expenseByCategory: [CategoryTotal]

    public var balance: Decimal { totalIncome - totalExpense }
}

/// 纯函数统计引擎。转账不计入收支。
public enum StatisticsEngine {
    private static func expenseCategoryName(for record: TransactionRecord) -> String {
        let raw = record.topCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? record.categoryName
            : record.topCategoryName
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "—" || name == "-" || name == "未分类" || name == "其他支出" {
            return "其他"
        }
        return name
    }

    /// 统计闭区间 `[startDay, endDay]`，结束日期按当地日历包含整天。
    /// 退款、报销、转账和“不计入收支”统一交给 LedgerPolicy 处理。
    public static func periodSummary(
        of records: [TransactionRecord],
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) -> PeriodSummary {
        let startDay = calendar.startOfDay(for: min(start, end))
        let endDay = calendar.startOfDay(for: max(start, end))
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let periodRecords = LedgerPolicy.userRecords(from: records).filter {
            $0.kind != .transfer && $0.date >= startDay && $0.date < endExclusive
        }

        var totalExpense = Decimal(0)
        var totalIncome = Decimal(0)
        var categoryTotals: [String: (total: Decimal, count: Int)] = [:]
        var dailyTotals: [Date: (expense: Decimal, income: Decimal)] = [:]

        for record in periodRecords {
            let day = calendar.startOfDay(for: record.date)
            switch record.kind {
            case .expense:
                totalExpense += record.amount
                var dayEntry = dailyTotals[day] ?? (0, 0)
                dayEntry.expense += record.amount
                dailyTotals[day] = dayEntry
                let name = expenseCategoryName(for: record)
                var entry = categoryTotals[name] ?? (0, 0)
                entry.total += record.amount
                entry.count += 1
                categoryTotals[name] = entry
            case .income:
                totalIncome += record.amount
                var dayEntry = dailyTotals[day] ?? (0, 0)
                dayEntry.income += record.amount
                dailyTotals[day] = dayEntry
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

        let dayCount = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        let daily = (0..<max(dayCount, 1)).compactMap { offset -> PeriodDailyTotal? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }
            let totals = dailyTotals[day] ?? (0, 0)
            return PeriodDailyTotal(date: day, expense: totals.expense, income: totals.income)
        }

        return PeriodSummary(
            start: startDay,
            end: endDay,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            expenseByCategory: byCategory,
            dailyTotals: daily
        )
    }

    public static func yearlySummary(
        of records: [TransactionRecord],
        year: Int,
        calendar: Calendar = .current
    ) -> YearlySummary {
        let userRecords = LedgerPolicy.userRecords(from: records)
        var totalExpense = Decimal(0)
        var totalIncome = Decimal(0)
        var monthlyExpenses = [Decimal](repeating: 0, count: 12)
        var categoryTotals: [String: (total: Decimal, count: Int)] = [:]

        for record in userRecords where record.kind != .transfer {
            let components = calendar.dateComponents([.year, .month], from: record.date)
            guard components.year == year, let month = components.month else { continue }
            switch record.kind {
            case .expense:
                totalExpense += record.amount
                monthlyExpenses[month - 1] += record.amount
                let name = expenseCategoryName(for: record)
                var entry = categoryTotals[name] ?? (0, 0)
                entry.total += record.amount
                entry.count += 1
                categoryTotals[name] = entry
            case .income:
                totalIncome += record.amount
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

        return YearlySummary(
            year: year,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            monthlyExpenses: monthlyExpenses,
            expenseByCategory: byCategory
        )
    }

    public static func monthlySummary(
        of records: [TransactionRecord],
        year: Int,
        month: Int,
        calendar: Calendar = .current
    ) -> MonthlySummary {
        let monthRecords = LedgerPolicy.userRecords(from: records).filter { record in
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
                let name = expenseCategoryName(for: record)
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
