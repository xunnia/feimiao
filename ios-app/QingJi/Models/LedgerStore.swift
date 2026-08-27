import Foundation
import SwiftData
import QingJiCore

/// App 层对 SwiftData 的账务写入边界。
///
/// 页面只负责收集输入和展示状态；退款、报销、级联删除等会改变一整个交易
/// 家族的操作统一从这里走，确保 iOS 与 Android 的业务口径不会因为 UI 页面
/// 各写一份而逐渐分叉。
enum LedgerStore {
    enum Error: LocalizedError, Equatable {
        case invalidAmount
        case invalidTransfer
        case invalidSettlementAccount
        case refundExceedsRemaining
        case transactionNotFound
        case immutableOffset

        var errorDescription: String? {
            switch self {
            case .invalidAmount: return "金额必须大于 0。"
            case .invalidTransfer: return "转账需要选择两个不同的账户。"
            case .invalidSettlementAccount: return "到账账户不存在或币种不一致。"
            case .refundExceedsRemaining: return "退款金额不能超过剩余可退金额。"
            case .transactionNotFound: return "找不到原账单，请刷新后重试。"
            case .immutableOffset: return "退款或报销记录不能直接编辑，请在原账单的冲减记录中撤销后重新添加。"
            }
        }
    }

    static func allTransactions(in context: ModelContext) throws -> [MoneyTransaction] {
        try context.fetch(FetchDescriptor<MoneyTransaction>(sortBy: [
            SortDescriptor(\.date, order: .reverse)
        ]))
    }

    static func visibleTransactions(
        in context: ModelContext,
        selectedBookID: UUID? = nil
    ) throws -> [MoneyTransaction] {
        let all = try allTransactions(in: context)
        return LedgerScope.filter(all, selectedBookID: selectedBookID)
            .filter { $0.refundOfID == nil }
    }

    static func refundChildren(
        of original: MoneyTransaction,
        in context: ModelContext
    ) throws -> [MoneyTransaction] {
        let all = try allTransactions(in: context)
        return all.filter { $0.refundOfID == original.stableID }
            .sorted { $0.date < $1.date }
    }

    static func refundStatus(
        for original: MoneyTransaction,
        in context: ModelContext
    ) throws -> RefundStatus {
        let records = try allTransactions(in: context).map(\.record)
        return LedgerPolicy.refundStatus(for: original.record, in: records)
    }

    /// 批量记账草稿。AI 解析可以先让用户检查/改分类，确认后一次性落库，
    /// 不能因为中途某一笔失败而留下半批账目。
    struct TransactionDraft {
        let amount: Decimal
        let kind: TransactionKind
        let date: Date
        let note: String
        let category: TxCategory?
        let account: Account?
        let toAccount: Account?
        let book: Book?
        let tags: [String]
        let reimbursable: Bool
        let isExcluded: Bool
        let attachmentPath: String
        let orderNo: String
        let timePrecision: TransactionTimePrecision

        init(
            amount: Decimal,
            kind: TransactionKind,
            date: Date,
            note: String = "",
            category: TxCategory? = nil,
            account: Account? = nil,
            toAccount: Account? = nil,
            book: Book? = nil,
            tags: [String] = [],
            reimbursable: Bool = false,
            isExcluded: Bool = false,
            attachmentPath: String = "",
            orderNo: String = "",
            timePrecision: TransactionTimePrecision = .exact
        ) {
            self.amount = amount
            self.kind = kind
            self.date = date
            self.note = note
            self.category = category
            self.account = account
            self.toAccount = toAccount
            self.book = book
            self.tags = tags
            self.reimbursable = reimbursable
            self.isExcluded = isExcluded
            self.attachmentPath = attachmentPath
            self.orderNo = orderNo
            self.timePrecision = timePrecision
        }
    }

    @discardableResult
    static func createTransaction(
        in context: ModelContext,
        amount: Decimal,
        kind: TransactionKind,
        date: Date,
        note: String = "",
        category: TxCategory? = nil,
        account: Account? = nil,
        toAccount: Account? = nil,
        book: Book? = nil,
        tags: [String] = [],
        reimbursable: Bool = false,
        isExcluded: Bool = false,
        attachmentPath: String = "",
        orderNo: String = "",
        timePrecision: TransactionTimePrecision = .exact
    ) throws -> MoneyTransaction {
        return try createTransactions(
            in: context,
            drafts: [TransactionDraft(
                amount: amount,
                kind: kind,
                date: date,
                note: note,
                category: category,
                account: account,
                toAccount: toAccount,
                book: book,
                tags: tags,
                reimbursable: reimbursable,
                isExcluded: isExcluded,
                attachmentPath: attachmentPath,
                orderNo: orderNo,
                timePrecision: timePrecision
            )]
        )[0]
    }

