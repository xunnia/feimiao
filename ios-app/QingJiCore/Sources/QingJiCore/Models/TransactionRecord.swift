import Foundation

/// 平台无关的流水数据，用于统计、导入导出等纯逻辑场景。
/// App 层的 SwiftData 模型与本类型互相转换。
public struct TransactionRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var kind: TransactionKind
    public var amount: Decimal
    public var currencyCode: String
    public var categoryName: String
    public var accountName: String
    /// 转账目标账户名，仅 kind == .transfer 时有意义。
    public var toAccountName: String
    public var note: String
    public var date: Date

    public init(
        id: UUID = UUID(),
        kind: TransactionKind,
        amount: Decimal,
        currencyCode: String = "CNY",
        categoryName: String = "",
        accountName: String = "",
        toAccountName: String = "",
        note: String = "",
        date: Date
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryName = categoryName
        self.accountName = accountName
        self.toAccountName = toAccountName
        self.note = note
        self.date = date
    }
}
