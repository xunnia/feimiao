import XCTest
@testable import QingJiCore

final class LedgerPolicyTests: XCTestCase {
    func testAttachedRefundIsFoldedAndChildIsHidden() {
        let originalID = UUID()
        let refundID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let incomeID = UUID()
        let records = [
            TransactionRecord(id: originalID, kind: .expense, amount: 100, categoryName: "购物", date: date),
            TransactionRecord(id: refundID, kind: .expense, amount: -35, categoryName: "购物", date: date, refundOfID: originalID),
            TransactionRecord(id: incomeID, kind: .income, amount: 500, categoryName: "工资", date: date),
        ]

        let visible = LedgerPolicy.userRecords(from: records)

        XCTAssertEqual(visible.map(\.id), [originalID, incomeID])
        XCTAssertEqual(visible.first?.amount, 65)
        XCTAssertEqual(LedgerPolicy.expenseFamilyCount(from: records), 1)
    }

    func testFullyRefundedFamilyDoesNotCountAsExpense() {
        let originalID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            TransactionRecord(id: originalID, kind: .expense, amount: 80, categoryName: "餐饮", date: date),
            TransactionRecord(kind: .expense, amount: -80, categoryName: "餐饮", date: date, refundOfID: originalID),
        ]

        let visible = LedgerPolicy.userRecords(from: records)

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].amount, 0)
        XCTAssertEqual(LedgerPolicy.expenseFamilyCount(from: records), 0)
    }

    func testExcludedOriginalAlsoExcludesItsRefundFamily() {
        let originalID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            TransactionRecord(id: originalID, kind: .expense, amount: 80, date: date, isExcluded: true),
            TransactionRecord(kind: .expense, amount: -20, date: date, refundOfID: originalID),
        ]

        XCTAssertTrue(LedgerPolicy.userRecords(from: records).isEmpty)
    }

    func testOrphanAttachedRefundDoesNotCreateGhostExpense() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            TransactionRecord(kind: .expense, amount: -20, date: date, refundOfID: UUID()),
        ]

        XCTAssertTrue(LedgerPolicy.userRecords(from: records).isEmpty)
    }

    func testExpenseAndIncomeCountUseNetAmount() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expenseID = UUID()
        let records = [
            TransactionRecord(id: expenseID, kind: .expense, amount: 80, date: date),
            TransactionRecord(kind: .expense, amount: -80, date: date, refundOfID: expenseID),
            TransactionRecord(kind: .income, amount: 120, date: date),
            TransactionRecord(kind: .income, amount: 0, date: date),
        ]

        let visible = LedgerPolicy.userRecords(from: records)

        XCTAssertEqual(visible.filter { $0.countsAsExpenseFamily }.count, 0)
        XCTAssertEqual(visible.filter { $0.countsAsIncomeEvent }.count, 1)
    }

    func testRefundStatusIgnoresExcludedOrMalformedChildren() {
        let originalID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = TransactionRecord(id: originalID, kind: .expense, amount: 100, date: date)
        let records = [
            original,
            TransactionRecord(kind: .expense, amount: -30, date: date, refundOfID: originalID),
            TransactionRecord(kind: .expense, amount: -10, date: date, refundOfID: originalID, isExcluded: true),
            TransactionRecord(kind: .expense, amount: 5, date: date, refundOfID: originalID),
        ]

        let status = LedgerPolicy.refundStatus(for: original, in: records)

        XCTAssertEqual(status.originalAmount, 100)
        XCTAssertEqual(status.refundedAmount, 30)
        XCTAssertEqual(status.remainingAmount, 70)
        XCTAssertTrue(LedgerPolicy.canOffset(original, in: records))
    }
}