    /// 一次性写入多笔普通流水。所有输入先验证，再插入和保存；保存失败时
    /// 把本批新对象从 context 移除，调用方不会得到“保存了半批”的成功结果。
    @discardableResult
    static func createTransactions(
        in context: ModelContext,
        drafts: [TransactionDraft]
    ) throws -> [MoneyTransaction] {
        guard !drafts.isEmpty else { return [] }
        let normalizedDrafts = drafts.map { draft in
            TransactionDraft(
                amount: MoneyNormalization.roundToCents(draft.amount),
                kind: draft.kind,
                date: draft.date,
                note: draft.note,
                category: draft.category,
                account: draft.account,
                toAccount: draft.toAccount,
                book: draft.book,
                tags: draft.tags,
                reimbursable: draft.reimbursable,
                isExcluded: draft.isExcluded,
                attachmentPath: draft.attachmentPath,
                orderNo: draft.orderNo,
                timePrecision: draft.timePrecision
            )
        }
        for draft in normalizedDrafts {
            guard draft.amount > 0 else { throw Error.invalidAmount }
            if draft.kind == .transfer {
                guard let account = draft.account,
                      let toAccount = draft.toAccount,
                      account.stableID != toAccount.stableID,
                      account.currencyCode == toAccount.currencyCode else {
                    throw Error.invalidTransfer
                }
            }
        }

        let transactions = normalizedDrafts.map { draft in
            MoneyTransaction(
                amount: draft.amount,
                kind: draft.kind,
                date: draft.date,
                note: draft.note,
                currencyCode: draft.account?.currencyCode ?? "CNY",
                category: draft.kind == .transfer ? nil : draft.category,
                account: draft.account,
                toAccount: draft.kind == .transfer ? draft.toAccount : nil,
                book: draft.book,
                timePrecision: draft.timePrecision,
                settledAt: draft.date,
                settlementQuality: draft.account == nil ? .unknown : .userConfirmed,
                settlementAccountID: draft.account?.stableID,
                settlementAccountQuality: draft.account == nil ? .unknown : .userConfirmed,
                eventType: .defaultFor(draft.kind),
                attachmentPath: draft.attachmentPath,
                orderNo: draft.orderNo,
                reimbursable: draft.reimbursable,
                isExcluded: draft.isExcluded,
                tagNames: draft.tags.joined(separator: ",")
            )
        }
        transactions.forEach(context.insert)
        do {
            try context.save()
            return transactions
        } catch {
            transactions.forEach(context.delete)
            throw error
        }
    }

    /// 更新普通流水；退款家族的原账单金额不能被改到已冲减金额以下。
    static func updateTransaction(
        _ transaction: MoneyTransaction,
        amount: Decimal,
        date: Date,
        note: String,
        category: TxCategory?,
        account: Account?,
        toAccount: Account? = nil,
        attachmentPath: String? = nil,
        tags: [String]? = nil,
        reimbursable: Bool,
        isExcluded: Bool,
        in context: ModelContext
    ) throws {
        let normalizedAmount = MoneyNormalization.roundToCents(amount)
        guard normalizedAmount > 0 else { throw Error.invalidAmount }
        guard transaction.refundOfID == nil else { throw Error.immutableOffset }
        if transaction.kind == .transfer {
            guard let account, let toAccount,
                  account.stableID != toAccount.stableID,
                  account.currencyCode == toAccount.currencyCode else {
                throw Error.invalidTransfer
            }
        }
        if transaction.kind == .expense {
            let status = try refundStatus(for: transaction, in: context)
            guard normalizedAmount >= status.refundedAmount else {
                throw Error.refundExceedsRemaining
            }
        }
        transaction.amount = normalizedAmount
        transaction.date = date
        transaction.note = note
        transaction.category = transaction.kind == .transfer ? nil : category
        transaction.account = account
        transaction.toAccount = transaction.kind == .transfer ? toAccount : nil
        if let attachmentPath {
            transaction.attachmentPath = attachmentPath
        }
        if let tags {
            transaction.tags = tags
        }
        transaction.currencyCode = account?.currencyCode ?? transaction.currencyCode
        if transaction.refundOfID == nil {
            transaction.settledAt = date
            transaction.settlementQuality = account == nil ? .unknown : .userConfirmed
            transaction.settlementAccountID = account?.stableID
            transaction.settlementAccountQuality = account == nil ? .unknown : .userConfirmed
            transaction.eventType = .defaultFor(transaction.kind)
        }
        transaction.reimbursable = reimbursable
        transaction.isExcluded = isExcluded
        transaction.updatedAt = Date()
        try context.save()
    }

