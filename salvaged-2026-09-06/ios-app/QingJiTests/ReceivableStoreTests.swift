import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class ReceivableStoreTests: XCTestCase {
    private final class Stack {
        let context: ModelContext

        init() throws {
            let schema = Schema([
                Account.self,
                Book.self,
                TxCategory.self,
                MoneyTransaction.self,
                AssetEvent.self,
                ReceivableAsset.self,
                ReceivableRecovery.self,
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
        }
    }

    func testRecoveryUpdatesRemainingAndUndoRestoresIt() throws {
        let stack = try Stack()
        let book = Book(name: "总账本", isDefault: true)
        let account = Account(name: "现金", kind: .cash)
        stack.context.insert(book)
        stack.context.insert(account)
        try stack.context.save()

        let asset = try ReceivableStore.create(
            in: stack.context,
            name: "借给小林",
            kind: .loanOut,
            originalAmount: 100,
            currencyCode: "CNY",
            book: book
        )
        let recoveredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let recovery = try ReceivableStore.recover(
            asset,
            amount: 35,
            in: stack.context,
            account: account,
            date: recoveredAt,
            note: "第一次收回"
        )

        XCTAssertEqual(recovery.amount, 35)
        XCTAssertEqual(recovery.targetAccountID, account.stableID)
        XCTAssertNotNil(recovery.transactionID)
        XCTAssertEqual(asset.remainingAmount, 65)
        XCTAssertEqual(asset.lifecycle, .partiallyRecovered)
        let recoveredEvents = try stack.context.fetch(FetchDescriptor<AssetEvent>())
            .filter { $0.assetID == asset.stableID }
        XCTAssertTrue(recoveredEvents.contains { $0.kind == .receivableCreated })
        XCTAssertTrue(recoveredEvents.contains { $0.kind == .receivableRecovered })
        let recoveredEvent = try XCTUnwrap(
            recoveredEvents.first { $0.kind == .receivableRecovered }
        )
        XCTAssertEqual(recovery.eventID, recoveredEvent.stableID)
        let transaction = try XCTUnwrap(
            try stack.context.fetch(FetchDescriptor<MoneyTransaction>()).first
        )
        XCTAssertEqual(transaction.stableID, recovery.transactionID)
        XCTAssertEqual(transaction.kind, .income)
        XCTAssertEqual(transaction.eventType, .receivableRecovery)
        XCTAssertTrue(transaction.isExcluded)
        XCTAssertEqual(transaction.book?.stableID, book.stableID)
        XCTAssertEqual(
            LedgerStore.accountBalance(
                for: account,
                transactions: [transaction]
            ),
            35
        )

        try ReceivableStore.undoLatestRecovery(asset, in: stack.context)
        XCTAssertEqual(asset.remainingAmount, 100)
        XCTAssertEqual(asset.lifecycle, .active)
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()),
            0
        )
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()),
            0
        )
        let undoneEvents = try stack.context.fetch(FetchDescriptor<AssetEvent>())
            .filter { $0.assetID == asset.stableID }
        XCTAssertTrue(undoneEvents.contains { $0.kind == .receivableRecoveryUndone })
        XCTAssertTrue(undoneEvents.contains { $0.stableID == recoveredEvent.stableID })
    }

    func testRecoveryRejectsUnavailableOrMismatchedAccount() throws {
        let stack = try Stack()
        let account = Account(name: "美元账户", kind: .bankCard, currencyCode: "USD")
        stack.context.insert(account)
        try stack.context.save()

        let asset = try ReceivableStore.create(
            in: stack.context,
            name: "押金",
            kind: .rentalDeposit,
            originalAmount: 80,
            currencyCode: "CNY"
        )

        XCTAssertThrowsError(
            try ReceivableStore.recover(
                asset,
                amount: 20,
                in: stack.context,
                account: account
            )
        ) { error in
            XCTAssertEqual(error as? ReceivableStore.Error, .accountUnavailable)
        }
        XCTAssertEqual(asset.remainingAmount, 80)

        account.status = .archived
        try stack.context.save()
        XCTAssertThrowsError(
            try ReceivableStore.recover(
                asset,
                amount: 20,
                in: stack.context,
                account: account
            )
        ) { error in
            XCTAssertEqual(error as? ReceivableStore.Error, .accountUnavailable)
        }
        XCTAssertEqual(
            try stack.context.fetchCount(FetchDescriptor<ReceivableRecovery>()),
            0
        )
    }
}
