import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class BillRecordSaverTests: XCTestCase {
    private final class Stack {
        let context: ModelContext

        init() throws {
            let schema = Schema([
                Account.self,
                Book.self,
                TxCategory.self,
                MoneyTransaction.self,
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
        }
    }

    private enum SaveFailure: Error, Equatable {
        case expected
    }

    private func seed(_ stack: Stack) throws -> (Book, Account) {
        let book = Book(name: "测试账本", isDefault: true)
        let account = Account(name: "支付宝", kind: .alipay)
        let dining = TxCategory(
            key: "dining",
            name: "食品餐饮",
            symbol: "fork.knife",
            kind: .expense,
            emoji: "🍜"
        )
        let otherIncome = TxCategory(
            key: "otherIncome",
            name: "其他收入",
            symbol: "plus",
            kind: .income,
            emoji: "💰"
        )
        stack.context.insert(book)
        stack.context.insert(account)
        stack.context.insert(dining)
        stack.context.insert(otherIncome)
        try stack.context.save()
        return (book, account)
    }

    private func result(_ records: [TransactionRecord]) -> ImportedBillResult {
        ImportedBillResult(source: .alipay, records: records, skippedRowCount: 0)
    }

    func testDuplicateImportDoesNotCreateAdditionalTransactions() throws {
        let stack = try Stack()
        let (book, account) = try seed(stack)
        let record = TransactionRecord(
            kind: .expense,
            amount: 28,
            categoryName: "食品餐饮",
            categoryKey: "dining",
            accountName: "支付宝",
            bookID: book.stableID,
            note: "午餐",
            merchant: "某餐馆",
            product: "套餐",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            eventType: .expense,
            orderNo: "ORDER-1"
        )
        let imported = result([record])

        XCTAssertEqual(try BillRecordSaver.save(imported, account: account, context: stack.context), 1)
        XCTAssertEqual(try BillRecordSaver.save(imported, account: account, context: stack.context), 0)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
    }

    func testRefundAttachesToOrderAndUsesOriginalBillDate() throws {
        let stack = try Stack()
        let (book, account) = try seed(stack)
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let refundDate = Date(timeIntervalSince1970: 1_700_086_400)
        let originalID = UUID()
        let refundID = UUID()
        let orderNo = "ORDER-REFUND-1"
        let original = TransactionRecord(
            id: originalID,
            kind: .expense,
            amount: 100,
            categoryName: "食品餐饮",
            categoryKey: "dining",
            accountName: "支付宝",
            bookID: book.stableID,
            note: "耳机",
            merchant: "某店",
            product: "耳机",
            date: originalDate,
            eventType: .expense,
            orderNo: orderNo
        )
        let refund = TransactionRecord(
            id: refundID,
            kind: .expense,
            amount: -40,
            accountName: "支付宝",
            bookID: book.stableID,
            note: "退货",
            merchant: "某店",
            product: "耳机",
            date: refundDate,
            eventType: .refund,
            orderNo: orderNo
        )

        XCTAssertEqual(
            try BillRecordSaver.save(result([original, refund]), account: account, context: stack.context),
            2
        )
        let transactions = try stack.context.fetch(FetchDescriptor<MoneyTransaction>())
        let originalRow = try XCTUnwrap(transactions.first { $0.stableID == originalID })
        let refundRow = try XCTUnwrap(transactions.first { $0.stableID == refundID })
        XCTAssertEqual(refundRow.refundOfID, originalRow.stableID)
        XCTAssertEqual(refundRow.date, originalDate)
        XCTAssertEqual(refundRow.settledAt, refundDate)
        XCTAssertEqual(try LedgerStore.refundStatus(for: originalRow, in: stack.context).remainingAmount, 60)
    }

    func testUnmatchedRefundBecomesVisibleIncome() throws {
        let stack = try Stack()
        let (_, account) = try seed(stack)
        let refundDate = Date(timeIntervalSince1970: 1_700_086_400)
        let refund = TransactionRecord(
            kind: .expense,
            amount: -18,
            accountName: "支付宝",
            note: "",
            merchant: "无法匹配的商户",
            date: refundDate,
            eventType: .refund,
            orderNo: "ORPHAN-REFUND"
        )

        XCTAssertEqual(try BillRecordSaver.save(result([refund]), account: account, context: stack.context), 1)
        let transaction = try XCTUnwrap(
            try stack.context.fetch(FetchDescriptor<MoneyTransaction>()).first
        )
        XCTAssertEqual(transaction.kind, .income)
        XCTAssertEqual(transaction.amount, 18)
        XCTAssertNil(transaction.refundOfID)
        XCTAssertEqual(transaction.eventType, .income)
        XCTAssertEqual(transaction.note, "退款")
    }

    func testFailedSaveRemovesOnlyTheBatchBeingImported() throws {
        let stack = try Stack()
        let (_, account) = try seed(stack)
        let existing = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 9,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            note: "已有账单",
            account: account
        )
        let incoming = result([
            TransactionRecord(
                kind: .expense,
                amount: 12,
                accountName: "支付宝",
                date: Date(timeIntervalSince1970: 1_700_000_100),
                eventType: .expense,
                orderNo: "NEW-1"
            ),
            TransactionRecord(
                kind: .expense,
                amount: -5,
                accountName: "支付宝",
                merchant: "无原单商户",
                date: Date(timeIntervalSince1970: 1_800_000_000),
                eventType: .refund,
                orderNo: "NEW-REFUND"
            ),
        ])

        XCTAssertThrowsError(
            try BillRecordSaver.save(
                incoming,
                account: account,
                context: stack.context,
                saveContext: { _ in throw SaveFailure.expected }
            )
        ) { error in
            XCTAssertEqual(error as? SaveFailure, .expected)
        }

        let transactions = try stack.context.fetch(FetchDescriptor<MoneyTransaction>())
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.stableID, existing.stableID)
    }
}