    /// 轻量修改分类，供 AI 记账卡和明细页复用；不改变金额、日期、账户或
    /// 退款家族关系。
    static func updateCategory(
        of transaction: MoneyTransaction,
        category: TxCategory?,
        in context: ModelContext
    ) throws {
        guard transaction.refundOfID == nil else { throw Error.immutableOffset }
        if let category, category.kind != transaction.kind {
            throw Error.transactionNotFound
        }
        transaction.category = transaction.kind == .transfer ? nil : category
        transaction.updatedAt = Date()
        try context.save()
    }

    /// 在原账单日期创建附着式退款或报销，并限制总冲减不超过原金额。
    @discardableResult
    static func createOffset(
        for original: MoneyTransaction,
        amount: Decimal,
        note: String,
        eventType: TransactionEventType,
        settlementAccount: Account? = nil,
        settledAt: Date = Date(),
        in context: ModelContext
    ) throws -> MoneyTransaction {
        guard original.kind == .expense, original.amount > 0 else {
            throw Error.invalidAmount
        }
        let normalizedAmount = MoneyNormalization.roundToCents(amount)
        guard normalizedAmount > 0 else { throw Error.invalidAmount }
        if let settlementAccount,
           (settlementAccount.isDeleted || settlementAccount.status != .active ||
            settlementAccount.currencyCode != original.currencyCode) {
            throw Error.invalidSettlementAccount
        }
        let status = try refundStatus(for: original, in: context)
        guard normalizedAmount <= status.remainingAmount else {
            throw Error.refundExceedsRemaining
        }

        let offset = MoneyTransaction(
            amount: -normalizedAmount,
            kind: .expense,
            date: original.date,
            note: note,
            merchantName: original.merchantName,
            productName: original.productName,
            currencyCode: original.currencyCode,
            category: original.category,
            account: original.account,
            book: original.book,
            timePrecision: original.timePrecision,
            settledAt: settledAt,
            settlementQuality: settlementAccount == nil ? .legacyAssumed : .userConfirmed,
            settlementAccountID: settlementAccount?.stableID
                ?? original.settlementAccountID
                ?? original.account?.stableID,
            settlementAccountQuality: settlementAccount == nil ? .legacyAssumed : .userConfirmed,
            eventType: eventType,
            orderNo: original.orderNo,
            refundOfID: original.stableID,
            isReimbursed: eventType == .reimbursement
        )
        context.insert(offset)
        if eventType == .reimbursement {
            // 安卓端只有“净额已补满”才清掉待报销；保留这个条件，避免
            // 编辑页做部分报销后账单从待处理列表里凭空消失。
            let fullyReimbursed = amount >= status.remainingAmount
            original.isReimbursed = fullyReimbursed
            original.reimbursable = !fullyReimbursed
        }
        original.updatedAt = Date()
        try context.save()
        return offset
    }

    /// 删除原账单时级联删除附着退款；删除退款子行时同步报销标记。
    static func delete(_ transaction: MoneyTransaction, in context: ModelContext) throws {
        let all = try allTransactions(in: context)
        var attachmentPaths = Set<String>()
        if !transaction.attachmentPath.isEmpty {
            attachmentPaths.insert(transaction.attachmentPath)
        }
        if transaction.refundOfID == nil {
            for child in all where child.refundOfID == transaction.stableID {
                if !child.attachmentPath.isEmpty {
                    attachmentPaths.insert(child.attachmentPath)
                }
                context.delete(child)
            }
        } else if transaction.eventType == .reimbursement,
                  let originalID = transaction.refundOfID,
                  let original = all.first(where: { $0.stableID == originalID }) {
            original.isReimbursed = false
            original.reimbursable = true
            original.updatedAt = Date()
        }
        context.delete(transaction)
        try context.save()
        // 数据库提交成功后再清理本地媒体，避免保存失败导致账单和照片同时丢失。
        guard let remainingTransactions = try? allTransactions(in: context) else {
            return
        }
        let remainingPaths = Set(
            remainingTransactions.compactMap { transaction in
                transaction.attachmentPath.isEmpty
                    ? nil
                    : AttachmentStore.canonicalRelativePath(transaction.attachmentPath)
            }
        )
        let pathsToRemove = attachmentPaths.map(AttachmentStore.canonicalRelativePath)
        for path in pathsToRemove where !remainingPaths.contains(path) {
            AttachmentStore.remove(path)
        }
    }

    static func accountBalance(
        for account: Account,
        transactions: [MoneyTransaction],
        checkpoints: [AccountBalanceCheckpointRecord] = []
    ) -> Decimal {
        AccountBalanceCalculator.balance(
            accountName: account.name,
            initialBalance: account.initialBalance,
            records: transactions.map(\.record),
            accountID: account.stableID,
            balanceAdjustment: AccountCheckpointStore.effectiveAdjustment(
                for: account.stableID,
                checkpoints: checkpoints
            )
        )
    }
}
