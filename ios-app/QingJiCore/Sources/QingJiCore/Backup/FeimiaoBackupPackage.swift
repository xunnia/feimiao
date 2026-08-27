import Foundation

/// Android / iOS 之间交换本地账本的稳定格式。
///
/// 这里使用稳定 UUID 和分类 key，而不是平台数据库主键；两个平台可以各自
/// 使用原生存储实现，同时保持导入后的交易关系、退款归属和统计口径一致。
public struct FeimiaoBackupPackage: Codable, Equatable, Sendable {
    /// v7 additionally carries local audit/checkpoint records; v9 carries AI
    /// run history and report schedules. Credentials remain excluded from every
    /// backup version.
    public static let currentSchemaVersion = 9

    public var schemaVersion: Int
    public var exportedAt: Date
    public var books: [BackupBook]
    public var accounts: [BackupAccount]
    public var categories: [BackupCategory]
    public var tags: [BackupTag]
    public var transactions: [BackupTransaction]
    public var budgets: [BackupBudget]
    public var savingsGoals: [BackupSavingsGoal]
    public var recurringRules: [BackupRecurringRule]
    public var recurringOccurrences: [BackupRecurringOccurrence]
    public var physicalAssets: [BackupPhysicalAsset]
    public var assetEvents: [BackupAssetEvent]
    public var assetUsageEvents: [BackupAssetUsageEvent]
    public var assetTransactionLinks: [BackupAssetTransactionLink]
    public var assetRefundAllocations: [BackupAssetRefundAllocation]
    public var assetValuations: [BackupAssetValuation]
    public var receivableAssets: [BackupReceivableAsset]
    public var receivableRecoveries: [BackupReceivableRecovery]
    public var liabilities: [BackupLiabilityProfile]
    public var netWorthSnapshots: [BackupNetWorthSnapshot]
    public var aiChatSessions: [BackupAIChatSession]
    public var aiChatMessages: [BackupAIChatMessage]
    public var aiMemories: [BackupAIMemory]
    public var aiRequestRuns: [BackupAIRequestRun]
    public var aiRequestEvents: [BackupAIRequestEvent]
    public var aiReportSchedules: [BackupAIReportSchedule]
    public var budgetPlansV2: [BackupBudgetPlanV2]
    public var budgetPlanRevisionsV2: [BackupBudgetPlanRevisionV2]
    public var budgetCycleOverridesV2: [BackupBudgetCycleOverrideV2]
    public var budgetCommitmentOccurrencesV2: [BackupBudgetCommitmentOccurrenceV2]
    public var budgetChangeEventsV2: [BackupBudgetChangeEventV2]
    public var reports: [BackupReport]
    public var accountBalanceCheckpoints: [BackupAccountBalanceCheckpoint]
    public var netWorthVerifiedCheckpoints: [BackupNetWorthVerifiedCheckpoint]
    public var netWorthVerifiedItems: [BackupNetWorthVerifiedCheckpointItem]

