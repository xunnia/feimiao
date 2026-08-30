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
    @State private var editingTransaction: MoneyTransaction?
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
            selectedBookID: router.selectedBookID,
            fallbackBookID: books.first(where: \.isDefault)?.stableID
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
        let visibleTransactions = snapshot.includedTransactions.filter { transaction in
            guard transaction.refundOfID == nil,
                  Calendar.current.isDate(transaction.date, equalTo: displayedMonth, toGranularity: .month)
            else { return false }
            switch transactionFilter {
            case .all: return true
            case .expense: return transaction.kind == .expense
            case .income: return transaction.kind == .income
            }
        }

        ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    summaryCard(
                        summary: summary,
                        totalBudget: totalBudget,
                        status: budgetStatus,
                        currencyCode: snapshot.includedCurrencyCode,
                        now: now
                    )
                    filterSegment
                    recentSection(
                        transactions: visibleTransactions,
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
                            .foregroundStyle(.primary)
                    }
                    .liquidGlassCircleControl()
                    .accessibilityLabel("打开菜单")
                }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.selectedTab = .search
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .liquidGlassCircleControl()
                .accessibilityLabel("搜索明细")
            }
            ToolbarItem(placement: .topBarTrailing) {
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
                    .foregroundStyle(.primary)
                }
                .liquidGlassPillControl(horizontalPadding: 14, minWidth: 116)
                .tint(.primary)
                .accessibilityLabel("当前账本：\(selectedBookName)")
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
            .sheet(item: $editingTransaction) { transaction in
                EditTransactionSheet(transaction: transaction)
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
                .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
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
                .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
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
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            Image(status?.isOverBudget == true ? "MascotOverspend" : "MascotIdle")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .offset(x: 6, y: -8)
                .allowsHitTesting(false)
        }
    }

    private func recentSection(
        transactions: [MoneyTransaction],
        refundByID: [UUID: Decimal]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if transactions.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "tray",
                    description: Text("切换上方筛选，或记下这个月的第一笔")
                )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(dayGroups(transactions)) { group in
                    TransactionDayCard(
                        day: group.day,
                        items: group.items,
                        refundByID: refundByID,
                        onSelect: { editingTransaction = $0 }
                    )
                }
            }
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch transactionFilter {
        case .all: return "这个月还没有账目"
        case .expense: return "这个月还没有支出记录"
        case .income: return "这个月还没有收入记录"
        }
    }

    private func dayGroups(_ transactions: [MoneyTransaction]) -> [HomeTransactionDayGroup] {
        let calendar = Calendar.current
        return Dictionary(grouping: transactions) {
            calendar.startOfDay(for: $0.date)
        }
        .map { day, items in
            HomeTransactionDayGroup(
                day: day,
                items: items.sorted { $0.date > $1.date }
            )
        }
        .sorted { $0.day > $1.day }
    }

    private func startOfMonth(_ date: Date) -> Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: date)
        ) ?? date
    }
}

private struct HomeTransactionDayGroup: Identifiable {
    let day: Date
    let items: [MoneyTransaction]
    var id: Date { day }
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
        return "\(max(0, Int((raw * 100).rounded())))%"
    }

    private var remainingDays: Int {
        let calendar = Calendar.current
        let now = AppClock.now
        let day = calendar.component(.day, from: now)
        let count = calendar.range(of: .day, in: .month, for: now)?.count ?? day
        return max(1, count - day + 1)
    }

    private var footerText: String {
        let amount = MoneyFormat.string(budget, currencyCode: currencyCode)
        return isCurrentMonth ? "\(amount) · 剩 \(remainingDays) 天" : amount
    }

    private var remainingText: String {
        let absolute = status.remaining < 0 ? -status.remaining : status.remaining
        let amount = MoneyFormat.string(absolute, currencyCode: currencyCode)
        return status.isOverBudget ? "-\(amount)" : amount
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 12)
                    Text(
                        isCurrentMonth
                            ? (status.isOverBudget ? "月预算已超" : "月预算剩余")
                            : (status.isOverBudget ? "该月超预算" : "该月预算剩余")
                    )
                }
                .font(.caption.weight(.light))
                .foregroundStyle(.secondary)
                Text(remainingText)
                    .font(.system(size: 29, weight: .medium, design: .rounded))
                    .foregroundStyle(status.isOverBudget ? Color.warning : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())

                HStack(spacing: 0) {
                    metric(title: "收入", amount: summary.totalIncome, color: .income)
                    Divider().frame(height: 32).padding(.horizontal, 14)
                    metric(title: "支出", amount: summary.totalExpense, color: .primary)
                }

                BudgetGradientProgressBar(value: ratio)
                HStack {
                    Text(percentText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.10), in: .rect(cornerRadius: 6))
                    Spacer()
                    Text(footerText)
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
            .offset(y: 8)
        }
    }

    private func metric(title: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(MoneyFormat.string(amount, currencyCode: currencyCode))
                .font(.subheadline.monospacedDigit().weight(.regular))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}

private struct BudgetGradientProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.48, green: 0.68, blue: 0.38),
                                Color(red: 0.90, green: 0.69, blue: 0.20),
                                Color.warning,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 7)
        .accessibilityLabel("预算进度")
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100))%")
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
                .liquidGlassPillControl(horizontalPadding: 12, minHeight: 38)
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

    private var ringColor: Color {
        status.todayAllowance < 0
            ? Color.warning
            : Color(red: 0.48, green: 0.68, blue: 0.38)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: value)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
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
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
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

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 8) {
                    Button(action: openSelectedEntry) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .liquidGlassCircleControl()
                    .glassEffectID("entry-add", in: glassNamespace)
                    .accessibilityLabel("添加一笔")

                    Button {
                        withAnimation(.snappy(duration: 0.32)) {
                            isAIMode.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isAIMode ? "sparkles" : "pencil")
                            Text(isAIMode ? "AI 记账" : "手动记账")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                    }
                    .liquidGlassPillControl(horizontalPadding: 0, minHeight: 44)
                    .glassEffectID(isAIMode ? "entry-ai" : "entry-manual", in: glassNamespace)
                    .accessibilityLabel("切换到\(isAIMode ? "手动记账" : "AI 记账")")

                    Spacer(minLength: 0)

                    Button(action: openSelectedEntry) {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .liquidGlassCircleControl()
                    .glassEffectID("entry-open", in: glassNamespace)
                    .accessibilityLabel("打开\(isAIMode ? "AI 记账" : "手动记账")")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular,
            in: .rect(cornerRadius: 26)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .sheet(isPresented: $showManualEntry) {
            QuickAddView()
                .presentationDetents([.fraction(0.84), .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
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
