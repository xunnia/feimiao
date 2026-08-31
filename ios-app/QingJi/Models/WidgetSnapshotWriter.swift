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
        let privacy = UserDefaults.standard.bool(forKey: "qingji.widgetPrivacyMode")
        let currency = records.first?.currencyCode ?? "CNY"
        let money: (Decimal) -> String = { value in
            privacy ? "••••" : MoneyFormat.string(value, currencyCode: currency)
        }

        let budgetPlansV2 = (try? context.fetch(FetchDescriptor<BudgetPlanRecord>())) ?? []
        let budgetRevisionsV2 = (try? context.fetch(FetchDescriptor<BudgetPlanRevisionRecord>())) ?? []
        let budgetOverridesV2 = (try? context.fetch(FetchDescriptor<BudgetCycleOverrideRecord>())) ?? []
        let v2Status: BudgetStatus? = {
            guard let bookID = selectedBook?.stableID else { return nil }
            BudgetStore.currentStatusV2(
                plans: budgetPlansV2.map(\.core),
                revisions: budgetRevisionsV2.map(\.core),
                overrides: budgetOverridesV2.map(\.core),
                bookID: bookID,
                records: records,
                referenceDate: now,
                knowledgeCutoff: now,
                calendar: calendar
            )
        }()
        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        let legacyBudget = BudgetStore.effectiveTotalBudget(
            from: budgets,
            selectedBookID: selectedBook?.stableID,
            fallbackBookID: selectedBook?.stableID
        )
        let budgetStatus = v2Status ?? legacyBudget.map {
            BudgetStore.status(
                for: $0,
                transactions: scoped,
                referenceDate: now,
                calendar: calendar
            )
        }
        let budgetAmount = v2Status?.monthlyBudget ?? legacyBudget?.amount
        let hasBudget = budgetAmount.map { $0 > 0 } ?? false
        let budgetRemaining = budgetStatus?.remaining ?? 0
        let budgetProgress: Int = {
            guard let budgetAmount, budgetAmount > 0 else { return 0 }
            let ratio = NSDecimalNumber(decimal: budgetStatus?.spentThisMonth ?? summary.totalExpense).doubleValue /
                max(NSDecimalNumber(decimal: budgetAmount).doubleValue, 0.01)
            return Int((min(max(ratio, 0), 1) * 100).rounded())
        }()
        let budgetText = !hasBudget
            ? money(summary.totalExpense)
            : (budgetRemaining >= 0 ? money(budgetRemaining) : "超 \(money(-budgetRemaining))")
        let budgetHint = !hasBudget
            ? "未设置预算 · 已展示本月支出"
            : "已用 \(money(budgetStatus?.spentThisMonth ?? summary.totalExpense)) / \(money(budgetAmount ?? 0))"

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
            budgetTitle: hasBudget ? "预算剩余" : "本月支出",
            budgetText: budgetText,
            budgetHint: budgetHint,
            budgetProgress: budgetProgress,
            paceCaption: "截至\(formatter.string(from: now))",
            paceAverageText: "--",
            privacyMode: privacy,
            categories: categoryTotals
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: container.appendingPathComponent(fileName), options: Data.WritingOptions.atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
