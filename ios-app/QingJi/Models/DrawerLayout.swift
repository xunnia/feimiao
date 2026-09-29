import Foundation

/// 主页抽屉的纯逻辑（对齐安卓 main.dart 抽屉）：功能项顺序、折叠条数、账本排序。
/// 放在 Models 里是为了让 XCTest 直接验证，不用跑界面。
enum DrawerLayout {
    /// 抽屉功能项。rawValue 与安卓持久化的 key 一致，顺序即默认顺序。
    enum Item: String, CaseIterable, Identifiable {
        case stats, assets, budget, savings, assistant, categories, tags
        case importExport = "import"
        case reimburse, recurring, autorecord

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stats: "统计数据"
            case .assets: "资产管理"
            case .budget: "预算管理"
            case .savings: "存钱目标"
            case .assistant: "喵助手"
            case .categories: "分类管理"
            case .tags: "标签管理"
            case .importExport: "导入导出"
            case .reimburse: "待报销"
            case .recurring: "定时记账"
            case .autorecord: "自动记账"
            }
        }

        /// iOS 没有安卓那套细线图标，功能行允许用 SF Symbols（Logo/猫/分类图标/封面除外）。
        var symbol: String {
            switch self {
            case .stats: "chart.bar.xaxis"
            case .assets: "wallet.bifold"
            case .budget: "calendar"
            case .savings: "banknote"
            case .assistant: "sparkles"
            case .categories: "square.grid.2x2"
            case .tags: "tag"
            case .importExport: "arrow.up.arrow.down"
            case .reimburse: "receipt"
            case .recurring: "calendar.badge.clock"
            case .autorecord: "bell"
            }
        }
    }

    /// 折叠时显示的条数，与安卓一致。
    static let collapsedCount = 5

    /// 从持久化字符串（逗号分隔的 key）还原顺序：未知 key 丢掉、重复只留第一次、
    /// 新增的功能按默认顺序补在末尾。这样老版本存下来的顺序升级后不会丢项。
    static func order(from stored: String) -> [Item] {
        var seen = Set<Item>()
        var result: [Item] = []
        for raw in stored.split(separator: ",") {
            let key = raw.trimmingCharacters(in: .whitespaces)
            guard let item = Item(rawValue: key), !seen.contains(item) else { continue }
            seen.insert(item)
            result.append(item)
        }
        for item in Item.allCases where !seen.contains(item) {
            result.append(item)
        }
        return result
    }

    static func storedValue(for order: [Item]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    /// 把 `item` 挪到 `target` 所在的位置（长按拖动排序用）。任一不在列表里时原样返回。
    static func move(_ item: Item, onto target: Item, in order: [Item]) -> [Item] {
        guard item != target,
              let from = order.firstIndex(of: item),
              let to = order.firstIndex(of: target) else { return order }
        var next = order
        next.remove(at: from)
        next.insert(item, at: to)
        return next
    }

    /// 账本显示顺序：总账本（默认账本）第一，加星靠前，其余保持原顺序。
    /// 抽屉列表和主页账本快切共用。
    static func orderedBooks<T>(
        _ books: [T],
        isDefault: (T) -> Bool,
        isStarred: (T) -> Bool
    ) -> [T] {
        func rank(_ book: T) -> Int {
            if isDefault(book) { return 0 }
            return isStarred(book) ? 1 : 2
        }
        return books.enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element), r = rank(rhs.element)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    static func orderedBooks(_ books: [Book]) -> [Book] {
        orderedBooks(books, isDefault: \.isDefault, isStarred: \.isStarred)
    }
}
