import Foundation

public struct BackupAIChatSession: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isStarred: Bool
    public var isRecord: Bool
    public var providerID: UUID?
    public var model: String
    public var effortRaw: String

    public init(id: UUID, title: String = "新对话", createdAt: Date, updatedAt: Date,
                isStarred: Bool = false, isRecord: Bool = false, providerID: UUID? = nil,
                model: String = "", effortRaw: String = "low") {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isStarred = isStarred
        self.isRecord = isRecord
        self.providerID = providerID
        self.model = model
        self.effortRaw = effortRaw
    }
}

public struct BackupAIChatMessage: Codable, Equatable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var role: String
    public var content: String
    public var createdAt: Date
    public var reasoningSummary: String
    public var sourceJSON: String
    public var attachmentsJSON: String?
    public var recordJSON: String?
    public var isError: Bool

    public init(id: UUID, sessionID: UUID, role: String, content: String,
                createdAt: Date, reasoningSummary: String = "", sourceJSON: String = "",
                attachmentsJSON: String? = nil, recordJSON: String? = nil, isError: Bool = false) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.reasoningSummary = reasoningSummary
        self.sourceJSON = sourceJSON
        self.attachmentsJSON = attachmentsJSON
        self.recordJSON = recordJSON
        self.isError = isError
    }
}

public struct BackupAIMemory: Codable, Equatable, Sendable {
    public var id: UUID
    public var phrase: String
    public var content: String
    public var source: String
    public var sessionID: UUID?
    public var consent: Bool
    public var statusRaw: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?

    public init(
        id: UUID,
        phrase: String,
        content: String,
        source: String = "user",
        sessionID: UUID? = nil,
        consent: Bool = false,
        statusRaw: String = "active",
        createdAt: Date,
        updatedAt: Date,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.phrase = phrase
        self.content = content
        self.source = source
        self.sessionID = sessionID
        self.consent = consent
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }
}

/// v3 backup records for the R1/R2 domains. Raw strings are intentional here:
/// the app-specific SwiftData enums can evolve without making the transport
/// package depend on SwiftUI or the persistence layer.

public struct BackupSavingsGoal: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var targetAmount: Decimal
    public var savedAmount: Decimal
    public var currencyCode: String
    public var linkedAssetID: UUID?
    public var note: String
    public var isArchived: Bool
    public var updatedAt: Date?

    public init(id: UUID, name: String, emoji: String = "🐷", targetAmount: Decimal, savedAmount: Decimal = 0, currencyCode: String = "CNY", linkedAssetID: UUID? = nil, note: String = "", isArchived: Bool = false, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.currencyCode = currencyCode
        self.linkedAssetID = linkedAssetID
        self.note = note
        self.isArchived = isArchived
        self.updatedAt = updatedAt
    }
}

public struct BackupRecurringRule: Codable, Equatable, Sendable {
    public var id: UUID
    public var bookID: UUID?
    public var kind: TransactionKind
    public var amount: Decimal
    public var categoryKey: String?
    public var accountID: UUID?
    public var toAccountID: UUID?
    public var note: String
    public var periodRaw: String
    public var startDate: Date
    public var nextDueDate: Date
    public var endDate: Date?
    public var totalCount: Int?
    public var generatedCount: Int
    public var anchorDay: Int
    public var isEnabled: Bool
    public var updatedAt: Date?

    public init(id: UUID, bookID: UUID? = nil, kind: TransactionKind, amount: Decimal, categoryKey: String? = nil, accountID: UUID? = nil, toAccountID: UUID? = nil, note: String = "", periodRaw: String = "monthly", startDate: Date, nextDueDate: Date, endDate: Date? = nil, totalCount: Int? = nil, generatedCount: Int = 0, anchorDay: Int = 0, isEnabled: Bool = true, updatedAt: Date? = nil) {
        self.id = id
        self.bookID = bookID
        self.kind = kind
        self.amount = amount
        self.categoryKey = categoryKey
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.note = note
        self.periodRaw = periodRaw
        self.startDate = startDate
        self.nextDueDate = nextDueDate
        self.endDate = endDate
        self.totalCount = totalCount
        self.generatedCount = generatedCount
        self.anchorDay = anchorDay
        self.isEnabled = isEnabled
        self.updatedAt = updatedAt
    }
}

public struct BackupRecurringOccurrence: Codable, Equatable, Sendable {
    public var id: UUID
    public var ruleID: UUID
    public var dueDate: Date
    public var transactionID: UUID?
    public var createdAt: Date?

    public init(id: UUID, ruleID: UUID, dueDate: Date, transactionID: UUID? = nil, createdAt: Date? = nil) {
        self.id = id
        self.ruleID = ruleID
        self.dueDate = dueDate
        self.transactionID = transactionID
        self.createdAt = createdAt
    }
}

