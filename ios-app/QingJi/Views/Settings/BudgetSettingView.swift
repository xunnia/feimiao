import SwiftUI
import SwiftData
import QingJiCore

/// 月度总预算设置。设置后快记页和统计页会显示「今日可花」。
struct BudgetSettingView: View {
    @Environment(\.modelContext) private var context
    @Query private var budgets: [Budget]
    @Query private var transactions: [MoneyTransaction]

    @State private var amountText = ""

    private var totalBudget: Budget? {
        budgets.first { $0.categoryKey == nil }
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
    }

    private var currencyCode: String {
        transactions.first?.currencyCode ?? "CNY"
    }

    var body: some View {
        Form {
            Section {
                TextField("月度预算金额", text: $amountText)
                    .keyboardType(.decimalPad)
                Button("保存预算") {
                    save()
                }
                .disabled(parsedAmount == nil || parsedAmount! < 0)
            } footer: {
                Text("设置后，记账页会按「(月预算 − 已花) ÷ 剩余天数」实时显示今日可花额度，超速消费当天就能看到，而不是月底才发现超支。设为 0 关闭预算。")
            }

            if let budget = totalBudget, budget.amount > 0 {
                Section {
                    monthProgress(budget)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("月度预算")
        .onAppear {
            if let budget = totalBudget, budget.amount > 0 {
                amountText = "\(budget.amount)"
            }
        }
    }

    /// 本月预算执行进度卡片，复用 BudgetEngine.status 计算逻辑。
    private func monthProgress(_ budget: Budget) -> some View {
        let status = BudgetEngine.status(monthlyBudget: budget.amount, records: transactions.map(\.record))
        let ratio = min(MoneyFormat.double(status.spentThisMonth) / max(MoneyFormat.double(budget.amount), 0.01), 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本月进度")
                    .font(.headline)
                Spacer()
                Text("本月已花 \(MoneyFormat.string(status.spentThisMonth, currencyCode: currencyCode)) / 预算 \(MoneyFormat.string(budget.amount, currencyCode: currencyCode))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(status.isOverBudget ? Color.warning : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ProgressView(value: ratio)
                .tint(status.isOverBudget ? Color.warning : Color.accentColor)
            Text(status.todayAllowance >= 0
                 ? "今日还可以花 \(MoneyFormat.string(status.todayAllowance, currencyCode: currencyCode))"
                 : "今日已超 \(MoneyFormat.string(-status.todayAllowance, currencyCode: currencyCode))")
                .font(.footnote)
                .foregroundStyle(status.todayAllowance >= 0 ? Color.secondary : Color.warning)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func save() {
        guard let amount = parsedAmount, amount >= 0 else { return }
        if let budget = totalBudget {
            budget.amount = amount
        } else {
            context.insert(Budget(amount: amount))
        }
        try? context.save()
    }
}
