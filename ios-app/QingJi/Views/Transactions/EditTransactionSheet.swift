import UIKit
import SwiftUI
import SwiftData
import PhotosUI
import QingJiCore

private enum OffsetKind: String, Identifiable {
    case refund
    case reimbursement

    var id: String { rawValue }
    var title: String { self == .refund ? "退款" : "报销到账" }
    var note: String { self == .refund ? "退款" : "报销到账" }
    var eventType: TransactionEventType {
        self == .refund ? .refund : .reimbursement
    }
}

private struct OffsetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let original: MoneyTransaction
    let accounts: [Account]
    let kind: OffsetKind

    @State private var amountText = ""
    @State private var settledAt = AppClock.now
    @State private var settlementAccountID: UUID?
    @State private var errorMessage: String?

    private var settlementAccount: Account? {
        selectableAccounts.first { $0.stableID == settlementAccountID }
    }

    private var selectableAccounts: [Account] {
        accounts.filter { !$0.isDeleted && $0.status == .active }
    }

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("原账单") {
                        Text(original.category?.name ?? "支出")
                    }
                    LabeledContent("剩余可冲减") {
                        Text(MoneyFormat.string(remaining, currencyCode: original.currencyCode))
                            .monospacedDigit()
                    }
                }
                Section("本次\(kind.title)") {
                    TextField("金额", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("到账账户", selection: $settlementAccountID) {
                        Text("未指定").tag(Optional<UUID>.none)
                        ForEach(selectableAccounts) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    DatePicker("到账日期", selection: $settledAt, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { save() }
                        .disabled(amount == nil || amount! <= 0)
                }
            }
            .onAppear {
                if let status = try? LedgerStore.refundStatus(for: original, in: context) {
                    amountText = "\(status.remainingAmount)"
                }
                settlementAccountID = selectableAccounts.first(where: {
                    $0.stableID == original.settlementAccountID
                })?.stableID ?? selectableAccounts.first(where: {
                    $0.stableID == original.account?.stableID
                })?.stableID ?? selectableAccounts.first?.stableID
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

    private var remaining: Decimal {
        guard let status = try? LedgerStore.refundStatus(for: original, in: context) else {
            return 0
        }
        return status.remainingAmount
    }

    private func save() {
        guard let amount, amount > 0 else { return }
        do {
            try LedgerStore.createOffset(
                for: original,
                amount: amount,
                note: kind.note,
                eventType: kind.eventType,
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

/// 编辑一笔已有流水。
struct EditTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let transaction: MoneyTransaction

    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var allCategories: [TxCategory]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Tag.sortOrder)
    private var tags: [Tag]
    @Query(sort: \MoneyTransaction.date)
    private var allTransactions: [MoneyTransaction]

    @State private var amountText = ""
    @State private var note = ""
    @State private var date = AppClock.now
    @State private var categoryKey = ""
    @State private var accountID: UUID?
    @State private var targetAccountID: UUID?
    @State private var isReimbursable = false
    @State private var isExcluded = false
    @State private var selectedTagNames: Set<String> = []
    @State private var attachmentPath = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var operationMessage: String?
    @State private var offsetKind: OffsetKind?
    @State private var didSave = false

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
    }

    private var category: TxCategory? {
        allCategories.first { $0.key == categoryKey && $0.kind == transaction.kind }
    }

    private var account: Account? {
        accounts.first { $0.stableID == accountID }
    }

    private var targetAccount: Account? {
        accounts.first { $0.stableID == targetAccountID }
    }

    private var selectableAccounts: [Account] {
        accounts.filter {
            (!$0.isDeleted && $0.status == .active) ||
            $0.stableID == transaction.account?.stableID ||
            $0.stableID == transaction.toAccount?.stableID
        }
    }

    private var selectedTagList: [String] {
        let ordered = tags.filter { selectedTagNames.contains($0.name) }.map(\.name)
        let existing = Set(ordered)
        return ordered + selectedTagNames.filter { !existing.contains($0) }.sorted()
    }

    private var refundChildren: [MoneyTransaction] {
        allTransactions
            .filter { $0.refundOfID == transaction.stableID }
            .sorted { $0.date < $1.date }
    }

    private var refundStatus: RefundStatus {
        LedgerPolicy.refundStatus(
            for: transaction.record,
            in: allTransactions.map(\.record)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("金额", text: $amountText)
                        .keyboardType(.decimalPad)
                    if transaction.kind != .transfer {
                        Picker("分类", selection: $categoryKey) {
                            Text("未分类").tag("")
                            ForEach(allCategories.filter { $0.kind == transaction.kind }) { item in
                                Label {
                                    Text(item.name)
                                } icon: {
                                    CategoryIcon(
                                        categoryKey: item.key,
                                        emoji: item.emoji,
                                        size: 24
                                    )
                                }
                                .tag(item.key)
                            }
                        }
                    }
                    Picker("账户", selection: $accountID) {
                        Text("无").tag(Optional<UUID>.none)
                        ForEach(selectableAccounts) { item in
                            Text(item.name).tag(Optional(item.stableID))
                        }
                    }
                    if transaction.kind == .transfer {
                        Picker("转入账户", selection: $targetAccountID) {
                            Text("无").tag(Optional<UUID>.none)
                            ForEach(selectableAccounts) { item in
                                Text(item.name).tag(Optional(item.stableID))
                            }
                        }
                    }
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("备注", text: $note)
                    if transaction.kind == .expense, transaction.refundOfID == nil {
                        Toggle("待报销", isOn: $isReimbursable)
                    }
                    Toggle("不计入收支统计", isOn: $isExcluded)
                }
                if !tags.isEmpty {
                    Section("标签") {
                        ForEach(tags) { tag in
                            Button {
                                if selectedTagNames.contains(tag.name) {
                                    selectedTagNames.remove(tag.name)
                                } else {
                                    selectedTagNames.insert(tag.name)
                                }
                            } label: {
                                HStack {
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedTagNames.contains(tag.name) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("附件") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(
                            attachmentPath.isEmpty ? "附加照片" : "更换照片",
                            systemImage: attachmentPath.isEmpty ? "camera" : "photo"
                        )
                    }
                    if !attachmentPath.isEmpty {
                        HStack {
                            Label("已附照片", systemImage: "paperclip")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("移除", role: .destructive) {
                                attachmentPath = ""
                            }
                        }
                    }
                }
                Section {
                    Button("删除这笔", role: .destructive) {
                        do {
                            try LedgerStore.delete(transaction, in: context)
                            dismiss()
                        } catch {
                            operationMessage = error.localizedDescription
                        }
                    }
                }
                if transaction.kind == .expense && transaction.amount > 0 {
                    Section("冲减") {
                        LabeledContent("原始金额") {
                            Text(MoneyFormat.string(refundStatus.originalAmount, currencyCode: transaction.currencyCode))
                                .monospacedDigit()
                        }
                        LabeledContent("已冲减") {
                            Text(MoneyFormat.string(refundStatus.refundedAmount, currencyCode: transaction.currencyCode))
                                .monospacedDigit()
                        }
                        LabeledContent("剩余可冲减") {
                            Text(MoneyFormat.string(refundStatus.remainingAmount, currencyCode: transaction.currencyCode))
                                .monospacedDigit()
                                .foregroundStyle(refundStatus.remainingAmount > 0 ? .primary : .secondary)
                        }
                        if refundStatus.remainingAmount > 0 {
                            Button {
                                offsetKind = .refund
                            } label: {
                                Label("新增退款", systemImage: "arrow.uturn.backward.circle")
                            }
                            Button {
                                offsetKind = .reimbursement
                            } label: {
                                Label("新增报销到账", systemImage: "checkmark.seal")
                            }
                        }
                        ForEach(refundChildren) { adjustment in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(adjustment.eventType == .reimbursement ? "报销到账" : "退款")
                                    Text(adjustment.date, format: .dateTime.year().month().day())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(MoneyFormat.string(-adjustment.amount, currencyCode: adjustment.currencyCode))
                                    .monospacedDigit()
                                Button("撤销", role: .destructive) {
                                    revoke(adjustment)
                                }
                                .font(.caption)
                            }
                        }
                        Text("退款和报销会挂在原账单上，按原账单日期参与统计，不会漂到今天。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(parsedAmount == nil || parsedAmount! <= 0)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { return }
                        let path = try AttachmentStore.save(data: data)
                        await MainActor.run {
                            // 只清理本次编辑过程中产生的临时附件；原附件在保存成功前
                            // 仍由原交易持有，用户取消时不能留下坏链接。
                            if !attachmentPath.isEmpty && attachmentPath != transaction.attachmentPath {
                                AttachmentStore.remove(attachmentPath)
                            }
                            attachmentPath = path
                            photoItem = nil
                        }
                    } catch {
                        await MainActor.run {
                            operationMessage = "无法添加照片：\(error.localizedDescription)"
                        }
                    }
                }
            }
            .onDisappear {
                if !didSave && attachmentPath != transaction.attachmentPath && !attachmentPath.isEmpty {
                    AttachmentStore.remove(attachmentPath)
                }
            }
            .sheet(item: $offsetKind) { kind in
                OffsetSheet(
                    original: transaction,
                    accounts: selectableAccounts,
                    kind: kind
                )
            }
            .alert("操作失败", isPresented: Binding(
                get: { operationMessage != nil },
                set: { if !$0 { operationMessage = nil } }
            )) {
                Button("好") { operationMessage = nil }
            } message: {
                Text(operationMessage ?? "")
            }
        }
    }

    private func load() {
        amountText = "\(transaction.amount)"
        note = transaction.note
        date = transaction.date
        categoryKey = transaction.category?.key ?? ""
        accountID = transaction.account?.stableID
        targetAccountID = transaction.toAccount?.stableID
        isReimbursable = transaction.reimbursable
        isExcluded = transaction.isExcluded
        selectedTagNames = Set(transaction.tags)
        attachmentPath = transaction.attachmentPath
    }

    private func save() {
        guard let amount = parsedAmount, amount > 0 else { return }
        let oldAttachmentPath = transaction.attachmentPath
        do {
            try LedgerStore.updateTransaction(
                transaction,
                amount: amount,
                date: date,
                note: note,
                category: category,
                account: account,
                toAccount: targetAccount,
                attachmentPath: attachmentPath,
                tags: selectedTagList,
                reimbursable: transaction.kind == .expense && isReimbursable,
                isExcluded: isExcluded,
                in: context
            )
            if !oldAttachmentPath.isEmpty && oldAttachmentPath != attachmentPath {
                AttachmentStore.remove(oldAttachmentPath)
            }
            didSave = true
            dismiss()
        } catch {
            if attachmentPath != oldAttachmentPath && !attachmentPath.isEmpty {
                AttachmentStore.remove(attachmentPath)
                attachmentPath = oldAttachmentPath
            }
            operationMessage = error.localizedDescription
        }
    }

    private func revoke(_ adjustment: MoneyTransaction) {
        do {
            try LedgerStore.delete(adjustment, in: context)
        } catch {
            operationMessage = error.localizedDescription
        }
    }
}
