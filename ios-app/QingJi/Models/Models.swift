import Foundation
import SwiftData
import QingJiCore

// 所有属性带默认值、关系全部可选、不用 .unique 约束 ——
// 这是 SwiftData + CloudKit 同步的硬性要求，开启 iCloud 能力后即可自动同步。

/// 资金账户（现金、银行卡、微信、支付宝……）。
@Model
final class Account {
    var stableID: UUID = UUID()
    var name: String = ""
    var kindRaw: String = AccountKind.cash.rawValue
    var currencyCode: String = "CNY"
    var initialBalance: Decimal = 0
    var institution: String = ""
    var includeInNetWorth: Bool = true
    var isDeleted: Bool = false
    var statusRaw: String = AccountStatus.active.rawValue
    var archivedAt: Date? = nil
    var lastVerifiedAt: Date? = nil
    var openingBalanceEffectiveAt: Date? = nil
    var openingBalanceQualityRaw: String = AccountOpeningBalanceQuality.legacyUnknown.rawValue
    var balanceModeRaw: String = LiabilityBalanceMode.legacyHybrid.rawValue
    var creditStatementDay: Int? = nil
    var creditPaymentDay: Int? = nil
    var creditLimit: Decimal? = nil
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \MoneyTransaction.account)
    var outgoingTransactions: [MoneyTransaction]? = nil
    @Relationship(deleteRule: .nullify, inverse: \MoneyTransaction.toAccount)
    var incomingTransfers: [MoneyTransaction]? = nil

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var status: AccountStatus {
        get { AccountStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var openingBalanceQuality: AccountOpeningBalanceQuality {
        get { AccountOpeningBalanceQuality(rawValue: openingBalanceQualityRaw) ?? .legacyUnknown }
        set { openingBalanceQualityRaw = newValue.rawValue }
    }

    var balanceMode: LiabilityBalanceMode {
        get { LiabilityBalanceMode(rawValue: balanceModeRaw) ?? .legacyHybrid }
        set { balanceModeRaw = newValue.rawValue }
    }

    init(name: String, kind: AccountKind, currencyCode: String = "CNY", sortOrder: Int = 0) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.currencyCode = currencyCode
        self.sortOrder = sortOrder
    }
}

/// 账本。默认账本相当于安卓端的「总账本」，其他账本可选择是否计入总账。
@Model
final class Book {
    var stableID: UUID = UUID()
    var name: String = ""
    var cover: String = ""
    var remark: String = ""
    var sortOrder: Int = 0
    var isStarred: Bool = false
    var includeInTotal: Bool = true
    var isDefault: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \MoneyTransaction.book)
    var transactions: [MoneyTransaction]? = nil

    init(
        name: String,
        cover: String = "",
        remark: String = "",
        sortOrder: Int = 0,
        isStarred: Bool = false,
        includeInTotal: Bool = true,
        isDefault: Bool = false
    ) {
        self.name = name
        self.cover = cover
        self.remark = remark
        self.sortOrder = sortOrder
        self.isStarred = isStarred
        self.includeInTotal = includeInTotal
        self.isDefault = isDefault
    }
}

/// 收支分类。（命名避开 SwiftUI 的 Category/SwiftData 保留词）
@Model
final class TxCategory {
    /// 稳定标识（对应 CategorySeed.key），自定义分类用 UUID 字符串。
    var key: String = ""
    var name: String = ""
    var symbol: String = "tag"
    var emoji: String = "🏷️"
    var kindRaw: String = TransactionKind.expense.rawValue
    var parentKey: String? = nil
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \MoneyTransaction.category)
    var transactions: [MoneyTransaction]? = nil

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    init(
        key: String,
        name: String,
        symbol: String,
        kind: TransactionKind,
        sortOrder: Int = 0,
        emoji: String = "🏷️",
        parentKey: String? = nil
    ) {
        self.key = key
        self.name = name
        self.symbol = symbol
        self.emoji = emoji
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.parentKey = parentKey
    }
}

