import Foundation
import SwiftData

/// 账本删除保护，抽屉 ⋯ 菜单和账本管理页共用（对齐安卓 _confirmDeleteBook）：
/// 没账目直接删；有账目先推荐「转移到总账本再删」，拒绝后才允许连账目永久删除。
enum BookStore {
    enum BookStoreError: LocalizedError {
        case defaultBook
        case noFallback

        var errorDescription: String? {
            switch self {
            case .defaultBook: return "总账本不能删除。"
            case .noFallback: return "至少需要保留一个总账本。"
            }
        }
    }

    static func transactionCount(for book: Book, in context: ModelContext) -> Int {
        let all = (try? LedgerStore.allTransactions(in: context)) ?? []
        return all.filter { $0.book?.persistentModelID == book.persistentModelID }.count
    }

    /// 账目转回总账本后删除账本。
    static func deleteMovingTransactions(_ book: Book, in context: ModelContext) throws {
        guard !book.isDefault else { throw BookStoreError.defaultBook }
        let books = try context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.sortOrder)]))
        guard let fallback = books.first(where: { $0.isDefault })
            ?? books.first(where: { $0.persistentModelID != book.persistentModelID }) else {
            throw BookStoreError.noFallback
        }
        let all = try LedgerStore.allTransactions(in: context)
        for transaction in all where transaction.book?.persistentModelID == book.persistentModelID {
            transaction.book = fallback
            transaction.updatedAt = Date()
        }
        // 这个账本的预算规则一起软删（和安卓 deleteBook 一致）。
        BudgetRuleStore.deleteRules(forBook: book.stableID, in: context)
        context.delete(book)
        try context.save()
    }

    /// 连同账目一起永久删除。逐笔走 LedgerStore.delete，退款子行、报销标记和附件照常清理。
    static func deleteWithTransactions(_ book: Book, in context: ModelContext) throws {
        guard !book.isDefault else { throw BookStoreError.defaultBook }
        let bookID = book.persistentModelID
        let transactions = try LedgerStore.allTransactions(in: context)
            .filter { $0.book?.persistentModelID == bookID }
        try LedgerStore.assertTransactionsCanBeDeleted(transactions, in: context)
        // 删原账单会级联删掉它的退款子行，所以每次重新取一遍，避免删到已删除的对象。
        while let next = try LedgerStore.allTransactions(in: context)
            .first(where: { $0.book?.persistentModelID == bookID }) {
            try LedgerStore.delete(next, in: context)
        }
        // 这个账本的预算规则一起软删（和安卓 deleteBook 一致）。
        BudgetRuleStore.deleteRules(forBook: book.stableID, in: context)
        context.delete(book)
        try context.save()
    }
}
