import Foundation
import SwiftData
import QingJiCore

/// 物品资产的写入边界。价值变化和生命周期变化都留下事件，便于详情页审计与备份。
enum AssetStore {
    enum Error: LocalizedError {
        case invalidName
        case invalidAmount
        case invalidWarranty
        case endedAsset
        case invalidTransaction
        case duplicateTransaction
        case allocationInvalid

        var errorDescription: String? {
            switch self {
            case .invalidName: return "资产名称不能为空。"
            case .invalidAmount: return "资产金额不能为负。"
            case .invalidWarranty: return "保修到期日不能早于购买日期。"
            case .endedAsset: return "已出售、退货、报废、丢失或赠送的资产不能继续编辑价值。"
            case .invalidTransaction: return "只能关联同账本、同币种的普通支出。"
            case .duplicateTransaction: return "这笔支出已经关联了其他物品或当前资产。"
            case .allocationInvalid: return "物品分配金额超过订单可用金额。"
            }
        }
    }

    static func visibleAssets(in context: ModelContext) throws -> [PhysicalAsset] {
        try context.fetch(FetchDescriptor<PhysicalAsset>(sortBy: [
            SortDescriptor(\PhysicalAsset.updatedAt, order: .reverse)
        ])).filter { !$0.isDeleted && $0.lifecycle != .archived }
    }

    static func events(for asset: PhysicalAsset, in context: ModelContext) throws -> [AssetEvent] {
        try context.fetch(FetchDescriptor<AssetEvent>(sortBy: [
            SortDescriptor(\AssetEvent.occurredAt, order: .reverse)
        ])).filter { $0.assetID == asset.stableID }
    }

    static func usageEvents(for asset: PhysicalAsset, in context: ModelContext) throws -> [AssetUsageEvent] {
        try context.fetch(FetchDescriptor<AssetUsageEvent>(sortBy: [
            SortDescriptor(\AssetUsageEvent.occurredAt, order: .reverse)
        ])).filter { $0.assetID == asset.stableID }
    }

