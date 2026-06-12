import UIKit
import SwiftUI
import SwiftData
import Charts
import QingJiCore

/// 月度统计：收支卡片 + 分类占比扇形图 + 每日支出柱状图 + 分类排行。
struct MonthlyStatsView: View {
    @Query private var transactions: [MoneyTransaction]
    @State private var displayedMonth = Date()

    private var summary: MonthlySummary {
        let components = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        return StatisticsEngine.monthlySummary(
            of: transactions.map(\.record),
            year: components.year ?? 2026,
            month: components.month ?? 1
        )
    }

    private var currencyCode: String {
        transactions.first?.currencyCode ?? Locale.current.currency?.identifier ?? "CNY"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    monthSwitcher
                    totalsCards
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
        HStack(spacing: 12) {
            totalCard(title: "支出", amount: summary.totalExpense, color: .primary)
            totalCard(title: "收入", amount: summary.totalIncome, color: .green)
            totalCard(title: "结余", amount: summary.balance, color: summary.balance >= 0 ? .blue : .red)
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
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
