import UIKit
import SwiftUI
import SwiftData
import QingJiCore

/// 每周对账：账面余额 vs 实际余额，差额一键补记，消除「账不平」的挫败感。
struct ReconcileView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query private var transactions: [MoneyTransaction]
    @Query private var categories: [TxCategory]

    @State private var actualTexts: [PersistentIdentifier: String] = [:]

    var body: some View {
        Form {
            Section {
                Text("对一下每个账户的真实余额，有差额点「补平」，系统会自动记一笔调整，让账永远是平的。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(accounts) { account in
                accountSection(account)
            }
        }
        .navigationTitle("对账")
    }

    @ViewBuilder
    private func accountSection(_ account: Account) -> some View {
        let booked = AccountBalanceCalculator.balance(
            accountName: account.name,
            initialBalance: account.initialBalance,
            records: transactions.map(\.record)
        )
        let actual = Decimal(string: (actualTexts[account.persistentModelID] ?? "").replacingOccurrences(of: ",", with: ""))
        let difference = actual.map { $0 - booked }

        Section(account.name) {
            LabeledContent("账面余额") {
                Text(MoneyFormat.string(booked, currencyCode: account.currencyCode))
                    .monospacedDigit()
            }
            TextField("实际余额", text: Binding(
                get: { actualTexts[account.persistentModelID] ?? "" },
                set: { actualTexts[account.persistentModelID] = $0 }
            ))
            .keyboardType(.decimalPad)

            if let difference, difference != 0 {
                LabeledContent("差额") {
                    Text(MoneyFormat.string(difference, currencyCode: account.currencyCode))
                        .foregroundStyle(difference < 0 ? Color.warning : Color.income)
                        .monospacedDigit()
                }
                Button(difference < 0 ? "补平：记一笔漏记支出" : "补平：记一笔漏记收入") {
                    reconcile(account: account, difference: difference)
                }
            } else if actual != nil {
                Label("账已平", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.income)
            }
        }
    }

    /// 实际比账面少 → 漏记了支出；多 → 漏记了收入。
    private func reconcile(account: Account, difference: Decimal) {
        let kind: TransactionKind = difference < 0 ? .expense : .income
        let fallbackKey = kind == .income ? "otherIncome" : CategorySeed.fallbackExpenseKey
        let category = categories.first { $0.key == fallbackKey }
        context.insert(MoneyTransaction(
            amount: abs(difference),
            kind: kind,
            note: String(localized: "对账调整"),
            currencyCode: account.currencyCode,
            category: category,
            account: account
        ))
        try? context.save()
        actualTexts[account.persistentModelID] = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
