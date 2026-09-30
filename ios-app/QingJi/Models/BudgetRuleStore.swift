import Foundation
import SwiftData
import QingJiCore

// 预算规则模型的 App 层（docs/08 §6）：SwiftData 表、读写、旧数据迁移。
// 计算全部交给 QingJiCore 的 BudgetRuleEngine，和安卓同一套算法。

/// 一条预算规则（安卓 budget_rules 同结构）。删除只写 deletedMs。
@Model
final class BudgetRuleRecord {
    var stableID: UUID = UUID()
    var bookID: UUID = UUID()
    var kindRaw: String = BudgetRuleKind.base.rawValue
    var name: String = ""
    var amountCents: Int = 0
    var unitRaw: String = BudgetRuleUnit.month.rawValue
    /// YYYY-MM-DD
    var startDate: String = ""
    var endDate: String? = nil
    var fundingRaw: String? = nil
    var colorIndex: Int = 0
    var createdMs: Int = 0
    var updatedMs: Int = 0
    var deletedMs: Int? = nil

    init(stableID: UUID = UUID(), bookID: UUID, kindRaw: String, name: String = "",
         amountCents: Int, unitRaw: String, startDate: String, endDate: String? = nil,
         fundingRaw: String? = nil, colorIndex: Int = 0, createdMs: Int, updatedMs: Int? = nil,
         deletedMs: Int? = nil) {
        self.stableID = stableID
        self.bookID = bookID
        self.kindRaw = kindRaw
        self.name = name
        self.amountCents = amountCents
        self.unitRaw = unitRaw
        self.startDate = startDate
        self.endDate = endDate
        self.fundingRaw = fundingRaw
        self.colorIndex = colorIndex
        self.createdMs = createdMs
        self.updatedMs = updatedMs ?? createdMs
        self.deletedMs = deletedMs
    }
}

/// 月底结余从哪个月起用哪种方式（安卓 budget_rollover_changes）。
@Model
final class BudgetRolloverChangeRecord {
    var stableID: UUID = UUID()
    var bookID: UUID = UUID()
    /// YYYY-MM
    var effectiveMonth: String = ""
    var modeRaw: String = BudgetRolloverMode.reset.rawValue
    var createdMs: Int = 0
    var updatedMs: Int = 0

    init(stableID: UUID = UUID(), bookID: UUID, effectiveMonth: String, modeRaw: String,
         createdMs: Int, updatedMs: Int? = nil) {
        self.stableID = stableID
        self.bookID = bookID
        self.effectiveMonth = effectiveMonth
        self.modeRaw = modeRaw
        self.createdMs = createdMs
        self.updatedMs = updatedMs ?? createdMs
    }
}

/// 某个账本某个月的预算结果（主页卡、小组件、统计环、记账页提示都从这里拿）。
struct BudgetRuleSnapshot {
    let bookID: UUID?
    let month: BudgetMonthResult
    let today: BudgetCivilDay
    let spendByDay: [Int: Int]
    let excludedForeignCount: Int

    var hasBudget: Bool { month.hasRules }

    /// 旧消费者用的形状（和安卓 BudgetRuleSnapshot.status 同口径）。没有规则时为 nil。
    var status: BudgetStatus? {
        guard hasBudget else { return nil }
        let todayStatus = month.today
        return BudgetStatus(
            monthlyBudget: BudgetRuleStore.decimal(month.effectiveCents),
            spentThisMonth: BudgetRuleStore.decimal(month.spentCents),
            spentToday: BudgetRuleStore.decimal(todayStatus?.spentTodayCents ?? 0),
            remaining: BudgetRuleStore.decimal(month.remainingCents),
            todayAllowance: BudgetRuleStore.decimal(todayStatus?.leftTodayCents ?? 0),
            isOverBudget: month.remainingCents < 0
        )
    }

    /// 今天有规则管时才画「今日可用」。
    var hasDailyGuidance: Bool { month.todayCovered }

    /// 实际总额（含结转）。没有规则时为 nil。
    var plannedAmount: Decimal? { hasBudget ? BudgetRuleStore.decimal(month.effectiveCents) : nil }
}

enum BudgetRuleSaveError: LocalizedError {
    case invalidAmount
    case missingDates
    case validation(BudgetRuleValidation)

