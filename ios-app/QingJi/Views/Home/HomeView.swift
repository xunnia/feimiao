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
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @State private var transactionFilter: HomeTransactionFilter = .all

    private var includedTransactions: [MoneyTransaction] {
        LedgerScope.filter(transactions, selectedBookID: router.selectedBookID)
            .filter { !$0.isExcluded }
    }

    private var selectedBookName: String {
        if let selectedBookID = router.selectedBookID,
           let book = books.first(where: { $0.stableID == selectedBookID }) {
            return book.name
        }
        return "总账本"
    }

    private var monthSummary: MonthlySummary {
        let now = AppClock.now
        let components = Calendar.current.dateComponents([.year, .month], from: now)
        return StatisticsEngine.monthlySummary(
            of: includedTransactions.map(\.record),
            year: components.year ?? 2000,
            month: components.month ?? 1
        )
    }

    private var currencyCode: String {
        includedTransactions.first?.currencyCode ?? "CNY"
    }

    private var recentTransactions: [MoneyTransaction] {
        let now = AppClock.now
        let monthTransactions = includedTransactions.filter {
            $0.refundOfID == nil &&
            Calendar.current.isDate($0.date, equalTo: now, toGranularity: .month)
        }
        let filtered = monthTransactions.filter { transaction in
            switch transactionFilter {
            case .all: true
            case .expense: transaction.kind == .expense
            case .income: transaction.kind == .income
            }
        }
        return filtered
            .prefix(8)
            .map { $0 }
    }

    private var refundByID: [UUID: Decimal] {
        includedTransactions.reduce(into: [:]) { result, transaction in
            guard let originalID = transaction.refundOfID, transaction.amount < 0 else { return }
            result[originalID, default: 0] += -transaction.amount
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    filterSegment
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            // 首页的主操作必须和 Android 一样固定在底部；其它页面仍使用
            // iOS 原生 TabBar/NavigationStack。底部输入框内的材质与动效使用
            // iOS 原生 Liquid Glass，但不改变 Android 的功能入口。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeRecordInputBar()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            router.selectedTab = .transactions
                        } label: {
                            Label("全部明细", systemImage: "list.bullet")
                        }
                        Button {
                            router.selectedTab = .statistics
                        } label: {
                            Label("统计", systemImage: "chart.pie")
                        }
                        Button {
                            router.showAssistant = true
                        } label: {
                            Label("打开喵助手", systemImage: "cat.fill")
                        }
                        Divider()
                        Button {
                            router.selectedTab = .settings
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .accessibilityLabel("菜单")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.selectedTab = .transactions
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
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
                        .frame(minWidth: 100, minHeight: 44)
                        .padding(.horizontal, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .accessibilityLabel("当前账本：\(selectedBookName)")
                }
            }
            .sheet(isPresented: Binding(
                get: { router.showAssistant },
                set: { router.showAssistant = $0 }
            )) {
                NavigationStack {
                    MeowAssistantView()
                }
            }
            .toolbar(.hidden, for: .tabBar)
        }
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

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("月度总览")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("本月")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(MoneyFormat.string(monthSummary.balance, currencyCode: currencyCode))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            HStack(spacing: 12) {
                amountColumn(title: "收入", amount: monthSummary.totalIncome, color: .income, symbol: "arrow.down.left")
                amountColumn(title: "支出", amount: monthSummary.totalExpense, color: .primary, symbol: "arrow.up.right")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func amountColumn(title: String, amount: Decimal, color: Color, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(MoneyFormat.string(amount, currencyCode: currencyCode))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近账目")
                    .font(.headline)
                Spacer()
                Button("全部") { router.selectedTab = .transactions }
                    .font(.subheadline)
            }

            if recentTransactions.isEmpty {
                ContentUnavailableView("还没有账目", systemImage: "tray", description: Text("记下第一笔，肥喵就开始帮你整理"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentTransactions.enumerated()), id: \.element.persistentModelID) { index, transaction in
                        TransactionRow(
                            transaction: transaction,
                            refundAmount: refundByID[transaction.stableID] ?? 0
                        )
                            .padding(.vertical, 8)
                        if index < recentTransactions.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(.background, in: .rect(cornerRadius: 18))
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

            HStack(spacing: 8) {
                Button(action: openSelectedEntry) {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加一笔")

                Button {
                    isAIMode.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isAIMode ? "sparkles" : "pencil")
                        Text(isAIMode ? "AI 记账" : "手动记账")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换到\(isAIMode ? "手动记账" : "AI 记账")")

                Spacer(minLength: 0)

                Button(action: openSelectedEntry) {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开\(isAIMode ? "AI 记账" : "手动记账")")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
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
