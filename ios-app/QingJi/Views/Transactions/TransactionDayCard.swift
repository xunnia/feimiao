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

    private var expense: Decimal {
        items.reduce(Decimal.zero) { total, transaction in
            guard transaction.kind == .expense else { return total }
            let refund = refundByID[transaction.stableID] ?? 0
            let net = transaction.amount > 0 ? transaction.amount - refund : transaction.amount
            return total + (net > 0 ? net : 0)
        }
    }

    private var income: Decimal {
        items.reduce(Decimal.zero) { total, transaction in
            transaction.kind == .income ? total + transaction.amount : total
        }
    }

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
                    refundAmount: refundByID[transaction.stableID] ?? 0
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
        let components = calendar.dateComponents([.month, .day, .weekday], from: normalized)
        let month = components.month ?? 1
        let dayOfMonth = components.day ?? 1
        let weekday = Self.weekdays[(components.weekday ?? 2) - 1]
        let full = "\(month)月\(dayOfMonth)日 周\(weekday)"
        if normalized == today { return "今天 · \(full)" }
        if normalized == yesterday { return "昨天 · \(full)" }
        return full
    }

    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
}
