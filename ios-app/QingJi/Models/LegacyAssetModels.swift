import Foundation
import SwiftData
import QingJiCore

/// Exact persisted PhysicalAsset/ReceivableAsset declarations of V1 (b40316f) and
/// V2 (9c0323c), when the soft-delete flag was still stored as isDeleted. The
/// current classes rename it to isSoftDeleted because isDeleted clashes with
/// NSManagedObject.isDeleted; these copies keep the V1/V2 checksums unchanged.
/// Never add current fields here.
enum LegacyAssetModels {
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

        var sourceType: PhysicalAssetSourceType {
            get { PhysicalAssetSourceType(rawValue: sourceTypeRaw) ?? .historicalExisting }
            set { sourceTypeRaw = newValue.rawValue }
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
}
