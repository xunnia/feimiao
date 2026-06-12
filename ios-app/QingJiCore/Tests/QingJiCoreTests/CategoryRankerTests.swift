import XCTest
@testable import QingJiCore

final class CategoryRankerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
    }

    func testFrequencyWins() {
        let ranked = CategoryRanker.rank(
            defaultOrder: ["dining", "transport", "shopping"],
            usages: [
                ("shopping", date(day: 1, hour: 15)),
                ("shopping", date(day: 2, hour: 15)),
                ("transport", date(day: 3, hour: 15)),
            ],
            at: date(day: 10, hour: 15),
            calendar: calendar
        )
        XCTAssertEqual(ranked, ["shopping", "transport", "dining"])
    }

    func testTimeBucketBoostBeatsRawFrequency() {
        // transport 用过 2 次但都在晚上；dining 只用过 1 次但和当前同为早晨时段，
        // 时段加成（+2）应让 dining 排前面。
        let ranked = CategoryRanker.rank(
            defaultOrder: ["transport", "dining"],
            usages: [
                ("transport", date(day: 1, hour: 20)),
                ("transport", date(day: 2, hour: 20)),
                ("dining", date(day: 3, hour: 8)),
            ],
            at: date(day: 10, hour: 8),
            calendar: calendar
        )
        XCTAssertEqual(ranked.first, "dining")
    }

    func testTiesKeepDefaultOrder() {
        let ranked = CategoryRanker.rank(
            defaultOrder: ["a", "b", "c"],
            usages: [],
            at: date(day: 1, hour: 12),
            calendar: calendar
        )
        XCTAssertEqual(ranked, ["a", "b", "c"])
    }

    func testTimeBuckets() {
        XCTAssertEqual(CategoryRanker.timeBucket(forHour: 8), 0)
        XCTAssertEqual(CategoryRanker.timeBucket(forHour: 12), 1)
        XCTAssertEqual(CategoryRanker.timeBucket(forHour: 15), 2)
        XCTAssertEqual(CategoryRanker.timeBucket(forHour: 19), 3)
        XCTAssertEqual(CategoryRanker.timeBucket(forHour: 23), 4)
        XCTAssertEqual(CategoryRanker.timeBucket(forHour: 2), 4)
    }
}
