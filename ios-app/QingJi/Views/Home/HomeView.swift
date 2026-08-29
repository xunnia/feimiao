import UIKit
import SwiftUI
import SwiftData
import QingJiCore

private enum HomeTransactionFilter: String, CaseIterable, Hashable {
    case all
    case expense
    case income

    var title: LocalizedStringKey {
        switch self {
        case .all: "全部"
        case .expense: "支出"
        case .income: "收入"
        }
    }
}

/// iOS 首页：先看本月真实汇总，再进入记账和明细。
/// 账本筛选遵守安卓端的「计入总账」约定；退款子记录保留在统计中，但不在首页重复列出。
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    let onOpenDrawer: (() -> Void)?
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @Query private var budgets: [Budget]
    @State private var transactionFilter: HomeTransactionFilter = .all
    @State private var displayedMonth = AppClock.now
    @State private var monthPickerDate = AppClock.now
    @State private var showMonthPicker = false
    @State private var projectionCache = IOSLedgerProjectionCache()
    @State private var statisticsCache = IOSStatisticsProjectionCache()

    init(onOpenDrawer: (() -> Void)? = nil) {
        self.onOpenDrawer = onOpenDrawer
    }

    private var selectedBookName: String {
        if let selectedBookID = router.selectedBookID,
           let book = books.first(where: { $0.stableID == selectedBookID }) {
            return book.name
        }
        return "总账本"
    }

    var body: some View {
        let now = AppClock.now
        let snapshot = projectionCache.snapshot(
            for: transactions,
            selectedBookID: router.selectedBookID
        )
        let components = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        let summary = statisticsCache.monthly(
            of: snapshot.includedRecords,
            revision: snapshot.revision,
            year: components.year ?? 2000,
            month: components.month ?? 1
        )
        let totalBudget = BudgetStore.effectiveTotalBudget(
            from: budgets,
            selectedBookID: router.selectedBookID
        )
        let budgetStatus = totalBudget.map { budget in
            statisticsCache.status(
                for: budget,
                records: snapshot.includedRecords,
                revision: snapshot.revision,
                referenceDate: Calendar.current.isDate(
                    displayedMonth,
                    equalTo: now,
                    toGranularity: .month
                ) ? now : displayedMonth
            )
        }
        let recentTransactions = Array(snapshot.includedTransactions.filter { transaction in
            guard transaction.refundOfID == nil,
                  Calendar.current.isDate(transaction.date, equalTo: displayedMonth, toGranularity: .month)
            else { return false }
            switch transactionFilter {
            case .all: return true
            case .expense: return transaction.kind == .expense
            case .income: return transaction.kind == .income
            }
        }.prefix(8))

        ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard(
                        summary: summary,
                        totalBudget: totalBudget,
                        status: budgetStatus,
                        currencyCode: snapshot.includedCurrencyCode,
                        now: now
                    )
                    filterSegment
                    recentSection(
                        transactions: recentTransactions,
                        refundByID: snapshot.includedRefundTotals
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .liquidGlassCanvas()
            // 首页的主操作必须和 Android 一样固定在底部；其它页面沿用根导航栈。
            // 底部输入框内的材质与动效使用
            // iOS 原生 Liquid Glass，但不改变 Android 的功能入口。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeRecordInputBar()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onOpenDrawer?()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("打开菜单")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                router.selectedTab = .search
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("搜索明细")

                            Menu {
                                Button {
                                    router.selectedBookID = nil
                                } label: {
                                    Label("总账本", systemImage: router.selectedBookID == nil ? "checkmark" : "book.closed")
                                }
                                ForEach(books) { book in
                                    Button {
                                        router.selectedBookID = book.stableID
                                    } label: {
                                        Label(book.name, systemImage: router.selectedBookID == book.stableID ? "checkmark" : "book.closed")
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "book.closed")
                                    Text(selectedBookName)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                }
                                .font(.subheadline.weight(.medium))
                                .frame(minWidth: 100, minHeight: 44)
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("当前账本：\(selectedBookName)")
                        }
                    }
                }
            }
            .sheet(isPresented: $showMonthPicker) {
                MonthPickerSheet(
                    selection: $monthPickerDate,
                    maximumDate: now
                ) {
                    displayedMonth = startOfMonth(monthPickerDate)
                    showMonthPicker = false
                }
                .presentationDetents([.medium])
            }
        .toolbar(.hidden, for: .tabBar)
    }

    private var filterSegment: some View {
        Picker("账目范围", selection: $transactionFilter) {
            ForEach(HomeTransactionFilter.allCases, id: \.self) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("账目范围")
    }

    private func summaryCard(
        summary: MonthlySummary,
        totalBudget: Budget?,
        status: BudgetStatus?,
        currencyCode: String,
        now: Date
    ) -> some View {
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button {
                    monthPickerDate = displayedMonth
                    showMonthPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Text(displayedMonth, format: .dateTime.year().month())
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("选择月份")

                Button {
                    router.statsScope = .month
                    router.selectedTab = .statistics
                } label: {
                    HStack(spacing: 4) {
                        Text("统计")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("查看统计")
                Spacer()
            }

            if let totalBudget, let status {
                BudgetSummaryBody(
                    summary: summary,
                    status: status,
                    budget: totalBudget.amount,
                    isCurrentMonth: Calendar.current.isDate(displayedMonth, equalTo: now, toGranularity: .month),
                    currencyCode: currencyCode
                )
            } else {
                NoBudgetSummaryBody(
                    summary: summary,
                    currencyCode: currencyCode
                ) {
                    router.settingsPushTarget = .budget
                    router.selectedTab = .settings
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Image("mascot-idle")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .offset(x: 4, y: -6)
                .allowsHitTesting(false)
        }
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.07)), in: .rect(cornerRadius: 20))
    }

    private func recentSection(
        transactions: [MoneyTransaction],
        refundByID: [UUID: Decimal]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近账目")
                    .font(.headline)
                Spacer()
                Button("全部") { router.selectedTab = .transactions }
                    .font(.subheadline)
            }

            if transactions.isEmpty {
                ContentUnavailableView("还没有账目", systemImage: "tray", description: Text("记下第一笔，肥喵就开始帮你整理"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(transactions.enumerated()), id: \.element.persistentModelID) { index, transaction in
                        TransactionRow(
                            transaction: transaction,
                            refundAmount: refundByID[transaction.stableID] ?? 0
                        )
                            .padding(.vertical, 8)
                        if index < transactions.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(.background, in: .rect(cornerRadius: 18))
            }
        }
    }

    private func startOfMonth(_ date: Date) -> Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: date)
        ) ?? date
    }
}

