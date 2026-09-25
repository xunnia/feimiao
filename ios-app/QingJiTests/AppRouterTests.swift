import XCTest
@testable import QingJi

final class AppRouterTests: XCTestCase {
    func testEveryStatisticsColdLaunchAliasUsesStatisticsRoot() {
        for scope in ["week", "month", "year", "custom"] {
            XCTAssertEqual(RootTabView.initialPath(for: "stats/\(scope)"), [.statistics])
            XCTAssertEqual(RootTabView.initialPath(for: "stats-\(scope)"), [.statistics])
        }
        XCTAssertEqual(RootTabView.initialPath(for: "stats/custom/category-detail"), [.statistics])
        XCTAssertEqual(RootTabView.initialPath(for: "stats/month/ring"), [.statistics])
        XCTAssertEqual(RootTabView.initialPath(for: "stats/month/trend"), [.statistics])
        XCTAssertEqual(RootTabView.initialPath(for: "stats/month/trend/income"), [.statistics])
        XCTAssertEqual(RootTabView.initialPath(for: "stats/month/top5"), [.statistics])
        XCTAssertEqual(RootTabView.initialPath(for: "stats/month/sources"), [.statistics])
        XCTAssertEqual(RootTabView.initialPath(for: "stats/month/picker"), [.statistics])
        XCTAssertEqual(RootTabView.initialPath(for: "stats/month/books"), [.statistics])
        XCTAssertEqual(RootTabView.initialPath(for: "stats/month/book-selected"), [.statistics])
        for route in ["stats/month/pace", "stats/month/pace/activity", "stats/month/pace/detail",
                      "stats/month/budget-ring"] {
            XCTAssertEqual(RootTabView.initialPath(for: route), [.statistics])
        }
        XCTAssertEqual(MonthlyStatsView.demoMonthPriorityCard(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/pace/activity"
        ]), "stats-month-pace-activity")
        XCTAssertEqual(MonthlyStatsView.demoMonthPriorityCard(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/pace/detail"
        ]), "stats-month-pace-activity")
        XCTAssertTrue(MonthlyStatsView.demoMonthPicker(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/picker"
        ]))
        XCTAssertTrue(MonthlyStatsView.demoBookPicker(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/books"
        ]))
        XCTAssertFalse(MonthlyStatsView.demoBookPicker(environment: [
            "QINGJI_DEMO": "0", "QINGJI_SCREEN": "stats/month/books"
        ]))
        XCTAssertTrue(MonthlyStatsView.demoSelectedBook(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/book-selected"
        ]))
        XCTAssertEqual(MonthlyStatsView.demoMonthBottom(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/top5"
        ]), "stats-month-top5")
        XCTAssertEqual(MonthlyStatsView.demoMonthBottom(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/sources"
        ]), "stats-month-sources")
        XCTAssertTrue(MonthlyStatsView.demoMonthRing(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/ring"
        ]))
        XCTAssertFalse(MonthlyStatsView.demoMonthRing(environment: [
            "QINGJI_DEMO": "0", "QINGJI_SCREEN": "stats/month/ring"
        ]))
        XCTAssertTrue(MonthlyStatsView.demoMonthTrend(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/trend"
        ]))
        XCTAssertTrue(MonthlyStatsView.demoMonthTrendIncome(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/trend/income"
        ]))
        let demo = MonthlyStatsView.demoCategoryDrillDown(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/custom/category-detail"
        ], now: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertEqual(demo?.name, "食品餐饮")
        XCTAssertNil(MonthlyStatsView.demoCategoryDrillDown(environment: [
            "QINGJI_DEMO": "0", "QINGJI_SCREEN": "stats/custom/category-detail"
        ], now: Date()))
    }

    func testMonthPickerUsesYearAndMonthWithoutFutureDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let maximum = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27))!
        let future = MonthPickerSheet.selectedMonth(year: 2027, month: 12,
                                                     maximumDate: maximum, calendar: calendar)
        XCTAssertEqual(calendar.component(.year, from: future), 2026)
        XCTAssertEqual(calendar.component(.month, from: future), 8)
        XCTAssertEqual(calendar.component(.day, from: future), 1)
        let historical = MonthPickerSheet.selectedMonth(year: 2025, month: 12,
                                                         maximumDate: maximum, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: historical), 12)
    }

    func testImportReviewColdLaunchUsesDedicatedRootRoute() {
        XCTAssertEqual(
            RootTabView.initialPath(for: "settings/import-review"),
            [.importReview]
        )
    }

    func testImportReviewDemoLaunchUsesStableRootOnlyForThatRoute() {
        XCTAssertTrue(
            RootTabView.shouldRenderDemoImportReviewAsRoot(environment: [
                "QINGJI_DEMO": "1",
                "QINGJI_SCREEN": "settings/import-review"
            ])
        )
        XCTAssertFalse(
            RootTabView.shouldRenderDemoImportReviewAsRoot(environment: [
                "QINGJI_DEMO": "1",
                "QINGJI_SCREEN": "settings"
            ])
        )
        XCTAssertFalse(
            RootTabView.shouldRenderDemoImportReviewAsRoot(environment: [
                "QINGJI_DEMO": "0",
                "QINGJI_SCREEN": "settings/import-review"
            ])
        )
    }

    func testOrdinarySettingsDestinationsStillUseSettingsRoot() {
        for screen in ["settings/budget", "settings/accounts", "settings/backup"] {
            XCTAssertEqual(RootTabView.initialPath(for: screen), [.settings])
        }
    }

    func testPrimaryAndroidInformationArchitectureRoutesRemainStable() {
        XCTAssertEqual(RootTabView.initialPath(for: "home"), [])
        XCTAssertEqual(RootTabView.initialPath(for: "search"), [.search])
        XCTAssertEqual(RootTabView.initialPath(for: "transactions"), [.transactions])
        XCTAssertEqual(RootTabView.initialPath(for: "stats/month"), [.statistics])
    }
}
