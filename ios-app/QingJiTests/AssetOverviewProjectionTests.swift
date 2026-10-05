import XCTest
@testable import QingJi

final class AssetOverviewProjectionTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return result
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private func snapshot(_ asOf: Date, cash: Decimal = 10000, scope: Int = 1) -> NetWorthSnapshot {
        let value = NetWorthSnapshot(asOf: asOf)
        value.knowledgeCutoff = asOf
        value.cashAssets = cash
        value.physicalAssets = 5000
        value.liabilities = 2000
        value.scopeVersion = scope
        value.quality = .available
        return value
    }
    private func projection(_ points: [NetWorthSnapshot], range: AssetOverviewRange = .all) -> AssetOverviewProjection {
        AssetOverviewProjection(snapshots: points, range: range, now: date(2026, 10, 3), calendar: calendar)
    }
    func testMutuallyExclusiveMetricsAndOneDecimalRounding() {
        let first = snapshot(date(2026, 7, 1))
        let last = snapshot(date(2026, 10, 3), cash: 12345)
        let history = projection([first, last])
        XCTAssertEqual(AssetOverviewMetric.funds.value(last), 12345)
        XCTAssertEqual(AssetOverviewMetric.total.value(last), 17345)
        XCTAssertEqual(AssetOverviewMetric.netWorth.value(last), 15345)
        XCTAssertEqual(history.percentage(.funds, current: 12345), "23.5%")
    }
    func testWindowAndFutureSnapshots() {
        let points = [snapshot(date(2025, 1, 1)), snapshot(date(2026, 7, 5)), snapshot(date(2026, 10, 3)), snapshot(date(2026, 10, 4))]
        XCTAssertEqual(projection(points).points.count, 3)
        XCTAssertEqual(projection(points, range: .quarter).points.count, 2)
    }
    func testMissingZeroNegativeAndOldCurrentAreNotFakeZero() {
        XCTAssertNil(projection([]).percentage(.funds, current: 10000))
        for base in [Decimal.zero, Decimal(-100)] {
            let history = projection([snapshot(date(2026, 7, 1), cash: base), snapshot(date(2026, 10, 3))])
            XCTAssertNil(history.percentage(.funds, current: 10000))
        }
        let history = projection([snapshot(date(2026, 7, 1)), snapshot(date(2026, 10, 3))])
        XCTAssertNil(history.delta(.funds, current: 20000))
    }
    func testScopeAndCurrencyCoverageBreaksCannotBeBridged() {
        let first = snapshot(date(2026, 7, 1))
        let middle = snapshot(date(2026, 8, 1), scope: 2)
        let last = snapshot(date(2026, 10, 3), scope: 2)
        let history = projection([first, middle, last])
        XCTAssertTrue(history.hasTrend)
        XCTAssertEqual(history.breakCount, 1)
        XCTAssertNil(history.percentage(.funds, current: 10000))
        last.uncoveredCurrenciesJSON = "[\"USD\"]"
        XCTAssertFalse(projection([middle, last]).hasTrend)
    }
    func testLegacyAndInvalidCoverageAreNotComparable() {
        let first = snapshot(date(2026, 7, 1))
        let last = snapshot(date(2026, 10, 3))
        first.quality = .legacyUnverified
        XCTAssertFalse(projection([first, last]).hasTrend)
        first.quality = .available
        first.coveredCurrenciesJSON = "not-json"
        XCTAssertFalse(projection([first, last]).hasTrend)
    }
    func testSameDayKeepsLatestKnowledgeWithoutAddingFakeHistory() {
        let first = snapshot(date(2026, 10, 3), cash: 100)
        let last = snapshot(date(2026, 10, 3), cash: 200)
        last.knowledgeCutoff = first.knowledgeCutoff.addingTimeInterval(3600)
        let history = projection([first, last])
        XCTAssertEqual(history.points.count, 1)
        XCTAssertEqual(history.points.first?.cashAssets, 200)
        XCTAssertFalse(history.hasTrend)
    }

    func testMissingValuationAndUnknownPartialReasonsCannotBecomeGrowth() {
        for reasons in ["[]", "[\"缺少估值\"]", "[\"存在未换算外币\",\"缺少估值\"]", "not-json"] {
            let first = snapshot(date(2026, 7, 1))
            let last = snapshot(date(2026, 10, 3), cash: 12000)
            first.quality = .partial
            last.quality = .partial
            first.reasonsJSON = reasons
            last.reasonsJSON = reasons
            first.uncoveredCurrenciesJSON = "[\"USD\"]"
            last.uncoveredCurrenciesJSON = "[\"USD\"]"
            let history = projection([first, last])
            XCTAssertFalse(history.hasTrend, reasons)
            XCTAssertNil(history.delta(.funds, current: 12000), reasons)
            XCTAssertNil(history.percentage(.funds, current: 12000), reasons)
        }
    }

    func testStableCurrencyOnlyPartialSnapshotsRemainComparable() {
        let first = snapshot(date(2026, 7, 1))
        let last = snapshot(date(2026, 10, 3), cash: 12000)
        for point in [first, last] {
            point.quality = .partial
            point.reasonsJSON = "[\"存在未换算外币\"]"
            point.uncoveredCurrenciesJSON = "[\"USD\"]"
        }
        XCTAssertTrue(projection([first, last]).hasTrend)
        XCTAssertEqual(projection([first, last]).percentage(.funds, current: 12000), "20.0%")
        last.quality = .available
        last.reasonsJSON = "[]"
        last.uncoveredCurrenciesJSON = "[]"
        XCTAssertNil(projection([first, last]).delta(.funds, current: 12000))
    }

    func testInvalidQualityCoverageAndVersionsAreNotComparable() {
        let first = snapshot(date(2026, 7, 1))
        let last = snapshot(date(2026, 10, 3))
        for covered in ["[]", "[\"\"]", "[\"USD\"]", "not-json"] {
            first.coveredCurrenciesJSON = covered
            XCTAssertFalse(projection([first, last]).hasTrend)
        }
        first.coveredCurrenciesJSON = "[\"CNY\"]"
        first.reasonsJSON = "[\"缺少估值\"]"
        XCTAssertFalse(projection([first, last]).hasTrend)
        first.reasonsJSON = "[]"
        first.scopeVersion = 0
        XCTAssertFalse(projection([first, last]).hasTrend)
    }

    func testNonPositiveCurrentSuppressesPercentageButPreservesDelta() {
        for current in [Decimal.zero, Decimal(-100)] {
            let history = projection([snapshot(date(2026, 7, 1)), snapshot(date(2026, 10, 3), cash: current)])
            XCTAssertNil(history.percentage(.funds, current: current))
            XCTAssertEqual(history.delta(.funds, current: current), current - 10000)
        }
    }

    @MainActor
    func testNegativeChangeUsesSignedValueBeforeDisplayRounding() {
        let defaults = UserDefaults.standard
        let oldPlaces = defaults.object(forKey: "qingji.moneyDecimalPlaces")
        let oldMode = defaults.object(forKey: "qingji.moneyRoundingMode")
        defer {
            defaults.set(oldPlaces, forKey: "qingji.moneyDecimalPlaces")
            defaults.set(oldMode, forKey: "qingji.moneyRoundingMode")
        }
        defaults.set(0, forKey: "qingji.moneyDecimalPlaces")
        let value = Decimal(string: "-1.2")!
        defaults.set("floor", forKey: "qingji.moneyRoundingMode")
        XCTAssertEqual(AssetsOverviewDashboard.changeAmount(value), AssetsOverviewDashboard.amount(-2))
        defaults.set("ceil", forKey: "qingji.moneyRoundingMode")
        XCTAssertEqual(AssetsOverviewDashboard.changeAmount(value), AssetsOverviewDashboard.amount(-1))
    }
}
