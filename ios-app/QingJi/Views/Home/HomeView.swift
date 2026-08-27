import UIKit
import SwiftUI
import SwiftData
import QingJiCore

/// iOS 首页：先看本月真实汇总，再进入记账和明细。
/// 账本筛选遵守安卓端的「计入总账」约定；退款子记录保留在统计中，但不在首页重复列出。
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]
    @Query(sort: \Book.sortOrder)
    private var books: [Book]
    @State private var showAssistant = false
    @State private var showAIEntry = false

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
        includedTransactions
            .filter { $0.refundOfID == nil }
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
                    greeting
                    summaryCard
                    quickActions
                    assistantCard
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("肥喵记账")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.selectedTab = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .sheet(isPresented: $showAssistant) {
                NavigationStack {
                    MeowAssistantView()
                }
            }
            .sheet(isPresented: $showAIEntry) {
                AIQuickEntryView()
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppClock.now, format: .dateTime.year().month().day().weekday())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("今天也把每一笔记清楚")
                .font(.title2.weight(.semibold))
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
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
                    Label(selectedBookName, systemImage: "book.closed")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
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

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                router.selectedTab = .quickAdd
            } label: {
                Label("记一笔", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)

            Button {
                router.selectedTab = .transactions
            } label: {
                Label("看明细", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .controlSize(.large)
    }

    private var assistantCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "cat.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("问问喵助手")
                    .font(.subheadline.weight(.semibold))
                Text("查账、看趋势，或用一句话记账")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    showAssistant = true
                } label: {
                    Label("打开喵助手", systemImage: "bubble.left.and.bubble.right")
                }
                Button {
                    showAIEntry = true
                } label: {
                    Label("AI 记一笔", systemImage: "sparkles")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("喵助手操作")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .contentShape(Rectangle())
        .onTapGesture { showAssistant = true }
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

#Preview {
    HomeView()
        .modelContainer(AppModelContainer.shared)
        .environment(AppRouter())
}
