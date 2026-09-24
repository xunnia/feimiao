import UIKit
import SwiftUI
import SwiftData
import Charts
import QingJiCore

/// 统计页：周 / 月 / 年 / 自定义四种时间维度。
///
/// 展示层只负责选择时间和绘图，金额、退款折叠和“不计入收支”过滤全部交给
/// QingJiCore 的 StatisticsEngine，保证 iOS 与 Android 共用同一账务口径。
struct MonthlyStatsView: View {
    private typealias Scope = AppRouter.StatsScope

    @Environment(AppRouter.self) private var router
    @Query private var transactions: [MoneyTransaction]
    @Query private var budgets: [Budget]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]

    @State private var displayedMonth = AppClock.now
    @State private var weekStart = Calendar.current.startOfDay(for: AppClock.now)
    @State private var customStartDate = Calendar.current.startOfDay(for: AppClock.now)
    @State private var customEndDate = Calendar.current.startOfDay(for: AppClock.now)
    @AppStorage("qingji.stats.custom.start") private var savedCustomStart: Double = 0
    @AppStorage("qingji.stats.custom.end") private var savedCustomEnd: Double = 0
    @State private var projectionCache = IOSLedgerProjectionCache()
    @State private var statisticsCache = IOSStatisticsProjectionCache()
    @State private var selectedCategory: CategoryDrillDown?
    @State private var trendShowsIncome = false

    private struct CategoryDrillDown: Identifiable, Hashable {
        var id: String { "\(title):\(names.sorted().joined(separator: ",")):\(start.timeIntervalSince1970):\(end.timeIntervalSince1970)" }
        let title: String
        let names: Set<String>
        let start: Date
        let end: Date
    }

    static func demoCategoryDrillDown(environment: [String: String], now: Date) -> (name: String, start: Date, end: Date)? {
        guard environment["QINGJI_DEMO"] == "1",
              environment["QINGJI_SCREEN"] == "stats/custom/category-detail" else { return nil }
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
            ?? calendar.startOfDay(for: now)
        return ("食品餐饮", start, calendar.startOfDay(for: now))
    }

    static func demoMonthRing(environment: [String: String]) -> Bool {
        environment["QINGJI_DEMO"] == "1" && environment["QINGJI_SCREEN"] == "stats/month/ring"
    }

    static func demoMonthTrend(environment: [String: String]) -> Bool {
        environment["QINGJI_DEMO"] == "1" &&
            ["stats/month/trend", "stats/month/trend/income"].contains(environment["QINGJI_SCREEN"])
    }

    static func demoMonthTrendIncome(environment: [String: String]) -> Bool {
        environment["QINGJI_DEMO"] == "1" &&
            environment["QINGJI_SCREEN"] == "stats/month/trend/income"
    }

    var body: some View {
        @Bindable var router = router
        let snapshot = projectionCache.snapshot(
            for: transactions,
            selectedBookID: router.selectedBookID
        )

        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 20) {
                    Picker("范围", selection: $router.statsScope) {
                        Text("周").tag(Scope.week)
                        Text("月").tag(Scope.month)
                        Text("年").tag(Scope.year)
                        Text("自定义").tag(Scope.custom)
                    }
                    .pickerStyle(.segmented)

                    switch router.statsScope {
                    case .week:
                        weekContent(snapshot: snapshot)
                    case .month:
                        monthContent(snapshot: snapshot)
                    case .year:
                        yearContent(snapshot: snapshot)
                    case .custom:
                        customContent(snapshot: snapshot)
                    }
                }
                .padding()
            }
            .task(id: transactions.count) {
                let environment = ProcessInfo.processInfo.environment
                if Self.demoMonthRing(environment: environment) || Self.demoMonthTrend(environment: environment) {
                    if Self.demoMonthTrendIncome(environment: environment) {
                        trendShowsIncome = true
                    }
                    try? await Task.sleep(for: .seconds(2))
                    scroll.scrollTo(Self.demoMonthTrend(environment: environment)
                                    ? "stats-month-trend" : "stats-month-ring", anchor: .top)
                }
            }
        }
        .liquidGlassCanvas()
        .navigationTitle("统计")
        .onAppear(perform: restoreDateSelections)
        .task {
            if let demo = Self.demoCategoryDrillDown(environment: ProcessInfo.processInfo.environment,
                                                     now: AppClock.now) {
                selectedCategory = CategoryDrillDown(title: demo.name, names: [demo.name],
                                                     start: demo.start, end: demo.end)
            }
        }
        .navigationDestination(item: $selectedCategory) { selection in
            CategoryTransactionsView(title: selection.title, categoryNames: selection.names,
                                     start: selection.start, end: selection.end)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .liquidGlassCircleControl(size: 44)
            Spacer()
            Text(displayedMonth, format: .dateTime.year().month())
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .liquidGlassCircleControl(size: 44)
            .disabled(Calendar.current.isDate(displayedMonth, equalTo: AppClock.now, toGranularity: .month))
        }
    }

    private var weekHeader: some View {
        HStack {
            Button {
                shiftWeek(by: -7)
            } label: {
                Image(systemName: "chevron.left")
            }
            .liquidGlassCircleControl(size: 44)
            Spacer()
            Text(Self.weekRangeLabel(start: weekStart, end: weekEnd))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Button {
                shiftWeek(by: 7)
            } label: {
                Image(systemName: "chevron.right")
            }
            .liquidGlassCircleControl(size: 44)
            .disabled(weekEnd >= Calendar.current.startOfDay(for: AppClock.now))
        }
    }

    private var yearHeader: some View {
        HStack {
            Button {
                shiftYear(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .liquidGlassCircleControl(size: 44)
            Spacer()
            Text(displayedMonth, format: .dateTime.year())
                .font(.headline)
            Spacer()
            Button {
                shiftYear(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .liquidGlassCircleControl(size: 44)
            .disabled(Calendar.current.component(.year, from: displayedMonth) >= Calendar.current.component(.year, from: AppClock.now))
        }
    }

    private var customHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                DatePicker("开始日期", selection: $customStartDate, in: ...AppClock.now, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accessibilityLabel("开始日期")
                Text("–").foregroundStyle(.secondary)
                DatePicker("结束日期", selection: $customEndDate, in: customStartDate...AppClock.now, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accessibilityLabel("结束日期")
            }
            VStack(alignment: .leading, spacing: 8) {
                DatePicker("开始日期", selection: $customStartDate, in: ...AppClock.now, displayedComponents: .date)
                DatePicker("结束日期", selection: $customEndDate, in: customStartDate...AppClock.now, displayedComponents: .date)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .onChange(of: customStartDate) { _, newValue in
            customStartDate = Calendar.current.startOfDay(for: newValue)
            if customEndDate < customStartDate {
                customEndDate = customStartDate
            }
            persistCustomRange()
        }
        .onChange(of: customEndDate) { _, newValue in
            customEndDate = Calendar.current.startOfDay(for: newValue)
            if customEndDate < customStartDate {
                customEndDate = customStartDate
            }
            persistCustomRange()
        }
    }

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    }

    static func weekRangeLabel(start: Date, end: Date, calendar: Calendar = .current) -> String {
        func monthDay(_ date: Date) -> String {
            let parts = calendar.dateComponents([.month, .day], from: date)
            return "\(parts.month ?? 1)月\(parts.day ?? 1)日"
        }
        return "\(monthDay(start)) – \(monthDay(end))"
    }

    static func trendAxisDates(_ days: [PeriodDailyTotal]) -> [Date] {
        let step = max(2, Int(ceil(Double(days.count - 1) / 4)))
        return stride(from: step, to: days.count - 1, by: step).map { days[$0].date }
    }

    private func weekContent(snapshot: IOSLedgerSnapshot) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: AppClock.now)
        let isCurrentWeek = today >= weekStart && today <= weekEnd
        let previousStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let elapsedDays = calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0
        let previousEnd = calendar.date(byAdding: .day,
                                        value: isCurrentWeek ? min(max(elapsedDays, 0), 6) : 6,
                                        to: previousStart) ?? previousStart
        let summary = statisticsCache.period(
            of: snapshot.records,
            revision: snapshot.revision,
            start: weekStart,
            end: weekEnd
        )
        let previous = statisticsCache.period(
            of: snapshot.records,
            revision: snapshot.revision,
            start: previousStart,
            end: previousEnd
        )
        return VStack(spacing: 20) {
            weekHeader
            periodTotals(summary, currencyCode: snapshot.scopedCurrencyCode,
                         label: isCurrentWeek ? "本周" : "该周", previous: previous)
            if summary.totalExpense == 0 && summary.totalIncome == 0 {
                emptyState(title: "这一周没有记录", systemImage: "chart.bar",
                           message: "换一周看看吧")
            } else if !summary.expenseByCategory.isEmpty {
                periodCategoryRing(summary.expenseByCategory, total: summary.totalExpense,
                                   currencyCode: snapshot.scopedCurrencyCode,
                                   totalLabel: "本周支出", start: weekStart, end: weekEnd)
                periodDailyBarChart(summary.dailyTotals)
                    .padding(14)
                    .liquidGlassSurface(cornerRadius: 18)
                categoryRanking(summary.expenseByCategory, currencyCode: snapshot.scopedCurrencyCode,
                                start: weekStart, end: weekEnd)
                    .padding(14)
                    .liquidGlassSurface(cornerRadius: 18)
            }
        }
    }

    private func monthContent(snapshot: IOSLedgerSnapshot) -> some View {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        let monthStart = calendar.date(from: components) ?? calendar.startOfDay(for: displayedMonth)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? monthStart
        let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let previousEnd = Self.previousMonthComparisonEnd(for: displayedMonth, now: AppClock.now,
                                                          calendar: calendar)
        let summary = statisticsCache.monthly(
            of: snapshot.records,
            revision: snapshot.revision,
            year: components.year ?? 2026,
            month: components.month ?? 1
        )
        let previousComponents = calendar.dateComponents([.year, .month], from: previousStart)
        let previousMonth = statisticsCache.monthly(
            of: snapshot.records,
            revision: snapshot.revision,
            year: previousComponents.year ?? 2026,
            month: previousComponents.month ?? 1
        )
        let period = statisticsCache.period(
            of: snapshot.records, revision: snapshot.revision,
            start: monthStart, end: monthEnd
        )
        let previous = statisticsCache.period(
            of: snapshot.records, revision: snapshot.revision,
            start: previousStart, end: previousEnd
        )
        let budget = BudgetStore.effectiveTotalBudget(
            from: budgets,
            selectedBookID: router.selectedBookID,
            fallbackBookID: books.first(where: \.isDefault)?.stableID
        )
        return VStack(spacing: 20) {
            monthHeader
            periodTotals(period, currencyCode: snapshot.scopedCurrencyCode,
                         label: "\(components.month ?? 1)月", previous: previous)
            if let budget {
                budgetProgress(
                    budget,
                    records: snapshot.records,
                    revision: snapshot.revision,
                    currencyCode: snapshot.scopedCurrencyCode
                )
            }
            monthlyContent(summary: summary, previousMonth: previousMonth,
                           currencyCode: snapshot.scopedCurrencyCode,
                           start: monthStart, end: monthEnd)
        }
    }

    static func previousMonthComparisonEnd(for displayedMonth: Date, now: Date,
                                           calendar: Calendar = .current) -> Date {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
            ?? calendar.startOfDay(for: displayedMonth)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let previousDays = calendar.range(of: .day, in: .month, for: previousStart)?.count ?? 28
        let isCurrentMonth = calendar.isDate(displayedMonth, equalTo: now, toGranularity: .month)
        let cutoff = isCurrentMonth ? min(calendar.component(.day, from: now), previousDays) : previousDays
        return calendar.date(byAdding: .day, value: max(cutoff, 1) - 1, to: previousStart)
            ?? previousStart
    }

    private func yearContent(snapshot: IOSLedgerSnapshot) -> some View {
        let summary = statisticsCache.yearly(
            of: snapshot.records,
            revision: snapshot.revision,
            year: Calendar.current.component(.year, from: displayedMonth)
        )
        return VStack(spacing: 20) {
            yearHeader
            yearlyContent(summary: summary, currencyCode: snapshot.scopedCurrencyCode)
        }
    }

    private func customContent(snapshot: IOSLedgerSnapshot) -> some View {
        let summary = statisticsCache.period(
            of: snapshot.records,
            revision: snapshot.revision,
            start: customStartDate,
            end: customEndDate
        )
        return VStack(spacing: 20) {
            customHeader
            periodTotals(summary, currencyCode: snapshot.scopedCurrencyCode, label: "区间")
            if summary.expenseByCategory.isEmpty {
                emptyState(title: "这个区间还没有支出", systemImage: "chart.pie", message: "记几笔之后这里会出现分析图表")
            } else {
                periodCategoryRing(summary.expenseByCategory, total: summary.totalExpense,
                                   currencyCode: snapshot.scopedCurrencyCode,
                                   totalLabel: "期间支出", start: customStartDate, end: customEndDate)
                categoryRanking(summary.expenseByCategory, currencyCode: snapshot.scopedCurrencyCode,
                                start: customStartDate, end: customEndDate)
            }
        }
    }

    private let statisticsAccent = Color(red: 0.49, green: 0.55, blue: 0.62)
    private let statisticsIncome = Color(red: 0.73, green: 0.56, blue: 0.32)

    private func periodTotals(_ summary: PeriodSummary, currencyCode: String,
                              label: String, previous: PeriodSummary? = nil) -> some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("总支出 · \(label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let previous {
                        changeBadge(current: summary.totalExpense, previous: previous.totalExpense,
                                    goodWhenUp: false)
                    }
                }
                Text(MoneyFormat.string(summary.totalExpense, currencyCode: currencyCode))
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if summary.dailyTotals.contains(where: { $0.expense > 0 }) {
                    Chart(summary.dailyTotals, id: \.date) { item in
                        LineMark(x: .value("日期", item.date),
                                 y: .value("支出", MoneyFormat.double(item.expense)))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(statisticsAccent)
                    }
                    .chartLegend(.hidden)
                    .chartXAxis {
                        AxisMarks(values: Self.trendAxisDates(summary.dailyTotals)) {
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        }
                    }
                    .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                    .frame(height: 128)
                    .padding(.top, 10)
                    .accessibilityLabel("每日支出趋势")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .liquidGlassSurface(cornerRadius: 18)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    customMiniTotal("收入", amount: summary.totalIncome, currencyCode: currencyCode,
                                    values: summary.dailyTotals.map { MoneyFormat.double($0.income) },
                                    color: statisticsIncome, previous: previous?.totalIncome)
                    customMiniTotal("结余", amount: summary.balance, currencyCode: currencyCode,
                                    values: Self.runningBalances(summary.dailyTotals),
                                    color: statisticsAccent, previous: previous?.balance)
                }
                VStack(spacing: 8) {
                    totalCard(title: "收入", amount: summary.totalIncome, color: .primary, currencyCode: currencyCode)
                    totalCard(title: "结余", amount: summary.balance, color: .primary, currencyCode: currencyCode)
                }
            }
        }
    }

    static func runningBalances(_ days: [PeriodDailyTotal]) -> [Double] {
        var balance = Decimal.zero
        return days.map { day in
            balance += day.income - day.expense
            return MoneyFormat.double(balance)
        }
    }

    private func customMiniTotal(_ title: LocalizedStringKey, amount: Decimal,
                                 currencyCode: String, values: [Double], color: Color,
                                 previous: Decimal? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(MoneyFormat.string(amount, currencyCode: currencyCode))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(alignment: .bottom) {
                if let previous {
                    changeBadge(current: amount, previous: previous, goodWhenUp: true)
                }
                Spacer(minLength: 4)
                if values.contains(where: { $0 != 0 }) {
                    Chart(Array(values.enumerated()), id: \.offset) { index, value in
                        LineMark(x: .value("日序", index), y: .value("金额", value))
                            .foregroundStyle(color)
                            .interpolationMethod(.monotone)
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
                    .frame(width: 64, height: 26)
                    .accessibilityHidden(true)
                }
            }
            .frame(height: 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .liquidGlassSurface(cornerRadius: 18)
    }

    static func percentChange(current: Decimal, previous: Decimal) -> Double? {
        let base = NSDecimalNumber(decimal: previous).doubleValue
        guard base != 0 else { return nil }
        let value = (NSDecimalNumber(decimal: current).doubleValue - base) / abs(base) * 100
        guard value.isFinite, abs(value) >= 0.05 else { return nil }
        return value
    }

    static func percentChangeLabel(current: Decimal, previous: Decimal) -> String? {
        guard let percent = percentChange(current: current, previous: previous) else { return nil }
        let magnitude = abs(percent)
        let formatted = String(format: magnitude >= 10 ? "%.0f" : "%.1f", magnitude)
        return "\(percent > 0 ? "↑" : "↓") \(formatted)%"
    }

    @ViewBuilder
    private func changeBadge(current: Decimal, previous: Decimal, goodWhenUp: Bool) -> some View {
        if let percent = Self.percentChange(current: current, previous: previous),
           let label = Self.percentChangeLabel(current: current, previous: previous) {
            Text(label)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle((percent > 0) == goodWhenUp
                                 ? Color(red: 52 / 255, green: 168 / 255, blue: 83 / 255)
                                 : Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255))
        }
    }

    private func monthlyContent(summary: MonthlySummary, previousMonth: MonthlySummary,
                                currencyCode: String,
                                start: Date, end: Date) -> some View {
        Group {
            if summary.expenseByCategory.isEmpty {
                emptyState(title: "本月还没有支出", systemImage: "chart.pie", message: "记几笔之后这里会出现分析图表")
            } else {
                periodCategoryRing(summary.expenseByCategory, total: summary.totalExpense,
                                   currencyCode: currencyCode, totalLabel: "本月支出",
                                   start: start, end: end)
                    .id("stats-month-ring")
                monthlyTrendChart(summary, previousMonth: previousMonth)
                    .id("stats-month-trend")
                categoryRanking(summary.expenseByCategory, currencyCode: currencyCode,
                                start: start, end: end)
                    .padding(14)
                    .liquidGlassSurface(cornerRadius: 18)
            }
        }
    }

    private func totalsCards(
        expense: Decimal,
        income: Decimal,
        balance: Decimal,
        currencyCode: String
    ) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                totalCard(title: "支出", amount: expense, color: Color.expense, currencyCode: currencyCode)
                totalCard(title: "收入", amount: income, color: Color.income, currencyCode: currencyCode)
                totalCard(title: "结余", amount: balance, color: balance >= 0 ? Color.income : Color.warning, currencyCode: currencyCode)
            }
        }
    }

    private func totalCard(
        title: LocalizedStringKey,
        amount: Decimal,
        color: Color,
        currencyCode: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MoneyFormat.string(amount, currencyCode: currencyCode))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private static let ringColors: [Color] = [
        Color(red: 125 / 255, green: 139 / 255, blue: 155 / 255),
        Color(red: 242 / 255, green: 178 / 255, blue: 60 / 255),
        Color(red: 244 / 255, green: 169 / 255, blue: 184 / 255),
        Color(red: 255 / 255, green: 159 / 255, blue: 104 / 255),
        Color(red: 143 / 255, green: 191 / 255, blue: 159 / 255),
        Color(red: 155 / 255, green: 183 / 255, blue: 212 / 255),
    ]

    static func condensedRingCategories(_ categories: [CategoryTotal]) -> [CategoryTotal] {
        let positive = categories.filter { $0.total > 0 }
        guard positive.count > 6 else { return positive }
        let rest = positive.dropFirst(5)
        return Array(positive.prefix(5)) + [CategoryTotal(
            name: "更多",
            total: rest.reduce(Decimal.zero) { $0 + $1.total },
            share: rest.reduce(0) { $0 + $1.share },
            count: rest.reduce(0) { $0 + $1.count }
        )]
    }

    private func periodCategoryRing(_ categories: [CategoryTotal], total: Decimal,
                                    currencyCode: String, totalLabel: String,
                                    start: Date, end: Date) -> some View {
        let items = Self.condensedRingCategories(categories)
        return VStack(alignment: .leading, spacing: 12) {
            Text("支出构成").font(.headline)
            GeometryReader { geometry in
                let chartWidth = min(144, geometry.size.width * 0.48)
                HStack(spacing: 10) {
                    ringChart(items, total: total, currencyCode: currencyCode,
                              totalLabel: totalLabel, width: chartWidth)
                    ringLegend(items, allCategories: categories, currencyCode: currencyCode,
                               start: start, end: end)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 156)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassSurface(cornerRadius: 18)
    }

    private func ringChart(_ items: [CategoryTotal], total: Decimal,
                           currencyCode: String, totalLabel: String,
                           width: CGFloat) -> some View {
        ZStack {
            if !items.isEmpty {
                Chart(Array(items.enumerated()), id: \.offset) { index, item in
                    SectorMark(angle: .value("金额", MoneyFormat.double(item.total)),
                               innerRadius: .ratio(0.70), angularInset: 2)
                        .foregroundStyle(Self.ringColors[index % Self.ringColors.count])
                }
                .chartLegend(.hidden)
            }
            VStack(spacing: 2) {
                Text(totalLabel).font(.caption2).foregroundStyle(.secondary)
                Text(MoneyFormat.string(total, currencyCode: currencyCode))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.55)
            }
            .padding(.horizontal, 18)
            .accessibilityHidden(true)
        }
        .frame(width: width, height: 156)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("支出构成，\(totalLabel) \(MoneyFormat.string(total, currencyCode: currencyCode))")
    }

    private func ringLegend(_ items: [CategoryTotal], allCategories: [CategoryTotal],
                            currencyCode: String, start: Date, end: Date) -> some View {
        let moreNames = Set(allCategories.filter { $0.total > 0 }.dropFirst(5).map(\.name))
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    let isMore = allCategories.filter { $0.total > 0 }.count > 6 && index == items.count - 1
                    let names: Set<String> = isMore ? moreNames : [item.name]
                    selectedCategory = CategoryDrillDown(title: item.name, names: names,
                                                         start: start, end: end)
                } label: {
                    HStack(spacing: 3) {
                        Circle().fill(Self.ringColors[index % Self.ringColors.count])
                            .frame(width: 9, height: 9)
                        Text(item.name).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        Text(item.share.formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(.secondary)
                        Text(MoneyFormat.string(item.total, currencyCode: currencyCode))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Image(systemName: "chevron.right").font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(item.name)支出明细")
            }
        }
    }

    private func monthlyTrendChart(_ summary: MonthlySummary,
                                   previousMonth: MonthlySummary) -> some View {
        let color = trendShowsIncome
            ? Color(red: 242 / 255, green: 178 / 255, blue: 60 / 255)
            : Color.primary
        let scale = Self.monthlyTrendScale(current: summary.dailyTotals,
                                           previous: previousMonth.dailyTotals,
                                           showsIncome: trendShowsIncome)
        let calendar = Calendar.current
        let now = AppClock.now
        let isCurrentMonth = summary.year == calendar.component(.year, from: now) &&
            summary.month == calendar.component(.month, from: now)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("每日趋势").font(.headline)
                Spacer()
                Picker("收支类型", selection: $trendShowsIncome) {
                    Text("支出").tag(false)
                    Text("收入").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 112)
            }
            HStack(spacing: 12) {
                Label("本月\(trendShowsIncome ? "收入" : "支出")", systemImage: "circle.fill")
                    .foregroundStyle(color)
                Text("- - 上月同期").foregroundStyle(color.opacity(0.5))
            }
            .font(.caption2)
            Chart {
                if isCurrentMonth {
                    RuleMark(x: .value("今天", calendar.component(.day, from: now)))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                ForEach(previousMonth.dailyTotals, id: \.day) { item in
                    LineMark(
                        x: .value("日", item.day),
                        y: .value("金额", max(0, MoneyFormat.double(trendShowsIncome ? item.income : item.expense))),
                        series: .value("周期", "上月")
                    )
                    .foregroundStyle(color.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.monotone)
                }
                ForEach(summary.dailyTotals, id: \.day) { item in
                    LineMark(
                        x: .value("日", item.day),
                        y: .value("金额", max(0, MoneyFormat.double(trendShowsIncome ? item.income : item.expense))),
                        series: .value("周期", "本月")
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                }
            }
            .chartLegend(.hidden)
            .chartXScale(domain: 0...(summary.dailyTotals.count + 1))
            .chartXAxis {
                AxisMarks(values: [1, 5, 10, 15, 20, 25, 30].filter {
                    $0 <= summary.dailyTotals.count
                }) { AxisValueLabel() }
            }
            .chartYScale(domain: 0.0...scale.upper)
            .chartYAxis {
                AxisMarks(position: .leading,
                          values: Array(stride(from: scale.step, through: scale.upper, by: scale.step))) { axis in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                    AxisValueLabel {
                        if let amount = axis.as(Double.self) {
                            Text(Self.monthlyTrendAxisLabel(amount))
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassSurface(cornerRadius: 18)
    }

    static func monthlyTrendScale(current: [DailyTotal], previous: [DailyTotal],
                                  showsIncome: Bool) -> (step: Double, upper: Double) {
        let values = (current + previous).map {
            max(0, MoneyFormat.double(showsIncome ? $0.income : $0.expense))
        }
        let maximum = values.max() ?? 0
        if maximum <= 0 { return (1, 1) }
        let rough = maximum / 3
        let magnitude = pow(10, floor(log10(rough)))
        let normalized = rough / magnitude
        let step = (normalized <= 1 ? 1.0 : normalized <= 2 ? 2.0 : normalized <= 5 ? 5.0 : 10.0) * magnitude
        return (step, (floor(maximum / step) + 1) * step)
    }

    static func monthlyTrendAxisLabel(_ value: Double) -> String {
        if value >= 10_000 { return String(format: "¥%.1f万", value / 10_000) }
        return "¥\(Int(value).formatted(.number.grouping(.automatic)))"
    }

    private func periodDailyBarChart(_ dailyTotals: [PeriodDailyTotal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每日支出")
                .font(.headline)
            Chart(dailyTotals, id: \.date) { item in
                BarMark(
                    x: .value("日", item.date, unit: .day),
                    y: .value("支出", MoneyFormat.double(item.expense))
                )
                .foregroundStyle(statisticsAccent.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day))
            }
            .frame(height: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryRanking(_ categories: [CategoryTotal], currencyCode: String,
                                 start: Date? = nil, end: Date? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类排行")
                .font(.headline)
            ForEach(categories.prefix(5), id: \.name) { item in
                let seed = CategorySeed.all.first { $0.nameZh == item.name }
                Group {
                    if let start, let end {
                        Button {
                            selectedCategory = CategoryDrillDown(title: item.name, names: [item.name],
                                                                 start: start, end: end)
                        } label: {
                            rankingRow(item, seed: seed, currencyCode: currencyCode, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看\(item.name)支出明细")
                    } else {
                        rankingRow(item, seed: seed, currencyCode: currencyCode, showsChevron: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rankingRow(_ item: CategoryTotal, seed: CategorySeed?,
                            currencyCode: String, showsChevron: Bool) -> some View {
        VStack(spacing: 4) {
            HStack {
                CategoryIcon(categoryKey: seed?.key ?? "", emoji: seed?.emoji ?? "🏷️", size: 28)
                    .accessibilityHidden(true)
                Text(item.name).font(.subheadline).lineLimit(1)
                Text("\(item.count) 笔").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(MoneyFormat.string(item.total, currencyCode: currencyCode))
                    .font(.subheadline.monospacedDigit())
                Text(item.share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                if showsChevron {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(max(item.share, 0), 1))
                .tint(.secondary)
        }
    }

    /// 月度预算执行条 + 今日可花。
    private func budgetProgress(
        _ budget: Budget,
        records: [TransactionRecord],
        revision: IOSLedgerDataRevision,
        currencyCode: String
    ) -> some View {
        let status = statisticsCache.status(
            for: budget,
            records: records,
            revision: revision,
            referenceDate: displayedMonth
        )
        let ratio = min(MoneyFormat.double(status.spentThisMonth) / max(MoneyFormat.double(budget.amount), 0.01), 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本月预算")
                    .font(.headline)
                Spacer()
                Text("\(MoneyFormat.string(status.spentThisMonth, currencyCode: currencyCode)) / \(MoneyFormat.string(budget.amount, currencyCode: currencyCode))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(status.isOverBudget ? Color.warning : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ProgressView(value: ratio)
                .tint(status.isOverBudget ? Color.warning : .accentColor)
            if Calendar.current.isDate(displayedMonth, equalTo: AppClock.now, toGranularity: .month) {
                Text(status.todayAllowance >= 0
                     ? "今日还可以花 \(MoneyFormat.string(status.todayAllowance, currencyCode: currencyCode))"
                     : "今日已超出节奏 \(MoneyFormat.string(-status.todayAllowance, currencyCode: currencyCode))，缓一缓")
                    .font(.footnote)
                    .foregroundStyle(status.todayAllowance >= 0 ? Color.secondary : Color.warning)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func yearlyContent(summary: YearlySummary, currencyCode: String) -> some View {
        VStack(spacing: 20) {
            totalsCards(
                expense: summary.totalExpense,
                income: summary.totalIncome,
                balance: summary.balance,
                currencyCode: currencyCode
            )
            if summary.totalExpense == 0 && summary.totalIncome == 0 {
                emptyState(title: "今年还没有账目", systemImage: "chart.bar", message: "记几笔之后这里会出现年度报告")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("每月支出")
                        .font(.headline)
                    Chart(Array(summary.monthlyExpenses.enumerated()), id: \.offset) { index, amount in
                        BarMark(
                            x: .value("月", index + 1),
                            y: .value("支出", MoneyFormat.double(amount))
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                    .chartXAxis {
                        AxisMarks(values: Array(1...12))
                    }
                    .frame(height: 160)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                categoryRanking(summary.expenseByCategory, currencyCode: currencyCode)
            }
        }
    }

    private func emptyState(title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .padding(.top, 40)
    }

    private func shiftMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func shiftWeek(by value: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: value, to: weekStart) else { return }
        weekStart = monday(of: newDate)
    }

    private func shiftYear(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .year, value: value, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func restoreDateSelections() {
        weekStart = monday(of: AppClock.now)
        if savedCustomStart > 0 {
            customStartDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: savedCustomStart))
        } else {
            let now = AppClock.now
            customStartDate = Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month], from: now)
            ) ?? Calendar.current.startOfDay(for: now)
        }
        if savedCustomEnd > 0 {
            customEndDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: savedCustomEnd))
        } else {
            customEndDate = Calendar.current.startOfDay(for: AppClock.now)
        }
        if customEndDate < customStartDate {
            customEndDate = customStartDate
        }
    }

    private func persistCustomRange() {
        savedCustomStart = customStartDate.timeIntervalSince1970
        savedCustomEnd = customEndDate.timeIntervalSince1970
    }

    private func monday(of date: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: day) ?? day
    }
}
