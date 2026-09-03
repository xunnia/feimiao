import Foundation
import CryptoKit
import SwiftData
import QingJiCore

enum P0ParityFixtureError: LocalizedError {
    case resourceMissing
    case invalidDate(String)
    case invalidAmount(String)
    case invalidReference(String)
    case unsupportedValue(String)
    case fixtureHashMissing
    case fixtureHashMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing:
            return "canonical P0 fixture is not bundled"
        case .invalidDate(let value):
            return "invalid P0 fixture date: \(value)"
        case .invalidAmount(let value):
            return "invalid P0 fixture amount: \(value)"
        case .invalidReference(let value):
            return "invalid P0 fixture reference: \(value)"
        case .unsupportedValue(let value):
            return "unsupported P0 fixture value: \(value)"
        case .fixtureHashMissing:
            return "QINGJI_P0_FIXTURE_HASH is missing from the parity launch environment"
        case .fixtureHashMismatch(let expected, let actual):
            return "P0 fixture SHA-256 differs: actual=\(actual) expected=\(expected)"
        }
    }
}

enum P0ParityFixtureLoader {
    static let resourceName = "p0-demo-ledger-2026-08-v1"

    static func load() throws -> P0ParityFixture {
        try loadWithProvenance().fixture
    }

    static func loadWithProvenance() throws -> (fixture: P0ParityFixture, inputHash: String) {
        let urls = [
            Bundle.main.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: "tools/fixtures"
            ),
            Bundle.main.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: "fixtures"
            ),
            Bundle.main.url(forResource: resourceName, withExtension: "json"),
        ]
        guard let url = urls.compactMap({ $0 }).first else {
            throw P0ParityFixtureError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let actualHash = SHA256.hash(data: data)
            .map { String(format: "%02X", $0) }
            .joined()
        guard actualHash == P0ParityFixture.canonicalInputHash else {
            throw P0ParityFixtureError.fixtureHashMismatch(
                expected: P0ParityFixture.canonicalInputHash,
                actual: actualHash
            )
        }
        guard let rawExpectedHash = ProcessInfo.processInfo.environment["QINGJI_P0_FIXTURE_HASH"],
              !rawExpectedHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw P0ParityFixtureError.fixtureHashMissing
        }
        let expectedHash = rawExpectedHash.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard expectedHash == actualHash else {
            throw P0ParityFixtureError.fixtureHashMismatch(expected: expectedHash, actual: actualHash)
        }
        return (try P0ParityFixture.decode(data), actualHash)
    }

    static func date(_ raw: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
        ]
        guard let value = formatter.date(from: raw) else {
            throw P0ParityFixtureError.invalidDate(raw)
        }
        return value
    }

    static func amount(_ raw: String) throws -> Decimal {
        guard let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else {
            throw P0ParityFixtureError.invalidAmount(raw)
        }
        return value
    }
}

enum P0ParityDemoSeeder {
    static func seed(
        context: ModelContext,
        fixture: P0ParityFixture,
        inputHash: String
    ) throws {
        guard fixture.schemaVersion == 1 else {
            throw P0ParityFixtureError.unsupportedValue("schemaVersion=\(fixture.schemaVersion)")
        }

        let categories = insertCategories(context: context)
        let books = try insertBooks(context: context, fixture: fixture)
        let accounts = try insertAccounts(context: context, fixture: fixture)
        let transactions = try insertTransactions(
            context: context,
            fixture: fixture,
            categories: categories,
            books: books,
            accounts: accounts
        )
        let budgets = try insertBudgets(context: context, fixture: fixture, books: books)
        let savingsGoals = try insertSavingsGoals(context: context, fixture: fixture)
        let recurringRules = try insertRecurringRules(
            context: context,
            fixture: fixture,
            categories: categories,
            books: books,
            accounts: accounts
        )
        let reports = try insertReports(context: context, fixture: fixture, books: books)

        var physicalAssets: [PhysicalAsset] = []
        let launchScreen = ProcessInfo.processInfo.environment["QINGJI_SCREEN"] ?? ""
        if ["assets/detail", "assets-detail", "settings/assets/detail"].contains(launchScreen),
           let detail = fixture.optionalSceneData?.physicalAssetDetail,
           let bookKey = fixture.books.first?.key,
           let book = books[bookKey] {
            physicalAssets = try insertAssetDetail(
                context: context,
                detail: detail,
                book: book
            )
        }

        try context.save()
        try P0ParityBusinessExporter.write(
            fixture: fixture,
            inputHash: inputHash,
            books: books,
            accounts: accounts,
            transactions: transactions,
            budgets: budgets,
            savingsGoals: savingsGoals,
            recurringRules: recurringRules,
            reports: reports,
            physicalAssets: physicalAssets
        )
    }

    private static func insertCategories(context: ModelContext) -> [String: TxCategory] {
        var result: [String: TxCategory] = [:]
        for (index, seed) in CategorySeed.all.enumerated() {
            let category = TxCategory(
                key: seed.key,
                name: seed.nameZh,
                symbol: seed.symbol,
                kind: seed.kind,
                sortOrder: index,
                emoji: seed.emoji,
                parentKey: seed.parentKey
            )
            context.insert(category)
            result[seed.key] = category
        }
        return result
    }

