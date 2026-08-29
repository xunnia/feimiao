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

    @State private var displayedMonth = AppClock.now
    @State private var weekStart = Calendar.current.startOfDay(for: AppClock.now)
    @State private var customStartDate = Calendar.current.startOfDay(for: AppClock.now)
    @State private var customEndDate = Calendar.current.startOfDay(for: AppClock.now)
    @AppStorage("qingji.stats.custom.start") private var savedCustomStart: Double = 0
    @AppStorage("qingji.stats.custom.end") private var savedCustomEnd: Double = 0
    @State private var projectionCache = IOSLedgerProjectionCache()
    @State private var statisticsCache = IOSStatisticsProjectionCache()

    var body: some View {
        @Bindable var router = router
        let snapshot = projectionCache.snapshot(
            for: transactions,
            selectedBookID: router.selectedBookID
        )

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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
            .onAppear(perform: restoreDateSelections)
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            Spacer()
            Text(displayedMonth, format: .dateTime.year().month())
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
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
            .buttonStyle(.bordered)
            Spacer()
            VStack(spacing: 2) {
                Text("本周")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(weekStart, format: .dateTime.month().day())
                Text(weekEnd, format: .dateTime.month().day())
                    .foregroundStyle(.secondary)
            }
            .font(.headline)
            Spacer()
            Button {
                shiftWeek(by: 7)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
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
            .buttonStyle(.bordered)
            Spacer()
            Text(displayedMonth, format: .dateTime.year())
                .font(.headline)
            Spacer()
            Button {
                shiftYear(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(Calendar.current.component(.year, from: displayedMonth) >= Calendar.current.component(.year, from: AppClock.now))
        }
    }

    private var customHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Label("开始", systemImage: "calendar")
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker("开始日期", selection: $customStartDate, in: ...AppClock.now, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            HStack {
                Label("结束", systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker("结束日期", selection: $customEndDate, in: customStartDate...AppClock.now, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
        }
        .font(.subheadline)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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

    private func weekContent(snapshot: IOSLedgerSnapshot) -> some View {
        let summary = statisticsCache.period(
            of: snapshot.records,
            revision: snapshot.revision,
            start: weekStart,
            end: Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        )
        return VStack(spacing: 20) {
            weekHeader
            periodContent(summary, currencyCode: snapshot.scopedCurrencyCode)
        }
    }

    private func monthContent(snapshot: IOSLedgerSnapshot) -> some View {
        let components = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        let summary = statisticsCache.monthly(
            of: snapshot.records,
            revision: snapshot.revision,
            year: components.year ?? 2026,
            month: components.month ?? 1
        )
        let budget = BudgetStore.effectiveTotalBudget(
            from: budgets,
            selectedBookID: router.selectedBookID
        )
        return VStack(spacing: 20) {
            monthHeader
            totalsCards(
                expense: summary.totalExpense,
                income: summary.totalIncome,
                balance: summary.balance,
                currencyCode: snapshot.scopedCurrencyCode
            )
            if let budget {
                budgetProgress(
                    budget,
                    records: snapshot.records,
                    revision: snapshot.revision,
                    currencyCode: snapshot.scopedCurrencyCode
                )
            }
            monthlyContent(summary: summary, currencyCode: snapshot.scopedCurrencyCode)
        }
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
            periodContent(summary, currencyCode: snapshot.scopedCurrencyCode)
        }
    }

    private func monthlyContent(summary: MonthlySummary, currencyCode: String) -> some View {
        Group {
            if summary.expenseByCategory.isEmpty {
                emptyState(title: "本月还没有支出", systemImage: "chart.pie", message: "记几笔之后这里会出现分析图表")
            } else {
                categoryPieChart(summary.expenseByCategory)
                monthlyDailyBarChart(summary)
                categoryRanking(summary.expenseByCategory, currencyCode: currencyCode)
            }
        }
    }

    private func periodContent(_ summary: PeriodSummary, currencyCode: String) -> some View {
        VStack(spacing: 20) {
            totalsCards(
                expense: summary.totalExpense,
                income: summary.totalIncome,
                balance: summary.balance,
                currencyCode: currencyCode
            )
            if summary.expenseByCategory.isEmpty {
                emptyState(title: "这个区间还没有支出", systemImage: "chart.pie", message: "记几笔之后这里会出现分析图表")
            } else {
                categoryPieChart(summary.expenseByCategory)
                periodDailyBarChart(summary.dailyTotals)
                categoryRanking(summary.expenseByCategory, currencyCode: currencyCode)
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

    private func categoryPieChart(_ categories: [CategoryTotal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("支出构成")
                .font(.headline)
            Chart(categories.prefix(8), id: \.name) { item in
                SectorMark(
                    angle: .value("金额", MoneyFormat.double(item.total)),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("分类", item.name))
                .cornerRadius(4)
            }
            .frame(height: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monthlyDailyBarChart(_ summary: MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每日支出")
                .font(.headline)
            Chart(summary.dailyTotals, id: \.day) { item in
                BarMark(
                    x: .value("日", item.day),
                    y: .value("支出", MoneyFormat.double(item.expense))
                )
                .foregroundStyle(Color.accentColor.gradient)
            }
            .frame(height: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .foregroundStyle(Color.accentColor.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day))
            }
            .frame(height: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryRanking(_ categories: [CategoryTotal], currencyCode: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类排行")
                .font(.headline)
            ForEach(categories, id: \.name) { item in
                VStack(spacing: 4) {
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                        Text("\(item.count) 笔")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(MoneyFormat.string(item.total, currencyCode: currencyCode))
                            .font(.subheadline.monospacedDigit())
                        Text(item.share.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    ProgressView(value: item.share)
                        .tint(.accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
