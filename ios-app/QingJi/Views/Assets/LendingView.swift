import SwiftUI
import SwiftData
import UIKit

/// Android 借贷往来页的 iOS 原生实现：按对象聚合借出权益和个人借入，
/// 展开后查看真实的登记、收回、借入和还款时间线。
struct LendingView: View {
    @Query(sort: \ReceivableAsset.updatedAt, order: .reverse)
    private var receivables: [ReceivableAsset]
    @Query(sort: \ReceivableRecovery.recoveredAt, order: .reverse)
    private var recoveries: [ReceivableRecovery]
    @Query(sort: \LiabilityProfile.updatedAt, order: .reverse)
    private var liabilities: [LiabilityProfile]
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]

    @State private var expandedParties: Set<String> = []
    @State private var recoveryAsset: ReceivableAsset?
    @State private var repaymentProfile: LiabilityProfile?
    @State private var showBorrowSheet = false

    private var parties: [LendingParty] {
        var grouped: [String: LendingParty] = [:]

        func add(name: String, event: LendingEvent) {
            var party = grouped[name] ?? LendingParty(name: name)
            party.events.append(event)
            grouped[name] = party
        }

        for asset in receivables where !asset.isDeleted && asset.kind == .loanOut {
            let name = lendingPartyName(
                counterparty: asset.counterparty,
                fallback: asset.name
            )
            let open = (asset.lifecycle == .active || asset.lifecycle == .partiallyRecovered) &&
                asset.remainingAmount > 0
            add(
                name: name,
                event: LendingEvent(
                    id: "loan-\(asset.stableID.uuidString)",
                    date: asset.createdAt,
                    title: "借出",
                    amount: asset.originalAmount,
                    currencyCode: asset.currencyCode,
                    side: .lent,
                    annotation: asset.lifecycle.label,
                    recoveryAsset: open ? asset : nil
                )
            )
            for recovery in recoveries where recovery.receivableID == asset.stableID {
                add(
                    name: name,
                    event: LendingEvent(
                        id: "recovery-\(recovery.stableID.uuidString)",
                        date: recovery.recoveredAt,
                        title: "收回",
                        amount: recovery.amount,
                        currencyCode: asset.currencyCode,
                        side: .lent,
                        annotation: recovery.note.isEmpty ? nil : recovery.note
                    )
                )
            }
        }

        for profile in liabilities where
            profile.kind == .personalBorrow && profile.lifecycle != .archived {
            let name = lendingPartyName(
                counterparty: profile.counterparty,
                fallback: "未注明对象"
            )
            let open = profile.lifecycle == .active && profile.currentPrincipal > 0
            add(
                name: name,
                event: LendingEvent(
                    id: "borrow-\(profile.stableID.uuidString)",
                    date: profile.startDate ?? profile.createdAt,
                    title: "借入",
                    amount: profile.originalPrincipal,
                    currencyCode: profile.currencyCode,
                    side: .borrowed,
                    annotation: profile.startDate == nil ? "按登记时间" : profile.lifecycle.label,
                    repaymentProfile: open ? profile : nil
                )
            )
            if let liabilityAccountID = profile.accountID {
                for transaction in transactions where
                    transaction.kind == .transfer &&
                    transaction.toAccount?.stableID == liabilityAccountID {
                    add(
                        name: name,
                        event: LendingEvent(
                            id: "repayment-\(transaction.stableID.uuidString)",
                            date: transaction.date,
                            title: "还款",
                            amount: transaction.amount,
                            currencyCode: transaction.currencyCode,
                            side: .borrowed
                        )
                    )
                }
            }
        }

        return grouped.values
            .map { party in
                var resolved = party
                resolved.events.sort { $0.date > $1.date }
                resolved.lentRemaining = receivables
                    .filter {
                        !$0.isDeleted && $0.kind == .loanOut &&
                        lendingPartyName(counterparty: $0.counterparty, fallback: $0.name) == party.name &&
                        ($0.lifecycle == .active || $0.lifecycle == .partiallyRecovered)
                    }
                    .reduce(Decimal.zero) { $0 + $1.remainingAmount }
                resolved.borrowedRemaining = liabilities
                    .filter {
                        $0.kind == .personalBorrow && $0.lifecycle == .active &&
                        lendingPartyName(counterparty: $0.counterparty, fallback: "未注明对象") == party.name
                    }
                    .reduce(Decimal.zero) { $0 + $1.currentPrincipal }
                return resolved
            }
            .sorted {
                ($0.events.map(\.date).max() ?? .distantPast) >
                    ($1.events.map(\.date).max() ?? .distantPast)
            }
    }

    var body: some View {
        Group {
            if parties.isEmpty {
                ContentUnavailableView(
                    "还没有借贷往来",
                    systemImage: "person.2",
                    description: Text("登记借出权益或个人借入后，这里会按对象汇总")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(parties) { party in
                            partyCard(party)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .liquidGlassCanvas()
        .navigationTitle("借贷往来")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showBorrowSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .liquidGlassCircleControl()
                .accessibilityLabel("记一笔借入")
            }
        }
        .sheet(isPresented: $showBorrowSheet) {
            BorrowEntrySheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $recoveryAsset) { asset in
            ReceivableRecoverySheet(asset: asset)
                .presentationDetents([.medium])
        }
        .sheet(item: $repaymentProfile) { profile in
            LiabilityRepaymentSheet(profile: profile)
                .presentationDetents([.medium, .large])
        }
    }

    private func partyCard(_ party: LendingParty) -> some View {
        let expanded = expandedParties.contains(party.name)
        let net = party.lentRemaining - party.borrowedRemaining
        return VStack(spacing: 0) {
            Button {
                if expanded {
                    expandedParties.remove(party.name)
                } else {
                    expandedParties.insert(party.name)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(party.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if party.lentRemaining > 0 && party.borrowedRemaining > 0 {
                            Text("借出剩余 \(MoneyFormat.string(party.lentRemaining, currencyCode: "CNY")) · 借入剩余 \(MoneyFormat.string(party.borrowedRemaining, currencyCode: "CNY"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(net == 0 ? "已结清" : net > 0 ? "TA欠我" : "我欠TA")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if net != 0 {
                            Text(MoneyFormat.string(net < 0 ? -net : net, currencyCode: "CNY"))
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(net > 0 ? Color.accentColor : .primary)
                        }
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(party.events) { event in
                    Divider().padding(.leading, 14)
                    eventRow(event)
                }
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.6)
        }
    }

    private func eventRow(_ event: LendingEvent) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline)
                HStack(spacing: 5) {
                    Text(event.date, format: .dateTime.year().month().day())
                    if let annotation = event.annotation {
                        Text("· \(annotation)")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(MoneyFormat.string(event.amount, currencyCode: event.currencyCode))
                .font(.subheadline.monospacedDigit().weight(.medium))
            if let asset = event.recoveryAsset {
                Button("收回") { recoveryAsset = asset }
                    .font(.caption.weight(.semibold))
                    .liquidGlassPrimaryPillControl(horizontalPadding: 10, minHeight: 36)
            }
            if let profile = event.repaymentProfile {
                Button("还款") { repaymentProfile = profile }
                    .font(.caption.weight(.semibold))
                    .liquidGlassPrimaryPillControl(horizontalPadding: 10, minHeight: 36)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private enum LendingSide {
    case lent
    case borrowed
}

private struct LendingEvent: Identifiable {
    let id: String
    let date: Date
    let title: String
    let amount: Decimal
    let currencyCode: String
    let side: LendingSide
    let annotation: String?
    let recoveryAsset: ReceivableAsset?
    let repaymentProfile: LiabilityProfile?

    init(
        id: String,
        date: Date,
        title: String,
        amount: Decimal,
        currencyCode: String,
        side: LendingSide,
        annotation: String? = nil,
        recoveryAsset: ReceivableAsset? = nil,
        repaymentProfile: LiabilityProfile? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.side = side
        self.annotation = annotation
        self.recoveryAsset = recoveryAsset
        self.repaymentProfile = repaymentProfile
    }
}

private struct LendingParty: Identifiable {
    let name: String
    var id: String { name }
    var events: [LendingEvent] = []
    var lentOriginal: Decimal = 0
    var borrowedOriginal: Decimal = 0
    var lentRemaining: Decimal = 0
    var borrowedRemaining: Decimal = 0
}

private func lendingPartyName(counterparty: String, fallback: String) -> String {
    let trimmed = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    return fallback.isEmpty ? "未注明对象" : fallback
}

struct BorrowEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]

    @State private var counterparty = ""
    @State private var amountText = ""
    @State private var targetAccountID: UUID?
    @State private var bookID: UUID?
    @State private var dueDateEnabled = false
    @State private var dueDate = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    private var targetAccounts: [Account] {
        accounts.filter {
            !$0.isDeleted && $0.status == .active && $0.currencyCode == "CNY"
        }
    }

    private var amount: Decimal? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private var canSave: Bool {
        !counterparty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            amount.map { $0 > 0 } == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("借入信息") {
                    TextField("对象姓名", text: $counterparty)
                    TextField("借入金额", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("备注（可选）", text: $note)
                }

                Section("资金去向") {
                    Picker("入账账户", selection: $targetAccountID) {
                        Text("不指定（只记录欠款）").tag(Optional<UUID>.none)
                        ForEach(targetAccounts) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    Picker("账本", selection: $bookID) {
                        Text("总账本").tag(Optional<UUID>.none)
                        ForEach(books) { book in
                            Text(book.name).tag(Optional(book.stableID))
                        }
                    }
                }

                Section("还款约定") {
                    Toggle("设置还款日", isOn: $dueDateEnabled)
                    if dueDateEnabled {
                        DatePicker("还款日", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section {
                    Text("每笔借入都会建立独立的负债账户和档案；指定入账账户时，钱会以真实转账进入该账户，不会伪装成普通收入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("记一笔借入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
            .alert("无法保存", isPresented: Binding(
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
        guard let amount, amount > 0, canSave else { return }
        do {
            _ = try LiabilityStore.createPersonalBorrow(
                in: context,
                counterparty: counterparty,
                amount: amount,
                toAccount: targetAccounts.first(where: { $0.stableID == targetAccountID }),
                dueDate: dueDateEnabled ? dueDate : nil,
                book: books.first(where: { $0.stableID == bookID }),
                note: note
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
