import Foundation

/// 账本筛选的单一入口。
///
/// nil 是总账本，包含全部原记录。多个场景合并查看时按稳定标识去重。
/// 退款/报销跟随原交易家族，避免旧数据的子行漏掉冲减。
enum LedgerScope {
    static func filter(_ transactions: [MoneyTransaction], selectedBookID: UUID?, books: [Book] = []) -> [MoneyTransaction] {
        filter(transactions, selectedBookIDs: selectedBookID.map { Set([$0]) }, books: books)
    }

    static func filter(_ transactions: [MoneyTransaction], selectedBookIDs: Set<UUID>?, books: [Book] = []) -> [MoneyTransaction] {
        var selectedBookIDs = selectedBookIDs
        let defaultIDs = Set(books.filter(\.isDefault).map(\.stableID))
            .union(transactions.compactMap { $0.book?.isDefault == true ? $0.book?.stableID : nil })
        if let requested = selectedBookIDs, !requested.isDisjoint(with: defaultIDs) { selectedBookIDs = nil }
        let roots = Dictionary(transactions.filter { $0.refundOfID == nil }.map { ($0.stableID, $0) },
                               uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        return transactions.filter { transaction in
            let original = transaction.refundOfID.flatMap { roots[$0] } ?? transaction
            if let selectedBookIDs, original.scenarioBookIDs.isDisjoint(with: selectedBookIDs) { return false }
            return seen.insert(transaction.stableID).inserted
        }
    }

    /// 新关联可从当前场景选账；已有资产原始锚点继续有效。
    static func allowsAssetAssociation(_ transaction: MoneyTransaction, bookID: UUID?, books: [Book]) -> Bool {
        guard let bookID else { return false }
        return transaction.book?.stableID == bookID || transaction.scenarioBookIDs.contains(bookID)
    }
}
