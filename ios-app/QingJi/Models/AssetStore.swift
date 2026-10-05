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
        case invalidSale
        case saleAccountMissing
        case saleNotFound
        case returnRequiresPurchaseLink
        case returnNotAvailable
        case invalidTerminalStatus

        var errorDescription: String? {
            switch self {
            case .invalidName: return "资产名称不能为空。"
            case .invalidAmount: return "资产金额不能为负。"
            case .invalidWarranty: return "保修到期日不能早于购买日期。"
            case .endedAsset: return "已出售、退货、报废、丢失或赠送的资产不能继续编辑价值。"
            case .invalidTransaction: return "只能关联同账本、同币种的普通支出。"
            case .duplicateTransaction: return "这笔支出已经关联了其他物品或当前资产。"
            case .allocationInvalid: return "物品分配金额超过订单可用金额。"
            case .invalidSale: return "出售金额或出售费用不合法。"
            case .saleAccountMissing: return "收款账户不存在、已停用或币种不一致。"
            case .saleNotFound: return "找不到可撤销的出售记录。"
            case .returnRequiresPurchaseLink: return "多物品订单需要先完成购置成本分配，才能确认退货。"
            case .returnNotAvailable: return "这件物品当前没有可退回的购置账单。"
            case .invalidTerminalStatus: return "当前资产状态不能执行这个结束持有操作。"
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

    struct PurchaseCandidate {
        let transaction: MoneyTransaction
        let remainingGrossCents: Int
        let remainingRefundCents: Int
    }

    static func purchaseCandidates(
        transactions: [MoneyTransaction],
        links: [AssetTransactionLink]
    ) -> [PurchaseCandidate] {
        let refundTotals = LedgerPolicy.refundTotals(from: transactions.map(\.record))
        var allocations: [UUID: (gross: Int, refund: Int)] = [:]
        for link in links where link.assetObjectType == "physical" &&
            (link.linkTypeRaw == AssetTransactionLinkType.sourceTransaction.rawValue ||
             link.linkTypeRaw == AssetTransactionLinkType.purchaseTransaction.rawValue) {
            let previous = allocations[link.transactionID] ?? (gross: 0, refund: 0)
            allocations[link.transactionID] = (
                gross: previous.gross + link.allocatedGrossCents,
                refund: previous.refund + link.allocatedRefundCents
            )
        }
        return transactions.compactMap { transaction in
            guard transaction.kind == .expense,
                  transaction.amount > 0,
                  transaction.refundOfID == nil,
                  !transaction.isExcluded,
                  transaction.currencyCode == "CNY" else { return nil }
            let orderGross = MoneyNormalization.cents(transaction.amount)
            let validRefund = MoneyNormalization.cents(-(refundTotals[transaction.stableID] ?? .zero))
            guard validRefund <= orderGross else { return nil }
            let used = allocations[transaction.stableID] ?? (gross: 0, refund: 0)
            let remainingGross = orderGross - used.gross
            guard remainingGross > 0 else { return nil }
            return PurchaseCandidate(
                transaction: transaction,
                remainingGrossCents: remainingGross,
                remainingRefundCents: max(0, validRefund - used.refund)
            )
        }
        .sorted {
            $0.transaction.date == $1.transaction.date
                ? $0.transaction.stableID.uuidString > $1.transaction.stableID.uuidString
                : $0.transaction.date > $1.transaction.date
        }
    }

    /// 给多件物品订单建立购置成本分配，遵守“毛额、退款、净额均不能超订单”规则。
    @discardableResult
    static func linkPurchaseAllocation(
        _ asset: PhysicalAsset,
        transaction: MoneyTransaction,
        grossCents: Int,
        refundCents: Int = 0,
        in context: ModelContext,
        saveImmediately: Bool = true
    ) throws -> AssetTransactionLink {
        guard transaction.kind == .expense,
              transaction.amount > 0,
              transaction.refundOfID == nil,
              !transaction.isExcluded,
              transaction.book?.stableID == asset.bookID,
              transaction.currencyCode == asset.currencyCode else {
            throw Error.invalidTransaction
        }
        try validatePurchaseAllocation(
            transaction: transaction,
            grossCents: grossCents,
            refundCents: refundCents,
            assetID: asset.stableID,
            in: context
        )
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
        if saveImmediately { try context.save() }
        return link
    }

    private static func validatePurchaseAllocation(
        transaction: MoneyTransaction,
        grossCents: Int,
        refundCents: Int,
        assetID: UUID,
        in context: ModelContext
    ) throws {
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
        guard !otherLines.contains(where: { $0.assetID == assetID }) else {
            throw Error.duplicateTransaction
        }
        let lines = otherLines + [AssetAllocationLine(
            assetID: assetID,
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
        includeInNetWorth: Bool = true,
        sourceType: PhysicalAssetSourceType = .historicalExisting,
        usageLifecycle: PhysicalAssetLifecycle = .owned,
        saveImmediately: Bool = true
    ) throws -> PhysicalAsset {
        try validateUsageLifecycle(usageLifecycle)
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
        asset.sourceType = sourceType
        asset.lifecycle = usageLifecycle
        asset.usageStatusRaw = usageLifecycle == .idle ? "idle" : "active"
        asset.acquisitionCostSourceRaw = normalizedPurchasePrice > 0
            ? AssetAcquisitionCostSource.manual.rawValue
            : AssetAcquisitionCostSource.manualUnknown.rawValue
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
        if saveImmediately { try context.save() }
        return asset
    }

    /// 新购买物品：创建资产的同时生成一笔 asset_purchase 支出，并把两者绑定。
    @discardableResult
    static func createPurchased(
        in context: ModelContext,
        name: String,
        kind: PhysicalAssetKind,
        purchasePrice: Decimal,
        currentValue: Decimal,
        account: Account,
        category: TxCategory? = nil,
        book: Book? = nil,
        purchaseDate: Date,
        brand: String = "",
        model: String = "",
        location: String = "",
        warrantyUntil: Date? = nil,
        note: String = "",
        includeInNetWorth: Bool = true,
        usageLifecycle: PhysicalAssetLifecycle = .owned
    ) throws -> PhysicalAsset {
        try validateUsageLifecycle(usageLifecycle)
        let normalizedPrice = MoneyNormalization.roundToCents(purchasePrice)
        guard normalizedPrice > 0,
              !account.isDeleted,
              account.status == .active,
              account.currencyCode == "CNY" else {
            throw Error.invalidTransaction
        }
        guard category == nil || category?.kind == .expense else {
            throw Error.invalidTransaction
        }
        var createdAsset: PhysicalAsset?
        try context.transaction {
            let asset = try create(
                in: context,
                name: name,
                kind: kind,
                purchasePrice: normalizedPrice,
                currentValue: currentValue,
                currencyCode: account.currencyCode,
                book: book,
                purchaseDate: purchaseDate,
                brand: brand,
                model: model,
                location: location,
                warrantyUntil: warrantyUntil,
                note: note,
                includeInNetWorth: includeInNetWorth,
                sourceType: .newPurchaseWithAccount,
                usageLifecycle: usageLifecycle,
                saveImmediately: false
            )
            let transaction = MoneyTransaction(
                amount: normalizedPrice,
                kind: .expense,
                date: purchaseDate,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "购买：\(name)"
                    : note,
                merchantName: name,
                currencyCode: account.currencyCode,
                category: category,
                account: account,
                book: book,
                timePrecision: .dateOnly,
                settledAt: purchaseDate,
                settlementQuality: .userConfirmed,
                settlementAccountID: account.stableID,
                settlementAccountQuality: .userConfirmed,
                eventType: .assetPurchase
            )
            context.insert(transaction)
            _ = try linkPurchaseAllocation(
                asset,
                transaction: transaction,
                grossCents: MoneyNormalization.cents(normalizedPrice),
                in: context,
                saveImmediately: false
            )
            createdAsset = asset
        }
        return createdAsset!
    }

    /// 从既有支出账单加入物品；多物品订单必须显式给出本物品的毛额和退款分摊。
    @discardableResult
    static func createFromTransaction(
        in context: ModelContext,
        transaction: MoneyTransaction,
        name: String,
        kind: PhysicalAssetKind,
        allocatedGrossCents: Int,
        allocatedRefundCents: Int = 0,
        currentValue: Decimal? = nil,
        brand: String = "",
        model: String = "",
        location: String = "",
        warrantyUntil: Date? = nil,
        note: String = "",
        includeInNetWorth: Bool = true,
        usageLifecycle: PhysicalAssetLifecycle = .owned
    ) throws -> PhysicalAsset {
        try validateUsageLifecycle(usageLifecycle)
        guard transaction.kind == .expense,
              transaction.amount > 0,
              transaction.refundOfID == nil,
              !transaction.isExcluded,
              transaction.currencyCode == "CNY" else {
            throw Error.invalidTransaction
        }
        guard allocatedGrossCents > 0,
              allocatedRefundCents >= 0,
              allocatedRefundCents <= allocatedGrossCents else {
            throw Error.allocationInvalid
        }
        try validatePurchaseAllocation(
            transaction: transaction,
            grossCents: allocatedGrossCents,
            refundCents: allocatedRefundCents,
            assetID: UUID(),
            in: context
        )
        let net = Decimal(allocatedGrossCents - allocatedRefundCents) / Decimal(100)
        var createdAsset: PhysicalAsset?
        try context.transaction {
            let asset = try create(
                in: context,
                name: name,
                kind: kind,
                purchasePrice: net,
                currentValue: currentValue ?? net,
                currencyCode: transaction.currencyCode,
                book: transaction.book,
                purchaseDate: transaction.date,
                brand: brand,
                model: model,
                location: location,
                warrantyUntil: warrantyUntil,
                note: note,
                includeInNetWorth: includeInNetWorth,
                sourceType: .fromTransaction,
                usageLifecycle: usageLifecycle,
                saveImmediately: false
            )
            _ = try linkPurchaseAllocation(
                asset,
                transaction: transaction,
                grossCents: allocatedGrossCents,
                refundCents: allocatedRefundCents,
                in: context,
                saveImmediately: false
            )
            createdAsset = asset
        }
        return createdAsset!
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
        includeInNetWorth: Bool,
        usageLifecycle: PhysicalAssetLifecycle? = nil
    ) throws {
        guard asset.lifecycle == .owned || asset.lifecycle == .idle else {
            throw Error.endedAsset
        }
        if let usageLifecycle { try validateUsageLifecycle(usageLifecycle) }
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
        if previousValue != normalizedCurrentValue {
            asset.depreciationPaused = true
        }
        asset.bookID = book?.stableID
        asset.purchaseDate = purchaseDate
        asset.warrantyUntil = warrantyUntil
        asset.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.includeInNetWorth = includeInNetWorth
        if let usageLifecycle {
            asset.lifecycle = usageLifecycle
            asset.usageStatusRaw = usageLifecycle == .idle ? "idle" : "active"
        }
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

    private static func validateUsageLifecycle(_ lifecycle: PhysicalAssetLifecycle) throws {
        guard lifecycle == .owned || lifecycle == .idle else { throw Error.endedAsset }
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

    /// 只更新当前估值，不改购置成本；每次更新都会追加估值记录。
    @discardableResult
    static func updateCurrentValue(
        _ asset: PhysicalAsset,
        value: Decimal,
        at date: Date = Date(),
        note: String = "手动更新当前价值",
        in context: ModelContext
    ) throws -> AssetValuation {
        guard asset.lifecycle == .owned || asset.lifecycle == .idle else {
            throw Error.endedAsset
        }
        let normalized = MoneyNormalization.roundToCents(value)
        guard normalized >= 0 else { throw Error.invalidAmount }
        let latestValuation = try context.fetch(FetchDescriptor<AssetValuation>(
            sortBy: [
                SortDescriptor(\.valuedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
            ]
        )).first { $0.assetID == asset.stableID }
        let becomesCurrent = latestValuation == nil || date >= latestValuation!.valuedAt
        if becomesCurrent {
            asset.currentValue = normalized
            asset.depreciationPaused = true
            asset.updatedAt = date
        }
        let valuation = AssetValuation(
            assetID: asset.stableID,
            value: normalized,
            sourceRaw: "manual",
            valuedAt: date,
            note: note
        )
        context.insert(valuation)
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .valuationUpdated,
            occurredAt: date,
            value: normalized,
            note: note
        ))
        try context.save()
        return valuation
    }

    /// 更新资产照片、缩略图和发票/保修单路径；数据库只保存受管目录中的相对路径。
    static func updateEvidence(
        _ asset: PhysicalAsset,
        photoPath: String,
        thumbnailPath: String? = nil,
        invoicePath: String,
        note: String = "",
        at date: Date = Date(),
        in context: ModelContext
    ) throws {
        asset.photoPath = photoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if let thumbnailPath {
            asset.thumbnailPath = thumbnailPath.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        asset.invoicePath = invoicePath.trimmingCharacters(in: .whitespacesAndNewlines)
        asset.updatedAt = date
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .edited,
            occurredAt: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "更新资产凭证"
                : note
        ))
        try context.save()
    }

    /// 配置或关闭线性折旧。关闭后清空折旧字段，重新保存配置会恢复自动折旧。
    static func configureDepreciation(
        _ asset: PhysicalAsset,
        enabled: Bool,
        base: Decimal = .zero,
        salvageValue: Decimal = .zero,
        usefulLifeMonths: Int = 0,
        startAt: Date? = nil,
        note: String = "",
        at date: Date = Date(),
        in context: ModelContext
    ) throws {
        if enabled {
            let normalizedBase = MoneyNormalization.roundToCents(base)
            let normalizedSalvage = MoneyNormalization.roundToCents(salvageValue)
            guard normalizedBase > 0,
                  normalizedSalvage >= 0,
                  normalizedSalvage <= normalizedBase,
                  usefulLifeMonths > 0,
                  let startAt else {
                throw Error.invalidAmount
            }
            if let purchaseDate = asset.purchaseDate,
               Calendar.current.startOfDay(for: startAt) <
               Calendar.current.startOfDay(for: purchaseDate) {
                throw Error.invalidWarranty
            }
            asset.depreciationMethod = "linear"
            asset.depreciationBase = normalizedBase
            asset.salvageValue = normalizedSalvage
            asset.usefulLifeMonths = usefulLifeMonths
            asset.depreciationStartDate = startAt
            asset.depreciationPaused = false
        } else {
            asset.depreciationMethod = ""
            asset.depreciationBase = .zero
            asset.salvageValue = .zero
            asset.usefulLifeMonths = 0
            asset.depreciationStartDate = nil
            asset.depreciationPaused = false
        }
        asset.updatedAt = date
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .depreciation,
            occurredAt: date,
            value: enabled ? asset.depreciationBase : nil,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (enabled ? "设置线性折旧" : "关闭自动折旧")
                : note
        ))
        try context.save()
    }

    /// 应用截至指定日期的线性折旧；只降低当前价值，不生成普通收支流水。
    @discardableResult
    static func applyDepreciation(
        asOf: Date = Date(),
        in context: ModelContext
    ) throws -> Int {
        let assets = try context.fetch(FetchDescriptor<PhysicalAsset>())
            .filter {
                !$0.isDeleted &&
                ($0.lifecycle == .owned || $0.lifecycle == .idle) &&
                $0.depreciationMethod == "linear" &&
                !$0.depreciationPaused &&
                $0.depreciationStartDate != nil &&
                $0.usefulLifeMonths > 0
            }
        let calendar = Calendar.current
        var changed = 0
        for asset in assets {
            guard let start = asset.depreciationStartDate,
                  asOf >= start else { continue }
            let startMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: start)
            ) ?? start
            let endMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: asOf)
            ) ?? asOf
            let elapsed = min(
                max(calendar.dateComponents([.month], from: startMonth, to: endMonth).month ?? 0, 0),
                asset.usefulLifeMonths
            )
            guard elapsed > 0 else { continue }
            let depreciable = asset.depreciationBase - asset.salvageValue
            guard depreciable > 0 else { continue }
            var monthly = Decimal.zero
            var left = depreciable
            var right = Decimal(asset.usefulLifeMonths)
            NSDecimalDivide(&monthly, &left, &right, .plain)
            var target = asset.depreciationBase - monthly * Decimal(elapsed)
            if target < asset.salvageValue { target = asset.salvageValue }
            target = MoneyNormalization.roundToCents(target)
            guard target < asset.currentValue else { continue }
            asset.currentValue = target
            asset.updatedAt = asOf
            context.insert(AssetValuation(
                assetID: asset.stableID,
                value: target,
                sourceRaw: "auto_depreciation",
                valuedAt: asOf,
                note: "自动线性折旧"
            ))
            context.insert(AssetEvent(
                assetID: asset.stableID,
                kind: .depreciation,
                occurredAt: asOf,
                value: target,
                note: "自动线性折旧"
            ))
            changed += 1
        }
        if changed > 0 { try context.save() }
        return changed
    }

    /// 出售物品：出售到账作为 asset_sale 事件收入写入，但明确排除普通收支统计。
    /// 这样账户余额会增加，资产净值会减少，报表不会把出售本金误当成工资收入。
    @discardableResult
    static func sell(
        _ asset: PhysicalAsset,
        grossProceeds: Decimal,
        fee: Decimal = .zero,
        account: Account? = nil,
        at date: Date = Date(),
        note: String = "",
        in context: ModelContext
    ) throws -> MoneyTransaction? {
        guard asset.lifecycle == .owned || asset.lifecycle == .idle else {
            throw Error.invalidSale
        }
        let gross = MoneyNormalization.roundToCents(grossProceeds)
        let normalizedFee = MoneyNormalization.roundToCents(fee)
        guard gross >= 0, normalizedFee >= 0, normalizedFee <= gross else {
            throw Error.invalidSale
        }
        guard asset.currencyCode.uppercased() == "CNY" else {
            throw Error.saleAccountMissing
        }
        if let account,
           account.isDeleted || account.status != .active ||
           account.currencyCode != asset.currencyCode {
            throw Error.saleAccountMissing
        }
        let net = gross - normalizedFee
        let previousValue = asset.currentValue
        let previousLifecycle = asset.lifecycle
        let previousInclude = asset.includeInNetWorth
        let previousEndedAt = asset.endedAt
        let books = try context.fetch(FetchDescriptor<Book>())
        let book = books.first { $0.stableID == asset.bookID }
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var saleTransaction: MoneyTransaction?
        if let account, net > 0 {
            let transaction = MoneyTransaction(
                amount: net,
                kind: .income,
                date: date,
                note: cleanedNote.isEmpty ? "资产出售：\(asset.name)" : cleanedNote,
                merchantName: asset.name,
                currencyCode: asset.currencyCode,
                book: book,
                timePrecision: .dateOnly,
                settledAt: date,
                settlementQuality: .userConfirmed,
                settlementAccountID: account.stableID,
                settlementAccountQuality: .userConfirmed,
                eventType: .assetSale,
                isExcluded: true
            )
            context.insert(transaction)
            saleTransaction = transaction
        }
        asset.lifecycle = .sold
        asset.currentValue = .zero
        asset.includeInNetWorth = false
        asset.endedAt = date
        asset.updatedAt = date
        if let saleTransaction {
            let link = AssetTransactionLink(
                assetID: asset.stableID,
                transactionID: saleTransaction.stableID,
                linkTypeRaw: AssetTransactionLinkType.saleAccountMovement.rawValue,
                amount: net
            )
            link.costQualityRaw = AssetAllocationCostQuality.exact.rawValue
            link.note = "出售到账，不计入普通收入"
            context.insert(link)
        }
        context.insert(AssetValuation(
            assetID: asset.stableID,
            value: .zero,
            sourceRaw: "sale",
            valuedAt: date,
            note: cleanedNote
        ))
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .sold,
            occurredAt: date,
            value: net,
            note: cleanedNote,
            metadataJSON: metadataJSON([
                "gross_sale_amount": gross.description,
                "sale_fee": normalizedFee.description,
                "net_proceeds": net.description,
                "previous_value": previousValue.description,
                "previous_lifecycle": previousLifecycle.rawValue,
                "previous_include_in_net_worth": previousInclude ? "1" : "0",
                "previous_ended_at": previousEndedAt?.timeIntervalSince1970.description ?? "",
                "transaction_id": saleTransaction?.stableID.uuidString ?? ""
            ])
        ))
        try context.save()
        return saleTransaction
    }

    /// 撤销出售时删除出售专用到账流水，恢复出售前的价值和持有状态。
    static func undoSale(
        _ asset: PhysicalAsset,
        at date: Date = Date(),
        in context: ModelContext
    ) throws {
        guard asset.lifecycle == .sold else { throw Error.saleNotFound }
        let events = try events(for: asset, in: context)
        let saleEvent = events.first { $0.kind == .sold }
        let metadata = saleEvent.flatMap { eventMetadata($0) } ?? [:]
        let previousValue = Decimal(
            string: metadata["previous_value"] as? String ?? ""
        ) ?? asset.currentValue
        let previousLifecycle = PhysicalAssetLifecycle(
            rawValue: metadata["previous_lifecycle"] as? String ?? "owned"
        ) ?? .owned
        let previousInclude = (metadata["previous_include_in_net_worth"] as? String) != "0"
        let previousEndedAt = dateFromMetadata(metadata["previous_ended_at"])
        let links = try context.fetch(FetchDescriptor<AssetTransactionLink>())
            .filter {
                $0.assetID == asset.stableID &&
                $0.linkTypeRaw == AssetTransactionLinkType.saleAccountMovement.rawValue
            }
            .sorted { $0.createdAt > $1.createdAt }
        if let link = links.first {
            let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
            for child in transactions where child.refundOfID == link.transactionID {
                context.delete(child)
            }
            if let transaction = transactions.first(where: { $0.stableID == link.transactionID }) {
                context.delete(transaction)
            }
            context.delete(link)
        }
        asset.lifecycle = previousLifecycle == .owned || previousLifecycle == .idle
            ? previousLifecycle
            : .owned
        asset.currentValue = MoneyNormalization.roundToCents(previousValue)
        asset.includeInNetWorth = previousInclude
        asset.endedAt = previousEndedAt
        asset.updatedAt = date
        context.insert(AssetValuation(
            assetID: asset.stableID,
            value: asset.currentValue,
            sourceRaw: "manual",
            valuedAt: date,
            note: "撤销出售，恢复出售前价值"
        ))
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .restored,
            occurredAt: date,
            value: asset.currentValue,
            note: "撤销出售"
        ))
        try context.save()
    }

    /// 确认退货：仅允许购置来源完整覆盖原账单的物品，避免多物品订单被整单误退。
    @discardableResult
    static func returnToPurchase(
        _ asset: PhysicalAsset,
        at date: Date = Date(),
        note: String = "退货退款",
        in context: ModelContext,
        save: AssetFinancialCommand.Save = { try $0.save() }
    ) throws -> MoneyTransaction {
        guard asset.lifecycle == .owned || asset.lifecycle == .idle else {
            throw Error.returnNotAvailable
        }
        let purchaseLinks = try context.fetch(FetchDescriptor<AssetTransactionLink>())
            .filter {
                $0.assetID == asset.stableID &&
                ($0.linkTypeRaw == AssetTransactionLinkType.sourceTransaction.rawValue ||
                 $0.linkTypeRaw == AssetTransactionLinkType.purchaseTransaction.rawValue)
            }
        guard purchaseLinks.count == 1,
              let link = purchaseLinks.first else {
            throw Error.returnRequiresPurchaseLink
        }
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        guard let original = transactions.first(where: { $0.stableID == link.transactionID }) else {
            throw Error.returnNotAvailable
        }
        let status = LedgerPolicy.refundStatus(
            for: original.record,
            in: transactions.map(\.record)
        )
        guard status.remainingAmount > 0 else { throw Error.returnNotAvailable }
        let allocatedGross = link.allocatedGrossCents > 0
            ? Decimal(link.allocatedGrossCents) / Decimal(100)
            : link.amount
        let allocatedRefund = Decimal(link.allocatedRefundCents) / Decimal(100)
        let allocatedNet = max(allocatedGross - allocatedRefund, .zero)
        guard allocatedNet == status.remainingAmount else {
            throw Error.returnRequiresPurchaseLink
        }
        let previousValue = asset.currentValue
        let previousLifecycle = asset.lifecycle
        let previousInclude = asset.includeInNetWorth
        let previousEndedAt = asset.endedAt
        let previousUpdatedAt = asset.updatedAt
        let previousOriginalUpdatedAt = original.updatedAt
        return try AssetFinancialCommand.perform(in: context, save: save) { changes in
            changes.restoreOnFailure {
                asset.lifecycle = previousLifecycle
                asset.currentValue = previousValue
                asset.includeInNetWorth = previousInclude
                asset.endedAt = previousEndedAt
                asset.updatedAt = previousUpdatedAt
                original.updatedAt = previousOriginalUpdatedAt
            }
            let refund = try LedgerStore.createOffset(
                for: original, amount: status.remainingAmount, note: note, eventType: .refund,
                settlementAccount: original.account, settledAt: date, in: context,
                saveImmediately: false
            )
            changes.restoreOnFailure { context.delete(refund) }
            asset.lifecycle = .returned
            asset.currentValue = .zero
            asset.includeInNetWorth = false
            asset.endedAt = date
            asset.updatedAt = date
            changes.insert(AssetValuation(
                assetID: asset.stableID, value: .zero, sourceRaw: "status_zero",
                valuedAt: date, note: "确认退货"
            ))
            changes.insert(AssetEvent(
                assetID: asset.stableID, kind: .returned, occurredAt: date,
                value: status.remainingAmount, note: note,
                metadataJSON: metadataJSON([
                    "refund_transaction_id": refund.stableID.uuidString,
                    "previous_value": previousValue.description,
                    "previous_lifecycle": previousLifecycle.rawValue,
                    "previous_include_in_net_worth": previousInclude ? "1" : "0",
                    "previous_ended_at": previousEndedAt?.timeIntervalSince1970.description ?? ""
                ])
            ))
            return refund
        }
    }

    /// 撤销退货状态只恢复物品本身；原账单退款保留，和 Android 的审计语义一致。
    static func undoReturn(
        _ asset: PhysicalAsset,
        at date: Date = Date(),
        in context: ModelContext
    ) throws {
        guard asset.lifecycle == .returned else { throw Error.returnNotAvailable }
        let returnedEvent = try events(for: asset, in: context).first { $0.kind == .returned }
        let metadata = returnedEvent.flatMap { eventMetadata($0) } ?? [:]
        let previousValue = Decimal(
            string: metadata["previous_value"] as? String ?? ""
        ) ?? asset.currentValue
        let previousLifecycle = PhysicalAssetLifecycle(
            rawValue: metadata["previous_lifecycle"] as? String ?? "owned"
        ) ?? .owned
        let previousInclude = (metadata["previous_include_in_net_worth"] as? String) != "0"
        let previousEndedAt = dateFromMetadata(metadata["previous_ended_at"])
        asset.lifecycle = previousLifecycle == .idle ? .idle : .owned
        asset.currentValue = MoneyNormalization.roundToCents(previousValue)
        asset.includeInNetWorth = previousInclude
        asset.endedAt = previousEndedAt
        asset.updatedAt = date
        context.insert(AssetValuation(
            assetID: asset.stableID,
            value: asset.currentValue,
            sourceRaw: "manual",
            valuedAt: date,
            note: "撤销退货，恢复退货前价值"
        ))
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .restored,
            occurredAt: date,
            value: asset.currentValue,
            note: "撤销退货"
        ))
        try context.save()
    }

    /// 报废、丢失、赠送属于终止持有，不生成虚构的收入或支出。
    static func end(
        _ asset: PhysicalAsset,
        lifecycle: PhysicalAssetLifecycle,
        at date: Date = Date(),
        note: String = "",
        in context: ModelContext
    ) throws {
        guard lifecycle == .disposed || lifecycle == .lost || lifecycle == .gifted else {
            throw Error.invalidTerminalStatus
        }
        guard asset.lifecycle == .owned || asset.lifecycle == .idle else {
            throw Error.invalidTerminalStatus
        }
        let previousValue = asset.currentValue
        let previousLifecycle = asset.lifecycle
        let previousInclude = asset.includeInNetWorth
        let previousEndedAt = asset.endedAt
        asset.lifecycle = lifecycle
        asset.currentValue = .zero
        asset.includeInNetWorth = false
        asset.endedAt = date
        asset.updatedAt = date
        let eventKind: AssetEventKind = switch lifecycle {
        case .disposed: .disposed
        case .lost: .lost
        case .gifted: .gifted
        default: .edited
        }
        context.insert(AssetValuation(
            assetID: asset.stableID,
            value: .zero,
            sourceRaw: "status_zero",
            valuedAt: date,
            note: note
        ))
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: eventKind,
            occurredAt: date,
            value: .zero,
            note: note,
            metadataJSON: metadataJSON([
                "previous_value": previousValue.description,
                "previous_lifecycle": previousLifecycle.rawValue,
                "previous_include_in_net_worth": previousInclude ? "1" : "0",
                "previous_ended_at": previousEndedAt?.timeIntervalSince1970.description ?? ""
            ])
        ))
        try context.save()
    }

    static func undoEnd(
        _ asset: PhysicalAsset,
        at date: Date = Date(),
        in context: ModelContext
    ) throws {
        guard asset.lifecycle == .disposed || asset.lifecycle == .lost || asset.lifecycle == .gifted else {
            throw Error.invalidTerminalStatus
        }
        let event = try events(for: asset, in: context).first {
            $0.kind == .disposed || $0.kind == .lost || $0.kind == .gifted
        }
        let metadata = event.flatMap { eventMetadata($0) } ?? [:]
        let previousValue = Decimal(
            string: metadata["previous_value"] as? String ?? ""
        ) ?? asset.currentValue
        let previousLifecycle = PhysicalAssetLifecycle(
            rawValue: metadata["previous_lifecycle"] as? String ?? "owned"
        ) ?? .owned
        let previousInclude = (metadata["previous_include_in_net_worth"] as? String) != "0"
        let previousEndedAt = dateFromMetadata(metadata["previous_ended_at"])
        asset.lifecycle = previousLifecycle == .idle ? .idle : .owned
        asset.currentValue = MoneyNormalization.roundToCents(previousValue)
        asset.includeInNetWorth = previousInclude
        asset.endedAt = previousEndedAt
        asset.updatedAt = date
        context.insert(AssetValuation(
            assetID: asset.stableID,
            value: asset.currentValue,
            sourceRaw: "manual",
            valuedAt: date,
            note: "撤销结束持有"
        ))
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .restored,
            occurredAt: date,
            value: asset.currentValue,
            note: "撤销结束持有"
        ))
        try context.save()
    }

    private static func metadataJSON(_ values: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func eventMetadata(_ event: AssetEvent) -> [String: Any]? {
        guard let data = event.metadataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let values = object as? [String: Any] else {
            return nil
        }
        return values
    }

    private static func dateFromMetadata(_ value: Any?) -> Date? {
        guard let text = value as? String,
              let seconds = Double(text),
              !seconds.isZero else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
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
        case invalidAccount
        case inactiveAsset
        case recoveryConflict
        case eventBeforeBalanceAnchor
        case futureRecovery

        var errorDescription: String? {
            switch self {
            case .invalidName: return "权益名称不能为空。"
            case .invalidAmount: return "金额必须大于 0。"
            case .exceedsRemaining: return "收回金额不能超过剩余金额。"
            case .recoveryNotLatest: return "只能从最近一次收回开始撤销。"
            case .invalidAccount: return "到账账户不存在、已停用或币种与权益不一致。"
            case .inactiveAsset: return "只有待收回或部分收回的权益可以继续收回。"
            case .recoveryConflict: return "权益或到账流水已变更，请先核对最近一次收回记录，不能直接撤销。"
            case .eventBeforeBalanceAnchor: return "收回日期早于账户期初或最近余额核对，请先核对该账户和到账日期。"
            case .futureRecovery: return "不能把未来日期记为已经到账，请选择实际收回日期。"
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
        )).filter { $0.receivableID == asset.stableID }.sorted {
            if $0.recoveredAt != $1.recoveredAt { return $0.recoveredAt > $1.recoveredAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.stableID.uuidString > $1.stableID.uuidString
        }
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
        note: String = "",
        save: AssetFinancialCommand.Save = { try $0.save() }
    ) throws -> ReceivableRecovery {
        let normalizedAmount = MoneyNormalization.roundToCents(amount)
        guard normalizedAmount > 0 else { throw Error.invalidAmount }
        guard date <= Date() else { throw Error.futureRecovery }
        guard !asset.isDeleted, asset.lifecycle == .active || asset.lifecycle == .partiallyRecovered else {
            throw Error.inactiveAsset
        }
        guard normalizedAmount <= asset.remainingAmount else { throw Error.exceedsRemaining }
        if let account {
            let accounts = try context.fetch(FetchDescriptor<Account>())
            guard accounts.contains(where: { $0.stableID == account.stableID }),
                  !account.isDeleted, account.status == .active,
                  account.currencyCode.uppercased() == asset.currencyCode.uppercased() else {
                throw Error.invalidAccount
            }
            guard try AssetFinancialCommand.allowsEvent(at: date, for: account, in: context) else {
                throw Error.eventBeforeBalanceAnchor
            }
        }
        let book = try context.fetch(FetchDescriptor<Book>()).first { $0.stableID == asset.bookID }
        let before = (asset.remainingAmount, asset.lifecycleRaw, asset.includeInNetWorth,
                      asset.economicStatusRaw, asset.endedAt, asset.updatedAt)
        let existingTransactions = try LedgerStore.allTransactions(in: context)
        let accountCheckpoints = try account.map { try AssetFinancialCommand.activeAnchors(for: $0.stableID, in: context) } ?? []
        let balanceBefore = account.map { LedgerStore.accountBalance(for: $0, transactions: existingTransactions, checkpoints: accountCheckpoints) }
        let sequence = try AssetFinancialCommand.nextSequence(for: asset.stableID, command: "receivable_recovery", in: context)
        return try AssetFinancialCommand.perform(in: context, save: save) { changes in
            changes.restoreOnFailure {
                (asset.remainingAmount, asset.lifecycleRaw, asset.includeInNetWorth,
                 asset.economicStatusRaw, asset.endedAt, asset.updatedAt) = before
            }
            let recovery = ReceivableRecovery(
                receivableID: asset.stableID, amount: normalizedAmount, recoveredAt: date,
                targetAccountID: account?.stableID, note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if let account {
                let transaction = MoneyTransaction(
                    amount: normalizedAmount, kind: .income, date: date,
                    note: note.isEmpty ? "收回权益：\(asset.name)" : note,
                    currencyCode: asset.currencyCode, account: account, book: book,
                    timePrecision: .dateOnly, settledAt: date, settlementQuality: .userConfirmed,
                    settlementAccountID: account.stableID, settlementAccountQuality: .userConfirmed,
                    eventType: .receivableRecovery, isExcluded: true
                )
                changes.insert(transaction)
                recovery.transactionID = transaction.stableID
            }
            changes.insert(recovery)
            asset.remainingAmount = MoneyNormalization.roundToCents(asset.remainingAmount - normalizedAmount)
            asset.lifecycle = asset.remainingAmount == 0 ? .recovered : .partiallyRecovered
            asset.economicStatusRaw = asset.remainingAmount == 0 ? "recovered" : "partial_recovered"
            if asset.remainingAmount == 0 { asset.includeInNetWorth = false; asset.endedAt = date }
            asset.updatedAt = Date()
            changes.insert(AssetEvent(
                assetID: asset.stableID, kind: .edited, occurredAt: date, value: normalizedAmount,
                note: "收回权益", metadataJSON: AssetFinancialCommand.metadata([
                    "command": "receivable_recovery", "recovery_id": recovery.stableID.uuidString,
                    "sequence": String(sequence),
                    "transaction_id": recovery.transactionID?.uuidString ?? "",
                    "target_account_id": recovery.targetAccountID?.uuidString ?? "",
                    "original_amount": asset.originalAmount.description, "currency_code": asset.currencyCode,
                    "previous_remaining": before.0.description, "remaining_after": asset.remainingAmount.description,
                    "previous_lifecycle": before.1, "previous_include_in_net_worth": before.2 ? "1" : "0",
                    "include_after": asset.includeInNetWorth ? "1" : "0", "previous_economic_status": before.3,
                    "lifecycle_after": asset.lifecycleRaw, "economic_status_after": asset.economicStatusRaw,
                    "ended_at_after": asset.endedAt?.timeIntervalSince1970.description ?? "",
                    "previous_ended_at": before.4?.timeIntervalSince1970.description ?? ""
                ])
            ))
            if let account, let balanceBefore {
                let actual = LedgerStore.accountBalance(for: account, transactions: try LedgerStore.allTransactions(in: context),
                                                       checkpoints: accountCheckpoints)
                guard MoneyNormalization.roundToCents(actual) == MoneyNormalization.roundToCents(balanceBefore + normalizedAmount) else {
                    throw Error.recoveryConflict
                }
            }
            return recovery
        }
    }

    static func undoLatestRecovery(
        _ asset: ReceivableAsset,
        in context: ModelContext,
        save: AssetFinancialCommand.Save = { try $0.save() }
    ) throws {
        let items = try recoveries(for: asset, in: context)
        let events = try context.fetch(FetchDescriptor<AssetEvent>())
        let recoveryEvents = events.filter {
            $0.assetID == asset.stableID && AssetFinancialCommand.metadata(of: $0)["command"] == "receivable_recovery"
        }
        func sequence(of recovery: ReceivableRecovery) -> Int {
            guard let event = recoveryEvents.first(where: {
                AssetFinancialCommand.metadata(of: $0)["recovery_id"] == recovery.stableID.uuidString
            }) else { return 0 }
            return Int(AssetFinancialCommand.metadata(of: event)["sequence"] ?? "") ?? 0
        }
        guard let latest = items.max(by: {
            if sequence(of: $0) != sequence(of: $1) { return sequence(of: $0) < sequence(of: $1) }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.stableID.uuidString < $1.stableID.uuidString
        }) else { return }
        guard !asset.isDeleted, latest.amount > 0, latest.amount == MoneyNormalization.roundToCents(latest.amount),
              asset.originalAmount > 0, asset.remainingAmount >= 0,
              asset.lifecycle == .partiallyRecovered || asset.lifecycle == .recovered,
              asset.remainingAmount + latest.amount <= asset.originalAmount else { throw Error.recoveryConflict }
        let event = events.first {
            $0.assetID == asset.stableID &&
            AssetFinancialCommand.metadata(of: $0)["command"] == "receivable_recovery" &&
            AssetFinancialCommand.metadata(of: $0)["recovery_id"] == latest.stableID.uuidString
        }
        let metadata = event.map(AssetFinancialCommand.metadata(of:)) ?? [:]
        if let event {
            guard let original = metadata["original_amount"].flatMap({ Decimal(string: $0) }),
                  let after = metadata["remaining_after"].flatMap({ Decimal(string: $0) }),
                  let previous = metadata["previous_remaining"].flatMap({ Decimal(string: $0) }),
                  original == asset.originalAmount, after == asset.remainingAmount,
                  previous == MoneyNormalization.roundToCents(after + latest.amount), previous <= original,
                  metadata["lifecycle_after"] == asset.lifecycleRaw,
                  metadata["economic_status_after"] == asset.economicStatusRaw,
                  metadata["include_after"] == (asset.includeInNetWorth ? "1" : "0"),
                  metadata["currency_code"] == asset.currencyCode,
                  metadata["transaction_id"] == (latest.transactionID?.uuidString ?? ""),
                  metadata["target_account_id"] == (latest.targetAccountID?.uuidString ?? ""),
                  metadata["ended_at_after"] == (asset.endedAt?.timeIntervalSince1970.description ?? ""),
                  event.value == latest.amount, event.occurredAt == latest.recoveredAt,
                  let previousLifecycle = metadata["previous_lifecycle"].flatMap(ReceivableLifecycle.init(rawValue:)),
                  previousLifecycle == .active || previousLifecycle == .partiallyRecovered,
                  ["0", "1"].contains(metadata["previous_include_in_net_worth"] ?? "") else {
                throw Error.recoveryConflict
            }
        } else if latest.targetAccountID != nil || latest.transactionID != nil {
            // Only legacy recoveries without an account are safe to undo without an arrival journal.
            throw Error.recoveryConflict
        }
        guard (latest.targetAccountID == nil) == (latest.transactionID == nil) else { throw Error.recoveryConflict }
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        var transaction: MoneyTransaction?
        if let id = latest.transactionID {
            guard let linked = transactions.first(where: { $0.stableID == id }),
                  linked.eventType == .receivableRecovery, linked.kind == .income, linked.isExcluded,
                  linked.refundOfID == nil, linked.toAccount == nil,
                  linked.date == latest.recoveredAt, linked.settledAt == latest.recoveredAt,
                  linked.amount == latest.amount, linked.settlementAccountID == latest.targetAccountID,
                  linked.account?.stableID == latest.targetAccountID,
                  linked.currencyCode.uppercased() == asset.currencyCode.uppercased(),
                  !transactions.contains(where: { $0.refundOfID == id }) else {
                throw Error.recoveryConflict
            }
            transaction = linked
        }
        if let id = latest.targetAccountID, latest.transactionID != nil,
           try !AssetFinancialCommand.allowsUndo(for: [id], createdAt: event?.createdAt ?? latest.createdAt, in: context) {
            throw Error.recoveryConflict
        }
        let before = (asset.remainingAmount, asset.lifecycleRaw, asset.includeInNetWorth,
                      asset.economicStatusRaw, asset.endedAt, asset.updatedAt)
        let targetAccount = try context.fetch(FetchDescriptor<Account>()).first { $0.stableID == latest.targetAccountID }
        let checkpoints = try targetAccount.map { try AssetFinancialCommand.activeAnchors(for: $0.stableID, in: context) } ?? []
        let balanceBefore = targetAccount.map { LedgerStore.accountBalance(for: $0, transactions: transactions, checkpoints: checkpoints) }
        if latest.transactionID != nil,
           (targetAccount == nil || targetAccount?.currencyCode.uppercased() != asset.currencyCode.uppercased()) {
            throw Error.recoveryConflict
        }
        try AssetFinancialCommand.perform(in: context, save: save) { changes in
            changes.restoreOnFailure {
                (asset.remainingAmount, asset.lifecycleRaw, asset.includeInNetWorth,
                 asset.economicStatusRaw, asset.endedAt, asset.updatedAt) = before
            }
            if let transaction { changes.delete(transaction) }
            changes.delete(latest)
            asset.remainingAmount = metadata["previous_remaining"].flatMap { Decimal(string: $0) }
                ?? MoneyNormalization.roundToCents(before.0 + latest.amount)
            asset.lifecycleRaw = metadata["previous_lifecycle"]
                ?? (asset.remainingAmount >= asset.originalAmount ? ReceivableLifecycle.active.rawValue : ReceivableLifecycle.partiallyRecovered.rawValue)
            // Old recoveries have no evidence of the previous inclusion choice.
            if let include = metadata["previous_include_in_net_worth"] { asset.includeInNetWorth = include == "1" }
            asset.economicStatusRaw = metadata["previous_economic_status"] ?? asset.economicStatusRaw
            if let ended = metadata["previous_ended_at"] {
                asset.endedAt = Double(ended).map(Date.init(timeIntervalSince1970:))
            }
            asset.updatedAt = Date()
            changes.insert(AssetEvent(
                assetID: asset.stableID, kind: .restored, note: "撤销收回权益",
                metadataJSON: AssetFinancialCommand.metadata([
                    "command": "receivable_recovery_reversal", "recovery_id": latest.stableID.uuidString,
                    "reversal_of": event?.stableID.uuidString ?? "", "legacy_unverified": event == nil ? "1" : "0"
                ])
            ))
            if transaction != nil, let targetAccount, let balanceBefore {
                let actual = LedgerStore.accountBalance(for: targetAccount, transactions: try LedgerStore.allTransactions(in: context),
                                                       checkpoints: checkpoints)
                guard MoneyNormalization.roundToCents(actual) == MoneyNormalization.roundToCents(balanceBefore - latest.amount) else {
                    throw Error.recoveryConflict
                }
            }
        }
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
        case needsBalanceReview
        case repaymentChanged
        case eventBeforeBalanceAnchor
        case inactiveProfile
        case futureRepayment

        var errorDescription: String? {
            switch self {
            case .invalidPrincipal: return "负债本金必须大于 0。"
            case .invalidRepayment: return "还款金额必须大于 0，利息分类必须是支出分类。"
            case .accountMissing: return "还款账户不存在或已停用。"
            case .sameAccount: return "还款账户不能是负债账户本身。"
            case .needsBalanceReview: return "负债档案本金与账户欠款口径不一致，请先在账户中核对实际欠款和档案本金，再记录还款。不会自动修改原数据。"
            case .repaymentChanged: return "最近还款或负债档案已经变更，请先核对，不能直接撤销。"
            case .eventBeforeBalanceAnchor: return "还款日期早于账户期初或最近余额核对，请先核对付款账户、负债账户和还款日期。"
            case .inactiveProfile: return "只有还款中的负债档案可以记录还款，请先恢复或核对档案状态。"
            case .futureRepayment: return "还款只能记录已发生的付款，不能选择未来日期。"
            }
        }
    }

    static func profiles(in context: ModelContext) throws -> [LiabilityProfile] {
        try context.fetch(FetchDescriptor<LiabilityProfile>(sortBy: [
            SortDescriptor(\LiabilityProfile.updatedAt, order: .reverse)
        ]))
    }

    static func latestRepaymentEvent(for profile: LiabilityProfile, events: [AssetEvent]) -> AssetEvent? {
        let items = events.filter { $0.assetID == profile.stableID }
        let reversed = Set(items.compactMap { AssetFinancialCommand.metadata(of: $0)["reversal_of"] })
        return items.filter {
            AssetFinancialCommand.metadata(of: $0)["command"] == "liability_repayment" &&
            !reversed.contains($0.stableID.uuidString)
        }.sorted {
            let left = Int(AssetFinancialCommand.metadata(of: $0)["sequence"] ?? "") ?? 0
            let right = Int(AssetFinancialCommand.metadata(of: $1)["sequence"] ?? "") ?? 0
            if left != right { return left > right }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.stableID.uuidString > $1.stableID.uuidString
        }.first
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
        in context: ModelContext,
        save: AssetFinancialCommand.Save = { try $0.save() }
    ) throws -> (principal: Decimal, interest: Decimal) {
        let normalizedAmount = MoneyNormalization.roundToCents(amount)
        guard normalizedAmount > 0 else { throw Error.invalidRepayment }
        guard profile.currentPrincipal >= 0 else { throw Error.invalidPrincipal }
        guard profile.lifecycle == .active else { throw Error.inactiveProfile }
        guard date <= Date() else { throw Error.futureRepayment }
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
        guard accounts.contains(where: { $0.stableID == fromAccount.stableID }),
              profile.currencyCode.uppercased() == liabilityAccount.currencyCode.uppercased() else {
            throw Error.accountMissing
        }
        guard try AssetFinancialCommand.allowsEvent(at: date, for: fromAccount, in: context),
              try AssetFinancialCommand.allowsEvent(at: date, for: liabilityAccount, in: context) else {
            throw Error.eventBeforeBalanceAnchor
        }
        let transactions = try LedgerStore.allTransactions(in: context)
        let checkpoints = try AccountCheckpointStore.checkpoints(for: liabilityAccount.stableID, in: context)
        let balance = MoneyNormalization.roundToCents(LedgerStore.accountBalance(
            for: liabilityAccount, transactions: transactions, checkpoints: checkpoints
        ))
        let payerCheckpoints = try AccountCheckpointStore.checkpoints(for: fromAccount.stableID, in: context)
        let payerBalance = LedgerStore.accountBalance(for: fromAccount, transactions: transactions, checkpoints: payerCheckpoints)
        let pureCreditCardTransfer = profile.kind == .creditCard && profile.currentPrincipal == 0
        if !pureCreditCardTransfer {
            guard balance < 0 else { throw Error.needsBalanceReview }
            if liabilityAccount.balanceMode == .legacyHybrid,
               MoneyNormalization.roundToCents(profile.currentPrincipal) != -balance {
                throw Error.needsBalanceReview
            }
        }
        // Ledger-mode debt is the actual negative balance, not a stale profile.
        // Zero-principal credit-card profiles retain the existing pure transfer.
        let principal = !pureCreditCardTransfer
            ? min(normalizedAmount, -balance)
            : normalizedAmount
        let interest = pureCreditCardTransfer ? .zero : normalizedAmount - principal
        guard interest == 0 || category == nil || category?.kind == .expense else { throw Error.invalidRepayment }
        let before = (profile.currentPrincipal, profile.lifecycleRaw, profile.updatedAt)
        let sequence = try AssetFinancialCommand.nextSequence(for: profile.stableID, command: "liability_repayment", in: context)
        try AssetFinancialCommand.perform(in: context, save: save) { changes in
            changes.restoreOnFailure {
                (profile.currentPrincipal, profile.lifecycleRaw, profile.updatedAt) = before
            }
            let principalTransaction = MoneyTransaction(
                amount: principal, kind: .transfer, date: date,
                note: note.isEmpty ? "偿还本金" : note,
                currencyCode: fromAccount.currencyCode, account: fromAccount,
                toAccount: liabilityAccount, book: book, timePrecision: .dateOnly,
                settledAt: date, settlementQuality: .userConfirmed,
                settlementAccountID: fromAccount.stableID, settlementAccountQuality: .userConfirmed,
                eventType: .transfer
            )
            changes.insert(principalTransaction)
            var interestTransaction: MoneyTransaction?
            if interest > 0 {
                let transaction = MoneyTransaction(
                    amount: interest, kind: .expense, date: date,
                    note: note.isEmpty ? "还款利息" : "\(note)（利息）",
                    currencyCode: fromAccount.currencyCode, category: category,
                    account: fromAccount, book: book, timePrecision: .dateOnly,
                    settledAt: date, settlementQuality: .userConfirmed,
                    settlementAccountID: fromAccount.stableID, settlementAccountQuality: .userConfirmed,
                    eventType: .interest
                )
                changes.insert(transaction)
                interestTransaction = transaction
            }
            if !pureCreditCardTransfer { profile.currentPrincipal = max(before.0 - principal, .zero) }
            if balance + principal >= 0, profile.kind == .personalBorrow {
                profile.lifecycle = .paidOff
            }
            profile.updatedAt = Date()
            changes.insert(AssetEvent(
                assetID: profile.stableID, kind: .edited, occurredAt: date, value: normalizedAmount,
                note: "负债还款", metadataJSON: AssetFinancialCommand.metadata([
                    "command": "liability_repayment", "account_id": liabilityAccount.stableID.uuidString,
                    "sequence": String(sequence),
                    "payer_account_id": fromAccount.stableID.uuidString,
                    "balance_mode": liabilityAccount.balanceModeRaw,
                    "original_principal": profile.originalPrincipal.description,
                    "principal_before": before.0.description, "principal_after": profile.currentPrincipal.description,
                    "lifecycle_before": before.1, "lifecycle_after": profile.lifecycleRaw,
                    "principal_paid": principal.description, "interest_paid": interest.description,
                    "currency_code": fromAccount.currencyCode,
                    "principal_transaction_id": principalTransaction.stableID.uuidString,
                    "interest_transaction_id": interestTransaction?.stableID.uuidString ?? ""
                ])
            ))
            let current = try LedgerStore.allTransactions(in: context)
            let payerAfter = LedgerStore.accountBalance(for: fromAccount, transactions: current, checkpoints: payerCheckpoints)
            let debtAfter = LedgerStore.accountBalance(for: liabilityAccount, transactions: current, checkpoints: checkpoints)
            guard MoneyNormalization.roundToCents(payerAfter) == MoneyNormalization.roundToCents(payerBalance - normalizedAmount),
                  MoneyNormalization.roundToCents(debtAfter) == MoneyNormalization.roundToCents(balance + principal) else {
                throw Error.needsBalanceReview
            }
        }
        return (principal, interest)
    }

    /// Old repayments without an event are never reconstructed from guesses.
    static func undoLatestRepayment(
        _ profile: LiabilityProfile,
        in context: ModelContext,
        save: AssetFinancialCommand.Save = { try $0.save() }
    ) throws {
        let events = try context.fetch(FetchDescriptor<AssetEvent>()).filter { $0.assetID == profile.stableID }
        guard let event = latestRepaymentEvent(for: profile, events: events) else { throw Error.repaymentChanged }
        let values = AssetFinancialCommand.metadata(of: event)
        guard let principalBefore = values["principal_before"].flatMap({ Decimal(string: $0) }),
              let principalAfter = values["principal_after"].flatMap({ Decimal(string: $0) }),
              let principalPaid = values["principal_paid"].flatMap({ Decimal(string: $0) }),
              let interestPaid = values["interest_paid"].flatMap({ Decimal(string: $0) }),
              principalBefore >= 0, principalAfter >= 0, principalPaid > 0, interestPaid >= 0,
              profile.originalPrincipal >= 0, principalBefore <= profile.originalPrincipal,
              principalBefore == MoneyNormalization.roundToCents(principalBefore),
              principalAfter == MoneyNormalization.roundToCents(principalAfter),
              principalPaid == MoneyNormalization.roundToCents(principalPaid),
              interestPaid == MoneyNormalization.roundToCents(interestPaid),
              principalAfter == max(principalBefore - principalPaid, .zero),
              values["lifecycle_before"] == LiabilityLifecycle.active.rawValue,
              event.value == MoneyNormalization.roundToCents(principalPaid + interestPaid),
              principalAfter == profile.currentPrincipal, values["lifecycle_after"] == profile.lifecycleRaw,
              values["account_id"] == profile.accountID?.uuidString,
              values["currency_code"] == profile.currencyCode else { throw Error.repaymentChanged }
        if let recordedOriginal = values["original_principal"] {
            guard let original = Decimal(string: recordedOriginal),
                  original == profile.originalPrincipal else { throw Error.repaymentChanged }
        }
        let account = try context.fetch(FetchDescriptor<Account>()).first { $0.stableID == profile.accountID }
        guard account?.balanceModeRaw == values["balance_mode"] else { throw Error.repaymentChanged }
        guard let payerID = values["payer_account_id"].flatMap(UUID.init(uuidString:)),
              let accountID = profile.accountID,
              payerID != accountID,
              try AssetFinancialCommand.allowsUndo(for: [payerID, accountID], createdAt: event.createdAt, in: context) else {
            throw Error.repaymentChanged
        }
        let all = try LedgerStore.allTransactions(in: context)
        guard let principalID = values["principal_transaction_id"].flatMap(UUID.init(uuidString:)),
              let principal = all.first(where: { $0.stableID == principalID }),
              principal.eventType == .transfer, principal.kind == .transfer, principal.refundOfID == nil,
              !principal.isExcluded, principal.date == event.occurredAt, principal.settledAt == event.occurredAt,
              principal.amount == principalPaid, principal.settlementAccountID == payerID,
              principal.account?.stableID.uuidString == values["payer_account_id"],
              principal.toAccount?.stableID.uuidString == values["account_id"],
              principal.currencyCode == values["currency_code"],
              !all.contains(where: { $0.refundOfID == principalID }) else { throw Error.repaymentChanged }
        var interest: MoneyTransaction?
        if interestPaid > 0 {
            guard let interestID = values["interest_transaction_id"].flatMap(UUID.init(uuidString:)),
                  let transaction = all.first(where: { $0.stableID == interestID }),
                  transaction.eventType == .interest, transaction.kindRaw == TransactionKind.expense.rawValue,
                  transaction.refundOfID == nil, transaction.toAccount == nil, !transaction.isExcluded,
                  transaction.date == event.occurredAt, transaction.settledAt == event.occurredAt,
                  transaction.amount == interestPaid, transaction.settlementAccountID == payerID,
                  transaction.account?.stableID.uuidString == values["payer_account_id"],
                  transaction.currencyCode == values["currency_code"],
                  !all.contains(where: { $0.refundOfID == transaction.stableID }) else { throw Error.repaymentChanged }
            interest = transaction
        } else if values["interest_transaction_id"] != "" {
            throw Error.repaymentChanged
        }
        let before = (profile.currentPrincipal, profile.lifecycleRaw, profile.updatedAt)
        let accounts = try context.fetch(FetchDescriptor<Account>())
        guard let debtAccount = accounts.first(where: { $0.stableID == profile.accountID }),
              let payerAccount = accounts.first(where: { $0.stableID == payerID }),
              debtAccount.currencyCode == values["currency_code"],
              payerAccount.currencyCode == values["currency_code"] else { throw Error.repaymentChanged }
        let debtCheckpoints = try AccountCheckpointStore.checkpoints(for: debtAccount.stableID, in: context)
        let payerCheckpoints = try AccountCheckpointStore.checkpoints(for: payerAccount.stableID, in: context)
        let debtBefore = LedgerStore.accountBalance(for: debtAccount, transactions: all, checkpoints: debtCheckpoints)
        let payerBefore = LedgerStore.accountBalance(for: payerAccount, transactions: all, checkpoints: payerCheckpoints)
        try AssetFinancialCommand.perform(in: context, save: save) { changes in
            changes.restoreOnFailure { (profile.currentPrincipal, profile.lifecycleRaw, profile.updatedAt) = before }
            changes.delete(principal)
            if let interest { changes.delete(interest) }
            profile.currentPrincipal = principalBefore
            profile.lifecycleRaw = values["lifecycle_before"] ?? before.1
            profile.updatedAt = Date()
            changes.insert(AssetEvent(
                assetID: profile.stableID, kind: .restored, note: "撤销负债还款",
                metadataJSON: AssetFinancialCommand.metadata([
                    "command": "liability_repayment_reversal", "reversal_of": event.stableID.uuidString
                ])
            ))
            let current = try LedgerStore.allTransactions(in: context)
            let debtAfter = LedgerStore.accountBalance(for: debtAccount, transactions: current, checkpoints: debtCheckpoints)
            let payerAfter = LedgerStore.accountBalance(for: payerAccount, transactions: current, checkpoints: payerCheckpoints)
            guard MoneyNormalization.roundToCents(debtAfter) == MoneyNormalization.roundToCents(debtBefore - principal.amount),
                  MoneyNormalization.roundToCents(payerAfter) == MoneyNormalization.roundToCents(payerBefore + principal.amount + (interest?.amount ?? 0)) else {
                throw Error.repaymentChanged
            }
        }
    }
}