public struct BackupPhysicalAsset: Codable, Equatable, Sendable {
    public var id: UUID
    public var bookID: UUID?
    public var name: String
    public var kindRaw: String
    public var lifecycleRaw: String
    /// Android keeps these newer asset state dimensions separately. Optional
    /// transport fields keep older canonical backups readable.
    public var economicStatusRaw: String?
    public var usageStatusRaw: String?
    public var visibilityStatusRaw: String?
    public var inclusionQualityRaw: String?
    public var sourceTypeRaw: String?
    public var acquisitionCostSourceRaw: String?
    public var purchasePrice: Decimal
    public var currentValue: Decimal
    public var currencyCode: String
    public var purchaseDate: Date?
    public var brand: String
    public var model: String
    public var location: String
    public var warrantyUntil: Date?
    public var usageTrackingEnabled: Bool
    public var usageCount: Int
    public var savingsGoalID: UUID?
    public var photoPath: String
    public var thumbnailPath: String
    public var invoicePath: String
    public var depreciationMethod: String
    public var depreciationBase: Decimal
    public var salvageValue: Decimal
    public var usefulLifeMonths: Int
    public var depreciationStartDate: Date?
    public var depreciationPaused: Bool
    public var note: String
    public var includeInNetWorth: Bool
    public var isDeleted: Bool
    public var endedAt: Date?
    public var archivedAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: UUID, bookID: UUID? = nil, name: String, kindRaw: String = "other", lifecycleRaw: String = "owned", economicStatusRaw: String? = nil, usageStatusRaw: String? = nil, visibilityStatusRaw: String? = nil, inclusionQualityRaw: String? = nil, sourceTypeRaw: String? = nil, acquisitionCostSourceRaw: String? = nil, purchasePrice: Decimal = 0, currentValue: Decimal = 0, currencyCode: String = "CNY", purchaseDate: Date? = nil, brand: String = "", model: String = "", location: String = "", warrantyUntil: Date? = nil, usageTrackingEnabled: Bool = false, usageCount: Int = 0, savingsGoalID: UUID? = nil, photoPath: String = "", thumbnailPath: String = "", invoicePath: String = "", depreciationMethod: String = "", depreciationBase: Decimal = 0, salvageValue: Decimal = 0, usefulLifeMonths: Int = 0, depreciationStartDate: Date? = nil, depreciationPaused: Bool = false, note: String = "", includeInNetWorth: Bool = true, isDeleted: Bool = false, endedAt: Date? = nil, archivedAt: Date? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.kindRaw = kindRaw
        self.lifecycleRaw = lifecycleRaw
        self.economicStatusRaw = economicStatusRaw
        self.usageStatusRaw = usageStatusRaw
        self.visibilityStatusRaw = visibilityStatusRaw
        self.inclusionQualityRaw = inclusionQualityRaw
        self.sourceTypeRaw = sourceTypeRaw
        self.acquisitionCostSourceRaw = acquisitionCostSourceRaw
        self.purchasePrice = purchasePrice
        self.currentValue = currentValue
        self.currencyCode = currencyCode
        self.purchaseDate = purchaseDate
        self.brand = brand
        self.model = model
        self.location = location
        self.warrantyUntil = warrantyUntil
        self.usageTrackingEnabled = usageTrackingEnabled
        self.usageCount = usageCount
        self.savingsGoalID = savingsGoalID
        self.photoPath = photoPath
        self.thumbnailPath = thumbnailPath
        self.invoicePath = invoicePath
        self.depreciationMethod = depreciationMethod
        self.depreciationBase = depreciationBase
        self.salvageValue = salvageValue
        self.usefulLifeMonths = usefulLifeMonths
        self.depreciationStartDate = depreciationStartDate
        self.depreciationPaused = depreciationPaused
        self.note = note
        self.includeInNetWorth = includeInNetWorth
        self.isDeleted = isDeleted
        self.endedAt = endedAt
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupAssetEvent: Codable, Equatable, Sendable {
    public var id: UUID
    public var assetID: UUID
    public var kindRaw: String
    public var occurredAt: Date
    public var value: Decimal?
    public var note: String
    public var metadataJSON: String
    public var createdAt: Date?

    public init(id: UUID, assetID: UUID, kindRaw: String, occurredAt: Date, value: Decimal? = nil, note: String = "", metadataJSON: String = "", createdAt: Date? = nil) {
        self.id = id
        self.assetID = assetID
        self.kindRaw = kindRaw
        self.occurredAt = occurredAt
        self.value = value
        self.note = note
        self.metadataJSON = metadataJSON
        self.createdAt = createdAt
    }
}

public struct BackupAssetUsageEvent: Codable, Equatable, Sendable {
    public var id: UUID
    public var assetID: UUID
    public var countDelta: Int
    public var reversalOfID: UUID?
    public var occurredAt: Date
    public var note: String
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: UUID,
        assetID: UUID,
        countDelta: Int,
        reversalOfID: UUID? = nil,
        occurredAt: Date,
        note: String = "",
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.assetID = assetID
        self.countDelta = countDelta
        self.reversalOfID = reversalOfID
        self.occurredAt = occurredAt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupAssetTransactionLink: Codable, Equatable, Sendable {
    public var id: UUID
    public var assetID: UUID
    public var assetObjectType: String
    public var transactionID: UUID
    public var linkTypeRaw: String
    public var amount: Decimal
    public var allocatedGrossCents: Int
    public var allocatedRefundCents: Int
    public var costQualityRaw: String
    public var note: String
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: UUID,
        assetID: UUID,
        assetObjectType: String = "physical",
        transactionID: UUID,
        linkTypeRaw: String,
        amount: Decimal = 0,
        allocatedGrossCents: Int = 0,
        allocatedRefundCents: Int = 0,
        costQualityRaw: String = "partial",
        note: String = "",
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.assetID = assetID
        self.assetObjectType = assetObjectType
        self.transactionID = transactionID
        self.linkTypeRaw = linkTypeRaw
        self.amount = amount
        self.allocatedGrossCents = allocatedGrossCents
        self.allocatedRefundCents = allocatedRefundCents
        self.costQualityRaw = costQualityRaw
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupAssetRefundAllocation: Codable, Equatable, Sendable {
    public var id: UUID
    public var assetTransactionLinkID: UUID
    public var refundTransactionID: UUID
    public var allocatedRefundCents: Int
    public var statusRaw: String
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: UUID,
        assetTransactionLinkID: UUID,
        refundTransactionID: UUID,
        allocatedRefundCents: Int,
        statusRaw: String = "active",
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.assetTransactionLinkID = assetTransactionLinkID
        self.refundTransactionID = refundTransactionID
        self.allocatedRefundCents = allocatedRefundCents
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupAssetValuation: Codable, Equatable, Sendable {
    public var id: UUID
    public var assetID: UUID
    public var value: Decimal
    public var sourceRaw: String
    public var valuedAt: Date
    public var note: String
    public var createdAt: Date?

    public init(id: UUID, assetID: UUID, value: Decimal, sourceRaw: String = "manual", valuedAt: Date, note: String = "", createdAt: Date? = nil) {
        self.id = id
        self.assetID = assetID
        self.value = value
        self.sourceRaw = sourceRaw
        self.valuedAt = valuedAt
        self.note = note
        self.createdAt = createdAt
    }
}

public struct BackupReceivableAsset: Codable, Equatable, Sendable {
    public var id: UUID
    public var bookID: UUID?
    public var name: String
    public var kindRaw: String
    public var lifecycleRaw: String
    public var economicStatusRaw: String?
    public var visibilityStatusRaw: String?
    public var inclusionQualityRaw: String?
    public var originalAmount: Decimal
    public var remainingAmount: Decimal
    public var currencyCode: String
    public var counterparty: String
    public var dueDate: Date?
    public var includeInNetWorth: Bool
    public var note: String
    public var isDeleted: Bool
    public var endedAt: Date?
    public var archivedAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: UUID, bookID: UUID? = nil, name: String, kindRaw: String = "other", lifecycleRaw: String = "active", economicStatusRaw: String? = nil, visibilityStatusRaw: String? = nil, inclusionQualityRaw: String? = nil, originalAmount: Decimal, remainingAmount: Decimal, currencyCode: String = "CNY", counterparty: String = "", dueDate: Date? = nil, includeInNetWorth: Bool = true, note: String = "", isDeleted: Bool = false, endedAt: Date? = nil, archivedAt: Date? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.kindRaw = kindRaw
        self.lifecycleRaw = lifecycleRaw
        self.economicStatusRaw = economicStatusRaw
        self.visibilityStatusRaw = visibilityStatusRaw
        self.inclusionQualityRaw = inclusionQualityRaw
        self.originalAmount = originalAmount
        self.remainingAmount = remainingAmount
        self.currencyCode = currencyCode
        self.counterparty = counterparty
        self.dueDate = dueDate
        self.includeInNetWorth = includeInNetWorth
        self.note = note
        self.isDeleted = isDeleted
        self.endedAt = endedAt
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupReceivableRecovery: Codable, Equatable, Sendable {
    public var id: UUID
    public var receivableID: UUID
    public var eventID: UUID?
    public var amount: Decimal
    public var recoveredAt: Date
    public var targetAccountID: UUID?
    public var transactionID: UUID?
    public var note: String
    public var createdAt: Date?

    public init(id: UUID, receivableID: UUID, amount: Decimal, recoveredAt: Date, targetAccountID: UUID? = nil, transactionID: UUID? = nil, eventID: UUID? = nil, note: String = "", createdAt: Date? = nil) {
        self.id = id
        self.receivableID = receivableID
        self.eventID = eventID
        self.amount = amount
        self.recoveredAt = recoveredAt
        self.targetAccountID = targetAccountID
        self.transactionID = transactionID
        self.note = note
        self.createdAt = createdAt
    }
}

public struct BackupLiabilityProfile: Codable, Equatable, Sendable {
    public var id: UUID
    public var accountID: UUID?
    public var repaymentAccountID: UUID?
    public var kindRaw: String
    public var lifecycleRaw: String
    public var originalPrincipal: Decimal
    public var currentPrincipal: Decimal
    public var currencyCode: String
    public var counterparty: String
    public var annualRate: Decimal?
    public var startDate: Date?
    public var dueDate: Date?
    public var statementDay: Int?
    public var paymentDay: Int?
    public var creditLimit: Decimal?
    public var note: String
    public var updatedAt: Date?

    public init(id: UUID, accountID: UUID? = nil, repaymentAccountID: UUID? = nil, kindRaw: String = "other", lifecycleRaw: String = "active", originalPrincipal: Decimal = 0, currentPrincipal: Decimal = 0, currencyCode: String = "CNY", counterparty: String = "", annualRate: Decimal? = nil, startDate: Date? = nil, dueDate: Date? = nil, statementDay: Int? = nil, paymentDay: Int? = nil, creditLimit: Decimal? = nil, note: String = "", updatedAt: Date? = nil) {
        self.id = id
        self.accountID = accountID
        self.repaymentAccountID = repaymentAccountID
        self.kindRaw = kindRaw
        self.lifecycleRaw = lifecycleRaw
        self.originalPrincipal = originalPrincipal
        self.currentPrincipal = currentPrincipal
        self.currencyCode = currencyCode
        self.counterparty = counterparty
        self.annualRate = annualRate
        self.startDate = startDate
        self.dueDate = dueDate
        self.statementDay = statementDay
        self.paymentDay = paymentDay
        self.creditLimit = creditLimit
        self.note = note
        self.updatedAt = updatedAt
    }
}

public struct BackupNetWorthSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var asOf: Date
    public var knowledgeCutoff: Date
    public var scopeKey: String
    public var scopeVersion: Int
    public var calculationVersion: Int
    public var baseCurrency: String
    public var coveredCurrenciesJSON: String
    public var uncoveredCurrenciesJSON: String
    public var qualityRaw: String
    public var cashAssets: Decimal
    public var investmentAssets: Decimal
    public var physicalAssets: Decimal
    public var receivableAssets: Decimal
    public var liabilities: Decimal
    public var reasonsJSON: String
    public var causesJSON: String
    public var provisional: Bool
    public var createdAt: Date?

    public init(id: UUID, asOf: Date, knowledgeCutoff: Date, scopeKey: String = "global", scopeVersion: Int = 1, calculationVersion: Int = 1, baseCurrency: String = "CNY", coveredCurrenciesJSON: String = "[\"CNY\"]", uncoveredCurrenciesJSON: String = "[]", qualityRaw: String = "legacy_unverified", cashAssets: Decimal = 0, investmentAssets: Decimal = 0, physicalAssets: Decimal = 0, receivableAssets: Decimal = 0, liabilities: Decimal = 0, reasonsJSON: String = "[]", causesJSON: String = "[]", provisional: Bool = false, createdAt: Date? = nil) {
        self.id = id
        self.asOf = asOf
        self.knowledgeCutoff = knowledgeCutoff
        self.scopeKey = scopeKey
        self.scopeVersion = scopeVersion
        self.calculationVersion = calculationVersion
        self.baseCurrency = baseCurrency
        self.coveredCurrenciesJSON = coveredCurrenciesJSON
        self.uncoveredCurrenciesJSON = uncoveredCurrenciesJSON
        self.qualityRaw = qualityRaw
        self.cashAssets = cashAssets
        self.investmentAssets = investmentAssets
        self.physicalAssets = physicalAssets
        self.receivableAssets = receivableAssets
        self.liabilities = liabilities
        self.reasonsJSON = reasonsJSON
        self.causesJSON = causesJSON
        self.provisional = provisional
        self.createdAt = createdAt
    }
}