    private static func insertBooks(
        context: ModelContext,
        fixture: P0ParityFixture
    ) throws -> [String: Book] {
        var result: [String: Book] = [:]
        for row in fixture.books {
            guard result[row.key] == nil else {
                throw P0ParityFixtureError.invalidReference("duplicate book key \(row.key)")
            }
            let book = Book(
                name: row.name,
                cover: row.cover ?? "",
                remark: row.remark ?? "",
                sortOrder: row.sortOrder,
                isStarred: false,
                includeInTotal: row.includeInTotal,
                isDefault: row.isDefault
            )
            context.insert(book)
            result[row.key] = book
        }
        return result
    }

    private static func insertAccounts(
        context: ModelContext,
        fixture: P0ParityFixture
    ) throws -> [String: Account] {
        var result: [String: Account] = [:]
        for row in fixture.accounts {
            guard result[row.key] == nil else {
                throw P0ParityFixtureError.invalidReference("duplicate account key \(row.key)")
            }
            guard let kind = accountKind(for: row.kind) else {
                throw P0ParityFixtureError.unsupportedValue("account kind \(row.kind)")
            }
            let account = Account(
                name: row.name,
                kind: kind,
                currencyCode: fixture.currency,
                sortOrder: row.sortOrder
            )
            account.initialBalance = try P0ParityFixtureLoader.amount(row.initialBalance)
            context.insert(account)
            result[row.key] = account
        }
        return result
    }

    private static func accountKind(for canonicalKind: String) -> AccountKind? {
        switch canonicalKind {
        case "debit":
            return .bankCard
        case "credit":
            return .creditCard
        default:
            return AccountKind(rawValue: canonicalKind)
        }
    }

    private static func insertTransactions(
        context: ModelContext,
        fixture: P0ParityFixture,
        categories: [String: TxCategory],
        books: [String: Book],
        accounts: [String: Account]
    ) throws -> [MoneyTransaction] {
        var byKey: [String: MoneyTransaction] = [:]
        var rows: [MoneyTransaction] = []

        for row in fixture.transactions {
            guard byKey[row.key] == nil else {
                throw P0ParityFixtureError.invalidReference("duplicate transaction key \(row.key)")
            }
            guard let kind = TransactionKind(rawValue: row.kind),
                  let account = accounts[row.account],
                  let book = books[row.book] else {
                throw P0ParityFixtureError.invalidReference("transaction \(row.key)")
            }
            if let toAccountKey = row.toAccount, accounts[toAccountKey] == nil {
                throw P0ParityFixtureError.invalidReference("transaction \(row.key) toAccount")
            }
            if let categoryKey = row.category, categories[categoryKey] == nil {
                throw P0ParityFixtureError.invalidReference("transaction \(row.key) category")
            }

            let transactionDate = try P0ParityFixtureLoader.date(row.date)
            let settlementAccountKey = row.settlementAccount ?? row.account
            guard let settlementAccount = accounts[settlementAccountKey] else {
                throw P0ParityFixtureError.invalidReference("transaction \(row.key) settlementAccount")
            }
            let eventType = row.eventType.flatMap(TransactionEventType.init(rawValue:))
                ?? .defaultFor(kind)
            let amount = try P0ParityFixtureLoader.amount(row.amount)
            let category = row.category.flatMap { categories[$0] }
            let toAccount = row.toAccount.flatMap { accounts[$0] }
            let currencyCode = row.currency ?? fixture.currency
            let settledAt = try row.settledAt.map(P0ParityFixtureLoader.date) ?? transactionDate
            let transaction = MoneyTransaction(
                amount: amount,
                kind: kind,
                date: transactionDate,
                note: row.note,
                merchantName: row.merchant ?? "",
                productName: row.product ?? "",
                currencyCode: currencyCode,
                category: category,
                account: account,
                toAccount: toAccount,
                book: book,
                timePrecision: .entryClock,
                settledAt: settledAt,
                settlementQuality: .userConfirmed,
                settlementAccountID: settlementAccount.stableID,
                settlementAccountQuality: .userConfirmed,
                eventType: eventType,
                orderNo: row.orderNo ?? "",
                reimbursable: row.reimbursable ?? false,
                isReimbursed: row.isReimbursed ?? false,
                isExcluded: row.excluded ?? false
            )
            context.insert(transaction)
            byKey[row.key] = transaction
            rows.append(transaction)
        }

        for row in fixture.transactions {
            guard let refundKey = row.refundOf else { continue }
            guard let transaction = byKey[row.key],
                  let original = byKey[refundKey] else {
                throw P0ParityFixtureError.invalidReference("refund \(row.key) -> \(refundKey)")
            }
            transaction.refundOfID = original.stableID
        }
        return rows
    }

