import UIKit
import SwiftUI
import SwiftData
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

    @State private var kind: TransactionKind = .expense
    @State private var expression = AmountExpression()
    @State private var selectedCategory: TxCategory?
    @State private var selectedAccount: Account?
    @State private var transferTarget: Account?
    @State private var date = Date()
    @State private var note = ""
    @State private var rankedKeys: [String] = []
    @State private var showSavedToast = false
    @State private var budgetStatus: BudgetStatus?

    private var visibleCategories: [TxCategory] {
        let matching = allCategories.filter { $0.kind == kind }
        guard !rankedKeys.isEmpty else { return matching }
        let order = Dictionary(rankedKeys.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return matching.sorted {
            order[$0.key, default: .max] < order[$1.key, default: .max]
        }
    }

    /// 首次启动种子数据异步写入，account 选择要随查询结果就绪而兜底。
    private var effectiveAccount: Account? {
        selectedAccount ?? accounts.first
    }

    private var currencyCode: String {
        effectiveAccount?.currencyCode ?? Locale.current.currency?.identifier ?? "CNY"
    }

    var body: some View {
        NavigationStack {
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
                        CategoryGrid(categories: visibleCategories, selected: $selectedCategory)
                    }
                }

                detailBar
                AmountKeypad(expression: $expression, onSave: save)
                    .padding(.bottom, 8)
            }
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
            }) {
                AIQuickEntryView()
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
            .onAppear(perform: prepareDefaults)
            .onChange(of: kind) { resetCategorySelection() }
            .onChange(of: accounts.count) {
                if selectedAccount == nil { selectedAccount = accounts.first }
                if transferTarget == nil { resetCategorySelection() }
            }
            .onChange(of: allCategories.count) { resetCategorySelection() }
        }
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
            Picker("从", selection: $selectedAccount) {
                ForEach(accounts) { account in
                    Text(account.name).tag(Optional(account))
                }
            }
            Image(systemName: "arrow.down")
                .foregroundStyle(.secondary)
            Picker("到", selection: $transferTarget) {
                ForEach(accounts) { account in
                    Text(account.name).tag(Optional(account))
                }
            }
        }
        .pickerStyle(.menu)
        .padding(.top, 24)
    }

    private var detailBar: some View {
        HStack(spacing: 12) {
            if kind != .transfer {
                Menu {
                    ForEach(accounts) { account in
                        Button(account.name) { selectedAccount = account }
                    }
                } label: {
                    Label(effectiveAccount?.name ?? String(localized: "账户"), systemImage: effectiveAccount?.kind.symbol ?? "wallet.pass")
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            DatePicker("日期", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
            TextField("备注…", text: $note)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func prepareDefaults() {
        if selectedAccount == nil { selectedAccount = accounts.first }
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
        guard let budget = ((try? context.fetch(FetchDescriptor<Budget>())) ?? []).first(where: { $0.categoryKey == nil }),
              budget.amount > 0 else {
            budgetStatus = nil
            return
        }
        let all = (try? context.fetch(FetchDescriptor<MoneyTransaction>())) ?? []
        budgetStatus = BudgetEngine.status(monthlyBudget: budget.amount, records: all.map(\.record))
    }

    private func resetCategorySelection() {
        if kind == .transfer {
            selectedCategory = nil
            if transferTarget == nil {
                transferTarget = accounts.first { $0.persistentModelID != selectedAccount?.persistentModelID }
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
            defaultOrder: allCategories.map(\.key),
            usages: usages
        )
    }

    private func save() {
        let amount = expression.value
        guard amount > 0 else { return }

        let transaction: MoneyTransaction
        switch kind {
        case .transfer:
            guard let from = effectiveAccount, let to = transferTarget,
                  from.persistentModelID != to.persistentModelID else { return }
            transaction = MoneyTransaction(
                amount: amount, kind: .transfer, date: date, note: note,
                currencyCode: currencyCode, account: from, toAccount: to
            )
        case .expense, .income:
            guard let category = selectedCategory else { return }
            transaction = MoneyTransaction(
                amount: amount, kind: kind, date: date, note: note,
                currencyCode: currencyCode, category: category, account: effectiveAccount
            )
        }
        context.insert(transaction)
        try? context.save()

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        expression.clear()
        note = ""
        date = Date()
        refreshRanking()
        loadBudgetStatus()

        withAnimation(.spring) { showSavedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSavedToast = false }
        }
    }
}
