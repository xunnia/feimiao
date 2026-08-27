import Foundation

/// 一笔流水的类型：支出 / 收入 / 转账。
public enum TransactionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case expense
    case income
    case transfer
}
