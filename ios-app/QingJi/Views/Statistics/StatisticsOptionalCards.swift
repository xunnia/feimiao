import SwiftUI
import Charts
import QingJiCore

struct SpendingInsightsCard: View {
    let projection: SpendingInsightsProjection
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("喵的洞察").font(.headline)
            if let profile = projection.profile {
                HStack(spacing: 6) {
                    Text(profile.emoji)
                    Text(profile.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
                Text(profile.advice).font(.subheadline).foregroundStyle(.secondary)
            }
            if let change = projection.totalChangePercent {
                insightLine(change > 0
                    ? "本月总支出比上月多了 \(change)%"
                    : "本月总支出比上月省了 \(-change)%，不错喵")
            }
            if let category = projection.categoryIncrease {
                let count = category.countDifference > 0 ? "，多了 \(category.countDifference) 笔" : ""
                insightLine("「\(category.name)」比上月多花 \(MoneyFormat.string(category.amount, currencyCode: currencyCode))\(count)")
            }
            if let dominant = projection.dominantCategory {
                insightLine("「\(dominant.name)」占了本月支出的 \(dominant.percent)%，是绝对大头")
            }
            if let forecast = projection.forecast {
                let amount = MoneyFormat.string(forecast.projected, currencyCode: currencyCode)
                let message = forecast.overBy > 0
                    ? "按当前速度，月底预计花 \(amount)，可能超预算 \(MoneyFormat.string(forecast.overBy, currencyCode: currencyCode))（+\(forecast.overPercent)%），悠着点喵"
                    : "按当前速度，月底预计花 \(amount)，在预算内，稳的"
                Text(message).font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassSurface(cornerRadius: 18)
    }

    private func insightLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("·")
            Text(text)
        }
        .font(.subheadline)
    }
}

private extension SpendingProfileKind {
    var emoji: String {
        switch self {
        case .largePurchase: return "🛍️"
        case .monthToMonth: return "💸"
        case .steadySaver: return "🏦"
        case .balanced: return "⚖️"
        case .carefulRecorder: return "📒"
        }
    }

    var title: String {
        switch self {
        case .largePurchase: return "大额冲动型"
        case .monthToMonth: return "月光型"
        case .steadySaver: return "稳健储蓄型"
        case .balanced: return "收支平衡型"
        case .carefulRecorder: return "认真记账型"
        }
    }

    var advice: String {
        switch self {
        case .largePurchase: return "大件支出占比很高，下单前给自己留 24 小时冷静期"
        case .monthToMonth: return "本月几乎没结余，试试发工资先转 10% 进存钱目标"
        case .steadySaver: return "结余率超过 30%，继续保持，可以考虑给闲钱找个去处"
        case .balanced: return "收支健康，把结余率再往 30% 推一把会更稳"
        case .carefulRecorder: return "记上收入后，喵可以帮你算结余率和更准的画像"
        }
    }
}

struct MonthlyHeatmapCard: View {
    let summary: MonthlySummary
    let currencyCode: String
    @State private var selectedDay: DailyTotal?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    private let heatmapTint = Color(red: 125.0 / 255, green: 139.0 / 255, blue: 155.0 / 255)

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: summary.year, month: summary.month, day: 1)) ?? AppClock.now
        let leading = (calendar.component(.weekday, from: start) + 5) % 7
        let maximum = max(summary.dailyTotals.map { MoneyFormat.double($0.expense) }.max() ?? 0, 0)
        return VStack(alignment: .leading, spacing: 10) {
            Text("消费热力图").font(.headline)
            HStack(spacing: 4) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<(leading + summary.dailyTotals.count), id: \.self) { index in
                    if index < leading {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    } else {
                        let day = summary.dailyTotals[index - leading]
                        let value = MoneyFormat.double(day.expense)
                        let intensity = maximum > 0 ? min(max(value / maximum, 0), 1) : 0
                        Button { selectedDay = day } label: {
                            Text("\(day.day)")
                                .font(.caption2)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .background(value <= 0 ? Color.secondary.opacity(0.12)
                                            : heatmapTint.opacity(0.18 + 0.72 * intensity),
                                            in: .rect(cornerRadius: 5))
                                .foregroundStyle(intensity > 0.55 ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(summary.month)月\(day.day)日，支出 \(MoneyFormat.string(day.expense, currencyCode: currencyCode))")
                    }
                }
            }
            HStack(spacing: 4) {
                Spacer()
                Text("少")
                ForEach([0.2, 0.45, 0.7, 0.9], id: \.self) { opacity in
                    RoundedRectangle(cornerRadius: 3).fill(heatmapTint.opacity(opacity))
                        .frame(width: 10, height: 10)
                }
                Text(maximum > 0 ? "多 · 单日最高 \(MoneyFormat.string(Decimal(maximum), currencyCode: currencyCode))" : "多")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassSurface(cornerRadius: 18)
        .alert("每日支出", isPresented: Binding(
            get: { selectedDay != nil }, set: { if !$0 { selectedDay = nil } }
        )) {
            Button("好") { selectedDay = nil }
        } message: {
            if let selectedDay {
                Text("\(summary.month)月\(selectedDay.day)日 · \(MoneyFormat.string(selectedDay.expense, currencyCode: currencyCode))")
            }
        }
    }
}

