import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class BookMembershipStoreTests: XCTestCase {
    private func stack() throws -> (ModelContainer, ModelContext, Book, Book, Book, Account) {
        let schema = Schema([Account.self, Book.self, TxCategory.self, MoneyTransaction.self,
                             BudgetRuleRecord.self, AccountBalanceCheckpointRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let total = Book(name: "总账本", isDefault: true)
        let business = Book(name: "生意", includeInTotal: false)
        let project = Book(name: "项目A")
        let cash = Account(name: "现金", kind: .cash)
        [total, business, project].forEach(context.insert)
        context.insert(cash)
        try context.save()
        return (container, context, total, business, project, cash)
    }

    func testLegacyFallbackAndTotalAlwaysIncludesPreviouslyExcludedBook() throws {
        let (_, context, total, business, _, cash) = try stack()
        let transaction = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: business)
        XCTAssertFalse(transaction.hasExplicitBookMemberships)
        XCTAssertEqual(transaction.scenarioBookIDs, [business.stableID])
        XCTAssertEqual(LedgerScope.filter([transaction], selectedBookID: nil).count, 1)
        XCTAssertEqual(LedgerScope.filter([transaction], selectedBookID: business.stableID).count, 1)
        XCTAssertTrue(MoneyTransaction(amount: 1, kind: .income, book: total).scenarioBookIDs.isEmpty)
    }

    func testOneOriginalInTwoScenesDeduplicatesUnionAndCashSettlement() throws {
        let (_, context, total, business, project, cash) = try stack()
        let transaction = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: total, scenarioBookIDs: [business.stableID, project.stableID])
        let all = try LedgerStore.allTransactions(in: context)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(LedgerScope.filter(all, selectedBookID: business.stableID).count, 1)
        XCTAssertEqual(LedgerScope.filter(all, selectedBookID: project.stableID).count, 1)
        XCTAssertEqual(LedgerScope.filter(all + all, selectedBookIDs: [business.stableID, project.stableID]).count, 1)
        XCTAssertEqual(LedgerScope.filter(all + all, selectedBookID: nil).count, 1)
        XCTAssertEqual(transaction.account?.stableID, cash.stableID)
        XCTAssertEqual(LedgerStore.accountBalance(for: cash, transactions: all), -100)
        XCTAssertEqual(all.map(\.amount).reduce(0, +), 100)
        XCTAssertEqual(transaction.book?.stableID, total.stableID, "场景归集不能改资产原始账本锚点")
    }

    func testRemoveLastSceneDoesNotReviveLegacyFallbackAndSurvivesNewContext() throws {
        let (container, context, _, business, _, cash) = try stack()
        let transaction = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: business)
        try BookMembershipStore.update(transactionIDs: [transaction.stableID], operation: .remove([business.stableID]), in: context)
        let restored = try ModelContext(container).fetch(FetchDescriptor<MoneyTransaction>())
        XCTAssertTrue(try XCTUnwrap(restored.first).hasExplicitBookMemberships)
        XCTAssertTrue(try XCTUnwrap(restored.first).scenarioBookIDs.isEmpty)
        XCTAssertEqual(LedgerScope.filter(restored, selectedBookID: business.stableID).count, 0)
        XCTAssertEqual(LedgerScope.filter(restored, selectedBookID: nil).count, 1)
    }

    func testRefundFamilyFollowsOriginalIncludingLegacyChildAndLaterRefunds() throws {
        let (_, context, total, business, project, cash) = try stack()
        let original = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: total)
        let refund = try LedgerStore.createOffset(for: original, amount: 20, note: "退款", eventType: .refund, in: context)
        try BookMembershipStore.update(transactionIDs: [refund.stableID], operation: .add([business.stableID, project.stableID]), in: context)
        XCTAssertEqual(original.scenarioBookIDs, [business.stableID, project.stableID])
        XCTAssertEqual(refund.scenarioBookIDs, original.scenarioBookIDs)
        // 即使旧子行没有独立关联，查询也按原交易归属。
        refund.hasExplicitBookMemberships = false
        refund.bookMembershipIDsRaw = ""
        let later = try LedgerStore.createOffset(for: original, amount: 30, note: "报销", eventType: .reimbursement, in: context)
        XCTAssertEqual(later.scenarioBookIDs, original.scenarioBookIDs)
        let scoped = LedgerScope.filter(try LedgerStore.allTransactions(in: context), selectedBookID: business.stableID)
        XCTAssertEqual(scoped.count, 3)
        XCTAssertEqual(scoped.map(\.amount).reduce(0, +), 50)
    }

    func testMissingBookOrTransactionDoesNotPartiallyChangeBatch() throws {
        let (_, context, total, business, _, cash) = try stack()
        let transaction = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: total)
        XCTAssertThrowsError(try BookMembershipStore.update(transactionIDs: [transaction.stableID], operation: .replace([business.stableID, UUID()]), in: context))
        XCTAssertThrowsError(try BookMembershipStore.update(transactionIDs: [transaction.stableID, UUID()], operation: .add([business.stableID]), in: context))
        XCTAssertFalse(transaction.hasExplicitBookMemberships)
        XCTAssertTrue(transaction.scenarioBookIDs.isEmpty)
    }

    func testDeletingScenePreservesOriginalOtherMembershipAndAccount() throws {
        let (_, context, total, business, project, cash) = try stack()
        let transaction = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: business, scenarioBookIDs: [business.stableID, project.stableID])
        try BookStore.deleteMovingTransactions(business, in: context)
        XCTAssertEqual(transaction.scenarioBookIDs, [project.stableID])
        XCTAssertEqual(transaction.account?.stableID, cash.stableID)
        XCTAssertEqual(try LedgerStore.allTransactions(in: context).count, 1)
        XCTAssertEqual(LedgerStore.accountBalance(for: cash, transactions: try LedgerStore.allTransactions(in: context)), -100)
        XCTAssertEqual(transaction.book?.stableID, total.stableID)
        XCTAssertEqual(LedgerScope.filter([transaction], selectedBookID: nil).count, 1)
        XCTAssertThrowsError(try BookStore.deleteMovingTransactions(total, in: context))
    }

    func testMembershipOnlyChangeInvalidatesProjectionCache() throws {
        let (_, context, total, business, _, cash) = try stack()
        let transaction = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: total)
        let cache = IOSLedgerProjectionCache()
        XCTAssertTrue(cache.snapshot(for: [transaction], selectedBookID: business.stableID).scopedTransactions.isEmpty)
        transaction.setScenarioBookIDs([business.stableID])
        XCTAssertEqual(cache.snapshot(for: [transaction], selectedBookID: business.stableID).scopedTransactions.count, 1)
        XCTAssertEqual(cache.rebuildCount, 2)
    }

    func testMembershipSaveFailureRestoresEveryFamilyWithoutRollingBackUnrelatedChanges() throws {
        struct Failure: Error {}
        let (_, context, total, business, project, cash) = try stack()
        let original = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: total, scenarioBookIDs: [business.stableID])
        let refund = try LedgerStore.createOffset(for: original, amount: 20, note: "退款", eventType: .refund, in: context)
        cash.name = "未保存的账户名称"
        XCTAssertThrowsError(try BookMembershipStore.update(transactionIDs: [original.stableID],
            operation: .replace([project.stableID]), in: context, saveContext: { _ in throw Failure() }))
        XCTAssertEqual(original.scenarioBookIDs, [business.stableID])
        XCTAssertEqual(refund.scenarioBookIDs, [business.stableID])
        XCTAssertEqual(cash.name, "未保存的账户名称")
    }

    func testDefaultUUIDScopeIncludesAllAndAssetEligibilityAcceptsSceneOrOriginalAnchor() throws {
        let (_, context, total, business, project, cash) = try stack()
        let original = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: business, scenarioBookIDs: [project.stableID])
        // 带关系初始化会被 SwiftData 自动放进同一个 context，这里显式插入，查询结果按两笔断言。
        let marker = MoneyTransaction(amount: 1, kind: .income, book: total)
        context.insert(marker)
        XCTAssertEqual(LedgerScope.filter([original, marker], selectedBookID: total.stableID).count, 2)
        XCTAssertEqual(LedgerScope.filter([original], selectedBookID: total.stableID, books: [total, business, project]).count, 1)
        XCTAssertEqual(LedgerScope.filter([original], selectedBookIDs: [total.stableID, project.stableID], books: [total, business, project]).count, 1)
        XCTAssertEqual(Set(try LedgerStore.visibleTransactions(in: context, selectedBookID: total.stableID).map(\.stableID)),
                       [original.stableID, marker.stableID])
        XCTAssertFalse(LedgerScope.allowsAssetAssociation(original, bookID: total.stableID, books: [total, business, project]), "总账本查询全量不应扩大资产的关联资格")
        XCTAssertTrue(LedgerScope.allowsAssetAssociation(original, bookID: business.stableID, books: [total, business, project]))
        XCTAssertTrue(LedgerScope.allowsAssetAssociation(original, bookID: project.stableID, books: [total, business, project]))
        try BookMembershipStore.update(transactionIDs: [original.stableID], operation: .remove([project.stableID]), in: context)
        XCTAssertTrue(LedgerScope.allowsAssetAssociation(original, bookID: business.stableID, books: [total, business, project]), "移出场景不能破坏已有资产原始账本锚点")
    }

    func testBookDeleteCannotDeleteAnyOriginalThroughLegacyDestructiveMethod() throws {
        let (_, context, _, business, _, cash) = try stack()
        let original = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(), account: cash, book: business)
        XCTAssertThrowsError(try BookStore.deleteWithTransactions(business, in: context))
        XCTAssertEqual(try LedgerStore.allTransactions(in: context).map(\.stableID), [original.stableID])
    }

    func testEditingSaveFailureRestoresAllFieldsAndFamilyButPreservesUnrelatedEdits() throws {
        struct Failure: Error {}
        let (_, context, total, business, project, cash) = try stack()
        let original = try LedgerStore.createTransaction(in: context, amount: 100, kind: .expense,
            date: Date(timeIntervalSince1970: 1_700_000_000), account: cash, book: total,
            scenarioBookIDs: [business.stableID])
        let refund = try LedgerStore.createOffset(for: original, amount: 20, note: "退款", eventType: .refund, in: context)
        let before = original.record
        let beforeUpdatedAt = original.updatedAt
        cash.name = "未保存的账户名"
        XCTAssertThrowsError(try LedgerStore.updateTransaction(original, amount: 200,
            date: Date(timeIntervalSince1970: 1_800_000_000), note: "更改备注", category: nil, account: nil,
            attachmentPath: "new.jpg", tags: ["新标签"], scenarioBookIDs: [project.stableID],
            reimbursable: true, isExcluded: true, in: context, saveContext: { _ in throw Failure() }))
        XCTAssertEqual(original.amount, before.amount)
        XCTAssertEqual(original.date, before.date)
        XCTAssertEqual(original.note, before.note)
        XCTAssertEqual(original.account?.stableID, cash.stableID)
        XCTAssertEqual(original.attachmentPath, "")
        XCTAssertTrue(original.tags.isEmpty)
        XCTAssertFalse(original.reimbursable)
        XCTAssertFalse(original.isExcluded)
        XCTAssertEqual(original.updatedAt, beforeUpdatedAt)
        XCTAssertEqual(original.scenarioBookIDs, [business.stableID])
        XCTAssertEqual(refund.scenarioBookIDs, [business.stableID])
        XCTAssertEqual(cash.name, "未保存的账户名")
        try context.save()
        XCTAssertEqual(try LedgerStore.allTransactions(in: context).map(\.amount).reduce(0, +), 80)
    }

    func testDeletingSceneRestoresAllCompatibleAnchorsOnFailureAndKeepsHistoricalBudget() throws {
        struct Failure: Error {}
        let schema = Schema([Account.self, Book.self, TxCategory.self, MoneyTransaction.self,
            Budget.self, BudgetRuleRecord.self, AccountBalanceCheckpointRecord.self,
            PhysicalAsset.self, AssetTransactionLink.self, ReceivableAsset.self, RecurringRule.self,
            ReportRecord.self, AIChatMessage.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let total = Book(name: "总账本", isDefault: true)
        let business = Book(name: "生意")
        context.insert(total); context.insert(business)
        let original = MoneyTransaction(amount: 100, kind: .expense, book: business)
        context.insert(original)
        let physical = PhysicalAsset(name: "设备", bookID: business.stableID)
        let receivable = ReceivableAsset(name: "押金", originalAmount: 100, bookID: business.stableID)
        let recurring = RecurringRule(amount: 10, kind: .expense, bookID: business.stableID,
            accountID: nil, period: .monthly, startDate: Date())
        let report = ReportRecord(bookID: business.stableID, title: "旧报告", periodStart: Date(), periodEnd: Date())
        let budget = Budget(amount: 500, bookID: business.stableID)
        let card = AIRecordCardState(entries: [], bookID: business.stableID)
        let message = AIChatMessage(sessionID: UUID(), role: "assistant", content: "",
            recordJSON: String(decoding: try JSONEncoder().encode(card), as: UTF8.self))
        let link = AssetTransactionLink(assetID: physical.stableID, transactionID: original.stableID,
            linkTypeRaw: AssetTransactionLinkType.sourceTransaction.rawValue, amount: 100)
        context.insert(physical); context.insert(receivable); context.insert(recurring)
        context.insert(report); context.insert(budget); context.insert(message); context.insert(link)
        try context.save()
        let rule = try BudgetRuleStore.save(in: context, editing: nil, bookID: business.stableID,
            kind: .base, name: "", amountYuan: 500, unit: .month, start: nil, end: nil, funding: .carve)
        let previousMessage = message.recordJSON
        try BookMembershipStore.update(transactionIDs: [original.stableID], operation: .remove([business.stableID]), in: context)
        XCTAssertEqual(original.book?.stableID, business.stableID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AssetTransactionLink>()).first?.stableID, link.stableID)
        try BookMembershipStore.update(transactionIDs: [original.stableID], operation: .add([business.stableID]), in: context)
        XCTAssertThrowsError(try BookStore.deleteMovingTransactions(business, in: context, saveContext: { _ in throw Failure() }))
        XCTAssertEqual(original.book?.stableID, business.stableID)
        XCTAssertEqual(original.scenarioBookIDs, [business.stableID])
        XCTAssertTrue(original.hasExplicitBookMemberships)
        XCTAssertEqual(physical.bookID, business.stableID)
        XCTAssertEqual(receivable.bookID, business.stableID)
        XCTAssertEqual(recurring.bookID, business.stableID)
        XCTAssertEqual(report.bookID, business.stableID)
        XCTAssertEqual(message.recordJSON, previousMessage)
        XCTAssertNil(rule.deletedMs)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Book>()).count, 2)
        try BookStore.deleteMovingTransactions(business, in: context)
        XCTAssertTrue(original.scenarioBookIDs.isEmpty)
        XCTAssertEqual(original.book?.stableID, total.stableID)
        XCTAssertEqual(physical.bookID, total.stableID)
        XCTAssertEqual(receivable.bookID, total.stableID)
        XCTAssertEqual(recurring.bookID, total.stableID)
        XCTAssertNil(report.bookID)
        XCTAssertEqual(try JSONDecoder().decode(AIRecordCardState.self, from: Data(message.recordJSON.utf8)).bookID, total.stableID)
        XCTAssertNotNil(rule.deletedMs)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Budget>()).first?.stableID, budget.stableID)
        XCTAssertEqual(budget.bookID, business.stableID, "旧预算历史不能随删除场景而永久删除或改写")
        XCTAssertEqual(try context.fetch(FetchDescriptor<AssetTransactionLink>()).first?.stableID, link.stableID)
        XCTAssertEqual(try LedgerStore.allTransactions(in: context).count, 1)
    }
}