    public init(
        schemaVersion: Int = FeimiaoBackupPackage.currentSchemaVersion,
        exportedAt: Date = .now,
        books: [BackupBook] = [],
        accounts: [BackupAccount] = [],
        categories: [BackupCategory] = [],
        tags: [BackupTag] = [],
        transactions: [BackupTransaction] = [],
        budgets: [BackupBudget] = [],
        savingsGoals: [BackupSavingsGoal] = [],
        recurringRules: [BackupRecurringRule] = [],
        recurringOccurrences: [BackupRecurringOccurrence] = [],
        physicalAssets: [BackupPhysicalAsset] = [],
        assetEvents: [BackupAssetEvent] = [],
        assetUsageEvents: [BackupAssetUsageEvent] = [],
        assetTransactionLinks: [BackupAssetTransactionLink] = [],
        assetRefundAllocations: [BackupAssetRefundAllocation] = [],
        assetValuations: [BackupAssetValuation] = [],
        receivableAssets: [BackupReceivableAsset] = [],
        receivableRecoveries: [BackupReceivableRecovery] = [],
        liabilities: [BackupLiabilityProfile] = [],
        netWorthSnapshots: [BackupNetWorthSnapshot] = [],
        aiChatSessions: [BackupAIChatSession] = [],
        aiChatMessages: [BackupAIChatMessage] = [],
        aiMemories: [BackupAIMemory] = [],
        aiRequestRuns: [BackupAIRequestRun] = [],
        aiRequestEvents: [BackupAIRequestEvent] = [],
        aiReportSchedules: [BackupAIReportSchedule] = [],
        budgetPlansV2: [BackupBudgetPlanV2] = [],
        budgetPlanRevisionsV2: [BackupBudgetPlanRevisionV2] = [],
        budgetCycleOverridesV2: [BackupBudgetCycleOverrideV2] = [],
        budgetCommitmentOccurrencesV2: [BackupBudgetCommitmentOccurrenceV2] = [],
        budgetChangeEventsV2: [BackupBudgetChangeEventV2] = [],
        reports: [BackupReport] = [],
        accountBalanceCheckpoints: [BackupAccountBalanceCheckpoint] = [],
        netWorthVerifiedCheckpoints: [BackupNetWorthVerifiedCheckpoint] = [],
        netWorthVerifiedItems: [BackupNetWorthVerifiedCheckpointItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.books = books
        self.accounts = accounts
        self.categories = categories
        self.tags = tags
        self.transactions = transactions
        self.budgets = budgets
        self.savingsGoals = savingsGoals
        self.recurringRules = recurringRules
        self.recurringOccurrences = recurringOccurrences
        self.physicalAssets = physicalAssets
        self.assetEvents = assetEvents
        self.assetUsageEvents = assetUsageEvents
        self.assetTransactionLinks = assetTransactionLinks
        self.assetRefundAllocations = assetRefundAllocations
        self.assetValuations = assetValuations
        self.receivableAssets = receivableAssets
        self.receivableRecoveries = receivableRecoveries
        self.liabilities = liabilities
        self.netWorthSnapshots = netWorthSnapshots
        self.aiChatSessions = aiChatSessions
        self.aiChatMessages = aiChatMessages
        self.aiMemories = aiMemories
        self.aiRequestRuns = aiRequestRuns
        self.aiRequestEvents = aiRequestEvents
        self.aiReportSchedules = aiReportSchedules
        self.budgetPlansV2 = budgetPlansV2
        self.budgetPlanRevisionsV2 = budgetPlanRevisionsV2
        self.budgetCycleOverridesV2 = budgetCycleOverridesV2
        self.budgetCommitmentOccurrencesV2 = budgetCommitmentOccurrencesV2
        self.budgetChangeEventsV2 = budgetChangeEventsV2
        self.reports = reports
        self.accountBalanceCheckpoints = accountBalanceCheckpoints
        self.netWorthVerifiedCheckpoints = netWorthVerifiedCheckpoints
        self.netWorthVerifiedItems = netWorthVerifiedItems
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, books, accounts, categories, tags, transactions, budgets
        case savingsGoals, recurringRules, recurringOccurrences, physicalAssets
        case assetEvents, assetUsageEvents, assetTransactionLinks, assetRefundAllocations, assetValuations, receivableAssets, receivableRecoveries
        case liabilities, netWorthSnapshots, aiChatSessions, aiChatMessages
        case aiMemories, aiRequestRuns, aiRequestEvents, aiReportSchedules
        case budgetPlansV2, budgetPlanRevisionsV2, budgetCycleOverridesV2
        case budgetCommitmentOccurrencesV2, budgetChangeEventsV2
        case reports, accountBalanceCheckpoints, netWorthVerifiedCheckpoints, netWorthVerifiedItems
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .now
        books = try container.decodeIfPresent([BackupBook].self, forKey: .books) ?? []
        accounts = try container.decodeIfPresent([BackupAccount].self, forKey: .accounts) ?? []
        categories = try container.decodeIfPresent([BackupCategory].self, forKey: .categories) ?? []
        tags = try container.decodeIfPresent([BackupTag].self, forKey: .tags) ?? []
        transactions = try container.decodeIfPresent([BackupTransaction].self, forKey: .transactions) ?? []
        budgets = try container.decodeIfPresent([BackupBudget].self, forKey: .budgets) ?? []
        savingsGoals = try container.decodeIfPresent([BackupSavingsGoal].self, forKey: .savingsGoals) ?? []
        recurringRules = try container.decodeIfPresent([BackupRecurringRule].self, forKey: .recurringRules) ?? []
        recurringOccurrences = try container.decodeIfPresent([BackupRecurringOccurrence].self, forKey: .recurringOccurrences) ?? []
        physicalAssets = try container.decodeIfPresent([BackupPhysicalAsset].self, forKey: .physicalAssets) ?? []
        assetEvents = try container.decodeIfPresent([BackupAssetEvent].self, forKey: .assetEvents) ?? []
        assetUsageEvents = try container.decodeIfPresent([BackupAssetUsageEvent].self, forKey: .assetUsageEvents) ?? []
        assetTransactionLinks = try container.decodeIfPresent([BackupAssetTransactionLink].self, forKey: .assetTransactionLinks) ?? []
        assetRefundAllocations = try container.decodeIfPresent([BackupAssetRefundAllocation].self, forKey: .assetRefundAllocations) ?? []
        assetValuations = try container.decodeIfPresent([BackupAssetValuation].self, forKey: .assetValuations) ?? []
        receivableAssets = try container.decodeIfPresent([BackupReceivableAsset].self, forKey: .receivableAssets) ?? []
        receivableRecoveries = try container.decodeIfPresent([BackupReceivableRecovery].self, forKey: .receivableRecoveries) ?? []
        liabilities = try container.decodeIfPresent([BackupLiabilityProfile].self, forKey: .liabilities) ?? []
        netWorthSnapshots = try container.decodeIfPresent([BackupNetWorthSnapshot].self, forKey: .netWorthSnapshots) ?? []
        aiChatSessions = try container.decodeIfPresent([BackupAIChatSession].self, forKey: .aiChatSessions) ?? []
        aiChatMessages = try container.decodeIfPresent([BackupAIChatMessage].self, forKey: .aiChatMessages) ?? []
        aiMemories = try container.decodeIfPresent([BackupAIMemory].self, forKey: .aiMemories) ?? []
        aiRequestRuns = try container.decodeIfPresent([BackupAIRequestRun].self, forKey: .aiRequestRuns) ?? []
        aiRequestEvents = try container.decodeIfPresent([BackupAIRequestEvent].self, forKey: .aiRequestEvents) ?? []
        aiReportSchedules = try container.decodeIfPresent([BackupAIReportSchedule].self, forKey: .aiReportSchedules) ?? []
        budgetPlansV2 = try container.decodeIfPresent([BackupBudgetPlanV2].self, forKey: .budgetPlansV2) ?? []
        budgetPlanRevisionsV2 = try container.decodeIfPresent([BackupBudgetPlanRevisionV2].self, forKey: .budgetPlanRevisionsV2) ?? []
        budgetCycleOverridesV2 = try container.decodeIfPresent([BackupBudgetCycleOverrideV2].self, forKey: .budgetCycleOverridesV2) ?? []
        budgetCommitmentOccurrencesV2 = try container.decodeIfPresent([BackupBudgetCommitmentOccurrenceV2].self, forKey: .budgetCommitmentOccurrencesV2) ?? []
        budgetChangeEventsV2 = try container.decodeIfPresent([BackupBudgetChangeEventV2].self, forKey: .budgetChangeEventsV2) ?? []
        reports = try container.decodeIfPresent([BackupReport].self, forKey: .reports) ?? []
        accountBalanceCheckpoints = try container.decodeIfPresent([BackupAccountBalanceCheckpoint].self, forKey: .accountBalanceCheckpoints) ?? []
        netWorthVerifiedCheckpoints = try container.decodeIfPresent([BackupNetWorthVerifiedCheckpoint].self, forKey: .netWorthVerifiedCheckpoints) ?? []
        netWorthVerifiedItems = try container.decodeIfPresent([BackupNetWorthVerifiedCheckpointItem].self, forKey: .netWorthVerifiedItems) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(books, forKey: .books)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(categories, forKey: .categories)
        try container.encode(tags, forKey: .tags)
        try container.encode(transactions, forKey: .transactions)
        try container.encode(budgets, forKey: .budgets)
        try container.encode(savingsGoals, forKey: .savingsGoals)
        try container.encode(recurringRules, forKey: .recurringRules)
        try container.encode(recurringOccurrences, forKey: .recurringOccurrences)
        try container.encode(physicalAssets, forKey: .physicalAssets)
        try container.encode(assetEvents, forKey: .assetEvents)
        try container.encode(assetUsageEvents, forKey: .assetUsageEvents)
        try container.encode(assetTransactionLinks, forKey: .assetTransactionLinks)
        try container.encode(assetRefundAllocations, forKey: .assetRefundAllocations)
        try container.encode(assetValuations, forKey: .assetValuations)
        try container.encode(receivableAssets, forKey: .receivableAssets)
        try container.encode(receivableRecoveries, forKey: .receivableRecoveries)
        try container.encode(liabilities, forKey: .liabilities)
        try container.encode(netWorthSnapshots, forKey: .netWorthSnapshots)
        try container.encode(aiChatSessions, forKey: .aiChatSessions)
        try container.encode(aiChatMessages, forKey: .aiChatMessages)
        try container.encode(aiMemories, forKey: .aiMemories)
        try container.encode(aiRequestRuns, forKey: .aiRequestRuns)
        try container.encode(aiRequestEvents, forKey: .aiRequestEvents)
        try container.encode(aiReportSchedules, forKey: .aiReportSchedules)
        try container.encode(budgetPlansV2, forKey: .budgetPlansV2)
        try container.encode(budgetPlanRevisionsV2, forKey: .budgetPlanRevisionsV2)
        try container.encode(budgetCycleOverridesV2, forKey: .budgetCycleOverridesV2)
        try container.encode(budgetCommitmentOccurrencesV2, forKey: .budgetCommitmentOccurrencesV2)
        try container.encode(budgetChangeEventsV2, forKey: .budgetChangeEventsV2)
        try container.encode(reports, forKey: .reports)
        try container.encode(accountBalanceCheckpoints, forKey: .accountBalanceCheckpoints)
        try container.encode(netWorthVerifiedCheckpoints, forKey: .netWorthVerifiedCheckpoints)
        try container.encode(netWorthVerifiedItems, forKey: .netWorthVerifiedItems)
    }
}

public struct BackupTag: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var colorValue: Int
    public var sortOrder: Int
    public var updatedAt: Date?

