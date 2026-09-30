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
    @Query private var budgetRules: [BudgetRuleRecord]
    @Query private var budgetRollovers: [BudgetRolloverChangeRecord]
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
        // 预算规则模型（docs/08 §6.10）：和小组件、统计环、记账页同一个入口。
        let budgetSnapshot = BudgetRuleStore.snapshot(
            rules: budgetRules,
            rollovers: budgetRollovers,
            selectedBookID: router.selectedBookID,
            books: books,
            transactions: transactions,
            year: components.year ?? 2000,
            month: components.month ?? 1,
            now: now
        )
        let totalBudget = budgetSnapshot.plannedAmount
        let budgetStatus = budgetSnapshot.status
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
                        hasDailyGuidance: budgetSnapshot.hasDailyGuidance,
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
                    // 与抽屉「我的账本」同一顺序；总账本就是默认账本（selectedBookID == nil），
                    // 不再单独多列一行。
                    ForEach(DrawerLayout.orderedBooks(books)) { book in
                        let selected = router.selectedBookID.map { $0 == book.stableID } ?? book.isDefault
                        Button {
                            router.selectedBookID = book.isDefault ? nil : book.stableID
                        } label: {
                            Label(book.name, systemImage: selected ? "checkmark" : "book.closed")
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
        totalBudget: Decimal?,
        status: BudgetStatus?,
        hasDailyGuidance: Bool,
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
                    budget: totalBudget,
                    isCurrentMonth: Calendar.current.isDate(displayedMonth, equalTo: now, toGranularity: .month),
                    hasDailyGuidance: hasDailyGuidance,
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
    /// 今天有规则管时才画「今日可用」，否则退回「已用 %」圆环（与安卓一致）。
    let hasDailyGuidance: Bool
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

    /// 标明这个数是预算总额，第一次看的人不用猜（与 Android 对齐）。
    private var footerText: String {
        let amount = "预算 \(MoneyFormat.string(budget, currencyCode: currencyCode))"
        return isCurrentMonth ? "\(amount) · 剩 \(remainingDays) 天" : amount
    }

    /// 「月预算已超」已经表达了方向，金额不再带负号，避免双重否定。
    private var remainingText: String {
        let absolute = status.remaining < 0 ? -status.remaining : status.remaining
        return MoneyFormat.string(absolute, currencyCode: currencyCode)
    }

    /// 超支时条形按「已花」铺满，100% 预算线落在 预算/已花 处；未超支为 nil。
    private var overflowStart: Double? {
        BudgetOverflow.boundary(budget: budget, spent: status.spentThisMonth, isOver: status.isOverBudget)
    }

    var body: some View {
        // 圆环底边和左列最后一行（百分比标签那行）对齐：猫从卡片右上角探出，
        // 居中时圆环顶边会贴住猫脚、下方反而空一截。与 Android 对齐。
        HStack(alignment: .bottom, spacing: 12) {
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
                    metric(title: "收入", amount: summary.totalIncome, color: incomeColor(summary.totalIncome))
                    Divider().frame(height: 32).padding(.horizontal, 14)
                    metric(title: "支出", amount: summary.totalExpense, color: .primary)
                }

                BudgetGradientProgressBar(value: ratio, overflowStart: overflowStart)
                HStack {
                    Text(percentText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(status.isOverBudget ? Color.warning : Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            status.isOverBudget ? Color.warning.opacity(0.16) : Color.accentColor.opacity(0.10),
                            in: .rect(cornerRadius: 6)
                        )
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
                isCurrentMonth: isCurrentMonth && hasDailyGuidance,
                dailyAverage: HomeDailyAverage.expense(
                    summary.totalExpense,
                    year: summary.year,
                    month: summary.month,
                    isCurrentMonth: isCurrentMonth,
                    today: AppClock.now
                )
            )
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

/// 收入有数时才用收入绿；¥0 没必要用颜色强调，用次要灰（与 Android homeIncomeColor 对齐）。
private func incomeColor(_ income: Decimal) -> Color {
    income > 0 ? Color.income : Color.secondary
}

/// 超支分界线的共用计算，横条和圆环口径一致（与 Android home_summary_card 对齐）。
enum BudgetOverflow {
    /// 100% 预算线在「已花」整条中的位置（预算 / 已花，0~1）；未超支返回 nil。
    static func boundary(budget: Decimal, spent: Decimal, isOver: Bool) -> Double? {
        guard isOver, budget > 0, spent > budget else { return nil }
        return min(max(MoneyFormat.double(budget) / MoneyFormat.double(spent), 0), 1)
    }

    /// 分界线颜色：接近卡片底色的细线，在任意填充色上都能看清。
    static let boundaryColor = Color(uiColor: .systemBackground).opacity(0.92)
}

/// 预算进度条：主页和预算页共用（同类同设计）。
struct BudgetGradientProgressBar: View {
    let value: Double
    /// 非 nil 时进入超支模式：整条 = 已花，分界线左侧浅橙是预算内的 100%，右侧实橙是超出部分。
    var overflowStart: Double? = nil

    private static let gradient = LinearGradient(
        colors: [
            Color.budgetHealthy,
            Color(red: 0.90, green: 0.69, blue: 0.20),
            Color.warning,
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    private var accessibilityPercent: String {
        if let start = overflowStart, start > 0, start < 1 {
            return "\(Int((100 / start).rounded()))%"
        }
        return "\(Int(min(max(value, 0), 1) * 100))%"
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            if let start = overflowStart, start < 1 {
                let split = width * min(max(start, 0), 1)
                ZStack(alignment: .leading) {
                    // 两段不重叠：左段浅橙（预算内 100%），右段实橙（超出）。
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.overspendWithin)
                            .frame(width: split)
                        Rectangle()
                            .fill(Color.warning)
                    }
                    // 100% 分界线
                    Rectangle()
                        .fill(BudgetOverflow.boundaryColor)
                        .frame(width: 2)
                        .offset(x: min(max(split - 1, 0), max(0, width - 2)))
                }
                .clipShape(Capsule())
            } else {
                let clamped = min(max(value, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(Self.gradient)
                        .frame(width: width * clamped)
                }
            }
        }
        .frame(height: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("预算进度")
        .accessibilityValue(accessibilityPercent)
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
                metric(title: "收入", amount: summary.totalIncome, color: incomeColor(summary.totalIncome))
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

/// 主页圆环的「日均支出」（口径 D-STAT-013）：本月除以今天的日序，历史月除以该月完整天数。
/// 保留两位小数四舍五入（与 Android homeDailyAverageExpense 对齐）。
enum HomeDailyAverage {
    static func expense(
        _ expense: Decimal,
        year: Int,
        month: Int,
        isCurrentMonth: Bool,
        today: Date,
        calendar: Calendar = .current
    ) -> Decimal {
        let days: Int
        if isCurrentMonth {
            days = calendar.component(.day, from: today)
        } else {
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))
            days = start.flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 0
        }
        guard days > 0, expense > 0 else { return 0 }
        var raw = expense / Decimal(days)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return rounded
    }
}

private struct TodayAllowanceRing: View {
    let status: BudgetStatus
    let currencyCode: String
    let isCurrentMonth: Bool
    /// 历史月圆环中间显示的日均支出。
    let dailyAverage: Decimal

    private static let lineWidth: CGFloat = 7

    /// 今日已超：负的「可用」没有意义，封底为 0。
    private var todayOver: Bool { isCurrentMonth && status.todayAllowance < 0 }

    /// 月预算已经超了：往后每天的「可用」都封底 ¥0，没有信息量，改显示「今日已花」。
    private var monthOver: Bool { todayOver && status.isOverBudget }

    /// 超支模式下预算内部分占整圈的比例；nil 表示正常圆环。
    ///
    /// 当月：整圈 = 今天已花，今天的日额度（spentToday + todayAllowance）以内是浅橙，
    /// 之后实橙是超出部分；日额度 ≤ 0（今天开始前就已超）时整圈都是超出。
    /// 月初就超了但今天还没花：没有「今天超出」可画，返回 nil 走普通圆环（只留浅橙底圈）。
    /// 历史月：和横条同一套 预算/已花 分界。与 Android home_summary_card 对齐。
    private var overflowWithin: Double? {
        if isCurrentMonth {
            guard todayOver, status.spentToday > 0 else { return nil }
            let dayBase = status.spentToday + status.todayAllowance
            guard dayBase > 0 else { return 0 }
            return min(max(MoneyFormat.double(dayBase) / MoneyFormat.double(status.spentToday), 0), 1)
        }
        return BudgetOverflow.boundary(
            budget: status.monthlyBudget,
            spent: status.spentThisMonth,
            isOver: status.isOverBudget
        )
    }

    private var usedRatio: Double {
        status.monthlyBudget > 0
            ? MoneyFormat.double(status.spentThisMonth) / MoneyFormat.double(status.monthlyBudget)
            : 0
    }

    private var value: Double {
        guard isCurrentMonth else { return min(max(usedRatio, 0), 1) }
        if todayOver { return 0 }
        let envelope = status.spentToday + status.todayAllowance
        return envelope > 0
            ? min(max(MoneyFormat.double(status.todayAllowance) / MoneyFormat.double(envelope), 0), 1)
            : 1
    }

    private var ringColor: Color {
        todayOver || (!isCurrentMonth && status.isOverBudget) ? Color.warning : Color.budgetHealthy
    }

    private var label: String {
        guard isCurrentMonth else { return "日均支出" }
        return monthOver ? "今日已花" : "今日可用"
    }

    /// 历史月不再写「已用 %」，那个数左边百分比标签已经有了。
    private var amountText: String {
        guard isCurrentMonth else {
            return MoneyFormat.string(dailyAverage, currencyCode: currencyCode)
        }
        if monthOver {
            return MoneyFormat.string(status.spentToday, currencyCode: currencyCode)
        }
        return MoneyFormat.string(todayOver ? 0 : status.todayAllowance, currencyCode: currencyCode)
    }

    var body: some View {
        ZStack {
            if let within = overflowWithin {
                overflowRing(within: within)
            } else {
                Circle()
                    .stroke(ringColor.opacity(0.18), lineWidth: Self.lineWidth)
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(amountText)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: 62)
        }
        .frame(width: 80, height: 80)
    }

    /// 12 点起顺时针的预算内浅橙弧 + 其余实橙超出弧 + 100% 分界线（两段不重叠）。
    @ViewBuilder
    private func overflowRing(within: Double) -> some View {
        Circle()
            .trim(from: within, to: 1)
            .stroke(Color.warning, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))
        if within > 0 {
            Circle()
                .trim(from: 0, to: within)
                .stroke(
                    Color.overspendWithin,
                    style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .butt)
                )
                .rotationEffect(.degrees(-90))
            // 分界线：先放在 12 点的环上，再绕圆心顺时针转到分界角度。
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                Rectangle()
                    .fill(BudgetOverflow.boundaryColor)
                    .frame(width: 2, height: Self.lineWidth + 2)
                    // Circle.stroke 以内切圆路径为中心线（半径 = side/2），分界线也居中在这条线上。
                    .position(x: proxy.size.width / 2, y: (proxy.size.height - side) / 2)
                    .rotationEffect(.degrees(360 * within))
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
    @State private var showAddSheet = false
    /// [+] 面板选好的附件；面板收起后再带着它打开 AI 记账。
    @State private var pickedAttachments: [AIChatAttachment] = []
    @State private var attachmentEntry: AttachmentEntry?
    @State private var attachmentMessage: String?
    @Namespace private var glassNamespace

    /// 带附件打开 AI 记账的一次请求（手动记账看不了图，带附件一律进 AI）。
    private struct AttachmentEntry: Identifiable {
        let id = UUID()
        let attachments: [AIChatAttachment]
    }

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
                    // 和喵助手同一张「添加到聊天」面板（对齐安卓 record_input_bar）。
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .liquidGlassCircleControl()
                    .glassEffectID("entry-add", in: glassNamespace)
                    .accessibilityLabel("添加到聊天")

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
        .sheet(isPresented: $showAddSheet, onDismiss: {
            guard !pickedAttachments.isEmpty else { return }
            attachmentEntry = AttachmentEntry(attachments: pickedAttachments)
            pickedAttachments = []
        }) {
            ChatAddSheet(existing: []) { added, message in
                pickedAttachments = added
                if let message {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        attachmentMessage = message
                    }
                }
            }
        }
        .sheet(item: $attachmentEntry) { entry in
            AIQuickEntryView(initialAttachments: entry.attachments)
                .presentationDetents([.large])
        }
        .alert("添加附件", isPresented: Binding(
            get: { attachmentMessage != nil },
            set: { if !$0 { attachmentMessage = nil } }
        )) {
            Button("好") { attachmentMessage = nil }
        } message: {
            Text(attachmentMessage ?? "")
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
