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
        XCTAssertTrue(MonthlyStatsView.demoMonthRing(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/ring"
        ]))
        XCTAssertFalse(MonthlyStatsView.demoMonthRing(environment: [
            "QINGJI_DEMO": "0", "QINGJI_SCREEN": "stats/month/ring"
        ]))
        XCTAssertTrue(MonthlyStatsView.demoMonthTrend(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/month/trend"
        ]))
        let demo = MonthlyStatsView.demoCategoryDrillDown(environment: [
            "QINGJI_DEMO": "1", "QINGJI_SCREEN": "stats/custom/category-detail"
        ], now: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertEqual(demo?.name, "食品餐饮")
        XCTAssertNil(MonthlyStatsView.demoCategoryDrillDown(environment: [
            "QINGJI_DEMO": "0", "QINGJI_SCREEN": "stats/custom/category-detail"
        ], now: Date()))
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
