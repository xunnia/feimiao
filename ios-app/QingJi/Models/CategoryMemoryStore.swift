import Foundation
import QingJiCore

/// 轻量的本地分类学习记忆。
///
/// 记忆只保存“决定性商户 -> 分类 key”，不会把京东、淘宝这类万能平台
/// 学成某个子分类。之后如果迁移到 CloudKit/完整备份，仍可沿用同一稳定 key。
enum CategoryMemoryStore {
    private static let defaultsKey = "qingji.category-memory.v1"

    struct Item: Identifiable, Hashable {
        let merchant: String
        let kind: TransactionKind
        let categoryKey: String

        var id: String { "\(kind.rawValue)|\(merchant)" }
    }

    static func categoryKey(
        for merchant: String,
        kind: TransactionKind,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard let merchantKey = BillCategorizer.learnKey(for: merchant) else { return nil }
        let values = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        return values[storageKey(merchantKey, kind: kind)]
    }

    static func learn(
        merchant: String,
        kind: TransactionKind,
        categoryKey: String,
        defaults: UserDefaults = .standard
    ) {
        let cleanCategoryKey = categoryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let merchantKey = BillCategorizer.learnKey(for: merchant),
              !cleanCategoryKey.isEmpty else { return }
        var values = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        // The caller has already selected a category from the current SwiftData
        // tree. Do not validate only against the built-in seed list here, or a
        // user-created category can never participate in the learning loop.
        values[storageKey(merchantKey, kind: kind)] = cleanCategoryKey
        defaults.set(values, forKey: defaultsKey)
    }

    static func all(defaults: UserDefaults = .standard) -> [Item] {
        let values = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        return values.compactMap { key, categoryKey in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let kind = TransactionKind(rawValue: parts[0]),
                   !parts[1].isEmpty,
                   !categoryKey.isEmpty else { return nil }
            return Item(merchant: parts[1], kind: kind, categoryKey: categoryKey)
        }
        .sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.merchant.localizedStandardCompare(rhs.merchant) == .orderedAscending
        }
    }

    static func forget(
        merchant: String,
        kind: TransactionKind,
        defaults: UserDefaults = .standard
    ) {
        guard let merchantKey = BillCategorizer.learnKey(for: merchant) else { return }
        var values = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        values.removeValue(forKey: storageKey(merchantKey, kind: kind))
        defaults.set(values, forKey: defaultsKey)
    }

    private static func storageKey(_ merchant: String, kind: TransactionKind) -> String {
        "\(kind.rawValue)|\(merchant.lowercased())"
    }
}