struct MonthlyCompareBarsCard: View {
    let current: MonthlySummary
    let previous: MonthlySummary
    let currencyCode: String

    var body: some View {
        let categories = Array(current.expenseByCategory.filter { $0.total > 0 }.prefix(6))
        let maximum = max(categories.map { category in
            max(MoneyFormat.double(category.total), MoneyFormat.double(previousAmount(for: category.name)))
        }.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("本月 vs 上月").font(.headline)
            HStack(spacing: 14) {
                Label("本月", systemImage: "circle.fill").foregroundStyle(Color.primary)
                Label("上月", systemImage: "circle.fill").foregroundStyle(Color.secondary.opacity(0.4))
            }
            .font(.caption)
            if categories.isEmpty {
                Text("本月还没有支出").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(categories, id: \.name) { category in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(category.name).lineLimit(1)
                        Spacer()
                        Text(MoneyFormat.string(category.total, currencyCode: currencyCode)).monospacedDigit()
                    }
                    .font(.caption)
                    ProgressView(value: max(0, MoneyFormat.double(category.total)), total: maximum).tint(.primary)
                    ProgressView(value: max(0, MoneyFormat.double(previousAmount(for: category.name))),
                                 total: maximum).tint(Color.secondary.opacity(0.4))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassSurface(cornerRadius: 18)
    }

    private func previousAmount(for name: String) -> Decimal {
        previous.expenseByCategory.first { $0.name == name }?.total ?? 0
    }
}

struct TwelveMonthStackCard: View {
    let summaries: [MonthlySummary]
    let currencyCode: String
    @State private var selectedIndex: Int?
    private let savedColor = Color(red: 0.73, green: 0.56, blue: 0.32)

    private struct Segment: Identifiable {
        let id: String
        let index: Int
        let start: Double
        let end: Double
        let color: Color
    }

    private var segments: [Segment] {
        summaries.enumerated().flatMap { index, summary -> [Segment] in
            let expense = max(MoneyFormat.double(summary.totalExpense), 0)
            let income = max(MoneyFormat.double(summary.totalIncome), 0)
            let spent = Segment(id: "\(index)-spent", index: index, start: 0,
                                end: min(expense, income), color: .primary)
            let remainder = Segment(id: "\(index)-remainder", index: index,
                                    start: min(expense, income), end: max(expense, income),
                                    color: expense > income ? .warning : savedColor)
            return [spent, remainder]
        }
    }

    var body: some View {
        let hasData = summaries.contains { $0.totalExpense != 0 || $0.totalIncome != 0 }
        return VStack(alignment: .leading, spacing: 12) {
            Text("近 12 月收支").font(.headline)
            if hasData {
                HStack(spacing: 14) {
                    legend("花掉", color: .primary)
                    legend("结余", color: savedColor)
                    legend("超支", color: .warning)
                }
                Chart(segments) { segment in
                    BarMark(x: .value("月", segment.index),
                            yStart: .value("起", segment.start), yEnd: .value("终", segment.end))
                        .foregroundStyle(segment.color)
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: [0, 2, 4, 6, 8, 10]) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self), summaries.indices.contains(index) {
                                Text("\(summaries[index].month)月")
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedIndex)
                .frame(height: 170)
                if let selectedIndex, summaries.indices.contains(selectedIndex) {
                    let summary = summaries[selectedIndex]
                    Text("\(summary.month)月 · 支 \(MoneyFormat.string(summary.totalExpense, currencyCode: currencyCode)) · 收 \(MoneyFormat.string(summary.totalIncome, currencyCode: currencyCode))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("近 12 个月还没有记录").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassSurface(cornerRadius: 18)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
        .font(.caption2)
    }
}
