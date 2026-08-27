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
}
