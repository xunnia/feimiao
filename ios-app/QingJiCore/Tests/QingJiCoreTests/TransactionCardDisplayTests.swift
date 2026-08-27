import XCTest
@testable import QingJiCore

final class TransactionCardDisplayTests: XCTestCase {
    func testContentFirstUsesNoteAsTitleAndCategoryAsSecondary() {
        let value = resolveTransactionCardText(
            mode: .contentFirst,
            kind: .expense,
            note: "午餐 麦当劳",
            categoryName: "食品餐饮"
        )
        XCTAssertEqual(value.title, "午餐 麦当劳")
        XCTAssertEqual(value.secondary, "食品餐饮")
    }

    func testCategoryFirstUsesCategoryAsTitleAndNoteAsSecondary() {
        let value = resolveTransactionCardText(
            mode: .categoryFirst,
            kind: .expense,
            note: "午餐 麦当劳",
            categoryName: "食品餐饮"
        )
        XCTAssertEqual(value.title, "食品餐饮")
        XCTAssertEqual(value.secondary, "午餐 麦当劳")
    }

    func testTransferTitleKeepsBothAccountNames() {
        let value = resolveTransactionCardText(
            mode: .contentFirst,
            kind: .transfer,
            note: "账户转入",
            categoryName: "",
            accountName: "现金",
            toAccountName: "银行卡"
        )
        XCTAssertEqual(value.title, "现金 → 银行卡")
        XCTAssertEqual(value.secondary, "账户转入")
    }

    func testDateOnlyDoesNotInventClockTime() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            transactionCardTimeLabel(date, dateGrouped: true, precision: .dateOnly),
            ""
        )
        XCTAssertFalse(
            transactionCardTimeLabel(date, dateGrouped: true, precision: .exact).isEmpty
        )
    }
}
