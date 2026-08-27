import XCTest
@testable import QingJiCore

final class StatisticsEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makeRecords() -> [TransactionRecord] {
        [
            TransactionRecord(kind: .expense, amount: 30, categoryName: "餐饮", date: date(2026, 6, 1)),
            TransactionRecord(kind: .expense, amount: 20, categoryName: "餐饮", date: date(2026, 6, 2)),
            TransactionRecord(kind: .expense, amount: 50, categoryName: "交通", date: date(2026, 6, 2)),
            TransactionRecord(kind: .income, amount: 1000, categoryName: "工资", date: date(2026, 6, 10)),
            TransactionRecord(kind: .transfer, amount: 500, date: date(2026, 6, 5)),
            // 其他月份的记录应被排除
            TransactionRecord(kind: .expense, amount: 999, categoryName: "餐饮", date: date(2026, 5, 31)),
        ]
    }

    func testTotalsExcludeTransfersAndOtherMonths() {
        let summary = StatisticsEngine.monthlySummary(of: makeRecords(), year: 2026, month: 6, calendar: calendar)
        XCTAssertEqual(summary.totalExpense, 100)
        XCTAssertEqual(summary.totalIncome, 1000)
        XCTAssertEqual(summary.balance, 900)
    }

    func testCategoryRankingAndShare() {
        let summary = StatisticsEngine.monthlySummary(of: makeRecords(), year: 2026, month: 6, calendar: calendar)
        XCTAssertEqual(summary.expenseByCategory.map(\.name), ["交通", "餐饮"])
        XCTAssertEqual(summary.expenseByCategory[0].total, 50)
        XCTAssertEqual(summary.expenseByCategory[0].share, 0.5, accuracy: 0.0001)
        XCTAssertEqual(summary.expenseByCategory[1].count, 2)
    }

    func testDailyTotalsCoverWholeMonth() {
        let summary = StatisticsEngine.monthlySummary(of: makeRecords(), year: 2026, month: 6, calendar: calendar)
        XCTAssertEqual(summary.dailyTotals.count, 30)
        XCTAssertEqual(summary.dailyTotals[0].expense, 30)  // 6月1日
        XCTAssertEqual(summary.dailyTotals[1].expense, 70)  // 6月2日
        XCTAssertEqual(summary.dailyTotals[9].income, 1000) // 6月10日
        XCTAssertEqual(summary.dailyTotals[19].expense, 0)
    }

    func testEmptyMonth() {
        let summary = StatisticsEngine.monthlySummary(of: [], year: 2026, month: 2, calendar: calendar)
        XCTAssertEqual(summary.totalExpense, 0)
        XCTAssertEqual(summary.dailyTotals.count, 28)
        XCTAssertTrue(summary.expenseByCategory.isEmpty)
    }

    func testRefundAndExcludedRecordsUseNetAmount() {
        let originalID = UUID()
        let records = [
            TransactionRecord(id: originalID, kind: .expense, amount: 100, categoryName: "购物", date: date(2026, 6, 10)),
            TransactionRecord(kind: .expense, amount: -35, categoryName: "购物", date: date(2026, 6, 10), refundOfID: originalID),
            TransactionRecord(kind: .expense, amount: 500, categoryName: "其他", date: date(2026, 6, 10), isExcluded: true),
        ]
        let summary = StatisticsEngine.monthlySummary(of: records, year: 2026, month: 6, calendar: calendar)
        XCTAssertEqual(summary.totalExpense, 65)
        XCTAssertEqual(summary.expenseByCategory.first?.total, 65)
        XCTAssertEqual(summary.expenseByCategory.first?.count, 1)
    }

    func testPeriodSummaryIncludesBothEndpointsAndPreservesEmptyDays() {
        let records = [
            TransactionRecord(kind: .expense, amount: 30, categoryName: "餐饮", date: date(2026, 6, 29)),
            TransactionRecord(kind: .income, amount: 100, categoryName: "工资", date: date(2026, 6, 30)),
            TransactionRecord(kind: .expense, amount: 20, categoryName: "交通", date: date(2026, 7, 1)),
            TransactionRecord(kind: .transfer, amount: 999, date: date(2026, 6, 30)),
        ]

        let summary = StatisticsEngine.periodSummary(
            of: records,
            start: date(2026, 6, 29),
            end: date(2026, 7, 1),
            calendar: calendar
        )

        XCTAssertEqual(summary.totalExpense, 50)
        XCTAssertEqual(summary.totalIncome, 100)
        XCTAssertEqual(summary.balance, 50)
        XCTAssertEqual(summary.dailyTotals.count, 3)
        XCTAssertEqual(summary.dailyTotals.map { calendar.component(.day, from: $0.date) }, [29, 30, 1])
        XCTAssertEqual(summary.dailyTotals[1].income, 100)
        XCTAssertEqual(summary.dailyTotals[1].expense, 0)
        XCTAssertEqual(summary.expenseByCategory.map(\.name), ["餐饮", "交通"])
    }

    func testPeriodSummaryNormalizesReversedDates() {
        let summary = StatisticsEngine.periodSummary(
            of: [
                TransactionRecord(kind: .expense, amount: 12, date: date(2026, 6, 30)),
            ],
            start: date(2026, 7, 1),
            end: date(2026, 6, 30),
            calendar: calendar
        )

        XCTAssertEqual(summary.start, calendar.startOfDay(for: date(2026, 6, 30)))
        XCTAssertEqual(summary.end, calendar.startOfDay(for: date(2026, 7, 1)))
        XCTAssertEqual(summary.totalExpense, 12)
        XCTAssertEqual(summary.dailyTotals.count, 2)
    }

    func testCategoryTotalsPreferStableTopLevelCategoryName() {
        let summary = StatisticsEngine.monthlySummary(
            of: [
                TransactionRecord(
                    kind: .expense,
                    amount: 28,
                    categoryName: "数码配件",
                    categoryKey: "shop_digital_acc",
                    topCategoryName: "购物消费",
                    topCategoryKey: "shopping",
                    date: date(2026, 6, 8)
                )
            ],
            year: 2026,
            month: 6,
            calendar: calendar
        )

        XCTAssertEqual(summary.expenseByCategory.first?.name, "购物消费")
    }
}
