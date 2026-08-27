import Foundation
import SwiftData
import QingJiCore

/// 存钱目标。金额和进度独立保存，便于跨平台备份以及以后关联物品资产。
@Model
final class SavingsGoal {
    var stableID: UUID = UUID()
    var name: String = ""
    var emoji: String = "🐷"
    var targetAmount: Decimal = 0
    var savedAmount: Decimal = 0
    var currencyCode: String = "CNY"
    var linkedAssetID: UUID? = nil
    var note: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: savedAmount).doubleValue /
                       NSDecimalNumber(decimal: targetAmount).doubleValue, 0), 1)
    }

    var isCompleted: Bool { targetAmount > 0 && savedAmount >= targetAmount }

    init(
        name: String,
        emoji: String = "🐷",
        targetAmount: Decimal,
        savedAmount: Decimal = 0,
        currencyCode: String = "CNY",
        linkedAssetID: UUID? = nil,
        note: String = "",
        stableID: UUID = UUID()
    ) {
        self.stableID = stableID
        self.name = name
        self.emoji = emoji
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.currencyCode = currencyCode
        self.linkedAssetID = linkedAssetID
        self.note = note
    }
}

/// 定时记账规则。规则只保存稳定 ID，不依赖 Android 自增主键。
@Model
final class RecurringRule {
    var stableID: UUID = UUID()
    var bookID: UUID? = nil
    var kindRaw: String = TransactionKind.expense.rawValue
    var amount: Decimal = 0
    var categoryKey: String? = nil
    var accountID: UUID? = nil
    var toAccountID: UUID? = nil
    var note: String = ""
    var periodRaw: String = RecurringPeriod.monthly.rawValue
    var startDate: Date = Date()
    var nextDueDate: Date = Date()
    var endDate: Date? = nil
    var totalCount: Int? = nil
    var generatedCount: Int = 0
    var anchorDay: Int = 0
    var isEnabled: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var period: RecurringPeriod {
        get { RecurringPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

    var isCompleted: Bool {
        if let totalCount, totalCount > 0, generatedCount >= totalCount { return true }
        guard let endDate else { return false }
        return nextDueDate > Calendar.current.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: endDate
        ) ?? endDate
    }

    init(
        amount: Decimal,
        kind: TransactionKind,
        bookID: UUID?,
        categoryKey: String? = nil,
        accountID: UUID?,
        toAccountID: UUID? = nil,
        note: String = "",
        period: RecurringPeriod,
        startDate: Date,
        firstDueDate: Date? = nil,
        endDate: Date? = nil,
        totalCount: Int? = nil,
        stableID: UUID = UUID()
    ) {
        self.stableID = stableID
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.bookID = bookID
        self.categoryKey = categoryKey
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.note = note
        self.periodRaw = period.rawValue
        self.startDate = startDate
        self.nextDueDate = firstDueDate ?? startDate
        self.endDate = endDate
        self.totalCount = totalCount
        self.anchorDay = Calendar.current.component(.day, from: startDate)
    }
}

/// 定时规则的幂等执行记录。相同 rule + dueDate 只能物化一次。
@Model
final class RecurringOccurrence {
    var stableID: UUID = UUID()
    var ruleID: UUID = UUID()
    var dueDate: Date = Date()
    var transactionID: UUID? = nil
    var createdAt: Date = Date()

    init(ruleID: UUID, dueDate: Date, transactionID: UUID? = nil, stableID: UUID = UUID()) {
        self.stableID = stableID
        self.ruleID = ruleID
        self.dueDate = dueDate
        self.transactionID = transactionID
    }
}

enum PhysicalAssetKind: String, CaseIterable, Hashable, Identifiable {
    case digital
    case appliance
    case vehicle
    case property
    case valuables
    case collectibles
    case tools
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .digital: return "数码"
        case .appliance: return "家电"
        case .vehicle: return "车辆"
        case .property: return "房产"
        case .valuables: return "贵重物品"
        case .collectibles: return "收藏品"
        case .tools: return "工具设备"
        case .other: return "其他"
        }
    }
}

