import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class BackupStoreTests: XCTestCase {
    private final class Stack {
        let context: ModelContext

        init() throws {
            let schema = Schema([
                Account.self,
                Book.self,
                TxCategory.self,
                Tag.self,
                MoneyTransaction.self,
                Budget.self,
                SavingsGoal.self,
                RecurringRule.self,
                RecurringOccurrence.self,
                PhysicalAsset.self,
                AssetEvent.self,
                AssetUsageEvent.self,
                AssetTransactionLink.self,
                AssetRefundAllocation.self,
                AssetValuation.self,
                ReceivableAsset.self,
                ReceivableRecovery.self,
                LiabilityProfile.self,
                NetWorthSnapshot.self,
                AIChatSession.self,
                AIChatMessage.self,
                AIMemoryRecord.self,
                AIRequestRunRecord.self,
                AIRequestEventRecord.self,
                AIReportScheduleRecord.self,
                BudgetPlanRecord.self,
                BudgetPlanRevisionRecord.self,
                BudgetCycleOverrideRecord.self,
                BudgetCommitmentOccurrenceRecord.self,
                BudgetChangeEventRecord.self,
                ReportRecord.self,
                AccountBalanceCheckpointRecord.self,
                NetWorthVerifiedCheckpointRecord.self,
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
        }
    }

    func testRestoreReplacesCurrentModelsInsteadOfMergingThem() throws {
        let stack = try Stack()
        let oldBook = Book(name: "旧账本")
        let oldAccount = Account(name: "旧账户", kind: .cash)
        stack.context.insert(oldBook)
        stack.context.insert(oldAccount)
        try stack.context.save()

        let newBookID = UUID()
        let newAccountID = UUID()
        let newTransactionID = UUID()
        let package = FeimiaoBackupPackage(
            books: [BackupBook(id: newBookID, name: "恢复账本")],
            accounts: [BackupAccount(id: newAccountID, name: "恢复账户", kind: .cash)],
            categories: [BackupCategory(
                key: "dining",
                name: "餐饮",
                symbol: "fork.knife",
                kind: .expense
            )],
            transactions: [BackupTransaction(
                id: newTransactionID,
                amount: 12.34,
                kind: .expense,
                date: Date(timeIntervalSince1970: 1_700_000_000),
                note: "恢复后的午餐",
                categoryKey: "dining",
                accountID: newAccountID,
                bookID: newBookID
            )]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let summary = try BackupStore.importData(
            encoder.encode(package),
            into: stack.context
        )

        XCTAssertEqual(summary.transactions, 1)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<Book>()), 1)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<Account>()), 1)
        XCTAssertEqual(try stack.context.fetchCount(FetchDescriptor<MoneyTransaction>()), 1)
        XCTAssertEqual(
            try stack.context.fetch(FetchDescriptor<MoneyTransaction>()).first?.stableID,
            newTransactionID
        )
        XCTAssertEqual(
            try stack.context.fetch(FetchDescriptor<MoneyTransaction>()).first?.note,
            "恢复后的午餐"
        )
    }

    func testExportAndRestorePreserveAssetRefundAuditAndLinks() throws {
        let stack = try Stack()
        let book = Book(name: "资产账本", isDefault: true)
        let account = Account(name: "现金", kind: .cash)
        let category = TxCategory(key: "shopping", name: "购物", symbol: "bag", kind: .expense)
        stack.context.insert(book)
        stack.context.insert(account)
        stack.context.insert(category)
        try stack.context.save()

        let original = try LedgerStore.createTransaction(
            in: stack.context,
            amount: 100,
            kind: .expense,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            note: "购买资产",
            category: category,
            account: account,
            book: book
        )
        let asset = try AssetStore.createFromTransaction(
            in: stack.context,
            transaction: original,
            name: "测试物品",
            kind: .digital,
            allocatedGrossCents: 10_000,
            currentValue: 80
        )
        let refund = try LedgerStore.createOffset(
            for: original,
            amount: 20,
            note: "资产退款",
            eventType: .refund,
            settlementAccount: account,
            in: stack.context
        )
        let sourceLink = try XCTUnwrap(
            stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
                .first(where: { $0.assetID == asset.stableID })
        )
        let audit = try XCTUnwrap(
            stack.context.fetch(FetchDescriptor<AssetRefundAllocation>())
                .first(where: { $0.refundTransactionID == refund.stableID })
        )
        let originalID = original.stableID
        let refundID = refund.stableID
        let assetID = asset.stableID
        let sourceLinkID = sourceLink.stableID
        let auditID = audit.stableID
        let exported = try BackupStore.export(context: stack.context)

        try BackupStore.importData(exported, into: stack.context)

        let restoredAsset = try XCTUnwrap(
            stack.context.fetch(FetchDescriptor<PhysicalAsset>())
                .first(where: { $0.stableID == assetID })
        )
        let restoredLink = try XCTUnwrap(
            stack.context.fetch(FetchDescriptor<AssetTransactionLink>())
                .first(where: { $0.stableID == sourceLinkID })
        )
        let restoredAudit = try XCTUnwrap(
            stack.context.fetch(FetchDescriptor<AssetRefundAllocation>())
                .first(where: { $0.stableID == auditID })
        )
        XCTAssertEqual(restoredLink.transactionID, originalID)
        XCTAssertEqual(restoredLink.allocatedRefundCents, 2_000)
        XCTAssertEqual(restoredAudit.assetTransactionLinkID, restoredLink.stableID)
        XCTAssertEqual(restoredAudit.refundTransactionID, refundID)
        XCTAssertEqual(restoredAudit.statusRaw, "active")
        XCTAssertEqual(restoredAsset.purchasePrice, 80)
    }

    func testUnsupportedFutureRestoreDoesNotDeleteCurrentModels() throws {
        let stack = try Stack()
        let oldBook = Book(name: "当前账本", isDefault: true)
        stack.context.insert(oldBook)
        try stack.context.save()
        let future = FeimiaoBackupPackage(schemaVersion: FeimiaoBackupPackage.currentSchemaVersion + 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        XCTAssertThrowsError(
            try BackupStore.importData(try encoder.encode(future), into: stack.context)
        ) { error in
            guard let backupError = error as? BackupStoreError,
                  case .unsupportedVersion(let version) = backupError else {
                return XCTFail("期望拒绝未来备份版本，实际为：\(error)")
            }
            XCTAssertEqual(version, FeimiaoBackupPackage.currentSchemaVersion + 1)
        }
        XCTAssertEqual(
            try stack.context.fetch(FetchDescriptor<Book>()).first?.stableID,
            oldBook.stableID
        )
    }
}
