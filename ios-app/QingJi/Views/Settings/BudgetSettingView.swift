import SwiftUI
import SwiftData
import QingJiCore

/// 月度总预算设置。设置后快记页和统计页会显示「今日可花」。
struct BudgetSettingView: View {
    @Environment(\.modelContext) private var context
    @Query private var budgets: [Budget]

    @State private var amountText = ""

    private var totalBudget: Budget? {
        budgets.first { $0.categoryKey == nil }
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
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
        }
        .navigationTitle("月度预算")
        .onAppear {
            if let budget = totalBudget, budget.amount > 0 {
                amountText = "\(budget.amount)"
            }
        }
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
