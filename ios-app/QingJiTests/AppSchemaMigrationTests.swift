import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

private enum RejectedLedgerMigration: SchemaMigrationPlan {
    private enum Failure: Error { case deliberate }
    static var schemas: [any VersionedSchema.Type] { [FeimiaoSchemaV2.self, FeimiaoSchemaV3.self] }
    static var stages: [MigrationStage] {
        [.custom(fromVersion: FeimiaoSchemaV2.self, toVersion: FeimiaoSchemaV3.self,
                 willMigrate: { _ in throw Failure.deliberate }, didMigrate: nil)]
    }
}

/// These use an actual SQLite store, initially created WITHOUT VersionedSchema.
/// Reopening through the production factory must match historical model checksums,
/// preserve the store and relationships, and add only the default membership fields.
@MainActor
final class AppSchemaMigrationTests: XCTestCase {
    func testStartupFailureCanRetryWithoutOpeningAnEmptyFallbackContainer() throws {
        enum OpenFailure: Swift.Error { case injected }
        let expected = try AppModelContainer.makeContainer(inMemory: true)
        var attempts = 0
        let state = DatabaseStartupState(opener: {
            attempts += 1
            if attempts == 1 { throw OpenFailure.injected }
            return expected
        })
        state.open()
        XCTAssertTrue(state.failed)
        XCTAssertNil(state.container)
        state.open()
        XCTAssertFalse(state.failed)
        XCTAssertTrue(state.container === expected)
        state.open()
        XCTAssertEqual(attempts, 2, "An already opened store must not be replaced by another open")
    }

