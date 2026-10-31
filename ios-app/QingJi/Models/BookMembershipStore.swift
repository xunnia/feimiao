import Foundation
import SwiftData

/// 只改变账本关联，绝不复制账单或改变账户结算。
enum BookMembershipStore {
    enum Error: LocalizedError {
        case missingBook
        case missingTransaction

        var errorDescription: String? {
            switch self {
            case .missingBook: return "选择的账本已不存在，请重新选择。"
            case .missingTransaction: return "部分账单已不存在，请刷新后重新选择。"
            }
        }
    }

    enum Operation {
        case replace(Set<UUID>)
        case add(Set<UUID>)
        case remove(Set<UUID>)

        var requestedIDs: Set<UUID> {
            switch self {
            case .replace(let ids), .add(let ids), .remove(let ids): return ids
            }
        }
    }

    struct PreviousValue {
        let transaction: MoneyTransaction
        let raw: String
        let explicit: Bool
        let book: Book?
        let updatedAt: Date

        func restore() {
            transaction.bookMembershipIDsRaw = raw
            transaction.hasExplicitBookMemberships = explicit
            transaction.book = book
            transaction.updatedAt = updatedAt
        }
    }

    @discardableResult
    static func apply(
        transactionIDs: Set<UUID>, operation: Operation, in context: ModelContext
    ) throws -> [PreviousValue] {
        let all = try LedgerStore.allTransactions(in: context)
        let existing = Set(all.map(\.stableID))
        guard transactionIDs.isSubset(of: existing) else { throw Error.missingTransaction }
        let books = try context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.sortOrder)]))
        let validIDs = Set(books.filter { !$0.isDefault }.map(\.stableID))
        guard operation.requestedIDs.isSubset(of: validIDs) else { throw Error.missingBook }
        let rootIDs = Set(all.filter { transactionIDs.contains($0.stableID) }.map { $0.refundOfID ?? $0.stableID })
        let originals = Dictionary(all.filter { rootIDs.contains($0.stableID) }.map { ($0.stableID, $0) },
                                   uniquingKeysWith: { first, _ in first })
        guard rootIDs.isSubset(of: Set(originals.keys)) else { throw Error.missingTransaction }
        var next: [UUID: Set<UUID>] = [:]
        for (id, original) in originals {
            let current = original.scenarioBookIDs.intersection(validIDs)
            switch operation {
            case .replace(let ids): next[id] = ids
            case .add(let ids): next[id] = current.union(ids)
            case .remove(let ids): next[id] = current.subtracting(ids)
            }
        }
        let now = Date()
        return all.compactMap { transaction in
            let rootID = transaction.refundOfID ?? transaction.stableID
            guard let ids = next[rootID] else { return nil }
            let old = PreviousValue(transaction: transaction, raw: transaction.bookMembershipIDsRaw,
                                    explicit: transaction.hasExplicitBookMemberships, book: transaction.book,
                                    updatedAt: transaction.updatedAt)
            transaction.setScenarioBookIDs(ids)
            // 旧关系是历史/资产关联的兼容锚点，不随场景归集移动。
            // 显式空集合会覆盖它，故移出场景也不会重新出现。
            transaction.updatedAt = now
            return old
        }
    }

    static func update(
        transactionIDs: Set<UUID>, operation: Operation, in context: ModelContext,
        saveContext: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard !transactionIDs.isEmpty else { return }
        let previous = try apply(transactionIDs: transactionIDs, operation: operation, in: context)
        do { try saveContext(context) }
        catch {
            previous.forEach { $0.restore() }
            throw error
        }
    }
}