    public init(
        id: UUID,
        name: String,
        colorValue: Int = 0x7D8B9B,
        sortOrder: Int = 0,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorValue = colorValue
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}

public struct BackupBook: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var cover: String?
    public var remark: String
    public var sortOrder: Int
    public var isStarred: Bool
    public var includeInTotal: Bool
    public var isDefault: Bool
    public var updatedAt: Date?

    public init(
        id: UUID,
        name: String,
        cover: String? = nil,
        remark: String = "",
        sortOrder: Int = 0,
        isStarred: Bool = false,
        includeInTotal: Bool = true,
        isDefault: Bool = false,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.cover = cover
        self.remark = remark
        self.sortOrder = sortOrder
        self.isStarred = isStarred
        self.includeInTotal = includeInTotal
        self.isDefault = isDefault
        self.updatedAt = updatedAt
    }
}

public struct BackupAccount: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AccountKind
    public var currencyCode: String
    public var initialBalance: Decimal
    public var sortOrder: Int
    public var institution: String?
    public var includeInNetWorth: Bool?
    public var isDeleted: Bool?
    public var status: AccountStatus?
    public var archivedAt: Date?
    public var lastVerifiedAt: Date?
    public var openingBalanceEffectiveAt: Date?
    public var openingBalanceQuality: AccountOpeningBalanceQuality?
    public var balanceMode: LiabilityBalanceMode?
    public var creditStatementDay: Int?
    public var creditPaymentDay: Int?
    public var creditLimit: Decimal?
    public var updatedAt: Date?

    public init(
        id: UUID,
        name: String,
        kind: AccountKind,
        currencyCode: String = "CNY",
        initialBalance: Decimal = 0,
        sortOrder: Int = 0,
        institution: String? = nil,
        includeInNetWorth: Bool? = nil,
        isDeleted: Bool? = nil,
        status: AccountStatus? = nil,
        archivedAt: Date? = nil,
        lastVerifiedAt: Date? = nil,
        openingBalanceEffectiveAt: Date? = nil,
        openingBalanceQuality: AccountOpeningBalanceQuality? = nil,
        balanceMode: LiabilityBalanceMode? = nil,
        creditStatementDay: Int? = nil,
        creditPaymentDay: Int? = nil,
        creditLimit: Decimal? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.currencyCode = currencyCode
        self.initialBalance = initialBalance
        self.sortOrder = sortOrder
        self.institution = institution
        self.includeInNetWorth = includeInNetWorth
        self.isDeleted = isDeleted
        self.status = status
        self.archivedAt = archivedAt
        self.lastVerifiedAt = lastVerifiedAt
        self.openingBalanceEffectiveAt = openingBalanceEffectiveAt
        self.openingBalanceQuality = openingBalanceQuality
        self.balanceMode = balanceMode
        self.creditStatementDay = creditStatementDay
        self.creditPaymentDay = creditPaymentDay
        self.creditLimit = creditLimit
        self.updatedAt = updatedAt
    }
}

