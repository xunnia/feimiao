import XCTest
@testable import QingJiCore

final class BudgetEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ day: Int, month: Int = 6) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    func testTodayAllowance() {
        // 6 月预算 3000；6 月 1~9 日花 900，今天（10 日）花 50。
        // 今日可花 = (3000 - 900) / 21 - 50 = 50
        var records = [TransactionRecord]()
        records.append(TransactionRecord(kind: .expense, amount: 900, date: date(5)))
        records.append(TransactionRecord(kind: .expense, amount: 50, date: date(10)))
        let status = BudgetEngine.status(monthlyBudget: 3000, records: records, on: date(10), calendar: calendar)
        XCTAssertEqual(status.spentThisMonth, 950)
        XCTAssertEqual(status.spentToday, 50)
        XCTAssertEqual(status.remaining, 2050)
        XCTAssertEqual(status.todayAllowance, 50)
        XCTAssertFalse(status.isOverBudget)
    }

    func testOverBudget() {
        let records = [TransactionRecord(kind: .expense, amount: 3200, date: date(8))]
        let status = BudgetEngine.status(monthlyBudget: 3000, records: records, on: date(10), calendar: calendar)
        XCTAssertTrue(status.isOverBudget)
        XCTAssertEqual(status.remaining, -200)
        XCTAssertLessThan(status.todayAllowance, 0)
    }

    func testOtherMonthsExcluded() {
        let records = [
            TransactionRecord(kind: .expense, amount: 500, date: date(20, month: 5)),
            TransactionRecord(kind: .income, amount: 8000, date: date(5)),
            TransactionRecord(kind: .expense, amount: 100, date: date(5)),
        ]
        let status = BudgetEngine.status(monthlyBudget: 3000, records: records, on: date(10), calendar: calendar)
        XCTAssertEqual(status.spentThisMonth, 100)
    }
}

final class AccountBalanceCalculatorTests: XCTestCase {
    func testBalanceWithTransfers() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            TransactionRecord(kind: .income, amount: 1000, accountName: "微信", date: day),
            TransactionRecord(kind: .expense, amount: 300, accountName: "微信", date: day),
            TransactionRecord(kind: .transfer, amount: 200, accountName: "微信", toAccountName: "银行卡", date: day),
            TransactionRecord(kind: .transfer, amount: 50, accountName: "银行卡", toAccountName: "微信", date: day),
            TransactionRecord(kind: .expense, amount: 999, accountName: "支付宝", date: day),
        ]
        let balance = AccountBalanceCalculator.balance(accountName: "微信", initialBalance: 100, records: records)
        // 100 + 1000 - 300 - 200 + 50 = 650
        XCTAssertEqual(balance, 650)
    }
}

final class YearlySummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    func testYearlyTotalsAndMonthlyBuckets() {
        func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        let records = [
            TransactionRecord(kind: .expense, amount: 100, categoryName: "餐饮", date: date(1, 5)),
            TransactionRecord(kind: .expense, amount: 200, categoryName: "交通", date: date(6, 5)),
            TransactionRecord(kind: .income, amount: 5000, categoryName: "工资", date: date(6, 10)),
            TransactionRecord(kind: .expense, amount: 999, categoryName: "餐饮", date: date(3, 1, year: 2025)),
        ]
        let summary = StatisticsEngine.yearlySummary(of: records, year: 2026, calendar: calendar)
        XCTAssertEqual(summary.totalExpense, 300)
        XCTAssertEqual(summary.totalIncome, 5000)
        XCTAssertEqual(summary.monthlyExpenses[0], 100)
        XCTAssertEqual(summary.monthlyExpenses[5], 200)
        XCTAssertEqual(summary.monthlyExpenses[2], 0)
        XCTAssertEqual(summary.expenseByCategory.first?.name, "交通")
    }
}