    /// 使用与 Android 相同的“购置成本 + 后续净支出”口径计算资产指标。
    /// 有精确分摊记录时优先使用分；没有关联记录的历史/手工资产回退到
    /// `purchasePrice`，不会把未知成本伪装成 0。
    static func metrics(
        for asset: PhysicalAsset,
        in context: ModelContext,
        asOf: Date = Date()
    ) throws -> PhysicalAssetMetrics {
        let links = try context.fetch(FetchDescriptor<AssetTransactionLink>())
            .filter { $0.assetID == asset.stableID }
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let records = transactions.map(\.record)
        let transactionByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.stableID, $0) })
        var acquisition = Decimal.zero
        var additional = Decimal.zero
        if links.isEmpty {
            acquisition = MoneyNormalization.roundToCents(asset.purchasePrice)
        } else {
            for link in links {
                if let transaction = transactionByID[link.transactionID],
                   link.linkTypeRaw != AssetTransactionLinkType.sourceTransaction.rawValue,
                   link.linkTypeRaw != AssetTransactionLinkType.purchaseTransaction.rawValue {
                    let net = LedgerPolicy.refundStatus(
                        for: transaction.record,
                        in: records
                    ).remainingAmount
                    additional += max(net, Decimal.zero)
                    continue
                }
                let gross = link.allocatedGrossCents > 0
                    ? Decimal(link.allocatedGrossCents) / Decimal(100)
                    : link.amount
                let refund = Decimal(link.allocatedRefundCents) / Decimal(100)
                let net = max(gross - refund, Decimal.zero)
                switch link.linkTypeRaw {
                case AssetTransactionLinkType.sourceTransaction.rawValue,
                     AssetTransactionLinkType.purchaseTransaction.rawValue:
                    acquisition += net
                default:
                    additional += net
                }
            }
        }
        if acquisition == .zero && asset.purchasePrice > .zero {
            acquisition = MoneyNormalization.roundToCents(asset.purchasePrice)
        }
        let hasValuation = try context.fetch(FetchDescriptor<AssetValuation>())
            .contains { $0.assetID == asset.stableID }
        let calendar = Calendar.current
        return AssetMetrics.resolve(
            PhysicalAssetMetricInput(
                netAcquisitionCost: MoneyNormalization.roundToCents(acquisition),
                additionalNetCost: MoneyNormalization.roundToCents(additional),
                currentNetValue: MoneyNormalization.roundToCents(asset.currentValue),
                purchasedAt: asset.purchaseDate,
                endedAt: asset.endedAt,
                isEconomicallyOwned: asset.lifecycle == .owned || asset.lifecycle == .idle,
                hasKnownValuation: hasValuation,
                hasComparableCurrency: asset.currencyCode.uppercased() == "CNY",
                usageTrackingEnabled: asset.usageTrackingEnabled,
                usageCount: asset.usageCount
            ),
            asOf: asOf,
            calendar: calendar
        )
    }

    static func costTransactions(
        for asset: PhysicalAsset,
        in context: ModelContext,
        query: String = ""
    ) throws -> [MoneyTransaction] {
        guard !asset.isDeleted,
              asset.lifecycle == .owned || asset.lifecycle == .idle,
              let bookID = asset.bookID else { return [] }
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allLinks = try context.fetch(FetchDescriptor<AssetTransactionLink>())
        let linkedTransactionIDs = Set(allLinks.map(\.transactionID))
        let records = try context.fetch(FetchDescriptor<MoneyTransaction>())
        return records
            .filter { transaction in
                transaction.kind == .expense &&
                transaction.amount > 0 &&
                transaction.refundOfID == nil &&
                !transaction.isExcluded &&
                transaction.book?.stableID == bookID &&
                transaction.currencyCode == asset.currencyCode &&
                !linkedTransactionIDs.contains(transaction.stableID) &&
                (normalized.isEmpty ||
                 transaction.note.lowercased().contains(normalized) ||
                 transaction.category?.name.lowercased().contains(normalized) == true ||
                 transaction.amount.description.contains(normalized))
            }
            .sorted { $0.date > $1.date }
    }

    /// 将一笔已有支出作为物品的后续持有成本关联；关联本身不改变账单。
    @discardableResult
    static func linkCost(
        _ asset: PhysicalAsset,
        transaction: MoneyTransaction,
        type: AssetTransactionLinkType,
        in context: ModelContext
    ) throws -> AssetTransactionLink {
        guard type != .sourceTransaction,
              type != .purchaseTransaction,
              type != .saleAccountMovement else { throw Error.invalidTransaction }
        guard try costTransactions(for: asset, in: context)
            .contains(where: { $0.stableID == transaction.stableID }) else {
            throw Error.invalidTransaction
        }
        let records = try context.fetch(FetchDescriptor<MoneyTransaction>()).map(\.record)
        let net = LedgerPolicy.refundStatus(
            for: transaction.record,
            in: records
        ).remainingAmount
        guard net > 0 else { throw Error.invalidTransaction }
        let link = AssetTransactionLink(
            assetID: asset.stableID,
            transactionID: transaction.stableID,
            linkTypeRaw: type.rawValue,
            amount: MoneyNormalization.roundToCents(net)
        )
        link.costQualityRaw = AssetAllocationCostQuality.exact.rawValue
        link.note = type.label
        context.insert(link)
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .costLinked,
            value: link.amount,
            note: "\(type.label) · \(transaction.note)"
        ))
        try context.save()
        return link
    }

    static func unlinkCost(
        _ link: AssetTransactionLink,
        in context: ModelContext
    ) throws {
        guard link.linkTypeRaw != AssetTransactionLinkType.sourceTransaction.rawValue,
              link.linkTypeRaw != AssetTransactionLinkType.purchaseTransaction.rawValue,
              link.linkTypeRaw != AssetTransactionLinkType.saleAccountMovement.rawValue else {
            throw Error.invalidTransaction
        }
        let assetID = link.assetID
        context.delete(link)
        context.insert(AssetEvent(
            assetID: assetID,
            kind: .costUnlinked,
            note: "解除持有成本关联"
        ))
        try context.save()
    }

    /// 给多件物品订单建立购置成本分配，遵守“毛额、退款、净额均不能超订单”规则。
    @discardableResult
    static func linkPurchaseAllocation(
        _ asset: PhysicalAsset,
        transaction: MoneyTransaction,
        grossCents: Int,
        refundCents: Int = 0,
        in context: ModelContext
    ) throws -> AssetTransactionLink {
        guard transaction.kind == .expense,
              transaction.amount > 0,
              transaction.refundOfID == nil,
              !transaction.isExcluded,
              transaction.book?.stableID == asset.bookID,
              transaction.currencyCode == asset.currencyCode else {
            throw Error.invalidTransaction
        }
        let allTransactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let refundStatus = LedgerPolicy.refundStatus(for: transaction.record, in: allTransactions.map(\.record))
        let orderGross = MoneyNormalization.cents(transaction.amount)
        let validRefund = MoneyNormalization.cents(refundStatus.refundedAmount)
        let otherLines = try context.fetch(FetchDescriptor<AssetTransactionLink>())
            .filter {
                $0.transactionID == transaction.stableID &&
                ($0.linkTypeRaw == AssetTransactionLinkType.sourceTransaction.rawValue ||
                 $0.linkTypeRaw == AssetTransactionLinkType.purchaseTransaction.rawValue)
            }
            .map {
                AssetAllocationLine(
                    assetID: $0.assetID,
                    grossCents: $0.allocatedGrossCents,
                    refundCents: $0.allocatedRefundCents
                )
            }
        let lines = otherLines + [AssetAllocationLine(
            assetID: asset.stableID,
            grossCents: grossCents,
            refundCents: refundCents
        )]
        do {
            _ = try AssetAllocationPolicy.validate(
                orderGrossCents: orderGross,
                validOrderRefundCents: validRefund,
                lines: lines
            )
        } catch {
            throw Error.allocationInvalid
        }
        guard !otherLines.contains(where: { $0.assetID == asset.stableID }) else {
            throw Error.duplicateTransaction
        }
        let link = AssetTransactionLink(
            assetID: asset.stableID,
            transactionID: transaction.stableID,
            linkTypeRaw: AssetTransactionLinkType.sourceTransaction.rawValue,
            amount: Decimal(grossCents - refundCents) / Decimal(100)
        )
        link.allocatedGrossCents = grossCents
        link.allocatedRefundCents = refundCents
        link.costQualityRaw = AssetAllocationCostQuality.partial.rawValue
        link.note = "从已有账单分配"
        context.insert(link)
        asset.acquisitionCostSourceRaw = AssetAcquisitionCostSource.transactionAllocations.rawValue
        asset.purchasePrice = MoneyNormalization.roundToCents(
            Decimal(grossCents - refundCents) / Decimal(100)
        )
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .transactionLinked,
            value: link.amount,
            note: "从已有账单分配"
        ))
        try context.save()
        return link
    }

    @discardableResult
    static func create(
        in context: ModelContext,
        name: String,
        kind: PhysicalAssetKind,
        purchasePrice: Decimal,
        currentValue: Decimal,
        currencyCode: String = "CNY",
        book: Book? = nil,
        purchaseDate: Date? = nil,
        brand: String = "",
        model: String = "",
        location: String = "",
        warrantyUntil: Date? = nil,
        note: String = "",
        includeInNetWorth: Bool = true
    ) throws -> PhysicalAsset {
        let normalizedPurchasePrice = MoneyNormalization.roundToCents(purchasePrice)
        let normalizedCurrentValue = MoneyNormalization.roundToCents(currentValue)
        try validate(
            name: name,
            purchasePrice: normalizedPurchasePrice,
            currentValue: normalizedCurrentValue,
            purchaseDate: purchaseDate,
            warrantyUntil: warrantyUntil
        )
        let now = Date()
        let asset = PhysicalAsset(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            purchasePrice: normalizedPurchasePrice,
            currentValue: normalizedCurrentValue,
            currencyCode: currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            bookID: book?.stableID
        )
        asset.purchaseDate = purchaseDate
        asset.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.warrantyUntil = warrantyUntil
        asset.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.includeInNetWorth = includeInNetWorth
        asset.createdAt = now
        asset.updatedAt = now
        context.insert(asset)
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .created,
            occurredAt: purchaseDate ?? now,
            value: normalizedCurrentValue,
            note: asset.note
        ))
        context.insert(AssetValuation(
            assetID: asset.stableID,
            value: normalizedCurrentValue,
            sourceRaw: purchaseDate == nil ? "opening" : "purchase",
            valuedAt: purchaseDate ?? now,
            note: "初始当前价值"
        ))
        try context.save()
        return asset
    }

    static func update(
        _ asset: PhysicalAsset,
        in context: ModelContext,
        name: String,
        kind: PhysicalAssetKind,
        purchasePrice: Decimal,
        currentValue: Decimal,
        book: Book? = nil,
        purchaseDate: Date?,
        warrantyUntil: Date?,
        brand: String,
        model: String,
        location: String,
        note: String,
        includeInNetWorth: Bool
    ) throws {
        guard asset.lifecycle == .owned || asset.lifecycle == .idle else {
            throw Error.endedAsset
        }
        let normalizedPurchasePrice = MoneyNormalization.roundToCents(purchasePrice)
        let normalizedCurrentValue = MoneyNormalization.roundToCents(currentValue)
        try validate(
            name: name,
            purchasePrice: normalizedPurchasePrice,
            currentValue: normalizedCurrentValue,
            purchaseDate: purchaseDate,
            warrantyUntil: warrantyUntil
        )
        let previousValue = asset.currentValue
        asset.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.kind = kind
        asset.purchasePrice = normalizedPurchasePrice
        asset.currentValue = normalizedCurrentValue
        asset.bookID = book?.stableID
        asset.purchaseDate = purchaseDate
        asset.warrantyUntil = warrantyUntil
        asset.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.includeInNetWorth = includeInNetWorth
        asset.updatedAt = Date()
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: previousValue == normalizedCurrentValue ? .edited : .valuationUpdated,
            value: normalizedCurrentValue,
            note: previousValue == normalizedCurrentValue ? "编辑资产资料" : "手动更新当前价值"
        ))
        if previousValue != normalizedCurrentValue {
            context.insert(AssetValuation(
                assetID: asset.stableID,
                value: normalizedCurrentValue,
                sourceRaw: "manual",
                note: "手动更新当前价值"
            ))
        }
        try context.save()
    }

    static func setLifecycle(
        _ asset: PhysicalAsset,
        lifecycle: PhysicalAssetLifecycle,
        in context: ModelContext,
        note: String = ""
    ) throws {
        guard asset.lifecycle == .owned || asset.lifecycle == .idle || lifecycle == .archived else {
            throw Error.endedAsset
        }
        asset.lifecycle = lifecycle
        asset.updatedAt = Date()
        if lifecycle != .owned && lifecycle != .idle {
            asset.includeInNetWorth = false
            asset.endedAt = Date()
        } else {
            asset.includeInNetWorth = true
            asset.endedAt = nil
        }
        let eventKind: AssetEventKind
        switch lifecycle {
        case .owned: eventKind = .restored
        case .idle: eventKind = .edited
        case .sold: eventKind = .sold
        case .returned: eventKind = .returned
        case .disposed: eventKind = .disposed
        case .lost: eventKind = .lost
        case .gifted: eventKind = .gifted
        case .archived: eventKind = .archived
        }
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: eventKind,
            value: asset.currentValue,
            note: note
        ))
        try context.save()
    }

    static func restore(_ asset: PhysicalAsset, in context: ModelContext) throws {
        guard asset.lifecycle == .archived else { return }
        asset.lifecycle = .owned
        asset.includeInNetWorth = true
        asset.endedAt = nil
        asset.archivedAt = nil
        asset.updatedAt = Date()
        context.insert(AssetEvent(assetID: asset.stableID, kind: .restored, value: asset.currentValue))
        try context.save()
    }

    static func archive(_ asset: PhysicalAsset, in context: ModelContext) throws {
        asset.lifecycle = .archived
        asset.archivedAt = Date()
        asset.includeInNetWorth = false
        asset.updatedAt = Date()
        context.insert(AssetEvent(assetID: asset.stableID, kind: .archived, value: asset.currentValue))
        try context.save()
    }

    static func addUsage(_ asset: PhysicalAsset, count: Int = 1, in context: ModelContext) throws {
        guard asset.usageTrackingEnabled, count > 0 else { return }
        asset.usageCount += count
        asset.updatedAt = Date()
        context.insert(AssetUsageEvent(
            assetID: asset.stableID,
            countDelta: count,
            occurredAt: Date(),
            note: "增加使用次数"
        ))
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .usageAdded,
            value: Decimal(count),
            note: "增加使用次数"
        ))
        try context.save()
    }

    static func undoLatestUsage(_ asset: PhysicalAsset, in context: ModelContext) throws {
        let events = try usageEvents(for: asset, in: context)
        let reversed = Set(events.compactMap(\.reversalOfID))
        guard let target = events.first(where: {
            $0.reversalOfID == nil && $0.countDelta > 0 && !reversed.contains($0.stableID)
        }) else { return }
        let now = Date()
        context.insert(AssetUsageEvent(
            assetID: asset.stableID,
            countDelta: 0,
            reversalOfID: target.stableID,
            occurredAt: now,
            note: "撤销使用记录",
            stableID: UUID()
        ))
        asset.usageCount = max(0, asset.usageCount - target.countDelta)
        asset.updatedAt = now
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .usageAdded,
            value: Decimal(-target.countDelta),
            note: "撤销使用次数"
        ))
        try context.save()
    }

    private static func validate(
        name: String,
        purchasePrice: Decimal,
        currentValue: Decimal,
        purchaseDate: Date?,
        warrantyUntil: Date?
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.invalidName
        }
        guard purchasePrice >= 0, currentValue >= 0 else { throw Error.invalidAmount }
        if let purchaseDate, let warrantyUntil,
           Calendar.current.startOfDay(for: warrantyUntil) < Calendar.current.startOfDay(for: purchaseDate) {
            throw Error.invalidWarranty
        }
    }
}