/// 用户自定义标签。交易暂时以稳定名称快照保存，便于备份跨平台迁移。
@Model
final class Tag {
    var stableID: UUID = UUID()
    var name: String = ""
    var colorValue: Int = 0x7D8B9B
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, colorValue: Int = 0x7D8B9B, sortOrder: Int = 0) {
        self.name = name
        self.colorValue = colorValue
        self.sortOrder = sortOrder
    }
}

/// 一笔流水。（命名避开 SwiftUI.Transaction）
@Model
final class MoneyTransaction {
    var stableID: UUID = UUID()
    var amount: Decimal = 0
    var kindRaw: String = TransactionKind.expense.rawValue
    var date: Date = Date()
    var note: String = ""
    /// 外部账单的交易对方和商品分开保存，便于退款匹配与分类学习。
    var merchantName: String = ""
    var productName: String = ""
    var currencyCode: String = "CNY"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var timePrecisionRaw: String = TransactionTimePrecision.legacyUnknown.rawValue
    var settledAt: Date? = nil
    var settlementQualityRaw: String = SettlementQuality.unknown.rawValue
    /// 结算账户使用稳定 UUID，避免依赖 SwiftData 的对象关系或 Android 自增主键。
    var settlementAccountID: UUID? = nil
    var settlementAccountQualityRaw: String = SettlementQuality.unknown.rawValue
    var eventTypeRaw: String = TransactionEventType.legacyAdjustment.rawValue
    var attachmentPath: String = ""
    var orderNo: String = ""
    var recurringRuleID: UUID? = nil
    var reimbursable: Bool = false
    var refundOfID: UUID? = nil
    var isReimbursed: Bool = false
    var isExcluded: Bool = false
    /// 简单、可移植的标签存储；正式标签管理会在下一批换成独立实体。
    var tagNames: String = ""

    var category: TxCategory? = nil
    var account: Account? = nil
    var book: Book? = nil
    /// 转账的目标账户，仅 kind == .transfer 时有值。
    var toAccount: Account? = nil

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var timePrecision: TransactionTimePrecision {
        get { TransactionTimePrecision(rawValue: timePrecisionRaw) ?? .legacyUnknown }
        set { timePrecisionRaw = newValue.rawValue }
    }

    var settlementQuality: SettlementQuality {
        get { SettlementQuality(rawValue: settlementQualityRaw) ?? .unknown }
        set { settlementQualityRaw = newValue.rawValue }
    }

    var settlementAccountQuality: SettlementQuality {
        get { SettlementQuality(rawValue: settlementAccountQualityRaw) ?? .unknown }
        set { settlementAccountQualityRaw = newValue.rawValue }
    }

    var eventType: TransactionEventType {
        get { TransactionEventType(rawValue: eventTypeRaw) ?? .legacyAdjustment }
        set { eventTypeRaw = newValue.rawValue }
    }

    init(
        amount: Decimal,
        kind: TransactionKind,
        date: Date = Date(),
        note: String = "",
        merchantName: String = "",
        productName: String = "",
        currencyCode: String = "CNY",
        category: TxCategory? = nil,
        account: Account? = nil,
        toAccount: Account? = nil,
        book: Book? = nil,
        stableID: UUID = UUID(),
        timePrecision: TransactionTimePrecision = .exact,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        settledAt: Date? = nil,
        settlementQuality: SettlementQuality = .unknown,
        settlementAccountID: UUID? = nil,
        settlementAccountQuality: SettlementQuality = .unknown,
        eventType: TransactionEventType? = nil,
        attachmentPath: String = "",
        orderNo: String = "",
        recurringRuleID: UUID? = nil,
        reimbursable: Bool = false,
        refundOfID: UUID? = nil,
        isReimbursed: Bool = false,
        isExcluded: Bool = false,
        tagNames: String = ""
    ) {
        self.stableID = stableID
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.date = date
        self.note = note
        self.merchantName = merchantName
        self.productName = productName
        self.currencyCode = currencyCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.timePrecisionRaw = timePrecision.rawValue
        self.settledAt = settledAt
        self.settlementQualityRaw = settlementQuality.rawValue
        self.settlementAccountID = settlementAccountID
        self.settlementAccountQualityRaw = settlementAccountQuality.rawValue
        self.eventTypeRaw = (eventType ?? .defaultFor(kind)).rawValue
        self.attachmentPath = attachmentPath
        self.orderNo = orderNo
        self.recurringRuleID = recurringRuleID
        self.reimbursable = reimbursable
        self.category = category
        self.account = account
        self.toAccount = toAccount
        self.book = book
        self.refundOfID = refundOfID
        self.isReimbursed = isReimbursed
        self.isExcluded = isExcluded
        self.tagNames = tagNames
    }

