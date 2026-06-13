import UIKit
import SwiftUI
import SwiftData
import QingJiCore

/// 流水明细：按天分组、显示当日小计，支持搜索与左滑删除。
struct TransactionListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]

    @State private var searchText = ""
    @State private var editingTransaction: MoneyTransaction?

    private var filtered: [MoneyTransaction] {
        guard !searchText.isEmpty else { return transactions }
        return transactions.filter {
            $0.note.localizedStandardContains(searchText)
                || ($0.category?.name.localizedStandardContains(searchText) ?? false)
                || ($0.account?.name.localizedStandardContains(searchText) ?? false)
        }
    }

    private var sections: [(day: Date, items: [MoneyTransaction])] {
        let calendar = Calendar.current
        return Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, items: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "还没有账目",
                        systemImage: "tray",
                        description: Text("去「记一笔」页开始记账吧")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("明细")
            .searchable(text: $searchText, prompt: "搜索备注、分类、账户")
            .sheet(item: $editingTransaction) { transaction in
                EditTransactionSheet(transaction: transaction)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(sections, id: \.day) { section in
                Section {
                    ForEach(section.items) { transaction in
                        TransactionRow(transaction: transaction)
                            .contentShape(Rectangle())
                            .onTapGesture { editingTransaction = transaction }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            context.delete(section.items[index])
                        }
                        try? context.save()
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .listStyle(.plain)
    }

    private func sectionHeader(_ section: (day: Date, items: [MoneyTransaction])) -> some View {
        let expense = section.items
            .filter { $0.kind == .expense }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return HStack {
            Text(section.day, format: .dateTime.month().day().weekday())
            Spacer()
            if expense > 0 {
                Text("支出 \(MoneyFormat.string(expense, currencyCode: section.items.first?.currencyCode ?? "CNY"))")
            }
        }
        .font(.footnote)
    }
}

struct TransactionRow: View {
    let transaction: MoneyTransaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if !transaction.note.isEmpty {
                    Text(transaction.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(amountText)
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch transaction.kind {
        case .transfer: return "arrow.left.arrow.right"
        default: return transaction.category?.symbol ?? "tag"
        }
    }

    private var title: String {
        switch transaction.kind {
        case .transfer:
            let from = transaction.account?.name ?? "?"
            let to = transaction.toAccount?.name ?? "?"
            return "\(from) → \(to)"
        default:
            return transaction.category?.name ?? "未分类"
        }
    }

    private var amountText: String {
        let text = MoneyFormat.string(transaction.amount, currencyCode: transaction.currencyCode)
        switch transaction.kind {
        case .expense: return "-\(text)"
        case .income: return "+\(text)"
        case .transfer: return text
        }
    }

    private var amountColor: Color {
        switch transaction.kind {
        case .expense: return Color.expense
        case .income: return Color.income
        case .transfer: return .secondary
        }
    }
}
