import XCTest
@testable import QingJi

final class AppRouterTests: XCTestCase {
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
        for screen in ["settings/budget", "settings/accounts", "settings/backup", "settings/books", "books"] {
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
