import Foundation

public enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income
    case transfer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        }
    }
}

public enum TransactionTimePrecision: String, Codable, CaseIterable, Sendable {
    case exact
    case entryClock = "entry_clock"
    case dateOnly = "date_only"
    case legacyUnknown = "legacy_unknown"
}

public struct LedgerBook: Identifiable, Hashable, Codable {
    public var id: Int64
    public var uuid: String
    public var name: String
    public var icon: String
    public var cover: String
    public var remark: String
    public var sortOrder: Int
    public var createdAt: Date
    public var isStarred: Bool
    public var includeInTotal: Bool
    public var updatedAt: Date
    public var isDeleted: Bool
    public var deletedAt: Date?

    public init(
        id: Int64,
        uuid: String,
        name: String,
        icon: String = "📒",
        cover: String = "",
        remark: String = "",
        sortOrder: Int = 0,
        createdAt: Date = .now,
        isStarred: Bool = false,
        includeInTotal: Bool = true,
        updatedAt: Date = .now,
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.icon = icon
        self.cover = cover
        self.remark = remark
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.isStarred = isStarred
        self.includeInTotal = includeInTotal
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }
}

public enum LedgerAccountStatus: String, Codable, Sendable {
    case active
    case archived
    case legacyHidden = "legacy_hidden"
}

public struct LedgerAccount: Identifiable, Hashable, Codable {
    public var id: Int64
    public var uuid: String
    public var name: String
    public var currencyCode: String
    public var type: String
    public var openingBalance: MoneyAmount
    public var includeInNetWorth: Bool
    public var institution: String
    public var sortOrder: Int
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isDeleted: Bool
    public var deletedAt: Date?

    public init(
        id: Int64,
        uuid: String,
        name: String,
        currencyCode: String = "CNY",
        type: String = "cash",
        openingBalance: MoneyAmount = .zero,
        includeInNetWorth: Bool = true,
        institution: String = "",
        sortOrder: Int = 0,
        status: String = LedgerAccountStatus.active.rawValue,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.currencyCode = currencyCode
        self.type = type
        self.openingBalance = openingBalance
        self.includeInNetWorth = includeInNetWorth
        self.institution = institution
        self.sortOrder = sortOrder
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }

    /// Archived and legacy-hidden accounts remain available for historical
    /// rendering, but only active accounts may be used by a new transaction.
    public var isAvailableForNewTransactions: Bool {
        status == LedgerAccountStatus.active.rawValue && !isDeleted
    }

    public var isArchived: Bool {
        status == LedgerAccountStatus.archived.rawValue && !isDeleted
    }
}

public struct LedgerCategory: Identifiable, Hashable, Codable {
    public var id: Int64
    public var uuid: String
    public var key: String
    public var nameZh: String
    public var nameEn: String
    public var emoji: String
    public var kind: TransactionKind
    public var parentID: Int64?
    public var isHidden: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var isDeleted: Bool
    public var deletedAt: Date?

    public init(
        id: Int64,
        uuid: String,
        key: String,
        nameZh: String,
        nameEn: String,
        emoji: String,
        kind: TransactionKind,
        parentID: Int64? = nil,
        isHidden: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.key = key
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.emoji = emoji
        self.kind = kind
        self.parentID = parentID
        self.isHidden = isHidden
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }
}

public struct LedgerTag: Identifiable, Hashable, Codable {
    public var id: Int64
    public var uuid: String
    public var name: String
    public var colorARGB: Int64
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var isDeleted: Bool
    public var deletedAt: Date?

    public init(
        id: Int64,
        uuid: String,
        name: String,
        colorARGB: Int64 = 4_286_351_771,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.colorARGB = colorARGB
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }
}

public struct LedgerTransaction: Identifiable, Hashable, Codable {
    public var id: Int64
    public var uuid: String
    public var bookID: Int64?
    public var kind: TransactionKind
    public var amount: MoneyAmount
    public var currencyCode: String
    public var categoryID: Int64?
    public var accountID: Int64?
    public var toAccountID: Int64?
    public var note: String
    public var date: Date
    public var timePrecision: TransactionTimePrecision
    public var tagIDs: [Int64]
    public var isReimbursable: Bool
    public var imagePath: String
    public var isExcluded: Bool
    public var refundOf: Int64?
    public var createdAt: Date
    public var updatedAt: Date
    public var isDeleted: Bool
    public var deletedAt: Date?

