import SwiftUI
import QingJiCore

struct MonthlyPaceCard: View {
    let projection: MonthlyPaceProjection
    let categories: [CategoryTotal]
    let currencyCode: String
    let onOpenAllExpenses: () -> Void

    private let currentBlue = Color(red: 10 / 255, green: 132 / 255, blue: 1)

    var body: some View {
        let topCategories = Array(categories.filter { $0.total > 0 }.prefix(3))
        return VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: projection.title)
                .font(.subheadline)
            Divider()
            HStack(spacing: 42) {
                metric(label: "平均", amount: projection.average, muted: projection.average <= 0)
                metric(label: "本月", amount: projection.current, color: currentBlue)
            }
            paceBars
            Text("分类与支出活动")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Divider()
            if topCategories.isEmpty {
                Text("本月还没有支出分类。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(topCategories, id: \.name) { item in
                    HStack(spacing: 10) {
                        let seed = CategorySeed.all.first { $0.nameZh == item.name }
                        CategoryIcon(categoryKey: seed?.key ?? "", emoji: seed?.emoji ?? "🏷️", size: 30)
                            .accessibilityHidden(true)
                        Text(item.name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(MoneyFormat.string(item.total, currencyCode: currencyCode))
                            .monospacedDigit()
                        Text(item.share.formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                    .font(.subheadline)
                    Divider().padding(.leading, 42)
                }
                Button(action: onOpenAllExpenses) {
                    HStack {
                        Text("查看所有支出活动")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .id("stats-month-pace-activity")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassSurface(cornerRadius: 18)
    }

    private func metric(label: String, amount: Decimal, color: Color = .primary,
                        muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(color)
            Text(muted ? "--" : MoneyFormat.string(amount, currencyCode: currencyCode))
                .font(.title3.monospacedDigit())
                .foregroundStyle(muted ? Color.secondary : color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private var paceBars: some View {
        let values = projection.samples.flatMap { [MoneyFormat.double($0.full), MoneyFormat.double($0.pace)] }
        let maximum = max(max(values.max() ?? 0, MoneyFormat.double(projection.average)), 0.01)
        return GeometryReader { geometry in
            let chartHeight = geometry.size.height - 34
            let averageShare = CGFloat(MoneyFormat.double(projection.average) / maximum)
            let averageTop = min(max(chartHeight * (1 - averageShare), 16), chartHeight - 8)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(height: 2)
                    .offset(y: averageTop)
                Text("平均")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: max(averageTop - 22, 0))
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(projection.samples.enumerated()), id: \.offset) { _, sample in
                        PaceBar(sample: sample, maximum: maximum, chartHeight: chartHeight,
                                currentBlue: currentBlue)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: 166)
    }
}

private struct PaceBar: View {
    let sample: MonthlyPaceSample
    let maximum: Double
    let chartHeight: CGFloat
    let currentBlue: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 18, height: height(sample.full))
                RoundedRectangle(cornerRadius: 4)
                    .fill(sample.isCurrent ? currentBlue : Color.secondary.opacity(0.65))
                    .frame(width: 18, height: height(sample.pace))
            }
            .frame(width: 24, height: chartHeight, alignment: .bottom)
            Text(verbatim: sample.label)
                .font(.caption2)
                .foregroundStyle(sample.isCurrent ? currentBlue : Color.secondary)
        }
    }

    private func height(_ amount: Decimal) -> CGFloat {
        min(max(CGFloat(MoneyFormat.double(amount) / maximum) * chartHeight, 8), chartHeight)
    }
}
