import UIKit
import SwiftUI
import Charts
import QingJiCore

struct AssetsOverviewDashboard: View {
    let breakdown: NetWorthStore.Breakdown
    let snapshots: [NetWorthSnapshot]
    @State private var range = AssetOverviewRange.all
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var labelSize: CGFloat = 13
    @ScaledMetric(relativeTo: .title2) private var amountSize: CGFloat = 22
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    private var projection: AssetOverviewProjection {
        AssetOverviewProjection(snapshots: snapshots, range: range, now: AppClock.now)
    }
    private var labelFont: Font {
        .system(size: labelSize, weight: .regular)
    }
    private func value(_ metric: AssetOverviewMetric) -> Decimal {
        switch metric {
        case .netWorth: return breakdown.netWorth
        case .funds: return breakdown.cashAssets + breakdown.investmentAssets + breakdown.receivableAssets
        case .physical: return breakdown.physicalAssets
        case .total: return breakdown.totalAssets
        case .liabilities: return breakdown.totalLiabilities
        }
    }
    static func amount(_ value: Decimal) -> String {
        MoneyFormat.string(value, currencyCode: "CNY", withSymbol: false)
    }

    static func changeAmount(_ value: Decimal) -> String {
        let formatted = amount(value)
        return value >= 0 ? "+\(formatted)" : formatted
    }

    var body: some View {
        let history = projection
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("净资产").font(labelFont).foregroundStyle(.secondary)
                    Spacer()
                    Text("人民币").font(.caption).foregroundStyle(.secondary)
                }
                Text(Self.amount(breakdown.netWorth))
                    .font(.system(size: heroSize, weight: .bold, design: .rounded))
                    .foregroundStyle(breakdown.netWorth < 0 ? Color.warning : Color.primary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityLabel("净资产 \(Self.amount(breakdown.netWorth)) 人民币")
                if let delta = history.delta(.netWorth, current: breakdown.netWorth) {
                    Text("区间变化 \(Self.changeAmount(delta))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("区间变化暂不可比").font(.caption).foregroundStyle(.secondary)
                }
                if !breakdown.unsupportedCurrencies.isEmpty {
                    Text("未含 \(breakdown.unsupportedCurrencies.sorted().joined(separator: "、")) 外币")
                        .font(.caption).foregroundStyle(Color.warning)
                }
                HStack {
                    Text("快照估算").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("趋势时间", selection: $range) {
                            ForEach(AssetOverviewRange.allCases) { item in
                                Text(item.label).tag(item)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(range.label)
                            Image(systemName: "chevron.down").font(.system(size: 10))
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("assets-trend-range")
                }
                AssetsHistoryChart(history: history, metric: .netWorth, color: .statisticsAccent, axes: true)
                    .frame(height: history.hasTrend ? 184 : 72)
                if history.breakCount > 0 {
                    Text("统计范围或数据质量变化处断开")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appThemeCard(cornerRadius: 28)
            .accessibilityIdentifier("assets-net-worth-card")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                ForEach(AssetOverviewMetric.allCases.filter { $0 != .netWorth }) { metric in
                    metricCard(metric, history: history)
                }
            }
        }
    }

    private func metricCard(_ metric: AssetOverviewMetric, history: AssetOverviewProjection) -> some View {
        let current = value(metric)
        let percentage = history.percentage(metric, current: current)
        let delta = history.delta(metric, current: current)
        let color: Color = metric == .physical ? Color(red: 0.75, green: 0.60, blue: 0.32) : metric == .liabilities ? .warning : .statisticsAccent
        return VStack(alignment: .leading, spacing: 4) {
            Text(metric.label).font(labelFont).foregroundStyle(.secondary)
            Text(Self.amount(current))
                .font(.system(size: amountSize, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityLabel("\(metric.label) \(Self.amount(current)) 人民币")
            Spacer(minLength: 2)
            HStack(alignment: .bottom, spacing: 4) {
                HStack(spacing: 2) {
                    if percentage != nil, let delta {
                        Image(systemName: delta < 0 ? "arrow.down" : delta > 0 ? "arrow.up" : "minus")
                            .font(.system(size: 11))
                    }
                    Text(percentage ?? "—").font(.system(size: 12.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel(percentage.map { "区间估算变化 \($0)，非收益率" } ?? "区间估算变化不可比")
                Spacer(minLength: 0)
                AssetsHistoryChart(history: history, metric: metric, color: color)
                    .frame(width: 48, height: 28)
            }
        }
        .padding(16)
        .aspectRatio(typeSize.isAccessibilitySize ? nil : 5.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 156 : 106, alignment: .leading)
        .appThemeCard(cornerRadius: 20)
        .accessibilityIdentifier("assets-metric-\(metric.rawValue)")
    }
}

private struct AssetsHistoryChart: View {
    let history: AssetOverviewProjection
    let metric: AssetOverviewMetric
    let color: Color
    var axes = false

    var body: some View {
        Group {
            if history.hasTrend {
                chart
            } else if axes {
                Text(history.points.count > 1 ? "已有快照暂不可比" : "至少积累 2 个可比快照后显示趋势")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.label)估算趋势，\(history.points.count)个快照，\(history.breakCount)处断点，非收益率")
    }

    private var chart: some View {
        Chart {
            ForEach(Array(history.segments.enumerated()), id: \.offset) { index, segment in
                ForEach(segment, id: \.stableID) { point in
                    let amount = MoneyFormat.double(metric.value(point))
                    if axes {
                        AreaMark(x: .value("日期", point.asOf), y: .value("金额", amount), series: .value("区间", index))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.16), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    }
                    LineMark(x: .value("日期", point.asOf), y: .value("金额", amount), series: .value("区间", index))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: axes ? 2.2 : 1.8, lineCap: .round, lineJoin: .round))
                    if axes && point.stableID == segment.last?.stableID {
                        PointMark(x: .value("日期", point.asOf), y: .value("金额", amount))
                            .foregroundStyle(color).symbolSize(24)
                    }
                }
            }
        }
        .chartYScale(domain: valueRange)
        .chartPlotStyle { plot in plot.clipped() }
        .chartLegend(.hidden)
        .chartXAxis {
            if axes {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: false)
                }
            }
        }
        .chartYAxis {
            if axes {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    AxisValueLabel()
                }
            }
        }
    }

    private var valueRange: ClosedRange<Double> {
        let values = history.segments.flatMap { $0 }.map { MoneyFormat.double(metric.value($0)) }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let inset = max((high - low) * 0.12, max(abs(high) * 0.01, 1))
        return (low - inset)...(high + inset)
    }
}
