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
        XCTAssertEqual(loanAccount.repaymentAccountID, cash.stableID)

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
}
