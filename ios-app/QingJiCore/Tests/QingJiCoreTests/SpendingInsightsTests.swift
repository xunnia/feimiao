import XCTest
@testable import QingJiCore

final class SpendingInsightsTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return result
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func project(_ records: [TransactionRecord], month: Int = 6,
                         now: Date? = nil, budget: Decimal? = nil) -> SpendingInsightsProjection {
        let current = StatisticsEngine.monthlySummary(of: records, year: 2026, month: month, calendar: calendar)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: date(2026, month, 1))!
        let parts = calendar.dateComponents([.year, .month], from: previousMonth)
        let previous = StatisticsEngine.monthlySummary(of: records, year: parts.year!, month: parts.month!,
                                                       calendar: calendar)
        return SpendingInsights.project(records: records, current: current, previous: previous,
                                        now: now ?? date(2026, month, 15), monthlyBudget: budget,
                                        calendar: calendar)
    }

    func testSummaryUsesCategoryIncreaseAndDominantShare() {
        let records = [
            TransactionRecord(kind: .expense, amount: 100, categoryName: "餐饮", date: date(2026, 5, 10)),
            TransactionRecord(kind: .expense, amount: 150, categoryName: "餐饮", date: date(2026, 6, 5)),
            TransactionRecord(kind: .expense, amount: 150, categoryName: "餐饮", date: date(2026, 6, 8)),
        ]
        let result = project(records)
        XCTAssertEqual(result.totalChangePercent, 200)
        XCTAssertEqual(result.categoryIncrease?.name, "餐饮")
        XCTAssertEqual(result.categoryIncrease?.amount, 200)
        XCTAssertEqual(result.dominantCategory?.percent, 100)
    }

    func testProfilePrioritizesLargePurchaseAndNeedsFiveFamilies() {
        let small = (1...5).map { day in
            TransactionRecord(kind: .expense, amount: 50, date: date(2026, 6, day))
        }
        XCTAssertNil(project(Array(small.prefix(4))).profile)
        let records = small + [
            TransactionRecord(kind: .expense, amount: 400, date: date(2026, 6, 20)),
            TransactionRecord(kind: .income, amount: 5_000, date: date(2026, 6, 1)),
        ]
        XCTAssertEqual(project(records).profile, .largePurchase)
    }

    func testForecastUsesNetExpenseAndSkipsEarlyDays() {
        let original = UUID()
        let records = [
            TransactionRecord(id: original, kind: .expense, amount: 700, date: date(2026, 6, 10)),
            TransactionRecord(kind: .expense, amount: -100, date: date(2026, 7, 1), refundOfID: original),
        ]
        XCTAssertNil(project(records, now: date(2026, 6, 2), budget: 1_000).forecast)
        let result = project(records, now: date(2026, 6, 15), budget: 1_000)
        XCTAssertEqual(result.forecast?.projected, 1_200)
        XCTAssertEqual(result.forecast?.overBy, 200)
        XCTAssertEqual(result.forecast?.overPercent, 20)
    }
}
