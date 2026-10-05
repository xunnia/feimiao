import SwiftUI

struct AssetsStructureSection: View {
    let breakdown: NetWorthStore.Breakdown
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
        VStack(alignment: .leading, spacing: 8) {
            Text("资产结构").font(.footnote).foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 16) {
                if structure.hasShares && structure.visibleKinds.count > 1 {
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
                if structure.visibleKinds.isEmpty {
                    Text("暂无已计入的人民币资产").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(structure.visibleKinds) { kind in
                    let amount = AssetsOverviewDashboard.amount(structure.amounts[kind, default: 0])
                    let percentage = AssetStructureProjection.percentLabel(structure.percentage(kind))
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
                    .accessibilityLabel("\(kind.label) \(amount) 人民币，\(structure.hasShares ? "占比\(percentage)" : "占比不可计算")")
                }
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { footer(structure) }
                    VStack(alignment: .leading, spacing: 6) { footer(structure) }
                }
                if structure.partial || !structure.isConsistent {
                    Text(structure.partial ? "部分金额待确认，占比暂不可比" : "金额口径待核实，占比暂不可比")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .appThemeCard(cornerRadius: 20)
        }
        .accessibilityIdentifier("assets-structure")
    }

    private func category(_ kind: AssetStructureProjection.Kind) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color(kind)).frame(width: 6, height: 6)
            Text(kind.label).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func values(_ amount: String, percentage: String) -> some View {
        HStack(spacing: 12) {
            Text(amount).font(.system(.headline, design: .rounded, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.6)
            if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(percentage).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func footer(_ structure: AssetStructureProjection) -> some View {
        Text("人民币 · 已计入资产").font(.caption).foregroundStyle(.secondary)
        Text("负债率 \(AssetStructureProjection.percentLabel(structure.liabilityPercentage))")
            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
    }
}