enum PhysicalAssetLifecycle: String, CaseIterable, Hashable, Identifiable {
    case owned
    case idle
    case sold
    case returned
    case disposed
    case lost
    case gifted
    case archived

    var id: String { rawValue }
    var label: String {
        switch self {
        case .owned: return "在用"
        case .idle: return "闲置"
        case .sold: return "已出售"
        case .returned: return "已退货"
        case .disposed: return "已报废"
        case .lost: return "已丢失"
        case .gifted: return "已赠送"
        case .archived: return "已归档"
        }
    }
}

/// 物品资产的资料和当前估值；生命周期变化通过 AssetEvent 追加记录。
@Model
final class PhysicalAsset {
    var stableID: UUID = UUID()
    var bookID: UUID? = nil
    var name: String = ""
    var kindRaw: String = PhysicalAssetKind.other.rawValue
    var lifecycleRaw: String = PhysicalAssetLifecycle.owned.rawValue
    /// Android stores these dimensions independently from the legacy lifecycle
    /// field. Keeping them as raw strings preserves forward-compatible state.
    var economicStatusRaw: String = "owned"
    var usageStatusRaw: String = "active"
    var visibilityStatusRaw: String = "active"
    var inclusionQualityRaw: String = "confirmed"
    var sourceTypeRaw: String = "historical_existing"
    var acquisitionCostSourceRaw: String = "manual"
    var purchasePrice: Decimal = 0
    var currentValue: Decimal = 0
    var currencyCode: String = "CNY"
    var purchaseDate: Date? = nil
    var brand: String = ""
    var model: String = ""
    var location: String = ""
    var warrantyUntil: Date? = nil
    var usageTrackingEnabled: Bool = false
    var usageCount: Int = 0
    var savingsGoalID: UUID? = nil
    var photoPath: String = ""
    var thumbnailPath: String = ""
    var invoicePath: String = ""
    var depreciationMethod: String = ""
    var depreciationBase: Decimal = 0
    var salvageValue: Decimal = 0
    var usefulLifeMonths: Int = 0
    var depreciationStartDate: Date? = nil
    var depreciationPaused: Bool = false
    var note: String = ""
    var includeInNetWorth: Bool = true
    var isDeleted: Bool = false
    var endedAt: Date? = nil
    var archivedAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: PhysicalAssetKind {
        get { PhysicalAssetKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var lifecycle: PhysicalAssetLifecycle {
        get { PhysicalAssetLifecycle(rawValue: lifecycleRaw) ?? .owned }
        set { lifecycleRaw = newValue.rawValue }
    }

    init(
        name: String,
        kind: PhysicalAssetKind = .other,
        purchasePrice: Decimal = 0,
        currentValue: Decimal = 0,
        currencyCode: String = "CNY",
        bookID: UUID? = nil,
        stableID: UUID = UUID()
    ) {
        self.stableID = stableID
        self.name = name
        self.kindRaw = kind.rawValue
        self.purchasePrice = purchasePrice
        self.currentValue = currentValue
        self.currencyCode = currencyCode
        self.bookID = bookID
    }
}

enum AssetEventKind: String, CaseIterable, Hashable, Identifiable {
    case created
    case edited
    case valuationUpdated
    case purchased
    case sold
    case returned
    case disposed
    case lost
    case gifted
    case archived
    case restored
    case usageAdded
    case depreciation
    case transactionLinked = "transaction_linked"
    case transactionUnlinked = "transaction_unlinked"
    case costLinked = "cost_linked"
    case costUnlinked = "cost_unlinked"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .created: return "新增资产"
        case .edited: return "编辑资料"
        case .valuationUpdated: return "更新估值"
        case .purchased: return "新购买"
        case .sold: return "出售资产"
        case .returned: return "退货"
        case .disposed: return "报废"
        case .lost: return "标记丢失"
        case .gifted: return "赠送"
        case .archived: return "归档"
        case .restored: return "恢复"
        case .usageAdded: return "使用次数"
        case .depreciation: return "折旧"
        case .transactionLinked: return "关联账单"
        case .transactionUnlinked: return "解除账单关联"
        case .costLinked: return "关联持有成本"
        case .costUnlinked: return "解除持有成本"
        }
    }
}

