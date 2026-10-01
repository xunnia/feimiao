import Foundation

/// 旧预算 V2 的取值。旧表只保留不再读（docs/08 §6.12）：这些枚举只给
/// SwiftData 记录的默认值和旧数据迁移到预算规则时识别用。
public enum BudgetPlanCadenceV2: String, Codable, CaseIterable, Hashable, Sendable {
    case monthly
    case weekly
    case oneOff = "one_off"
}

public enum BudgetPlanStatusV2: String, Codable, CaseIterable, Hashable, Sendable {
    case active
    case archived
}

public enum BudgetOverrideIntent: String, Codable, CaseIterable, Hashable, Sendable {
    case replaceTotal = "replace_total"
    case adjustRemaining = "adjust_remaining"
    case setRemaining = "set_remaining"
}