/// 权益/应收款的生命周期和回收记录。
enum ReceivableStore {
    enum Error: LocalizedError {
        case invalidName
        case invalidAmount
        case exceedsRemaining
        case recoveryNotLatest

        var errorDescription: String? {
            switch self {
            case .invalidName: return "权益名称不能为空。"
            case .invalidAmount: return "金额必须大于 0。"
            case .exceedsRemaining: return "收回金额不能超过剩余金额。"
            case .recoveryNotLatest: return "只能从最近一次收回开始撤销。"
            }
        }
    }

    static func visible(in context: ModelContext) throws -> [ReceivableAsset] {
        try context.fetch(FetchDescriptor<ReceivableAsset>(sortBy: [
            SortDescriptor(\ReceivableAsset.updatedAt, order: .reverse)
        ])).filter { !$0.isDeleted && $0.lifecycle != .archived }
    }

    static func recoveries(
        for asset: ReceivableAsset,
        in context: ModelContext
    ) throws -> [ReceivableRecovery] {
        try context.fetch(FetchDescriptor<ReceivableRecovery>(
            sortBy: [SortDescriptor(\ReceivableRecovery.recoveredAt, order: .reverse)]
        )).filter { $0.receivableID == asset.stableID }
    }

    @discardableResult
    static func create(
        in context: ModelContext,
        name: String,
        kind: ReceivableKind,
        originalAmount: Decimal,
        currencyCode: String = "CNY",
        counterparty: String = "",
        dueDate: Date? = nil,
        book: Book? = nil,
        note: String = "",
        includeInNetWorth: Bool = true
    ) throws -> ReceivableAsset {
        let normalizedOriginalAmount = MoneyNormalization.roundToCents(originalAmount)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.invalidName
        }
        guard normalizedOriginalAmount > 0 else { throw Error.invalidAmount }
        let asset = ReceivableAsset(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            originalAmount: normalizedOriginalAmount,
            kind: kind,
            bookID: book?.stableID,
            currencyCode: currencyCode.uppercased()
        )
        asset.counterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.dueDate = dueDate
        asset.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.includeInNetWorth = includeInNetWorth
        context.insert(asset)
        try context.save()
        return asset
    }

    static func update(
        _ asset: ReceivableAsset,
        in context: ModelContext,
        name: String,
        kind: ReceivableKind,
        originalAmount: Decimal,
        book: Book? = nil,
        counterparty: String,
        dueDate: Date?,
        note: String,
        includeInNetWorth: Bool
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.invalidName
        }
        let normalizedOriginalAmount = MoneyNormalization.roundToCents(originalAmount)
        guard normalizedOriginalAmount > 0 else { throw Error.invalidAmount }
        let recovered = asset.originalAmount - asset.remainingAmount
        guard normalizedOriginalAmount >= recovered else { throw Error.exceedsRemaining }
        asset.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.kind = kind
        asset.originalAmount = normalizedOriginalAmount
        asset.remainingAmount = normalizedOriginalAmount - recovered
        asset.bookID = book?.stableID
        asset.counterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.dueDate = dueDate
        asset.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.includeInNetWorth = includeInNetWorth
        asset.updatedAt = Date()
        try context.save()
    }

    @discardableResult
    static func recover(
        _ asset: ReceivableAsset,
        amount: Decimal,
        in context: ModelContext,
        account: Account? = nil,
        date: Date = Date(),
        note: String = ""
    ) throws -> ReceivableRecovery {
        let normalizedAmount = MoneyNormalization.roundToCents(amount)
        guard normalizedAmount > 0 else { throw Error.invalidAmount }
        guard normalizedAmount <= asset.remainingAmount else { throw Error.exceedsRemaining }
        let recovery = ReceivableRecovery(
            receivableID: asset.stableID,
            amount: normalizedAmount,
            recoveredAt: date,
            targetAccountID: account?.stableID,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(recovery)
        asset.remainingAmount -= normalizedAmount
        asset.lifecycle = asset.remainingAmount == 0 ? .recovered : .partiallyRecovered
        if asset.remainingAmount == 0 { asset.includeInNetWorth = false }
        asset.updatedAt = Date()
        try context.save()
        return recovery
    }

    static func undoLatestRecovery(
        _ asset: ReceivableAsset,
        in context: ModelContext
    ) throws {
        let items = try recoveries(for: asset, in: context)
        guard let latest = items.first else { return }
        guard Calendar.current.isDate(
            latest.recoveredAt,
            equalTo: items.map(\.recoveredAt).max() ?? latest.recoveredAt,
            toGranularity: .second
        ) else {
            throw Error.recoveryNotLatest
        }
        context.delete(latest)
        asset.remainingAmount += latest.amount
        asset.lifecycle = asset.remainingAmount >= asset.originalAmount ? .active : .partiallyRecovered
        asset.includeInNetWorth = true
        asset.updatedAt = Date()
        try context.save()
    }

    static func setLost(_ asset: ReceivableAsset, in context: ModelContext, note: String = "") throws {
        asset.lifecycle = .lost
        asset.remainingAmount = 0
        asset.includeInNetWorth = false
        asset.endedAt = Date()
        asset.updatedAt = Date()
        try context.save()
    }

    static func archive(_ asset: ReceivableAsset, in context: ModelContext) throws {
        asset.lifecycle = .archived
        asset.archivedAt = Date()
        asset.updatedAt = Date()
        try context.save()
    }

    static func restore(_ asset: ReceivableAsset, in context: ModelContext) throws {
        asset.lifecycle = asset.remainingAmount >= asset.originalAmount ? .active : .partiallyRecovered
        asset.archivedAt = nil
        asset.includeInNetWorth = asset.remainingAmount > 0
        asset.updatedAt = Date()
        try context.save()
    }
}