private struct BudgetSummaryBody: View {
    let summary: MonthlySummary
    let status: BudgetStatus
    let budget: Decimal
    let isCurrentMonth: Bool
    let currencyCode: String

    private var ratio: Double {
        guard budget > 0 else { return 0 }
        return min(max(MoneyFormat.double(status.spentThisMonth) / MoneyFormat.double(budget), 0), 1)
    }

    private var percentText: String {
        let raw = budget > 0 ? MoneyFormat.double(status.spentThisMonth) / MoneyFormat.double(budget) : 0
        return raw > 1 ? "100%+" : "\(Int((raw * 100).rounded()))%"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    isCurrentMonth
                        ? (status.isOverBudget ? "月预算已超" : "月预算剩余")
                        : (status.isOverBudget ? "该月超预算" : "该月预算剩余"),
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(MoneyFormat.string(status.remaining, currencyCode: currencyCode))
                    .font(.system(size: 27, weight: .medium, design: .rounded))
                    .foregroundStyle(status.isOverBudget ? Color.warning : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())

                HStack(spacing: 0) {
                    metric(title: "收入", amount: summary.totalIncome, color: .income)
                    Divider().frame(height: 32).padding(.horizontal, 14)
                    metric(title: "支出", amount: summary.totalExpense, color: .primary)
                }

                ProgressView(value: ratio)
                    .tint(status.isOverBudget ? Color.warning : Color.accentColor)
                HStack {
                    Text(percentText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(status.isOverBudget ? Color.warning : Color.accentColor)
                    Spacer()
                    Text("预算 \(MoneyFormat.string(budget, currencyCode: currencyCode))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            TodayAllowanceRing(
                status: status,
                currencyCode: currencyCode,
                isCurrentMonth: isCurrentMonth
            )
        }
    }

    private func metric(title: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(MoneyFormat.string(amount, currencyCode: currencyCode))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}

private struct NoBudgetSummaryBody: View {
    let summary: MonthlySummary
    let currencyCode: String
    let onOpenBudget: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                metric(title: "支出", amount: summary.totalExpense, color: .primary)
                Divider().frame(height: 42).padding(.horizontal, 18)
                metric(title: "收入", amount: summary.totalIncome, color: .income)
            }
            HStack {
                Text("结余 \(MoneyFormat.string(summary.balance, currencyCode: currencyCode))")
                    .font(.caption)
                    .foregroundStyle(summary.balance < 0 ? Color.warning : .secondary)
                Spacer()
                Button(action: onOpenBudget) {
                    Label("设置预算", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.caption)
                }
                .buttonStyle(.glass)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func metric(title: String, amount: Decimal, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(MoneyFormat.string(amount, currencyCode: currencyCode))
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

private struct TodayAllowanceRing: View {
    let status: BudgetStatus
    let currencyCode: String
    let isCurrentMonth: Bool

    private var value: Double {
        guard isCurrentMonth else {
            return status.monthlyBudget > 0
                ? min(max(MoneyFormat.double(status.spentThisMonth) / MoneyFormat.double(status.monthlyBudget), 0), 1)
                : 0
        }
        if status.todayAllowance < 0 { return 0 }
        let envelope = status.spentToday + status.todayAllowance
        return envelope > 0
            ? min(max(MoneyFormat.double(status.todayAllowance) / MoneyFormat.double(envelope), 0), 1)
            : 1
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.14), lineWidth: 9)
            Circle()
                .trim(from: 0, to: value)
                .stroke(
                    status.todayAllowance < 0 ? Color.warning : Color.accentColor,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(isCurrentMonth ? "今日可用" : "已用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(isCurrentMonth
                     ? MoneyFormat.string(status.todayAllowance, currencyCode: currencyCode)
                     : "\(Int((value * 100).rounded()))%")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: 80, height: 80)
    }
}

private struct MonthPickerSheet: View {
    @Binding var selection: Date
    let maximumDate: Date
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            DatePicker(
                "月份",
                selection: $selection,
                in: ...maximumDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("选择月份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onConfirm)
                }
            }
        }
    }
}

