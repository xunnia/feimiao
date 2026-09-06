import XCTest
@testable import QingJi

@MainActor
final class LedgerScopeTests: XCTestCase {
    func testTotalScopeAlwaysIncludesDefaultBook() {
        let defaultBook = Book(
            name: "总账本",
            includeInTotal: false,
            isDefault: true
        )
        let includedBook = Book(name: "计入总账", includeInTotal: true)
        let excludedBook = Book(name: "独立账本", includeInTotal: false)
        let defaultTransaction = MoneyTransaction(
            amount: 10,
            kind: .expense,
            book: defaultBook
        )
        let includedTransaction = MoneyTransaction(
            amount: 20,
            kind: .expense,
            book: includedBook
        )
        let excludedTransaction = MoneyTransaction(
            amount: 30,
            kind: .expense,
            book: excludedBook
        )

        let scoped = LedgerScope.filter(
            [defaultTransaction, includedTransaction, excludedTransaction],
            selectedBookID: nil
        )

        XCTAssertEqual(
            Set(scoped.map(\.stableID)),
            Set([defaultTransaction.stableID, includedTransaction.stableID])
        )
    }

    func testSelectedBookScopeRemainsExact() {
        let firstBook = Book(name: "第一账本")
        let secondBook = Book(name: "第二账本")
        let firstTransaction = MoneyTransaction(
            amount: 10,
            kind: .expense,
            book: firstBook
        )
        let secondTransaction = MoneyTransaction(
            amount: 20,
            kind: .expense,
            book: secondBook
        )

        let scoped = LedgerScope.filter(
            [firstTransaction, secondTransaction],
            selectedBookID: secondBook.stableID
        )

        XCTAssertEqual(scoped.map(\.stableID), [secondTransaction.stableID])
    }
}
