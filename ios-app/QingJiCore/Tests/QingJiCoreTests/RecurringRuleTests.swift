import XCTest
@testable import QingJiCore

final class RecurringRuleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return value
    }

    func testMonthlyRuleKeepsTheOriginalAnchorDay() {
        let first = date(2026, 1, 31, 9, 30)
        let february = RecurringPeriod.monthly.advance(
            first,
            anchorDay: 31,
            calendar: calendar
        )
        let march = RecurringPeriod.monthly.advance(
            february,
            anchorDay: 31,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.day, from: february), 28)
        XCTAssertEqual(calendar.component(.day, from: march), 31)
        XCTAssertEqual(calendar.component(.hour, from: february), 9)
        XCTAssertEqual(calendar.component(.minute, from: february), 30)
    }

    func testPreviewStopsAtEndDate() {
        let first = date(2026, 8, 27)
        let dates = RecurringPeriod.weekly.previewDates(
            from: first,
            count: 10,
            endDate: date(2026, 9, 10),
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(dates.map { calendar.component(.day, from: $0) }, [27, 3, 10])
    }

    func testDailyAndYearlyAdvance() {
        let day = date(2026, 12, 31)
        let nextDay = RecurringPeriod.daily.advance(day, calendar: calendar)
        let nextYear = RecurringPeriod.yearly.advance(
            date(2024, 2, 29),
            anchorDay: 29,
            calendar: calendar
        )

        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: nextDay),
                       DateComponents(year: 2027, month: 1, day: 1))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: nextYear),
                       DateComponents(year: 2025, month: 2, day: 28))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
