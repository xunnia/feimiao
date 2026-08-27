import Foundation

public struct BackupAccountBalanceCheckpoint: Codable, Equatable, Sendable {
    public var id: UUID
    public var accountID: UUID
    public var eventKindRaw: String
    public var effectiveAt: Date
    public var sequence: Int
    public var timezone: String
    public var knowledgeCutoff: Date
    public var targetBalance: Decimal
    public var calculatedBefore: Decimal
    public var deltaAtCreation: Decimal
    public var reason: String
    public var note: String
    public var status: String
    public var reversalOfID: UUID?
    public var coveredUnknownEventIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        accountID: UUID,
        eventKindRaw: String = "anchor",
        effectiveAt: Date,
        sequence: Int = 0,
        timezone: String = "device_local",
        knowledgeCutoff: Date,
        targetBalance: Decimal = 0,
        calculatedBefore: Decimal = 0,
        deltaAtCreation: Decimal = 0,
        reason: String = "manual",
        note: String = "",
        status: String = "active",
        reversalOfID: UUID? = nil,
        coveredUnknownEventIDs: [String] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.accountID = accountID
        self.eventKindRaw = eventKindRaw
        self.effectiveAt = effectiveAt
        self.sequence = sequence
        self.timezone = timezone
        self.knowledgeCutoff = knowledgeCutoff
        self.targetBalance = targetBalance
        self.calculatedBefore = calculatedBefore
        self.deltaAtCreation = deltaAtCreation
        self.reason = reason
        self.note = note
        self.status = status
        self.reversalOfID = reversalOfID
        self.coveredUnknownEventIDs = coveredUnknownEventIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupNetWorthVerifiedCheckpoint: Codable, Equatable, Sendable {
    public var id: UUID
    public var asOf: Date
    public var knowledgeCutoff: Date
    public var scopeVersion: Int
    public var calculationVersion: Int
    public var currencyCoverageJSON: String
    public var totalAssets: Decimal
    public var totalLiabilities: Decimal
    public var netWorth: Decimal
    public var completenessRaw: String
    public var reasonsJSON: String
    public var statusRaw: String
    public var supersedesID: UUID?
    public var createdAt: Date

    public init(
        id: UUID,
        asOf: Date,
        knowledgeCutoff: Date,
        scopeVersion: Int = 1,
        calculationVersion: Int = 1,
        currencyCoverageJSON: String = "",
        totalAssets: Decimal = 0,
        totalLiabilities: Decimal = 0,
        netWorth: Decimal = 0,
        completenessRaw: String = "partial",
        reasonsJSON: String = "",
        statusRaw: String = "active",
        supersedesID: UUID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.asOf = asOf
        self.knowledgeCutoff = knowledgeCutoff
        self.scopeVersion = scopeVersion
        self.calculationVersion = calculationVersion
        self.currencyCoverageJSON = currencyCoverageJSON
        self.totalAssets = totalAssets
        self.totalLiabilities = totalLiabilities
        self.netWorth = netWorth
        self.completenessRaw = completenessRaw
        self.reasonsJSON = reasonsJSON
        self.statusRaw = statusRaw
        self.supersedesID = supersedesID
        self.createdAt = createdAt
    }
}

public struct BackupNetWorthVerifiedCheckpointItem: Codable, Equatable, Sendable {
    public var checkpointID: UUID
    public var objectType: String
    public var objectUUID: String
    public var confirmedAmount: Decimal
    public var currencyCode: String
    public var valueEffectiveAt: Date
    public var valueSource: String
    public var quality: String

    public init(
        checkpointID: UUID,
        objectType: String,
        objectUUID: String,
        confirmedAmount: Decimal,
        currencyCode: String = "CNY",
        valueEffectiveAt: Date,
        valueSource: String = "unknown",
        quality: String = "partial"
    ) {
        self.checkpointID = checkpointID
        self.objectType = objectType
        self.objectUUID = objectUUID
        self.confirmedAmount = confirmedAmount
        self.currencyCode = currencyCode
        self.valueEffectiveAt = valueEffectiveAt
        self.valueSource = valueSource
        self.quality = quality
    }
}