/// 负债档案的写入边界；还款会产生转账和必要的利息支出，保持净资产不凭空变化。
enum LiabilityStore {
    enum Error: LocalizedError {
        case invalidPrincipal
        case invalidRepayment
        case accountMissing
        case sameAccount

        var errorDescription: String? {
            switch self {
            case .invalidPrincipal: return "负债本金必须大于 0。"
            case .invalidRepayment: return "还款金额必须大于 0，且不能超过当前本金。"
            case .accountMissing: return "还款账户不存在或已停用。"
            case .sameAccount: return "还款账户不能是负债账户本身。"
            }
        }
    }

    static func profiles(in context: ModelContext) throws -> [LiabilityProfile] {
        try context.fetch(FetchDescriptor<LiabilityProfile>(sortBy: [
            SortDescriptor(\LiabilityProfile.updatedAt, order: .reverse)
        ]))
    }

    @discardableResult
    static func create(
        in context: ModelContext,
        kind: LiabilityKind,
        originalPrincipal: Decimal,
        currentPrincipal: Decimal? = nil,
        account: Account? = nil,
        counterparty: String = "",
        annualRate: Decimal? = nil,
        statementDay: Int? = nil,
        paymentDay: Int? = nil,
        creditLimit: Decimal? = nil,
        startDate: Date? = nil,
        dueDate: Date? = nil,
        note: String = ""
    ) throws -> LiabilityProfile {
        let normalizedOriginalPrincipal = MoneyNormalization.roundToCents(originalPrincipal)
        guard normalizedOriginalPrincipal > 0 else { throw Error.invalidPrincipal }
        let current = MoneyNormalization.roundToCents(currentPrincipal ?? originalPrincipal)
        guard current >= 0, current <= normalizedOriginalPrincipal else { throw Error.invalidPrincipal }
        let profile = LiabilityProfile(
            accountID: account?.stableID,
            kind: kind,
            originalPrincipal: normalizedOriginalPrincipal,
            currentPrincipal: current,
            currencyCode: account?.currencyCode ?? "CNY"
        )
        profile.counterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.annualRate = annualRate
        profile.statementDay = statementDay
        profile.paymentDay = paymentDay
        profile.creditLimit = creditLimit
        profile.startDate = startDate
        profile.dueDate = dueDate
        profile.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(profile)
        try context.save()
        return profile
    }

