import Foundation

public enum AssetAcquisitionCostSource: String, Codable, CaseIterable, Hashable, Sendable {
    case transactionAllocations = "transaction_allocations"
    case manual
    case manualUnknown = "manual_unknown"
}

public enum AssetAllocationCostQuality: String, Codable, CaseIterable, Hashable, Sendable {
    case exact
    case partial
    case pendingRefundAllocation = "pending_refund_allocation"
    case manualUnverified = "manual_unverified"
}

public struct AssetAllocationLine: Equatable, Sendable {
    public let assetID: UUID
    public let grossCents: Int
    public let refundCents: Int

    public init(assetID: UUID, grossCents: Int, refundCents: Int) {
        self.assetID = assetID
        self.grossCents = grossCents
        self.refundCents = refundCents
    }

    public var netCents: Int { grossCents - refundCents }
}

public struct AssetAllocationTotals: Equatable, Sendable {
    public let grossCents: Int
    public let refundCents: Int
    public let netCents: Int

    public init(grossCents: Int, refundCents: Int, netCents: Int) {
        self.grossCents = grossCents
        self.refundCents = refundCents
        self.netCents = netCents
    }
}

public enum AssetAllocationPolicy {
    public static func validate(
        orderGrossCents: Int,
        validOrderRefundCents: Int,
        lines: some Sequence<AssetAllocationLine>
    ) throws -> AssetAllocationTotals {
        guard orderGrossCents >= 0,
              validOrderRefundCents >= 0,
              validOrderRefundCents <= orderGrossCents else {
            throw AssetAllocationError.invalidOrder
        }
        var gross = 0
        var refund = 0
        var assetIDs = Set<UUID>()
        for line in lines {
            guard assetIDs.insert(line.assetID).inserted else {
                throw AssetAllocationError.duplicateAsset
            }
            guard line.grossCents >= 0,
                  line.refundCents >= 0,
                  line.refundCents <= line.grossCents else {
                throw AssetAllocationError.invalidLine
            }
            gross += line.grossCents
            refund += line.refundCents
        }
        guard gross <= orderGrossCents else { throw AssetAllocationError.grossExceedsOrder }
        guard refund <= validOrderRefundCents else { throw AssetAllocationError.refundExceedsOrder }
        let net = gross - refund
        guard net <= orderGrossCents - validOrderRefundCents else {
            throw AssetAllocationError.netExceedsOrder
        }
        return AssetAllocationTotals(grossCents: gross, refundCents: refund, netCents: net)
    }
}

public enum AssetAllocationError: Error, Equatable, Sendable {
    case invalidOrder
    case duplicateAsset
    case invalidLine
    case grossExceedsOrder
    case refundExceedsOrder
    case netExceedsOrder
}