    /// 转换为平台无关的 DTO，供统计引擎与导出使用。
    var record: TransactionRecord {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "zh"
        let topCategoryName: String = {
            guard let parentKey = category?.parentKey else { return category?.name ?? "" }
            return CategorySeed.byKey(parentKey)?.localizedName(languageCode: languageCode)
                ?? category?.name
                ?? ""
        }()
        let categoryName = category?.name ?? ""
        let categoryKey = category?.key ?? ""
        let topCategoryKey = category?.parentKey ?? category?.key ?? ""
        let accountID = account?.stableID
        let accountName = account?.name ?? ""
        let toAccountID = toAccount?.stableID
        let toAccountName = toAccount?.name ?? ""
        let bookID = book?.stableID
        return TransactionRecord(
            id: stableID,
            kind: kind,
            amount: amount,
            currencyCode: currencyCode,
            categoryName: categoryName,
            categoryKey: categoryKey,
            topCategoryName: topCategoryName,
            topCategoryKey: topCategoryKey,
            accountID: accountID,
            accountName: accountName,
            toAccountID: toAccountID,
            toAccountName: toAccountName,
            bookID: bookID,
            note: note,
            merchant: merchantName,
            product: productName,
            date: date,
            timePrecision: timePrecision,
            createdAt: createdAt,
            settledAt: settledAt,
            settlementQuality: settlementQuality,
            settlementAccountID: settlementAccountID,
            settlementAccountQuality: settlementAccountQuality,
            eventType: eventType,
            tags: tags,
            reimbursable: reimbursable,
            isReimbursed: isReimbursed,
            attachmentPath: attachmentPath,
            orderNo: orderNo,
            recurringRuleID: recurringRuleID,
            isExcluded: isExcluded,
            refundOfID: refundOfID
        )
    }

    var tags: [String] {
        get { tagNames.split(separator: ",").map(String.init) }
        set { tagNames = newValue.joined(separator: ",") }
    }
}

/// 月度预算。当前只用「总预算」一条记录（categoryKey == nil），
/// 字段已为今后的分类预算预留。
@Model
final class Budget {
    var stableID: UUID = UUID()
    var amount: Decimal = 0
    var categoryKey: String? = nil
    var bookID: UUID? = nil
    var periodStart: Date? = nil
    var periodEnd: Date? = nil
    var cycleRaw: String = "monthly"
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var cycle: BudgetCycle {
        get { BudgetCycle(rawValue: cycleRaw) ?? .monthly }
        set { cycleRaw = newValue.rawValue }
    }

    init(
        amount: Decimal,
        categoryKey: String? = nil,
        bookID: UUID? = nil,
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        cycleRaw: String = "monthly",
        isActive: Bool = true,
        stableID: UUID = UUID()
    ) {
        self.stableID = stableID
        self.amount = amount
        self.categoryKey = categoryKey
        self.bookID = bookID
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.cycleRaw = cycleRaw
        self.isActive = isActive
    }
}
