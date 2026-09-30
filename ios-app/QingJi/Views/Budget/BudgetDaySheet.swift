import SwiftUI
import SwiftData
import QingJiCore

/// 某一天详情（docs/08 §6.9）：这天归哪条规则管、当天预算 / 花了 / 超了、当天账单。
/// 和安卓 budget_day_sheet.dart 同一套文案。selectedBookID 为 nil 表示总账本。
struct BudgetDaySheet: View {
    let selectedBookID: UUID?
    let day: BudgetCivilDay

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Book.sortOrder) private var books: [Book]
    @Query private var ruleRecords: [BudgetRuleRecord]
    @Query private var rolloverRecords: [BudgetRolloverChangeRecord]
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @State private var projectionCache = IOSLedgerProjectionCache()
    @State private var editingTransaction: MoneyTransaction?

    private var title: String {
        "\(day.month)月\(day.day)日 周\(budgetWeekdayNames[day.weekday - 1])"
    }

    private func ruleLine(_ info: BudgetDayInfo) -> String {
        if let special = info.specialRule {
            let funding = special.isExtra || info.baseRule == nil ? "额外多给" : "从\(day.month)月预算里匀"
            return "归「\(budgetRuleName(special))」管 · \(funding)"
        }
        if let base = info.baseRule {
            return "归日常预算管 · \(budgetRuleAmountText(base))"
        }
        return "这天没有预算，花的钱不算进预算"
    }

    var body: some View {
        let snapshot = BudgetRuleStore.snapshot(
            rules: ruleRecords, rollovers: rolloverRecords, selectedBookID: selectedBookID,
            books: books, transactions: transactions, year: day.year, month: day.month)
        let info = snapshot.month.days.first { $0.day == day }
        let future = day > snapshot.today
        let spent = future ? 0 : snapshot.spendByDay[day.key] ?? 0
        let over = info?.covered == true ? spent - (info?.budgetCents ?? 0) : 0
        let projection = projectionCache.snapshot(for: transactions, selectedBookID: selectedBookID)
        let calendar = Calendar.current
        let dayTransactions: [MoneyTransaction] = future ? [] : projection.scopedTransactions.filter {
            $0.kindRaw == TransactionKind.expense.rawValue && $0.refundOfID == nil
                && BudgetCivilDay($0.date, calendar: calendar) == day
        }
        let refundByID = projection.refundTotals.mapValues { $0 < 0 ? -$0 : $0 }
        let ruleColor = (info?.specialRule ?? info?.baseRule).map(BudgetRuleColors.color)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let info {
                        HStack(spacing: 8) {
                            if let ruleColor { BudgetRuleDot(color: ruleColor) }
                            Text(ruleLine(info))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("budget-day-rule")
                        }
                        .padding(.horizontal, 4)
                        if info.covered {
                            HStack(spacing: 8) {
                                stat("当天预算", budgetYuanText(info.budgetCents))
                                if !future { stat("花了", budgetYuanText(spent)) }
                                if !future && over >= 100 { stat("超了", budgetYuanText(over), warning: true) }
                            }
                            if !future && over >= 100 {
                                Text("多花的会从后面的日子里自动匀出来，不用管它")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                    .accessibilityIdentifier("budget-day-tip")
                            }
                        }
                    }
                    if !dayTransactions.isEmpty {
                        TransactionDayCard(
                            day: day.date(calendar: calendar),
                            items: dayTransactions,
                            refundByID: refundByID,
                            onSelect: { editingTransaction = $0 }
                        )
                    } else if !future {
                        Text("这天没有记支出")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 20, trailing: 16))
            }
            .liquidGlassCanvas()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
            .sheet(item: $editingTransaction) { transaction in
                EditTransactionSheet(transaction: transaction)
            }
        }
    }

    private func stat(_ label: String, _ value: String, warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(warning ? Color.warning : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .liquidGlassSurface(cornerRadius: 14)
    }
}
