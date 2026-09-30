import Foundation

// 预算页上规则、金额的显示文字（docs/08 §6.7–§6.9）。
// 和安卓 lib/core/budget/budget_rule_display.dart 一一对应，文字逐字一致。

/// 同一条规则（引擎按 id + createdMs + uuid 认规则）。
public func budgetSameRule(_ a: BudgetRule?, _ b: BudgetRule?) -> Bool {
    guard let a, let b else { return false }
    return a.id == b.id && a.createdMs == b.createdMs && a.uuid == b.uuid
}

/// 整数元，千分位：¥4,000。负数带负号。
public func budgetYuanText(_ cents: Int) -> String {
    let yuan = budgetFloorYuanCents(cents) / 100
    let digits = String(abs(yuan))
    var out = ""
    for (i, ch) in digits.enumerated() {
        if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return (yuan < 0 ? "-" : "") + "¥" + out
}

/// 显示用的「还能花」：向下取整到元，负数不显示（§6.7）。
public func budgetLeftDisplayCents(_ remainingCents: Int) -> Int {
    remainingCents <= 0 ? 0 : budgetFloorYuanCents(remainingCents)
}

public func budgetUnitText(_ unit: BudgetRuleUnit) -> String {
    switch unit {
    case .day: return "每天"
    case .week: return "每周"
    case .month: return "每月"
    case .year: return "每年"
    }
}

/// 「每月 ¥4,000」
public func budgetRuleAmountText(_ rule: BudgetRule) -> String {
    "\(budgetUnitText(rule.unit)) \(budgetYuanText(rule.amountCents))"
}

public func budgetRuleName(_ rule: BudgetRule) -> String {
    let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty { return name }
    return rule.isBase ? "日常" : "特别安排"
}

public enum BudgetRuleState: Sendable { case active, upcoming, ended }

/// 一条规则在列表里的时间说明。
public struct BudgetRuleSpan: Sendable {
    public let state: BudgetRuleState
    /// 「10月起」「5月–9月」「9月25日–27日」
    public let text: String
    /// 实际管到哪天（被后面的日常预算接走时有值）。
    public let effectiveEnd: BudgetCivilDay?
}

private func monthText(_ day: BudgetCivilDay, withYear: Bool) -> String {
    withYear ? "\(day.year)年\(day.month)月" : "\(day.month)月"
}

func budgetDateRangeText(_ start: BudgetCivilDay, _ end: BudgetCivilDay, today: BudgetCivilDay) -> String {
    let withYear = start.year != today.year || end.year != today.year
    let head = withYear ? "\(start.year)年\(start.month)月\(start.day)日" : "\(start.month)月\(start.day)日"
    if start == end { return head }
    let tail: String
    if start.year != end.year {
        tail = "\(end.year)年\(end.month)月\(end.day)日"
    } else if start.month != end.month {
        tail = "\(end.month)月\(end.day)日"
    } else {
        tail = "\(end.day)日"
    }
    return "\(head)–\(tail)"
}

/// rules 是这个账本全部没删的规则（算日常预算被谁接走）。
public func budgetRuleSpan(_ rule: BudgetRule, rules: [BudgetRule], today: BudgetCivilDay) -> BudgetRuleSpan {
    if !rule.isBase, let end = rule.endDate {
        let text = budgetDateRangeText(rule.startDate, end, today: today)
        if today < rule.startDate { return BudgetRuleSpan(state: .upcoming, text: text, effectiveEnd: nil) }
        if today > end { return BudgetRuleSpan(state: .ended, text: text, effectiveEnd: nil) }
        return BudgetRuleSpan(state: .active, text: text, effectiveEnd: nil)
    }
    // 日常预算：后建、且开始日晚于它的那条最早在哪天接手。
    var takeover: BudgetCivilDay?
    for other in BudgetRuleCalendar(rules).rules {
        guard other.isBase, !budgetSameRule(other, rule), other.id != rule.id else { continue }
        guard other.outranks(rule) else { continue }
        if other.startDate <= rule.startDate {
            takeover = rule.startDate
            break
        }
        if takeover == nil || other.startDate < takeover! { takeover = other.startDate }
    }
    let withYear = rule.startDate.year != today.year
    if let takeover, takeover <= rule.startDate {
        return BudgetRuleSpan(state: .ended, text: "没有生效过", effectiveEnd: rule.startDate.adding(days: -1))
    }
    if let takeover, today >= takeover {
        let last = takeover.adding(days: -1)
        let startText = monthText(rule.startDate, withYear: withYear)
        let endText = monthText(last, withYear: withYear || last.year != rule.startDate.year)
        return BudgetRuleSpan(state: .ended,
                              text: startText == endText ? startText : "\(startText)–\(endText)",
                              effectiveEnd: last)
    }
    let text = "\(monthText(rule.startDate, withYear: withYear))起"
    if today < rule.startDate { return BudgetRuleSpan(state: .upcoming, text: text, effectiveEnd: nil) }
    return BudgetRuleSpan(state: .active, text: text, effectiveEnd: takeover?.adding(days: -1))
}

/// 规则列表排序：新建时间倒序（§6.8）。
public func budgetRulesNewestFirst(_ rules: [BudgetRule]) -> [BudgetRule] {
    rules.sorted { $0.outranks($1) }
}

/// 节奏一句话（§6.7）。
public func budgetPaceText(_ month: BudgetMonthResult) -> (text: String, warning: Bool) {
    guard let today = month.today else { return ("", false) }
    let remaining = month.remainingCents
    if month.effectiveCents > 0 && remaining * 10 < month.effectiveCents {
        return remaining <= 0
            ? ("这个月已经超出预算啦", true)
            : ("只剩 \(budgetYuanText(budgetFloorYuanCents(remaining))) 啦", true)
    }
    let delta = today.paceDeltaCents
    if delta >= 0 {
        return ("比计划少花 \(budgetYuanText(budgetFloorYuanCents(delta))) · 节奏不错", false)
    }
    return ("比计划多花 \(budgetYuanText(budgetFloorYuanCents(-delta)))", true)
}

/// 保存前预览里的一行。warning 用警示橙。
public struct BudgetRulePreviewLine: Equatable, Sendable {
    public let text: String
    public let warning: Bool
    public init(_ text: String, warning: Bool = false) {
        self.text = text
        self.warning = warning
    }
}

/// 「每天约 ¥N」：平均到每天，四舍五入到元。
private func perDay(_ cents: Int, _ days: Int) -> String {
    guard days > 0 else { return budgetYuanText(0) }
    return budgetYuanText(Int((Double(cents) / Double(days) / 100).rounded()) * 100)
}

/// 校验不通过时给用户看的话。
public func budgetRuleValidationText(_ validation: BudgetRuleValidation) -> String {
    switch validation.issue {
    case .carveWithoutBase:
        return "\(validation.month)月还没有日常预算，没法从里面匀，可以改成额外多给"
    case .carveExceedsBase:
        return "比\(validation.month)月整月预算还多，其余日子会分不到钱，可以改成额外多给"
    }
}

/// 保存前的预览（§6.5）。existing 是这个账本没删的全部规则，
/// candidate 编辑时带原 id、新建时 id 为 0。
public func budgetRulePreview(existing: [BudgetRule], candidate: BudgetRule, today: BudgetCivilDay) -> [BudgetRulePreviewLine] {
    let others = existing.filter { !$0.isDeleted && (candidate.id == 0 || $0.id != candidate.id) }
    let rules = others + [candidate]
    func resolve(_ set: [BudgetRule], _ year: Int, _ month: Int) -> BudgetMonthResult {
        BudgetRuleEngine.resolveMonth(rules: set, spendByDay: [:], year: year, month: month, today: today)
    }

    if candidate.isBase {
        let at = candidate.startDate > today ? candidate.startDate : today
        let month = resolve(rules, at.year, at.month)
        let plain = month.days.filter { $0.specialRule == nil && budgetSameRule($0.baseRule, candidate) }
        var lines = [BudgetRulePreviewLine("\(at.month)月一共 \(budgetYuanText(month.budgetCents))")]
        if !plain.isEmpty {
            lines.append(BudgetRulePreviewLine("平时每天约 \(perDay(plain.reduce(0) { $0 + $1.budgetCents }, plain.count))"))
        }
        return lines
    }

    guard let end = candidate.endDate else { return [] }
    let count = candidate.startDate.days(to: end) + 1
    let total = budgetSpecialTotalYuan(candidate) * 100
    var lines = [BudgetRulePreviewLine(count == 1
        ? "这一天 \(budgetYuanText(total))"
        : "这 \(count) 天一共 \(budgetYuanText(total))，每天约 \(perDay(total, count))")]

    if let issue = BudgetRuleEngine.validateSpecial(existing: others, candidate: candidate) {
        lines.append(BudgetRulePreviewLine(budgetRuleValidationText(issue), warning: true))
        return lines
    }

    let firstIndex = candidate.startDate.monthIndex
    let lastIndex = end.monthIndex
    var index = firstIndex
    while index <= lastIndex && index < firstIndex + 3 {
        let year = index / 12
        let m = index % 12 + 1
        let after = resolve(rules, year, m)
        let before = resolve(others, year, m)
        let added = after.budgetCents - before.budgetCents
        let rest = after.days.filter { $0.specialRule == nil && $0.baseRule != nil }
        let restText = rest.isEmpty
            ? ""
            : "，其余日子每天约 \(perDay(rest.reduce(0) { $0 + $1.budgetCents }, rest.count))"
        lines.append(BudgetRulePreviewLine(added == 0
            ? "\(m)月一共还是 \(budgetYuanText(after.budgetCents))\(restText)"
            : "\(m)月一共 \(budgetYuanText(after.budgetCents))（多了 \(budgetYuanText(added))）\(restText)"))
        index += 1
    }
    if lastIndex >= firstIndex + 3 {
        lines.append(BudgetRulePreviewLine("后面几个月照同样的方法算"))
    }

    // 会盖掉哪条特别安排的哪几天（按先后顺序列）。
    let oldCalendar = BudgetRuleCalendar(others)
    let newCalendar = BudgetRuleCalendar(rules)
    var covered: [(rule: BudgetRule, days: [BudgetCivilDay])] = []
    var d = candidate.startDate
    while d <= end {
        defer { d = d.adding(days: 1) }
        guard budgetSameRule(newCalendar.specialOwner(d), candidate),
              let previous = oldCalendar.specialOwner(d) else { continue }
        if let i = covered.firstIndex(where: { budgetSameRule($0.rule, previous) }) {
            covered[i].days.append(d)
        } else {
            covered.append((previous, [d]))
        }
    }
    for entry in covered {
        lines.append(BudgetRulePreviewLine(
            "会盖掉「\(budgetRuleName(entry.rule))」的 \(budgetDateRangeText(entry.days.first!, entry.days.last!, today: today))"))
    }
    return lines
}

/// 改日常预算的金额或单位时，保存前的提示（§6.4）；没改就返回 nil。
public func budgetBaseEditWarning(original: BudgetRule?, amountCents: Int, unit: BudgetRuleUnit,
                                  today: BudgetCivilDay) -> String? {
    guard let original, original.isBase else { return nil }
    if original.amountCents == amountCents && original.unit == unit { return nil }
    let start = original.startDate
    let head = start.year != today.year ? "\(start.year)年\(start.month)月" : "\(start.month)月"
    return "\(head)以来的每个月都会按新金额重新计算"
}

// MARK: - 计入预算的支出（§6.7，和安卓 _budgetSpendByDay 同一口径）

/// 一笔原始交易行（已按账本范围筛过）。
public struct BudgetSpendRow: Sendable {
    public let id: UUID
    public let isExpense: Bool
    public let amountCents: Int
    public let currencyCode: String
    public let attributionDay: BudgetCivilDay
    public let createdAt: Date?
    public let refundOfID: UUID?
    public let isExcluded: Bool

    public init(id: UUID, isExpense: Bool, amountCents: Int, currencyCode: String,
                attributionDay: BudgetCivilDay, createdAt: Date?, refundOfID: UUID?, isExcluded: Bool) {
        self.id = id
        self.isExpense = isExpense
        self.amountCents = amountCents
        self.currencyCode = currencyCode
        self.attributionDay = attributionDay
        self.createdAt = createdAt
        self.refundOfID = refundOfID
        self.isExcluded = isExcluded
    }
}

/// yyyymmdd → 当天计入预算的支出（分）；foreign：yyyymmdd → 被排除的非 CNY 笔数。
/// - 只算支出家族，净额 = 原单 − 已发生的退款，净额 ≤ 0 不算；
/// - 「不计入预算」（isExcluded）不算；
/// - 归属日晚于 today 的等到那天；创建时间晚于 knowledgeCutoff 的当作还不知道；
/// - 遗留的独立负支出行按带符号金额冲减。
public func budgetSpendByDay(_ rows: [BudgetSpendRow], today: BudgetCivilDay,
                             knowledgeCutoff: Date) -> (spend: [Int: Int], foreign: [Int: Int]) {
    func unknown(_ createdAt: Date?) -> Bool { (createdAt ?? .distantPast) > knowledgeCutoff }
    var refunds: [UUID: [BudgetSpendRow]] = [:]
    for row in rows where row.isExpense {
        if let root = row.refundOfID { refunds[root, default: []].append(row) }
    }
    var spend: [Int: Int] = [:]
    var foreign: [Int: Int] = [:]
    for row in rows where row.isExpense && row.refundOfID == nil && row.amountCents != 0 {
        if row.isExcluded { continue }
        if unknown(row.createdAt) || row.attributionDay > today { continue }
        let key = row.attributionDay.key
        if row.currencyCode.trimmingCharacters(in: .whitespaces).uppercased() != "CNY" {
            foreign[key, default: 0] += 1
            continue
        }
        var net = row.amountCents
        if net > 0 {
            for refund in refunds[row.id] ?? [] {
                if unknown(refund.createdAt) || refund.attributionDay > today { continue }
                net -= abs(refund.amountCents)
            }
            if net <= 0 { continue }
        }
        spend[key, default: 0] += net
    }
    return (spend, foreign)
}

/// 这个月有规则、且不晚于今天的日子里，被排除的外币笔数。
public func budgetForeignCount(_ foreign: [Int: Int], month: BudgetMonthResult, today: BudgetCivilDay) -> Int {
    guard !foreign.isEmpty else { return 0 }
    return month.days.reduce(0) { sum, day in
        day.covered && day.day <= today ? sum + (foreign[day.day.key] ?? 0) : sum
    }
}