/// 安卓主页底部「记一记」输入框的 iOS 原生实现。
///
/// 入口、模式切换和发送分流与 Android RecordInputBar 对齐；按钮使用
/// Liquid Glass 和系统触感，保证 iOS 的手感提升不改变业务行为。
private struct HomeRecordInputBar: View {
    @AppStorage("qingji.recordAiMode") private var isAIMode = false
    @State private var showManualEntry = false
    @State private var showAIEntry = false
    @Namespace private var glassNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: openSelectedEntry) {
                Text("记一记")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开\(isAIMode ? "AI 记账" : "手动记账")")

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: openSelectedEntry) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.semibold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("entry-add", in: glassNamespace)
                    .accessibilityLabel("添加一笔")

                    Button {
                        withAnimation(.snappy(duration: 0.32)) {
                            isAIMode.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isAIMode ? "sparkles" : "pencil")
                                .symbolEffect(.replace, value: isAIMode)
                            Text(isAIMode ? "AI 记账" : "手动记账")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID(isAIMode ? "entry-ai" : "entry-manual", in: glassNamespace)
                    .accessibilityLabel("切换到\(isAIMode ? "手动记账" : "AI 记账")")

                    Spacer(minLength: 0)

                    Button(action: openSelectedEntry) {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.semibold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.accentColor)
                    .glassEffectID("entry-open", in: glassNamespace)
                    .accessibilityLabel("打开\(isAIMode ? "AI 记账" : "手动记账")")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color.accentColor.opacity(0.06)), in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground).opacity(0),
                    Color(.systemGroupedBackground).opacity(0.92),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showManualEntry) {
            QuickAddView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAIEntry) {
            AIQuickEntryView()
                .presentationDetents([.large])
        }
    }

    private func openSelectedEntry() {
        if isAIMode {
            showAIEntry = true
        } else {
            showManualEntry = true
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(AppModelContainer.shared)
        .environment(AppRouter())
}
