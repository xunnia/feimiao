import Foundation

// 预算规则模型（docs/08-预算与资产方案.md §6，2026-09-30 用户定稿）。
// 和安卓 lib/core/budget/budget_rules.dart、budget_rule_calendar.dart、
// budget_rule_engine.dart 一一对应，同一套整数算法，两端结果一致到分。
// 纯逻辑：日期用不带时区的公历日（BudgetCivilDay），不受设备时区影响。

public enum BudgetRuleKind: String, Codable, Sendable { case base, special }
public enum BudgetRuleUnit: String, Codable, CaseIterable, Sendable { case day, week, month, year }
public enum BudgetFunding: String, Codable, Sendable { case carve, extra }

public enum BudgetRolloverMode: String, Codable, CaseIterable, Sendable {
    case reset
    case keepSavings = "keep_savings"
    case carryBoth = "carry_both"
}

/// 不带时区的公历日。serial = 从 1970-01-01 起的天数。
public struct BudgetCivilDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        // 规整越界的日/月，和 Dart 的 DateTime(y, m, d) 一样。
        let normalized = BudgetCivilDay.fromSerial(
            BudgetCivilDay.serial(year: year, month: month, day: 1) + day - 1
        )
        self.year = normalized.0
        self.month = normalized.1
        self.day = normalized.2
    }

    private init(raw: (Int, Int, Int)) {
        year = raw.0
        month = raw.1
        day = raw.2
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// 解析 `YYYY-MM-DD`；无效返回 nil。
    public init?(text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1, d <= BudgetCivilDay.daysInMonth(year: y, month: m)
        else { return nil }
        self.init(raw: (y, m, d))
    }

    public var serial: Int { BudgetCivilDay.serial(year: year, month: month, day: day) }
    /// yyyymmdd
    public var key: Int { year * 10000 + month * 100 + day }
    /// 周一 = 1 … 周日 = 7（和 Dart 的 weekday 相同）。
    public var weekday: Int { ((serial % 7) + 7 + 3) % 7 + 1 }
    public var text: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { text }
    public var monthIndex: Int { year * 12 + month - 1 }

    public func adding(days: Int) -> BudgetCivilDay {
        BudgetCivilDay(raw: BudgetCivilDay.fromSerial(serial + days))
    }

    public func days(to other: BudgetCivilDay) -> Int { other.serial - serial }

    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    public static func < (lhs: BudgetCivilDay, rhs: BudgetCivilDay) -> Bool { lhs.serial < rhs.serial }

    public static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    // Howard Hinnant 的 days_from_civil / civil_from_days。
    static func serial(year: Int, month: Int, day: Int) -> Int {
        let totalMonths = year * 12 + (month - 1)
        let y0 = Int((Double(totalMonths) / 12).rounded(.down))
        let m0 = totalMonths - y0 * 12 + 1
        let y = m0 <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m0 + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func fromSerial(_ value: Int) -> (Int, Int, Int) {
        let z = value + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return (y, m, d)
    }
}

/// 单位对应的自然周期：一天、周一到周日、自然月、自然年。
public func budgetNaturalPeriod(_ unit: BudgetRuleUnit, _ day: BudgetCivilDay) -> (start: BudgetCivilDay, length: Int) {
    switch unit {
    case .day:
        return (day, 1)
    case .week:
        return (day.adding(days: 1 - day.weekday), 7)
    case .month:
        return (BudgetCivilDay(year: day.year, month: day.month, day: 1),
                BudgetCivilDay.daysInMonth(year: day.year, month: day.month))
    case .year:
        return (BudgetCivilDay(year: day.year, month: 1, day: 1),
                BudgetCivilDay.isLeap(day.year) ? 366 : 365)
    }
}

/// 把 total 元平均分给 count 天，零头按 1 元一份从第一天起分。
public func budgetEvenShare(_ total: Int, _ count: Int, _ index: Int) -> Int {
    total / count + (index < total % count ? 1 : 0)
}

/// 向下取整到元（分）。负数也向下。
public func budgetFloorYuanCents(_ cents: Int) -> Int {
    Int((Double(cents) / 100).rounded(.down)) * 100
}

public struct BudgetRule: Hashable, Sendable {
    public let id: Int
    public let uuid: String
    public let bookID: String
    public let kind: BudgetRuleKind
    public let name: String
    /// 分，100 的倍数。
    public let amountCents: Int
    public let unit: BudgetRuleUnit
    public let startDate: BudgetCivilDay
    public let endDate: BudgetCivilDay?
    public let funding: BudgetFunding?
    public let colorIndex: Int
    public let createdMs: Int
    public let updatedMs: Int
    public let deletedMs: Int?

    public init(
        id: Int,
        uuid: String = "",
        bookID: String,
        kind: BudgetRuleKind,
        name: String = "",
        amountCents: Int,
        unit: BudgetRuleUnit,
        startDate: BudgetCivilDay,
        endDate: BudgetCivilDay? = nil,
        funding: BudgetFunding? = nil,
        colorIndex: Int = 0,
        createdMs: Int,
        updatedMs: Int? = nil,
        deletedMs: Int? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.bookID = bookID
        self.kind = kind
        self.name = name
        self.amountCents = amountCents
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
        self.funding = funding
        self.colorIndex = colorIndex
        self.createdMs = createdMs
        self.updatedMs = updatedMs ?? createdMs
        self.deletedMs = deletedMs
    }

    public var amountYuan: Int { amountCents / 100 }
    public var isBase: Bool { kind == .base }
    public var isDeleted: Bool { deletedMs != nil }
    /// 「匀」是默认；只有明确写了 extra 才额外多给。
    public var isExtra: Bool { funding == .extra }

    public func covers(_ day: BudgetCivilDay) -> Bool {
        day >= startDate && (endDate.map { day <= $0 } ?? true)
    }

    /// 新建时间晚的优先；同一毫秒按 id。编辑不改变先后。
    public func outranks(_ other: BudgetRule) -> Bool {
        createdMs != other.createdMs ? createdMs > other.createdMs : id > other.id
    }
}

public struct BudgetRolloverChange: Hashable, Sendable {
    public let id: Int
    public let bookID: String
    public let year: Int
    public let month: Int
    public let mode: BudgetRolloverMode

    public init(id: Int, bookID: String, year: Int, month: Int, mode: BudgetRolloverMode) {
        self.id = id
        self.bookID = bookID
        self.year = year
        self.month = month
        self.mode = mode
    }

    public var monthIndex: Int { year * 12 + month - 1 }
}

public struct BudgetDayInfo: Sendable {
    public let day: BudgetCivilDay
    public let budgetCents: Int
    public let baseRule: BudgetRule?
    public let specialRule: BudgetRule?

    /// 有任何规则管这一天。没有规则的日子，支出不计入预算。
    public var covered: Bool { baseRule != nil || specialRule != nil }
}

/// 特别安排一共多少元：对每一天取「金额 ÷ 该单位自然周期天数」再加总，
/// 四舍五入到元。用公分母做精确整数运算。
public func budgetSpecialTotalYuan(_ rule: BudgetRule) -> Int {
    guard let end = rule.endDate, end >= rule.startDate else { return 0 }
    var counts: [Int: Int] = [:]
    var d = rule.startDate
    while d <= end {
        counts[budgetNaturalPeriod(rule.unit, d).length, default: 0] += 1
        d = d.adding(days: 1)
    }
    func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    var lcm = 1
    for length in counts.keys { lcm = lcm / gcd(lcm, length) * length }
    var numerator = 0
    for (length, count) in counts { numerator += count * (lcm / length) }
    return (2 * rule.amountYuan * numerator + lcm) / (2 * lcm)
}

/// 每一天分到多少（§6.3–§6.5）。
public final class BudgetRuleCalendar {
    private final class Slice {
        var cents: [Int: Int] = [:]
        var baseCents = 0
        var carveCents = 0
        var firstCarveDay: BudgetCivilDay?
    }

    private struct RuleKey: Hashable {
        let id: Int
        let createdMs: Int
        let uuid: String
    }

    private let bases: [BudgetRule]
    private let specials: [BudgetRule]
    private var slices: [String: Slice] = [:]
    private var specialTotals: [RuleKey: Int] = [:]

    public init<S: Sequence>(_ rules: S) where S.Element == BudgetRule {
        let list = Array(rules)
        bases = list.filter { !$0.isDeleted && $0.isBase }
        specials = list.filter { !$0.isDeleted && !$0.isBase && $0.endDate != nil }
    }

    public var rules: [BudgetRule] { bases + specials }

    private static func key(_ rule: BudgetRule) -> RuleKey {
        RuleKey(id: rule.id, createdMs: rule.createdMs, uuid: rule.uuid)
    }

    /// 开始日 ≤ 这天的日常预算里，最后新建的那条（§6.4 接力）。
    public func baseOwner(_ day: BudgetCivilDay) -> BudgetRule? {
        var best: BudgetRule?
        for rule in bases where day >= rule.startDate {
            if best == nil || rule.outranks(best!) { best = rule }
        }
        return best
    }

    /// 覆盖这天的特别安排里，最后新建的那条（§6.5）。
    public func specialOwner(_ day: BudgetCivilDay) -> BudgetRule? {
        var best: BudgetRule?
        for rule in specials where rule.covers(day) {
            if best == nil || rule.outranks(best!) { best = rule }
        }
        return best
    }

    public func specialTotalYuan(_ rule: BudgetRule) -> Int {
        let key = Self.key(rule)
        if let cached = specialTotals[key] { return cached }
        let value = budgetSpecialTotalYuan(rule)
        specialTotals[key] = value
        return value
    }

    public func specialShareCents(_ rule: BudgetRule, _ day: BudgetCivilDay) -> Int {
        let count = rule.startDate.days(to: rule.endDate!) + 1
        let index = rule.startDate.days(to: day)
        return budgetEvenShare(specialTotalYuan(rule), count, index) * 100
    }

    public func dayInfo(_ day: BudgetCivilDay) -> BudgetDayInfo {
        let base = baseOwner(day)
        let special = specialOwner(day)
        let cents: Int
        if let base {
            cents = slice(base, day).cents[day.key] ?? 0
        } else if let special {
            cents = specialShareCents(special, day)
        } else {
            cents = 0
        }
        return BudgetDayInfo(day: day, budgetCents: cents, baseRule: base, specialRule: special)
    }

    /// base 在包含 day 的自然周期里：原份额、被「匀」拿走的钱、第一次「匀」的日子。
    func sliceTotals(_ base: BudgetRule, _ day: BudgetCivilDay) -> (baseCents: Int, carveCents: Int, firstCarveDay: BudgetCivilDay?) {
        let s = slice(base, day)
        return (s.baseCents, s.carveCents, s.firstCarveDay)
    }

    private func slice(_ base: BudgetRule, _ day: BudgetCivilDay) -> Slice {
        let period = budgetNaturalPeriod(base.unit, day)
        let cacheKey = "\(base.id):\(base.createdMs):\(base.uuid):\(period.start.key)"
        if let cached = slices[cacheKey] { return cached }
        let slice = Slice()
        var normal: [BudgetCivilDay] = []
        let baseKey = Self.key(base)
        for i in 0..<period.length {
            let d = period.start.adding(days: i)
            guard let owner = baseOwner(d), Self.key(owner) == baseKey else { continue }
            let share = budgetEvenShare(base.amountYuan, period.length, i) * 100
            if let special = specialOwner(d) {
                if special.isExtra {
                    slice.cents[d.key] = share + specialShareCents(special, d)
                } else {
                    let carve = specialShareCents(special, d)
                    slice.cents[d.key] = carve
                    slice.baseCents += share
                    slice.carveCents += carve
                    if slice.firstCarveDay == nil { slice.firstCarveDay = d }
                }
            } else {
                normal.append(d)
                slice.baseCents += share
                slice.cents[d.key] = share
            }
        }
        // 有「匀」时，其余日子平均分剩下的钱；没有时保持原份额（不重排零头）。
        if slice.firstCarveDay != nil, !normal.isEmpty {
            let pool = max((slice.baseCents - slice.carveCents) / 100, 0)
            for (i, d) in normal.enumerated() {
                slice.cents[d.key] = budgetEvenShare(pool, normal.count, i) * 100
            }
        }
        slices[cacheKey] = slice
        return slice
    }
}

/// 今天的额度：每天早上定一次，白天只做减法（§6.7）。
public struct BudgetTodayStatus: Equatable, Sendable {
    /// 今天的额度（分，已向下取整到元，≥ 0）。
    public let allowanceCents: Int
    public let spentTodayCents: Int
    /// 今天还能花 = 额度 − 今天已花；< 0 时界面写「今天多花了 ¥X」。
    public let leftTodayCents: Int
    /// 今天到月底，包含今天。
    public let remainingDays: Int
    public let plannedBeforeTodayCents: Int
    public let spentBeforeTodayCents: Int

    /// 比计划少花（> 0）或多花（< 0）了多少分。
    public var paceDeltaCents: Int { plannedBeforeTodayCents - spentBeforeTodayCents }
}

public struct BudgetMonthResult: Sendable {
    public let year: Int
    public let month: Int
    public let days: [BudgetDayInfo]
    /// 这个月每天预算之和（不含结余）。
    public let budgetCents: Int
    /// 从上个月带进来的结余（可为负）。
    public let carryInCents: Int
    public let spentCents: Int
    public let rolloverMode: BudgetRolloverMode
    /// 只有这个月包含今天时才有。
    public let today: BudgetTodayStatus?

    public var hasRules: Bool { days.contains { $0.covered } }
    public var effectiveCents: Int { budgetCents + carryInCents }
    /// 还能花（可为负；界面负数改写「X月超出 ¥Y」）。
    public var remainingCents: Int { effectiveCents - spentCents }

    /// 今天有规则覆盖时才有日度引导。
    public var todayCovered: Bool {
        guard let today else { return false }
        let index = days.count - today.remainingDays
        return index >= 0 && index < days.count && days[index].covered
    }
}

public enum BudgetRuleIssue: String, Sendable { case carveWithoutBase, carveExceedsBase }

public struct BudgetRuleValidation: Equatable, Sendable {
    public let issue: BudgetRuleIssue
    public let year: Int
    public let month: Int
}

public enum BudgetRuleEngine {
    /// spendByDay：yyyymmdd → 当天计入预算的支出（分）。调用方已按口径过滤
    /// （净额 > 0、计入预算、CNY、账本范围）；这里再只取有规则、且不晚于今天的日子。
    public static func resolveMonth(
        rules: [BudgetRule],
        rolloverChanges: [BudgetRolloverChange] = [],
        spendByDay: [Int: Int],
        year: Int,
        month: Int,
        today: BudgetCivilDay
    ) -> BudgetMonthResult {
        let calendar = BudgetRuleCalendar(rules)
        let changes = rolloverChanges.sorted {
            $0.monthIndex != $1.monthIndex ? $0.monthIndex < $1.monthIndex : $0.id < $1.id
        }
        func modeFor(_ index: Int) -> BudgetRolloverMode {
            var mode = BudgetRolloverMode.reset
            for change in changes {
                if change.monthIndex > index { break }
                mode = change.mode
            }
            return mode
        }
        let target = year * 12 + month - 1
        let starts = calendar.rules.map { $0.startDate.monthIndex } + changes.map(\.monthIndex)
        var carry = 0
        if let first = starts.min(), first < target {
            for index in first..<target {
                let days = self.days(calendar, index)
                let budget = days.reduce(0) { $0 + $1.budgetCents }
                let spent = self.spent(days, spendByDay, today)
                let result = budget + carry - spent
                switch modeFor(index + 1) {
                case .reset: carry = 0
                case .keepSavings: carry = max(result, 0)
                case .carryBoth: carry = result
                }
            }
        }
        if modeFor(target) == .reset { carry = 0 }

        let days = self.days(calendar, target)
        let budget = days.reduce(0) { $0 + $1.budgetCents }
        let spent = self.spent(days, spendByDay, today)
        let inMonth = today.year == year && today.month == month
        return BudgetMonthResult(
            year: year,
            month: month,
            days: days,
            budgetCents: budget,
            carryInCents: carry,
            spentCents: spent,
            rolloverMode: modeFor(target),
            today: inMonth ? todayStatus(days, spendByDay, today, budget + carry) : nil
        )
    }

    /// 任意日期区间的每天预算之和与已花（不带结余）。
    public static func resolveRange(
        rules: [BudgetRule],
        spendByDay: [Int: Int],
        start: BudgetCivilDay,
        end: BudgetCivilDay,
        today: BudgetCivilDay
    ) -> (budgetCents: Int, spentCents: Int) {
        let calendar = BudgetRuleCalendar(rules)
        var budget = 0
        var spent = 0
        var d = start
        while d <= end {
            let info = calendar.dayInfo(d)
            if info.covered {
                budget += info.budgetCents
                if d <= today { spent += spendByDay[d.key] ?? 0 }
            }
            d = d.adding(days: 1)
        }
        return (budget, spent)
    }

    private static func days(_ calendar: BudgetRuleCalendar, _ index: Int) -> [BudgetDayInfo] {
        let year = Int((Double(index) / 12).rounded(.down))
        let month = index - year * 12 + 1
        return (1...BudgetCivilDay.daysInMonth(year: year, month: month)).map {
            calendar.dayInfo(BudgetCivilDay(year: year, month: month, day: $0))
        }
    }

    private static func spent(_ days: [BudgetDayInfo], _ spendByDay: [Int: Int], _ today: BudgetCivilDay) -> Int {
        days.reduce(0) { total, day in
            guard day.covered, day.day <= today else { return total }
            return total + (spendByDay[day.day.key] ?? 0)
        }
    }

    private static func todayStatus(
        _ days: [BudgetDayInfo],
        _ spendByDay: [Int: Int],
        _ today: BudgetCivilDay,
        _ effectiveCents: Int
    ) -> BudgetTodayStatus {
        var plannedBefore = 0
        var spentBefore = 0
        var weight = 0
        var todayBudget = 0
        var spentToday = 0
        for day in days {
            let spend = day.covered ? spendByDay[day.day.key] ?? 0 : 0
            if day.day < today {
                plannedBefore += day.budgetCents
                spentBefore += spend
            } else {
                weight += day.budgetCents
                if day.day == today {
                    todayBudget = day.budgetCents
                    spentToday = spend
                }
            }
        }
        let remainingStart = effectiveCents - spentBefore
        var allowance = 0
        if remainingStart > 0, weight > 0, todayBudget > 0 {
            // 分最多 10^11 量级，乘积在 Int64 范围内。
            let raw = remainingStart.multipliedFullWidth(by: todayBudget)
            let quotient = weight.dividingFullWidth((raw.high, raw.low)).quotient
            allowance = budgetFloorYuanCents(quotient)
        }
        return BudgetTodayStatus(
            allowanceCents: allowance,
            spentTodayCents: spentToday,
            leftTodayCents: allowance - spentToday,
            remainingDays: BudgetCivilDay.daysInMonth(year: today.year, month: today.month) - today.day + 1,
            plannedBeforeTodayCents: plannedBefore,
            spentBeforeTodayCents: spentBefore
        )
    }

    /// 保存特别安排前的校验（§6.5）。candidate 编辑时带原 id，新建时 id 为 0。
    /// 返回 nil 表示可以保存。
    public static func validateSpecial(existing: [BudgetRule], candidate: BudgetRule) -> BudgetRuleValidation? {
        guard !candidate.isBase, let end = candidate.endDate, !candidate.isExtra else { return nil }
        let others = existing.filter { candidate.id == 0 || $0.id != candidate.id }
        let calendar = BudgetRuleCalendar(others + [candidate])
        var d = candidate.startDate
        while d <= end {
            defer { d = d.adding(days: 1) }
            guard let owner = calendar.specialOwner(d),
                  owner.id == candidate.id, owner.createdMs == candidate.createdMs,
                  owner.uuid == candidate.uuid else { continue }
            guard let base = calendar.baseOwner(d) else {
                return BudgetRuleValidation(issue: .carveWithoutBase, year: d.year, month: d.month)
            }
            let totals = calendar.sliceTotals(base, d)
            if totals.carveCents > totals.baseCents {
                let at = totals.firstCarveDay ?? d
                return BudgetRuleValidation(issue: .carveExceedsBase, year: at.year, month: at.month)
            }
        }
        return nil
    }
}
