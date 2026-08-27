import XCTest
@testable import QingJi

final class AIPrivacyConsentStoreTests: XCTestCase {
    func testConsentIsIsolatedPerProviderAndCanBeReset() {
        let suiteName = "AIPrivacyConsentStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = UUID()
        let second = UUID()

        XCTAssertFalse(AIPrivacyConsentStore.isAccepted(for: first, defaults: defaults))
        AIPrivacyConsentStore.accept(for: first, defaults: defaults)
        XCTAssertTrue(AIPrivacyConsentStore.isAccepted(for: first, defaults: defaults))
        XCTAssertFalse(AIPrivacyConsentStore.isAccepted(for: second, defaults: defaults))

        AIPrivacyConsentStore.reset(defaults: defaults)
        XCTAssertFalse(AIPrivacyConsentStore.isAccepted(for: first, defaults: defaults))
    }
}