    private static func insertBudgets(
        context: ModelContext,
        fixture: P0ParityFixture,
        books: [String: Book]
    ) throws -> [Budget] {
        var result: [Budget] = []
        for row in fixture.budgets {
            guard let book = books[row.book] else {
                throw P0ParityFixtureError.invalidReference("budget \(row.key) book")
            }
            let budget = Budget(
                amount: try P0ParityFixtureLoader.amount(row.amount),
                categoryKey: row.category,
                bookID: book.stableID,
                periodStart: try P0ParityFixtureLoader.date(row.periodStart),
                cycleRaw: row.cycle
            )
            context.insert(budget)
            result.append(budget)
        }
        return result
    }

    private static func insertSavingsGoals(
        context: ModelContext,
        fixture: P0ParityFixture
    ) throws -> [SavingsGoal] {
        var result: [SavingsGoal] = []
        for row in fixture.savingsGoals {
            let goal = SavingsGoal(
                name: row.name,
                emoji: row.emoji ?? "🐷",
                targetAmount: try P0ParityFixtureLoader.amount(row.target),
                savedAmount: try P0ParityFixtureLoader.amount(row.saved),
                currencyCode: fixture.currency,
                note: row.note ?? ""
            )
            context.insert(goal)
            result.append(goal)
        }
        return result
    }

    private static func insertRecurringRules(
        context: ModelContext,
        fixture: P0ParityFixture,
        categories: [String: TxCategory],
        books: [String: Book],
        accounts: [String: Account]
    ) throws -> [RecurringRule] {
        var result: [RecurringRule] = []
        for row in fixture.recurringRules {
            guard let kind = TransactionKind(rawValue: row.kind),
                  let book = books[row.book],
                  let account = accounts[row.account],
                  let period = RecurringPeriod(rawValue: row.period) else {
                throw P0ParityFixtureError.invalidReference("recurring rule \(row.key)")
            }
            if let categoryKey = row.category, categories[categoryKey] == nil {
                throw P0ParityFixtureError.invalidReference("recurring rule \(row.key) category")
            }
            if let toAccountKey = row.toAccount, accounts[toAccountKey] == nil {
                throw P0ParityFixtureError.invalidReference("recurring rule \(row.key) toAccount")
            }
            let startDate = try P0ParityFixtureLoader.date(row.startDate)
            let rule = RecurringRule(
                amount: try P0ParityFixtureLoader.amount(row.amount),
                kind: kind,
                bookID: book.stableID,
                categoryKey: row.category,
                accountID: account.stableID,
                toAccountID: row.toAccount.flatMap { accounts[$0]?.stableID },
                note: row.note ?? "",
                period: period,
                startDate: startDate,
                firstDueDate: startDate,
                endDate: try row.endDate.map(P0ParityFixtureLoader.date),
                totalCount: row.totalCount
            )
            context.insert(rule)
            result.append(rule)
        }
        return result
    }

    private static func insertReports(
        context: ModelContext,
        fixture: P0ParityFixture,
        books: [String: Book]
    ) throws -> [ReportRecord] {
        var result: [ReportRecord] = []
        for row in fixture.reports {
            guard let book = books[row.book] else {
                throw P0ParityFixtureError.invalidReference("report \(row.key) book")
            }
            let report = ReportRecord(
                bookID: book.stableID,
                type: row.type,
                title: row.title,
                summary: row.summary,
                markdown: "# \(row.title)\n\n\(row.summary)",
                periodStart: try P0ParityFixtureLoader.date(row.periodStart),
                periodEnd: try P0ParityFixtureLoader.date(row.periodEnd),
                createdAt: try P0ParityFixtureLoader.date(fixture.clock),
                pinnedAt: nil
            )
            context.insert(report)
            result.append(report)
        }
        return result
    }

    private static func insertAssetDetail(
        context: ModelContext,
        detail: P0FixturePhysicalAssetDetail,
        book: Book
    ) throws -> [PhysicalAsset] {
        guard let kind = PhysicalAssetKind(rawValue: detail.kind) else {
            throw P0ParityFixtureError.unsupportedValue("asset kind \(detail.kind)")
        }
        let purchaseDate = try P0ParityFixtureLoader.date(detail.purchaseDate)
        let asset = PhysicalAsset(
            name: detail.name,
            kind: kind,
            purchasePrice: try P0ParityFixtureLoader.amount(detail.purchasePrice),
            currentValue: try P0ParityFixtureLoader.amount(detail.currentValue),
            currencyCode: "CNY",
            bookID: book.stableID
        )
        asset.brand = detail.brand ?? ""
        asset.model = detail.model ?? ""
        asset.location = detail.location ?? ""
        asset.purchaseDate = purchaseDate
        asset.warrantyUntil = try detail.warrantyUntil.map(P0ParityFixtureLoader.date)
        asset.includeInNetWorth = detail.includeInNetWorth ?? true
        asset.sourceType = .historicalExisting
        asset.acquisitionCostSourceRaw = "manual"
        asset.note = "P0 fixture asset"
        context.insert(asset)
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .created,
            occurredAt: purchaseDate,
            value: asset.currentValue,
            note: "fixture asset"
        ))
        context.insert(AssetValuation(
            assetID: asset.stableID,
            value: asset.currentValue,
            sourceRaw: "purchase",
            valuedAt: purchaseDate,
            note: "fixture current value"
        ))
        return [asset]
    }
}
