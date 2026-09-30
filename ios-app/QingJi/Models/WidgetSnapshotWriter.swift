import Foundation
import SwiftData
import WidgetKit
import QingJiCore

/// 主 App 侧的小组件快照写入器。只写 App Group 文件，不让 Widget 扩展
/// 直接打开 SwiftData，避免扩展进程和主进程同时迁移数据库。
@MainActor
enum WidgetSnapshotWriter {
    static let appGroupID = "group.com.qingji.app"
    private static let fileName = "widget-snapshot.json"

    static func write(context: ModelContext, now: Date = AppClock.now) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return }

        let transactions = (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? []
        let books = (try? context.fetch(FetchDescriptor<Book>(sortBy: [
            SortDescriptor(\Book.sortOrder)
        ]))) ?? []
        let selectedBook = books.first(where: { $0.isDefault }) ?? books.first
        let scoped = LedgerScope.filter(transactions, selectedBookID: selectedBook?.stableID)
        let records = scoped.map(\.record)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let year = components.year ?? 2000
        let month = components.month ?? 1
        let day = components.day ?? 1
        let summary = StatisticsEngine.monthlySummary(
            of: records,
            year: year,
            month: month,
            calendar: calendar
        )
        let todayExpense = summary.dailyTotals.first(where: { $0.day == day })?.expense ?? 0
        // 07 案例 74：同期平均和统计页进度卡同一个引擎、同一个门槛（至少 2 个历史月）。
        let pace = MonthlyPaceEngine.project(records: records, year: year, month: month,
                                             now: now, calendar: calendar)
        let privacy = UserDefaults.standard.bool(forKey: "qingji.widgetPrivacyMode")
        let currency = records.first?.currencyCode ?? "CNY"
        let money: (Decimal) -> String = { value in
            privacy ? "••••" : MoneyFormat.string(value, currencyCode: currency)
        }

        // 预算规则模型（docs/08 §6.10）：和主页总账本同一个入口、同一个数。
        let budgetSnapshot = BudgetRuleStore.snapshot(
            rules: (try? context.fetch(FetchDescriptor<BudgetRuleRecord>())) ?? [],
            rollovers: (try? context.fetch(FetchDescriptor<BudgetRolloverChangeRecord>())) ?? [],
            selectedBookID: nil,
            books: books,
            transactions: transactions,
            year: year,
            month: month,
            now: now,
            calendar: calendar
        )
        let budget = budgetSnapshot.plannedAmount
        let budgetStatus = budgetSnapshot.status
        let budgetRemaining = budgetStatus?.remaining ?? 0
        let budgetProgress: Int = {
            guard let budget, budget > 0 else { return 0 }
            let ratio = NSDecimalNumber(decimal: budgetStatus?.spentThisMonth ?? summary.totalExpense).doubleValue /
                max(NSDecimalNumber(decimal: budget).doubleValue, 0.01)
            return Int((min(max(ratio, 0), 1) * 100).rounded())
        }()
        let budgetText = budget == nil
            ? money(summary.totalExpense)
            : (budgetRemaining >= 0 ? money(budgetRemaining) : "超 \(money(-budgetRemaining))")
        let budgetHint = budget == nil
            ? "未设置预算 · 已展示本月支出"
            : "已用 \(money(budgetStatus?.spentThisMonth ?? summary.totalExpense)) / \(money(budget ?? 0))"

        let categoryTotals = summary.expenseByCategory.prefix(3).map { item in
            let ratio = summary.totalExpense > 0
                ? NSDecimalNumber(decimal: item.total).doubleValue /
                    NSDecimalNumber(decimal: summary.totalExpense).doubleValue
                : 0
            let percent = Int((min(max(ratio, 0), 1) * 100).rounded())
            return WidgetCategorySnapshot(
                id: item.name,
                name: item.name,
                amountText: money(item.total),
                percentText: "\(percent)%",
                progress: percent,
                count: item.count
            )
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        let snapshot = WidgetSnapshot(
            generatedAtMs: Int64(now.timeIntervalSince1970 * 1000),
            bookName: selectedBook?.name ?? "肥喵记账",
            dateText: formatter.string(from: now),
            todayExpenseText: money(todayExpense),
            monthExpenseText: money(summary.totalExpense),
            monthIncomeText: money(summary.totalIncome),
            balanceText: money(summary.balance),
            budgetTitle: budget == nil ? "本月支出" : "预算剩余",
            budgetText: budgetText,
            budgetHint: budgetHint,
            budgetProgress: budgetProgress,
            paceCaption: "截至\(formatter.string(from: now))",
            paceAverageText: pace.hasAverage ? money(pace.average) : "--",
            privacyMode: privacy,
            categories: categoryTotals
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: container.appendingPathComponent(fileName), options: Data.WritingOptions.atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
