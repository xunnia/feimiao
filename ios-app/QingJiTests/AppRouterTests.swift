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
