import SwiftUI
import QingJiCore

struct BudgetUsageRingCard: View {
    let budget: Decimal
    let status: BudgetStatus
    let displayedMonth: Date
    let now: Date
    let currencyCode: String

    static func displayPercent(spent: Decimal, budget: Decimal) -> Int {
        guard budget > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: spent / budget).doubleValue
        return Int((ratio * 100).rounded())
    }

    var body: some View {
        let percent = Self.displayPercent(spent: status.spentThisMonth, budget: budget)
        let over = status.spentThisMonth > budget
        let color = over ? Color.warning : Color(red: 127 / 255, green: 176 / 255, blue: 105 / 255)
        let calendar = Calendar.current
        let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        let daysLeft = calendar.isDate(displayedMonth, equalTo: now, toGranularity: .month)
            ? max(daysInMonth - calendar.component(.day, from: now), 0) : 0
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(max(Double(percent) / 100, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)%")
                    .font(.headline.monospacedDigit())
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 5) {
                Text("预算使用")
                    .font(.caption).foregroundStyle(.secondary)
                Text(over ? "超支 \(MoneyFormat.string(status.spentThisMonth - budget, currencyCode: currencyCode))"
                          : "\(percent)%")
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(over ? color : Color.primary)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text("已用 \(MoneyFormat.string(status.spentThisMonth, currencyCode: currencyCode)) / " +
                     "\(MoneyFormat.string(budget, currencyCode: currencyCode))" +
                     (daysLeft > 0 ? " · 剩 \(daysLeft) 天" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassSurface(cornerRadius: 18)
    }
}
