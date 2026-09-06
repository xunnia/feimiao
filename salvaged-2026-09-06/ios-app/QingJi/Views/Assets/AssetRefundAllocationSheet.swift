import SwiftUI
import SwiftData
import QingJiCore

/// Native iOS editor for the same per-refund asset allocation contract used by
/// Android. A refund must be fully accounted for before the sheet can close.
struct AssetRefundAllocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let asset: PhysicalAsset

    @State private var pending: [PendingPhysicalAssetRefundAllocation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("读取待分配退款")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pending.isEmpty {
                    ContentUnavailableView(
                        "退款都已分配",
                        systemImage: "checkmark.circle",
                        description: Text("关联物品的净购置成本已经更新。")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(pending) { item in
                                AssetRefundAllocationCard(item: item) {
                                    load()
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("分配退款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
            .alert("无法读取退款", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("重试") { load() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { load() }
        }
    }

    private func load() {
        isLoading = true
        do {
            pending = try AssetRefundAllocationStore.pendingRefundAllocations(
                for: asset,
                in: context
            )
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}

private struct AssetRefundAllocationCard: View {
    @Environment(\.modelContext) private var context

    let item: PendingPhysicalAssetRefundAllocation
    let onCompleted: () -> Void

    @State private var values: [UUID: String]
    @State private var untrackedText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        item: PendingPhysicalAssetRefundAllocation,
        onCompleted: @escaping () -> Void
    ) {
        self.item = item
        self.onCompleted = onCompleted
        _values = State(initialValue: Dictionary(
            item.targets.map {
                ($0.assetID, $0.currentRefundAllocationCents == 0
                    ? ""
                    : Self.plainAmount($0.currentRefundAllocationCents))
            },
            uniquingKeysWith: { first, _ in first }
        ))
        _untrackedText = State(initialValue: item.currentUntrackedCents == 0
            ? ""
            : Self.plainAmount(item.currentUntrackedCents))
    }

    private var allocations: [UUID: Int]? {
        var result: [UUID: Int] = [:]
        for target in item.targets {
            let raw = values[target.assetID, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                result[target.assetID] = 0
                continue
            }
            guard let amount = Decimal(string: raw.replacingOccurrences(of: ",", with: "")),
                  amount >= 0 else { return nil }
            let cents = MoneyNormalization.cents(amount)
            guard cents <= target.allocationLimitCents else { return nil }
            result[target.assetID] = cents
        }
        return result
    }

    private var untrackedCents: Int? {
        guard item.untrackedLimitCents > 0 else { return 0 }
        let raw = untrackedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return 0 }
        guard let amount = Decimal(string: raw.replacingOccurrences(of: ",", with: "")),
              amount >= 0 else { return nil }
        let cents = MoneyNormalization.cents(amount)
        return cents <= item.untrackedLimitCents ? cents : nil
    }

    private var totalCents: Int? {
        guard let allocations, let untrackedCents else { return nil }
        return allocations.values.reduce(untrackedCents, +)
    }

    private var canSave: Bool {
        !isSaving && totalCents == item.refundCents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.orderLabel)
                        .font(.headline)
                        .lineLimit(2)
                    Text(item.refundDate.formatted(.dateTime.year().month().day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                Text(money(item.refundCents))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            ForEach(item.targets) { target in
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.assetName)
                        .font(.subheadline.weight(.medium))
                    Text("本次最多 \(money(target.allocationLimitCents)) · 累计已退 \(money(target.totalAllocatedRefundCents))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        "分配金额",
                        text: Binding(
                            get: { values[target.assetID, default: ""] },
                            set: { values[target.assetID] = $0 }
                        )
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                }
            }

            if item.untrackedLimitCents > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("不属于已跟踪物品")
                        .font(.subheadline.weight(.medium))
                    Text("订单中未登记物品，本次最多 \(money(item.untrackedLimitCents))，不会改变任何物品成本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("未跟踪部分", text: $untrackedText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(totalCents == item.refundCents ? .secondary : .orange)
                Spacer()
                Button(isSaving ? "提交中" : "确认分配") { save() }
                    .disabled(!canSave)
                    .liquidGlassPrimaryPillControl(horizontalPadding: 12, minHeight: 40)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .alert("分配失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var summary: String {
        guard let totalCents else { return "请检查金额和每项上限" }
        if totalCents == item.refundCents { return "合计 \(money(totalCents))，可以确认" }
        if totalCents < item.refundCents { return "还需分配 \(money(item.refundCents - totalCents))" }
        return "已超出 \(money(totalCents - item.refundCents))"
    }

    private func save() {
        guard let allocations, let untrackedCents, canSave else { return }
        isSaving = true
        do {
            try AssetRefundAllocationStore.allocateRefund(
                refundTransactionID: item.refundTransactionID,
                allocationsByAssetID: allocations,
                untrackedCents: untrackedCents,
                in: context
            )
            isSaving = false
            onCompleted()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    private func money(_ cents: Int) -> String {
        MoneyFormat.string(
            Decimal(cents) / Decimal(100),
            currencyCode: item.currencyCode
        )
    }

    private static func plainAmount(_ cents: Int) -> String {
        NSDecimalNumber(decimal: Decimal(cents) / Decimal(100)).stringValue
    }
}
