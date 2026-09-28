import XCTest
@testable import QingJiCore

final class MonthlyPaceEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testSameDayComparisonFoldsRefundsAndExcludesOtherMonths() {
        let expenseID = UUID()
        let records = [
            TransactionRecord(kind: .expense, amount: 100, date: date(2026, 6, 20)),
            TransactionRecord(kind: .expense, amount: 20, date: date(2026, 6, 29)),
            TransactionRecord(kind: .expense, amount: 80, date: date(2026, 7, 25)),
            TransactionRecord(kind: .expense, amount: 70, date: date(2026, 7, 28)),
            TransactionRecord(id: expenseID, kind: .expense, amount: 200,
                              date: date(2026, 8, 27)),
            TransactionRecord(kind: .expense, amount: -20,
                              date: date(2026, 8, 28), refundOfID: expenseID),
            TransactionRecord(kind: .expense, amount: 900,
                              date: date(2026, 8, 10), isExcluded: true),
            TransactionRecord(kind: .income, amount: 300, date: date(2026, 8, 27)),
        ]
        let result = MonthlyPaceEngine.project(records: records, year: 2026, month: 8,
                                               now: date(2026, 8, 27), calendar: calendar)
        XCTAssertEqual(result.samples.count, 7)
        XCTAssertEqual(result.samples[4].full, 120)
        XCTAssertEqual(result.samples[4].pace, 100)
        XCTAssertEqual(result.samples[5].full, 150)
        XCTAssertEqual(result.samples[5].pace, 80)
        XCTAssertEqual(result.average, 90)
        XCTAssertEqual(result.current, 180)
        XCTAssertEqual(result.cutoffDay, 27)
        XCTAssertEqual(result.title, "截至 8月27日，本月支出与往常偏高")
    }

    func testHistoricalMonthUsesWholeMonthAndLeapDayCutoff() {
        let result = MonthlyPaceEngine.project(
            records: [TransactionRecord(kind: .expense, amount: 40, date: date(2028, 2, 29))],
            year: 2028, month: 3, now: date(2028, 8, 12), calendar: calendar
        )
        XCTAssertEqual(result.cutoffDay, 31)
        XCTAssertEqual(result.samples[5].pace, 40)
        XCTAssertEqual(result.current, 0)
        XCTAssertEqual(result.title, "截至 3月31日，本月支出与往常偏低")
    }
}
