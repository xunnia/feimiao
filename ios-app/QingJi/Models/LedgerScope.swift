import Foundation

/// 账本筛选的单一入口。
///
/// nil 代表安卓端的「总账本」聚合视图：默认账本和所有开启「计入总账」的账本
/// 都可见。没有账本归属的旧版流水按历史兼容规则保留在总账本中。
enum LedgerScope {
    static func filter(_ transactions: [MoneyTransaction], selectedBookID: UUID?) -> [MoneyTransaction] {
        transactions.filter { transaction in
            guard let selectedBookID else {
                return transaction.book?.includeInTotal ?? true
            }
            return transaction.book?.stableID == selectedBookID
        }
    }
}