public struct BackupCategory: Codable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var symbol: String
    public var emoji: String
    public var kind: TransactionKind
    public var parentKey: String?
    public var sortOrder: Int
    public var isArchived: Bool

    public init(
        key: String,
        name: String,
        symbol: String,
        emoji: String = "🏷️",
        kind: TransactionKind,
        parentKey: String? = nil,
        sortOrder: Int = 0,
        isArchived: Bool = false
    ) {
        self.key = key
        self.name = name
        self.symbol = symbol
        self.emoji = emoji
        self.kind = kind
        self.parentKey = parentKey
        self.sortOrder = sortOrder
        self.isArchived = isArchived
    }
}

public struct BackupTransaction: Codable, Equatable, Sendable {
    public var id: UUID
    public var amount: Decimal
    public var kind: TransactionKind
    public var date: Date
    public var note: String
    public var merchant: String?
    public var product: String?
    public var currencyCode: String
    public var categoryKey: String?
    public var accountID: UUID?
    public var toAccountID: UUID?
    public var bookID: UUID?
    public var refundOfID: UUID?
    public var isReimbursed: Bool
    public var isExcluded: Bool
    public var tags: [String]
    public var categoryName: String?
    public var topCategoryKey: String?
    public var topCategoryName: String?
    public var timePrecision: TransactionTimePrecision?
    public var createdAt: Date?
    public var settledAt: Date?
    public var settlementQuality: SettlementQuality?
    public var settlementAccountID: UUID?
    public var settlementAccountQuality: SettlementQuality?
    public var eventType: TransactionEventType?
    public var reimbursable: Bool?
    public var attachmentPath: String?
    public var orderNo: String?
    public var recurringRuleID: UUID?
    public var updatedAt: Date?

