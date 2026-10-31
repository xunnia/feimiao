import SwiftUI
import SwiftData
import QingJiCore

/// 同一账单可归集到多个场景；总账本是固定的全量视图，不参与勾选。
struct BookMembershipSection: View {
    let books: [Book]
    @Binding var selection: Set<UUID>

    var body: some View {
        Section {
            ForEach(books.filter { !$0.isDefault }) { book in
                Button {
                    if !selection.insert(book.stableID).inserted { selection.remove(book.stableID) }
                } label: {
                    HStack {
                        Text(book.name).foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(book.stableID) {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(selection.contains(book.stableID) ? .isSelected : [])
            }
        } header: { Text("场景账本（可多选）") }
        footer: { Text("总账本始终包含全部账单。加入多个场景不会重复记账，账户只结算一次。") }
    }
}

struct BookMembershipSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let books: [Book]
    @Binding var selection: Set<UUID>
    @State private var draft: Set<UUID>

    init(books: [Book], selection: Binding<Set<UUID>>) {
        self.books = books
        self._selection = selection
        self._draft = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            AppThemedForm { BookMembershipSection(books: books, selection: $draft) }
                .navigationTitle("选择账本")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { selection = draft; dismiss() }
                    }
                }
        }
    }
}

/// 历史账单批量归集，不按笔复制；移除仅解除目标场景，其他场景不变。
struct BookMembershipBulkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.sortOrder) private var books: [Book]
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var all: [MoneyTransaction]
    let candidateIDs: Set<UUID>?
    @State private var bookID: UUID?
    @State private var removing = false
    @State private var selected = Set<UUID>()
    @State private var query = ""
    @State private var kind: TransactionKind?
    @State private var filtersDates = false
    @State private var startDate = Calendar.current.startOfDay(for: AppClock.now)
    @State private var endDate = Calendar.current.startOfDay(for: AppClock.now)
    @State private var errorMessage: String?
    @State private var confirmRemoval = false

    init(bookID: UUID? = nil, candidateIDs: Set<UUID>? = nil) {
        self.candidateIDs = candidateIDs
        self._bookID = State(initialValue: bookID)
    }

    private var candidates: [MoneyTransaction] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        return all.filter { transaction in
            guard transaction.refundOfID == nil else { return false }
            if let candidateIDs, !candidateIDs.contains(transaction.stableID) { return false }
            if let kind, transaction.kind != kind { return false }
            if filtersDates, (transaction.date < start || transaction.date >= endExclusive) { return false }
            if removing, let bookID, !transaction.scenarioBookIDs.contains(bookID) { return false }
            if !removing, let bookID, transaction.scenarioBookIDs.contains(bookID) { return false }
            if !query.isEmpty {
                let text = [transaction.note, transaction.merchantName, transaction.productName,
                            transaction.category?.name ?? ""].joined(separator: " ")
                if !text.localizedStandardContains(query) { return false }
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            AppThemedForm {
                Section {
                    Picker("场景账本", selection: $bookID) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(books.filter { !$0.isDefault }) { book in
                            Text(book.name).tag(Optional(book.stableID))
                        }
                    }
                    Picker("操作", selection: $removing) {
                        Text("添加到此账本").tag(false)
                        Text("从此账本移除").tag(true)
                    }
                    Picker("收支类型", selection: $kind) {
                        Text("全部").tag(Optional<TransactionKind>.none)
                        Text("支出").tag(Optional(TransactionKind.expense))
                        Text("收入").tag(Optional(TransactionKind.income))
                        Text("转账").tag(Optional(TransactionKind.transfer))
                    }
                    Toggle("按日期筛选", isOn: $filtersDates)
                    if filtersDates {
                        DatePicker("开始日期", selection: $startDate, in: ...endDate, displayedComponents: .date)
                        DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                } footer: {
                    Text("原账单和退款/报销一起归集。移除不会删除账单，也不影响其他账本和账户余额。")
                }
                Section {
                    Button(selected.isSuperset(of: Set(candidates.map(\.stableID))) && !candidates.isEmpty ? "取消选择筛选结果" : "选择全部筛选结果") {
                        let ids = Set(candidates.map(\.stableID))
                        if selected.isSuperset(of: ids) { selected.subtract(ids) }
                        else { selected.formUnion(ids) }
                    }
                    ForEach(candidates) { transaction in
                        Button {
                            if !selected.insert(transaction.stableID).inserted { selected.remove(transaction.stableID) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(transaction.stableID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(transaction.note.isEmpty ? transaction.category?.name ?? "账单" : transaction.note)
                                        .foregroundStyle(.primary).lineLimit(2)
                                    Text(transaction.date, format: .dateTime.year().month().day())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(MoneyFormat.string(transaction.amount, currencyCode: transaction.currencyCode))
                                    .monospacedDigit().foregroundStyle(.primary)
                            }
                        }
                    }
                } header: { Text("已选 \(selected.count) 笔 · 当前 \(candidates.count) 笔") }
            }
            .searchable(text: $query, prompt: "搜索备注、商户、分类")
            .navigationTitle(removing ? "移出已有账单" : "添加已有账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(removing ? "移除" : "添加") {
                        if removing { confirmRemoval = true } else { save() }
                    }.disabled(bookID == nil || selected.isEmpty)
                }
            }
            .onAppear { if bookID == nil { bookID = books.first { !$0.isDefault }?.stableID } }
            .onChange(of: bookID) { _, _ in selected.removeAll() }
            .onChange(of: removing) { _, _ in selected.removeAll() }
            .confirmationDialog("从此账本移除已选的 \(selected.count) 笔账单？", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("仅解除关联") { save() }
                Button("取消", role: .cancel) {}
            } message: { Text("原账单仍保留在总账本和其他已关联的账本。") }
            .alert("无法更新账本", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") { errorMessage = nil } }
            message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard let bookID else { return }
        do {
            try BookMembershipStore.update(transactionIDs: selected,
                operation: removing ? .remove([bookID]) : .add([bookID]), in: context)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
