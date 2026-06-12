import Foundation
import SwiftData
import QingJiCore

// 所有属性带默认值、关系全部可选、不用 .unique 约束 ——
// 这是 SwiftData + CloudKit 同步的硬性要求，开启 iCloud 能力后即可自动同步。

/// 资金账户（现金、银行卡、微信、支付宝……）。
@Model
final class Account {
    var name: String = ""
    var kindRaw: String = AccountKind.cash.rawValue
    var currencyCode: String = "CNY"
    var initialBalance: Decimal = 0
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \MoneyTransaction.account)
    var outgoingTransactions: [MoneyTransaction]? = nil
    @Relationship(deleteRule: .nullify, inverse: \MoneyTransaction.toAccount)
    var incomingTransfers: [MoneyTransaction]? = nil

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    init(name: String, kind: AccountKind, currencyCode: String = "CNY", sortOrder: Int = 0) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.currencyCode = currencyCode
        self.sortOrder = sortOrder
    }
}

/// 收支分类。（命名避开 SwiftUI 的 Category/SwiftData 保留词）
@Model
final class TxCategory {
    /// 稳定标识（对应 CategorySeed.key），自定义分类用 UUID 字符串。
    var key: String = ""
    var name: String = ""
    var symbol: String = "tag"
    var kindRaw: String = TransactionKind.expense.rawValue
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \MoneyTransaction.category)
    var transactions: [MoneyTransaction]? = nil

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    init(key: String, name: String, symbol: String, kind: TransactionKind, sortOrder: Int = 0) {
        self.key = key
        self.name = name
        self.symbol = symbol
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
    }
}

/// 一笔流水。（命名避开 SwiftUI.Transaction）
@Model
final class MoneyTransaction {
    var amount: Decimal = 0
    var kindRaw: String = TransactionKind.expense.rawValue
    var date: Date = Date()
    var note: String = ""
    var currencyCode: String = "CNY"
    var createdAt: Date = Date()

    var category: TxCategory? = nil
    var account: Account? = nil
    /// 转账的目标账户，仅 kind == .transfer 时有值。
    var toAccount: Account? = nil

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    init(
        amount: Decimal,
        kind: TransactionKind,
        date: Date = Date(),
        note: String = "",
        currencyCode: String = "CNY",
        category: TxCategory? = nil,
        account: Account? = nil,
        toAccount: Account? = nil
    ) {
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.date = date
        self.note = note
        self.currencyCode = currencyCode
        self.category = category
        self.account = account
        self.toAccount = toAccount
    }

    /// 转换为平台无关的 DTO，供统计引擎与导出使用。
    var record: TransactionRecord {
        TransactionRecord(
            kind: kind,
            amount: amount,
            currencyCode: currencyCode,
            categoryName: category?.name ?? "",
            accountName: account?.name ?? "",
            note: note,
            date: date
        )
    }
}
