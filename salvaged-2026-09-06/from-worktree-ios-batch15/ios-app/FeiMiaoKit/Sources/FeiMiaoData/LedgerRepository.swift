import Foundation
import GRDB
import FeiMiaoDomain

public enum LedgerRepositoryError: LocalizedError, Equatable {
    case invalidName
    case invalidAmount
    case missingAccount
    case sameTransferAccount
    case protectedDefaultBook
    case accountInUse
    case inactiveAccount
    case invalidAccountStatus
    case invalidCategoryParent
    case invalidDateRange
    case invalidRefundTarget
    case refundExceedsRemainingAmount
    case noRefundableAmount
    case recordNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidName: "名称不能为空"
        case .invalidAmount: "请输入大于 0 的金额"
        case .missingAccount: "请选择账户"
        case .sameTransferAccount: "转出和转入账户不能相同"
        case .protectedDefaultBook: "总账本不能删除"
        case .accountInUse: "账户已有历史账单，请先归档而不是删除"
        case .inactiveAccount: "归档账户不能用于新的记账，请先恢复账户"
        case .invalidAccountStatus: "账户状态无效"
        case .invalidCategoryParent: "二级分类必须归属于同类型的可见一级分类"
        case .invalidDateRange: "日期范围无效"
        case .invalidRefundTarget: "只有有效的支出账单可以退款"
        case .refundExceedsRemainingAmount: "退款金额超过剩余可退金额"
        case .noRefundableAmount: "这笔账单已经没有可退金额"
        case .recordNotFound: "记录不存在或已被删除"
        }
    }
}

