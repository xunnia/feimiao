import SwiftUI
import SwiftData

/// 净资产详情和快照。每次保存都保留组件值，历史报告不会因当前估值变化而漂移。
struct NetWorthView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var transactions: [MoneyTransaction]
    @Query private var physicalAssets: [PhysicalAsset]
    @Query private var receivables: [ReceivableAsset]
    @Query private var liabilities: [LiabilityProfile]
    @Query(sort: \NetWorthSnapshot.asOf, order: .reverse)
    private var snapshots: [NetWorthSnapshot]
    @Query
    private var checkpoints: [AccountBalanceCheckpointRecord]

    @State private var message: String?

    private var breakdown: NetWorthStore.Breakdown {
        NetWorthStore.breakdown(
            accounts: accounts,
            transactions: transactions,
            physicalAssets: physicalAssets,
            receivables: receivables,
            liabilities: liabilities,
            checkpoints: checkpoints
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("当前净资产")
                        .font(.headline)
                    Text(MoneyFormat.string(breakdown.netWorth, currencyCode: "CNY"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(breakdown.netWorth >= 0 ? Color.primary : Color.red)
                    Text("资产 \(MoneyFormat.string(breakdown.totalAssets, currencyCode: "CNY")) · 负债 \(MoneyFormat.string(breakdown.totalLiabilities, currencyCode: "CNY"))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("资产构成") {
                breakdownRow("现金与账户", breakdown.cashAssets, "wallet.pass")
                breakdownRow("投资", breakdown.investmentAssets, "chart.line.uptrend.xyaxis")
                breakdownRow("物品", breakdown.physicalAssets, "shippingbox")
                breakdownRow("权益", breakdown.receivableAssets, "arrow.down.left.circle")
                breakdownRow("负债", breakdown.totalLiabilities, "minus.circle")
            }

            if !breakdown.unsupportedCurrencies.isEmpty {
                Section {
                    Label(
                        "未计入外币：\(breakdown.unsupportedCurrencies.sorted().joined(separator: "、"))",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                } footer: {
                    Text("外币不会被静默折算为 0；补充汇率或改用人民币后再纳入净资产。")
                }
            }

            Section("历史快照") {
                if snapshots.isEmpty {
                    Text("保存一次快照后，这里会记录当日资产构成。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshots) { snapshot in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(snapshot.asOf.formatted(date: .abbreviated, time: .omitted))
                                Text(snapshot.quality.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(MoneyFormat.string(snapshot.netWorth, currencyCode: snapshot.baseCurrency))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("净资产")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存快照") {
                    do {
                        _ = try NetWorthStore.saveSnapshot(in: context)
                        message = "净资产快照已保存"
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        }
        .alert("净资产", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func breakdownRow(_ title: String, _ amount: Decimal, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            Text(title)
            Spacer()
            Text(MoneyFormat.string(amount, currencyCode: "CNY"))
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(title == "负债" ? Color.red : Color.primary)
        }
    }
}
