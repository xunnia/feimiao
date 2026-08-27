import XCTest
@testable import QingJiCore

final class MoneyNormalizationTests: XCTestCase {
    func testRoundsHalfUpToCentsWithoutUsingDouble() {
        XCTAssertEqual(
            MoneyNormalization.roundToCents(Decimal(string: "33.3333")!),
            Decimal(string: "33.33")!
        )
        XCTAssertEqual(
            MoneyNormalization.roundToCents(Decimal(string: "12.345")!),
            Decimal(string: "12.35")!
        )
        XCTAssertEqual(MoneyNormalization.cents(Decimal(string: "12.345")!), 1235)
    }
}