public final class LedgerRepository: @unchecked Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Books

    public func books(includeDeleted: Bool = false) throws -> [LedgerBook] {
        try database.queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM books
                    \(includeDeleted ? "" : "WHERE is_deleted = 0")
                    ORDER BY starred DESC, sort_order ASC, id ASC
                    """
            )
            return rows.map(Self.book(from:))
        }
    }

    public func defaultBookID() throws -> Int64 {
        guard let id = try database.queue.read({ db in
            try Int64.fetchOne(
                db,
                sql: "SELECT id FROM books WHERE is_deleted = 0 ORDER BY sort_order ASC, id ASC LIMIT 1"
            )
        }) else { throw LedgerRepositoryError.recordNotFound }
        return id
    }

    @discardableResult
    public func createBook(
        name: String,
        icon: String = "📒",
        cover: String = "",
        remark: String = "",
        includeInTotal: Bool = true
    ) throws -> LedgerBook {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw LedgerRepositoryError.invalidName }
        let now = Self.nowMS
        let id = try database.queue.write { db -> Int64 in
            let order = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM books")) ?? 0
            try db.execute(
                sql: """
                    INSERT INTO books
                    (uuid, name, icon, cover, remark, sort_order, created_ms, starred,
                     include_in_total, updated_ms, is_deleted)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 0)
                    """,
                arguments: [
                    UUID().uuidString, cleanName, icon, cover, remark.trimmingCharacters(in: .whitespacesAndNewlines),
                    order, now, includeInTotal ? 1 : 0, now,
                ]
            )
            return db.lastInsertedRowID
        }
        return try book(id: id)
    }

    public func updateBook(_ book: LedgerBook) throws {
        let cleanName = book.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw LedgerRepositoryError.invalidName }
        try database.queue.write { db in
            let protectedID = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM books WHERE is_deleted = 0 ORDER BY sort_order, id LIMIT 1"
            )
            let includeInTotal = book.id == protectedID ? true : book.includeInTotal
            try db.execute(
                sql: """
                    UPDATE books SET name = ?, icon = ?, cover = ?, remark = ?, sort_order = ?,
                    starred = ?, include_in_total = ?, updated_ms = ?
                    WHERE id = ? AND is_deleted = 0
                    """,
                arguments: [
                    cleanName, book.icon, book.cover, book.remark, book.sortOrder,
                    book.isStarred ? 1 : 0, includeInTotal ? 1 : 0,
                    Self.nowMS, book.id,
                ]
            )
            guard db.changesCount == 1 else { throw LedgerRepositoryError.recordNotFound }
        }
    }

    public func deleteBook(id: Int64, moveTransactionsToDefault: Bool = true) throws {
        let defaultID = try defaultBookID()
        guard id != defaultID else { throw LedgerRepositoryError.protectedDefaultBook }
        try database.queue.write { db in
            if moveTransactionsToDefault {
                try db.execute(
                    sql: "UPDATE transactions SET book_id = ?, updated_ms = ? WHERE book_id = ? AND is_deleted = 0",
                    arguments: [defaultID, Self.nowMS, id]
                )
            } else {
                try db.execute(
                    sql: "UPDATE transactions SET is_deleted = 1, deleted_at_ms = ?, updated_ms = ? WHERE book_id = ?",
                    arguments: [Self.nowMS, Self.nowMS, id]
                )
            }
            try Self.softDelete(table: "books", id: id, db: db)
        }
    }

    private func book(id: Int64) throws -> LedgerBook {
        guard let value = try database.queue.read({ db in
            try Row.fetchOne(db, sql: "SELECT * FROM books WHERE id = ?", arguments: [id]).map(Self.book(from:))
        }) else { throw LedgerRepositoryError.recordNotFound }
        return value
    }

    // MARK: - Accounts

    public func accounts(includeDeleted: Bool = false) throws -> [LedgerAccount] {
        try database.queue.read { db in
            let whereSQL = includeDeleted
                ? ""
                : "WHERE is_deleted = 0 AND status <> 'legacy_hidden'"
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM accounts \(whereSQL) ORDER BY sort_order, id"
            ).map(Self.account(from:))
        }
    }

    @discardableResult
    public func createAccount(
        name: String,
        type: String = "cash",
        openingBalance: MoneyAmount = .zero,
        includeInNetWorth: Bool = true,
        institution: String = ""
    ) throws -> LedgerAccount {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw LedgerRepositoryError.invalidName }
        let now = Self.nowMS
        let id = try database.queue.write { db -> Int64 in
            let order = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM accounts")) ?? 0
            try db.execute(
                sql: """
                    INSERT INTO accounts
                    (uuid, name, currency_code, type, opening_balance, include_in_net_worth,
                     institution, sort_order, status, created_ms, updated_ms, is_deleted)
                    VALUES (?, ?, 'CNY', ?, ?, ?, ?, ?, 'active', ?, ?, 0)
                    """,
                arguments: [
                    UUID().uuidString, cleanName, type, openingBalance.storageString,
                    includeInNetWorth ? 1 : 0, institution, order, now, now,
                ]
            )
            return db.lastInsertedRowID
        }
        return try account(id: id)
    }

    public func updateAccount(_ account: LedgerAccount) throws {
        let cleanName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw LedgerRepositoryError.invalidName }
        guard LedgerAccountStatus(rawValue: account.status) != nil else {
            throw LedgerRepositoryError.invalidAccountStatus
        }
        try database.queue.write { db in
            try db.execute(
                sql: """
                    UPDATE accounts SET name = ?, currency_code = ?, type = ?, opening_balance = ?,
                    include_in_net_worth = ?, institution = ?, sort_order = ?, status = ?, updated_ms = ?
                    WHERE id = ? AND is_deleted = 0
                    """,
                arguments: [
                    cleanName, account.currencyCode, account.type, account.openingBalance.storageString,
                    account.includeInNetWorth ? 1 : 0, account.institution, account.sortOrder,
                    account.status, Self.nowMS, account.id,
                ]
            )
            guard db.changesCount == 1 else { throw LedgerRepositoryError.recordNotFound }
        }
    }

    public func deleteAccount(id: Int64) throws {
        try database.queue.write { db in
            let references = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM transactions
                    WHERE is_deleted = 0 AND (account_id = ? OR to_account_id = ?)
                    """,
                arguments: [id, id]
            ) ?? 0
            guard references == 0 else { throw LedgerRepositoryError.accountInUse }
            try Self.softDelete(table: "accounts", id: id, db: db)
        }
    }

    public func accountIsInUse(id: Int64) throws -> Bool {
        try database.queue.read { db in
            let references = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM transactions
                    WHERE is_deleted = 0 AND (account_id = ? OR to_account_id = ?)
                    """,
                arguments: [id, id]
            ) ?? 0
            return references > 0
        }
    }

    public func accountBalance(id: Int64) throws -> MoneyAmount {
        guard let balance = try accountBalances()[id] else {
            throw LedgerRepositoryError.recordNotFound
        }
        return balance
    }

    public func accountBalances() throws -> [Int64: MoneyAmount] {
        let activeAccounts = try accounts()
        var balances = Dictionary(uniqueKeysWithValues: activeAccounts.map { ($0.id, $0.openingBalance) })
        let records = try allTransactionsIncludingRefunds()
        for item in records {
            switch item.kind {
            case .expense:
                if let id = item.accountID, let balance = balances[id] {
                    balances[id] = balance - item.amount
                }
            case .income:
                if let id = item.accountID, let balance = balances[id] {
                    balances[id] = balance + item.amount
                }
            case .transfer:
                if let id = item.accountID, let balance = balances[id] {
                    balances[id] = balance - item.amount
                }
                if let id = item.toAccountID, let balance = balances[id] {
                    balances[id] = balance + item.amount
                }
            }
        }
        return balances
    }

    private func account(id: Int64) throws -> LedgerAccount {
        guard let value = try database.queue.read({ db in
            try Row.fetchOne(db, sql: "SELECT * FROM accounts WHERE id = ?", arguments: [id]).map(Self.account(from:))
        }) else { throw LedgerRepositoryError.recordNotFound }
        return value
    }

    // MARK: - Categories

    public func categories(
        kind: TransactionKind? = nil,
        includeHidden: Bool = false,
        includeDeleted: Bool = false
    ) throws -> [LedgerCategory] {
        try database.queue.read { db in
            var clauses: [String] = []
            var arguments = StatementArguments()
            if let kind {
                clauses.append("kind = ?")
                arguments += [kind.rawValue]
            }
            if !includeHidden { clauses.append("hidden = 0") }
            if !includeDeleted { clauses.append("is_deleted = 0") }
            let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM categories \(whereSQL) ORDER BY parent_id IS NOT NULL, sort_order, id",
                arguments: arguments
            ).map(Self.category(from:))
        }
    }

    @discardableResult
    public func createCategory(
        name: String,
        emoji: String = "🏷️",
        kind: TransactionKind,
        parentID: Int64? = nil
    ) throws -> LedgerCategory {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw LedgerRepositoryError.invalidName }
        let now = Self.nowMS
        let id = try database.queue.write { db -> Int64 in
            try Self.validateCategoryParent(parentID, kind: kind, categoryID: nil, db: db)
            let order = (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM categories WHERE kind = ? AND parent_id IS ?",
                arguments: [kind.rawValue, parentID]
            )) ?? 0
            try db.execute(
                sql: """
                    INSERT INTO categories
                    (uuid, key, name_zh, name_en, emoji, kind, parent_id, hidden,
                     sort_order, created_ms, updated_ms, is_deleted)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, 0)
                    """,
                arguments: [
                    UUID().uuidString, "custom_\(UUID().uuidString.lowercased())", cleanName,
                    cleanName, emoji, kind.rawValue, parentID, order, now, now,
                ]
            )
            return db.lastInsertedRowID
        }
        return try category(id: id)
    }

    public func updateCategory(_ category: LedgerCategory) throws {
        let cleanName = category.nameZh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw LedgerRepositoryError.invalidName }
        try database.queue.write { db in
            try Self.validateCategoryParent(
                category.parentID,
                kind: category.kind,
                categoryID: category.id,
                db: db
            )
            try db.execute(
                sql: """
                    UPDATE categories SET name_zh = ?, name_en = ?, emoji = ?, parent_id = ?,
                    hidden = ?, sort_order = ?, updated_ms = ? WHERE id = ? AND is_deleted = 0
                    """,
                arguments: [
                    cleanName, category.nameEn, category.emoji, category.parentID,
                    category.isHidden ? 1 : 0, category.sortOrder, Self.nowMS, category.id,
                ]
            )
            guard db.changesCount == 1 else { throw LedgerRepositoryError.recordNotFound }
        }
    }

    public func deleteCategory(id: Int64) throws {
        try database.queue.write { db in
            try db.execute(
                sql: "UPDATE transactions SET category_id = NULL, updated_ms = ? WHERE category_id = ?",
                arguments: [Self.nowMS, id]
            )
            try db.execute(
                sql: "UPDATE categories SET parent_id = NULL, updated_ms = ? WHERE parent_id = ? AND is_deleted = 0",
                arguments: [Self.nowMS, id]
            )
            try Self.softDelete(table: "categories", id: id, db: db)
        }
    }

    private func category(id: Int64) throws -> LedgerCategory {
        guard let value = try database.queue.read({ db in
            try Row.fetchOne(db, sql: "SELECT * FROM categories WHERE id = ?", arguments: [id]).map(Self.category(from:))
        }) else { throw LedgerRepositoryError.recordNotFound }
        return value
    }

    // MARK: - Tags

    public func tags(includeDeleted: Bool = false) throws -> [LedgerTag] {
        try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM tags \(includeDeleted ? "" : "WHERE is_deleted = 0") ORDER BY sort_order, id"
            ).map(Self.tag(from:))
        }
    }

    @discardableResult
    public func createTag(name: String, colorARGB: Int64 = 4_286_351_771) throws -> LedgerTag {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw LedgerRepositoryError.invalidName }
        let now = Self.nowMS
        let id = try database.queue.write { db -> Int64 in
            let order = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM tags")) ?? 0
            try db.execute(
                sql: """
                    INSERT INTO tags (uuid, name, color, sort_order, created_ms, updated_ms, is_deleted)
                    VALUES (?, ?, ?, ?, ?, ?, 0)
                    """,
                arguments: [UUID().uuidString, cleanName, colorARGB, order, now, now]
            )
            return db.lastInsertedRowID
        }
        return try tag(id: id)
    }

    public func updateTag(_ tag: LedgerTag) throws {
        let cleanName = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw LedgerRepositoryError.invalidName }
        try database.queue.write { db in
            try db.execute(
                sql: "UPDATE tags SET name = ?, color = ?, sort_order = ?, updated_ms = ? WHERE id = ? AND is_deleted = 0",
                arguments: [cleanName, tag.colorARGB, tag.sortOrder, Self.nowMS, tag.id]
            )
            guard db.changesCount == 1 else { throw LedgerRepositoryError.recordNotFound }
        }
    }

    public func deleteTag(id: Int64) throws {
        try database.queue.write { db in
            try Self.softDelete(table: "tags", id: id, db: db)
        }
    }

    private func tag(id: Int64) throws -> LedgerTag {
        guard let value = try database.queue.read({ db in
            try Row.fetchOne(db, sql: "SELECT * FROM tags WHERE id = ?", arguments: [id]).map(Self.tag(from:))
        }) else { throw LedgerRepositoryError.recordNotFound }
        return value
    }

    // MARK: - Transactions

    public func transactions(filter: TransactionFilter = .init()) throws -> [LedgerTransaction] {
        let context = try transactionContext()
        let term = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowedBookIDs: Set<Int64>
        if let bookID = filter.bookID {
            allowedBookIDs = [bookID]
        } else {
            allowedBookIDs = Set(context.books.filter(\.includeInTotal).map(\.id))
        }
        var refundTotals: [Int64: MoneyAmount] = [:]
        for refund in context.transactions {
            guard let rootID = refund.refundOf else { continue }
            refundTotals[rootID] = (refundTotals[rootID] ?? .zero) + refund.amount
        }
        return context.transactions.filter { item in
            guard item.refundOf == nil, allowedBookIDs.contains(item.bookID ?? -1) else { return false }
            if let kind = filter.kind, item.kind != kind { return false }
            if let startDate = filter.startDate, item.date < startDate { return false }
            if let endDate = filter.endDate, item.date > endDate { return false }
            if !filter.includeExcluded, item.isExcluded { return false }
            guard !term.isEmpty else { return true }
            let category = item.categoryID.flatMap { context.categoryByID[$0] }
            let account = item.accountID.flatMap { context.accountByID[$0] }
            let toAccount = item.toAccountID.flatMap { context.accountByID[$0] }
            let book = item.bookID.flatMap { context.bookByID[$0] }
            let tagNames = item.tagIDs.compactMap { context.tagByID[$0]?.name }
            let netAmount = item.amount + (refundTotals[item.id] ?? .zero)
            return [
                item.note, item.amount.storageString, netAmount.storageString, item.kind.title,
                category?.nameZh ?? "未分类", account?.name ?? "",
                toAccount?.name ?? "", book?.name ?? "",
                tagNames.joined(separator: " "),
            ].joined(separator: " ").lowercased().contains(term)
        }
    }

    public func transaction(id: Int64) throws -> LedgerTransaction {
        guard let value = try database.queue.read({ db in
            try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id]).map(Self.transaction(from:))
        }) else { throw LedgerRepositoryError.recordNotFound }
        return value
    }

    @discardableResult
    public func saveTransaction(_ draft: TransactionDraft) throws -> LedgerTransaction {
        guard let amount = draft.validatedAmount else { throw LedgerRepositoryError.invalidAmount }
        guard let accountID = draft.accountID else { throw LedgerRepositoryError.missingAccount }
        if draft.kind == .transfer {
            guard let destination = draft.toAccountID else { throw LedgerRepositoryError.missingAccount }
            guard destination != accountID else { throw LedgerRepositoryError.sameTransferAccount }
        }
        let bookID = try draft.bookID ?? defaultBookID()
        let categoryID = draft.kind == .transfer ? nil : draft.categoryID
        let isReimbursable = draft.kind == .expense && draft.isReimbursable
        let tagText = draft.tagIDs.sorted().map { String($0) }.joined(separator: ",")
        let now = Self.nowMS
        let dateMS = Int64(draft.date.timeIntervalSince1970 * 1_000)
        let id = try database.queue.write { db -> Int64 in
            if let id = draft.id {
                guard let existing = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT account_id, to_account_id FROM transactions
                        WHERE id = ? AND is_deleted = 0 AND refund_of IS NULL
                        """,
                    arguments: [id]
                ) else { throw LedgerRepositoryError.recordNotFound }
                let previousAccountID: Int64? = existing["account_id"]
                let previousToAccountID: Int64? = existing["to_account_id"]
                try Self.validatePostingAccount(accountID, preserving: previousAccountID, db: db)
                if draft.kind == .transfer, let destination = draft.toAccountID {
                    try Self.validatePostingAccount(destination, preserving: previousToAccountID, db: db)
                }
                try db.execute(
                    sql: """
                        UPDATE transactions SET book_id = ?, kind = ?, amount = ?, currency_code = ?,
                        category_id = ?, account_id = ?, to_account_id = ?, note = ?, date_ms = ?,
                        time_precision = ?, tags = ?, reimbursable = ?, image_path = ?, excluded = ?,
                        updated_ms = ? WHERE id = ? AND is_deleted = 0 AND refund_of IS NULL
                        """,
                    arguments: [
                        bookID, draft.kind.rawValue, amount.storageString, draft.currencyCode,
                        categoryID, accountID, draft.kind == .transfer ? draft.toAccountID : nil,
                        draft.note.trimmingCharacters(in: .whitespacesAndNewlines), dateMS,
                        draft.timePrecision.rawValue, tagText, isReimbursable ? 1 : 0,
                        draft.imagePath, draft.isExcluded ? 1 : 0, now, id,
                    ]
                )
                guard db.changesCount == 1 else { throw LedgerRepositoryError.recordNotFound }
                return id
            }
            try Self.validatePostingAccount(accountID, preserving: nil, db: db)
            if draft.kind == .transfer, let destination = draft.toAccountID {
                try Self.validatePostingAccount(destination, preserving: nil, db: db)
            }
            try db.execute(
                sql: """
                    INSERT INTO transactions
                    (uuid, book_id, kind, amount, currency_code, category_id, account_id,
                     to_account_id, note, date_ms, time_precision, tags, reimbursable,
                     image_path, excluded, refund_of, created_ms, updated_ms, is_deleted)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, 0)
                    """,
                arguments: [
                    UUID().uuidString, bookID, draft.kind.rawValue, amount.storageString,
                    draft.currencyCode, categoryID, accountID,
                    draft.kind == .transfer ? draft.toAccountID : nil,
                    draft.note.trimmingCharacters(in: .whitespacesAndNewlines), dateMS,
                    draft.timePrecision.rawValue, tagText, isReimbursable ? 1 : 0,
                    draft.imagePath, draft.isExcluded ? 1 : 0, now, now,
                ]
            )
            return db.lastInsertedRowID
        }
        return try transaction(id: id)
    }

    private static func validatePostingAccount(
        _ id: Int64,
        preserving previousID: Int64?,
        db: Database
    ) throws {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT status, is_deleted FROM accounts WHERE id = ?",
            arguments: [id]
        ) else { throw LedgerRepositoryError.missingAccount }
        let status: String = row["status"]
        let isDeleted: Bool = row["is_deleted"]
        guard !isDeleted else { throw LedgerRepositoryError.missingAccount }
        guard status == LedgerAccountStatus.active.rawValue || previousID == id else {
            throw LedgerRepositoryError.inactiveAccount
        }
    }

    public func deleteTransaction(id: Int64) throws {
        try database.queue.write { db in
            let now = Self.nowMS
            try db.execute(
                sql: """
                    UPDATE transactions SET is_deleted = 1, deleted_at_ms = ?, updated_ms = ?
                    WHERE (id = ? OR refund_of = ?) AND is_deleted = 0
                    """,
                arguments: [now, now, id, id]
            )
            guard db.changesCount > 0 else { throw LedgerRepositoryError.recordNotFound }
        }
    }

    @discardableResult
    public func refundTransaction(
        id: Int64,
        amount: MoneyAmount,
        note: String = "退款"
    ) throws -> LedgerTransaction {
        guard amount > .zero else { throw LedgerRepositoryError.invalidAmount }
        let refundID = try database.queue.write { db in
            let context = try Self.refundContext(transactionID: id, db: db)
            guard context.details.refundableAmount > .zero else {
                throw LedgerRepositoryError.noRefundableAmount
            }
            guard amount <= context.details.refundableAmount else {
                throw LedgerRepositoryError.refundExceedsRemainingAmount
            }
            return try Self.insertRefund(
                context: context,
                amount: amount,
                note: note,
                db: db
            )
        }
        return try transaction(id: refundID)
    }

    @discardableResult
    public func refundTransactionInFull(
        id: Int64,
        note: String = "退款"
    ) throws -> LedgerTransaction {
        let refundID = try database.queue.write { db in
            let context = try Self.refundContext(transactionID: id, db: db)
            let amount = context.details.refundableAmount
            guard amount > .zero else { throw LedgerRepositoryError.noRefundableAmount }
            return try Self.insertRefund(
                context: context,
                amount: amount,
                note: note,
                db: db
            )
        }
        return try transaction(id: refundID)
    }

    public func revokeRefund(id: Int64) throws {
        try database.queue.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT refund_of FROM transactions WHERE id = ? AND is_deleted = 0",
                arguments: [id]
            ) else { throw LedgerRepositoryError.recordNotFound }
            let refundOf: Int64? = row["refund_of"]
            guard refundOf != nil else { throw LedgerRepositoryError.invalidRefundTarget }

            let now = Self.nowMS
            try db.execute(
                sql: """
                    UPDATE transactions SET is_deleted = 1, deleted_at_ms = ?, updated_ms = ?
                    WHERE id = ? AND is_deleted = 0 AND refund_of IS NOT NULL
                    """,
                arguments: [now, now, id]
            )
            guard db.changesCount == 1 else { throw LedgerRepositoryError.recordNotFound }
        }
    }

    public func refundDetails(transactionID: Int64) throws -> TransactionRefundDetails {
        try database.queue.read { db in
            try Self.refundContext(transactionID: transactionID, db: db).details
        }
    }

    public func receiptIsReferenced(_ path: String) throws -> Bool {
        guard !path.isEmpty else { return false }
        return try database.queue.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM transactions WHERE image_path = ? AND is_deleted = 0",
                arguments: [path]
            ) ?? 0
            return count > 0
        }
    }

    public func netAmount(transactionID: Int64) throws -> MoneyAmount {
        let root = try transaction(id: transactionID)
        let refunds = try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM transactions WHERE refund_of = ? AND is_deleted = 0",
                arguments: [transactionID]
            ).map(Self.transaction(from:))
        }
        return refunds.reduce(root.amount) { $0 + $1.amount }
    }

    public func netAmounts(for transactions: [LedgerTransaction]) throws -> [Int64: MoneyAmount] {
        var amounts = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0.amount) })
        guard !amounts.isEmpty else { return amounts }
        for refund in try allTransactionsIncludingRefunds() {
            guard let rootID = refund.refundOf, let current = amounts[rootID] else { continue }
            amounts[rootID] = current + refund.amount
        }
        return amounts
    }

    public func summary(filter: TransactionFilter = .init()) throws -> LedgerSummary {
        var expense = MoneyAmount.zero
        var income = MoneyAmount.zero
        var count = 0
        let context = try transactionContext()
        let allowedBookIDs: Set<Int64> = filter.bookID.map { Set([$0]) }
            ?? Set(context.books.filter(\.includeInTotal).map(\.id))
        for item in context.transactions where allowedBookIDs.contains(item.bookID ?? -1) {
            if item.isExcluded || item.isDeleted { continue }
            if let kind = filter.kind, item.kind != kind { continue }
            if let startDate = filter.startDate, item.date < startDate { continue }
            if let endDate = filter.endDate, item.date > endDate { continue }
            switch item.kind {
            case .expense: expense = expense + item.amount
            case .income: income = income + item.amount
            case .transfer: break
            }
            if item.refundOf == nil { count += 1 }
        }
        return LedgerSummary(expense: expense, income: income, transactionCount: count)
    }

    /// Loads the home list, summary, and attached-refund net amounts from one
    /// isolated database read. The upper date bound is intentionally exclusive.
    public func homeMonthSnapshot(
        bookID: Int64?,
        monthStart: Date,
        nextMonthStart: Date
    ) throws -> HomeMonthSnapshot {
        guard monthStart < nextMonthStart else {
            throw LedgerRepositoryError.invalidDateRange
        }
        let startMS = Int64(monthStart.timeIntervalSince1970 * 1_000)
        let endMS = Int64(nextMonthStart.timeIntervalSince1970 * 1_000)

        return try database.queue.read { db in
            let roots: [LedgerTransaction]
            let refunds: [LedgerTransaction]
            if let bookID {
                roots = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM transactions
                        WHERE is_deleted = 0 AND refund_of IS NULL
                          AND date_ms >= ? AND date_ms < ? AND book_id = ?
                        ORDER BY date_ms DESC, id DESC
                        """,
                    arguments: [startMS, endMS, bookID]
                ).map(Self.transaction(from:))
                refunds = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT refund.* FROM transactions AS refund
                        JOIN transactions AS root ON root.id = refund.refund_of
                        WHERE refund.is_deleted = 0
                          AND root.is_deleted = 0 AND root.refund_of IS NULL
                          AND root.date_ms >= ? AND root.date_ms < ? AND root.book_id = ?
                        ORDER BY refund.id ASC
                        """,
                    arguments: [startMS, endMS, bookID]
                ).map(Self.transaction(from:))
            } else {
                let totalBookPredicate = """
                    book_id IN (
                      SELECT id FROM books
                      WHERE is_deleted = 0 AND include_in_total = 1
                    )
                    """
                roots = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM transactions
                        WHERE is_deleted = 0 AND refund_of IS NULL
                          AND date_ms >= ? AND date_ms < ?
                          AND \(totalBookPredicate)
                        ORDER BY date_ms DESC, id DESC
                        """,
                    arguments: [startMS, endMS]
                ).map(Self.transaction(from:))
                refunds = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT refund.* FROM transactions AS refund
                        JOIN transactions AS root ON root.id = refund.refund_of
                        WHERE refund.is_deleted = 0
                          AND root.is_deleted = 0 AND root.refund_of IS NULL
                          AND root.date_ms >= ? AND root.date_ms < ?
                          AND root.\(totalBookPredicate)
                        ORDER BY refund.id ASC
                        """,
                    arguments: [startMS, endMS]
                ).map(Self.transaction(from:))
            }

            var netAmounts = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0.amount) })
            for refund in refunds {
                guard let rootID = refund.refundOf, let current = netAmounts[rootID] else { continue }
                netAmounts[rootID] = current + refund.amount
            }

            var expense = MoneyAmount.zero
            var income = MoneyAmount.zero
            var count = 0
            for item in roots where !item.isExcluded {
                let netAmount = netAmounts[item.id] ?? item.amount
                switch item.kind {
                case .expense: expense = expense + netAmount
                case .income: income = income + netAmount
                case .transfer: break
                }
                count += 1
            }

            return HomeMonthSnapshot(
                bookID: bookID,
                monthStart: monthStart,
                nextMonthStart: nextMonthStart,
                transactions: roots,
                summary: LedgerSummary(
                    expense: expense,
                    income: income,
                    transactionCount: count
                ),
                netAmounts: netAmounts
            )
        }
    }

    public func hasAnyVisibleTransaction() throws -> Bool {
        try database.queue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                      SELECT 1 FROM transactions
                      WHERE is_deleted = 0 AND refund_of IS NULL
                    )
                    """
            ) == 1
        }
    }

    private func allTransactionsIncludingRefunds() throws -> [LedgerTransaction] {
        try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM transactions WHERE is_deleted = 0 ORDER BY date_ms DESC, id DESC"
            ).map(Self.transaction(from:))
        }
    }

    private func transactionContext() throws -> TransactionContext {
        try database.queue.read { db in
            let records = try Row.fetchAll(
                db,
                sql: "SELECT * FROM transactions WHERE is_deleted = 0 ORDER BY date_ms DESC, id DESC"
            ).map(Self.transaction(from:))
            let books = try Row.fetchAll(db, sql: "SELECT * FROM books WHERE is_deleted = 0").map(Self.book(from:))
            let accounts = try Row.fetchAll(db, sql: "SELECT * FROM accounts WHERE is_deleted = 0").map(Self.account(from:))
            let categories = try Row.fetchAll(db, sql: "SELECT * FROM categories WHERE is_deleted = 0").map(Self.category(from:))
            let tags = try Row.fetchAll(db, sql: "SELECT * FROM tags WHERE is_deleted = 0").map(Self.tag(from:))
            return TransactionContext(
                transactions: records,
                books: books,
                bookByID: Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) }),
                accountByID: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) }),
                categoryByID: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }),
                tagByID: Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
            )
        }
    }

    private static func refundContext(
        transactionID: Int64,
        db: Database
    ) throws -> RefundContext {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM transactions WHERE id = ?",
            arguments: [transactionID]
        ) else { throw LedgerRepositoryError.recordNotFound }
        let transaction = Self.transaction(from: row)
        guard !transaction.isDeleted else { throw LedgerRepositoryError.recordNotFound }
        guard transaction.refundOf == nil,
              transaction.kind == .expense,
              transaction.amount > .zero else {
            throw LedgerRepositoryError.invalidRefundTarget
        }

        let refunds = try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM transactions
                WHERE refund_of = ? AND is_deleted = 0
                ORDER BY created_ms ASC, id ASC
                """,
            arguments: [transactionID]
        ).map(Self.transaction(from:))
        let refundedAmount = refunds.reduce(MoneyAmount.zero) { total, refund in
            refund.amount < .zero ? total - refund.amount : total
        }
        let remainingAmount = transaction.amount - refundedAmount
        let refundableAmount = remainingAmount > .zero ? remainingAmount : .zero
        return RefundContext(
            details: TransactionRefundDetails(
                transaction: transaction,
                refunds: refunds,
                refundedAmount: refundedAmount,
                refundableAmount: refundableAmount
            ),
            dateMS: row["date_ms"]
        )
    }

    private static func insertRefund(
        context: RefundContext,
        amount: MoneyAmount,
        note: String,
        db: Database
    ) throws -> Int64 {
        let transaction = context.details.transaction
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Self.nowMS
        try db.execute(
            sql: """
                INSERT INTO transactions
                (uuid, book_id, kind, amount, currency_code, category_id, account_id,
                 to_account_id, note, date_ms, time_precision, tags, reimbursable,
                 image_path, excluded, refund_of, created_ms, updated_ms, is_deleted)
                VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, '', 0, '', ?, ?, ?, ?, 0)
                """,
            arguments: [
                UUID().uuidString, transaction.bookID, TransactionKind.expense.rawValue,
                (MoneyAmount.zero - amount).storageString, transaction.currencyCode,
                transaction.categoryID, transaction.accountID,
                cleanNote.isEmpty ? "退款" : cleanNote, context.dateMS,
                transaction.timePrecision.rawValue, transaction.isExcluded ? 1 : 0,
                transaction.id, now, now,
            ]
        )
        return db.lastInsertedRowID
    }

    // MARK: - Settings

    public func setting(for key: String) throws -> String? {
        try database.queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_settings WHERE key = ?", arguments: [key])
        }
    }

    public func setSetting(_ value: String?, for key: String) throws {
        try database.queue.write { db in
            if let value {
                try db.execute(
                    sql: "INSERT INTO app_settings(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                    arguments: [key, value]
                )
            } else {
                try db.execute(sql: "DELETE FROM app_settings WHERE key = ?", arguments: [key])
            }
        }
    }

    // MARK: - Mapping

    private static var nowMS: Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    private static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    private static func optionalDate(_ milliseconds: Int64?) -> Date? {
        milliseconds.map(date)
    }

    private static func softDelete(table: String, id: Int64, db: Database) throws {
        precondition(["books", "accounts", "categories", "tags"].contains(table))
        let now = nowMS
        try db.execute(
            sql: "UPDATE \(table) SET is_deleted = 1, deleted_at_ms = ?, updated_ms = ? WHERE id = ? AND is_deleted = 0",
            arguments: [now, now, id]
        )
        guard db.changesCount == 1 else { throw LedgerRepositoryError.recordNotFound }
    }

    private static func validateCategoryParent(
        _ parentID: Int64?,
        kind: TransactionKind,
        categoryID: Int64?,
        db: Database
    ) throws {
        guard let parentID else { return }
        if let categoryID, parentID == categoryID {
            throw LedgerRepositoryError.invalidCategoryParent
        }
        guard let parent = try Row.fetchOne(
            db,
            sql: """
                SELECT kind, parent_id, hidden, is_deleted FROM categories WHERE id = ?
                """,
            arguments: [parentID]
        ) else {
            throw LedgerRepositoryError.invalidCategoryParent
        }
        let parentKind = TransactionKind(rawValue: parent["kind"] as String)
        let parentParentID: Int64? = parent["parent_id"]
        let hidden = (parent["hidden"] as Int) == 1
        let deleted = (parent["is_deleted"] as Int) == 1
        let keepsExistingParent: Bool
        if let categoryID {
            let existingParentID = try Int64.fetchOne(
                db,
                sql: "SELECT parent_id FROM categories WHERE id = ?",
                arguments: [categoryID]
            )
            keepsExistingParent = existingParentID == parentID
        } else {
            keepsExistingParent = false
        }
        guard parentKind == kind,
              parentParentID == nil,
              (!hidden || keepsExistingParent),
              !deleted else {
            throw LedgerRepositoryError.invalidCategoryParent
        }
        if let categoryID {
            let childCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM categories WHERE parent_id = ? AND is_deleted = 0",
                arguments: [categoryID]
            ) ?? 0
            guard childCount == 0 else { throw LedgerRepositoryError.invalidCategoryParent }
        }
    }

    private static func book(from row: Row) -> LedgerBook {
        LedgerBook(
            id: row["id"], uuid: row["uuid"], name: row["name"], icon: row["icon"],
            cover: row["cover"], remark: row["remark"], sortOrder: row["sort_order"],
            createdAt: date(row["created_ms"]), isStarred: (row["starred"] as Int) == 1,
            includeInTotal: (row["include_in_total"] as Int) == 1,
            updatedAt: date(row["updated_ms"]), isDeleted: (row["is_deleted"] as Int) == 1,
            deletedAt: optionalDate(row["deleted_at_ms"])
        )
    }

    private static func account(from row: Row) -> LedgerAccount {
        LedgerAccount(
            id: row["id"], uuid: row["uuid"], name: row["name"],
            currencyCode: row["currency_code"], type: row["type"],
            openingBalance: MoneyAmount(row["opening_balance"] as String) ?? .zero,
            includeInNetWorth: (row["include_in_net_worth"] as Int) == 1,
            institution: row["institution"], sortOrder: row["sort_order"], status: row["status"],
            createdAt: date(row["created_ms"]), updatedAt: date(row["updated_ms"]),
            isDeleted: (row["is_deleted"] as Int) == 1, deletedAt: optionalDate(row["deleted_at_ms"])
        )
    }

    private static func category(from row: Row) -> LedgerCategory {
        LedgerCategory(
            id: row["id"], uuid: row["uuid"], key: row["key"], nameZh: row["name_zh"],
            nameEn: row["name_en"], emoji: row["emoji"],
            kind: TransactionKind(rawValue: row["kind"] as String) ?? .expense,
            parentID: row["parent_id"], isHidden: (row["hidden"] as Int) == 1,
            sortOrder: row["sort_order"], createdAt: date(row["created_ms"]),
            updatedAt: date(row["updated_ms"]), isDeleted: (row["is_deleted"] as Int) == 1,
            deletedAt: optionalDate(row["deleted_at_ms"])
        )
    }

    private static func tag(from row: Row) -> LedgerTag {
        LedgerTag(
            id: row["id"], uuid: row["uuid"], name: row["name"], colorARGB: row["color"],
            sortOrder: row["sort_order"], createdAt: date(row["created_ms"]),
            updatedAt: date(row["updated_ms"]), isDeleted: (row["is_deleted"] as Int) == 1,
            deletedAt: optionalDate(row["deleted_at_ms"])
        )
    }

    private static func transaction(from row: Row) -> LedgerTransaction {
        let tags = (row["tags"] as String).split(separator: ",").compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
        return LedgerTransaction(
            id: row["id"], uuid: row["uuid"], bookID: row["book_id"],
            kind: TransactionKind(rawValue: row["kind"] as String) ?? .expense,
            amount: MoneyAmount(row["amount"] as String) ?? .zero,
            currencyCode: row["currency_code"], categoryID: row["category_id"],
            accountID: row["account_id"], toAccountID: row["to_account_id"], note: row["note"],
            date: date(row["date_ms"]),
            timePrecision: TransactionTimePrecision(rawValue: row["time_precision"] as String) ?? .legacyUnknown,
            tagIDs: tags, isReimbursable: (row["reimbursable"] as Int) == 1,
            imagePath: row["image_path"], isExcluded: (row["excluded"] as Int) == 1,
            refundOf: row["refund_of"], createdAt: date(row["created_ms"]),
            updatedAt: date(row["updated_ms"]), isDeleted: (row["is_deleted"] as Int) == 1,
            deletedAt: optionalDate(row["deleted_at_ms"])
        )
    }
}

private struct TransactionContext {
    var transactions: [LedgerTransaction]
    var books: [LedgerBook]
    var bookByID: [Int64: LedgerBook]
    var accountByID: [Int64: LedgerAccount]
    var categoryByID: [Int64: LedgerCategory]
    var tagByID: [Int64: LedgerTag]
}

private struct RefundContext {
    var details: TransactionRefundDetails
    var dateMS: Int64
}
