import Foundation

/// 预置分类（中英双语），首次启动时写入数据库。
public struct CategorySeed: Equatable, Sendable {
    /// 稳定标识，不随语言变化，用于排序学习与导入匹配。
    public let key: String
    public let nameZh: String
    public let nameEn: String
    /// SF Symbol 图标名。
    public let symbol: String
    public let kind: TransactionKind

    public init(key: String, nameZh: String, nameEn: String, symbol: String, kind: TransactionKind) {
        self.key = key
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.symbol = symbol
        self.kind = kind
    }

    public func localizedName(languageCode: String) -> String {
        languageCode.lowercased().hasPrefix("zh") ? nameZh : nameEn
    }

    /// 兜底分类，导入账单匹配不到分类时使用。
    public static let fallbackExpenseKey = "other"

    public static let expenses: [CategorySeed] = [
        .init(key: "dining", nameZh: "餐饮", nameEn: "Dining", symbol: "fork.knife", kind: .expense),
        .init(key: "groceries", nameZh: "买菜超市", nameEn: "Groceries", symbol: "cart", kind: .expense),
        .init(key: "transport", nameZh: "交通", nameEn: "Transport", symbol: "bus", kind: .expense),
        .init(key: "shopping", nameZh: "购物", nameEn: "Shopping", symbol: "bag", kind: .expense),
        .init(key: "entertainment", nameZh: "娱乐", nameEn: "Entertainment", symbol: "gamecontroller", kind: .expense),
        .init(key: "housing", nameZh: "住房", nameEn: "Housing", symbol: "house", kind: .expense),
        .init(key: "utilities", nameZh: "水电网", nameEn: "Utilities", symbol: "bolt", kind: .expense),
        .init(key: "medical", nameZh: "医疗", nameEn: "Medical", symbol: "cross.case", kind: .expense),
        .init(key: "education", nameZh: "学习", nameEn: "Education", symbol: "book", kind: .expense),
        .init(key: "travel", nameZh: "旅行", nameEn: "Travel", symbol: "airplane", kind: .expense),
        .init(key: "pets", nameZh: "宠物", nameEn: "Pets", symbol: "pawprint", kind: .expense),
        .init(key: "gifts", nameZh: "人情", nameEn: "Gifts", symbol: "gift", kind: .expense),
        .init(key: "subscription", nameZh: "订阅", nameEn: "Subscriptions", symbol: "arrow.triangle.2.circlepath", kind: .expense),
        .init(key: "other", nameZh: "其他", nameEn: "Other", symbol: "ellipsis.circle", kind: .expense),
    ]

    public static let incomes: [CategorySeed] = [
        .init(key: "salary", nameZh: "工资", nameEn: "Salary", symbol: "banknote", kind: .income),
        .init(key: "bonus", nameZh: "奖金", nameEn: "Bonus", symbol: "star", kind: .income),
        .init(key: "investment", nameZh: "理财", nameEn: "Investment", symbol: "chart.line.uptrend.xyaxis", kind: .income),
        .init(key: "redPacket", nameZh: "红包", nameEn: "Red Packet", symbol: "envelope", kind: .income),
        .init(key: "refund", nameZh: "退款", nameEn: "Refund", symbol: "arrow.uturn.backward", kind: .income),
        .init(key: "otherIncome", nameZh: "其他", nameEn: "Other", symbol: "plus.circle", kind: .income),
    ]

    public static let all: [CategorySeed] = expenses + incomes
}