@Model
final class AssetEvent {
    var stableID: UUID = UUID()
    var assetID: UUID = UUID()
    var kindRaw: String = AssetEventKind.created.rawValue
    var occurredAt: Date = Date()
    var value: Decimal? = nil
    var note: String = ""
    var metadataJSON: String = ""
    var createdAt: Date = Date()

    var kind: AssetEventKind {
        get { AssetEventKind(rawValue: kindRaw) ?? .created }
        set { kindRaw = newValue.rawValue }
    }

    init(assetID: UUID, kind: AssetEventKind, occurredAt: Date = Date(), value: Decimal? = nil, note: String = "", metadataJSON: String = "") {
        self.assetID = assetID
        self.kindRaw = kind.rawValue
        self.occurredAt = occurredAt
        self.value = value
        self.note = note
        self.metadataJSON = metadataJSON
    }
}

/// 物品使用次数的可撤销审计事件。Android 用独立表保存增量和 reversal_of，
/// 不能把它压缩成一个计数后丢掉历史，否则跨端恢复后无法复核。
@Model
final class AssetUsageEvent {
    var stableID: UUID = UUID()
    var assetID: UUID = UUID()
    var countDelta: Int = 0
    var reversalOfID: UUID? = nil
    var occurredAt: Date = Date()
    var note: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        assetID: UUID,
        countDelta: Int,
        reversalOfID: UUID? = nil,
        occurredAt: Date = Date(),
        note: String = "",
        stableID: UUID = UUID()
    ) {
        self.stableID = stableID
        self.assetID = assetID
        self.countDelta = countDelta
        self.reversalOfID = reversalOfID
        self.occurredAt = occurredAt
        self.note = note
    }
}

enum AssetTransactionLinkType: String, CaseIterable, Hashable, Identifiable {
    case sourceTransaction = "source_transaction"
    case purchaseTransaction = "purchase_transaction"
    case saleAccountMovement = "sale_account_movement"
    case maintenance
    case accessory
    case insurance
    case otherCost = "other_cost"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .sourceTransaction: return "购买账单"
        case .purchaseTransaction: return "购置支出"
        case .saleAccountMovement: return "出售到账"
        case .maintenance: return "维修保养"
        case .accessory: return "配件"
        case .insurance: return "保险"
        case .otherCost: return "其他支出"
        }
    }
}

@Model
final class AssetTransactionLink {
    var stableID: UUID = UUID()
    var assetID: UUID = UUID()
    var assetObjectType: String = "physical"
    var transactionID: UUID = UUID()
    var linkTypeRaw: String = AssetTransactionLinkType.sourceTransaction.rawValue
    var amount: Decimal = 0
    var allocatedGrossCents: Int = 0
    var allocatedRefundCents: Int = 0
    var costQualityRaw: String = "partial"
    var note: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        assetID: UUID,
        transactionID: UUID,
        linkTypeRaw: String = AssetTransactionLinkType.sourceTransaction.rawValue,
        amount: Decimal = 0,
        stableID: UUID = UUID()
    ) {
        self.stableID = stableID
        self.assetID = assetID
        self.transactionID = transactionID
        self.linkTypeRaw = linkTypeRaw
        self.amount = amount
    }
}

@Model
final class AssetRefundAllocation {
    var stableID: UUID = UUID()
    var assetTransactionLinkID: UUID = UUID()
    var refundTransactionID: UUID = UUID()
    var allocatedRefundCents: Int = 0
    var statusRaw: String = "active"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        assetTransactionLinkID: UUID,
        refundTransactionID: UUID,
        allocatedRefundCents: Int,
        statusRaw: String = "active",
        stableID: UUID = UUID()
    ) {
        self.stableID = stableID
        self.assetTransactionLinkID = assetTransactionLinkID
        self.refundTransactionID = refundTransactionID
        self.allocatedRefundCents = allocatedRefundCents
        self.statusRaw = statusRaw
    }
}

