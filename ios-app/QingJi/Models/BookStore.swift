import Foundation
import SwiftData

/// 删除场景账本只解除关联，保留全部原始记录及其他场景。
enum BookStore {
    enum BookStoreError: LocalizedError {
        case defaultBook
        case noFallback
        case globalDeletionNotAllowed

        var errorDescription: String? {
            switch self {
            case .defaultBook: return "总账本不能删除。"
            case .noFallback: return "至少需要保留一个总账本。"
            case .globalDeletionNotAllowed: return "删除账本不会删除账单。请在明细页单独确认从所有账本删除原账单。"
            }
        }
    }

    static func transactionCount(for book: Book, in context: ModelContext) -> Int {
        let all = (try? LedgerStore.allTransactions(in: context)) ?? []
        return LedgerScope.filter(all, selectedBookID: book.isDefault ? nil : book.stableID).filter { $0.refundOfID == nil }.count
    }

    /// 保留旧调用名；新的语义仅是移除场景关联，不移动/复制账单。
    static func deleteMovingTransactions(_ book: Book, in context: ModelContext,
                                         saveContext: AssetFinancialCommand.Save = { try $0.save() }) throws {
        guard !book.isDefault else { throw BookStoreError.defaultBook }
        let books = try context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.sortOrder)]))
        guard let fallback = books.first(where: { $0.isDefault }) else { throw BookStoreError.noFallback }
        let all = try LedgerStore.allTransactions(in: context)
        let ids = Set(LedgerScope.filter(all, selectedBookID: book.stableID).map(\.stableID))
        try AssetFinancialCommand.perform(in: context, save: saveContext) { changes in
            let previous = try BookMembershipStore.apply(transactionIDs: ids, operation: .remove([book.stableID]), in: context)
            changes.restoreOnFailure { previous.forEach { $0.restore() } }
            // 删除场景时将旧兼容锚点转到总账本，所有金额、资产、周期规则都保留。
            for transaction in all where transaction.book?.stableID == book.stableID {
                let old = transaction.book
                changes.restoreOnFailure { transaction.book = old }
                transaction.book = fallback
            }
            if AssetFinancialCommand.contains(BudgetRuleRecord.self, in: context) {
                let oldRules = try context.fetch(FetchDescriptor<BudgetRuleRecord>())
                    .filter { $0.bookID == book.stableID }
                    .map { ($0, $0.deletedMs, $0.updatedMs) }
                changes.restoreOnFailure {
                    oldRules.forEach { record, deleted, updated in record.deletedMs = deleted; record.updatedMs = updated }
                }
                BudgetRuleStore.deleteRules(forBook: book.stableID, in: context)
            }
            try remap(PhysicalAsset.self, \.bookID, from: book.stableID, to: fallback.stableID, in: context, changes: changes)
            try remap(ReceivableAsset.self, \.bookID, from: book.stableID, to: fallback.stableID, in: context, changes: changes)
            try remap(RecurringRule.self, \.bookID, from: book.stableID, to: fallback.stableID, in: context, changes: changes)
            try remap(ReportRecord.self, \.bookID, from: book.stableID, to: nil, in: context, changes: changes)
            if AssetFinancialCommand.contains(AIChatMessage.self, in: context) {
                for message in try context.fetch(FetchDescriptor<AIChatMessage>()) {
                    guard let data = message.recordJSON.data(using: .utf8),
                          var card = try? JSONDecoder().decode(AIRecordCardState.self, from: data), card.bookID == book.stableID else { continue }
                    let old = message.recordJSON
                    changes.restoreOnFailure { message.recordJSON = old }
                    card.bookID = fallback.stableID
                    message.recordJSON = String(decoding: try JSONEncoder().encode(card), as: UTF8.self)
                }
            }
            // 旧 Budget / V2 预算与结转记录属于历史数据，本操作不删除或改写它们。
            changes.delete(book)
        }
    }

    private static func remap<T: PersistentModel>(
        _ type: T.Type, _ key: ReferenceWritableKeyPath<T, UUID?>, from oldID: UUID, to newID: UUID?,
        in context: ModelContext, changes: AssetFinancialCommand.Changes
    ) throws {
        guard AssetFinancialCommand.contains(type, in: context) else { return }
        for model in try context.fetch(FetchDescriptor<T>()) where model[keyPath: key] == oldID {
            let previous = model[keyPath: key]
            changes.restoreOnFailure { model[keyPath: key] = previous }
            model[keyPath: key] = newID
        }
    }

    /// 兼容旧调用，禁止账本操作携带全局删账；原账单删除由独立入口确认。
    static func deleteWithTransactions(_ book: Book, in context: ModelContext) throws {
        guard !book.isDefault else { throw BookStoreError.defaultBook }
        throw BookStoreError.globalDeletionNotAllowed
    }
}