    static func update(
        _ profile: LiabilityProfile,
        in context: ModelContext,
        kind: LiabilityKind,
        originalPrincipal: Decimal,
        currentPrincipal: Decimal,
        account: Account?,
        counterparty: String,
        annualRate: Decimal?,
        statementDay: Int?,
        paymentDay: Int?,
        creditLimit: Decimal?,
        startDate: Date?,
        dueDate: Date?,
        note: String
    ) throws {
        let normalizedOriginalPrincipal = MoneyNormalization.roundToCents(originalPrincipal)
        let normalizedCurrentPrincipal = MoneyNormalization.roundToCents(currentPrincipal)
        guard normalizedOriginalPrincipal > 0,
              normalizedCurrentPrincipal >= 0,
              normalizedCurrentPrincipal <= normalizedOriginalPrincipal else {
            throw Error.invalidPrincipal
        }
        profile.kind = kind
        profile.originalPrincipal = normalizedOriginalPrincipal
        profile.currentPrincipal = normalizedCurrentPrincipal
        profile.accountID = account?.stableID
        profile.currencyCode = account?.currencyCode ?? profile.currencyCode
        profile.counterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.annualRate = annualRate
        profile.statementDay = statementDay
        profile.paymentDay = paymentDay
        profile.creditLimit = creditLimit
        profile.startDate = startDate
        profile.dueDate = dueDate
        profile.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.updatedAt = Date()
        try context.save()
    }