@Model
final class AssetValuation {
    var stableID: UUID = UUID()
    var assetID: UUID = UUID()
    var value: Decimal = 0
    var sourceRaw: String = "manual"
    var valuedAt: Date = Date()
    var note: String = ""
    var createdAt: Date = Date()

    init(assetID: UUID, value: Decimal, sourceRaw: String = "manual", valuedAt: Date = Date(), note: String = "") {
        self.assetID = assetID
        self.value = value
        self.sourceRaw = sourceRaw
        self.valuedAt = valuedAt
        self.note = note
    }
}

enum ReceivableKind: String, CaseIterable, Hashable, Identifiable {
    case rentalDeposit
    case loanOut
    case accountReceivable
    case prepaidCard
    case membershipCard
    case securityDeposit
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .rentalDeposit: return "租房押金"
        case .loanOut: return "借出款"
        case .accountReceivable: return "应收款"
        case .prepaidCard: return "预付卡余额"
        case .membershipCard: return "会员卡余额"
        case .securityDeposit: return "保证金"
        case .other: return "其他权益"
        }
    }
}

enum ReceivableLifecycle: String, CaseIterable, Hashable, Identifiable {
    case active
    case partiallyRecovered
    case recovered
    case lost
    case archived

    var id: String { rawValue }
    var label: String {
        switch self {
        case .active: return "待收回"
        case .partiallyRecovered: return "部分收回"
        case .recovered: return "已收回"
        case .lost: return "已损失"
        case .archived: return "已归档"
        }
    }
}

@Model
final class ReceivableAsset {
    var stableID: UUID = UUID()
    var bookID: UUID? = nil
    var name: String = ""
    var kindRaw: String = ReceivableKind.other.rawValue
    var lifecycleRaw: String = ReceivableLifecycle.active.rawValue
    var economicStatusRaw: String = "active"
    var visibilityStatusRaw: String = "active"
    var inclusionQualityRaw: String = "confirmed"
    var originalAmount: Decimal = 0
    var remainingAmount: Decimal = 0
    var currencyCode: String = "CNY"
    var counterparty: String = ""
    var dueDate: Date? = nil
    var includeInNetWorth: Bool = true
    var note: String = ""
    var isDeleted: Bool = false
    var endedAt: Date? = nil
    var archivedAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: ReceivableKind {
        get { ReceivableKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var lifecycle: ReceivableLifecycle {
        get { ReceivableLifecycle(rawValue: lifecycleRaw) ?? .active }
        set { lifecycleRaw = newValue.rawValue }
    }

    init(name: String, originalAmount: Decimal, kind: ReceivableKind = .other, bookID: UUID? = nil, currencyCode: String = "CNY", stableID: UUID = UUID()) {
        self.stableID = stableID
        self.name = name
        self.originalAmount = originalAmount
        self.remainingAmount = originalAmount
        self.kindRaw = kind.rawValue
        self.bookID = bookID
        self.currencyCode = currencyCode
    }
}

@Model
final class ReceivableRecovery {
    var stableID: UUID = UUID()
    var receivableID: UUID = UUID()
    var amount: Decimal = 0
    var recoveredAt: Date = Date()
    var targetAccountID: UUID? = nil
    var transactionID: UUID? = nil
    var note: String = ""
    var createdAt: Date = Date()

    init(receivableID: UUID, amount: Decimal, recoveredAt: Date = Date(), targetAccountID: UUID? = nil, transactionID: UUID? = nil, note: String = "") {
        self.receivableID = receivableID
        self.amount = amount
        self.recoveredAt = recoveredAt
        self.targetAccountID = targetAccountID
        self.transactionID = transactionID
        self.note = note
    }
}

enum LiabilityKind: String, CaseIterable, Hashable, Identifiable {
    case creditCard
    case mortgage
    case carLoan
    case consumerLoan
    case personalBorrow
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .creditCard: return "信用卡"
        case .mortgage: return "房贷"
        case .carLoan: return "车贷"
        case .consumerLoan: return "消费贷"
        case .personalBorrow: return "个人借入"
        case .other: return "其他负债"
        }
    }
}

