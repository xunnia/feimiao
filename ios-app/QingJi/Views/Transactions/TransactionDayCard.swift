import Foundation
import SwiftUI
import QingJiCore

/// Android `TxDayCard` 的 iOS 原生对应组件。
///
/// 页面结构、每日净收支和账单顺序与 Android 保持一致；卡片材质、
/// 按压反馈和上下文菜单使用 iOS 原生实现。
struct TransactionDayCard: View {
    let day: Date
    let items: [MoneyTransaction]
    let refundByID: [UUID: Decimal]
    var onSelect: ((MoneyTransaction) -> Void)?
    var onDelete: ((MoneyTransaction) -> Void)?

    /// 已退金额一律按正数用。`LedgerPolicy.refundTotals` 存的是负数（退款行本身是负额），
    /// 调用方有的转过、有的没转；在这里统一，避免 38 − (−15) 被算成 53。
    static func refundAmount(for transaction: MoneyTransaction, in refundByID: [UUID: Decimal]) -> Decimal {
        let value = refundByID[transaction.stableID] ?? 0
        return value < 0 ? -value : value
    }

    /// 当天支出合计，口径同统计页 `StatisticsEngine`（`LedgerPolicy.userRecords`）和安卓
    /// `TxDayCard` 的 `userAmountOf`（07 F-TXN-013：用户净额 family）：
    /// - 「不计入收支」的不算；
    /// - 附着在原单上的退款行本身不单独算，已退金额从原单里减；
    /// - 老数据里没挂原单的独立负支出照原额冲减（07 §退款规则 5，不猜成退款）。
    static func dayExpense(_ items: [MoneyTransaction], refundByID: [UUID: Decimal]) -> Decimal {
        items.reduce(Decimal.zero) { total, transaction in
            guard transaction.kind == .expense, !transaction.isExcluded, transaction.refundOfID == nil else {
                return total
            }
            let net = transaction.amount > 0
                ? transaction.amount - refundAmount(for: transaction, in: refundByID)
                : transaction.amount
            return total + net
        }
    }

    /// 当天收入合计：「不计入收支」的不算。
    static func dayIncome(_ items: [MoneyTransaction]) -> Decimal {
        items.reduce(Decimal.zero) { total, transaction in
            transaction.kind == .income && !transaction.isExcluded ? total + transaction.amount : total
        }
    }

    private var expense: Decimal { Self.dayExpense(items, refundByID: refundByID) }
    private var income: Decimal { Self.dayIncome(items) }

    private var currencyCode: String {
        items.first?.currencyCode ?? "CNY"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, transaction in
                if index > 0 {
                    Divider()
                        .padding(.leading, 62)
                        .padding(.trailing, 14)
                }

                TransactionRow(
                    transaction: transaction,
                    refundAmount: Self.refundAmount(for: transaction, in: refundByID)
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { onSelect?(transaction) }
                .contextMenu {
                    if let onDelete {
                        Button("删除", role: .destructive) {
                            onDelete(transaction)
                        }
                    }
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dateLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if expense > 0 {
                Text("支 \(compactAmount(expense))")
            }
            if income > 0 {
                Text("收 \(compactAmount(income))")
                    .foregroundStyle(Color.income)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func compactAmount(_ amount: Decimal) -> String {
        MoneyFormat.string(amount, currencyCode: currencyCode)
            .replacingOccurrences(of: "CN¥", with: "")
            .replacingOccurrences(of: "¥", with: "")
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: AppClock.now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: normalized)
        let month = components.month ?? 1
        let dayOfMonth = components.day ?? 1
        let weekday = Self.weekdays[(components.weekday ?? 2) - 1]
        // 不是今年的日子带年份（搜索结果可能横跨好几年）。
        let year = components.year == calendar.component(.year, from: today)
            ? "" : "\(components.year ?? 0)年"
        let full = "\(year)\(month)月\(dayOfMonth)日 周\(weekday)"
        if normalized == today { return "今天 · \(full)" }
        if normalized == yesterday { return "昨天 · \(full)" }
        return full
    }

    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
}
