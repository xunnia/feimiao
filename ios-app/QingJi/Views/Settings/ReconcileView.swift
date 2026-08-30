import UIKit
import SwiftUI
import SwiftData
import QingJiCore

/// 每周对账：账面余额 vs 实际余额，保存可撤销的余额校准记录。
struct ReconcileView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query private var transactions: [MoneyTransaction]
    @Query
    private var checkpoints: [AccountBalanceCheckpointRecord]

    @State private var actualTexts: [PersistentIdentifier: String] = [:]
    @State private var errorMessage: String?

    private var usableAccounts: [Account] {
        accounts.filter { !$0.isDeleted && $0.status == .active }
    }

    var body: some View {
        Form {
            Section {
                Text("对一下每个账户的真实余额，有差额点「保存校准」。校准不会伪造一笔收入或支出，之后仍可撤销。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(usableAccounts) { account in
                accountSection(account)
            }
        }
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("对账")
        .alert("无法保存校准", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func accountSection(_ account: Account) -> some View {
        let booked = LedgerStore.accountBalance(
            for: account,
            transactions: transactions,
            checkpoints: checkpoints
        )
        let actual = Decimal(string: (actualTexts[account.persistentModelID] ?? "").replacingOccurrences(of: ",", with: ""))
        let difference = actual.map { $0 - booked }
        let history = checkpoints
            .filter { $0.accountID == account.stableID && $0.eventKindRaw == "anchor" && $0.status == "active" }
            .sorted { $0.effectiveAt > $1.effectiveAt }

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
                Button("保存余额校准") {
                    if let actual {
                        reconcile(account: account, actualBalance: actual)
                    }
                }
                .liquidGlassPrimaryPillControl(horizontalPadding: 14, minHeight: 44)
            } else if actual != nil {
                Label("账已平", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.income)
            }

            if !history.isEmpty {
                ForEach(history.prefix(3)) { checkpoint in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已核对 \(checkpoint.effectiveAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                            Text("确认余额 \(MoneyFormat.string(checkpoint.targetBalance, currencyCode: account.currencyCode))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("撤销") {
                            do {
                                try AccountCheckpointStore.reverse(checkpoint, in: context)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        .font(.caption)
                        .liquidGlassPillControl(horizontalPadding: 10, minHeight: 36)
                    }
                }
            }
        }
    }

    /// 保存“此刻实际余额”与账面余额的差额，不伪造普通收支流水。
    private func reconcile(account: Account, actualBalance: Decimal) {
        do {
            _ = try AccountCheckpointStore.create(
                for: account,
                actualBalance: actualBalance,
                effectiveAt: AppClock.now,
                in: context
            )
            actualTexts[account.persistentModelID] = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // 复用表单的本地输入状态；失败时不丢用户刚填的余额。
            errorMessage = error.localizedDescription
        }
    }
}
