import Foundation

/// 账户生命周期状态，与 Android 端的状态值保持一致。
public enum AccountStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case active
    case archived
    case legacyHidden = "legacy_hidden"
}

/// 账户期初余额的可信程度。
public enum AccountOpeningBalanceQuality: String, Codable, CaseIterable, Hashable, Sendable {
    case exact
    case userConfirmed = "user_confirmed"
    case legacyAssumed = "legacy_assumed"
    case legacyUnknown = "legacy_unknown"
}

/// 负债账户的余额解释方式。
public enum LiabilityBalanceMode: String, Codable, CaseIterable, Hashable, Sendable {
    case legacyHybrid = "legacy_hybrid"
    case ledger
}
