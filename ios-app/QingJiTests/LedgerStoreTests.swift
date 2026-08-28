import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class LedgerStoreTests: XCTestCase {
    private final class Stack {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            let schema = Schema([
                Account.self,
                Book.self,
                TxCategory.self,
                MoneyTransaction.self,
                AccountBalanceCheckpointRecord.self,
            ])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
            let modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            container = modelContainer
            context = ModelContext(modelContainer)
        }
    }

    private func seed(_ stack: Stack) throws -> (Book, Account, Account, TxCategory) {
        let book = Book(name: "测试账本", isDefault: true)
        let cash = Account(name: "现金", kind: .cash)
        let bank = Account(name: "银行卡", kind: .bankCard)
        let dining = TxCategory(
            key: "dining",
            name: "食品餐饮",
            symbol: "fork.knife",
            kind: .expense,
            emoji: "🍜"
        )
        stack.context.insert(book)
        stack.context.insert(cash)
        stack.context.insert(bank)
        stack.context.insert(dining)
        try stack.context.save()
        return (book, cash, bank, dining)
    }

    func testBatchValidationDoesNotLeavePartialTransactions() throws {
        let stack = try Stack()
        let (book, cash, bank, dining) = try seed(stack)

        let drafts = [
            LedgerStore.TransactionDraft(
                amount: 28,
                kind: .expense,
                date: Date(),
                note: "午餐",
                category: dining,
                account: cash,
                book: book
            ),
            LedgerStore.TransactionDraft(
                amount: 100,
                kind: .transfer,
                date: Date(),
                note: "错误转账",
                account: cash,
                toAccount: cash,
                book: book
            ),
        ]

        XCTAssertThrowsError(
            try LedgerStore.createTransactions(in: stack.context, drafts: drafts)
        ) { error in
            XCTAssertEqual(error as? LedgerStore.Error, .invalidTransfer)
        }
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            0
        )
        _ = bank
    }

    func testRefundKeepsOriginalDateButUsesSettlementDateAndCapsRemaining() throws {
        let stack = try Stack()
        let (book, cash, _, dining) = try seed(stack)
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let settlementDate = Date(timeIntervalSince1970: 1_700_086_400)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 100,
            kind: .expense,
            date: originalDate,
            note: "耳机",
            category: dining,
            account: cash,
            book: book
        )

        let refund = try LedgerStore.createOffset(
            for: original,
            amount: 35,
            note: "部分退款",
            eventType: .refund,
            settlementAccount: cash,
            settledAt: settlementDate,
            in: stack.context
        )
        XCTAssertEqual(refund.date, originalDate)
        XCTAssertEqual(refund.settledAt, settlementDate)

        let status = try LedgerStore.refundStatus(for: original, in: stack.context)
        XCTAssertEqual(status.originalAmount, 100)
        XCTAssertEqual(status.refundedAmount, 35)
        XCTAssertEqual(status.remainingAmount, 65)

        XCTAssertThrowsError(
            try LedgerStore.createOffset(
                for: original,
                amount: 66,
                note: "超额退款",
                eventType: .refund,
                settlementAccount: cash,
                settledAt: settlementDate,
                in: stack.context
            )
        ) { error in
            XCTAssertEqual(error as? LedgerStore.Error, .refundExceedsRemaining)
        }
    }

    func testReimbursementOnlyClearsPendingFlagAfterFullNetOffset() throws {
        let stack = try Stack()
        let (book, cash, _, dining) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 100,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            note: "出差餐费",
            category: dining,
            account: cash,
            book: book,
            reimbursable: true
        )

        _ = try LedgerStore.createOffset(
            for: original,
            amount: 40,
            note: "部分报销",
            eventType: .reimbursement,
            settlementAccount: cash,
            in: stack.context
        )
        XCTAssertTrue(original.reimbursable)
        XCTAssertFalse(original.isReimbursed)

        _ = try LedgerStore.createOffset(
            for: original,
            amount: 60,
            note: "报销到账",
            eventType: .reimbursement,
            settlementAccount: cash,
            in: stack.context
        )
        XCTAssertFalse(original.reimbursable)
        XCTAssertTrue(original.isReimbursed)
        let status = try LedgerStore.refundStatus(for: original, in: stack.context)
        XCTAssertEqual(status.remainingAmount, 0)
    }

    func testDeletingOriginalCascadesAttachedOffsets() throws {
        let stack = try Stack()
        let (book, cash, _, dining) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 80,
            kind: .expense,
            date: Date(),
            note: "可退商品",
            category: dining,
            account: cash,
            book: book
        )
        _ = try LedgerStore.createOffset(
            for: original,
            amount: 20,
            note: "退款",
            eventType: .refund,
            settlementAccount: cash,
            in: stack.context
        )
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            2
        )

        try LedgerStore.delete(original, in: stack.context)
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            0
        )
    }

    func testBalanceCheckpointAdjustsBalanceWithoutCreatingCashflow() throws {
        let stack = try Stack()
        let (book, cash, _, dining) = try seed(stack)
        cash.initialBalance = 100
        try stack.context.save()
        _ = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 20,
            kind: .expense,
            date: Date(),
            note: "已记支出",
            category: dining,
            account: cash,
            book: book
        )

        let rawBalance = LedgerStore.accountBalance(
            for: cash,
            transactions: try stack.context.fetch(FetchDescriptor<MoneyTransaction>())
        )
        XCTAssertEqual(rawBalance, 80)

        _ = try AccountCheckpointStore.create(
            for: cash,
            actualBalance: 130,
            effectiveAt: Date(timeIntervalSince1970: 1_700_000_000),
            in: stack.context
        )
        let checkpoints = try stack.context.fetch(FetchDescriptor<AccountBalanceCheckpointRecord>())
        XCTAssertEqual(
            LedgerStore.accountBalance(
                for: cash,
                transactions: try stack.context.fetch(FetchDescriptor<MoneyTransaction>()),
                checkpoints: checkpoints
            ),
            130
        )
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            1
        )

        let anchor = try XCTUnwrap(checkpoints.first(where: { $0.eventKindRaw == "anchor" }))
        try AccountCheckpointStore.reverse(anchor, in: stack.context, at: Date())
        let reversed = try stack.context.fetch(FetchDescriptor<AccountBalanceCheckpointRecord>())
        XCTAssertEqual(
            LedgerStore.accountBalance(
                for: cash,
                transactions: try stack.context.fetch(FetchDescriptor<MoneyTransaction>()),
                checkpoints: reversed
            ),
            80
        )
    }
}
