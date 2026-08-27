import Foundation

/// 主 App 与 WidgetKit 扩展之间的只读快照。扩展不能直接依赖 SwiftData
/// 业务容器，所有金额由主 App 用同一套统计规则先算好再写入 App Group。
public struct WidgetCategorySnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let amountText: String
    public let percentText: String
    public let progress: Int
    public let count: Int

    public init(
        id: String,
        name: String,
        amountText: String,
        percentText: String,
        progress: Int,
        count: Int
    ) {
        self.id = id
        self.name = name
        self.amountText = amountText
        self.percentText = percentText
        self.progress = progress
        self.count = count
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAtMs: Int64
    public let bookName: String
    public let dateText: String
    public let todayExpenseText: String
    public let monthExpenseText: String
    public let monthIncomeText: String
    public let balanceText: String
    public let budgetTitle: String
    public let budgetText: String
    public let budgetHint: String
    public let budgetProgress: Int
    public let paceCaption: String
    public let paceAverageText: String
    public let privacyMode: Bool
    public let categories: [WidgetCategorySnapshot]

    public init(
        generatedAtMs: Int64,
        bookName: String,
        dateText: String,
        todayExpenseText: String,
        monthExpenseText: String,
        monthIncomeText: String,
        balanceText: String,
        budgetTitle: String,
        budgetText: String,
        budgetHint: String,
        budgetProgress: Int,
        paceCaption: String,
        paceAverageText: String,
        privacyMode: Bool,
        categories: [WidgetCategorySnapshot]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAtMs = generatedAtMs
        self.bookName = bookName
        self.dateText = dateText
        self.todayExpenseText = todayExpenseText
        self.monthExpenseText = monthExpenseText
        self.monthIncomeText = monthIncomeText
        self.balanceText = balanceText
        self.budgetTitle = budgetTitle
        self.budgetText = budgetText
        self.budgetHint = budgetHint
        self.budgetProgress = min(max(budgetProgress, 0), 100)
        self.paceCaption = paceCaption
        self.paceAverageText = paceAverageText
        self.privacyMode = privacyMode
        self.categories = categories
    }

    public static let empty = WidgetSnapshot(
        generatedAtMs: 0,
        bookName: "肥喵记账",
        dateText: "",
        todayExpenseText: "--",
        monthExpenseText: "--",
        monthIncomeText: "--",
        balanceText: "--",
        budgetTitle: "本月支出",
        budgetText: "--",
        budgetHint: "打开肥喵记账后刷新",
        budgetProgress: 0,
        paceCaption: "暂无数据",
        paceAverageText: "--",
        privacyMode: false,
        categories: []
    )
}
