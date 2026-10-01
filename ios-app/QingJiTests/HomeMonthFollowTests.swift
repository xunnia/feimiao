import XCTest
@testable import QingJi

/// 主页跨月：App 常驻后台从 9 月过到 10 月，回来要自动显示 10 月；
/// 用户自己翻到的月份不被打断。数字和安卓 home_month_follow_test 一样。
final class HomeMonthFollowTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int = 1, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func follow(_ shown: Date, _ synced: Date, _ now: Date) -> Date {
        HomeView.monthAfterClockChange(shown: shown, syncedNow: synced, now: now, calendar: calendar)
    }

    func testCurrentMonthFollowsIntoNextMonth() {
        XCTAssertEqual(follow(date(2026, 9), date(2026, 9, 30, 23), date(2026, 10, 1, 8)), date(2026, 10, 1, 0))
    }

    func testCrossesYearBoundary() {
        XCTAssertEqual(follow(date(2026, 12), date(2026, 12, 31, 22), date(2027, 1, 1, 0)), date(2027, 1, 1, 0))
    }

    func testLongAbsenceJumpsToCurrentMonth() {
        XCTAssertEqual(follow(date(2026, 9), date(2026, 9, 10), date(2027, 2, 3)), date(2027, 2, 1, 0))
    }

    func testManuallyBrowsedMonthStays() {
        XCTAssertEqual(follow(date(2026, 7), date(2026, 9, 30), date(2026, 10, 1)), date(2026, 7, 1, 0))
    }

    func testSameMonthResumeKeepsMonth() {
        XCTAssertEqual(follow(date(2026, 10), date(2026, 10, 1, 9), date(2026, 10, 1, 21)), date(2026, 10, 1, 0))
    }

    func testClockMovedBackNeverShowsFutureMonth() {
        XCTAssertEqual(follow(date(2026, 8), date(2026, 10, 1), date(2026, 9, 15)), date(2026, 8, 1, 0))
        XCTAssertEqual(follow(date(2026, 10), date(2026, 9, 1), date(2026, 9, 15)), date(2026, 9, 1, 0))
    }
}