    public init(
        id: UUID,
        amount: Decimal,
        kind: TransactionKind,
        date: Date,
        note: String = "",
        merchant: String? = nil,
        product: String? = nil,
        currencyCode: String = "CNY",
        categoryKey: String? = nil,
        accountID: UUID? = nil,
        toAccountID: UUID? = nil,
        bookID: UUID? = nil,
        refundOfID: UUID? = nil,
        isReimbursed: Bool = false,
        isExcluded: Bool = false,
        tags: [String] = [],
        categoryName: String? = nil,
        topCategoryKey: String? = nil,
        topCategoryName: String? = nil,
        timePrecision: TransactionTimePrecision? = nil,
        createdAt: Date? = nil,
        settledAt: Date? = nil,
        settlementQuality: SettlementQuality? = nil,
        settlementAccountID: UUID? = nil,
        settlementAccountQuality: SettlementQuality? = nil,
        eventType: TransactionEventType? = nil,
        reimbursable: Bool? = nil,
        attachmentPath: String? = nil,
        orderNo: String? = nil,
        recurringRuleID: UUID? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.amount = amount
        self.kind = kind
        self.date = date
        self.note = note
        self.merchant = merchant
        self.product = product
        self.currencyCode = currencyCode
        self.categoryKey = categoryKey
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.bookID = bookID
        self.refundOfID = refundOfID
        self.isReimbursed = isReimbursed
        self.isExcluded = isExcluded
        self.tags = tags
        self.categoryName = categoryName
        self.topCategoryKey = topCategoryKey
        self.topCategoryName = topCategoryName
        self.timePrecision = timePrecision
        self.createdAt = createdAt
        self.settledAt = settledAt
        self.settlementQuality = settlementQuality
        self.settlementAccountID = settlementAccountID
        self.settlementAccountQuality = settlementAccountQuality
        self.eventType = eventType
        self.reimbursable = reimbursable
        self.attachmentPath = attachmentPath
        self.orderNo = orderNo
        self.recurringRuleID = recurringRuleID
        self.updatedAt = updatedAt
    }
}

public struct BackupBudget: Codable, Equatable, Sendable {
    public var id: UUID
    public var amount: Decimal
    public var categoryKey: String?
    public var bookID: UUID?
    public var periodStart: Date?
    public var periodEnd: Date?
    public var cycleRaw: String?
    public var isActive: Bool?
    public var updatedAt: Date?

    public init(
        id: UUID,
        amount: Decimal,
        categoryKey: String? = nil,
        bookID: UUID? = nil,
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        cycleRaw: String? = nil,
        isActive: Bool? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.amount = amount
        self.categoryKey = categoryKey
        self.bookID = bookID
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.cycleRaw = cycleRaw
        self.isActive = isActive
        self.updatedAt = updatedAt
    }
}
