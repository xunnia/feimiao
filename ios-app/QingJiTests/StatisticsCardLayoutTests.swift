import XCTest
@testable import QingJi

final class StatisticsCardLayoutTests: XCTestCase {
    func testDefaultAndExplicitlyEmptyStayDistinct() {
        XCTAssertEqual(StatisticsCardLayout.visibleKeys(from: StatisticsCardLayout.unconfigured),
                       ["battery", "budget_ring", "ring", "daily", "ranking", "top5", "sources"])
        XCTAssertEqual(StatisticsCardLayout.visibleKeys(from: ""), [])
    }

    func testUnknownAndDuplicateKeysDoNotReappear() {
        XCTAssertEqual(StatisticsCardLayout.visibleKeys(from: "ring,unknown,ring,daily"), ["ring", "daily"])
        XCTAssertEqual(StatisticsCardLayout.toggled("ring", on: false, in: "ring,daily"), "daily")
        XCTAssertEqual(StatisticsCardLayout.toggled("ring", on: true, in: "daily"), "daily,ring")
    }

    func testReorderPreservesConfiguredVisibility() {
        XCTAssertEqual(StatisticsCardLayout.moved(in: "ring,daily,top5", from: 0, to: 3),
                       "daily,top5,ring")
        XCTAssertEqual(StatisticsCardLayout.applicable(["battery", "ring", "daily", "sources"],
                                                       month: false), ["ring", "daily"])
    }
}
