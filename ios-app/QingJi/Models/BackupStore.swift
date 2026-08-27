import Foundation
import CryptoKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import QingJiCore

/// 用于 iOS「文件」App、AirDrop 和跨平台迁移的完整备份文件。
struct BackupDocument: FileDocument {
    static let archiveContentType = UTType(filenameExtension: "zip") ?? .data
    static let readableContentTypes: [UTType] = [.json, archiveContentType, .data]

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupImportSummary: Equatable {
    let books: Int
    let accounts: Int
    let categories: Int
    let transactions: Int
    let budgets: Int
    let savingsGoals: Int
    let recurringRules: Int
    let physicalAssets: Int
    let receivableAssets: Int
    let liabilities: Int
    let aiChatSessions: Int
    let aiChatMessages: Int
    let aiMemories: Int
    let aiRequestRuns: Int
    let aiRequestEvents: Int
    let aiReportSchedules: Int
    let budgetPlansV2: Int
    let reports: Int
    let accountBalanceCheckpoints: Int
    let verifiedNetWorthCheckpoints: Int

    init(
        books: Int,
        accounts: Int,
        categories: Int,
        transactions: Int,
        budgets: Int,
        savingsGoals: Int = 0,
        recurringRules: Int = 0,
        physicalAssets: Int = 0,
        receivableAssets: Int = 0,
        liabilities: Int = 0,
        aiChatSessions: Int = 0,
        aiChatMessages: Int = 0,
        aiMemories: Int = 0,
        aiRequestRuns: Int = 0,
        aiRequestEvents: Int = 0,
        aiReportSchedules: Int = 0,
        budgetPlansV2: Int = 0,
        reports: Int = 0,
        accountBalanceCheckpoints: Int = 0,
        verifiedNetWorthCheckpoints: Int = 0
    ) {
        self.books = books
        self.accounts = accounts
        self.categories = categories
        self.transactions = transactions
        self.budgets = budgets
        self.savingsGoals = savingsGoals
        self.recurringRules = recurringRules
        self.physicalAssets = physicalAssets
        self.receivableAssets = receivableAssets
        self.liabilities = liabilities
        self.aiChatSessions = aiChatSessions
        self.aiChatMessages = aiChatMessages
        self.aiMemories = aiMemories
        self.aiRequestRuns = aiRequestRuns
        self.aiRequestEvents = aiRequestEvents
        self.aiReportSchedules = aiReportSchedules
        self.budgetPlansV2 = budgetPlansV2
        self.reports = reports
        self.accountBalanceCheckpoints = accountBalanceCheckpoints
        self.verifiedNetWorthCheckpoints = verifiedNetWorthCheckpoints
    }
}

enum BackupStoreError: LocalizedError {
    case unsupportedVersion(Int)
    case malformed
    case malformedArchive
    case unsupportedArchiveFormat
    case missingAttachment(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "备份版本 \(version) 高于当前版本，请先更新肥喵记账。"
        case .malformed: return "备份文件损坏或格式无法识别。"
        case .malformedArchive: return "备份 ZIP 损坏或校验清单无效。"
        case .unsupportedArchiveFormat: return "这个 ZIP 的备份格式不受当前版本支持。"
        case .missingAttachment(let path): return "备份附件不存在：\(path)"
        }
    }
}

/// 备份文件有两种明确语义：跨设备导入可以合并，用户在“恢复”页面
/// 选择的完整备份则必须替换当前数据库，和 Android 的恢复行为一致。
enum BackupImportMode: Equatable {
    case merge
    case replace
}

enum BackupStore {
    private static let archiveFormat = "feimiao-ios-backup"
    private static let archiveVersion = 1
    private static let archiveDatabasePath = "database/feimiao.json"
    private static let localBackupDirectoryName = "backups"

