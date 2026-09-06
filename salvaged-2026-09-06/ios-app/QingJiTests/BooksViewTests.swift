import XCTest
@testable import QingJi

final class BooksViewTests: XCTestCase {
    func testAndroidCoverPathsNormalizeToCanonicalKeys() {
        XCTAssertEqual(
            BookCoverCatalog.normalized("assets/book_covers/default.png"),
            "daily"
        )
        XCTAssertEqual(
            BookCoverCatalog.normalized("assets/book_covers/dining.png"),
            "food"
        )
        XCTAssertEqual(
            BookCoverCatalog.normalized("assets\\book_covers\\shopping.png"),
            "shopping"
        )
        XCTAssertEqual(
            BookCoverCatalog.normalized("shopping"),
            "shopping"
        )
    }

    func testCanonicalKeysResolveToBundledCoverNames() {
        XCTAssertEqual(BookCoverCatalog.assetName("daily"), "BookCover-default")
        XCTAssertEqual(
            BookCoverCatalog.assetName("assets/book_covers/dining.png"),
            "BookCover-dining"
        )
        XCTAssertEqual(BookCoverCatalog.assetName("unknown"), "BookCover-default")
    }
}
