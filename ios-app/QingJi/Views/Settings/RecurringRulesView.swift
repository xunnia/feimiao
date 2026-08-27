import SwiftUI
import SwiftData
import QingJiCore

/// 定时记账管理。规则和自动生成的流水分开显示，重复打开 App 由 store 做幂等补记。
struct RecurringRulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringRule.nextDueDate)
    private var rules: [RecurringRule]
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var categories: [TxCategory]

    @State private var showEditor = false
    @State private var editingRule: RecurringRule?
    @State private var errorMessage: String?

    private var enabledRules: [RecurringRule] { rules.filter { $0.isEnabled && !$0.isCompleted } }
    private var pausedRules: [RecurringRule] { rules.filter { !$0.isEnabled || $0.isCompleted } }

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    "还没有定时记账",
                    systemImage: "clock.badge.plus",
                    description: Text("把房租、订阅或固定收入交给肥喵自动生成")
                )
                .listRowBackground(Color.clear)
            }

            if !enabledRules.isEmpty {
                Section("进行中") {
                    ForEach(enabledRules) { rule in
                        ruleRow(rule)
                    }
                }
            }

            if !pausedRules.isEmpty {
                Section("已暂停或已完成") {
                    ForEach(pausedRules) { rule in
                        ruleRow(rule)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("定时记账")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建定时记账")
            }
        }
        .sheet(isPresented: $showEditor) {
            RecurringRuleEditor(rule: nil)
                .presentationDetents([.large])
        }
        .sheet(item: $editingRule) { rule in
            RecurringRuleEditor(rule: rule)
                .presentationDetents([.large])
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            do { _ = try RecurringStore.materializeDue(in: context) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func ruleRow(_ rule: RecurringRule) -> some View {
        let account = accounts.first { $0.stableID == rule.accountID }
        let target = accounts.first { $0.stableID == rule.toAccountID }
        let book = books.first { $0.stableID == rule.bookID }
        let category = categories.first { $0.key == rule.categoryKey && $0.kind == rule.kind }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: rule.kind == .transfer ? "arrow.left.arrow.right" : "clock")
                    .font(.headline)
                    .foregroundStyle(rule.isEnabled && !rule.isCompleted ? Color.accentColor : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.kind == .transfer ? "转账" : (category?.name ?? "未分类"))
                        .font(.body.weight(.medium))
                    Text(rule.note.isEmpty ? (book?.name ?? "总账本") : rule.note)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(MoneyFormat.string(rule.amount, currencyCode: account?.currencyCode ?? "CNY"))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            HStack(spacing: 6) {
                Text(rule.period.label)
                Text("·")
                Text(rule.isCompleted ? "已完成" : "下次 \(rule.nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                Spacer(minLength: 4)
                if rule.kind == .transfer, let target {
                    Text("\(account?.name ?? "账户") → \(target.name)")
                } else if let account {
                    Text(account.name)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { editingRule = rule }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !rule.isCompleted {
                Button {
                    do { try RecurringStore.setEnabled(rule, enabled: !rule.isEnabled, in: context) }
                    catch { errorMessage = error.localizedDescription }
                } label: {
                    Label(rule.isEnabled ? "暂停" : "启用", systemImage: rule.isEnabled ? "pause.fill" : "play.fill")
                }
                .tint(rule.isEnabled ? .orange : .accentColor)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                do { try RecurringStore.delete(rule, in: context) }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

private struct RecurringRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query(filter: #Predicate<TxCategory> { !$0.isArchived }, sort: \TxCategory.sortOrder)
    private var categories: [TxCategory]

    let rule: RecurringRule?
    @State private var kind: TransactionKind
    @State private var amountText: String
    @State private var categoryKey: String
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var bookID: UUID?
    @State private var note: String
    @State private var period: RecurringPeriod
    @State private var startDate: Date
    @State private var nextDueDate: Date
    @State private var endDateEnabled: Bool
    @State private var endDate: Date
    @State private var totalCountText: String
    @State private var errorMessage: String?

    init(rule: RecurringRule?) {
        self.rule = rule
        _kind = State(initialValue: rule?.kind ?? .expense)
        _amountText = State(initialValue: rule.map { "\($0.amount)" } ?? "")
        _categoryKey = State(initialValue: rule?.categoryKey ?? "")
        _accountID = State(initialValue: rule?.accountID)
        _toAccountID = State(initialValue: rule?.toAccountID)
        _bookID = State(initialValue: rule?.bookID)
        _note = State(initialValue: rule?.note ?? "")
        _period = State(initialValue: rule?.period ?? .monthly)
        _startDate = State(initialValue: rule?.startDate ?? Date())
        _nextDueDate = State(initialValue: rule?.nextDueDate ?? Date())
        _endDateEnabled = State(initialValue: rule?.endDate != nil)
        _endDate = State(initialValue: rule?.endDate ?? Date())
        _totalCountText = State(initialValue: rule.flatMap { $0.totalCount.map(String.init) } ?? "")
    }

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ""))
    }

    private var selectedAccount: Account? {
        accounts.first { $0.stableID == accountID }
    }

    private var selectedTarget: Account? {
        accounts.first { $0.stableID == toAccountID }
    }

    private var selectedCategory: TxCategory? {
        categories.first { $0.key == categoryKey && $0.kind == kind }
    }

    private var eligibleCategories: [TxCategory] {
        categories.filter { $0.kind == kind }
    }

    private var totalCount: Int? {
        let text = totalCountText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : Int(text)
    }

    private var canSave: Bool {
        guard let amount, amount > 0, selectedAccount != nil else { return false }
        if kind == .transfer {
            guard let selectedTarget,
                  selectedTarget.stableID != selectedAccount?.stableID else { return false }
        } else if selectedCategory == nil {
            return false
        }
        if endDateEnabled && endDate < Calendar.current.startOfDay(for: startDate) { return false }
        if !totalCountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           (totalCount ?? 0) <= 0 { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $kind) {
                        Text("支出").tag(TransactionKind.expense)
                        Text("收入").tag(TransactionKind.income)
                        Text("转账").tag(TransactionKind.transfer)
                    }
                    .pickerStyle(.segmented)
                    TextField("金额", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section("账务") {
                    if kind != .transfer {
                        Picker("分类", selection: $categoryKey) {
                            Text("请选择分类").tag("")
                            ForEach(eligibleCategories) { category in
                                Text(category.parentKey == nil ? category.name : "└ \(category.name)")
                                    .tag(category.key)
                            }
                        }
                    }
                    Picker("付款账户", selection: $accountID) {
                        Text("请选择账户").tag(Optional<UUID>.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account.stableID))
                        }
                    }
                    if kind == .transfer {
                        Picker("转入账户", selection: $toAccountID) {
                            Text("请选择账户").tag(Optional<UUID>.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account.stableID))
                            }
                        }
                    }
                    Picker("账本", selection: $bookID) {
                        Text("总账本").tag(Optional<UUID>.none)
                        ForEach(books) { book in
                            Text(book.name).tag(Optional(book.stableID))
                        }
                    }
                }

                Section("执行计划") {
                    Picker("频率", selection: $period) {
                        ForEach(RecurringPeriod.allCases, id: \.self) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    DatePicker("下次执行", selection: $nextDueDate, displayedComponents: .date)
                    Toggle("设置结束日期", isOn: $endDateEnabled)
                    if endDateEnabled {
                        DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                    }
                    TextField("生成次数（可选）", text: $totalCountText)
                        .keyboardType(.numberPad)
                }

                Section {
                    TextField("备注（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(rule == nil ? "新建定时记账" : "编辑定时记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(rule == nil ? "创建" : "保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: prepareDefaults)
            .onChange(of: kind) { _, newKind in
                if newKind == .transfer {
                    categoryKey = ""
                    if toAccountID == accountID {
                        toAccountID = accounts.first { $0.stableID != accountID }?.stableID
                    }
                } else if categories.first(where: { $0.key == categoryKey && $0.kind == newKind }) == nil {
                    categoryKey = categories.first(where: { $0.kind == newKind })?.key ?? ""
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

    private func prepareDefaults() {
        if accountID == nil { accountID = accounts.first?.stableID }
        if kind == .transfer, toAccountID == nil {
            toAccountID = accounts.first { $0.stableID != accountID }?.stableID
        }
        if kind != .transfer, selectedCategory == nil {
            categoryKey = categories.first(where: { $0.kind == kind })?.key ?? ""
        }
    }

    private func save() {
        guard let amount, let account = selectedAccount, canSave else { return }
        let endDate = endDateEnabled ? endDate : nil
        do {
            if let rule {
                try RecurringStore.update(
                    rule,
                    in: context,
                    kind: kind,
                    amount: amount,
                    categoryKey: selectedCategory?.key,
                    account: account,
                    toAccount: kind == .transfer ? selectedTarget : nil,
                    book: books.first { $0.stableID == bookID },
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                    period: period,
                    nextDueDate: nextDueDate,
                    startDate: startDate,
                    endDate: endDate,
                    totalCount: totalCount
                )
            } else {
                _ = try RecurringStore.create(
                    in: context,
                    kind: kind,
                    amount: amount,
                    categoryKey: selectedCategory?.key,
                    account: account,
                    toAccount: kind == .transfer ? selectedTarget : nil,
                    book: books.first { $0.stableID == bookID },
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                    period: period,
                    startDate: startDate,
                    nextDueDate: nextDueDate,
                    endDate: endDate,
                    totalCount: totalCount
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
