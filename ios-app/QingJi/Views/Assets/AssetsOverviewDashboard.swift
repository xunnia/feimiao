import UIKit
import SwiftUI
import Charts
import QingJiCore

struct AssetsOverviewDashboard: View {
    let breakdown: NetWorthStore.Breakdown
    let snapshots: [NetWorthSnapshot]
    var verifiedCheckpoints: [NetWorthVerifiedCheckpointRecord] = []
    var cashAccountCount = 0
    var includedItemCount = 0
    var excludedItemCount = 0
    var missingValuationCount = 0
    var debtCount = 0
    var calibratedAccountCount = 0
    var accountCount = 0
    @State private var range = AssetOverviewRange.quarter
    @State private var showInfo = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var labelSize: CGFloat = 13
    @ScaledMetric(relativeTo: .callout) private var amountSize: CGFloat = 16.5
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    private var projection: AssetOverviewProjection {
        AssetOverviewProjection(snapshots: snapshots.filter { $0.asOf <= AppClock.now }, range: range, now: AppClock.now)
    }
    private var hasUnknownZero: Bool {
        breakdown.totalAssets == 0 && breakdown.totalLiabilities == 0
            && (missingValuationCount > 0 || !breakdown.unsupportedCurrencies.isEmpty)
    }
    private var labelFont: Font {
        .system(size: labelSize, weight: .regular)
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
        VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(missingValuationCount > 0 ? "净资产 · 部分待确认" : "净资产").font(labelFont).foregroundStyle(.secondary)
                    Spacer()
                    Text("人民币").font(.caption).foregroundStyle(.secondary)
                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("净资产口径与数据质量")
                }
                Text(hasUnknownZero ? "—" : Self.amount(breakdown.netWorth))
                    .font(.system(size: heroSize, weight: .bold, design: .rounded))
                    .foregroundStyle(breakdown.netWorth < 0 ? Color.warning : Color.primary)
                    .lineLimit(1).minimumScaleFactor(0.25)
                    .accessibilityLabel(hasUnknownZero ? "净资产待确认" : "净资产 \(Self.amount(breakdown.netWorth)) 人民币")
                if let change = AssetsPresentation.verifiedChange(verifiedCheckpoints, now: AppClock.now) {
                    Text("\(change.amount >= 0 ? "+" : "−")\(Self.amount(abs(change.amount))) · 较上次完整核对")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("\(shortDate(change.earlierDate)) → \(shortDate(change.laterDate))")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { verificationStatus }
                        VStack(alignment: .leading, spacing: 6) { verificationStatus }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack { trendStatus(history); Spacer(minLength: 4); rangeMenu }
                    VStack(alignment: .leading, spacing: 2) { trendStatus(history); rangeMenu }
                }
                if history.hasTrend {
                    AssetsHistoryChart(history: history, metric: .netWorth, color: .statisticsAccent, axes: true)
                        .frame(height: 64)
                }
                if history.hasTrend, let first = history.points.first, let last = history.points.last {
                    HStack {
                        Text(shortDate(first.asOf))
                        Spacer()
                        Text(shortDate(last.asOf))
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Divider().padding(.top, 4)
                if typeSize >= .xxxLarge {
                    VStack(alignment: .leading, spacing: 12) { keyMetrics }
                } else {
                    HStack(alignment: .top, spacing: 8) { keyMetrics }
                }
                if !breakdown.unsupportedCurrencies.isEmpty || missingValuationCount > 0 {
                    Button { showInfo = true } label: {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "info.circle")
                            Text("部分金额待确认，净资产可能不完整")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appThemeCard(cornerRadius: 22)
        .accessibilityIdentifier("assets-net-worth-card")
        .sheet(isPresented: $showInfo) { informationSheet }
    }

    @ViewBuilder private var verificationStatus: some View {
        Text(verifiedCheckpoints.isEmpty ? "还没有完整核对" : "完整核对变化暂不可比")
            .font(.footnote).foregroundStyle(.secondary)
        NavigationLink { ReconcileView() } label: {
            HStack(spacing: 2) {
                Text("核对账户")
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.footnote)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("核对账户余额，单账户校准不代表完整净资产核对")
    }

    private func trendStatus(_ history: AssetOverviewProjection) -> some View {
        Text((missingValuationCount == 0 ? history.delta(.netWorth, current: breakdown.netWorth) : nil).map {
            "估算变化 \($0 >= 0 ? "+" : "−")\(Self.amount(abs($0)))"
        } ?? (history.hasTrend ? "快照估算趋势" : history.points.count > 1 ? "已有快照暂不可比" : "可比快照不足"))
        .font(.caption).foregroundStyle(.secondary)
    }

    private var rangeMenu: some View {
        Menu {
            Picker("趋势时间", selection: $range) {
                ForEach(AssetOverviewRange.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(range.label)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assets-trend-range")
    }

    @ViewBuilder private var keyMetrics: some View {
        keyMetric("可动用资金", value: breakdown.cashAssets,
                  subtitle: "\(cashAccountCount) 个账户", identifier: "funds")
        keyMetric("计入物品", value: missingValuationCount > 0 || (includedItemCount == 0 && excludedItemCount > 0) ? nil : breakdown.physicalAssets,
                  subtitle: missingValuationCount > 0 ? "\(missingValuationCount) 件待估值" : includedItemCount == 0
                    ? "\(excludedItemCount) 件 · 未计入" : "\(includedItemCount) 件", identifier: "physical")
        keyMetric("总负债", value: breakdown.totalLiabilities, subtitle: "\(debtCount) 项", identifier: "liabilities")
    }

    private func keyMetric(_ label: String, value: Decimal?, subtitle: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map(Self.amount) ?? "—")
                .font(.system(size: amountSize, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(value.map { $0 < 0 } == true ? Color.warning : Color.primary)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)，\(value.map { Self.amount($0) + " 人民币" } ?? "待确认")，\(subtitle)")
        .accessibilityIdentifier("assets-metric-\(identifier)")
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.year(.twoDigits).month(.defaultDigits).day())
    }

    private var informationSheet: some View {
        NavigationStack {
            AppThemedForm {
                Section("人民币口径") {
                    LabeledContent("资金资产", value: Self.amount(breakdown.cashAssets + breakdown.investmentAssets + breakdown.receivableAssets))
                    LabeledContent("资金净值", value: Self.amount(breakdown.netWorth - breakdown.physicalAssets))
                    LabeledContent("总资产", value: Self.amount(breakdown.totalAssets))
                    Text("可动用资金取已计入的非投资账户正余额；投资、权益及物品在资产结构中分别列出。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("核对与估算") {
                    Text("已校准 \(calibratedAccountCount)/\(accountCount) 个账户")
                    Text("完整核对变化只比较两份冻结的完整核对记录；账户校准与自动快照不能代替完整净资产核对。")
                    Text("快照只用于估算趋势，不是收益率。统计范围或数据质量变化处断开。")
                    NavigationLink("历史快照") { NetWorthView() }
                }
                if !breakdown.unsupportedCurrencies.isEmpty || missingValuationCount > 0 {
                    Section("待确认") {
                        if missingValuationCount > 0 { Text("\(missingValuationCount) 件计入物品尚无有效估值") }
                        if !breakdown.unsupportedCurrencies.isEmpty {
                            Text("未含 \(breakdown.unsupportedCurrencies.sorted().joined(separator: "、")) 外币")
                        }
                    }
                }
            }
            .navigationTitle("净资产说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                LiquidGlassIconButton(systemName: "xmark", accessibilityLabel: "关闭", size: 44, subtle: true) { showInfo = false }
                    .foregroundStyle(Color.primary)
            }.sharedBackgroundVisibility(.hidden) }
        }
        .presentationDetents([.medium, .large])
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
                Text(history.points.count > 1 ? "已有快照暂不可比" : "至少积累 2 个可比快照后显示估算趋势")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.label)估算趋势，\(history.points.count)个快照，\(history.breakCount)处断点，非收益率。\(history.points.first.map { $0.asOf.formatted(date: .abbreviated, time: .omitted) } ?? "")至\(history.points.last.map { $0.asOf.formatted(date: .abbreviated, time: .omitted) } ?? "")")
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
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private var valueRange: ClosedRange<Double> {
        let values = history.segments.flatMap { $0 }.map { MoneyFormat.double(metric.value($0)) }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let inset = max((high - low) * 0.12, max(abs(high) * 0.01, 1))
        return (low - inset)...(high + inset)
    }
}
