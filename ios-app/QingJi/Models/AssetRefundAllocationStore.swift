import Foundation
import SwiftData
import QingJiCore

/// A refund allocation target shown when one purchase order contains more than
/// one tracked physical asset.
struct PhysicalAssetRefundAllocationTarget: Identifiable, Equatable, Sendable {
    let assetID: UUID
    let assetName: String
    let grossCents: Int
    let totalAllocatedRefundCents: Int
    let currentRefundAllocationCents: Int

    var id: UUID { assetID }

    /// The amount this refund can still add to the asset. The current refund is
    /// put back into the limit so editing an existing allocation is possible.
    var allocationLimitCents: Int {
        max(0, grossCents - totalAllocatedRefundCents + currentRefundAllocationCents)
    }
}

/// One refund that cannot be attributed to a single asset without user input.
struct PendingPhysicalAssetRefundAllocation: Identifiable, Equatable, Sendable {
    let refundTransactionID: UUID
    let originalTransactionID: UUID
    let refundDate: Date
    let orderLabel: String
    let currencyCode: String
    let refundCents: Int
    let targets: [PhysicalAssetRefundAllocationTarget]
    let untrackedLimitCents: Int
    let currentUntrackedCents: Int

    var id: UUID { refundTransactionID }

    var allocatedCents: Int {
        targets.reduce(currentUntrackedCents) { $0 + $1.currentRefundAllocationCents }
    }

    var remainingCents: Int { refundCents - allocatedCents }
}

/// Keeps asset purchase cost and attached refunds auditable across platforms.
///
/// Android stores one active audit row for every refund-to-asset decision. The
/// iOS model mirrors that contract instead of inferring ownership from the
/// current refund total, which would lose information when a refund is edited
/// or deleted.
enum AssetRefundAllocationStore {
    enum Error: LocalizedError, Equatable {
        case invalidRefund
        case noPurchaseLinks
        case invalidAmount
        case amountMismatch
        case unknownAsset
        case allocationExceedsLimit
        case invalidOrderAllocation
        case returnedAsset
        case invalidPurchaseLink

        var errorDescription: String? {
            switch self {
            case .invalidRefund:
                return "退款事件不存在或不是附着退款。"
            case .noPurchaseLinks:
                return "这笔退款没有关联物品的购置账单。"
            case .invalidAmount:
                return "退款分配金额不能为负。"
            case .amountMismatch:
                return "物品分配与未跟踪归属的合计必须等于退款金额。"
            case .unknownAsset:
                return "退款分配的物品不属于原购置账单。"
            case .allocationExceedsLimit:
                return "退款分配超过订单或物品当前可分配金额。"
            case .invalidOrderAllocation:
                return "订单的物品分配状态不合法，请重新检查购置账单。"
            case .returnedAsset:
                return "已退货物品的购置成本必须保持为零，请先撤销退货。"
            case .invalidPurchaseLink:
                return "这不是可解除的物品购置关联。"
            }
        }
    }

    /// `asset_refund_allocations.asset_transaction_link_id = 0` on Android is
    /// represented by a reserved UUID because SwiftData links use UUIDs.
    static let untrackedLinkID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private static let active = "active"
    private static let reversed = "reversed"
    private static let purchaseLinkTypes: Set<String> = [
        AssetTransactionLinkType.sourceTransaction.rawValue,
        AssetTransactionLinkType.purchaseTransaction.rawValue,
    ]

