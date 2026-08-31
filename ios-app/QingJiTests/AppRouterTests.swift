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
    }
}
