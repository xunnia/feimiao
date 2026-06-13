import UIKit
import SwiftUI
import SwiftData
import Charts
import QingJiCore

/// 月度统计：收支卡片 + 分类占比扇形图 + 每日支出柱状图 + 分类排行。
struct MonthlyStatsView: View {
    /// 复用 AppRouter 定义的枚举；本地 typealias 保持代码可读性。
    private typealias Scope = AppRouter.StatsScope

    @Environment(AppRouter.self) private var router

    @Query private var transactions: [MoneyTransaction]
    @Query private var budgets: [Budget]
    @State private var displayedMonth = Date()

    private var summary: MonthlySummary {
        let components = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        return StatisticsEngine.monthlySummary(
            of: transactions.map(\.record),
            year: components.year ?? 2026,
            month: components.month ?? 1
        )
    }

    private var yearlySummary: YearlySummary {
        let year = Calendar.current.component(.year, from: displayedMonth)
        return StatisticsEngine.yearlySummary(of: transactions.map(\.record), year: year)
    }

    private var monthlyBudget: Budget? {
        budgets.first { $0.categoryKey == nil && $0.amount > 0 }
    }

    private var currencyCode: String {
        transactions.first?.currencyCode ?? Locale.current.currency?.identifier ?? "CNY"
    }

    var body: some View {
        // 用 Bindable 包装 @Observable 对象，让 Picker 绑定到 router.statsScope
        @Bindable var router = router
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("范围", selection: $router.statsScope) {
                        Text("月度").tag(Scope.month)
                        Text("年度").tag(Scope.year)
                    }
                    .pickerStyle(.segmented)

                    if router.statsScope == .month {
                        monthSwitcher
                        totalsCards
                        if let budget = monthlyBudget {
                            budgetProgress(budget)
                        }
                        if summary.expenseByCategory.isEmpty {
                            ContentUnavailableView(
                                "本月还没有支出",
                                systemImage: "chart.pie",
                                description: Text("记几笔之后这里会出现分析图表")
                            )
                            .padding(.top, 40)
                        } else {
                            categoryPieChart
                            dailyBarChart
                            categoryRanking
                        }
                    } else {
                        yearlyContent
                    }
                    // 注：router.statsScope 在深链触发后由 AppRouter 更新，
                    // Picker 绑定确保 UI 与路由状态同步。
                }
                .padding()
            }
            .navigationTitle("统计")
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(displayedMonth, format: .dateTime.year().month())
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(Calendar.current.isDate(displayedMonth, equalTo: Date(), toGranularity: .month))
        }
        .padding(.horizontal, 4)
    }

    private func shiftMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private var totalsCards: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                totalCard(title: "支出", amount: summary.totalExpense, color: .primary)
                totalCard(title: "收入", amount: summary.totalIncome, color: .green)
                totalCard(title: "结余", amount: summary.balance, color: summary.balance >= 0 ? .blue : .red)
            }
        }
    }

    private func totalCard(title: LocalizedStringKey, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MoneyFormat.string(amount, currencyCode: currencyCode))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var categoryPieChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("支出构成")
                .font(.headline)
            Chart(summary.expenseByCategory.prefix(8), id: \.name) { item in
                SectorMark(
                    angle: .value("金额", MoneyFormat.double(item.total)),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("分类", item.name))
                .cornerRadius(4)
            }
            .frame(height: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dailyBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每日支出")
                .font(.headline)
            Chart(summary.dailyTotals, id: \.day) { item in
                BarMark(
                    x: .value("日", item.day),
                    y: .value("支出", MoneyFormat.double(item.expense))
                )
                .foregroundStyle(Color.accentColor.gradient)
            }
            .frame(height: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 月度预算执行条 + 今日可花。
    private func budgetProgress(_ budget: Budget) -> some View {
        let status = BudgetEngine.status(monthlyBudget: budget.amount, records: transactions.map(\.record))
        let ratio = min(MoneyFormat.double(status.spentThisMonth) / max(MoneyFormat.double(budget.amount), 0.01), 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本月预算")
                    .font(.headline)
                Spacer()
                Text("\(MoneyFormat.string(status.spentThisMonth, currencyCode: currencyCode)) / \(MoneyFormat.string(budget.amount, currencyCode: currencyCode))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(status.isOverBudget ? Color.red : Color.secondary)
            }
            ProgressView(value: ratio)
                .tint(status.isOverBudget ? .red : .accentColor)
            if Calendar.current.isDate(displayedMonth, equalTo: Date(), toGranularity: .month) {
                Text(status.todayAllowance >= 0
                     ? "今日还可以花 \(MoneyFormat.string(status.todayAllowance, currencyCode: currencyCode))"
                     : "今日已超出节奏 \(MoneyFormat.string(-status.todayAllowance, currencyCode: currencyCode))，缓一缓")
                    .font(.footnote)
                    .foregroundStyle(status.todayAllowance >= 0 ? Color.secondary : Color.red)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// 年度报告：12 个月支出走势 + 全年收支 + 分类排行。
    private var yearlyContent: some View {
        VStack(spacing: 20) {
            let yearly = yearlySummary
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    totalCard(title: "全年支出", amount: yearly.totalExpense, color: .primary)
                    totalCard(title: "全年收入", amount: yearly.totalIncome, color: .green)
                    totalCard(title: "全年结余", amount: yearly.balance, color: yearly.balance >= 0 ? .blue : .red)
                }
            }
            if yearly.totalExpense == 0 && yearly.totalIncome == 0 {
                ContentUnavailableView(
                    "今年还没有账目",
                    systemImage: "chart.bar",
                    description: Text("记几笔之后这里会出现年度报告")
                )
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("每月支出")
                        .font(.headline)
                    Chart(Array(yearly.monthlyExpenses.enumerated()), id: \.offset) { index, amount in
                        BarMark(
                            x: .value("月", index + 1),
                            y: .value("支出", MoneyFormat.double(amount))
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                    .chartXAxis {
                        AxisMarks(values: Array(1...12))
                    }
                    .frame(height: 160)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Text("全年分类排行")
                        .font(.headline)
                    ForEach(yearly.expenseByCategory.prefix(10), id: \.name) { item in
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                            Spacer()
                            Text(MoneyFormat.string(item.total, currencyCode: currencyCode))
                                .font(.subheadline.monospacedDigit())
                            Text(item.share.formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var categoryRanking: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类排行")
                .font(.headline)
            ForEach(summary.expenseByCategory, id: \.name) { item in
                VStack(spacing: 4) {
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                        Text("\(item.count) 笔")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(MoneyFormat.string(item.total, currencyCode: currencyCode))
                            .font(.subheadline.monospacedDigit())
                        Text(item.share.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    ProgressView(value: item.share)
                        .tint(.accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