    static func pendingRefundAllocations(
        for asset: PhysicalAsset,
        in context: ModelContext
    ) throws -> [PendingPhysicalAssetRefundAllocation] {
        guard !asset.isDeleted else { return [] }
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let links = try context.fetch(FetchDescriptor<AssetTransactionLink>())
        let allocations = try context.fetch(FetchDescriptor<AssetRefundAllocation>())
        let assets = try context.fetch(FetchDescriptor<PhysicalAsset>())
        let assetNames = Dictionary(uniqueKeysWithValues: assets.map { ($0.stableID, $0.name) })
        let ownOrderIDs = Set(
            links
                .filter { $0.assetID == asset.stableID && isPurchaseLink($0) }
                .map(\.transactionID)
        )
        guard !ownOrderIDs.isEmpty else { return [] }

        let result = transactions.compactMap { refund -> PendingPhysicalAssetRefundAllocation? in
            guard let originalID = refund.refundOfID,
                  ownOrderIDs.contains(originalID),
                  refund.amount < 0 else { return nil }
            let refundCents = positiveCents(refund.amount)
            guard refundCents > 0 else { return nil }
            let orderLinks = links.filter {
                $0.transactionID == originalID && isPurchaseLink($0)
            }
            guard !orderLinks.isEmpty else { return nil }

            let activeForRefund = allocations.filter {
                $0.refundTransactionID == refund.stableID && $0.statusRaw == active
            }
            let currentByLink = activeForRefund.reduce(into: [UUID: Int]()) { result, allocation in
                result[allocation.assetTransactionLinkID, default: 0] += allocation.allocatedRefundCents
            }
            let allocated = activeForRefund.reduce(0) { $0 + max(0, $1.allocatedRefundCents) }
            guard allocated < refundCents else { return nil }

            let order = transactions.first { $0.stableID == originalID }
            let orderGross = order.map { positiveCents($0.amount) } ?? 0
            let trackedGross = orderLinks.reduce(0) { $0 + purchaseGrossCents($1) }
            let currentUntracked = currentByLink[untrackedLinkID, default: 0]
            let refundIDs = Set(
                transactions
                    .filter { $0.refundOfID == originalID }
                    .map(\.stableID)
            )
            let otherUntracked = allocations.reduce(0) { total, allocation in
                guard allocation.statusRaw == active,
                      allocation.assetTransactionLinkID == untrackedLinkID,
                      refundIDs.contains(allocation.refundTransactionID),
                      allocation.refundTransactionID != refund.stableID else {
                    return total
                }
                return total + max(0, allocation.allocatedRefundCents)
            }
            let untrackedLimit = max(
                0,
                orderGross - trackedGross - max(0, otherUntracked)
            )
            let targets = orderLinks.map { link in
                let name = assetNames[link.assetID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                PhysicalAssetRefundAllocationTarget(
                    assetID: link.assetID,
                    assetName: name.isEmpty ? "物品" : name,
                    grossCents: purchaseGrossCents(link),
                    totalAllocatedRefundCents: max(0, link.allocatedRefundCents),
                    currentRefundAllocationCents: currentByLink[link.stableID, default: 0]
                )
            }
            let label = [order?.note, order?.merchantName, order?.productName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "关联订单"
            return PendingPhysicalAssetRefundAllocation(
                refundTransactionID: refund.stableID,
                originalTransactionID: originalID,
                refundDate: refund.settledAt ?? refund.date,
                orderLabel: label,
                currencyCode: refund.currencyCode,
                refundCents: refundCents,
                targets: targets,
                untrackedLimitCents: untrackedLimit,
                currentUntrackedCents: currentUntracked
            )
        }
        return result.sorted { left, right in
            if left.refundDate != right.refundDate {
                return left.refundDate > right.refundDate
            }
            return left.refundTransactionID.uuidString > right.refundTransactionID.uuidString
        }
    }

    /// Applies the Android rule used immediately after a new refund is made.
    /// This method deliberately does not save; the caller can commit the refund
    /// and its audit rows in one SwiftData save.
    static func applyNewRefund(
        _ refund: MoneyTransaction,
        in context: ModelContext
    ) throws {
        guard let originalID = refund.refundOfID, refund.amount < 0 else { return }
        var transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        if !transactions.contains(where: { $0.stableID == refund.stableID }) {
            transactions.append(refund)
        }
        let links = try context.fetch(FetchDescriptor<AssetTransactionLink>())
            .filter { $0.transactionID == originalID && isPurchaseLink($0) }
        guard !links.isEmpty else { return }
        let existing = try context.fetch(FetchDescriptor<AssetRefundAllocation>())
            .contains { $0.refundTransactionID == refund.stableID && $0.statusRaw == active }
        if existing { return }

        let refundCents = positiveCents(refund.amount)
        guard refundCents > 0 else { return }
        let validRefund = refunds(for: originalID, in: transactions)
            .reduce(0) { $0 + positiveCents($1.amount) }
        let orderGross = transactions.first { $0.stableID == originalID }.map { positiveCents($0.amount) } ?? 0
        let now = Date()

        if links.count == 1, let link = links.first {
            let gross = purchaseGrossCents(link)
            let current = max(0, link.allocatedRefundCents)
            let priorFullyAllocated = current == max(0, validRefund - refundCents)
            let uniquelyCoversTrackedItem = current + refundCents == gross
            if priorFullyAllocated,
               current + refundCents <= gross,
               (gross == orderGross || uniquelyCoversTrackedItem),
               isValidOrderAllocation(
                   orderGrossCents: orderGross,
                   validRefundCents: validRefund,
                   links: links,
                   proposedRefundByLink: [link.stableID: current + refundCents]
               ) {
                link.allocatedRefundCents = current + refundCents
                link.costQualityRaw = AssetAllocationCostQuality.exact.rawValue
                link.updatedAt = now
                context.insert(AssetRefundAllocation(
                    assetTransactionLinkID: link.stableID,
                    refundTransactionID: refund.stableID,
                    allocatedRefundCents: refundCents
                ))
                refreshQuality(
                    originalID: originalID,
                    transactions: transactions,
                    links: links,
                    allocations: try context.fetch(FetchDescriptor<AssetRefundAllocation>()),
                    now: now
                )
                syncAssetPurchasePrice(
                    assetID: link.assetID,
                    links: links,
                    assets: try context.fetch(FetchDescriptor<PhysicalAsset>()),
                    now: now
                )
                return
            }
        }

        for link in links {
            link.costQualityRaw = AssetAllocationCostQuality.pendingRefundAllocation.rawValue
            link.updatedAt = now
        }
    }

    /// Rehydrates historical refund audit rows when a single full-order asset
    /// is linked after the refund already exists.
    static func reconcileHistoricalRefunds(
        for originalID: UUID,
        in context: ModelContext,
        including pendingLink: AssetTransactionLink? = nil
    ) throws {
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        var links = try context.fetch(FetchDescriptor<AssetTransactionLink>())
            .filter { $0.transactionID == originalID && isPurchaseLink($0) }
        if let pendingLink,
           pendingLink.transactionID == originalID,
           isPurchaseLink(pendingLink),
           !links.contains(where: { $0.stableID == pendingLink.stableID }) {
            links.append(pendingLink)
        }
        guard links.count == 1, let link = links.first else {
            refreshQuality(
                originalID: originalID,
                transactions: transactions,
                links: links,
                allocations: try context.fetch(FetchDescriptor<AssetRefundAllocation>()),
                now: Date()
            )
            return
        }
        let orderGross = transactions.first { $0.stableID == originalID }.map { positiveCents($0.amount) } ?? 0
        let refunds = refunds(for: originalID, in: transactions)
        let validRefund = refunds.reduce(0) { $0 + positiveCents($1.amount) }
        let gross = purchaseGrossCents(link)
        let activeAllocations = try context.fetch(FetchDescriptor<AssetRefundAllocation>())
        var allocatedByRefund: [UUID: Int] = [:]
        var allocatedToLink = 0
        for allocation in activeAllocations where
            allocation.statusRaw == active && allocation.assetTransactionLinkID == link.stableID {
            allocatedByRefund[allocation.refundTransactionID, default: 0] += max(0, allocation.allocatedRefundCents)
            allocatedToLink += max(0, allocation.allocatedRefundCents)
        }
        let target = gross == orderGross
            ? min(gross, validRefund)
            : min(gross, max(allocatedToLink, link.allocatedRefundCents))
        var remaining = max(0, target - allocatedToLink)
        for refund in refunds.sorted(by: { $0.createdAt < $1.createdAt }) where remaining > 0 {
            let available = max(0, positiveCents(refund.amount) - allocatedByRefund[refund.stableID, default: 0])
            let take = min(available, remaining)
            guard take > 0 else { continue }
            context.insert(AssetRefundAllocation(
                assetTransactionLinkID: link.stableID,
                refundTransactionID: refund.stableID,
                allocatedRefundCents: take
            ))
            allocatedByRefund[refund.stableID, default: 0] += take
            remaining -= take
            allocatedToLink += take
        }
        link.allocatedRefundCents = allocatedToLink
        refreshQuality(
            originalID: originalID,
            transactions: transactions,
            links: links,
            allocations: try context.fetch(FetchDescriptor<AssetRefundAllocation>()),
            now: Date()
        )
        syncAssetPurchasePrice(
            assetID: link.assetID,
            links: links,
            assets: try context.fetch(FetchDescriptor<PhysicalAsset>()),
            now: Date()
        )
    }

    /// Replaces the allocation decision for one refund in a single save.
    static func allocateRefund(
        refundTransactionID: UUID,
        allocationsByAssetID: [UUID: Int],
        untrackedCents: Int = 0,
        in context: ModelContext
    ) throws {
        guard untrackedCents >= 0,
              allocationsByAssetID.values.allSatisfy({ $0 >= 0 }) else {
            throw Error.invalidAmount
        }
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        guard let refund = transactions.first(where: { $0.stableID == refundTransactionID }),
              let originalID = refund.refundOfID,
              refund.amount < 0 else { throw Error.invalidRefund }
        let refundCents = positiveCents(refund.amount)
        guard refundCents > 0 else { throw Error.invalidRefund }
        let allLinks = try context.fetch(FetchDescriptor<AssetTransactionLink>())
        let orderLinks = allLinks.filter {
            $0.transactionID == originalID && isPurchaseLink($0)
        }
        guard !orderLinks.isEmpty else { throw Error.noPurchaseLinks }
        guard allocationsByAssetID.keys.allSatisfy({ key in
            orderLinks.contains { $0.assetID == key }
        }) else { throw Error.unknownAsset }

        let allAllocations = try context.fetch(FetchDescriptor<AssetRefundAllocation>())
        let currentAudits = allAllocations.filter {
            $0.refundTransactionID == refundTransactionID && $0.statusRaw == active
        }
        let oldByLink = currentAudits.reduce(into: [UUID: Int]()) { result, allocation in
            result[allocation.assetTransactionLinkID, default: 0] += max(0, allocation.allocatedRefundCents)
        }
        var proposed = [UUID: Int]()
        for link in orderLinks {
            let old = oldByLink[link.stableID, default: 0]
            guard link.allocatedRefundCents >= old else { throw Error.invalidOrderAllocation }
            proposed[link.stableID] = link.allocatedRefundCents - old
        }

        var requested = 0
        for (assetID, cents) in allocationsByAssetID where cents > 0 {
            let matching = orderLinks.filter { $0.assetID == assetID }
            guard matching.count == 1, let link = matching.first else { throw Error.unknownAsset }
            let limit = purchaseGrossCents(link) - proposed[link.stableID, default: 0]
            guard cents <= max(0, limit) else { throw Error.allocationExceedsLimit }
            proposed[link.stableID, default: 0] += cents
            requested += cents
        }
        guard requested + untrackedCents == refundCents else { throw Error.amountMismatch }

        let orderGross = transactions.first { $0.stableID == originalID }.map { positiveCents($0.amount) } ?? 0
        let validRefund = refunds(for: originalID, in: transactions)
            .reduce(0) { $0 + positiveCents($1.amount) }
        guard isValidOrderAllocation(
            orderGrossCents: orderGross,
            validRefundCents: validRefund,
            links: orderLinks,
            proposedRefundByLink: proposed
        ) else { throw Error.invalidOrderAllocation }

        let refundIDs = Set(
            transactions.filter { $0.refundOfID == originalID }.map(\.stableID)
        )
        let otherUntracked = allAllocations.reduce(0) { total, allocation in
            guard allocation.statusRaw == active,
                  allocation.assetTransactionLinkID == untrackedLinkID,
                  allocation.refundTransactionID != refundTransactionID,
                  refundIDs.contains(allocation.refundTransactionID) else { return total }
            return total + max(0, allocation.allocatedRefundCents)
        }
        let trackedGross = orderLinks.reduce(0) { $0 + purchaseGrossCents($1) }
        guard untrackedCents <= max(0, orderGross - trackedGross - otherUntracked) else {
            throw Error.allocationExceedsLimit
        }

        let assets = try context.fetch(FetchDescriptor<PhysicalAsset>())
        for link in orderLinks {
            guard let physicalAsset = assets.first(where: { $0.stableID == link.assetID }) else { continue }
            if physicalAsset.lifecycle == .returned,
               proposed[link.stableID, default: 0] != purchaseGrossCents(link) {
                throw Error.returnedAsset
            }
        }

        let now = Date()
        for allocation in currentAudits {
            allocation.statusRaw = reversed
            allocation.updatedAt = now
        }
        for link in orderLinks {
            link.allocatedRefundCents = proposed[link.stableID, default: 0]
            link.updatedAt = now
        }
        var insertedAllocations: [AssetRefundAllocation] = []
        for (assetID, cents) in allocationsByAssetID where cents > 0 {
            guard let link = orderLinks.first(where: { $0.assetID == assetID }) else { throw Error.unknownAsset }
            let allocation = AssetRefundAllocation(
                assetTransactionLinkID: link.stableID,
                refundTransactionID: refundTransactionID,
                allocatedRefundCents: cents
            )
            context.insert(allocation)
            insertedAllocations.append(allocation)
        }
        if untrackedCents > 0 {
            let allocation = AssetRefundAllocation(
                assetTransactionLinkID: untrackedLinkID,
                refundTransactionID: refundTransactionID,
                allocatedRefundCents: untrackedCents
            )
            context.insert(allocation)
            insertedAllocations.append(allocation)
        }
        let nextAllocations = allAllocations + insertedAllocations
        refreshQuality(
            originalID: originalID,
            transactions: transactions,
            links: orderLinks,
            allocations: nextAllocations,
            now: now
        )
        for link in orderLinks {
            syncAssetPurchasePrice(
                assetID: link.assetID,
                links: allLinks,
                assets: assets,
                now: now
            )
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Reverses active audits for refunds that are about to be deleted. The
    /// caller owns the final save so deletion and audit reversal stay together.
    static func reverseAllocations(
        for refundsToDelete: [MoneyTransaction],
        allTransactions: [MoneyTransaction],
        in context: ModelContext
    ) throws {
        let refundIDs = Set(refundsToDelete.map(\.stableID))
        guard !refundIDs.isEmpty else { return }
        let allAllocations = try context.fetch(FetchDescriptor<AssetRefundAllocation>())
        let links = try context.fetch(FetchDescriptor<AssetTransactionLink>())
        let assets = try context.fetch(FetchDescriptor<PhysicalAsset>())
        var affectedAssets = Set<UUID>()
        for allocation in allAllocations where
            refundIDs.contains(allocation.refundTransactionID) && allocation.statusRaw == active {
            if allocation.assetTransactionLinkID != untrackedLinkID,
               let link = links.first(where: { $0.stableID == allocation.assetTransactionLinkID }) {
                link.allocatedRefundCents = max(
                    0,
                    link.allocatedRefundCents - max(0, allocation.allocatedRefundCents)
                )
                link.updatedAt = Date()
                affectedAssets.insert(link.assetID)
            }
            allocation.statusRaw = reversed
            allocation.updatedAt = Date()
        }
        let remainingTransactions = allTransactions.filter { !refundIDs.contains($0.stableID) }
        let affectedOrders = Set(refundsToDelete.compactMap(\.refundOfID))
        for originalID in affectedOrders {
            refreshQuality(
                originalID: originalID,
                transactions: remainingTransactions,
                links: links.filter { $0.transactionID == originalID && isPurchaseLink($0) },
                allocations: allAllocations,
                now: Date()
            )
        }
        for assetID in affectedAssets {
            syncAssetPurchasePrice(assetID: assetID, links: links, assets: assets, now: Date())
        }
    }

    /// Removes a purchase link while preserving the asset's current net cost.
    /// Refund audit rows are reversed so a later deletion or reassignment cannot
    /// subtract the same refund a second time.
    static func unlinkPurchaseAllocation(
        _ link: AssetTransactionLink,
        in context: ModelContext
    ) throws {
        guard isPurchaseLink(link) else { throw Error.invalidPurchaseLink }
        let assets = try context.fetch(FetchDescriptor<PhysicalAsset>())
        guard let asset = assets.first(where: { $0.stableID == link.assetID }), !asset.isDeleted else {
            throw Error.unknownAsset
        }
        guard asset.lifecycle == .owned || asset.lifecycle == .idle else {
            throw Error.returnedAsset
        }

        let allLinks = try context.fetch(FetchDescriptor<AssetTransactionLink>())
        let allAllocations = try context.fetch(FetchDescriptor<AssetRefundAllocation>())
        let originalTransactions = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let preservedNetCents = max(
            0,
            purchaseGrossCents(link) - max(0, link.allocatedRefundCents)
        )
        let now = Date()
        for allocation in allAllocations where
            allocation.assetTransactionLinkID == link.stableID && allocation.statusRaw == active {
            allocation.statusRaw = reversed
            allocation.updatedAt = now
        }
        context.delete(link)

        let remainingAssetPurchaseLinks = allLinks.filter {
            $0.stableID != link.stableID &&
                $0.assetID == asset.stableID &&
                isPurchaseLink($0)
        }
        if remainingAssetPurchaseLinks.isEmpty {
            asset.sourceType = .historicalExisting
            asset.acquisitionCostSourceRaw = AssetAcquisitionCostSource.manual.rawValue
            asset.purchasePrice = Decimal(preservedNetCents) / Decimal(100)
        } else {
            syncAssetPurchasePrice(
                assetID: asset.stableID,
                links: allLinks.filter { $0.stableID != link.stableID },
                assets: assets,
                now: now
            )
        }

        let remainingOrderLinks = allLinks.filter {
            $0.stableID != link.stableID &&
                $0.transactionID == link.transactionID &&
                isPurchaseLink($0)
        }
        refreshQuality(
            originalID: link.transactionID,
            transactions: originalTransactions,
            links: remainingOrderLinks,
            allocations: allAllocations,
            now: now
        )
        context.insert(AssetEvent(
            assetID: asset.stableID,
            kind: .transactionUnlinked,
            occurredAt: now,
            value: Decimal(preservedNetCents) / Decimal(100),
            note: "解除购置账单关联，保留当前净购置成本"
        ))
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func isPurchaseLink(_ link: AssetTransactionLink) -> Bool {
        purchaseLinkTypes.contains(link.linkTypeRaw) && link.assetObjectType == "physical"
    }

    private static func positiveCents(_ amount: Decimal) -> Int {
        abs(MoneyNormalization.cents(amount))
    }

    private static func purchaseGrossCents(_ link: AssetTransactionLink) -> Int {
        link.allocatedGrossCents > 0
            ? link.allocatedGrossCents
            : max(0, MoneyNormalization.cents(link.amount))
    }

    private static func refunds(
        for originalID: UUID,
        in transactions: [MoneyTransaction]
    ) -> [MoneyTransaction] {
        transactions.filter { $0.refundOfID == originalID && $0.amount < 0 }
    }

    private static func isValidOrderAllocation(
        orderGrossCents: Int,
        validRefundCents: Int,
        links: [AssetTransactionLink],
        proposedRefundByLink: [UUID: Int]
    ) -> Bool {
        do {
            _ = try AssetAllocationPolicy.validate(
                orderGrossCents: orderGrossCents,
                validOrderRefundCents: validRefundCents,
                lines: links.map {
                    AssetAllocationLine(
                        assetID: $0.assetID,
                        grossCents: purchaseGrossCents($0),
                        refundCents: proposedRefundByLink[$0.stableID, default: $0.allocatedRefundCents]
                    )
                }
            )
            return true
        } catch {
            return false
        }
    }

    private static func refreshQuality(
        originalID: UUID,
        transactions: [MoneyTransaction],
        links: [AssetTransactionLink],
        allocations: [AssetRefundAllocation],
        now: Date
    ) {
        guard !links.isEmpty else { return }
        let validRefund = refunds(for: originalID, in: transactions)
            .reduce(0) { $0 + positiveCents($1.amount) }
        let refundIDs = Set(
            transactions.filter { $0.refundOfID == originalID }.map(\.stableID)
        )
        let untracked = allocations.reduce(0) { total, allocation in
            guard allocation.statusRaw == active,
                  allocation.assetTransactionLinkID == untrackedLinkID,
                  refundIDs.contains(allocation.refundTransactionID) else { return total }
            return total + max(0, allocation.allocatedRefundCents)
        }
        let allocated = links.reduce(0) { $0 + max(0, $1.allocatedRefundCents) }
        let quality: AssetAllocationCostQuality = allocated + untracked < validRefund
            ? .pendingRefundAllocation
            : links.contains(where: { purchaseGrossCents($0) <= 0 })
                ? .partial
                : .exact
        for link in links {
            link.costQualityRaw = quality.rawValue
            link.updatedAt = now
        }
    }

    private static func syncAssetPurchasePrice(
        assetID: UUID,
        links: [AssetTransactionLink],
        assets: [PhysicalAsset],
        now: Date
    ) {
        guard let asset = assets.first(where: { $0.stableID == assetID }) else { return }
        let purchaseLinks = links.filter { $0.assetID == assetID && isPurchaseLink($0) }
        guard !purchaseLinks.isEmpty else { return }
        let netCents = purchaseLinks.reduce(0) {
            $0 + purchaseGrossCents($1) - max(0, $1.allocatedRefundCents)
        }
        asset.purchasePrice = Decimal(netCents) / Decimal(100)
        asset.acquisitionCostSourceRaw = AssetAcquisitionCostSource.transactionAllocations.rawValue
        asset.updatedAt = now
    }
}
