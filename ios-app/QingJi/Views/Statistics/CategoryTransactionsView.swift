import SwiftUI
import SwiftData
import QingJiCore

/// Statistics drill-down for one or several top-level expense categories.
struct CategoryTransactionsView: View {
    let title: String
    let categoryNames: Set<String>
    let start: Date
    let end: Date

    @Environment(AppRouter.self) private var router
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @State private var projectionCache = IOSLedgerProjectionCache()

    var body: some View {
        let snapshot = projectionCache.snapshot(for: transactions, selectedBookID: router.selectedBookID)
        let records = StatisticsEngine.expenseRecords(
            in: snapshot.records, categoryNames: categoryNames, start: start, end: end
        )
        let ids = Set(records.map(\.id))
        let items = snapshot.scopedTransactions.filter { ids.contains($0.stableID) }
        let sections = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }
        let refundByID = snapshot.refundTotals.mapValues { $0 < 0 ? -$0 : $0 }
        let total = records.reduce(Decimal.zero) { $0 + $1.amount }

        Group {
            if items.isEmpty {
                ContentUnavailableView("这段时间没有「\(title)」的记录", systemImage: "tray")
            } else {
                List {
                    HStack {
                        Text("共 \(records.filter { $0.amount > 0 }.count) 笔")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(MoneyFormat.string(total, currencyCode: snapshot.scopedCurrencyCode))
                            .font(.headline.monospacedDigit())
                    }
                    .listRowBackground(Color.clear)
                    ForEach(sections.keys.sorted(by: >), id: \.self) { day in
                        TransactionDayCard(day: day, items: sections[day] ?? [], refundByID: refundByID)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .liquidGlassCanvas()
        .navigationTitle(title)
    }
}
