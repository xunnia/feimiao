import Foundation

/// 平台无关的流水数据，用于统计、导入导出等纯逻辑场景。
/// App 层的 SwiftData 模型与本类型互相转换。
public struct TransactionRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var kind: TransactionKind
    public var amount: Decimal
    public var currencyCode: String
    public var categoryName: String
    public var categoryKey: String
    public var topCategoryName: String
    public var topCategoryKey: String
    public var accountID: UUID?
    public var accountName: String
    /// 转账目标账户名，仅 kind == .transfer 时有意义。
    public var toAccountID: UUID?
    public var toAccountName: String
    public var bookID: UUID?
    public var note: String
    public var merchant: String
    public var product: String
    public var date: Date
    public var timePrecision: TransactionTimePrecision
    public var createdAt: Date?
    public var settledAt: Date?
    public var settlementQuality: SettlementQuality
    public var settlementAccountID: UUID?
    public var settlementAccountQuality: SettlementQuality
    public var eventType: TransactionEventType
    public var tags: [String]
    public var reimbursable: Bool
    public var isReimbursed: Bool
    public var attachmentPath: String
    public var orderNo: String
    public var recurringRuleID: UUID?
    /// 退款归属原交易；统计层仍可按负支出参与净额计算。
    public var refundOfID: UUID?
    public var isExcluded: Bool

    /// 净额为正的原始消费家族才计作一笔支出。
    public var countsAsExpenseFamily: Bool {
        kind == .expense && amount > 0
    }

    /// 金额为正的普通收入事件才计作收入笔数。
    public var countsAsIncomeEvent: Bool {
        kind == .income && amount > 0
    }

    public init(
        id: UUID = UUID(),
        kind: TransactionKind,
        amount: Decimal,
        currencyCode: String = "CNY",
        categoryName: String = "",
        categoryKey: String = "",
        topCategoryName: String = "",
        topCategoryKey: String = "",
        accountID: UUID? = nil,
        accountName: String = "",
        toAccountID: UUID? = nil,
        toAccountName: String = "",
        bookID: UUID? = nil,
        note: String = "",
        merchant: String = "",
        product: String = "",
        date: Date,
        timePrecision: TransactionTimePrecision = .legacyUnknown,
        createdAt: Date? = nil,
        settledAt: Date? = nil,
        settlementQuality: SettlementQuality = .unknown,
        settlementAccountID: UUID? = nil,
        settlementAccountQuality: SettlementQuality = .unknown,
        eventType: TransactionEventType? = nil,
        tags: [String] = [],
        reimbursable: Bool = false,
        isReimbursed: Bool = false,
        attachmentPath: String = "",
        orderNo: String = "",
        recurringRuleID: UUID? = nil,
        refundOfID: UUID? = nil,
        isExcluded: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryName = categoryName
        self.categoryKey = categoryKey
        self.topCategoryName = topCategoryName
        self.topCategoryKey = topCategoryKey
        self.accountID = accountID
        self.accountName = accountName
        self.toAccountID = toAccountID
        self.toAccountName = toAccountName
        self.bookID = bookID
        self.note = note
        self.merchant = merchant
        self.product = product
        self.date = date
        self.timePrecision = timePrecision
        self.createdAt = createdAt
        self.settledAt = settledAt
        self.settlementQuality = settlementQuality
        self.settlementAccountID = settlementAccountID
        self.settlementAccountQuality = settlementAccountQuality
        self.eventType = eventType ?? .defaultFor(kind)
        self.tags = tags
        self.reimbursable = reimbursable
        self.isReimbursed = isReimbursed
        self.attachmentPath = attachmentPath
        self.orderNo = orderNo
        self.recurringRuleID = recurringRuleID
        self.refundOfID = refundOfID
        self.isExcluded = isExcluded
    }

    /// 返回金额替换后的副本，供账务策略折叠退款家族使用。
    public func withAmount(_ amount: Decimal) -> TransactionRecord {
        var copy = self
        copy.amount = amount
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, amount, currencyCode, categoryName, categoryKey
        case topCategoryName, topCategoryKey, accountID, accountName
        case toAccountID, toAccountName, bookID, note, merchant, product, date, timePrecision
        case createdAt, settledAt, settlementQuality, settlementAccountID
        case settlementAccountQuality, eventType, tags, reimbursable, isReimbursed
        case attachmentPath, orderNo, recurringRuleID, refundOfID, isExcluded
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try values.decode(TransactionKind.self, forKey: .kind)
        amount = try values.decode(Decimal.self, forKey: .amount)
        currencyCode = try values.decodeIfPresent(String.self, forKey: .currencyCode) ?? "CNY"
        categoryName = try values.decodeIfPresent(String.self, forKey: .categoryName) ?? ""
        categoryKey = try values.decodeIfPresent(String.self, forKey: .categoryKey) ?? ""
        topCategoryName = try values.decodeIfPresent(String.self, forKey: .topCategoryName) ?? ""
        topCategoryKey = try values.decodeIfPresent(String.self, forKey: .topCategoryKey) ?? ""
        accountID = try values.decodeIfPresent(UUID.self, forKey: .accountID)
        accountName = try values.decodeIfPresent(String.self, forKey: .accountName) ?? ""
        toAccountID = try values.decodeIfPresent(UUID.self, forKey: .toAccountID)
        toAccountName = try values.decodeIfPresent(String.self, forKey: .toAccountName) ?? ""
        bookID = try values.decodeIfPresent(UUID.self, forKey: .bookID)
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        merchant = try values.decodeIfPresent(String.self, forKey: .merchant) ?? ""
        product = try values.decodeIfPresent(String.self, forKey: .product) ?? ""
        date = try values.decode(Date.self, forKey: .date)
        timePrecision = try values.decodeIfPresent(TransactionTimePrecision.self, forKey: .timePrecision) ?? .legacyUnknown
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt)
        settledAt = try values.decodeIfPresent(Date.self, forKey: .settledAt)
        settlementQuality = try values.decodeIfPresent(SettlementQuality.self, forKey: .settlementQuality) ?? .unknown
        settlementAccountID = try values.decodeIfPresent(UUID.self, forKey: .settlementAccountID)
        settlementAccountQuality = try values.decodeIfPresent(SettlementQuality.self, forKey: .settlementAccountQuality) ?? .unknown
        eventType = try values.decodeIfPresent(TransactionEventType.self, forKey: .eventType) ?? .defaultFor(kind)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        reimbursable = try values.decodeIfPresent(Bool.self, forKey: .reimbursable) ?? false
        isReimbursed = try values.decodeIfPresent(Bool.self, forKey: .isReimbursed) ?? false
        attachmentPath = try values.decodeIfPresent(String.self, forKey: .attachmentPath) ?? ""
        orderNo = try values.decodeIfPresent(String.self, forKey: .orderNo) ?? ""
        recurringRuleID = try values.decodeIfPresent(UUID.self, forKey: .recurringRuleID)
        refundOfID = try values.decodeIfPresent(UUID.self, forKey: .refundOfID)
        isExcluded = try values.decodeIfPresent(Bool.self, forKey: .isExcluded) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(amount, forKey: .amount)
        try values.encode(currencyCode, forKey: .currencyCode)
        try values.encode(categoryName, forKey: .categoryName)
        try values.encode(categoryKey, forKey: .categoryKey)
        try values.encode(topCategoryName, forKey: .topCategoryName)
        try values.encode(topCategoryKey, forKey: .topCategoryKey)
        try values.encodeIfPresent(accountID, forKey: .accountID)
        try values.encode(accountName, forKey: .accountName)
        try values.encodeIfPresent(toAccountID, forKey: .toAccountID)
        try values.encode(toAccountName, forKey: .toAccountName)
        try values.encodeIfPresent(bookID, forKey: .bookID)
        try values.encode(note, forKey: .note)
        try values.encode(merchant, forKey: .merchant)
        try values.encode(product, forKey: .product)
        try values.encode(date, forKey: .date)
        try values.encode(timePrecision, forKey: .timePrecision)
        try values.encodeIfPresent(createdAt, forKey: .createdAt)
        try values.encodeIfPresent(settledAt, forKey: .settledAt)
        try values.encode(settlementQuality, forKey: .settlementQuality)
        try values.encodeIfPresent(settlementAccountID, forKey: .settlementAccountID)
        try values.encode(settlementAccountQuality, forKey: .settlementAccountQuality)
        try values.encode(eventType, forKey: .eventType)
        try values.encode(tags, forKey: .tags)
        try values.encode(reimbursable, forKey: .reimbursable)
        try values.encode(isReimbursed, forKey: .isReimbursed)
        try values.encode(attachmentPath, forKey: .attachmentPath)
        try values.encode(orderNo, forKey: .orderNo)
        try values.encodeIfPresent(recurringRuleID, forKey: .recurringRuleID)
        try values.encodeIfPresent(refundOfID, forKey: .refundOfID)
        try values.encode(isExcluded, forKey: .isExcluded)
    }
}
