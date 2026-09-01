import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

@MainActor
final class BackupStoreTests: XCTestCase {
    private enum SaveFailure: Error, Equatable {
        case expected
    }

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

    func testJSONRestoreSaveFailureRollsBackExistingModels() throws {
        let destination = try Stack()
        let existing = Book(name: "保存失败后仍在")
        destination.context.insert(existing)
        try destination.context.save()

        let replacementID = UUID()
        let package = FeimiaoBackupPackage(
            books: [BackupBook(id: replacementID, name: "不应留下的恢复账本")]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        XCTAssertThrowsError(
            try BackupStore.importData(
                try encoder.encode(package),
                into: destination.context,
                saveContext: { _ in throw SaveFailure.expected }
            )
        ) { error in
            guard let failure = error as? SaveFailure else {
                return XCTFail("expected injected save failure, got \(error)")
            }
            XCTAssertEqual(failure, .expected)
        }

        XCTAssertEqual(try destination.context.fetchCount(FetchDescriptor<Book>()), 1)
        XCTAssertEqual(
            try destination.context.fetch(FetchDescriptor<Book>()).first?.name,
            existing.name
        )
        XCTAssertNil(
            try destination.context.fetch(FetchDescriptor<Book>()).first {
                $0.stableID == replacementID
            }
        )
    }

    func testArchiveRoundTripIncludesTransactionAttachments() throws {
        let source = try Stack()
        let book = Book(name: "附件账本", isDefault: true)
        let account = Account(name: "现金", kind: .cash)
        source.context.insert(book)
        source.context.insert(account)
        let attachmentPath = try AttachmentStore.save(data: Data("receipt-data".utf8))
        defer { AttachmentStore.remove(attachmentPath) }
        let transaction = MoneyTransaction(
            amount: 18.5,
            kind: .expense,
            note: "带附件",
            account: account,
            book: book,
            attachmentPath: attachmentPath
        )
        source.context.insert(transaction)
        try source.context.save()

        let archive = try BackupStore.exportArchive(context: source.context)
        let entries = try ZipArchive.decode(archive)
        let paths = Set(entries.map(\.path))
        XCTAssertTrue(paths.contains("manifest.json"))
        XCTAssertTrue(paths.contains("database/feimiao.json"))
        XCTAssertTrue(paths.contains("receipts/\(attachmentPath)"))

        let restored = try Stack()
        let summary = try BackupStore.importData(archive, into: restored.context)
        XCTAssertEqual(summary.transactions, 1)
        let restoredTransaction = try XCTUnwrap(
            try restored.context.fetch(FetchDescriptor<MoneyTransaction>()).first
        )
        XCTAssertEqual(restoredTransaction.attachmentPath, attachmentPath)
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(AttachmentStore.url(for: attachmentPath))),
            Data("receipt-data".utf8)
        )
    }

    func testArchiveChecksumFailureLeavesExistingModelsUntouched() throws {
        let source = try Stack()
        let book = Book(name: "源账本", isDefault: true)
        source.context.insert(book)
        try source.context.save()
        let archive = try BackupStore.exportArchive(context: source.context)
        let entries = try ZipArchive.decode(archive)
        let mutatedEntries = try entries.map { entry in
            if entry.path == "database/feimiao.json" {
                return try ZipArchive.Entry(path: entry.path, data: entry.data + Data("tampered".utf8))
            }
            return entry
        }
        let tamperedArchive = try ZipArchive.encode(mutatedEntries)

        let destination = try Stack()
        let existing = Book(name: "保留账本")
        destination.context.insert(existing)
        try destination.context.save()

        XCTAssertThrowsError(
            try BackupStore.importData(tamperedArchive, into: destination.context)
        ) { error in
            guard case BackupStoreError.malformedArchive = error else {
                return XCTFail("expected malformed archive, got \(error)")
            }
        }
        XCTAssertEqual(try destination.context.fetchCount(FetchDescriptor<Book>()), 1)
        XCTAssertEqual(
            try destination.context.fetch(FetchDescriptor<Book>()).first?.name,
            existing.name
        )
    }

    func testArchiveAttachmentInstallFailureRollsBackModelsAndFiles() throws {
        let source = try Stack()
        let sourceBook = Book(name: "源账本", isDefault: true)
        source.context.insert(sourceBook)
        let firstAttachmentPath = "rollback-first-\(UUID().uuidString).txt"
        let secondAttachmentPath = "rollback-second-\(UUID().uuidString).txt"
        try AttachmentStore.writeImported(data: Data("source-first".utf8), relativePath: firstAttachmentPath)
        try AttachmentStore.writeImported(data: Data("source-second".utf8), relativePath: secondAttachmentPath)
        defer {
            AttachmentStore.remove(firstAttachmentPath)
            if let url = AttachmentStore.url(for: secondAttachmentPath) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let sourceTransaction = MoneyTransaction(
            amount: 22,
            kind: .expense,
            note: "源附件",
            book: sourceBook,
            attachmentPath: firstAttachmentPath
        )
        let secondSourceTransaction = MoneyTransaction(
            amount: 23,
            kind: .expense,
            note: "源第二附件",
            book: sourceBook,
            attachmentPath: secondAttachmentPath
        )
        source.context.insert(sourceTransaction)
        source.context.insert(secondSourceTransaction)
        try source.context.save()
        let archive = try BackupStore.exportArchive(context: source.context)
        AttachmentStore.remove(firstAttachmentPath)
        AttachmentStore.remove(secondAttachmentPath)
        try AttachmentStore.writeImported(data: Data("destination-old".utf8), relativePath: firstAttachmentPath)
        let collisionURL = try XCTUnwrap(AttachmentStore.url(for: secondAttachmentPath))
        try FileManager.default.createDirectory(at: collisionURL, withIntermediateDirectories: true)

        let destination = try Stack()
        let existing = Book(name: "恢复失败后仍在")
        destination.context.insert(existing)
        try destination.context.save()

        XCTAssertThrowsError(
            try BackupStore.importData(archive, into: destination.context)
        )
        XCTAssertEqual(try destination.context.fetchCount(FetchDescriptor<Book>()), 1)
        XCTAssertEqual(
            try destination.context.fetch(FetchDescriptor<Book>()).first?.name,
            existing.name
        )
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(AttachmentStore.url(for: firstAttachmentPath))),
            Data("destination-old".utf8)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: collisionURL.path))
        try FileManager.default.removeItem(at: collisionURL)
    }
}
