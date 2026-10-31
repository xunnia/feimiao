import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class AIRecordCardStoreTests: XCTestCase {
    @MainActor
    private final class Stack {
        let container: ModelContainer
        let context: ModelContext
        let fence = AIChatOperationFence()
        let book: Book
        let account: Account
        let category: TxCategory
        let sessionID: UUID
        let message: AIChatMessage
        var lease: AIChatOperationFence.Lease { fence.capture(sessionID: sessionID, bookID: book.stableID) }

        init(amounts: [Decimal?] = [Decimal(18), Decimal(25)], withBook: Bool = true) throws {
            let schema = Schema([Book.self, Account.self, TxCategory.self, MoneyTransaction.self, AIChatMessage.self])
            let modelContainer = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            ])
            container = modelContainer
            context = ModelContext(modelContainer)
            let seedBook = Book(name: "发起账本", isDefault: true)
            book = seedBook
            account = Account(name: "测试现金", kind: .cash)
            category = TxCategory(key: "dining", name: "食品餐饮", symbol: "fork.knife", kind: .expense)
            let id = UUID()
            sessionID = id
            let card = AIRecordCardState(entries: amounts.map {
                ParsedEntry(amount: $0, kind: .expense, categoryKey: "dining", note: "测试",
                            date: Date(timeIntervalSince1970: 1000), timePrecision: .entryClock, confidence: 1)
            }, bookID: withBook ? seedBook.stableID : nil, categoryKeys: amounts.map { _ in "dining" })
            message = AIChatMessage(sessionID: id, role: "assistant", content: "待确认",
                                    recordJSON: String(decoding: try JSONEncoder().encode(card), as: UTF8.self))
            context.autosaveEnabled = false
            context.insert(book)
            context.insert(account)
            context.insert(category)
            context.insert(message)
            try context.save()
        }

        func save(beforeCommit: @escaping () throws -> Void = {}) throws -> AIRecordCardState {
            try AIRecordCardStore.save(turnID: message.stableID, accountID: account.stableID,
                                      lease: lease, in: context, fence: fence, beforeCommit: beforeCommit)
        }

        func restored() throws -> (AIRecordCardState, [MoneyTransaction]) {
            let reload = ModelContext(container)
            let message = try XCTUnwrap(reload.fetch(FetchDescriptor<AIChatMessage>()).first)
            let card = try JSONDecoder().decode(AIRecordCardState.self, from: Data(message.recordJSON.utf8))
            return (card, try reload.fetch(FetchDescriptor<MoneyTransaction>()))
        }
    }

    func testConfirmationCommitsRowsAndCardOnceAndPreservesBook() throws {
        let stack = try Stack()
        let first = try stack.save()
        let second = try stack.save()
        XCTAssertEqual(first.transactionIDs, second.transactionIDs)
        let (card, rows) = try stack.restored()
        XCTAssertTrue(card.saved)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap { $0.book?.stableID }), Set([stack.book.stableID]))
        XCTAssertEqual(Set(card.transactionIDs.compactMap { $0 }), Set(rows.map(\.stableID)))
    }

    func testMetadataFailureRollsBackRowsWithoutSavingAnotherEditor() throws {
        enum Injected: Error { case failure }
        let stack = try Stack()
        stack.book.name = "其他页面未保存的改名"
        XCTAssertThrowsError(try stack.save(beforeCommit: { throw Injected.failure }))
        let (card, rows) = try stack.restored()
        XCTAssertFalse(card.saved)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(stack.book.name, "其他页面未保存的改名")
        XCTAssertEqual(try ModelContext(stack.container).fetch(FetchDescriptor<Book>()).first?.name, "发起账本")
        XCTAssertTrue(try stack.save().saved)
    }

    func testRestoreDuringCommitRevokesSave() throws {
        let stack = try Stack()
        XCTAssertThrowsError(try stack.save(beforeCommit: { stack.fence.invalidateDatabase() }))
        XCTAssertTrue(try stack.restored().1.isEmpty)
        XCTAssertFalse(try stack.restored().0.saved)
    }

    func testOldUnconfirmedCardCannotFallBackToCurrentBook() throws {
        let stack = try Stack(withBook: false)
        XCTAssertThrowsError(try stack.save())
        XCTAssertTrue(try stack.restored().1.isEmpty)
    }

    func testInvalidAmountsDoNotShiftSavedIndices() throws {
        let stack = try Stack(amounts: [.zero, Decimal(18), nil, Decimal(-2), Decimal(25)])
        let card = try stack.save()
        XCTAssertNil(card.transactionID(at: -1))
        XCTAssertNil(card.categoryKey(at: -1))
        XCTAssertNil(card.transactionID(at: 0))
        XCTAssertNotNil(card.transactionID(at: 1))
        XCTAssertNil(card.transactionID(at: 2))
        XCTAssertNil(card.transactionID(at: 3))
        XCTAssertNotNil(card.transactionID(at: 4))
        XCTAssertEqual(try stack.restored().1.count, 2)
    }

    func testCategoryAndDeletePersistTogetherThenUndoIsRepeatSafe() throws {
        let stack = try Stack()
        let card = try stack.save()
        let other = TxCategory(key: "transport", name: "交通", symbol: "car", kind: .expense)
        stack.context.insert(other)
        try stack.context.save()
        let changed = try AIRecordCardStore.changeCategory(turnID: stack.message.stableID, index: 0,
            categoryKey: "transport", lease: stack.lease, in: stack.context, fence: stack.fence)
        XCTAssertEqual(changed.categoryKey(at: 0), "transport")
        XCTAssertEqual(try stack.restored().1.first(where: { $0.stableID == card.transactionID(at: 0) })?.category?.key,
                       "transport")
        let deleted = try AIRecordCardStore.deleteEntry(turnID: stack.message.stableID, index: 0,
            lease: stack.lease, in: stack.context, fence: stack.fence)
        XCTAssertTrue(deleted.deletedIndices.contains(0))
        XCTAssertEqual(try stack.restored().1.count, 1)
        _ = try AIRecordCardStore.undo(turnID: stack.message.stableID, lease: stack.lease,
                                      in: stack.context, fence: stack.fence)
        _ = try AIRecordCardStore.undo(turnID: stack.message.stableID, lease: stack.lease,
                                      in: stack.context, fence: stack.fence)
        XCTAssertTrue(try stack.restored().0.rolledBack)
        XCTAssertTrue(try stack.restored().1.isEmpty)
    }

    func testUndoPreflightsWholeBatchBeforeDeletingAnyRow() throws {
        let stack = try Stack()
        _ = try stack.save()
        let local = ModelContext(stack.container)
        let rows = try local.fetch(FetchDescriptor<MoneyTransaction>())
        rows[1].eventType = .principalPayment
        try local.save()
        XCTAssertThrowsError(try AIRecordCardStore.undo(turnID: stack.message.stableID, lease: stack.lease,
            in: stack.context, fence: stack.fence))
        XCTAssertEqual(try stack.restored().1.count, 2)
        XCTAssertFalse(try stack.restored().0.rolledBack)
    }

    func testOtherSessionOrClearedLeaseCannotChangeCard() throws {
        let stack = try Stack()
        let wrong = stack.fence.capture(sessionID: UUID(), bookID: stack.book.stableID)
        XCTAssertThrowsError(try AIRecordCardStore.save(turnID: stack.message.stableID, accountID: stack.account.stableID,
            lease: wrong, in: stack.context, fence: stack.fence))
        let old = stack.lease
        stack.fence.invalidate(sessionID: stack.sessionID)
        XCTAssertThrowsError(try AIRecordCardStore.save(turnID: stack.message.stableID, accountID: stack.account.stableID,
            lease: old, in: stack.context, fence: stack.fence))
        XCTAssertTrue(try stack.restored().1.isEmpty)
    }
}