    var errorDescription: String? {
        switch self {
        case .invalidAmount: return "填一个大于 0 的整数金额"
        case .missingDates: return "在日历上点一下开始和结束的日子"
        case .validation(let v): return budgetRuleValidationText(v)
        }
    }
}

enum BudgetRuleStore {
    static let colorCount = 5

    static func decimal(_ cents: Int) -> Decimal { Decimal(cents) / Decimal(100) }

    static func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    // MARK: 账本范围

    /// 预算页、主页用的账本：nil = 总账本（规则挂在默认账本上，支出汇总所有计入总账的账本）。
    static func ruleBookID(selectedBookID: UUID?, books: [Book]) -> UUID? {
        if let selectedBookID { return selectedBookID }
        return (books.first(where: \.isDefault) ?? books.first)?.stableID
    }

    // MARK: 读

    static func liveRecords(_ all: [BudgetRuleRecord], bookID: UUID) -> [BudgetRuleRecord] {
        all.filter { $0.bookID == bookID && $0.deletedMs == nil }
            .sorted { $0.createdMs != $1.createdMs ? $0.createdMs < $1.createdMs : $0.stableID.uuidString < $1.stableID.uuidString }
    }

    static func records(in context: ModelContext, bookID: UUID) -> [BudgetRuleRecord] {
        liveRecords((try? context.fetch(FetchDescriptor<BudgetRuleRecord>())) ?? [], bookID: bookID)
    }

    /// 转成引擎用的规则。id 按新建先后编号（1 起），uuid 用 stableID。
    static func coreRules(_ records: [BudgetRuleRecord]) -> [BudgetRule] {
        records.enumerated().compactMap { index, record in core(record, id: index + 1) }
    }

    static func core(_ record: BudgetRuleRecord, id: Int) -> BudgetRule? {
        guard let kind = BudgetRuleKind(rawValue: record.kindRaw),
              let unit = BudgetRuleUnit(rawValue: record.unitRaw),
              let start = BudgetCivilDay(text: record.startDate) else { return nil }
        let end = record.endDate.flatMap { BudgetCivilDay(text: $0) }
        if kind == .special && end == nil { return nil }
        return BudgetRule(
            id: id,
            uuid: record.stableID.uuidString.lowercased(),
            bookID: record.bookID.uuidString,
            kind: kind,
            name: record.name,
            amountCents: record.amountCents,
            unit: unit,
            startDate: start,
            endDate: kind == .special ? end : nil,
            funding: kind == .special ? (record.fundingRaw.flatMap(BudgetFunding.init(rawValue:)) ?? .carve) : nil,
            colorIndex: record.colorIndex,
            createdMs: record.createdMs,
            updatedMs: record.updatedMs,
            deletedMs: record.deletedMs
        )
    }

    /// 找回引擎规则对应的记录。
    static func record(for rule: BudgetRule, in records: [BudgetRuleRecord]) -> BudgetRuleRecord? {
        records.first { $0.stableID.uuidString.lowercased() == rule.uuid }
    }

