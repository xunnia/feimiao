import Foundation

struct AssetStructureProjection {
    enum Kind: String, CaseIterable, Identifiable {
        case cash, investment, receivable, physical
        var id: String { rawValue }
        var label: String {
            switch self {
            case .cash: return "流动资金"
            case .investment: return "投资余额"
            case .receivable: return "权益资产"
            case .physical: return "计入物品"
            }
        }
    }

    let totalAssets: Decimal
    let totalLiabilities: Decimal
    let amounts: [Kind: Decimal]
    let partial: Bool

    init(breakdown: NetWorthStore.Breakdown) {
        totalAssets = breakdown.totalAssets
        totalLiabilities = breakdown.totalLiabilities
        amounts = [.cash: breakdown.cashAssets, .investment: breakdown.investmentAssets,
                   .receivable: breakdown.receivableAssets, .physical: breakdown.physicalAssets]
        partial = !breakdown.unsupportedCurrencies.isEmpty
    }

    var isConsistent: Bool {
        totalLiabilities >= 0 && amounts.values.allSatisfy { $0 >= 0 }
            && amounts.values.reduce(Decimal.zero, +) == totalAssets
    }
    var hasShares: Bool { !partial && isConsistent && totalAssets > 0 }
    var visibleKinds: [Kind] { Kind.allCases.filter { amounts[$0, default: 0] != 0 } }
    func percentage(_ kind: Kind) -> Decimal? {
        hasShares ? amounts[kind, default: 0] * 100 / totalAssets : nil
    }
    var liabilityPercentage: Decimal? {
        hasShares ? totalLiabilities * 100 / totalAssets : nil
    }
    static func percentLabel(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return "\(formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—")%"
    }
}
