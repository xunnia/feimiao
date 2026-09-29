import XCTest
@testable import QingJi

final class DrawerLayoutTests: XCTestCase {
    private let defaultKeys = [
        "stats", "assets", "budget", "savings", "assistant", "categories",
        "tags", "import", "reimburse", "recurring", "autorecord"
    ]

    func testEmptyStoredOrderFallsBackToAndroidDefault() {
        XCTAssertEqual(DrawerLayout.order(from: "").map(\.rawValue), defaultKeys)
    }

    func testStoredOrderDropsUnknownAndDuplicateKeysAndAppendsMissingOnes() {
        let order = DrawerLayout.order(from: "tags, stats,ai-search,tags,budget")
        XCTAssertEqual(Array(order.prefix(3)).map(\.rawValue), ["tags", "stats", "budget"])
        XCTAssertEqual(order.count, DrawerLayout.Item.allCases.count)
        XCTAssertEqual(Set(order), Set(DrawerLayout.Item.allCases))
        // 补进来的项保持默认相对顺序。
        XCTAssertEqual(Array(order.dropFirst(3)).map(\.rawValue),
                       defaultKeys.filter { !["tags", "stats", "budget"].contains($0) })
    }

    func testStoredValueRoundTrips() {
        let order = DrawerLayout.order(from: "recurring,assistant")
        XCTAssertEqual(DrawerLayout.order(from: DrawerLayout.storedValue(for: order)), order)
    }

    func testMoveTakesTargetPosition() {
        let order = DrawerLayout.order(from: "")
        let movedDown = DrawerLayout.move(.stats, onto: .budget, in: order)
        XCTAssertEqual(Array(movedDown.prefix(3)), [.assets, .budget, .stats])
        let movedUp = DrawerLayout.move(.tags, onto: .stats, in: order)
        XCTAssertEqual(movedUp.first, .tags)
        XCTAssertEqual(DrawerLayout.move(.stats, onto: .stats, in: order), order)
    }

    func testCollapsedCountMatchesAndroid() {
        XCTAssertEqual(DrawerLayout.collapsedCount, 5)
    }

    func testBookOrderPutsDefaultFirstThenStarredStable() {
        struct Stub { let name: String; let isDefault: Bool; let isStarred: Bool }
        let books = [
            Stub(name: "旅行", isDefault: false, isStarred: false),
            Stub(name: "宠物", isDefault: false, isStarred: true),
            Stub(name: "总账本", isDefault: true, isStarred: false),
            Stub(name: "生意", isDefault: false, isStarred: false),
            Stub(name: "家庭", isDefault: false, isStarred: true)
        ]
        let ordered = DrawerLayout.orderedBooks(books, isDefault: \.isDefault, isStarred: \.isStarred)
        XCTAssertEqual(ordered.map(\.name), ["总账本", "宠物", "家庭", "旅行", "生意"])
    }

    func testBookCoverKeysAcceptAndroidPathsAndLegacyNames() {
        XCTAssertEqual(BookCoverCatalog.key(for: "assets/book_covers/travel.png"), "travel")
        XCTAssertEqual(BookCoverCatalog.key(for: "pet"), "pet")
        XCTAssertEqual(BookCoverCatalog.key(for: "food"), "dining")
        XCTAssertEqual(BookCoverCatalog.key(for: "daily"), "default")
        XCTAssertEqual(BookCoverCatalog.key(for: ""), "default")
        XCTAssertEqual(BookCoverCatalog.key(for: "📒"), "default")
        XCTAssertEqual(BookCoverCatalog.storedValue(for: "couple"), "assets/book_covers/couple.png")
        XCTAssertEqual(BookCoverCatalog.imageName(for: "assets/book_covers/baby.png"), "BookCover-baby")
    }
}
