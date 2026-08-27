import Foundation

/// 时间字段的可信精度，与 Android 端 transaction_time.dart 保持同一存储值。
public enum TransactionTimePrecision: String, Codable, CaseIterable, Hashable, Sendable {
    case exact
    case entryClock = "entry_clock"
    case dateOnly = "date_only"
    case legacyUnknown = "legacy_unknown"

    /// 是否应在账单行中展示时分。
    public var carriesClock: Bool {
        switch self {
        case .exact, .entryClock:
            return true
        case .dateOnly:
            return false
        case .legacyUnknown:
            return false
        }
    }
}

/// 结算日期和结算账户的可信程度。
public enum SettlementQuality: String, Codable, CaseIterable, Hashable, Sendable {
    case exact
    case userConfirmed = "user_confirmed"
    case legacyAssumed = "legacy_assumed"
    case unknown
}

/// 账户活动的事件类型。
///
/// `legacyAdjustment` 用来兼容旧版只保存 kind 的流水；新写入的退款、报销、
/// 资产买卖和还款必须写入明确事件类型，避免账户余额和净资产重复计算。
public enum TransactionEventType: String, Codable, CaseIterable, Hashable, Sendable {
    case expense
    case income
    case refund
    case reimbursement
    case transfer
    case assetPurchase = "asset_purchase"
    case assetSale = "asset_sale"
    case receivableRecovery = "receivable_recovery"
    case legacyAdjustment = "legacy_adjustment"
    case principalPayment = "principal_payment"
    case interest

    public static func defaultFor(_ kind: TransactionKind) -> TransactionEventType {
        switch kind {
        case .expense: return .expense
        case .income: return .income
        case .transfer: return .transfer
        }
    }
}
