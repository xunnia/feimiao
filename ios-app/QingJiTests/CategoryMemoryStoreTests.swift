import XCTest
@testable import QingJi

@MainActor
final class CategoryMemoryStoreTests: XCTestCase {
    func testDeterministicMerchantLearningRoundTrip() {
        let suiteName = "qingji.category-memory-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CategoryMemoryStore.learn(
            merchant: "中国电信",
            kind: .expense,
            categoryKey: "house_phone",
            defaults: defaults
        )

        XCTAssertEqual(
            CategoryMemoryStore.categoryKey(
                for: "中国电信",
                kind: .expense,
                defaults: defaults
            ),
            "house_phone"
        )
    }

    func testPlatformMerchantIsNotLearned() {
        let suiteName = "qingji.category-memory-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        CategoryMemoryStore.learn(
            merchant: "京东-订单编号349126",
            kind: .expense,
            categoryKey: "shopping",
            defaults: defaults
        )

        XCTAssertNil(CategoryMemoryStore.categoryKey(for: "京东", kind: .expense, defaults: defaults))
    }

    func testUserCreatedCategoryKeyParticipatesInLearning() {
        let suiteName = "qingji.category-memory-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CategoryMemoryStore.learn(
            merchant: "中国电信",
            kind: .expense,
            categoryKey: "custom-\(UUID().uuidString)",
            defaults: defaults
        )

        XCTAssertNotNil(CategoryMemoryStore.categoryKey(
            for: "中国电信",
            kind: .expense,
            defaults: defaults
        ))
    }
}