    public init(
        id: Int64,
        uuid: String,
        bookID: Int64?,
        kind: TransactionKind,
        amount: MoneyAmount,
        currencyCode: String = "CNY",
        categoryID: Int64? = nil,
        accountID: Int64? = nil,
        toAccountID: Int64? = nil,
        note: String = "",
        date: Date,
        timePrecision: TransactionTimePrecision = .exact,
        tagIDs: [Int64] = [],
        isReimbursable: Bool = false,
        imagePath: String = "",
        isExcluded: Bool = false,
        refundOf: Int64? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.bookID = bookID
        self.kind = kind
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryID = categoryID
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.note = note
        self.date = date
        self.timePrecision = timePrecision
        self.tagIDs = tagIDs
        self.isReimbursable = isReimbursable
        self.imagePath = imagePath
        self.isExcluded = isExcluded
        self.refundOf = refundOf
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }
}

public struct TransactionRefundDetails: Hashable, Codable {
    public var transaction: LedgerTransaction
    public var refunds: [LedgerTransaction]
    public var refundedAmount: MoneyAmount
    public var refundableAmount: MoneyAmount

    public init(
        transaction: LedgerTransaction,
        refunds: [LedgerTransaction],
        refundedAmount: MoneyAmount,
        refundableAmount: MoneyAmount
    ) {
        self.transaction = transaction
        self.refunds = refunds
        self.refundedAmount = refundedAmount
        self.refundableAmount = refundableAmount
    }

    public var netAmount: MoneyAmount {
        transaction.amount - refundedAmount
    }

    public var isFullyRefunded: Bool {
        refundableAmount == .zero
    }
}

public struct TransactionFilter: Hashable, Sendable {
    public var bookID: Int64?
    public var kind: TransactionKind?
    public var searchText: String
    public var startDate: Date?
    public var endDate: Date?
    public var includeExcluded: Bool

    public init(
        bookID: Int64? = nil,
        kind: TransactionKind? = nil,
        searchText: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        includeExcluded: Bool = true
    ) {
        self.bookID = bookID
        self.kind = kind
        self.searchText = searchText
        self.startDate = startDate
        self.endDate = endDate
        self.includeExcluded = includeExcluded
    }
}

public struct LedgerSummary: Hashable, Sendable {
    public var expense: MoneyAmount
    public var income: MoneyAmount
    public var transactionCount: Int

    public init(expense: MoneyAmount = .zero, income: MoneyAmount = .zero, transactionCount: Int = 0) {
        self.expense = expense
        self.income = income
        self.transactionCount = transactionCount
    }

    public var balance: MoneyAmount { income - expense }
}

public struct TransactionDraft: Hashable {
    public var id: Int64?
    public var bookID: Int64?
    public var kind: TransactionKind
    public var amountText: String
    public var currencyCode: String
    public var categoryID: Int64?
    public var accountID: Int64?
    public var toAccountID: Int64?
    public var note: String
    public var date: Date
    public var timePrecision: TransactionTimePrecision
    public var tagIDs: [Int64]
    public var isReimbursable: Bool
    public var imagePath: String
    public var isExcluded: Bool

    public init(
        id: Int64? = nil,
        bookID: Int64? = nil,
        kind: TransactionKind = .expense,
        amountText: String = "",
        currencyCode: String = "CNY",
        categoryID: Int64? = nil,
        accountID: Int64? = nil,
        toAccountID: Int64? = nil,
        note: String = "",
        date: Date = .now,
        timePrecision: TransactionTimePrecision = .exact,
        tagIDs: [Int64] = [],
        isReimbursable: Bool = false,
        imagePath: String = "",
        isExcluded: Bool = false
    ) {
        self.id = id
        self.bookID = bookID
        self.kind = kind
        self.amountText = amountText
        self.currencyCode = currencyCode
        self.categoryID = categoryID
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.note = note
        self.date = date
        self.timePrecision = timePrecision
        self.tagIDs = tagIDs
        self.isReimbursable = isReimbursable
        self.imagePath = imagePath
        self.isExcluded = isExcluded
    }

    public var validatedAmount: MoneyAmount? {
        guard let amount = MoneyAmount(amountText), amount > .zero else { return nil }
        return amount
    }
}
