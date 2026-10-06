import SwiftUI

struct AssetsStructureSection: View {
    let breakdown: NetWorthStore.Breakdown
    var hasMissingValuations = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private func color(_ kind: AssetStructureProjection.Kind) -> Color {
        switch kind {
        case .cash: return .statisticsAccent
        case .investment: return Color.primary.opacity(0.52)
        case .receivable: return Color(red: 244.0 / 255, green: 169.0 / 255, blue: 184.0 / 255)
        case .physical: return Color(red: 242.0 / 255, green: 178.0 / 255, blue: 60.0 / 255)
        }
    }

    var body: some View {
        let structure = AssetStructureProjection(breakdown: breakdown)
        let kinds = AssetStructureProjection.Kind.allCases.filter {
            structure.visibleKinds.contains($0) || ($0 == .physical && hasMissingValuations)
        }
        let totalLabel = hasMissingValuations && breakdown.totalAssets == 0 ? "—" : AssetsOverviewDashboard.amount(breakdown.totalAssets)
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("资产结构")
                    Spacer(minLength: 8)
                    Text("总资产 \(totalLabel)")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("资产结构")
                    Text("总资产 \(totalLabel)")
                }
            }
            .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 12) {
                if structure.hasShares && !hasMissingValuations && structure.visibleKinds.count > 1 {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(structure.visibleKinds) { kind in
                                let share = NSDecimalNumber(decimal: structure.percentage(kind) ?? 0).doubleValue / 100
                                color(kind).frame(width: geometry.size.width * CGFloat(share))
                            }
                        }
                    }
                    .frame(height: 6).clipShape(Capsule())
                    .accessibilityHidden(true)
                }
                if kinds.isEmpty {
                    Text("暂无已计入的人民币资产").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(kinds) { kind in
                    let amount = kind == .physical && hasMissingValuations ? "—" : AssetsOverviewDashboard.amount(structure.amounts[kind, default: 0])
                    let percentage = AssetStructureProjection.percentLabel(hasMissingValuations ? nil : structure.percentage(kind))
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 6) {
                                category(kind)
                                values(amount, percentage: percentage)
                            }
                        } else {
                            HStack(spacing: 12) {
                                category(kind)
                                Spacer(minLength: 8)
                                values(amount, percentage: percentage)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(kind.label) \(amount) 人民币，\(structure.hasShares && !hasMissingValuations ? "占比\(percentage)" : "占比不可计算")")
                }
                if structure.visibleKinds.count == 1 && !hasMissingValuations {
                    Text("目前只有一类资产").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Text("负债").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(AssetsOverviewDashboard.amount(breakdown.totalLiabilities))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                if structure.partial || !structure.isConsistent || hasMissingValuations {
                    Text(structure.partial ? "部分金额待确认，占比暂不可比" : "金额口径待核实，占比暂不可比")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .appThemeCard(cornerRadius: 22)
        }
        .accessibilityIdentifier("assets-structure")
    }

    private func category(_ kind: AssetStructureProjection.Kind) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color(kind)).frame(width: 6, height: 6)
            Text(kind.label).font(.subheadline).foregroundStyle(.primary)
        }
    }

    private func values(_ amount: String, percentage: String) -> some View {
        HStack(spacing: 12) {
            Text(amount).font(.system(.subheadline, design: .rounded, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.6)
            if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if hasMissingValuations || percentage == "—" || AssetStructureProjection(breakdown: breakdown).visibleKinds.count > 1 {
                Text(percentage).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

}
