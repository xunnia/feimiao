import XCTest
@testable import QingJi

final class AppRouterTests: XCTestCase {
    func testImportReviewColdLaunchUsesDedicatedRootRoute() {
        XCTAssertEqual(
            RootTabView.initialPath(for: "settings/import-review"),
            [.importReview]
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
        XCTAssertEqual(RootTabView.initialPath(for: "lending"), [.settings])
        XCTAssertEqual(RootTabView.initialPath(for: "settings/lending"), [.settings])
    }

    func testImportReviewFixtureIsRestrictedToDemoLaunches() {
        XCTAssertTrue(
            RootTabView.usesDemoImportReview(environment: ["QINGJI_DEMO": "1"])
        )
        XCTAssertFalse(
            RootTabView.usesDemoImportReview(environment: ["QINGJI_DEMO": "0"])
        )
        XCTAssertFalse(RootTabView.usesDemoImportReview(environment: [:]))
    }

    @MainActor
    func testLendingDeepLinkTargetsTheSettingsDestination() {
        let router = AppRouter()
        router.handle(url: URL(string: "qingji://settings/lending")!)

        XCTAssertEqual(router.selectedTab, .settings)
        XCTAssertEqual(router.settingsPushTarget, .lending)
    }
}
