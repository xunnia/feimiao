import SwiftUI
import SwiftData
import UIKit

/// 待报销：按原账单挂接抵消流水，原账单日期和实际到账日期分别保留。
struct ReimburseView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var selectedTransaction: MoneyTransaction?
    @State private var errorMessage: String?
    let opensFirstSettlement: Bool
    @State private var didOpenLaunchSettlement = false

    private var pending: [MoneyTransaction] {
        transactions.filter {
            $0.kind == .expense &&
            $0.refundOfID == nil &&
            $0.reimbursable &&
            !$0.isReimbursed &&
            remainingAmount(for: $0) > 0
        }
    }

    private var pendingTotal: Decimal {
        pending.reduce(Decimal.zero) { total, transaction in
            total + remainingAmount(for: transaction)
        }
    }

    private var usableAccounts: [Account] {
        accounts.filter { !$0.isDeleted && $0.status == .active }
    }

    init(opensFirstSettlement: Bool = false) {
        self.opensFirstSettlement = opensFirstSettlement
    }

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView(
                    "没有待报销账目",
                    systemImage: "checkmark.circle",
                    description: Text("需要报销的支出会出现在这里")
                )
            } else {
                List {
                    Section {
                        HStack {
                            Label("待报销", systemImage: "clock.badge")
                                .font(.body.weight(.medium))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(MoneyFormat.string(pendingTotal, currencyCode: pending.first?.currencyCode ?? "CNY"))
                                    .font(.title3.monospacedDigit().weight(.semibold))
                                Text("\(pending.count) 笔")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                    }

                    Section {
                        ForEach(pending) { transaction in
                            reimburseRow(transaction)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        selectedTransaction = transaction
                                    } label: {
                                        Label("报销到账", systemImage: "checkmark.seal")
                                    }
                                    .tint(.accentColor)
                                }
                        }
                    } header: {
                        Text("待处理账目")
                    } footer: {
                        Text("确认到账后，原支出会按实际报销额抵消成 0。")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .liquidGlassCanvas()
            }
        }
        .navigationTitle("待报销")
        .sheet(item: $selectedTransaction) { transaction in
            ReimburseSettlementSheet(
                transaction: transaction,
                accounts: usableAccounts
            )
            .presentationDetents([.medium, .large])
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: openLaunchSettlementIfNeeded)
        .onChange(of: transactions.count) { _, _ in
            openLaunchSettlementIfNeeded()
        }
    }

    private func openLaunchSettlementIfNeeded() {
        guard opensFirstSettlement, !didOpenLaunchSettlement,
              let first = pending.first else { return }
        didOpenLaunchSettlement = true
        selectedTransaction = first
    }

    private func reimburseRow(_ transaction: MoneyTransaction) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(
                categoryKey: transaction.category?.key ?? "",
                emoji: transaction.category?.emoji ?? "🏷️",
                size: 36
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.category?.name ?? "未分类")
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(transaction.date, format: .dateTime.year().month().day())
                    if !transaction.note.isEmpty {
                        Text(transaction.note)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(MoneyFormat.string(remainingAmount(for: transaction), currencyCode: transaction.currencyCode))
                .font(.body.monospacedDigit().weight(.medium))
        }
        .padding(.vertical, 4)
    }

    private func remainingAmount(for transaction: MoneyTransaction) -> Decimal {
        (try? LedgerStore.refundStatus(for: transaction, in: context))?.remainingAmount ?? transaction.amount
    }
}

private struct ReimburseSettlementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let transaction: MoneyTransaction
    let accounts: [Account]
    @State private var settledAt = AppClock.now
    @State private var settlementAccountID: UUID?
    @State private var errorMessage: String?

    private var settlementAccount: Account? {
        accounts.first { $0.stableID == settlementAccountID && !$0.isDeleted && $0.status == .active }
    }

    private var remaining: Decimal {
        (try? LedgerStore.refundStatus(for: transaction, in: context))?.remainingAmount ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("原账单") {
                    LabeledContent("分类", value: transaction.category?.name ?? "未分类")
                    LabeledContent("原始金额", value: MoneyFormat.string(transaction.amount, currencyCode: transaction.currencyCode))
                    LabeledContent("本次抵消", value: MoneyFormat.string(remaining, currencyCode: transaction.currencyCode))
                }
                Section("到账信息") {
                    Picker("收款账户", selection: $settlementAccountID) {
                        Text("未指定").tag(Optional<UUID>.none)
                        ForEach(accounts.filter { !$0.isDeleted && $0.status == .active }) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    DatePicker("到账日期", selection: $settledAt, displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Text("抵消流水会挂在原账单下，原账单日期不变，到账日期只用于账户余额追踪。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("报销到账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认到账") { save() }
                        .disabled(remaining <= 0)
                }
            }
            .onAppear {
                settlementAccountID = accounts.first(where: {
                    $0.stableID == transaction.settlementAccountID
                })?.stableID
                    ?? accounts.first(where: { $0.stableID == transaction.account?.stableID })?.stableID
                    ?? accounts.first?.stableID
            }
            .alert("无法报销", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard remaining > 0 else { return }
        do {
            _ = try LedgerStore.createOffset(
                for: transaction,
                amount: remaining,
                note: "报销到账",
                eventType: .reimbursement,
                settlementAccount: settlementAccount,
                settledAt: settledAt,
                in: context
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ReimburseView()
        .modelContainer(AppModelContainer.shared)
}
