import Foundation
import SwiftData

@Model
final class AccountBalanceCheckpointRecord {
    var stableID: UUID = UUID()
    var accountID: UUID = UUID()
    var eventKindRaw: String = "anchor"
    var effectiveAt: Date = Date()
    var sequence: Int = 0
    var timezone: String = "device_local"
    var knowledgeCutoff: Date = Date()
    var targetBalance: Decimal = 0
    var calculatedBefore: Decimal = 0
    var deltaAtCreation: Decimal = 0
    var reason: String = "manual"
    var note: String = ""
    var status: String = "active"
    var reversalOfID: UUID? = nil
    var coveredUnknownEventIDsJSON: String = "[]"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        stableID: UUID = UUID(),
        accountID: UUID,
        effectiveAt: Date,
        knowledgeCutoff: Date,
        targetBalance: Decimal = 0,
        eventKindRaw: String = "anchor"
    ) {
        self.stableID = stableID
        self.accountID = accountID
        self.effectiveAt = effectiveAt
        self.knowledgeCutoff = knowledgeCutoff
        self.targetBalance = targetBalance
        self.eventKindRaw = eventKindRaw
    }

    var coveredUnknownEventIDs: [String] {
        guard let data = coveredUnknownEventIDsJSON.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }
}

@Model
final class NetWorthVerifiedCheckpointRecord {
    var stableID: UUID = UUID()
    var asOf: Date = Date()
    var knowledgeCutoff: Date = Date()
    var scopeVersion: Int = 1
    var calculationVersion: Int = 1
    var currencyCoverageJSON: String = ""
    var totalAssets: Decimal = 0
    var totalLiabilities: Decimal = 0
    var netWorth: Decimal = 0
    var completenessRaw: String = "partial"
    var reasonsJSON: String = ""
    var statusRaw: String = "active"
    var supersedesID: UUID? = nil
    var createdAt: Date = Date()
    var itemsJSON: String = "[]"

    init(
        stableID: UUID = UUID(),
        asOf: Date,
        knowledgeCutoff: Date,
        totalAssets: Decimal = 0,
        totalLiabilities: Decimal = 0,
        netWorth: Decimal = 0
    ) {
        self.stableID = stableID
        self.asOf = asOf
        self.knowledgeCutoff = knowledgeCutoff
        self.totalAssets = totalAssets
        self.totalLiabilities = totalLiabilities
        self.netWorth = netWorth
    }
}
