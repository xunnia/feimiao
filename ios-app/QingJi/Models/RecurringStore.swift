import Foundation
import SwiftData
import QingJiCore

/// 定时记账的写入和到期物化边界。
///
/// 规则与生成交易分开保存；`RecurringOccurrence` 以 rule + 日期保证重复打开
/// App 时不会重复落账。失效账户不会被静默替换，规则会停在待修复状态。
enum RecurringStore {
    enum Error: LocalizedError {
        case invalidAmount
        case accountRequired
        case invalidTransfer
        case accountUnavailable
        case targetUnavailable
        case invalidDateRange

        var errorDescription: String? {
            switch self {
            case .invalidAmount: return "金额必须大于 0。"
            case .accountRequired: return "定时记账必须选择账户。"
            case .invalidTransfer: return "转账需要选择两个不同的账户。"
            case .accountUnavailable: return "付款账户不存在、已归档或币种不一致。"
            case .targetUnavailable: return "转入账户不存在、已归档或币种不一致。"
            case .invalidDateRange: return "结束日期不能早于开始日期。"
            }
        }
    }

    static func rules(in context: ModelContext) throws -> [RecurringRule] {
        try context.fetch(FetchDescriptor<RecurringRule>(sortBy: [
            SortDescriptor(\RecurringRule.nextDueDate),
            SortDescriptor(\RecurringRule.createdAt)
        ]))
    }

    @discardableResult
    static func create(
        in context: ModelContext,
        kind: TransactionKind,
        amount: Decimal,
        categoryKey: String? = nil,
        account: Account,
        toAccount: Account? = nil,
        book: Book?,
        note: String = "",
        period: RecurringPeriod,
        startDate: Date,
        nextDueDate: Date? = nil,
        endDate: Date? = nil,
        totalCount: Int? = nil
    ) throws -> RecurringRule {
        try validate(
            amount: amount,
            kind: kind,
            account: account,
            toAccount: toAccount,
            startDate: startDate,
            nextDueDate: nextDueDate ?? startDate,
            endDate: endDate
        )
        let rule = RecurringRule(
            amount: amount,
            kind: kind,
            bookID: book?.stableID,
            categoryKey: kind == .transfer ? nil : categoryKey,
            accountID: account.stableID,
            toAccountID: kind == .transfer ? toAccount?.stableID : nil,
            note: note,
            period: period,
            startDate: startDate,
            firstDueDate: nextDueDate,
            endDate: endDate,
            totalCount: totalCount
        )
        context.insert(rule)
        try context.save()
        _ = try materializeDue(in: context)
        return rule
    }

    static func update(
        _ rule: RecurringRule,
        in context: ModelContext,
        kind: TransactionKind,
        amount: Decimal,
        categoryKey: String? = nil,
        account: Account,
        toAccount: Account? = nil,
        book: Book?,
        note: String,
        period: RecurringPeriod,
        nextDueDate: Date,
        startDate: Date,
        endDate: Date? = nil,
        totalCount: Int? = nil
    ) throws {
        try validate(
            amount: amount,
            kind: kind,
            account: account,
            toAccount: toAccount,
            startDate: startDate,
            nextDueDate: nextDueDate,
            endDate: endDate
        )
        rule.kind = kind
        rule.amount = amount
        rule.categoryKey = kind == .transfer ? nil : categoryKey
        rule.accountID = account.stableID
        rule.toAccountID = kind == .transfer ? toAccount?.stableID : nil
        rule.bookID = book?.stableID
        rule.note = note
        rule.period = period
        rule.startDate = startDate
        rule.nextDueDate = nextDueDate
        rule.endDate = endDate
        rule.totalCount = totalCount
        rule.anchorDay = Calendar.current.component(.day, from: startDate)
        rule.updatedAt = Date()
        try context.save()
    }

    static func setEnabled(_ rule: RecurringRule, enabled: Bool, in context: ModelContext) throws {
        rule.isEnabled = enabled
        rule.updatedAt = Date()
        try context.save()
        if enabled { _ = try materializeDue(in: context) }
    }

    static func delete(_ rule: RecurringRule, in context: ModelContext) throws {
        let occurrences = try context.fetch(FetchDescriptor<RecurringOccurrence>())
            .filter { $0.ruleID == rule.stableID }
        occurrences.forEach(context.delete)
        context.delete(rule)
        try context.save()
    }

