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

    func testBuiltInChildRollupUsesSameNameAsStoredParent() throws {
        let stack = try Stack()
        let (book, cash, _, dining) = try seed(stack)
        let groceries = TxCategory(key: "groceries", name: "生鲜食品",
                                   symbol: "carrot", kind: .expense, parentKey: "dining")
        stack.context.insert(groceries)
        let date = Date(timeIntervalSince1970: 1_787_788_800)
        let parent = MoneyTransaction(amount: 10, kind: .expense, date: date,
                                      category: dining, account: cash, book: book)
        let child = MoneyTransaction(amount: 20, kind: .expense, date: date,
                                     category: groceries, account: cash, book: book)
        stack.context.insert(parent)
        stack.context.insert(child)
        try stack.context.save()
        XCTAssertEqual(child.record.topCategoryKey, "dining")
        XCTAssertEqual(child.record.topCategoryName, parent.record.topCategoryName)
        let summary = StatisticsEngine.periodSummary(of: [parent.record, child.record],
                                                      start: date, end: date)
        XCTAssertEqual(summary.expenseByCategory.count, 1)
        XCTAssertEqual(summary.expenseByCategory.first?.name, "食品餐饮")
        XCTAssertEqual(summary.expenseByCategory.first?.total, Decimal(30))
        XCTAssertEqual(summary.expenseByCategory.first?.count, 2)
    }

    func testStatisticsBalanceSparklineUsesCumulativeNetAmounts() {
        let date = Date(timeIntervalSince1970: 0)
        let days = [
            PeriodDailyTotal(date: date, expense: 20, income: 100),
            PeriodDailyTotal(date: date.addingTimeInterval(86400), expense: 30, income: 0),
            PeriodDailyTotal(date: date.addingTimeInterval(172800), expense: -5, income: 0),
        ]
        XCTAssertEqual(MonthlyStatsView.runningBalances(days), [80, 50, 55])
        XCTAssertEqual(MonthlyStatsView.runningBalances([]), [])
    }

    func testCustomRingCondensesPositiveCategoriesWithoutLosingTotals() {
        var categories: [CategoryTotal] = []
        for index in 1...7 {
            let amount = 8 - index
            categories.append(CategoryTotal(name: index == 7 ? "其他" : "分类\(index)",
                                            total: Decimal(amount), share: Double(amount) / 28.0,
                                            count: index))
        }
        categories.append(CategoryTotal(name: "退款", total: -2, share: -2.0 / 28, count: 1))
        let items = MonthlyStatsView.condensedRingCategories(categories)
        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(items.last?.name, "更多")
        XCTAssertEqual(items.last?.total, 3)
        XCTAssertEqual(items.last?.count, 13)
        XCTAssertEqual(items.reduce(Decimal.zero) { $0 + $1.total }, 28)
        XCTAssertEqual(MonthlyStatsView.condensedRingCategories(Array(categories.prefix(6))).count, 6)
        XCTAssertEqual(MonthlyStatsView.condensedRingCategories([]), [])
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

    func testReimbursementUsesRoundedAmountWhenCheckingFullOffset() throws {
        let stack = try Stack()
        let (book, cash, _, dining) = try seed(stack)
        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 60,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            note: "四舍五入边界",
            category: dining,
            account: cash,
            book: book,
            reimbursable: true
        )

        _ = try LedgerStore.createOffset(
            for: original,
            amount: Decimal(string: "59.999")!,
            note: "报销到账",
            eventType: .reimbursement,
            settlementAccount: cash,
            in: stack.context
        )

        XCTAssertFalse(original.reimbursable)
        XCTAssertTrue(original.isReimbursed)
        XCTAssertEqual(try LedgerStore.refundStatus(for: original, in: stack.context).remainingAmount, 0)
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
