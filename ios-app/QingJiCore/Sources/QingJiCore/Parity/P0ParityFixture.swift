import Foundation

/// The deterministic input used by the Android/iOS parity capture harness.
///
/// This type intentionally contains transport primitives (decimal amounts and
/// ISO-8601 dates as strings) instead of platform model objects. Both apps can
/// therefore decode the same file without sharing a storage implementation.
public struct P0ParityFixture: Codable, Equatable, Sendable {
    /// Frozen together with the P0 contract; runtime loaders also compare the
    /// bytes they actually bundled against this value.
    public static let canonicalInputHash = "E45AB0CEFF322CCAE8A54474AB523F954724A749D0561F698ED81F23850996A6"

    public let schemaVersion: Int
    public let fixtureId: String
    public let clock: String
    public let locale: String
    public let timezone: String
    public let currency: String
    public let books: [P0FixtureBook]
    public let accounts: [P0FixtureAccount]
    public let transactions: [P0FixtureTransaction]
    public let budgets: [P0FixtureBudget]
    public let savingsGoals: [P0FixtureSavingsGoal]
    public let recurringRules: [P0FixtureRecurringRule]
    public let reports: [P0FixtureReport]
    public let optionalSceneData: P0FixtureOptionalSceneData?
    public let expected: P0FixtureExpected

    public static func decode(_ data: Data) throws -> P0ParityFixture {
        try JSONDecoder().decode(P0ParityFixture.self, from: data)
    }
}

public struct P0FixtureBook: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let cover: String?
    public let remark: String?
    public let includeInTotal: Bool
    public let isDefault: Bool
    public let sortOrder: Int
}

public struct P0FixtureAccount: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let kind: String
    public let initialBalance: String
    public let sortOrder: Int
}

public struct P0FixtureTransaction: Codable, Equatable, Sendable {
    public let key: String
    public let kind: String
    public let amount: String
    public let category: String?
    public let account: String
    public let toAccount: String?
    public let book: String
    public let note: String
    public let date: String
    public let currency: String?
    public let merchant: String?
    public let product: String?
    public let reimbursable: Bool?
    public let excluded: Bool?
    public let settledAt: String?
    public let settlementAccount: String?
    public let eventType: String?
    public let refundOf: String?
    public let isReimbursed: Bool?
    public let orderNo: String?
}

public struct P0FixtureBudget: Codable, Equatable, Sendable {
    public let key: String
    public let book: String
    public let category: String?
    public let periodStart: String
    public let cycle: String
    public let amount: String
}

public struct P0FixtureSavingsGoal: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let emoji: String?
    public let target: String
    public let saved: String
    public let note: String?
}

public struct P0FixtureRecurringRule: Codable, Equatable, Sendable {
    public let key: String
    public let kind: String
    public let amount: String
    public let category: String?
    public let account: String
    public let toAccount: String?
    public let book: String
    public let note: String?
    public let period: String
    public let startDate: String
    public let endDate: String?
    public let totalCount: Int?
}

public struct P0FixtureReport: Codable, Equatable, Sendable {
    public let key: String
    public let type: String
    public let book: String
    public let title: String
    public let summary: String
    public let periodStart: String
    public let periodEnd: String
}

public struct P0FixtureOptionalSceneData: Codable, Equatable, Sendable {
    public let physicalAssetDetail: P0FixturePhysicalAssetDetail?
}

public struct P0FixturePhysicalAssetDetail: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let kind: String
    public let purchasePrice: String
    public let currentValue: String
    public let purchaseDate: String
    public let brand: String?
    public let model: String?
    public let location: String?
    public let warrantyUntil: String?
    public let includeInNetWorth: Bool?
}

public struct P0FixtureExpected: Codable, Equatable, Sendable {
    public let augustIncome: String
    public let augustGrossExpense: String
    public let augustRefund: String
    public let augustNetExpense: String
    public let augustBalance: String
    public let augustTransactionRowsIncludingOffsetAndTransfer: Int
    public let augustVisibleOrdinaryRows: Int
    public let budget: String
}