    /// 将所有已到期规则补记到今天。最多补 400 次，避免异常历史规则阻塞启动。
    @discardableResult
    static func materializeDue(
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Int {
        let rules = try rules(in: context)
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let books = try context.fetch(FetchDescriptor<Book>())
        let categories = try context.fetch(FetchDescriptor<TxCategory>())
        let occurrences = try context.fetch(FetchDescriptor<RecurringOccurrence>())
        let cutoff = endOfDay(now, calendar: calendar)
        var createdCount = 0
        var changed = false

        for rule in rules where rule.isEnabled {
            guard let accountID = rule.accountID,
                  let account = accounts.first(where: {
                      $0.stableID == accountID && isAvailable($0)
                  }) else {
                continue
            }
            let target = rule.toAccountID.flatMap { id in
                accounts.first(where: { $0.stableID == id && isAvailable($0) })
            }
            if rule.kind == .transfer {
                guard let target,
                      target.stableID != account.stableID,
                      target.currencyCode == account.currencyCode else {
                    continue
                }
            }
            let book = rule.bookID.flatMap { id in books.first(where: { $0.stableID == id }) }
            let category = rule.kind == .transfer
                ? nil
                : rule.categoryKey.flatMap { key in
                    categories.first(where: { $0.key == key && $0.kind == rule.kind && !$0.isArchived })
                }
            var due = rule.nextDueDate
            var generated = rule.generatedCount
            var guardCount = 0

            while due <= cutoff && guardCount < 400 {
                if let totalCount = rule.totalCount,
                   totalCount > 0,
                   generated >= totalCount {
                    break
                }
                if let endDate = rule.endDate,
                   due > endOfDay(endDate, calendar: calendar) {
                    break
                }

                let exists = occurrences.contains {
                    $0.ruleID == rule.stableID &&
                    calendar.isDate($0.dueDate, equalTo: due, toGranularity: .day)
                }
                if !exists {
                    let transaction = MoneyTransaction(
                        amount: rule.amount,
                        kind: rule.kind,
                        date: due,
                        note: rule.note.isEmpty ? "周期记账" : rule.note,
                        currencyCode: account.currencyCode,
                        category: category,
                        account: account,
                        toAccount: rule.kind == .transfer ? target : nil,
                        book: book,
                        timePrecision: .dateOnly,
                        settledAt: due,
                        settlementQuality: .legacyAssumed,
                        settlementAccountID: account.stableID,
                        settlementAccountQuality: .legacyAssumed,
                        eventType: .defaultFor(rule.kind),
                        recurringRuleID: rule.stableID
                    )
                    context.insert(transaction)
                    context.insert(RecurringOccurrence(
                        ruleID: rule.stableID,
                        dueDate: due,
                        transactionID: transaction.stableID
                    ))
                    createdCount += 1
                }
                generated += 1
                guardCount += 1
                due = rule.period.advance(
                    due,
                    anchorDay: rule.anchorDay > 0 ? rule.anchorDay : nil,
                    calendar: calendar
                )
            }

            if guardCount > 0 {
                rule.nextDueDate = due
                rule.generatedCount = generated
                rule.updatedAt = Date()
                changed = true
            }
            if let endDate = rule.endDate,
               rule.nextDueDate > endOfDay(endDate, calendar: calendar) {
                rule.isEnabled = false
                changed = true
            }
        }

        if changed { try context.save() }
        return createdCount
    }

    private static func validate(
        amount: Decimal,
        kind: TransactionKind,
        account: Account?,
        toAccount: Account?,
        startDate: Date,
        nextDueDate: Date,
        endDate: Date?
    ) throws {
        guard amount > 0 else { throw Error.invalidAmount }
        guard let account else { throw Error.accountRequired }
        guard isAvailable(account) else { throw Error.accountUnavailable }
        if kind == .transfer {
            guard let toAccount,
                  toAccount.stableID != account.stableID,
                  isAvailable(toAccount),
                  toAccount.currencyCode == account.currencyCode else {
                throw Error.invalidTransfer
            }
        }
        let calendar = Calendar.current
        if calendar.startOfDay(for: nextDueDate) < calendar.startOfDay(for: startDate) {
            throw Error.invalidDateRange
        }
        if let endDate, endOfDay(endDate, calendar: calendar) < calendar.startOfDay(for: nextDueDate) {
            throw Error.invalidDateRange
        }
    }

    private static func isAvailable(_ account: Account) -> Bool {
        !account.isDeleted && account.status == .active && !account.currencyCode.isEmpty
    }

    private static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, nanosecond: -1), to: start) ?? date
    }
}
