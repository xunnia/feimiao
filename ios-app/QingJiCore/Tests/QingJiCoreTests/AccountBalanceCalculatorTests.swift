import XCTest
@testable import QingJiCore

final class AccountBalanceIdentityTests: XCTestCase {
    func testBalanceUsesStableAccountIDWhenNamesRepeat() {
        let firstID = UUID()
        let secondID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            TransactionRecord(
                kind: .expense,
                amount: 40,
                accountID: firstID,
                accountName: "现金",
                date: date
            ),
            TransactionRecord(
                kind: .income,
                amount: 20,
                accountID: secondID,
                accountName: "现金",
                date: date
            ),
        ]

        XCTAssertEqual(
            AccountBalanceCalculator.balance(
                accountName: "现金",
                initialBalance: 100,
                records: records,
                accountID: firstID
            ),
            60
        )
        XCTAssertEqual(
            AccountBalanceCalculator.balance(
                accountName: "现金",
                initialBalance: 100,
                records: records,
                accountID: secondID
            ),
            120
        )
    }

    func testLegacyRecordsStillFallbackToAccountName() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            TransactionRecord(kind: .expense, amount: 15, accountName: "现金", date: date),
        ]

        XCTAssertEqual(
            AccountBalanceCalculator.balance(
                accountName: "现金",
                initialBalance: 100,
                records: records,
                accountID: UUID()
            ),
            85
        )
    }

    func testRefundUsesSettlementAccountInsteadOfOriginalAccount() {
        let originalAccountID = UUID()
        let refundAccountID = UUID()
        let originalID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            TransactionRecord(
                id: originalID,
                kind: .expense,
                amount: 100,
                accountID: originalAccountID,
                accountName: "银行卡",
                date: date
            ),
            TransactionRecord(
                kind: .expense,
                amount: -20,
                accountID: originalAccountID,
                accountName: "银行卡",
                date: date,
                settlementAccountID: refundAccountID,
                eventType: .refund,
                refundOfID: originalID
            ),
        ]

        XCTAssertEqual(
            AccountBalanceCalculator.balance(
                accountName: "银行卡",
                initialBalance: 100,
                records: records,
                accountID: originalAccountID
            ),
            0
        )
        XCTAssertEqual(
            AccountBalanceCalculator.balance(
                accountName: "微信",
                initialBalance: 0,
                records: records,
                accountID: refundAccountID
            ),
            20
        )
    }

    func testExcludedAssetSaleStillMovesSettlementAccount() {
        let accountID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            TransactionRecord(
                kind: .income,
                amount: 480,
                accountID: accountID,
                accountName: "现金",
                date: date,
                settlementAccountID: accountID,
                eventType: .assetSale,
                isExcluded: true
            ),
        ]

        XCTAssertEqual(
            AccountBalanceCalculator.balance(
                accountName: "现金",
                initialBalance: 20,
                records: records,
                accountID: accountID
            ),
            500
        )
    }
}