    static func coreRollovers(_ all: [BudgetRolloverChangeRecord], bookID: UUID) -> [BudgetRolloverChange] {
        let mine = all.filter { $0.bookID == bookID }
            .sorted { $0.createdMs != $1.createdMs ? $0.createdMs < $1.createdMs : $0.stableID.uuidString < $1.stableID.uuidString }
        return mine.enumerated().compactMap { index, record in
            let parts = record.effectiveMonth.split(separator: "-")
            guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m),
                  let mode = BudgetRolloverMode(rawValue: record.modeRaw) else { return nil }
            return BudgetRolloverChange(id: index + 1, bookID: bookID.uuidString, year: y, month: m, mode: mode)
        }
    }

    static func rolloverChanges(in context: ModelContext, bookID: UUID) -> [BudgetRolloverChange] {
        coreRollovers((try? context.fetch(FetchDescriptor<BudgetRolloverChangeRecord>())) ?? [], bookID: bookID)
    }

    /// 某个月用哪种结余方式。
    static func rolloverMode(_ changes: [BudgetRolloverChange], year: Int, month: Int) -> BudgetRolloverMode {
        let target = year * 12 + month - 1
        var mode = BudgetRolloverMode.reset
        for change in changes.sorted(by: {
            $0.monthIndex != $1.monthIndex ? $0.monthIndex < $1.monthIndex : $0.id < $1.id
        }) {
            if change.monthIndex > target { break }
            mode = change.mode
        }
        return mode
    }

    static func rolloverMode(in context: ModelContext, bookID: UUID, year: Int, month: Int) -> BudgetRolloverMode {
        rolloverMode(rolloverChanges(in: context, bookID: bookID), year: year, month: month)
    }

    /// 计入预算的支出（已按账本范围筛过的交易）。
    static func spendRows(_ transactions: [MoneyTransaction], calendar: Calendar = .current) -> [BudgetSpendRow] {
        transactions.map { t in
            BudgetSpendRow(
                id: t.stableID,
                isExpense: t.kindRaw == TransactionKind.expense.rawValue,
                amountCents: MoneyNormalization.cents(t.amount),
                currencyCode: t.currencyCode,
                attributionDay: BudgetCivilDay(t.date, calendar: calendar),
                createdAt: t.createdAt,
                refundOfID: t.refundOfID,
                isExcluded: t.isExcluded
            )
        }
    }

    /// 某个账本某个月。selectedBookID 为 nil 表示总账本。
    /// 视图用 @Query 拿到的数组直接传进来，规则一改就会重算。
    static func snapshot(
        rules ruleRecords: [BudgetRuleRecord],
        rollovers rolloverRecords: [BudgetRolloverChangeRecord],
        selectedBookID: UUID?,
        books: [Book],
        transactions: [MoneyTransaction],
        year: Int,
        month: Int,
        now: Date = AppClock.now,
        calendar: Calendar = .current
    ) -> BudgetRuleSnapshot {
        let today = BudgetCivilDay(now, calendar: calendar)
        guard let bookID = ruleBookID(selectedBookID: selectedBookID, books: books) else {
            return BudgetRuleSnapshot(
                bookID: nil,
                month: BudgetRuleEngine.resolveMonth(rules: [], spendByDay: [:], year: year, month: month, today: today),
                today: today, spendByDay: [:], excludedForeignCount: 0)
        }
        let rules = coreRules(liveRecords(ruleRecords, bookID: bookID))
        var spend: [Int: Int] = [:]
        var foreign: [Int: Int] = [:]
        if !rules.isEmpty {
            let scoped = LedgerScope.filter(transactions, selectedBookID: selectedBookID)
            (spend, foreign) = budgetSpendByDay(spendRows(scoped, calendar: calendar), today: today,
                                                knowledgeCutoff: Date())
        }
        let result = BudgetRuleEngine.resolveMonth(
            rules: rules,
            rolloverChanges: coreRollovers(rolloverRecords, bookID: bookID),
            spendByDay: spend,
            year: year,
            month: month,
            today: today
        )
        return BudgetRuleSnapshot(bookID: bookID, month: result, today: today, spendByDay: spend,
                                  excludedForeignCount: budgetForeignCount(foreign, month: result, today: today))
    }

    /// 便捷版：自己从 context 取数据。
    static func snapshot(in context: ModelContext, selectedBookID: UUID?, year: Int, month: Int,
                         now: Date = AppClock.now) -> BudgetRuleSnapshot {
        snapshot(
            rules: (try? context.fetch(FetchDescriptor<BudgetRuleRecord>())) ?? [],
            rollovers: (try? context.fetch(FetchDescriptor<BudgetRolloverChangeRecord>())) ?? [],
            selectedBookID: selectedBookID,
            books: (try? context.fetch(FetchDescriptor<Book>())) ?? [],
            transactions: (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? [],
            year: year, month: month, now: now)
    }

    // MARK: 写

    static func dateText(_ day: BudgetCivilDay) -> String { day.text }

    private static func nextColor(in context: ModelContext, bookID: UUID) -> Int {
        let all = (try? context.fetch(FetchDescriptor<BudgetRuleRecord>())) ?? []
        let specials = all.filter { $0.bookID == bookID && $0.kindRaw == BudgetRuleKind.special.rawValue }.count
        return specials % colorCount
    }

    /// 新建或修改一条规则。日常预算一律从新建那个月 1 号起（改的时候不动开始日）。
    @discardableResult
    static func save(
        in context: ModelContext,
        editing: BudgetRuleRecord?,
        bookID: UUID,
        kind: BudgetRuleKind,
        name: String,
        amountYuan: Int,
        unit: BudgetRuleUnit,
        start: BudgetCivilDay?,
        end: BudgetCivilDay?,
        funding: BudgetFunding,
        now: Date = AppClock.now
    ) throws -> BudgetRuleRecord {
        guard amountYuan > 0 else { throw BudgetRuleSaveError.invalidAmount }
        let today = BudgetCivilDay(now)
        let startDay: BudgetCivilDay
        let endDay: BudgetCivilDay?
        if kind == .base {
            if let editing, editing.kindRaw == BudgetRuleKind.base.rawValue,
               let existing = BudgetCivilDay(text: editing.startDate) {
                startDay = existing
            } else {
                startDay = BudgetCivilDay(year: today.year, month: today.month, day: 1)
            }
            endDay = nil
        } else {
            guard let start, let end else { throw BudgetRuleSaveError.missingDates }
            startDay = min(start, end)
            endDay = max(start, end)
        }
        let createdMs = editing?.createdMs ?? nowMs()
        let others = records(in: context, bookID: bookID).filter { $0.stableID != editing?.stableID }
        if kind == .special && funding == .carve {
            let existing = coreRules(others)
            let candidate = BudgetRule(
                id: 0,
                uuid: (editing?.stableID ?? UUID()).uuidString.lowercased(),
                bookID: bookID.uuidString, kind: .special, name: name,
                amountCents: amountYuan * 100, unit: unit, startDate: startDay, endDate: endDay,
                funding: .carve, createdMs: createdMs)
            if let issue = BudgetRuleEngine.validateSpecial(existing: existing, candidate: candidate) {
                throw BudgetRuleSaveError.validation(issue)
            }
        }
        let ms = nowMs()
        let record: BudgetRuleRecord
        if let editing {
            record = editing
        } else {
            record = BudgetRuleRecord(bookID: bookID, kindRaw: kind.rawValue, amountCents: 0,
                                      unitRaw: unit.rawValue, startDate: startDay.text,
                                      colorIndex: kind == .base ? 0 : nextColor(in: context, bookID: bookID),
                                      createdMs: createdMs)
            context.insert(record)
        }
        if editing != nil && editing!.kindRaw != kind.rawValue {
            record.colorIndex = kind == .base ? 0 : nextColor(in: context, bookID: bookID)
        }
        record.bookID = bookID
        record.kindRaw = kind.rawValue
        record.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        record.amountCents = amountYuan * 100
        record.unitRaw = unit.rawValue
        record.startDate = startDay.text
        record.endDate = endDay?.text
        record.fundingRaw = kind == .special ? funding.rawValue : nil
        record.updatedMs = ms
        try context.save()
        return record
    }

    static func delete(_ record: BudgetRuleRecord, in context: ModelContext) throws {
        let ms = nowMs()
        record.deletedMs = ms
        record.updatedMs = ms
        try context.save()
    }

    /// 从这个月起换一种结余方式（同一个月改多次只留一条）。
    static func setRolloverMode(_ mode: BudgetRolloverMode, bookID: UUID, in context: ModelContext,
                                now: Date = AppClock.now) throws {
        let today = BudgetCivilDay(now)
        if rolloverMode(in: context, bookID: bookID, year: today.year, month: today.month) == mode { return }
        let monthText = String(format: "%04d-%02d", today.year, today.month)
        let all = (try? context.fetch(FetchDescriptor<BudgetRolloverChangeRecord>())) ?? []
        let ms = nowMs()
        if let existing = all.first(where: { $0.bookID == bookID && $0.effectiveMonth == monthText }) {
            existing.modeRaw = mode.rawValue
            existing.updatedMs = ms
        } else {
            context.insert(BudgetRolloverChangeRecord(bookID: bookID, effectiveMonth: monthText,
                                                      modeRaw: mode.rawValue, createdMs: ms))
        }
        try context.save()
    }

    /// 删账本时一起软删它的规则。
    static func deleteRules(forBook bookID: UUID, in context: ModelContext) {
        let ms = nowMs()
        for record in records(in: context, bookID: bookID) {
            record.deletedMs = ms
            record.updatedMs = ms
        }
    }

    // MARK: 旧数据迁移（§6.12，和安卓 _migrateBudgetRulesV50 同一规则）

    private static let migrationKey = "budgetRules.migratedV1"

    /// 每个还没有日常预算的账本迁一条：先取生效的 V2 主计划（按月/按周），
    /// 没有才取本账本的旧每月预算，再没有才取「全部账本」那条。旧表不删不改。
    /// 只跑一次（恢复备份后由导入流程自己带规则）。
    static func migrateIfNeeded(in context: ModelContext, now: Date = AppClock.now,
                                defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        migrate(in: context, now: now)
        defaults.set(true, forKey: migrationKey)
    }

    static func migrate(in context: ModelContext, now: Date = AppClock.now, save: Bool = true) {
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let plans = ((try? context.fetch(FetchDescriptor<BudgetPlanRecord>())) ?? []).filter {
            $0.roleRaw == "primary" && $0.statusRaw == BudgetPlanStatusV2.active.rawValue &&
                ($0.cadenceRaw == BudgetPlanCadenceV2.monthly.rawValue || $0.cadenceRaw == BudgetPlanCadenceV2.weekly.rawValue)
        }
        let revisions = (try? context.fetch(FetchDescriptor<BudgetPlanRevisionRecord>())) ?? []
        let legacy = ((try? context.fetch(FetchDescriptor<Budget>())) ?? []).filter {
            $0.isActive && $0.categoryKey == nil && $0.cycleRaw == BudgetCycle.monthly.rawValue
        }
        let today = BudgetCivilDay(now)
        let ms = nowMs()
        var inserted = false
        for book in books {
            let hasBase = records(in: context, bookID: book.stableID).contains { $0.kindRaw == BudgetRuleKind.base.rawValue }
            if hasBase { continue }
            guard let source = planSource(book.stableID, plans: plans, revisions: revisions, today: today)
                    ?? legacySource(book.stableID, budgets: legacy, now: now) else { continue }
            context.insert(BudgetRuleRecord(bookID: book.stableID, kindRaw: BudgetRuleKind.base.rawValue,
                                            amountCents: source.cents, unitRaw: source.unit.rawValue,
                                            startDate: source.start.text, createdMs: ms))
            inserted = true
        }
        if inserted && save { try? context.save() }
    }

    /// 金额取整到元；≤ 0 视为没有预算。
    private static func roundCents(_ cents: Int) -> Int? {
        let rounded = Int((Double(cents) / 100).rounded()) * 100
        return rounded > 0 ? rounded : nil
    }

    private static func planSource(_ bookID: UUID, plans: [BudgetPlanRecord], revisions: [BudgetPlanRevisionRecord],
                                   today: BudgetCivilDay) -> (cents: Int, unit: BudgetRuleUnit, start: BudgetCivilDay)? {
        let mine = plans.filter { $0.bookID == bookID }.sorted { $0.anchorStart < $1.anchorStart }
        guard !mine.isEmpty else { return nil }
        let covering = mine.filter { plan in
            let start = BudgetCivilDay(plan.anchorStart)
            let end = plan.endInclusive.map { BudgetCivilDay($0) }
            return start <= today && (end == nil || end! >= today)
        }
        let plan = covering.last ?? mine.last!
        let revs = revisions.filter { $0.planID == plan.stableID }.sorted { $0.effectiveCycleStart < $1.effectiveCycleStart }
        guard !revs.isEmpty else { return nil }
        let started = revs.filter { BudgetCivilDay($0.effectiveCycleStart) <= today }
        let revision = started.last ?? revs.first!
        guard let cents = roundCents(revision.amountCents) else { return nil }
        let anchor = BudgetCivilDay(plan.anchorStart)
        return (cents, plan.cadenceRaw == BudgetPlanCadenceV2.weekly.rawValue ? .week : .month,
                BudgetCivilDay(year: anchor.year, month: anchor.month, day: 1))
    }

    private static func legacySource(_ bookID: UUID, budgets: [Budget],
                                     now: Date) -> (cents: Int, unit: BudgetRuleUnit, start: BudgetCivilDay)? {
        let candidates = budgets.filter { budget in
            (budget.bookID == nil || budget.bookID == bookID) && (budget.periodStart ?? budget.createdAt) <= now
        }.sorted { a, b in
            let rankA = a.bookID == nil ? 0 : 1
            let rankB = b.bookID == nil ? 0 : 1
            if rankA != rankB { return rankA < rankB }
            return (a.periodStart ?? a.createdAt) < (b.periodStart ?? b.createdAt)
        }
        guard let budget = candidates.last,
              let cents = roundCents(MoneyNormalization.cents(budget.amount)) else { return nil }
        let start = BudgetCivilDay(budget.periodStart ?? budget.createdAt)
        return (cents, .month, BudgetCivilDay(year: start.year, month: start.month, day: 1))
    }
}
