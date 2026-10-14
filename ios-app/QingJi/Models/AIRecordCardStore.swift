import Foundation
import SwiftData
import QingJiCore

/// The card and its financial rows commit together. A separate context keeps
/// rollback local and re-reading the saved card makes repeated confirmation safe.
@MainActor
enum AIRecordCardStore {
    enum Error: LocalizedError {
        case staleOperation
        case missingCard
        case missingBook
        case missingAccount
        case invalidEntry

        var errorDescription: String? {
            switch self {
            case .staleOperation: return "会话或账本已改变，请重新打开对话。"
            case .missingCard: return "找不到这张记账卡，请重新打开对话。"
            case .missingBook: return "发起时的账本不可用，请重新发送。"
            case .missingAccount: return "请先添加一个可用账户。"
            case .invalidEntry: return "找不到这笔记录，请重新打开对话核对。"
            }
        }
    }

    static func save(
        turnID: UUID, accountID: UUID, lease: AIChatOperationFence.Lease,
        in context: ModelContext, fence: AIChatOperationFence = .shared,
        beforeCommit: @escaping () throws -> Void = {}
    ) throws -> AIRecordCardState {
        try perform(turnID: turnID, lease: lease, in: context, fence: fence) { local, message, state in
            var card = state
            if card.saved { return card }
            guard let bookID = card.bookID, bookID == lease.bookID,
                  let book = try local.fetch(FetchDescriptor<Book>()).first(where: { $0.stableID == bookID }) else {
                throw Error.missingBook
            }
            guard let account = try local.fetch(FetchDescriptor<Account>()).first(where: {
                $0.stableID == accountID && !$0.isDeleted && $0.status == .active
            }) else { throw Error.missingAccount }
            let categories = try local.fetch(FetchDescriptor<TxCategory>())
            let indices = card.entries.indices.filter { (card.entries[$0].amount ?? .zero) > 0 }
            let drafts = indices.map { index in
                let entry = card.entries[index]
                return LedgerStore.TransactionDraft(
                    amount: entry.amount ?? .zero, kind: entry.kind, date: entry.date, note: entry.note,
                    category: categories.first { $0.kind == entry.kind &&
                        $0.key == card.categoryKey(at: index) && !$0.isArchived },
                    account: account, book: book,
                    reimbursable: entry.kind == .expense && entry.note.range(
                        of: "报销|出差|差旅|垫付|公司报|帮公司|公司的|因公|客户招待|招待费",
                        options: .regularExpression) != nil,
                    timePrecision: entry.timePrecision)
            }
            guard !drafts.isEmpty else { throw LedgerStore.Error.invalidAmount }
            try LedgerStore.createTransactions(in: local, drafts: drafts, beforeSave: { saved in
                card.transactionIDs = Array(repeating: nil, count: card.entries.count)
                for (index, transaction) in zip(indices, saved) { card.transactionIDs[index] = transaction.stableID }
                card.saved = true
                card.feedback = "已记下 \(saved.count) 笔，不对可点改分类或删除"
                try persist(card, message: message, lease: lease, fence: fence)
                try beforeCommit()
                guard fence.isCurrent(lease) else { throw Error.staleOperation }
            })
            return card
        }
    }

    static func changeCategory(
        turnID: UUID, index: Int, categoryKey: String, lease: AIChatOperationFence.Lease,
        in context: ModelContext, fence: AIChatOperationFence = .shared
    ) throws -> AIRecordCardState {
        try perform(turnID: turnID, lease: lease, in: context, fence: fence) { local, message, state in
            var card = state
            let transaction = try transaction(at: index, card: card, in: local)
            guard let category = try local.fetch(FetchDescriptor<TxCategory>()).first(where: {
                $0.kind == card.entries[index].kind && $0.key == categoryKey && !$0.isArchived
            }) else { throw Error.invalidEntry }
            try LedgerStore.updateCategory(of: transaction, category: category, in: local, beforeSave: {
                if index >= card.categoryKeys.count {
                    card.categoryKeys += Array(repeating: nil, count: index - card.categoryKeys.count + 1)
                }
                card.categoryKeys[index] = category.key
                card.feedback = "已把第 \(index + 1) 笔改为「\(category.name)」"
                try persist(card, message: message, lease: lease, fence: fence)
            })
            return card
        }
    }