    static func localBackups() throws -> [URL] {
        let directory = try localBackupDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return files
            .filter { $0.pathExtension.lowercased() == "zip" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
    }

    /// 创建本机恢复点并只保留最近三份，供用户在 iOS 上获得与 Android
    /// 本机备份相同的可回退能力。
    @discardableResult
    static func createLocalBackup(context: ModelContext, now: Date = Date()) throws -> URL {
        let directory = try localBackupDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent("manual-\(formatter.string(from: now)).zip")
        try exportArchive(context: context).write(to: url, options: .atomic)

        let files = try localBackups()
        for stale in files.dropFirst(3) {
            try? FileManager.default.removeItem(at: stale)
        }
        return url
    }

    private static func localBackupDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(localBackupDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private struct ArchiveManifest: Codable {
        let format: String
        let version: Int
        let exportedAt: Date
        let schemaVersion: Int
        let database: String
        let checksums: [String: String]
        let contains: [String: Bool]
        let excludes: [String]
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func export(context: ModelContext) throws -> Data {
        let books = try context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.sortOrder)]))
        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
        let categories = try context.fetch(FetchDescriptor<TxCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        let tags = try context.fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.sortOrder)]))
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>(sortBy: [SortDescriptor(\.date, order: .forward)]))
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let savingsGoals = try context.fetch(FetchDescriptor<SavingsGoal>(sortBy: [SortDescriptor(\.updatedAt, order: .forward)]))
        let recurringRules = try context.fetch(FetchDescriptor<RecurringRule>(sortBy: [SortDescriptor(\.nextDueDate)]))
        let recurringOccurrences = try context.fetch(FetchDescriptor<RecurringOccurrence>(sortBy: [SortDescriptor(\.dueDate)]))
        let physicalAssets = try context.fetch(FetchDescriptor<PhysicalAsset>(sortBy: [SortDescriptor(\.updatedAt, order: .forward)]))
        let assetEvents = try context.fetch(FetchDescriptor<AssetEvent>(sortBy: [SortDescriptor(\.occurredAt)]))
        let assetUsageEvents = try context.fetch(FetchDescriptor<AssetUsageEvent>(sortBy: [SortDescriptor(\.occurredAt)]))
        let assetTransactionLinks = try context.fetch(FetchDescriptor<AssetTransactionLink>(sortBy: [SortDescriptor(\.createdAt)]))
        let assetRefundAllocations = try context.fetch(FetchDescriptor<AssetRefundAllocation>(sortBy: [SortDescriptor(\.createdAt)]))
        let assetValuations = try context.fetch(FetchDescriptor<AssetValuation>(sortBy: [SortDescriptor(\.valuedAt)]))
        let receivableAssets = try context.fetch(FetchDescriptor<ReceivableAsset>(sortBy: [SortDescriptor(\.updatedAt, order: .forward)]))
        let receivableRecoveries = try context.fetch(FetchDescriptor<ReceivableRecovery>(sortBy: [SortDescriptor(\.recoveredAt)]))
        let liabilities = try context.fetch(FetchDescriptor<LiabilityProfile>(sortBy: [SortDescriptor(\.updatedAt, order: .forward)]))
        let netWorthSnapshots = try context.fetch(FetchDescriptor<NetWorthSnapshot>(sortBy: [SortDescriptor(\.asOf)]))
        let aiChatSessions = try context.fetch(FetchDescriptor<AIChatSession>(sortBy: [SortDescriptor(\.updatedAt, order: .forward)]))
        let aiChatMessages = try context.fetch(FetchDescriptor<AIChatMessage>(sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
        let aiMemories = try context.fetch(FetchDescriptor<AIMemoryRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .forward)]))
        let aiRequestRuns = try context.fetch(FetchDescriptor<AIRequestRunRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .forward)]))
        let aiRequestEvents = try context.fetch(FetchDescriptor<AIRequestEventRecord>(sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
        let aiReportSchedules = try context.fetch(FetchDescriptor<AIReportScheduleRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .forward)]))
        let budgetPlansV2 = try context.fetch(FetchDescriptor<BudgetPlanRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .forward)]))
        let budgetPlanRevisionsV2 = try context.fetch(FetchDescriptor<BudgetPlanRevisionRecord>(sortBy: [SortDescriptor(\.effectiveCycleStart)]))
        let budgetCycleOverridesV2 = try context.fetch(FetchDescriptor<BudgetCycleOverrideRecord>(sortBy: [SortDescriptor(\.cycleStart)]))
        let budgetCommitmentOccurrencesV2 = try context.fetch(FetchDescriptor<BudgetCommitmentOccurrenceRecord>(sortBy: [SortDescriptor(\.dueDate)]))
        let budgetChangeEventsV2 = try context.fetch(FetchDescriptor<BudgetChangeEventRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        let reports = try context.fetch(FetchDescriptor<ReportRecord>(sortBy: [SortDescriptor(\.createdAt, order: .forward)]))
        let accountBalanceCheckpoints = try context.fetch(FetchDescriptor<AccountBalanceCheckpointRecord>(sortBy: [SortDescriptor(\.effectiveAt)]))
        let netWorthVerifiedCheckpoints = try context.fetch(FetchDescriptor<NetWorthVerifiedCheckpointRecord>(sortBy: [SortDescriptor(\.asOf)]))

        let package = FeimiaoBackupPackage(
            books: books.map {
                BackupBook(
                    id: $0.stableID,
                    name: $0.name,
                    cover: $0.cover,
                    remark: $0.remark,
                    sortOrder: $0.sortOrder,
                    isStarred: $0.isStarred,
                    includeInTotal: $0.includeInTotal,
                    isDefault: $0.isDefault,
                    updatedAt: $0.updatedAt
                )
            },
            accounts: accounts.map {
                BackupAccount(
                    id: $0.stableID,
                    name: $0.name,
                    kind: $0.kind,
                    currencyCode: $0.currencyCode,
                    initialBalance: $0.initialBalance,
                    sortOrder: $0.sortOrder,
                    institution: $0.institution,
                    includeInNetWorth: $0.includeInNetWorth,
                    isDeleted: $0.isDeleted,
                    status: $0.status,
                    archivedAt: $0.archivedAt,
                    lastVerifiedAt: $0.lastVerifiedAt,
                    openingBalanceEffectiveAt: $0.openingBalanceEffectiveAt,
                    openingBalanceQuality: $0.openingBalanceQuality,
                    balanceMode: $0.balanceMode,
                    creditStatementDay: $0.creditStatementDay,
                    creditPaymentDay: $0.creditPaymentDay,
                    creditLimit: $0.creditLimit,
                    updatedAt: $0.updatedAt
                )
            },
            categories: categories.map {
                BackupCategory(
                    key: $0.key,
                    name: $0.name,
                    symbol: $0.symbol,
                    emoji: $0.emoji,
                    kind: $0.kind,
                    parentKey: $0.parentKey,
                    sortOrder: $0.sortOrder,
                    isArchived: $0.isArchived
                )
            },
            tags: tags.map {
                BackupTag(
                    id: $0.stableID,
                    name: $0.name,
                    colorValue: $0.colorValue,
                    sortOrder: $0.sortOrder,
                    updatedAt: $0.updatedAt
                )
            },
            transactions: transactions.map {
                BackupTransaction(
                    id: $0.stableID,
                    amount: $0.amount,
                    kind: $0.kind,
                    date: $0.date,
                    note: $0.note,
                    merchant: $0.merchantName,
                    product: $0.productName,
                    currencyCode: $0.currencyCode,
                    categoryKey: $0.category?.key,
                    accountID: $0.account?.stableID,
                    toAccountID: $0.toAccount?.stableID,
                    bookID: $0.book?.stableID,
                    refundOfID: $0.refundOfID,
                    isReimbursed: $0.isReimbursed,
                    isExcluded: $0.isExcluded,
                    tags: $0.tags,
                    categoryName: $0.category?.name,
                    topCategoryKey: $0.category?.parentKey ?? $0.category?.key,
                    topCategoryName: $0.category?.parentKey == nil ? $0.category?.name : nil,
                    timePrecision: $0.timePrecision,
                    createdAt: $0.createdAt,
                    settledAt: $0.settledAt,
                    settlementQuality: $0.settlementQuality,
                    settlementAccountID: $0.settlementAccountID,
                    settlementAccountQuality: $0.settlementAccountQuality,
                    eventType: $0.eventType,
                    reimbursable: $0.reimbursable,
                    attachmentPath: $0.attachmentPath,
                    orderNo: $0.orderNo,
                    recurringRuleID: $0.recurringRuleID,
                    updatedAt: $0.updatedAt
                )
            },
            budgets: budgets.map {
                BackupBudget(
                    id: $0.stableID,
                    amount: $0.amount,
                    categoryKey: $0.categoryKey,
                    bookID: $0.bookID,
                    periodStart: $0.periodStart,
                    periodEnd: $0.periodEnd,
                    cycleRaw: $0.cycleRaw,
                    isActive: $0.isActive,
                    updatedAt: $0.updatedAt
                )
            },
            savingsGoals: savingsGoals.map {
                BackupSavingsGoal(
                    id: $0.stableID,
                    name: $0.name,
                    emoji: $0.emoji,
                    targetAmount: $0.targetAmount,
                    savedAmount: $0.savedAmount,
                    currencyCode: $0.currencyCode,
                    linkedAssetID: $0.linkedAssetID,
                    note: $0.note,
                    isArchived: $0.isArchived,
                    updatedAt: $0.updatedAt
                )
            },
            recurringRules: recurringRules.map {
                BackupRecurringRule(
                    id: $0.stableID,
                    bookID: $0.bookID,
                    kind: $0.kind,
                    amount: $0.amount,
                    categoryKey: $0.categoryKey,
                    accountID: $0.accountID,
                    toAccountID: $0.toAccountID,
                    note: $0.note,
                    periodRaw: $0.periodRaw,
                    startDate: $0.startDate,
                    nextDueDate: $0.nextDueDate,
                    endDate: $0.endDate,
                    totalCount: $0.totalCount,
                    generatedCount: $0.generatedCount,
                    anchorDay: $0.anchorDay,
                    isEnabled: $0.isEnabled,
                    updatedAt: $0.updatedAt
                )
            },
            recurringOccurrences: recurringOccurrences.map {
                BackupRecurringOccurrence(
                    id: $0.stableID,
                    ruleID: $0.ruleID,
                    dueDate: $0.dueDate,
                    transactionID: $0.transactionID,
                    createdAt: $0.createdAt
                )
            },
            physicalAssets: physicalAssets.map {
                BackupPhysicalAsset(
                    id: $0.stableID,
                    bookID: $0.bookID,
                    name: $0.name,
                    kindRaw: $0.kindRaw,
                    lifecycleRaw: $0.lifecycleRaw,
                    economicStatusRaw: $0.economicStatusRaw,
                    usageStatusRaw: $0.usageStatusRaw,
                    visibilityStatusRaw: $0.visibilityStatusRaw,
                    inclusionQualityRaw: $0.inclusionQualityRaw,
                    sourceTypeRaw: $0.sourceTypeRaw,
                    acquisitionCostSourceRaw: $0.acquisitionCostSourceRaw,
                    purchasePrice: $0.purchasePrice,
                    currentValue: $0.currentValue,
                    currencyCode: $0.currencyCode,
                    purchaseDate: $0.purchaseDate,
                    brand: $0.brand,
                    model: $0.model,
                    location: $0.location,
                    warrantyUntil: $0.warrantyUntil,
                    usageTrackingEnabled: $0.usageTrackingEnabled,
                    usageCount: $0.usageCount,
                    savingsGoalID: $0.savingsGoalID,
                    photoPath: $0.photoPath,
                    thumbnailPath: $0.thumbnailPath,
                    invoicePath: $0.invoicePath,
                    depreciationMethod: $0.depreciationMethod,
                    depreciationBase: $0.depreciationBase,
                    salvageValue: $0.salvageValue,
                    usefulLifeMonths: $0.usefulLifeMonths,
                    depreciationStartDate: $0.depreciationStartDate,
                    depreciationPaused: $0.depreciationPaused,
                    note: $0.note,
                    includeInNetWorth: $0.includeInNetWorth,
                    isDeleted: $0.isDeleted,
                    endedAt: $0.endedAt,
                    archivedAt: $0.archivedAt,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            assetEvents: assetEvents.map {
                BackupAssetEvent(
                    id: $0.stableID,
                    assetID: $0.assetID,
                    kindRaw: $0.kindRaw,
                    occurredAt: $0.occurredAt,
                    value: $0.value,
                    note: $0.note,
                    metadataJSON: $0.metadataJSON,
                    createdAt: $0.createdAt
                )
            },
            assetUsageEvents: assetUsageEvents.map {
                BackupAssetUsageEvent(
                    id: $0.stableID,
                    assetID: $0.assetID,
                    countDelta: $0.countDelta,
                    reversalOfID: $0.reversalOfID,
                    occurredAt: $0.occurredAt,
                    note: $0.note,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            assetTransactionLinks: assetTransactionLinks.map {
                BackupAssetTransactionLink(
                    id: $0.stableID,
                    assetID: $0.assetID,
                    assetObjectType: $0.assetObjectType,
                    transactionID: $0.transactionID,
                    linkTypeRaw: $0.linkTypeRaw,
                    amount: $0.amount,
                    allocatedGrossCents: $0.allocatedGrossCents,
                    allocatedRefundCents: $0.allocatedRefundCents,
                    costQualityRaw: $0.costQualityRaw,
                    note: $0.note,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            assetRefundAllocations: assetRefundAllocations.map {
                BackupAssetRefundAllocation(
                    id: $0.stableID,
                    assetTransactionLinkID: $0.assetTransactionLinkID,
                    refundTransactionID: $0.refundTransactionID,
                    allocatedRefundCents: $0.allocatedRefundCents,
                    statusRaw: $0.statusRaw,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            assetValuations: assetValuations.map {
                BackupAssetValuation(
                    id: $0.stableID,
                    assetID: $0.assetID,
                    value: $0.value,
                    sourceRaw: $0.sourceRaw,
                    valuedAt: $0.valuedAt,
                    note: $0.note,
                    createdAt: $0.createdAt
                )
            },
            receivableAssets: receivableAssets.map {
                BackupReceivableAsset(
                    id: $0.stableID,
                    bookID: $0.bookID,
                    name: $0.name,
                    kindRaw: $0.kindRaw,
                    lifecycleRaw: $0.lifecycleRaw,
                    economicStatusRaw: $0.economicStatusRaw,
                    visibilityStatusRaw: $0.visibilityStatusRaw,
                    inclusionQualityRaw: $0.inclusionQualityRaw,
                    originalAmount: $0.originalAmount,
                    remainingAmount: $0.remainingAmount,
                    currencyCode: $0.currencyCode,
                    counterparty: $0.counterparty,
                    dueDate: $0.dueDate,
                    includeInNetWorth: $0.includeInNetWorth,
                    note: $0.note,
                    isDeleted: $0.isDeleted,
                    endedAt: $0.endedAt,
                    archivedAt: $0.archivedAt,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            receivableRecoveries: receivableRecoveries.map {
                BackupReceivableRecovery(
                    id: $0.stableID,
                    receivableID: $0.receivableID,
                    amount: $0.amount,
                    recoveredAt: $0.recoveredAt,
                    targetAccountID: $0.targetAccountID,
                    transactionID: $0.transactionID,
                    note: $0.note,
                    createdAt: $0.createdAt
                )
            },
            liabilities: liabilities.map {
                BackupLiabilityProfile(
                    id: $0.stableID,
                    accountID: $0.accountID,
                    repaymentAccountID: $0.repaymentAccountID,
                    kindRaw: $0.kindRaw,
                    lifecycleRaw: $0.lifecycleRaw,
                    originalPrincipal: $0.originalPrincipal,
                    currentPrincipal: $0.currentPrincipal,
                    currencyCode: $0.currencyCode,
                    counterparty: $0.counterparty,
                    annualRate: $0.annualRate,
                    startDate: $0.startDate,
                    dueDate: $0.dueDate,
                    statementDay: $0.statementDay,
                    paymentDay: $0.paymentDay,
                    creditLimit: $0.creditLimit,
                    note: $0.note,
                    updatedAt: $0.updatedAt
                )
            },
            netWorthSnapshots: netWorthSnapshots.map {
                BackupNetWorthSnapshot(
                    id: $0.stableID,
                    asOf: $0.asOf,
                    knowledgeCutoff: $0.knowledgeCutoff,
                    scopeKey: $0.scopeKey,
                    scopeVersion: $0.scopeVersion,
                    calculationVersion: $0.calculationVersion,
                    baseCurrency: $0.baseCurrency,
                    coveredCurrenciesJSON: $0.coveredCurrenciesJSON,
                    uncoveredCurrenciesJSON: $0.uncoveredCurrenciesJSON,
                    qualityRaw: $0.qualityRaw,
                    cashAssets: $0.cashAssets,
                    investmentAssets: $0.investmentAssets,
                    physicalAssets: $0.physicalAssets,
                    receivableAssets: $0.receivableAssets,
                    liabilities: $0.liabilities,
                    reasonsJSON: $0.reasonsJSON,
                    causesJSON: $0.causesJSON,
                    provisional: $0.provisional,
                    createdAt: $0.createdAt
                )
            },
            aiChatSessions: aiChatSessions.map {
                BackupAIChatSession(
                    id: $0.stableID,
                    title: $0.title,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    isStarred: $0.isStarred,
                    isRecord: $0.isRecord,
                    providerID: $0.providerID,
                    model: $0.model,
                    effortRaw: $0.effortRaw
                )
            },
            aiChatMessages: aiChatMessages.map {
                BackupAIChatMessage(
                    id: $0.stableID,
                    sessionID: $0.sessionID,
                    role: $0.role,
                    content: $0.content,
                    createdAt: $0.createdAt,
                    reasoningSummary: $0.reasoningSummary,
                    sourceJSON: $0.sourceJSON,
                    attachmentsJSON: $0.attachmentsJSON.isEmpty ? nil : $0.attachmentsJSON,
                    recordJSON: $0.recordJSON.isEmpty ? nil : $0.recordJSON,
                    isError: $0.isError
                )
            },
            aiMemories: aiMemories.map {
                BackupAIMemory(
                    id: $0.stableID,
                    phrase: $0.phrase,
                    content: $0.content,
                    source: $0.source,
                    sessionID: $0.sessionID,
                    consent: $0.consent,
                    statusRaw: $0.statusRaw,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    lastUsedAt: $0.lastUsedAt
                )
            },
            aiRequestRuns: aiRequestRuns.map {
                BackupAIRequestRun(
                    id: $0.stableID,
                    sessionID: $0.sessionID,
                    modeRaw: $0.modeRaw,
                    statusRaw: $0.statusRaw,
                    providerID: $0.providerID,
                    providerLabel: $0.providerLabel,
                    model: $0.model,
                    effortRaw: $0.effortRaw,
                    endpointRaw: $0.endpointRaw,
                    inputCharacters: $0.inputCharacters,
                    attachmentCount: $0.attachmentCount,
                    resultSummary: $0.resultSummary,
                    errorMessage: $0.errorMessage,
                    createdAt: $0.createdAt,
                    startedAt: $0.startedAt,
                    finishedAt: $0.finishedAt,
                    updatedAt: $0.updatedAt
                )
            },
            aiRequestEvents: aiRequestEvents.map {
                BackupAIRequestEvent(
                    id: $0.stableID,
                    runID: $0.runID,
                    sequence: $0.sequence,
                    typeRaw: $0.typeRaw,
                    summary: $0.summary,
                    count: $0.count,
                    createdAt: $0.createdAt
                )
            },
            aiReportSchedules: aiReportSchedules.map {
                BackupAIReportSchedule(
                    id: $0.stableID,
                    sessionID: $0.sessionID,
                    title: $0.title,
                    reportType: $0.reportType,
                    periodKind: $0.periodKind,
                    dayValue: $0.dayValue,
                    enabled: $0.enabled,
                    nextRunAt: $0.nextRunAt,
                    providerID: $0.providerID,
                    model: $0.model,
                    effortRaw: $0.effortRaw,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            budgetPlansV2: budgetPlansV2.map {
                BackupBudgetPlanV2(
                    id: $0.stableID,
                    bookID: $0.bookID,
                    currencyCode: $0.currencyCode,
                    timezone: $0.timezone,
                    name: $0.name,
                    role: $0.roleRaw,
                    cadenceRaw: $0.cadenceRaw,
                    anchorStart: $0.anchorStart,
                    monthStartDay: $0.monthStartDay,
                    weekStart: $0.weekStart,
                    endInclusive: $0.endInclusive,
                    expenseScopeJSON: $0.expenseScopeJSON,
                    statusRaw: $0.statusRaw,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            budgetPlanRevisionsV2: budgetPlanRevisionsV2.map {
                BackupBudgetPlanRevisionV2(
                    id: $0.stableID,
                    planID: $0.planID,
                    effectiveCycleStart: $0.effectiveCycleStart,
                    effectiveToCycleStart: $0.effectiveToCycleStart,
                    amountCents: $0.amountCents,
                    categoryBudgetsJSON: $0.categoryBudgetsJSON,
                    monthlyIncomeCents: $0.monthlyIncomeCents,
                    fixedTemplatesJSON: $0.fixedTemplatesJSON,
                    legacySourcePeriodID: $0.legacySourcePeriodID,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            budgetCycleOverridesV2: budgetCycleOverridesV2.map {
                BackupBudgetCycleOverrideV2(
                    id: $0.stableID,
                    planID: $0.planID,
                    cycleStart: $0.cycleStart,
                    cycleEndInclusive: $0.cycleEndInclusive,
                    targetAmountCents: $0.targetAmountCents,
                    categoryBudgetsJSON: $0.categoryBudgetsJSON,
                    inputIntentRaw: $0.inputIntentRaw,
                    inputDeltaCents: $0.inputDeltaCents,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            budgetCommitmentOccurrencesV2: budgetCommitmentOccurrencesV2.map {
                BackupBudgetCommitmentOccurrenceV2(
                    id: $0.stableID,
                    planID: $0.planID,
                    revisionID: $0.revisionID,
                    templateID: $0.templateID,
                    cycleStart: $0.cycleStart,
                    cycleEndInclusive: $0.cycleEndInclusive,
                    dueDate: $0.dueDate,
                    plannedCents: $0.plannedCents,
                    resolutionStatusRaw: $0.resolutionStatusRaw,
                    reviewReasonRaw: $0.reviewReasonRaw,
                    matchedTransactionFamilyID: $0.matchedTransactionFamilyID,
                    resolvedAt: $0.resolvedAt,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            budgetChangeEventsV2: budgetChangeEventsV2.map {
                BackupBudgetChangeEventV2(
                    id: $0.stableID,
                    planID: $0.planID,
                    eventType: $0.eventType,
                    beforeJSON: $0.beforeJSON,
                    afterJSON: $0.afterJSON,
                    createdAt: $0.createdAt
                )
            },
            reports: reports.map {
                BackupReport(
                    id: $0.stableID,
                    bookID: $0.bookID,
                    type: $0.type,
                    title: $0.title,
                    summary: $0.summary,
                    markdown: $0.markdown,
                    periodStart: $0.periodStart,
                    periodEnd: $0.periodEnd,
                    createdAt: $0.createdAt,
                    pinnedAt: $0.pinnedAt
                )
            },
            accountBalanceCheckpoints: accountBalanceCheckpoints.map {
                BackupAccountBalanceCheckpoint(
                    id: $0.stableID,
                    accountID: $0.accountID,
                    eventKindRaw: $0.eventKindRaw,
                    effectiveAt: $0.effectiveAt,
                    sequence: $0.sequence,
                    timezone: $0.timezone,
                    knowledgeCutoff: $0.knowledgeCutoff,
                    targetBalance: $0.targetBalance,
                    calculatedBefore: $0.calculatedBefore,
                    deltaAtCreation: $0.deltaAtCreation,
                    reason: $0.reason,
                    note: $0.note,
                    status: $0.status,
                    reversalOfID: $0.reversalOfID,
                    coveredUnknownEventIDs: $0.coveredUnknownEventIDs,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            netWorthVerifiedCheckpoints: netWorthVerifiedCheckpoints.map {
                BackupNetWorthVerifiedCheckpoint(
                    id: $0.stableID,
                    asOf: $0.asOf,
                    knowledgeCutoff: $0.knowledgeCutoff,
                    scopeVersion: $0.scopeVersion,
                    calculationVersion: $0.calculationVersion,
                    currencyCoverageJSON: $0.currencyCoverageJSON,
                    totalAssets: $0.totalAssets,
                    totalLiabilities: $0.totalLiabilities,
                    netWorth: $0.netWorth,
                    completenessRaw: $0.completenessRaw,
                    reasonsJSON: $0.reasonsJSON,
                    statusRaw: $0.statusRaw,
                    supersedesID: $0.supersedesID,
                    createdAt: $0.createdAt
                )
            },
            netWorthVerifiedItems: netWorthVerifiedCheckpoints.flatMap {
                decodeVerifiedItems($0.itemsJSON, fallbackCheckpointID: $0.stableID)
            }
        )
        return try encoder.encode(package)
    }

    /// Creates the iOS transport archive. The entity payload remains canonical
    /// JSON so it can be adapted to Android SQLite without coupling SwiftData's
    /// private store schema to the Flutter database schema.
    static func exportArchive(context: ModelContext) throws -> Data {
        let databaseData = try export(context: context)
        let attachments = try AttachmentStore.allRelativePaths()
        var payloads: [(String, Data)] = [(archiveDatabasePath, databaseData)]

        for relativePath in attachments {
            guard let url = AttachmentStore.url(for: relativePath),
                  FileManager.default.fileExists(atPath: url.path) else {
                throw BackupStoreError.missingAttachment(relativePath)
            }
            let archivePath = relativePath.hasPrefix("asset_media/")
                ? relativePath
                : "receipts/\(relativePath)"
            payloads.append((archivePath, try Data(contentsOf: url)))
        }

        let checksums = Dictionary(uniqueKeysWithValues: payloads.map { path, data in
            (path, sha256(data))
        })
        let manifest = ArchiveManifest(
            format: archiveFormat,
            version: archiveVersion,
            exportedAt: Date(),
            schemaVersion: FeimiaoBackupPackage.currentSchemaVersion,
            database: archiveDatabasePath,
            checksums: checksums,
            contains: [
                "database": true,
                "receipts": attachments.contains { !$0.hasPrefix("asset_media/") },
                "assetMedia": attachments.contains { $0.hasPrefix("asset_media/") }
            ],
            excludes: ["deepseek_api_key", "custom_ai_api_key", "ai_provider_api_key_*", "oauth_refresh_token"]
        )
        let manifestData = try encoder.encode(manifest)
        let entries = try payloads.map { try ZipArchive.Entry(path: $0.0, data: $0.1) }
            + [try ZipArchive.Entry(path: "manifest.json", data: manifestData)]
        return try ZipArchive.encode(entries)
    }

    @discardableResult
    /// Defaults to full replacement because this entry point backs the user
    /// facing “恢复” action. Callers that are importing a partial exchange
    /// package must pass `mode: .merge` explicitly.
    static func importData(
        _ data: Data,
        into context: ModelContext,
        mode: BackupImportMode = .replace,
        save: Bool = true
    ) throws -> BackupImportSummary {
        if isZip(data) {
            return try importArchive(data, mode: mode, into: context)
        }

        let package: FeimiaoBackupPackage
        do {
            package = try decoder.decode(FeimiaoBackupPackage.self, from: data)
        } catch {
            throw BackupStoreError.malformed
        }
        guard package.schemaVersion <= FeimiaoBackupPackage.currentSchemaVersion else {
            throw BackupStoreError.unsupportedVersion(package.schemaVersion)
        }

        if mode == .replace {
            try deleteAllModels(from: context)
        }

        let currentBooks = try context.fetch(FetchDescriptor<Book>())
        let currentAccounts = try context.fetch(FetchDescriptor<Account>())
        let currentCategories = try context.fetch(FetchDescriptor<TxCategory>())
        let currentTags = try context.fetch(FetchDescriptor<Tag>())
        let currentTransactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let currentBudgets = try context.fetch(FetchDescriptor<Budget>())
        let currentSavingsGoals = try context.fetch(FetchDescriptor<SavingsGoal>())
        let currentRecurringRules = try context.fetch(FetchDescriptor<RecurringRule>())
        let currentRecurringOccurrences = try context.fetch(FetchDescriptor<RecurringOccurrence>())
        let currentPhysicalAssets = try context.fetch(FetchDescriptor<PhysicalAsset>())
        let currentAssetEvents = try context.fetch(FetchDescriptor<AssetEvent>())
        let currentAssetUsageEvents = try context.fetch(FetchDescriptor<AssetUsageEvent>())
        let currentAssetTransactionLinks = try context.fetch(FetchDescriptor<AssetTransactionLink>())
        let currentAssetRefundAllocations = try context.fetch(FetchDescriptor<AssetRefundAllocation>())
        let currentAssetValuations = try context.fetch(FetchDescriptor<AssetValuation>())
        let currentReceivableAssets = try context.fetch(FetchDescriptor<ReceivableAsset>())
        let currentReceivableRecoveries = try context.fetch(FetchDescriptor<ReceivableRecovery>())
        let currentLiabilities = try context.fetch(FetchDescriptor<LiabilityProfile>())
        let currentNetWorthSnapshots = try context.fetch(FetchDescriptor<NetWorthSnapshot>())
        let currentAIChatSessions = try context.fetch(FetchDescriptor<AIChatSession>())
        let currentAIChatMessages = try context.fetch(FetchDescriptor<AIChatMessage>())
        let currentAIMemories = try context.fetch(FetchDescriptor<AIMemoryRecord>())
        let currentAIRequestRuns = try context.fetch(FetchDescriptor<AIRequestRunRecord>())
        let currentAIRequestEvents = try context.fetch(FetchDescriptor<AIRequestEventRecord>())
        let currentAIReportSchedules = try context.fetch(FetchDescriptor<AIReportScheduleRecord>())
        let currentBudgetPlansV2 = try context.fetch(FetchDescriptor<BudgetPlanRecord>())
        let currentBudgetPlanRevisionsV2 = try context.fetch(FetchDescriptor<BudgetPlanRevisionRecord>())
        let currentBudgetCycleOverridesV2 = try context.fetch(FetchDescriptor<BudgetCycleOverrideRecord>())
        let currentBudgetCommitmentOccurrencesV2 = try context.fetch(FetchDescriptor<BudgetCommitmentOccurrenceRecord>())
        let currentBudgetChangeEventsV2 = try context.fetch(FetchDescriptor<BudgetChangeEventRecord>())
        let currentReports = try context.fetch(FetchDescriptor<ReportRecord>())
        let currentAccountBalanceCheckpoints = try context.fetch(FetchDescriptor<AccountBalanceCheckpointRecord>())
        let currentNetWorthVerifiedCheckpoints = try context.fetch(FetchDescriptor<NetWorthVerifiedCheckpointRecord>())

        var books = Dictionary(uniqueKeysWithValues: currentBooks.map { ($0.stableID, $0) })
        for item in package.books {
            let book = books[item.id] ?? Book(name: item.name)
            if books[item.id] == nil { context.insert(book) }
            book.stableID = item.id
            book.name = item.name
            if let cover = item.cover { book.cover = cover }
            book.remark = item.remark
            book.sortOrder = item.sortOrder
            book.isStarred = item.isStarred
            book.includeInTotal = item.includeInTotal
            book.isDefault = item.isDefault
            if let updatedAt = item.updatedAt { book.updatedAt = updatedAt }
            books[item.id] = book
        }

        var accounts = Dictionary(uniqueKeysWithValues: currentAccounts.map { ($0.stableID, $0) })
        for item in package.accounts {
            let account = accounts[item.id] ?? Account(name: item.name, kind: item.kind)
            if accounts[item.id] == nil { context.insert(account) }
            account.stableID = item.id
            account.name = item.name
            account.kind = item.kind
            account.currencyCode = item.currencyCode
            account.initialBalance = item.initialBalance
            account.sortOrder = item.sortOrder
            if let institution = item.institution { account.institution = institution }
            if let includeInNetWorth = item.includeInNetWorth {
                account.includeInNetWorth = includeInNetWorth
            }
            if let isDeleted = item.isDeleted { account.isDeleted = isDeleted }
            if let status = item.status { account.status = status }
            if let archivedAt = item.archivedAt { account.archivedAt = archivedAt }
            if let lastVerifiedAt = item.lastVerifiedAt { account.lastVerifiedAt = lastVerifiedAt }
            if let effectiveAt = item.openingBalanceEffectiveAt {
                account.openingBalanceEffectiveAt = effectiveAt
            }
            if let quality = item.openingBalanceQuality {
                account.openingBalanceQuality = quality
            }
            if let balanceMode = item.balanceMode { account.balanceMode = balanceMode }
            if let day = item.creditStatementDay { account.creditStatementDay = day }
            if let day = item.creditPaymentDay { account.creditPaymentDay = day }
            if let limit = item.creditLimit { account.creditLimit = limit }
            if let updatedAt = item.updatedAt { account.updatedAt = updatedAt }
            accounts[item.id] = account
        }

        var categoriesByKey = Dictionary(uniqueKeysWithValues: currentCategories.map { ($0.key, $0) })
        for item in package.categories {
            let category = categoriesByKey[item.key] ?? TxCategory(
                key: item.key,
                name: item.name,
                symbol: item.symbol,
                kind: item.kind,
                emoji: item.emoji,
                parentKey: item.parentKey,
                sortOrder: item.sortOrder
            )
            if categoriesByKey[item.key] == nil { context.insert(category) }
            category.name = item.name
            category.symbol = item.symbol
            category.emoji = item.emoji
            category.kind = item.kind
            category.parentKey = item.parentKey
            category.sortOrder = item.sortOrder
            category.isArchived = item.isArchived
            categoriesByKey[item.key] = category
        }

        var tags = Dictionary(uniqueKeysWithValues: currentTags.map { ($0.stableID, $0) })
        for item in package.tags {
            let tag = tags[item.id] ?? Tag(name: item.name)
            if tags[item.id] == nil { context.insert(tag) }
            tag.stableID = item.id
            tag.name = item.name
            tag.colorValue = item.colorValue
            tag.sortOrder = item.sortOrder
            if let updatedAt = item.updatedAt { tag.updatedAt = updatedAt }
            tags[item.id] = tag
        }

        var transactions = Dictionary(uniqueKeysWithValues: currentTransactions.map { ($0.stableID, $0) })
        for item in package.transactions {
            let transaction = transactions[item.id] ?? MoneyTransaction(amount: item.amount, kind: item.kind)
            if transactions[item.id] == nil { context.insert(transaction) }
            transaction.stableID = item.id
            transaction.amount = item.amount
            transaction.kind = item.kind
            transaction.date = item.date
            transaction.note = item.note
            transaction.merchantName = item.merchant ?? ""
            transaction.productName = item.product ?? ""
            transaction.currencyCode = item.currencyCode
            transaction.category = item.categoryKey.flatMap { categoriesByKey[$0] }
                ?? item.categoryName.flatMap { name in
                    categoriesByKey.values.first { $0.name == name && $0.kind == item.kind }
                }
            transaction.account = item.accountID.flatMap { accounts[$0] }
            transaction.toAccount = item.toAccountID.flatMap { accounts[$0] }
            transaction.book = item.bookID.flatMap { books[$0] }
            transaction.refundOfID = item.refundOfID
            transaction.isReimbursed = item.isReimbursed
            transaction.isExcluded = item.isExcluded
            transaction.tags = item.tags
            transaction.timePrecision = item.timePrecision ?? .legacyUnknown
            if let createdAt = item.createdAt { transaction.createdAt = createdAt }
            transaction.settledAt = item.settledAt
            transaction.settlementQuality = item.settlementQuality ?? .unknown
            transaction.settlementAccountID = item.settlementAccountID
            transaction.settlementAccountQuality = item.settlementAccountQuality ?? .unknown
            transaction.eventType = item.eventType ?? .defaultFor(item.kind)
            transaction.reimbursable = item.reimbursable ?? false
            transaction.attachmentPath = item.attachmentPath ?? ""
            transaction.orderNo = item.orderNo ?? ""
            transaction.recurringRuleID = item.recurringRuleID
            if let updatedAt = item.updatedAt { transaction.updatedAt = updatedAt }
            transactions[item.id] = transaction
        }

        var budgets = Dictionary(uniqueKeysWithValues: currentBudgets.map { ($0.stableID, $0) })
        for item in package.budgets {
            let budget = budgets[item.id] ?? Budget(amount: item.amount, categoryKey: item.categoryKey, stableID: item.id)
            if budgets[item.id] == nil { context.insert(budget) }
            budget.stableID = item.id
            budget.amount = item.amount
            budget.categoryKey = item.categoryKey
            budget.bookID = item.bookID
            budget.periodStart = item.periodStart
            budget.periodEnd = item.periodEnd
            budget.cycleRaw = item.cycleRaw ?? "monthly"
            budget.isActive = item.isActive ?? true
            if let updatedAt = item.updatedAt { budget.updatedAt = updatedAt }
            budgets[item.id] = budget
        }

        var savingsGoals = Dictionary(uniqueKeysWithValues: currentSavingsGoals.map { ($0.stableID, $0) })
        for item in package.savingsGoals {
            let goal = savingsGoals[item.id] ?? SavingsGoal(
                name: item.name,
                targetAmount: item.targetAmount,
                savedAmount: item.savedAmount,
                currencyCode: item.currencyCode,
                linkedAssetID: item.linkedAssetID,
                note: item.note,
                stableID: item.id
            )
            if savingsGoals[item.id] == nil { context.insert(goal) }
            goal.stableID = item.id
            goal.name = item.name
            goal.emoji = item.emoji
            goal.targetAmount = item.targetAmount
            goal.savedAmount = item.savedAmount
            goal.currencyCode = item.currencyCode
            goal.linkedAssetID = item.linkedAssetID
            goal.note = item.note
            goal.isArchived = item.isArchived
            if let updatedAt = item.updatedAt { goal.updatedAt = updatedAt }
            savingsGoals[item.id] = goal
        }

        var recurringRules = Dictionary(uniqueKeysWithValues: currentRecurringRules.map { ($0.stableID, $0) })
        for item in package.recurringRules {
            let rule = recurringRules[item.id] ?? RecurringRule(
                amount: item.amount,
                kind: item.kind,
                bookID: item.bookID,
                categoryKey: item.categoryKey,
                accountID: item.accountID,
                toAccountID: item.toAccountID,
                note: item.note,
                period: RecurringPeriod(rawValue: item.periodRaw) ?? .monthly,
                startDate: item.startDate,
                firstDueDate: item.nextDueDate,
                endDate: item.endDate,
                totalCount: item.totalCount,
                stableID: item.id
            )
            if recurringRules[item.id] == nil { context.insert(rule) }
            rule.stableID = item.id
            rule.bookID = item.bookID
            rule.kindRaw = item.kind.rawValue
            rule.amount = item.amount
            rule.categoryKey = item.categoryKey
            rule.accountID = item.accountID
            rule.toAccountID = item.toAccountID
            rule.note = item.note
            rule.periodRaw = item.periodRaw
            rule.startDate = item.startDate
            rule.nextDueDate = item.nextDueDate
            rule.endDate = item.endDate
            rule.totalCount = item.totalCount
            rule.generatedCount = item.generatedCount
            rule.anchorDay = item.anchorDay
            rule.isEnabled = item.isEnabled
            if let updatedAt = item.updatedAt { rule.updatedAt = updatedAt }
            recurringRules[item.id] = rule
        }

        var recurringOccurrences = Dictionary(uniqueKeysWithValues: currentRecurringOccurrences.map { ($0.stableID, $0) })
        for item in package.recurringOccurrences {
            let occurrence = recurringOccurrences[item.id] ?? RecurringOccurrence(
                ruleID: item.ruleID,
                dueDate: item.dueDate,
                transactionID: item.transactionID,
                stableID: item.id
            )
            if recurringOccurrences[item.id] == nil { context.insert(occurrence) }
            occurrence.stableID = item.id
            occurrence.ruleID = item.ruleID
            occurrence.dueDate = item.dueDate
            occurrence.transactionID = item.transactionID
            if let createdAt = item.createdAt { occurrence.createdAt = createdAt }
            recurringOccurrences[item.id] = occurrence
        }

        var physicalAssets = Dictionary(uniqueKeysWithValues: currentPhysicalAssets.map { ($0.stableID, $0) })
        for item in package.physicalAssets {
            let asset = physicalAssets[item.id] ?? PhysicalAsset(
                name: item.name,
                kind: PhysicalAssetKind(rawValue: item.kindRaw) ?? .other,
                purchasePrice: item.purchasePrice,
                currentValue: item.currentValue,
                currencyCode: item.currencyCode,
                bookID: item.bookID,
                stableID: item.id
            )
            if physicalAssets[item.id] == nil { context.insert(asset) }
            asset.stableID = item.id
            asset.bookID = item.bookID
            asset.name = item.name
            asset.kindRaw = item.kindRaw
            asset.lifecycleRaw = item.lifecycleRaw
            if let value = item.economicStatusRaw { asset.economicStatusRaw = value }
            if let value = item.usageStatusRaw { asset.usageStatusRaw = value }
            if let value = item.visibilityStatusRaw { asset.visibilityStatusRaw = value }
            if let value = item.inclusionQualityRaw { asset.inclusionQualityRaw = value }
            if let value = item.sourceTypeRaw { asset.sourceTypeRaw = value }
            if let value = item.acquisitionCostSourceRaw { asset.acquisitionCostSourceRaw = value }
            asset.purchasePrice = item.purchasePrice
            asset.currentValue = item.currentValue
            asset.currencyCode = item.currencyCode
            asset.purchaseDate = item.purchaseDate
            asset.brand = item.brand
            asset.model = item.model
            asset.location = item.location
            asset.warrantyUntil = item.warrantyUntil
            asset.usageTrackingEnabled = item.usageTrackingEnabled
            asset.usageCount = item.usageCount
            asset.savingsGoalID = item.savingsGoalID
            asset.photoPath = item.photoPath
            asset.thumbnailPath = item.thumbnailPath
            asset.invoicePath = item.invoicePath
            asset.depreciationMethod = item.depreciationMethod
            asset.depreciationBase = item.depreciationBase
            asset.salvageValue = item.salvageValue
            asset.usefulLifeMonths = item.usefulLifeMonths
            asset.depreciationStartDate = item.depreciationStartDate
            asset.depreciationPaused = item.depreciationPaused
            asset.note = item.note
            asset.includeInNetWorth = item.includeInNetWorth
            asset.isDeleted = item.isDeleted
            asset.endedAt = item.endedAt
            asset.archivedAt = item.archivedAt
            if let createdAt = item.createdAt { asset.createdAt = createdAt }
            if let updatedAt = item.updatedAt { asset.updatedAt = updatedAt }
            physicalAssets[item.id] = asset
        }

        var assetEvents = Dictionary(uniqueKeysWithValues: currentAssetEvents.map { ($0.stableID, $0) })
        for item in package.assetEvents {
            let event = assetEvents[item.id] ?? AssetEvent(
                assetID: item.assetID,
                kind: AssetEventKind(rawValue: item.kindRaw) ?? .created,
                occurredAt: item.occurredAt,
                value: item.value,
                note: item.note,
                metadataJSON: item.metadataJSON
            )
            if assetEvents[item.id] == nil { context.insert(event) }
            event.stableID = item.id
            event.assetID = item.assetID
            event.kindRaw = item.kindRaw
            event.occurredAt = item.occurredAt
            event.value = item.value
            event.note = item.note
            event.metadataJSON = item.metadataJSON
            if let createdAt = item.createdAt { event.createdAt = createdAt }
            assetEvents[item.id] = event
        }

        var assetUsageEvents = Dictionary(uniqueKeysWithValues: currentAssetUsageEvents.map { ($0.stableID, $0) })
        for item in package.assetUsageEvents {
            let event = assetUsageEvents[item.id] ?? AssetUsageEvent(
                assetID: item.assetID,
                countDelta: item.countDelta,
                reversalOfID: item.reversalOfID,
                occurredAt: item.occurredAt,
                note: item.note,
                stableID: item.id
            )
            if assetUsageEvents[item.id] == nil { context.insert(event) }
            event.stableID = item.id
            event.assetID = item.assetID
            event.countDelta = item.countDelta
            event.reversalOfID = item.reversalOfID
            event.occurredAt = item.occurredAt
            event.note = item.note
            if let createdAt = item.createdAt { event.createdAt = createdAt }
            if let updatedAt = item.updatedAt { event.updatedAt = updatedAt }
            assetUsageEvents[item.id] = event
        }

        var assetTransactionLinks = Dictionary(uniqueKeysWithValues: currentAssetTransactionLinks.map { ($0.stableID, $0) })
        for item in package.assetTransactionLinks {
            let link = assetTransactionLinks[item.id] ?? AssetTransactionLink(
                assetID: item.assetID,
                transactionID: item.transactionID,
                linkTypeRaw: item.linkTypeRaw,
                amount: item.amount,
                stableID: item.id
            )
            if assetTransactionLinks[item.id] == nil { context.insert(link) }
            link.stableID = item.id
            link.assetID = item.assetID
            link.assetObjectType = item.assetObjectType
            link.transactionID = item.transactionID
            link.linkTypeRaw = item.linkTypeRaw
            link.amount = item.amount
            link.allocatedGrossCents = item.allocatedGrossCents
            link.allocatedRefundCents = item.allocatedRefundCents
            link.costQualityRaw = item.costQualityRaw
            link.note = item.note
            if let createdAt = item.createdAt { link.createdAt = createdAt }
            if let updatedAt = item.updatedAt { link.updatedAt = updatedAt }
            assetTransactionLinks[item.id] = link
        }

        var assetRefundAllocations = Dictionary(uniqueKeysWithValues: currentAssetRefundAllocations.map { ($0.stableID, $0) })
        for item in package.assetRefundAllocations {
            let allocation = assetRefundAllocations[item.id] ?? AssetRefundAllocation(
                assetTransactionLinkID: item.assetTransactionLinkID,
                refundTransactionID: item.refundTransactionID,
                allocatedRefundCents: item.allocatedRefundCents,
                statusRaw: item.statusRaw,
                stableID: item.id
            )
            if assetRefundAllocations[item.id] == nil { context.insert(allocation) }
            allocation.stableID = item.id
            allocation.assetTransactionLinkID = item.assetTransactionLinkID
            allocation.refundTransactionID = item.refundTransactionID
            allocation.allocatedRefundCents = item.allocatedRefundCents
            allocation.statusRaw = item.statusRaw
            if let createdAt = item.createdAt { allocation.createdAt = createdAt }
            if let updatedAt = item.updatedAt { allocation.updatedAt = updatedAt }
            assetRefundAllocations[item.id] = allocation
        }

        var assetValuations = Dictionary(uniqueKeysWithValues: currentAssetValuations.map { ($0.stableID, $0) })
        for item in package.assetValuations {
            let valuation = assetValuations[item.id] ?? AssetValuation(
                assetID: item.assetID,
                value: item.value,
                sourceRaw: item.sourceRaw,
                valuedAt: item.valuedAt,
                note: item.note
            )
            if assetValuations[item.id] == nil { context.insert(valuation) }
            valuation.stableID = item.id
            valuation.assetID = item.assetID
            valuation.value = item.value
            valuation.sourceRaw = item.sourceRaw
            valuation.valuedAt = item.valuedAt
            valuation.note = item.note
            if let createdAt = item.createdAt { valuation.createdAt = createdAt }
            assetValuations[item.id] = valuation
        }

        var receivableAssets = Dictionary(uniqueKeysWithValues: currentReceivableAssets.map { ($0.stableID, $0) })
        for item in package.receivableAssets {
            let receivable = receivableAssets[item.id] ?? ReceivableAsset(
                name: item.name,
                originalAmount: item.originalAmount,
                kind: ReceivableKind(rawValue: item.kindRaw) ?? .other,
                bookID: item.bookID,
                currencyCode: item.currencyCode,
                stableID: item.id
            )
            if receivableAssets[item.id] == nil { context.insert(receivable) }
            receivable.stableID = item.id
            receivable.bookID = item.bookID
            receivable.name = item.name
            receivable.kindRaw = item.kindRaw
            receivable.lifecycleRaw = item.lifecycleRaw
            if let value = item.economicStatusRaw { receivable.economicStatusRaw = value }
            if let value = item.visibilityStatusRaw { receivable.visibilityStatusRaw = value }
            if let value = item.inclusionQualityRaw { receivable.inclusionQualityRaw = value }
            receivable.originalAmount = item.originalAmount
            receivable.remainingAmount = item.remainingAmount
            receivable.currencyCode = item.currencyCode
            receivable.counterparty = item.counterparty
            receivable.dueDate = item.dueDate
            receivable.includeInNetWorth = item.includeInNetWorth
            receivable.note = item.note
            receivable.isDeleted = item.isDeleted
            receivable.endedAt = item.endedAt
            receivable.archivedAt = item.archivedAt
            if let createdAt = item.createdAt { receivable.createdAt = createdAt }
            if let updatedAt = item.updatedAt { receivable.updatedAt = updatedAt }
            receivableAssets[item.id] = receivable
        }

        var receivableRecoveries = Dictionary(uniqueKeysWithValues: currentReceivableRecoveries.map { ($0.stableID, $0) })
        for item in package.receivableRecoveries {
            let recovery = receivableRecoveries[item.id] ?? ReceivableRecovery(
                receivableID: item.receivableID,
                amount: item.amount,
                recoveredAt: item.recoveredAt,
                targetAccountID: item.targetAccountID,
                transactionID: item.transactionID,
                note: item.note
            )
            if receivableRecoveries[item.id] == nil { context.insert(recovery) }
            recovery.stableID = item.id
            recovery.receivableID = item.receivableID
            recovery.amount = item.amount
            recovery.recoveredAt = item.recoveredAt
            recovery.targetAccountID = item.targetAccountID
            recovery.transactionID = item.transactionID
            recovery.note = item.note
            if let createdAt = item.createdAt { recovery.createdAt = createdAt }
            receivableRecoveries[item.id] = recovery
        }

        var liabilities = Dictionary(uniqueKeysWithValues: currentLiabilities.map { ($0.stableID, $0) })
        for item in package.liabilities {
            let liability = liabilities[item.id] ?? LiabilityProfile(
                accountID: item.accountID,
                kind: LiabilityKind(rawValue: item.kindRaw) ?? .other,
                originalPrincipal: item.originalPrincipal,
                currentPrincipal: item.currentPrincipal,
                currencyCode: item.currencyCode
            )
            if liabilities[item.id] == nil { context.insert(liability) }
            liability.stableID = item.id
            liability.accountID = item.accountID
            liability.repaymentAccountID = item.repaymentAccountID
            liability.kindRaw = item.kindRaw
            liability.lifecycleRaw = item.lifecycleRaw
            liability.originalPrincipal = item.originalPrincipal
            liability.currentPrincipal = item.currentPrincipal
            liability.currencyCode = item.currencyCode
            liability.counterparty = item.counterparty
            liability.annualRate = item.annualRate
            liability.startDate = item.startDate
            liability.dueDate = item.dueDate
            liability.statementDay = item.statementDay
            liability.paymentDay = item.paymentDay
            liability.creditLimit = item.creditLimit
            liability.note = item.note
            if let updatedAt = item.updatedAt { liability.updatedAt = updatedAt }
            liabilities[item.id] = liability
        }

        var netWorthSnapshots = Dictionary(uniqueKeysWithValues: currentNetWorthSnapshots.map { ($0.stableID, $0) })
        for item in package.netWorthSnapshots {
            let snapshot = netWorthSnapshots[item.id] ?? NetWorthSnapshot(
                asOf: item.asOf,
                baseCurrency: item.baseCurrency
            )
            if netWorthSnapshots[item.id] == nil { context.insert(snapshot) }
            snapshot.stableID = item.id
            snapshot.asOf = item.asOf
            snapshot.knowledgeCutoff = item.knowledgeCutoff
            snapshot.scopeKey = item.scopeKey
            snapshot.scopeVersion = item.scopeVersion
            snapshot.calculationVersion = item.calculationVersion
            snapshot.baseCurrency = item.baseCurrency
            snapshot.coveredCurrenciesJSON = item.coveredCurrenciesJSON
            snapshot.uncoveredCurrenciesJSON = item.uncoveredCurrenciesJSON
            snapshot.qualityRaw = item.qualityRaw
            snapshot.cashAssets = item.cashAssets
            snapshot.investmentAssets = item.investmentAssets
            snapshot.physicalAssets = item.physicalAssets
            snapshot.receivableAssets = item.receivableAssets
            snapshot.liabilities = item.liabilities
            snapshot.reasonsJSON = item.reasonsJSON
            snapshot.causesJSON = item.causesJSON
            snapshot.provisional = item.provisional
            if let createdAt = item.createdAt { snapshot.createdAt = createdAt }
            netWorthSnapshots[item.id] = snapshot
        }

        var aiChatSessions = Dictionary(uniqueKeysWithValues: currentAIChatSessions.map { ($0.stableID, $0) })
        for item in package.aiChatSessions {
            let session = aiChatSessions[item.id] ?? AIChatSession(
                stableID: item.id,
                title: item.title,
                isRecord: item.isRecord,
                providerID: item.providerID,
                model: item.model,
                effort: AIReasoningEffort(rawValue: item.effortRaw) ?? .low
            )
            if aiChatSessions[item.id] == nil { context.insert(session) }
            session.stableID = item.id
            session.title = item.title
            session.createdAt = item.createdAt
            session.updatedAt = item.updatedAt
            session.isStarred = item.isStarred
            session.isRecord = item.isRecord
            session.providerID = item.providerID
            session.model = item.model
            session.effortRaw = item.effortRaw
            aiChatSessions[item.id] = session
        }

        var aiChatMessages = Dictionary(uniqueKeysWithValues: currentAIChatMessages.map { ($0.stableID, $0) })
        for item in package.aiChatMessages {
            let message = aiChatMessages[item.id] ?? AIChatMessage(
                stableID: item.id,
                sessionID: item.sessionID,
                role: item.role,
                content: item.content,
                createdAt: item.createdAt,
                reasoningSummary: item.reasoningSummary,
                sourceJSON: item.sourceJSON,
                attachmentsJSON: item.attachmentsJSON ?? "[]",
                recordJSON: item.recordJSON ?? "",
                isError: item.isError
            )
            if aiChatMessages[item.id] == nil { context.insert(message) }
            message.stableID = item.id
            message.sessionID = item.sessionID
            message.role = item.role
            message.content = item.content
            message.createdAt = item.createdAt
            message.reasoningSummary = item.reasoningSummary
            message.sourceJSON = item.sourceJSON
            message.attachmentsJSON = item.attachmentsJSON ?? "[]"
            message.recordJSON = item.recordJSON ?? ""
            message.isError = item.isError
            aiChatMessages[item.id] = message
        }

        var aiMemories = Dictionary(uniqueKeysWithValues: currentAIMemories.map { ($0.stableID, $0) })
        for item in package.aiMemories {
            let memory = aiMemories[item.id] ?? AIMemoryRecord(
                stableID: item.id,
                phrase: item.phrase,
                content: item.content,
                source: item.source,
                sessionID: item.sessionID,
                consent: item.consent
            )
            if aiMemories[item.id] == nil { context.insert(memory) }
            memory.stableID = item.id
            memory.phrase = item.phrase
            memory.content = item.content
            memory.source = item.source
            memory.sessionID = item.sessionID
            memory.consent = item.consent
            memory.statusRaw = item.statusRaw
            memory.createdAt = item.createdAt
            memory.updatedAt = item.updatedAt
            memory.lastUsedAt = item.lastUsedAt
            aiMemories[item.id] = memory
        }

        var aiRequestRuns = Dictionary(uniqueKeysWithValues: currentAIRequestRuns.map { ($0.stableID, $0) })
        for item in package.aiRequestRuns {
            let run = aiRequestRuns[item.id] ?? AIRequestRunRecord(
                stableID: item.id,
                sessionID: item.sessionID,
                mode: AIRequestMode(rawValue: item.modeRaw) ?? .chat,
                providerID: item.providerID,
                providerLabel: item.providerLabel,
                model: item.model,
                effortRaw: item.effortRaw,
                endpointRaw: item.endpointRaw,
                inputCharacters: item.inputCharacters,
                attachmentCount: item.attachmentCount
            )
            if aiRequestRuns[item.id] == nil { context.insert(run) }
            run.stableID = item.id
            run.sessionID = item.sessionID
            run.modeRaw = item.modeRaw
            run.statusRaw = item.statusRaw
            run.providerID = item.providerID
            run.providerLabel = item.providerLabel
            run.model = item.model
            run.effortRaw = item.effortRaw
            run.endpointRaw = item.endpointRaw
            run.inputCharacters = item.inputCharacters
            run.attachmentCount = item.attachmentCount
            run.resultSummary = item.resultSummary
            run.errorMessage = item.errorMessage
            run.createdAt = item.createdAt
            run.startedAt = item.startedAt
            run.finishedAt = item.finishedAt
            run.updatedAt = item.updatedAt
            aiRequestRuns[item.id] = run
        }

        var aiRequestEvents = Dictionary(uniqueKeysWithValues: currentAIRequestEvents.map { ($0.stableID, $0) })
        for item in package.aiRequestEvents {
            let event = aiRequestEvents[item.id] ?? AIRequestEventRecord(
                stableID: item.id,
                runID: item.runID,
                sequence: item.sequence,
                type: AIRequestEventType(rawValue: item.typeRaw) ?? .stageChanged,
                summary: item.summary,
                count: item.count,
                createdAt: item.createdAt
            )
            if aiRequestEvents[item.id] == nil { context.insert(event) }
            event.stableID = item.id
            event.runID = item.runID
            event.sequence = item.sequence
            event.typeRaw = item.typeRaw
            event.summary = item.summary
            event.count = item.count
            event.createdAt = item.createdAt
            aiRequestEvents[item.id] = event
        }

        var aiReportSchedules = Dictionary(uniqueKeysWithValues: currentAIReportSchedules.map { ($0.stableID, $0) })
        for item in package.aiReportSchedules {
            let schedule = aiReportSchedules[item.id] ?? AIReportScheduleRecord(
                stableID: item.id,
                sessionID: item.sessionID,
                title: item.title,
                reportType: item.reportType,
                periodKind: item.periodKind,
                dayValue: item.dayValue,
                enabled: item.enabled,
                nextRunAt: item.nextRunAt,
                providerID: item.providerID,
                model: item.model,
                effortRaw: item.effortRaw
            )
            if aiReportSchedules[item.id] == nil { context.insert(schedule) }
            schedule.stableID = item.id
            schedule.sessionID = item.sessionID
            schedule.title = item.title
            schedule.reportType = item.reportType
            schedule.periodKind = item.periodKind
            schedule.dayValue = item.dayValue
            schedule.enabled = item.enabled
            schedule.nextRunAt = item.nextRunAt
            schedule.providerID = item.providerID
            schedule.model = item.model
            schedule.effortRaw = item.effortRaw
            schedule.createdAt = item.createdAt
            schedule.updatedAt = item.updatedAt
            aiReportSchedules[item.id] = schedule
        }

        var budgetPlansV2 = Dictionary(uniqueKeysWithValues: currentBudgetPlansV2.map { ($0.stableID, $0) })
        for item in package.budgetPlansV2 {
            let plan = budgetPlansV2[item.id] ?? BudgetPlanRecord(
                stableID: item.id,
                bookID: item.bookID,
                anchorStart: item.anchorStart
            )
            if budgetPlansV2[item.id] == nil { context.insert(plan) }
            plan.stableID = item.id
            plan.bookID = item.bookID
            plan.currencyCode = item.currencyCode
            plan.timezone = item.timezone
            plan.name = item.name
            plan.roleRaw = item.role
            plan.cadenceRaw = item.cadenceRaw
            plan.anchorStart = item.anchorStart
            plan.monthStartDay = item.monthStartDay
            plan.weekStart = item.weekStart
            plan.endInclusive = item.endInclusive
            plan.expenseScopeJSON = item.expenseScopeJSON
            plan.statusRaw = item.statusRaw
            plan.createdAt = item.createdAt
            plan.updatedAt = item.updatedAt
            budgetPlansV2[item.id] = plan
        }

        var budgetPlanRevisionsV2 = Dictionary(uniqueKeysWithValues: currentBudgetPlanRevisionsV2.map { ($0.stableID, $0) })
        for item in package.budgetPlanRevisionsV2 {
            let revision = budgetPlanRevisionsV2[item.id] ?? BudgetPlanRevisionRecord(
                stableID: item.id,
                planID: item.planID,
                effectiveCycleStart: item.effectiveCycleStart,
                amountCents: item.amountCents
            )
            if budgetPlanRevisionsV2[item.id] == nil { context.insert(revision) }
            revision.stableID = item.id
            revision.planID = item.planID
            revision.effectiveCycleStart = item.effectiveCycleStart
            revision.effectiveToCycleStart = item.effectiveToCycleStart
            revision.amountCents = item.amountCents
            revision.categoryBudgetsJSON = item.categoryBudgetsJSON
            revision.monthlyIncomeCents = item.monthlyIncomeCents
            revision.fixedTemplatesJSON = item.fixedTemplatesJSON
            revision.legacySourcePeriodID = item.legacySourcePeriodID
            revision.createdAt = item.createdAt
            revision.updatedAt = item.updatedAt
            budgetPlanRevisionsV2[item.id] = revision
        }

        var budgetCycleOverridesV2 = Dictionary(uniqueKeysWithValues: currentBudgetCycleOverridesV2.map { ($0.stableID, $0) })
        for item in package.budgetCycleOverridesV2 {
            let override = budgetCycleOverridesV2[item.id] ?? BudgetCycleOverrideRecord(
                stableID: item.id,
                planID: item.planID,
                cycleStart: item.cycleStart,
                cycleEndInclusive: item.cycleEndInclusive,
                targetAmountCents: item.targetAmountCents
            )
            if budgetCycleOverridesV2[item.id] == nil { context.insert(override) }
            override.stableID = item.id
            override.planID = item.planID
            override.cycleStart = item.cycleStart
            override.cycleEndInclusive = item.cycleEndInclusive
            override.targetAmountCents = item.targetAmountCents
            override.categoryBudgetsJSON = item.categoryBudgetsJSON
            override.inputIntentRaw = item.inputIntentRaw
            override.inputDeltaCents = item.inputDeltaCents
            override.createdAt = item.createdAt
            override.updatedAt = item.updatedAt
            budgetCycleOverridesV2[item.id] = override
        }

        var budgetCommitmentOccurrencesV2 = Dictionary(uniqueKeysWithValues: currentBudgetCommitmentOccurrencesV2.map { ($0.stableID, $0) })
        for item in package.budgetCommitmentOccurrencesV2 {
            let occurrence = budgetCommitmentOccurrencesV2[item.id] ?? BudgetCommitmentOccurrenceRecord(
                stableID: item.id,
                planID: item.planID,
                revisionID: item.revisionID,
                templateID: item.templateID,
                cycleStart: item.cycleStart,
                cycleEndInclusive: item.cycleEndInclusive,
                dueDate: item.dueDate,
                plannedCents: item.plannedCents
            )
            if budgetCommitmentOccurrencesV2[item.id] == nil { context.insert(occurrence) }
            occurrence.stableID = item.id
            occurrence.planID = item.planID
            occurrence.revisionID = item.revisionID
            occurrence.templateID = item.templateID
            occurrence.cycleStart = item.cycleStart
            occurrence.cycleEndInclusive = item.cycleEndInclusive
            occurrence.dueDate = item.dueDate
            occurrence.plannedCents = item.plannedCents
            occurrence.resolutionStatusRaw = item.resolutionStatusRaw
            occurrence.reviewReasonRaw = item.reviewReasonRaw
            occurrence.matchedTransactionFamilyID = item.matchedTransactionFamilyID
            occurrence.resolvedAt = item.resolvedAt
            occurrence.createdAt = item.createdAt
            occurrence.updatedAt = item.updatedAt
            budgetCommitmentOccurrencesV2[item.id] = occurrence
        }

        var budgetChangeEventsV2 = Dictionary(uniqueKeysWithValues: currentBudgetChangeEventsV2.map { ($0.stableID, $0) })
        for item in package.budgetChangeEventsV2 {
            let event = budgetChangeEventsV2[item.id] ?? BudgetChangeEventRecord(
                stableID: item.id,
                planID: item.planID,
                eventType: item.eventType,
                beforeJSON: item.beforeJSON,
                afterJSON: item.afterJSON
            )
            if budgetChangeEventsV2[item.id] == nil { context.insert(event) }
            event.stableID = item.id
            event.planID = item.planID
            event.eventType = item.eventType
            event.beforeJSON = item.beforeJSON
            event.afterJSON = item.afterJSON
            event.createdAt = item.createdAt
            budgetChangeEventsV2[item.id] = event
        }

        var reports = Dictionary(uniqueKeysWithValues: currentReports.map { ($0.stableID, $0) })
        for item in package.reports {
            let report = reports[item.id] ?? ReportRecord(
                stableID: item.id,
                bookID: item.bookID,
                type: item.type,
                title: item.title,
                summary: item.summary,
                markdown: item.markdown,
                periodStart: item.periodStart,
                periodEnd: item.periodEnd,
                createdAt: item.createdAt,
                pinnedAt: item.pinnedAt
            )
            if reports[item.id] == nil { context.insert(report) }
            report.stableID = item.id
            report.bookID = item.bookID
            report.type = item.type
            report.title = item.title
            report.summary = item.summary
            report.markdown = item.markdown
            report.periodStart = item.periodStart
            report.periodEnd = item.periodEnd
            report.createdAt = item.createdAt
            report.pinnedAt = item.pinnedAt
            reports[item.id] = report
        }

        var accountBalanceCheckpoints = Dictionary(uniqueKeysWithValues: currentAccountBalanceCheckpoints.map { ($0.stableID, $0) })
        for item in package.accountBalanceCheckpoints {
            let checkpoint = accountBalanceCheckpoints[item.id] ?? AccountBalanceCheckpointRecord(
                stableID: item.id,
                accountID: item.accountID,
                effectiveAt: item.effectiveAt,
                knowledgeCutoff: item.knowledgeCutoff,
                targetBalance: item.targetBalance,
                eventKindRaw: item.eventKindRaw
            )
            if accountBalanceCheckpoints[item.id] == nil { context.insert(checkpoint) }
            checkpoint.stableID = item.id
            checkpoint.accountID = item.accountID
            checkpoint.eventKindRaw = item.eventKindRaw
            checkpoint.effectiveAt = item.effectiveAt
            checkpoint.sequence = item.sequence
            checkpoint.timezone = item.timezone
            checkpoint.knowledgeCutoff = item.knowledgeCutoff
            checkpoint.targetBalance = item.targetBalance
            checkpoint.calculatedBefore = item.calculatedBefore
            checkpoint.deltaAtCreation = item.deltaAtCreation
            checkpoint.reason = item.reason
            checkpoint.note = item.note
            checkpoint.status = item.status
            checkpoint.reversalOfID = item.reversalOfID
            checkpoint.coveredUnknownEventIDsJSON = encodeStringArray(item.coveredUnknownEventIDs)
            checkpoint.createdAt = item.createdAt
            checkpoint.updatedAt = item.updatedAt
            accountBalanceCheckpoints[item.id] = checkpoint
        }

        var netWorthVerifiedCheckpoints = Dictionary(uniqueKeysWithValues: currentNetWorthVerifiedCheckpoints.map { ($0.stableID, $0) })
        let verifiedItemsByCheckpoint = Dictionary(grouping: package.netWorthVerifiedItems, by: \.checkpointID)
        for item in package.netWorthVerifiedCheckpoints {
            let checkpoint = netWorthVerifiedCheckpoints[item.id] ?? NetWorthVerifiedCheckpointRecord(
                stableID: item.id,
                asOf: item.asOf,
                knowledgeCutoff: item.knowledgeCutoff,
                totalAssets: item.totalAssets,
                totalLiabilities: item.totalLiabilities,
                netWorth: item.netWorth
            )
            if netWorthVerifiedCheckpoints[item.id] == nil { context.insert(checkpoint) }
            checkpoint.stableID = item.id
            checkpoint.asOf = item.asOf
            checkpoint.knowledgeCutoff = item.knowledgeCutoff
            checkpoint.scopeVersion = item.scopeVersion
            checkpoint.calculationVersion = item.calculationVersion
            checkpoint.currencyCoverageJSON = item.currencyCoverageJSON
            checkpoint.totalAssets = item.totalAssets
            checkpoint.totalLiabilities = item.totalLiabilities
            checkpoint.netWorth = item.netWorth
            checkpoint.completenessRaw = item.completenessRaw
            checkpoint.reasonsJSON = item.reasonsJSON
            checkpoint.statusRaw = item.statusRaw
            checkpoint.supersedesID = item.supersedesID
            checkpoint.createdAt = item.createdAt
            checkpoint.itemsJSON = encodeVerifiedItems(verifiedItemsByCheckpoint[item.id] ?? [])
            netWorthVerifiedCheckpoints[item.id] = checkpoint
        }

        if save {
            try context.save()
        }
        return BackupImportSummary(
            books: package.books.count,
            accounts: package.accounts.count,
            categories: package.categories.count,
            transactions: package.transactions.count,
            budgets: package.budgets.count,
            savingsGoals: package.savingsGoals.count,
            recurringRules: package.recurringRules.count,
            physicalAssets: package.physicalAssets.count,
            receivableAssets: package.receivableAssets.count,
            liabilities: package.liabilities.count,
            aiChatSessions: package.aiChatSessions.count,
            aiChatMessages: package.aiChatMessages.count,
            aiMemories: package.aiMemories.count,
            aiRequestRuns: package.aiRequestRuns.count,
            aiRequestEvents: package.aiRequestEvents.count,
            aiReportSchedules: package.aiReportSchedules.count,
            budgetPlansV2: package.budgetPlansV2.count,
            reports: package.reports.count,
            accountBalanceCheckpoints: package.accountBalanceCheckpoints.count,
            verifiedNetWorthCheckpoints: package.netWorthVerifiedCheckpoints.count
        )
    }

    private static func deleteAllModels(from context: ModelContext) throws {
        // Delete dependent records first so relationship nullification never
        // leaves an old child attached to a newly restored parent.
        try deleteAll(AIRequestEventRecord.self, from: context)
        try deleteAll(AIRequestRunRecord.self, from: context)
        try deleteAll(AIReportScheduleRecord.self, from: context)
        try deleteAll(AIChatMessage.self, from: context)
        try deleteAll(RecurringOccurrence.self, from: context)
        try deleteAll(AssetRefundAllocation.self, from: context)
        try deleteAll(AssetTransactionLink.self, from: context)
        try deleteAll(AssetUsageEvent.self, from: context)
        try deleteAll(AssetEvent.self, from: context)
        try deleteAll(AssetValuation.self, from: context)
        try deleteAll(ReceivableRecovery.self, from: context)
        try deleteAll(BudgetCommitmentOccurrenceRecord.self, from: context)
        try deleteAll(BudgetChangeEventRecord.self, from: context)
        try deleteAll(BudgetCycleOverrideRecord.self, from: context)
        try deleteAll(BudgetPlanRevisionRecord.self, from: context)
        try deleteAll(Budget.self, from: context)
        try deleteAll(MoneyTransaction.self, from: context)

        try deleteAll(AIMemoryRecord.self, from: context)
        try deleteAll(AIChatSession.self, from: context)
        try deleteAll(RecurringRule.self, from: context)
        try deleteAll(PhysicalAsset.self, from: context)
        try deleteAll(ReceivableAsset.self, from: context)
        try deleteAll(LiabilityProfile.self, from: context)
        try deleteAll(NetWorthSnapshot.self, from: context)
        try deleteAll(ReportRecord.self, from: context)
        try deleteAll(AccountBalanceCheckpointRecord.self, from: context)
        try deleteAll(NetWorthVerifiedCheckpointRecord.self, from: context)
        try deleteAll(SavingsGoal.self, from: context)
        try deleteAll(BudgetPlanRecord.self, from: context)
        try deleteAll(Account.self, from: context)
        try deleteAll(Book.self, from: context)
        try deleteAll(TxCategory.self, from: context)
        try deleteAll(Tag.self, from: context)
    }

    private static func deleteAll<T: PersistentModel>(
        _ type: T.Type,
        from context: ModelContext
    ) throws {
        let models = try context.fetch(FetchDescriptor<T>())
        for model in models {
            context.delete(model)
        }
    }

    private static func importArchive(
        _ data: Data,
        mode: BackupImportMode,
        into context: ModelContext
    ) throws -> BackupImportSummary {
        let entries: [ZipArchive.Entry]
        do {
            entries = try ZipArchive.decode(data)
        } catch {
            throw BackupStoreError.malformedArchive
        }
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        guard let manifestData = byPath["manifest.json"] else {
            throw BackupStoreError.malformedArchive
        }

        // Android's full backup has a different manifest schema and stores a
        // real SQLite database. Detect it before decoding the iOS manifest so
        // the two archive contracts remain independently strict.
        if let object = try? JSONSerialization.jsonObject(with: manifestData),
           let rawManifest = object as? [String: Any],
           rawManifest["format"] as? String == AndroidBackupImporter.archiveFormat {
            return try importAndroidArchive(
                byPath: byPath,
                manifest: rawManifest,
                mode: mode,
                into: context
            )
        }

        let manifest: ArchiveManifest
        do {
            manifest = try decoder.decode(ArchiveManifest.self, from: manifestData)
        } catch {
            throw BackupStoreError.malformedArchive
        }
        guard manifest.format == archiveFormat,
              manifest.version >= 1,
              manifest.version <= archiveVersion,
              manifest.schemaVersion <= FeimiaoBackupPackage.currentSchemaVersion,
              manifest.database == archiveDatabasePath,
              byPath[archiveDatabasePath] != nil else {
            // Android's raw SQLite archive deliberately has a different
            // manifest contract; never attempt to feed it to SwiftData JSON.
            throw BackupStoreError.unsupportedArchiveFormat
        }

        let payloadNames = Set(byPath.keys.filter { $0 != "manifest.json" })
        guard Set(manifest.checksums.keys) == payloadNames,
              payloadNames.allSatisfy(isSupportedPayloadPath) else {
            throw BackupStoreError.malformedArchive
        }
        for (path, checksum) in manifest.checksums {
            guard let payload = byPath[path], sha256(payload) == checksum else {
                throw BackupStoreError.malformedArchive
            }
        }

        guard let databaseData = byPath[archiveDatabasePath] else {
            throw BackupStoreError.malformedArchive
        }
        return try importArchivePayload(
            databaseData: databaseData,
            byPath: byPath,
            mode: mode,
            into: context
        )
    }

    private static func importAndroidArchive(
        byPath: [String: Data],
        manifest: [String: Any],
        mode: BackupImportMode,
        into context: ModelContext
    ) throws -> BackupImportSummary {
        guard let versionNumber = manifest["version"] as? NSNumber else {
            throw BackupStoreError.malformedArchive
        }
        let version = versionNumber.intValue
        guard (1...2).contains(version) else {
            throw BackupStoreError.malformedArchive
        }
        if let databaseVersion = manifest["databaseVersion"],
           !(databaseVersion is NSNumber) {
            throw BackupStoreError.malformedArchive
        }
        guard let rawChecksums = manifest["checksums"] as? [String: Any],
              !rawChecksums.isEmpty else {
            throw BackupStoreError.malformedArchive
        }
        var checksums: [String: String] = [:]
        for (path, value) in rawChecksums {
            guard let checksum = value as? String,
                  isAndroidPayloadPath(path) else {
                throw BackupStoreError.malformedArchive
            }
            checksums[path] = checksum
        }
        guard checksums["database/qingji.db"] != nil else {
            throw BackupStoreError.malformedArchive
        }

        let payloadNames = Set(byPath.keys.filter { $0 != "manifest.json" })
        guard payloadNames == Set(checksums.keys) else {
            throw BackupStoreError.malformedArchive
        }
        for (path, checksum) in checksums {
            guard let payload = byPath[path], sha256(payload) == checksum else {
                throw BackupStoreError.malformedArchive
            }
        }
        guard let databaseData = byPath["database/qingji.db"] else {
            throw BackupStoreError.malformedArchive
        }

        let databaseVersion = (manifest["databaseVersion"] as? NSNumber)?.intValue ?? 0
        let exportedAt = (manifest["createdAt"] as? String).flatMap { value in
            ISO8601DateFormatter().date(from: value)
        } ?? Date()
        let canonicalData = try AndroidBackupImporter.canonicalData(
            from: databaseData,
            databaseVersion: databaseVersion,
            exportedAt: exportedAt
        )
        return try importArchivePayload(
            databaseData: canonicalData,
            byPath: byPath,
            mode: mode,
            into: context
        )
    }

    private static func importArchivePayload(
        databaseData: Data,
        byPath: [String: Data],
        mode: BackupImportMode,
        into context: ModelContext
    ) throws -> BackupImportSummary {
        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("feimiao-backup-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        let previousAttachmentPaths = (try? AttachmentStore.allRelativePaths()) ?? []
        var stagedAttachments: [(relativePath: String, url: URL)] = []
        for path in byPath.keys.sorted() {
            let relativePath: String
            if path.hasPrefix("receipts/") {
                relativePath = String(path.dropFirst("receipts/".count))
            } else if path.hasPrefix("asset_media/") {
                // Keep the namespace so asset photo/invoice references survive
                // a round trip through the iOS receipts container.
                relativePath = path
            } else {
                continue
            }
            guard AttachmentStore.isSafeRelativePath(relativePath),
                  let payload = byPath[path] else {
                throw BackupStoreError.malformedArchive
            }
            let stagedURL = stagingRoot.appendingPathComponent(relativePath, isDirectory: false)
            try FileManager.default.createDirectory(
                at: stagedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payload.write(to: stagedURL, options: .atomic)
            stagedAttachments.append((relativePath, stagedURL))
        }

        var previousAttachments: [(relativePath: String, data: Data?)] = []
        do {
            // Keep model changes pending until every checked attachment is
            // installed. A failure therefore leaves both stores unchanged.
            let summary = try importData(databaseData, into: context, mode: mode, save: false)
            for attachment in stagedAttachments {
                let previous = AttachmentStore.url(for: attachment.relativePath)
                    .flatMap { try? Data(contentsOf: $0) }
                previousAttachments.append((attachment.relativePath, previous))
                try AttachmentStore.installImportedFile(
                    at: attachment.url,
                    relativePath: attachment.relativePath
                )
            }
            try context.save()
            if mode == .replace {
                let incomingPaths = Set(stagedAttachments.map(\.relativePath))
                for path in previousAttachmentPaths where !incomingPaths.contains(path) {
                    AttachmentStore.remove(path)
                }
            }
            return summary
        } catch {
            context.rollback()
            for previous in previousAttachments {
                if let data = previous.data {
                    try? AttachmentStore.writeImported(data: data, relativePath: previous.relativePath)
                } else {
                    AttachmentStore.remove(previous.relativePath)
                }
            }
            throw error
        }
    }

    private static func isAndroidPayloadPath(_ path: String) -> Bool {
        guard ZipArchive.isSafePath(path) else { return false }
        return path == "database/qingji.db"
            || path.hasPrefix("receipts/")
            || path.hasPrefix("asset_media/")
    }

    private static func isSupportedPayloadPath(_ path: String) -> Bool {
        guard ZipArchive.isSafePath(path) else { return false }
        return path == archiveDatabasePath
            || path.hasPrefix("receipts/")
            || path.hasPrefix("asset_media/")
    }

    private static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4b
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func encodeVerifiedItems(_ values: [BackupNetWorthVerifiedCheckpointItem]) -> String {
        guard let data = try? encoder.encode(values) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeVerifiedItems(
        _ raw: String,
        fallbackCheckpointID: UUID
    ) -> [BackupNetWorthVerifiedCheckpointItem] {
        guard let data = raw.data(using: .utf8),
              let values = try? decoder.decode([BackupNetWorthVerifiedCheckpointItem].self, from: data) else {
            return []
        }
        return values.map { item in
            guard item.checkpointID != fallbackCheckpointID else { return item }
            return BackupNetWorthVerifiedCheckpointItem(
                checkpointID: fallbackCheckpointID,
                objectType: item.objectType,
                objectUUID: item.objectUUID,
                confirmedAmount: item.confirmedAmount,
                currencyCode: item.currencyCode,
                valueEffectiveAt: item.valueEffectiveAt,
                valueSource: item.valueSource,
                quality: item.quality
            )
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
