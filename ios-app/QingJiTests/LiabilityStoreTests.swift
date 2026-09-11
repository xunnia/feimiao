import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class LiabilityStoreTests: XCTestCase {
    private final class Stack {
        let context: ModelContext

        init() throws {
            let schema = Schema([
                Account.self,
                Book.self,
                TxCategory.self,
                MoneyTransaction.self,
                LiabilityProfile.self,
                RecurringRule.self,
                RecurringOccurrence.self,
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
        }
    }

    func testPersonalBorrowCreatesLoanAccountAndTransferWhenMoneyHasDestination() throws {
        let stack = try Stack()
        let book = Book(name: "总账本", isDefault: true)
        let cash = Account(name: "现金", kind: .cash)
        stack.context.insert(book)
        stack.context.insert(cash)
        try stack.context.save()

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = try LiabilityStore.createPersonalBorrow(
            in: stack.context,
            counterparty: "小林",
            amount: 1_500,
            toAccount: cash,
            dueDate: date.addingTimeInterval(86_400 * 30),
            book: book,
            date: date,
            note: "应急周转"
        )

        let accounts = try stack.context.fetch(FetchDescriptor<Account>())
        let loanAccount = try XCTUnwrap(accounts.first { $0.kind == .loan })
        XCTAssertEqual(profile.kind, .personalBorrow)
        XCTAssertEqual(profile.accountID, loanAccount.stableID)
        XCTAssertEqual(profile.currentPrincipal, 1_500)
        XCTAssertEqual(profile.counterparty, "小林")
        XCTAssertEqual(loanAccount.initialBalance, 0)
        XCTAssertEqual(profile.repaymentAccountID, cash.stableID)

        let transactions = try stack.context.fetch(FetchDescriptor<MoneyTransaction>())
        let transfer = try XCTUnwrap(transactions.first)
        XCTAssertEqual(transfer.kind, .transfer)
        XCTAssertEqual(transfer.account?.stableID, loanAccount.stableID)
        XCTAssertEqual(transfer.toAccount?.stableID, cash.stableID)
        XCTAssertEqual(transfer.amount, 1_500)
        XCTAssertEqual(transfer.book?.stableID, book.stableID)
        XCTAssertEqual(
            LedgerStore.accountBalance(for: cash, transactions: transactions),
            1_500
        )
        XCTAssertEqual(
            LedgerStore.accountBalance(for: loanAccount, transactions: transactions),
            -1_500
        )
    }

    func testPersonalBorrowWithoutDestinationUsesLoanOpeningBalance() throws {
        let stack = try Stack()
        let profile = try LiabilityStore.createPersonalBorrow(
            in: stack.context,
            counterparty: "小周",
            amount: 280,
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let loanAccount = try XCTUnwrap(
            try stack.context.fetch(FetchDescriptor<Account>()).first
        )
        XCTAssertEqual(loanAccount.kind, .loan)
        XCTAssertEqual(loanAccount.initialBalance, -280)
        XCTAssertEqual(profile.accountID, loanAccount.stableID)
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            0
        )
    }

    func testPersonalBorrowRequiresAnObjectName() throws {
        let stack = try Stack()
        XCTAssertThrowsError(
            try LiabilityStore.createPersonalBorrow(
                in: stack.context,
                counterparty: "  ",
                amount: 100
            )
        ) { error in
            XCTAssertEqual(error as? LiabilityStore.Error, .invalidCounterparty)
        }
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<Account>()),
            0
        )
    }

    func testLoanWizardCreatesAccountProfileAndMonthlyTransferRule() throws {
        let stack = try Stack()
        let book = Book(name: "总账本", isDefault: true)
        let cash = Account(name: "现金", kind: .cash)
        stack.context.insert(book)
        stack.context.insert(cash)
        try stack.context.save()

        let now = Calendar.current.date(
            from: DateComponents(year: 2026, month: 8, day: 27, hour: 12)
        )!
        let result = try LiabilityStore.createLoanWizardSetup(
            in: stack.context,
            kind: .mortgage,
            name: "我的房贷",
            totalAmount: 1_000_000,
            remainingPrincipal: 800_000,
            annualRate: 3.1,
            monthlyPayment: 5_000,
            repaymentDay: 15,
            fromAccount: cash,
            book: book,
            now: now
        )

        XCTAssertEqual(result.account.kind, .loan)
        XCTAssertEqual(result.account.initialBalance, -800_000)
        XCTAssertEqual(result.profile.kind, .mortgage)
        XCTAssertEqual(result.profile.originalPrincipal, 1_000_000)
        XCTAssertEqual(result.profile.currentPrincipal, 800_000)
        XCTAssertEqual(result.profile.accountID, result.account.stableID)
        XCTAssertEqual(result.profile.repaymentAccountID, cash.stableID)
        XCTAssertEqual(result.profile.paymentDay, 15)
        XCTAssertEqual(result.rule.kind, .transfer)
        XCTAssertEqual(result.rule.amount, 5_000)
        XCTAssertEqual(result.rule.accountID, cash.stableID)
        XCTAssertEqual(result.rule.toAccountID, result.account.stableID)
        XCTAssertEqual(result.rule.bookID, book.stableID)
        XCTAssertEqual(result.rule.period, .monthly)
        let firstDueComponents = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: result.rule.nextDueDate
        )
        XCTAssertEqual(firstDueComponents.year, 2026)
        XCTAssertEqual(firstDueComponents.month, 9)
        XCTAssertEqual(firstDueComponents.day, 15)
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<RecurringRule>()),
            1
        )
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            0
        )
    }
}