    static func deleteEntry(
        turnID: UUID, index: Int, lease: AIChatOperationFence.Lease,
        in context: ModelContext, fence: AIChatOperationFence = .shared
    ) throws -> AIRecordCardState {
        try perform(turnID: turnID, lease: lease, in: context, fence: fence) { local, message, state in
            var card = state
            let transaction = try transaction(at: index, card: card, in: local)
            try LedgerStore.delete([transaction], in: local, beforeSave: {
                card.deletedIndices.insert(index)
                card.feedback = "已删除第 \(index + 1) 笔"
                try persist(card, message: message, lease: lease, fence: fence)
            })
            return card
        }
    }

    static func undo(
        turnID: UUID, lease: AIChatOperationFence.Lease,
        in context: ModelContext, fence: AIChatOperationFence = .shared
    ) throws -> AIRecordCardState {
        try perform(turnID: turnID, lease: lease, in: context, fence: fence) { local, message, state in
            var card = state
            guard card.saved else { throw Error.invalidEntry }
            if card.rolledBack { return card }
            let remaining = card.entries.indices.filter {
                !card.deletedIndices.contains($0) && card.transactionID(at: $0) != nil
            }
            let rows = try remaining.map { try transaction(at: $0, card: card, in: local) }
            try LedgerStore.delete(rows, in: local, beforeSave: {
                card.deletedIndices.formUnion(remaining)
                card.rolledBack = true
                card.feedback = "本次 AI 记账已撤销"
                try persist(card, message: message, lease: lease, fence: fence)
            })
            return card
        }
    }

    private static func transaction(at index: Int, card: AIRecordCardState, in context: ModelContext) throws -> MoneyTransaction {
        guard card.saved, !card.rolledBack, index >= 0, index < card.entries.count,
              !card.deletedIndices.contains(index), let id = card.transactionID(at: index),
              let row = try context.fetch(FetchDescriptor<MoneyTransaction>(
                predicate: #Predicate { $0.stableID == id })).first else { throw Error.invalidEntry }
        if let bookID = card.bookID, row.book?.stableID != bookID { throw Error.invalidEntry }
        return row
    }

    private static func persist(_ card: AIRecordCardState, message: AIChatMessage,
                                lease: AIChatOperationFence.Lease, fence: AIChatOperationFence) throws {
        guard fence.isCurrent(lease) else { throw Error.staleOperation }
        message.recordJSON = String(decoding: try JSONEncoder().encode(card), as: UTF8.self)
        if !card.feedback.isEmpty { message.content = card.feedback }
    }

    private static func perform(
        turnID: UUID, lease: AIChatOperationFence.Lease, in context: ModelContext,
        fence: AIChatOperationFence,
        _ operation: (ModelContext, AIChatMessage, AIRecordCardState) throws -> AIRecordCardState
    ) throws -> AIRecordCardState {
        guard fence.isCurrent(lease) else { throw Error.staleOperation }
        let local = ModelContext(context.container)
        local.autosaveEnabled = false
        do {
            guard let message = try local.fetch(FetchDescriptor<AIChatMessage>(
                predicate: #Predicate { $0.stableID == turnID })).first,
                message.sessionID == lease.sessionID,
                let data = message.recordJSON.data(using: .utf8) else { throw Error.missingCard }
            let card = try JSONDecoder().decode(AIRecordCardState.self, from: data)
            return try operation(local, message, card)
        } catch {
            local.rollback()
            throw error
        }
    }
}
