import XCTest
import SwiftData
import QingJiCore
@testable import QingJi

/// 模型为了兼容 CloudKit 不用唯一约束。库里一旦有重复编号（以后开 iCloud 同步，两台设备
/// 各写一条同 key 的默认分类就会出现），启动补分类、合并恢复、算资产都不能崩，
/// 也不删除或合并已有的记录。
@MainActor
final class DuplicateStoreKeyToleranceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.makeContainer(inMemory: true))
    }

    func testSeederToleratesDuplicateCategoryKeysWithoutDeletingEither() throws {
        let context = try makeContext()
        let seed = try XCTUnwrap(CategorySeed.all.first)
        context.insert(TxCategory(key: seed.key, name: "重复甲", symbol: "tag", kind: seed.kind, sortOrder: 900))
        context.insert(TxCategory(key: seed.key, name: "重复乙", symbol: "tag", kind: seed.kind, sortOrder: 901))
        try context.save()

        DataSeeder.seedIfNeeded(context: context)
        DataSeeder.seedIfNeeded(context: context)

        let all = try context.fetch(FetchDescriptor<TxCategory>())
        let duplicates = all.filter { $0.key == seed.key }
        XCTAssertEqual(duplicates.count, 2)
        XCTAssertTrue(duplicates.contains { $0.sortOrder == 0 })
        XCTAssertEqual(all.count, Set(CategorySeed.all.map(\.key)).count + 1)
    }

    func testMergeRestoreToleratesDuplicateStoreIDsWithoutDeletingCopies() throws {
        let context = try makeContext()
        let bookID = UUID()
        let accountID = UUID()
        let transactionID = UUID()
        for suffix in ["甲", "乙"] {
            let book = Book(name: "旧账本\(suffix)")
            book.stableID = bookID
            let account = Account(name: "旧账户\(suffix)", kind: .cash)
            account.stableID = accountID
            context.insert(book)
            context.insert(account)
            context.insert(TxCategory(key: "dining", name: "旧餐饮\(suffix)", symbol: "tag", kind: .expense))
            context.insert(MoneyTransaction(
                amount: 30,
                kind: .expense,
                note: "旧午餐\(suffix)",
                book: book,
                stableID: transactionID
            ))
        }
        try context.save()

        let package = FeimiaoBackupPackage(
            books: [BackupBook(id: bookID, name: "恢复账本")],
            accounts: [BackupAccount(id: accountID, name: "恢复账户", kind: .cash)],
            categories: [BackupCategory(
                key: "dining",
                name: "餐饮",
                symbol: "fork.knife",
                kind: .expense
            )],
            transactions: [BackupTransaction(
                id: transactionID,
                amount: 12.34,
                kind: .expense,
                date: Date(timeIntervalSince1970: 1_700_000_000),
                note: "恢复后的午餐",
                categoryKey: "dining",
                accountID: accountID,
                bookID: bookID
            )]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        _ = try BackupStore.importData(encoder.encode(package), into: context, mode: .merge)

        let books = try context.fetch(FetchDescriptor<Book>()).filter { $0.stableID == bookID }
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.stableID == accountID }
        let categories = try context.fetch(FetchDescriptor<TxCategory>()).filter { $0.key == "dining" }
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
            .filter { $0.stableID == transactionID }
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(categories.count, 2)
        XCTAssertEqual(transactions.count, 2)
        XCTAssertEqual(books.filter { $0.name == "恢复账本" }.count, 1)
        XCTAssertEqual(accounts.filter { $0.name == "恢复账户" }.count, 1)
        XCTAssertEqual(categories.filter { $0.name == "餐饮" }.count, 1)
        XCTAssertEqual(transactions.filter { $0.note == "恢复后的午餐" }.count, 1)
    }

    func testAssetMetricsTolerateDuplicateTransactionIDs() throws {
        let context = try makeContext()
        let book = Book(name: "测试账本", isDefault: true)
        context.insert(book)
        let sharedID = UUID()
        context.insert(MoneyTransaction(amount: 10, kind: .expense, note: "重复甲", book: book, stableID: sharedID))
        context.insert(MoneyTransaction(amount: 20, kind: .expense, note: "重复乙", book: book, stableID: sharedID))
        let calendar = Calendar(identifier: .gregorian)
        let asOf = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 10)))
        let asset = PhysicalAsset(name: "测试手机", kind: .digital, purchasePrice: 1_000, currentValue: 880)
        asset.purchaseDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        context.insert(asset)
        context.insert(AssetValuation(assetID: asset.stableID, value: 880, valuedAt: asOf))
        try context.save()

        let metrics = try AssetStore.metrics(for: asset, in: context, asOf: asOf)
        XCTAssertEqual(metrics.cumulativeHoldingInvestment.value, 1_000)
    }
}
