import Foundation

/// 旧预算（Budget 表）的周期字段。旧表只保留不再读（docs/08 §6.12），
/// 这个枚举只给旧数据迁移到预算规则时识别用。
public enum BudgetCycle: String, Codable, CaseIterable, Hashable, Sendable {
    case monthly
    case weekly
    case custom
}

/// 主页、统计环、记一笔页展示的月预算状态（由预算规则算出，见 BudgetRuleStore）。
public struct BudgetStatus: Equatable, Sendable {
    public let monthlyBudget: Decimal
    public let spentThisMonth: Decimal
    public let spentToday: Decimal
    /// 月剩余预算（可为负）。
    public let remaining: Decimal
    /// 「今日可花」：(预算 − 今天之前已花) ÷ 含今天的剩余天数 − 今天已花。可为负。
    public let todayAllowance: Decimal
    public let isOverBudget: Bool

    public init(
        monthlyBudget: Decimal,
        spentThisMonth: Decimal,
        spentToday: Decimal,
        remaining: Decimal,
        todayAllowance: Decimal,
        isOverBudget: Bool
    ) {
        self.monthlyBudget = monthlyBudget
        self.spentThisMonth = spentThisMonth
        self.spentToday = spentToday
        self.remaining = remaining
        self.todayAllowance = todayAllowance
        self.isOverBudget = isOverBudget
    }
}