    static func setLifecycle(_ profile: LiabilityProfile, status: LiabilityLifecycle, in context: ModelContext) throws {
        profile.lifecycle = status
        profile.updatedAt = Date()
        try context.save()
    }

    /// 本金部分建成还款账户 -> 负债账户的转账；若金额超过本金，超出部分作为利息支出。
    static func repay(
        _ profile: LiabilityProfile,
        amount: Decimal,
        fromAccount: Account,
        book: Book?,
        category: TxCategory?,
        date: Date = Date(),
        note: String = "",
        in context: ModelContext
    ) throws -> (principal: Decimal, interest: Decimal) {
        let normalizedAmount = MoneyNormalization.roundToCents(amount)
        guard normalizedAmount > 0 else { throw Error.invalidRepayment }
        guard fromAccount.status == .active && !fromAccount.isDeleted else { throw Error.accountMissing }
        let accounts = try context.fetch(FetchDescriptor<Account>())
        guard let liabilityAccountID = profile.accountID,
              let liabilityAccount = accounts.first(where: {
                  $0.stableID == liabilityAccountID &&
                  !$0.isDeleted &&
                  $0.status == .active &&
                  $0.currencyCode == fromAccount.currencyCode
              }) else {
            throw Error.accountMissing
        }
        guard liabilityAccount.stableID != fromAccount.stableID else { throw Error.sameAccount }
        let hasPrincipal = profile.currentPrincipal > 0
        // 信用卡档案常把本金记在负债账户余额上，currentPrincipal 为 0 时，
        // 整笔还款仍是账户之间的转账，不把它虚构成利息。
        let principal = hasPrincipal
            ? (normalizedAmount < profile.currentPrincipal ? normalizedAmount : profile.currentPrincipal)
            : normalizedAmount
        let interest = hasPrincipal ? normalizedAmount - principal : .zero
        if principal > 0 {
            _ = try LedgerStore.createTransaction(
                in: context,
                amount: principal,
                kind: .transfer,
                date: date,
                note: note.isEmpty ? "偿还本金" : note,
                account: fromAccount,
                toAccount: liabilityAccount,
                book: book,
                timePrecision: .dateOnly
            )
        }
        if interest > 0 {
            _ = try LedgerStore.createTransaction(
                in: context,
                amount: interest,
                kind: .expense,
                date: date,
                note: note.isEmpty ? "还款利息" : "\(note)（利息）",
                category: category,
                account: fromAccount,
                book: book,
                timePrecision: .dateOnly
            )
        }
        if hasPrincipal { profile.currentPrincipal -= principal }
        if profile.currentPrincipal <= 0, profile.kind == .personalBorrow {
            profile.lifecycle = .paidOff
        }
        profile.updatedAt = Date()
        try context.save()
        return (principal, interest)
    }
}
