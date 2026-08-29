import UIKit
import SwiftUI
import SwiftData
import PhotosUI
import QingJiCore

/// 核心快记页：打开 App 即是键盘，目标 3 秒记完一笔。
struct QuickAddView: View {
    @Environment(\.modelContext) private var context
    /// 全局路由：qingji://ai 深链会把 router.showAISheet 置 true，触发 AI 记账 sheet。
    @Environment(AppRouter.self) private var router

    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var allCategories: [TxCategory]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query(sort: \Tag.sortOrder)
    private var tags: [Tag]

    @State private var kind: TransactionKind = .expense
    @State private var expression = AmountExpression()
    @State private var selectedCategory: TxCategory?
    @State private var selectedAccountID: UUID?
    @State private var selectedBook: Book?
    @State private var transferTargetID: UUID?
    @State private var date = AppClock.now
    @State private var note = ""
    @State private var rankedKeys: [String] = []
    @State private var showSavedToast = false
    @State private var budgetStatus: BudgetStatus?
    @State private var showMoreDetails = false
    @State private var isReimbursable = false
    @State private var isExcluded = false
    @State private var selectedTagNames: Set<String> = []
    @State private var attachmentPath = ""
    @State private var saveError: String?
    @State private var didApplyLaunchKind = false

    private var visibleCategories: [TxCategory] {
        // Android's QuickAddView passes the complete ordered category list to
        // CategoryGrid. Keep the same flat sequence on iOS; subcategories are
        // selectable entries here rather than a second hidden panel.
        let matching = allCategories.filter { $0.kind == kind && !$0.isArchived }
        guard !rankedKeys.isEmpty else { return matching }
        let order = Dictionary(rankedKeys.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return matching.sorted {
            order[$0.key, default: .max] < order[$1.key, default: .max]
        }
    }

    private var childCategories: [TxCategory] {
        allCategories.filter { $0.kind == kind && !$0.isArchived && $0.parentKey != nil }
    }

    private var usableAccounts: [Account] {
        accounts.filter { !$0.isDeleted && $0.status == .active }
    }

    /// 首次启动种子数据异步写入，account 选择要随查询结果就绪而兜底。
    private var effectiveAccount: Account? {
        usableAccounts.first(where: { $0.stableID == selectedAccountID }) ?? usableAccounts.first
    }

    private var effectiveTransferTarget: Account? {
        usableAccounts.first(where: { $0.stableID == transferTargetID })
    }

    private var currencyCode: String {
        effectiveAccount?.currencyCode ?? "CNY"
    }

    private var effectiveBook: Book? {
        selectedBook
            ?? books.first(where: { $0.stableID == router.selectedBookID })
            ?? books.first
    }

    var body: some View {
        VStack(spacing: 0) {
                Picker("类型", selection: $kind) {
                    Text("支出").tag(TransactionKind.expense)
                    Text("收入").tag(TransactionKind.income)
                    Text("转账").tag(TransactionKind.transfer)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if let status = budgetStatus, kind == .expense {
                    todayAllowanceBar(status)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                amountDisplay
                    .padding(.vertical, 12)

                ScrollView {
                    if kind == .transfer {
                        transferPickers
                    } else {
                        CategoryGrid(
                            categories: visibleCategories,
                            childCategories: [],
                            selected: $selectedCategory
                        )
                    }
                }

                detailBar
                AmountKeypad(expression: $expression, onSave: save)
                    .padding(.bottom, 8)
            }
            .liquidGlassCanvas()
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.showAISheet = true
                    } label: {
                        Label("AI 记一笔", systemImage: "sparkles")
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { router.showAISheet },
                set: { router.showAISheet = $0 }
            ), onDismiss: {
                refreshRanking()
                loadBudgetStatus()
                router.clearPendingShare()
            }) {
                AIQuickEntryView(
                    initialText: router.pendingShareText,
                    sharedImageFileName: router.pendingShareImageFileName
                )
            }
            .fullScreenCover(isPresented: Binding(
                get: { router.showChats },
                set: { router.showChats = $0 }
            )) {
                NavigationStack {
                    AIChatsView()
                }
            }
            .sheet(isPresented: $showMoreDetails) {
                QuickAddDetailsSheet(
                    kind: kind,
                    tags: tags,
                    isReimbursable: $isReimbursable,
                    isExcluded: $isExcluded,
                    selectedTagNames: $selectedTagNames,
                    attachmentPath: $attachmentPath
                )
                .presentationDetents([.medium, .large])
            }
            .alert("无法保存", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .overlay(alignment: .top) {
                if showSavedToast {
                    Label("已记一笔", systemImage: "checkmark.circle.fill")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(Color.accentColor.opacity(0.5)), in: .capsule)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear {
                if !didApplyLaunchKind {
                    didApplyLaunchKind = true
                    if router.quickAddStartsWithIncome {
                        kind = .income
                    }
                }
                prepareDefaults()
            }
            .onChange(of: kind) { resetCategorySelection() }
            .onChange(of: accounts.count) {
                if selectedAccountID == nil { selectedAccountID = usableAccounts.first?.stableID }
                if transferTargetID == nil { resetCategorySelection() }
            }
            .onChange(of: allCategories.count) { resetCategorySelection() }
    }

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(MoneyFormat.symbol(of: currencyCode))
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(expression.displayText)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if expression.isCompound {
                Text("= \(expression.value.formatted())")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var transferPickers: some View {
        VStack(spacing: 16) {
            Picker("从", selection: $selectedAccountID) {
                Text("请选择账户").tag(Optional<UUID>.none)
                ForEach(usableAccounts) { account in
                    Text(account.name).tag(Optional(account.stableID))
                }
            }
            Image(systemName: "arrow.down")
                .foregroundStyle(.secondary)
            Picker("到", selection: $transferTargetID) {
                Text("请选择账户").tag(Optional<UUID>.none)
                ForEach(usableAccounts) { account in
                    Text(account.name).tag(Optional(account.stableID))
                }
            }
        }
        .pickerStyle(.menu)
        .padding(.top, 24)
    }

    private var detailBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if kind != .transfer {
                    Menu {
                        ForEach(usableAccounts) { account in
                            Button(account.name) { selectedAccountID = account.stableID }
                        }
                    } label: {
                        Label(effectiveAccount?.name ?? String(localized: "账户"), systemImage: effectiveAccount?.kind.symbol ?? "wallet.pass")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
                Menu {
                    ForEach(books) { book in
                        Button {
                            selectedBook = book
                        } label: {
                            if book.persistentModelID == effectiveBook?.persistentModelID {
                                Label(book.name, systemImage: "checkmark")
                            } else {
                                Text(book.name)
                            }
                        }
                    }
                } label: {
                    Label(effectiveBook?.name ?? "账本", systemImage: "book.closed")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                DatePicker("日期", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                TextField("备注…", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .frame(minWidth: 110)
                Button {
                    showMoreDetails = true
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.glass(.clear))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func prepareDefaults() {
        if selectedAccountID == nil { selectedAccountID = usableAccounts.first?.stableID }
        refreshRanking()
        resetCategorySelection()
        loadBudgetStatus()
    }

    private func todayAllowanceBar(_ status: BudgetStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.todayAllowance >= 0 ? "gauge.with.needle" : "exclamationmark.triangle.fill")
            if status.todayAllowance >= 0 {
                Text("今日可花 \(MoneyFormat.string(status.todayAllowance, currencyCode: currencyCode))")
            } else {
                Text("今日已超支 \(MoneyFormat.string(-status.todayAllowance, currencyCode: currencyCode))")
            }
            Spacer()
            Text("本月剩 \(MoneyFormat.string(status.remaining, currencyCode: currencyCode))")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(
            .regular.tint(status.todayAllowance >= 0 ? Color.accentColor.opacity(0.25) : Color.warning.opacity(0.35)),
            in: .capsule
        )
    }

    /// 设置过预算时计算「今日可花」。
    private func loadBudgetStatus() {
        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        guard let budget = BudgetStore.effectiveTotalBudget(
            from: budgets,
            selectedBookID: router.selectedBookID,
            fallbackBookID: effectiveBook?.stableID
        ), budget.amount > 0 else {
            budgetStatus = nil
            return
        }
        let all = (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? []
        let scoped = LedgerScope.filter(all, selectedBookID: router.selectedBookID)
        budgetStatus = BudgetStore.status(
            for: budget,
            transactions: scoped,
            referenceDate: AppClock.now
        )
    }

    private func resetCategorySelection() {
        if kind == .transfer {
            selectedCategory = nil
            if transferTargetID == nil {
                transferTargetID = usableAccounts.first { $0.stableID != selectedAccountID }?.stableID
            }
        } else if selectedCategory?.kind != kind {
            selectedCategory = visibleCategories.first
        }
    }

    /// 取最近 300 笔流水，让常用、当前时段常见的分类排前面。
    private func refreshRanking() {
        var descriptor = FetchDescriptor<MoneyTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 300
        let recent = (try? context.fetch(descriptor)) ?? []
        let usages = recent.compactMap { transaction -> (String, Date)? in
            guard let key = transaction.category?.key else { return nil }
            return (key, transaction.date)
        }
        rankedKeys = CategoryRanker.rank(
            defaultOrder: allCategories.filter { !$0.isArchived }.map(\.key),
            usages: usages
        )
    }

    private func save() {
        let amount = expression.value
        guard amount > 0 else { return }

        do {
            switch kind {
            case .transfer:
                guard let from = effectiveAccount, let to = effectiveTransferTarget,
                      from.persistentModelID != to.persistentModelID else {
                    saveError = LedgerStore.Error.invalidTransfer.localizedDescription
                    return
                }
                try LedgerStore.createTransaction(
                    in: context,
                    amount: amount,
                    kind: .transfer,
                    date: date,
                    note: note,
                    account: from,
                    toAccount: to,
                    book: effectiveBook,
                    tags: Array(selectedTagNames),
                    isExcluded: isExcluded,
                    attachmentPath: attachmentPath
                )
            case .expense, .income:
                guard let category = selectedCategory else { return }
                try LedgerStore.createTransaction(
                    in: context,
                    amount: amount,
                    kind: kind,
                    date: date,
                    note: note,
                    category: category,
                    account: effectiveAccount,
                    book: effectiveBook,
                    tags: Array(selectedTagNames),
                    reimbursable: kind == .expense && isReimbursable,
                    isExcluded: isExcluded,
                    attachmentPath: attachmentPath
                )
            }
        } catch {
            saveError = error.localizedDescription
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        expression.clear()
        note = ""
        date = AppClock.now
        isReimbursable = false
        isExcluded = false
        selectedTagNames.removeAll()
        attachmentPath = ""
        refreshRanking()
        loadBudgetStatus()

        withAnimation(.spring) { showSavedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSavedToast = false }
        }
    }
}

private struct QuickAddDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: TransactionKind
    let tags: [Tag]
    @Binding var isReimbursable: Bool
    @Binding var isExcluded: Bool
    @Binding var selectedTagNames: Set<String>
    @Binding var attachmentPath: String
    @State private var photoItem: PhotosPickerItem?
    @State private var attachmentError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("收支选项") {
                    if kind == .expense {
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
                                AttachmentStore.remove(attachmentPath)
                                attachmentPath = ""
                            }
                        }
                    }
                }
            }
            .navigationTitle("更多选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { return }
                        let path = try AttachmentStore.save(data: data)
                        await MainActor.run {
                            if !attachmentPath.isEmpty { AttachmentStore.remove(attachmentPath) }
                            attachmentPath = path
                            photoItem = nil
                        }
                    } catch {
                        await MainActor.run { attachmentError = error.localizedDescription }
                    }
                }
            }
            .alert("无法添加照片", isPresented: Binding(
                get: { attachmentError != nil },
                set: { if !$0 { attachmentError = nil } }
            )) {
                Button("好") { attachmentError = nil }
            } message: {
                Text(attachmentError ?? "")
            }
        }
    }
}