enum LiabilityLifecycle: String, CaseIterable, Hashable, Identifiable {
    case active
    case paidOff
    case paused
    case archived

    var id: String { rawValue }
    var label: String {
        switch self {
        case .active: return "还款中"
        case .paidOff: return "已结清"
        case .paused: return "暂停"
        case .archived: return "已归档"
        }
    }
}

@Model
final class LiabilityProfile {
    var stableID: UUID = UUID()
    var accountID: UUID? = nil
    var repaymentAccountID: UUID? = nil
    var kindRaw: String = LiabilityKind.other.rawValue
    var lifecycleRaw: String = LiabilityLifecycle.active.rawValue
    var originalPrincipal: Decimal = 0
    var currentPrincipal: Decimal = 0
    var currencyCode: String = "CNY"
    var counterparty: String = ""
    var annualRate: Decimal? = nil
    var startDate: Date? = nil
    var dueDate: Date? = nil
    var statementDay: Int? = nil
    var paymentDay: Int? = nil
    var creditLimit: Decimal? = nil
    var note: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: LiabilityKind {
        get { LiabilityKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var lifecycle: LiabilityLifecycle {
        get { LiabilityLifecycle(rawValue: lifecycleRaw) ?? .active }
        set { lifecycleRaw = newValue.rawValue }
    }

    init(accountID: UUID? = nil, kind: LiabilityKind = .other, originalPrincipal: Decimal = 0, currentPrincipal: Decimal = 0, currencyCode: String = "CNY") {
        self.accountID = accountID
        self.kindRaw = kind.rawValue
        self.originalPrincipal = originalPrincipal
        self.currentPrincipal = currentPrincipal
        self.currencyCode = currencyCode
    }
}

enum NetWorthSnapshotQuality: String, CaseIterable, Hashable, Identifiable {
    case available
    case partial
    case legacyUnverified

    var id: String { rawValue }
    var label: String {
        switch self {
        case .available: return "完整"
        case .partial: return "部分可核对"
        case .legacyUnverified: return "历史未核对"
        }
    }
}

/// 净资产快照使用组件字段而不是只保存合计，便于解释数值和显示质量状态。
@Model
final class NetWorthSnapshot {
    var stableID: UUID = UUID()
    var asOf: Date = Date()
    var knowledgeCutoff: Date = Date()
    var scopeKey: String = "global"
    var scopeVersion: Int = 1
    var calculationVersion: Int = 1
    var baseCurrency: String = "CNY"
    var coveredCurrenciesJSON: String = "[\"CNY\"]"
    var uncoveredCurrenciesJSON: String = "[]"
    var qualityRaw: String = NetWorthSnapshotQuality.legacyUnverified.rawValue
    var cashAssets: Decimal = 0
    var investmentAssets: Decimal = 0
    var physicalAssets: Decimal = 0
    var receivableAssets: Decimal = 0
    var liabilities: Decimal = 0
    var reasonsJSON: String = "[]"
    var causesJSON: String = "[]"
    var provisional: Bool = false
    var createdAt: Date = Date()

    var quality: NetWorthSnapshotQuality {
        get { NetWorthSnapshotQuality(rawValue: qualityRaw) ?? .legacyUnverified }
        set { qualityRaw = newValue.rawValue }
    }

    var totalAssets: Decimal { cashAssets + investmentAssets + physicalAssets + receivableAssets }
    var netWorth: Decimal { totalAssets - liabilities }

    init(asOf: Date = Date(), baseCurrency: String = "CNY") {
        self.asOf = asOf
        self.knowledgeCutoff = Date()
        self.baseCurrency = baseCurrency
    }
}