    func testRepeatedStartupFailuresRemainRetryableWithoutSyntheticLedger() {
        enum OpenFailure: Swift.Error { case injected }
        var attempts = 0
        let state = DatabaseStartupState(opener: {
            attempts += 1
            throw OpenFailure.injected
        })
        for _ in 0..<3 {
            state.open()
            XCTAssertTrue(state.failed)
            XCTAssertNil(state.container)
        }
        XCTAssertEqual(attempts, 3)
    }

    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Fixture {
        let records: [TransactionRecord]
        let updatedAt: [UUID: Date]
        let cashID: UUID
        let bankID: UUID
        let totalID: UUID
        let businessID: UUID
        let projectID: UUID
        let ruleID: UUID?
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-migration-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func legacyContainer(at url: URL, budgetRules: Bool) throws -> ModelContainer {
        // Schema(models) deliberately reproduces the former unversioned factory.
        let schema = Schema(budgetRules ? FeimiaoSchemaV2.models : FeimiaoSchemaV1.models)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }

    private func seedLegacy(at url: URL, budgetRules: Bool) throws -> Fixture {
        let container = try legacyContainer(at: url, budgetRules: budgetRules)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let cash = LegacyLedgerModels.Account(name: "现金", kind: .cash)
        cash.initialBalance = 12345.67; cash.institution = "机构"; cash.includeInNetWorth = false
        cash.isDeleted = true; cash.statusRaw = "archived"; cash.archivedAt = timestamp
        cash.lastVerifiedAt = timestamp; cash.openingBalanceEffectiveAt = timestamp
        cash.openingBalanceQualityRaw = "exact"; cash.balanceModeRaw = "principal_only"
        cash.creditStatementDay = 5; cash.creditPaymentDay = 20; cash.creditLimit = 9876.54
        cash.sortOrder = 7; cash.createdAt = timestamp; cash.updatedAt = timestamp
        let bank = LegacyLedgerModels.Account(name: "银行卡", kind: .cash)
        let total = LegacyLedgerModels.Book(name: "总账本", isDefault: true)
        let business = LegacyLedgerModels.Book(name: "生意", cover: "cover", remark: "备注", sortOrder: 3,
                                              isStarred: true, includeInTotal: false)
        business.createdAt = timestamp; business.updatedAt = timestamp
        let project = LegacyLedgerModels.Book(name: "项目")
        let category = LegacyLedgerModels.TxCategory(key: "custom", name: "采购", symbol: "cart",
            kind: .expense, sortOrder: 4, emoji: "🛒", parentKey: "dining")
        category.isArchived = true; category.createdAt = timestamp; category.updatedAt = timestamp
        context.insert(cash); context.insert(bank); context.insert(total)
        context.insert(business); context.insert(project); context.insert(category)
        let original = LegacyLedgerModels.MoneyTransaction(amount: 100.25, kind: .expense, date: timestamp,
            note: "采购,设备", merchantName: "商户", productName: "商品", category: category,
            account: cash, book: business, timePrecision: .exact, createdAt: timestamp, updatedAt: timestamp,
            settledAt: timestamp, settlementQuality: .userConfirmed, settlementAccountID: bank.stableID,
            settlementAccountQuality: .userConfirmed, eventType: .expense, attachmentPath: "receipts/test.jpg",
            orderNo: "ORDER-1", recurringRuleID: UUID(), reimbursable: true, isExcluded: true, tagNames: "采购,项目")
        let refund = LegacyLedgerModels.MoneyTransaction(amount: -20, kind: .expense, date: timestamp,
            note: "退款", category: category, account: cash, book: business, settledAt: timestamp,
            settlementQuality: .userConfirmed, settlementAccountID: bank.stableID,
            settlementAccountQuality: .userConfirmed, eventType: .refund, refundOfID: original.stableID)
        let transfer = LegacyLedgerModels.MoneyTransaction(amount: 50, kind: .transfer, date: timestamp,
            account: cash, toAccount: bank, book: project)
        let unassigned = LegacyLedgerModels.MoneyTransaction(amount: 10, kind: .income, date: timestamp, book: total)
        let rows = [original, refund, transfer, unassigned]
        rows.forEach(context.insert)
        var ruleID: UUID?
        if budgetRules {
            let rule = BudgetRuleRecord(bookID: business.stableID, kindRaw: "base", amountCents: 50000,
                unitRaw: "month", startDate: "2026-10-01", createdMs: 42)
            context.insert(rule); ruleID = rule.stableID
        }
        try context.save()
        return Fixture(records: rows.map(\.record), updatedAt: Dictionary(uniqueKeysWithValues: rows.map { ($0.stableID, $0.updatedAt) }),
                       cashID: cash.stableID, bankID: bank.stableID, totalID: total.stableID,
                       businessID: business.stableID, projectID: project.stableID, ruleID: ruleID)
    }

    private func assertUpgraded(_ fixture: Fixture, in context: ModelContext, file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = try context.fetch(FetchDescriptor<MoneyTransaction>())
        XCTAssertEqual(rows.count, fixture.records.count, file: file, line: line)
        for expected in fixture.records {
            let row = try XCTUnwrap(rows.first { $0.stableID == expected.id }, file: file, line: line)
            var actual = row.record
            actual.scenarioBookIDs = nil; actual.scenarioBookNames = nil
            XCTAssertEqual(actual, expected, "每个旧交易字段、金额、退款和对象关系必须保留", file: file, line: line)
            XCTAssertEqual(row.updatedAt, fixture.updatedAt[row.stableID], file: file, line: line)
            XCTAssertEqual(row.bookMembershipIDsRaw, "", file: file, line: line)
            XCTAssertFalse(row.hasExplicitBookMemberships, file: file, line: line)
        }
        let cash = try XCTUnwrap(context.fetch(FetchDescriptor<Account>()).first { $0.stableID == fixture.cashID })
        XCTAssertEqual(cash.name, "现金"); XCTAssertEqual(cash.kindRaw, AccountKind.cash.rawValue)
        XCTAssertEqual(cash.currencyCode, "CNY"); XCTAssertEqual(cash.initialBalance, 12345.67)
        XCTAssertEqual(cash.institution, "机构"); XCTAssertFalse(cash.includeInNetWorth); XCTAssertTrue(cash.isDeleted)
        XCTAssertEqual(cash.statusRaw, "archived"); XCTAssertEqual(cash.archivedAt, timestamp)
        XCTAssertEqual(cash.lastVerifiedAt, timestamp); XCTAssertEqual(cash.openingBalanceEffectiveAt, timestamp)
        XCTAssertEqual(cash.openingBalanceQualityRaw, "exact"); XCTAssertEqual(cash.balanceModeRaw, "principal_only")
        XCTAssertEqual(cash.creditStatementDay, 5); XCTAssertEqual(cash.creditPaymentDay, 20); XCTAssertEqual(cash.creditLimit, 9876.54)
        XCTAssertEqual(cash.sortOrder, 7); XCTAssertEqual(cash.createdAt, timestamp); XCTAssertEqual(cash.updatedAt, timestamp)
        XCTAssertEqual(Set((cash.outgoingTransactions ?? []).map(\.stableID)), Set(fixture.records.filter { $0.accountID == fixture.cashID }.map(\.id)))
        let bank = try XCTUnwrap(context.fetch(FetchDescriptor<Account>()).first { $0.stableID == fixture.bankID })
        XCTAssertEqual(Set((bank.incomingTransfers ?? []).map(\.stableID)), Set(fixture.records.filter { $0.toAccountID == fixture.bankID }.map(\.id)))
        let book = try XCTUnwrap(context.fetch(FetchDescriptor<Book>()).first { $0.stableID == fixture.businessID })
        XCTAssertEqual(book.name, "生意"); XCTAssertEqual(book.cover, "cover"); XCTAssertEqual(book.remark, "备注")
        XCTAssertEqual(book.sortOrder, 3); XCTAssertTrue(book.isStarred); XCTAssertFalse(book.includeInTotal); XCTAssertFalse(book.isDefault)
        XCTAssertEqual(book.createdAt, timestamp); XCTAssertEqual(book.updatedAt, timestamp)
        XCTAssertEqual(Set((book.transactions ?? []).map(\.stableID)), Set(fixture.records.filter { $0.bookID == fixture.businessID }.map(\.id)))
        let category = try XCTUnwrap(context.fetch(FetchDescriptor<TxCategory>()).first { $0.key == "custom" })
        XCTAssertEqual(category.name, "采购"); XCTAssertEqual(category.symbol, "cart"); XCTAssertEqual(category.emoji, "🛒")
        XCTAssertEqual(category.kindRaw, TransactionKind.expense.rawValue); XCTAssertEqual(category.parentKey, "dining")
        XCTAssertEqual(category.sortOrder, 4); XCTAssertTrue(category.isArchived)
        XCTAssertEqual(category.createdAt, timestamp); XCTAssertEqual(category.updatedAt, timestamp)
        XCTAssertEqual(Set((category.transactions ?? []).map(\.stableID)), Set(fixture.records.filter { $0.categoryKey == "custom" }.map(\.id)))
        let rules = try context.fetch(FetchDescriptor<BudgetRuleRecord>())
        XCTAssertEqual(rules.count, fixture.ruleID == nil ? 0 : 1)
        if let ruleID = fixture.ruleID {
            XCTAssertEqual(rules.first?.stableID, ruleID); XCTAssertEqual(rules.first?.bookID, fixture.businessID)
            XCTAssertEqual(rules.first?.amountCents, 50000)
        }
    }

    func testOriginalUnversionedStoreMigratesInPlaceAndReopensWithAllRelationships() throws {
        let url = try directory().appendingPathComponent("default.store")
        let fixture = try seedLegacy(at: url, budgetRules: false)
        do {
            let container = try AppModelContainer.makeContainer(at: url)
            try assertUpgraded(fixture, in: ModelContext(container))
        }
        let reopened = try AppModelContainer.makeContainer(at: url)
        try assertUpgraded(fixture, in: ModelContext(reopened))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecentUnversionedStoreKeepsBudgetRulesAndMembershipFallback() throws {
        let url = try directory().appendingPathComponent("default.store")
        let fixture = try seedLegacy(at: url, budgetRules: true)
        let container = try AppModelContainer.makeContainer(at: url)
        let context = ModelContext(container)
        try assertUpgraded(fixture, in: context)
        let rows = try context.fetch(FetchDescriptor<MoneyTransaction>())
        XCTAssertEqual(LedgerScope.filter(rows, selectedBookID: fixture.businessID).count, 2)
        XCTAssertEqual(LedgerScope.filter(rows, selectedBookID: nil).count, 4)
    }

    func testMigratedStoreKeepsLegacyEmptyAndMultipleMembershipsAfterSecondOpen() throws {
        let url = try directory().appendingPathComponent("default.store")
        let fixture = try seedLegacy(at: url, budgetRules: true)
        let ids = fixture.records.map(\.id)
        do {
            let container = try AppModelContainer.makeContainer(at: url)
            let context = ModelContext(container)
            try BookMembershipStore.update(transactionIDs: [ids[0]],
                operation: .replace([fixture.businessID, fixture.projectID]), in: context)
            try BookMembershipStore.update(transactionIDs: [ids[3]], operation: .replace([]), in: context)
        }
        let reopened = try AppModelContainer.makeContainer(at: url)
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<MoneyTransaction>())
        let multi = try XCTUnwrap(rows.first { $0.stableID == ids[0] })
        XCTAssertEqual(multi.scenarioBookIDs, [fixture.businessID, fixture.projectID]); XCTAssertTrue(multi.hasExplicitBookMemberships)
        let refund = try XCTUnwrap(rows.first { $0.stableID == ids[1] })
        XCTAssertEqual(refund.scenarioBookIDs, multi.scenarioBookIDs)
        let empty = try XCTUnwrap(rows.first { $0.stableID == ids[3] })
        XCTAssertTrue(empty.scenarioBookIDs.isEmpty); XCTAssertTrue(empty.hasExplicitBookMemberships)
        let legacy = try XCTUnwrap(rows.first { $0.stableID == ids[2] })
        XCTAssertEqual(legacy.scenarioBookIDs, [fixture.projectID]); XCTAssertFalse(legacy.hasExplicitBookMemberships)
    }

    func testFailedMigrationLeavesOriginalStoreReopenableWithOriginalRowsAndAttachment() throws {
        let dir = try directory()
        let url = dir.appendingPathComponent("default.store")
        let media = dir.appendingPathComponent("receipt.jpg")
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        try bytes.write(to: media)
        let fixture = try seedLegacy(at: url, budgetRules: true)
        XCTAssertThrowsError(try AppModelContainer.makeContainer(at: url, migrationPlan: RejectedLedgerMigration.self))
        XCTAssertEqual(try Data(contentsOf: media), bytes)
        do {
            let original = try legacyContainer(at: url, budgetRules: true)
            let records = try ModelContext(original).fetch(FetchDescriptor<LegacyLedgerModels.MoneyTransaction>()).map(\.record)
            XCTAssertEqual(Set(records.map(\.id)), Set(fixture.records.map(\.id)))
            for expected in fixture.records { XCTAssertEqual(records.first { $0.id == expected.id }, expected) }
        }
        let retried = try AppModelContainer.makeContainer(at: url)
        try assertUpgraded(fixture, in: ModelContext(retried))
    }
}
