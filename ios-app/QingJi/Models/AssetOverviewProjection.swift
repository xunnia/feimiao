import Foundation

enum AssetOverviewRange: Int, CaseIterable, Identifiable {
    case quarter = 90, year = 365, all = 0
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .quarter: return "近3个月"
        case .year: return "近1年"
        case .all: return "全部时间"
        }
    }
}

enum AssetOverviewMetric: String, CaseIterable, Identifiable {
    case netWorth, funds, physical, total, liabilities
    var id: String { rawValue }
    var label: String {
        switch self {
        case .netWorth: return "净资产"
        case .funds: return "资金资产"
        case .physical: return "计入物品"
        case .total: return "总资产"
        case .liabilities: return "总负债"
        }
    }
    func value(_ snapshot: NetWorthSnapshot) -> Decimal {
        switch self {
        case .netWorth: return snapshot.netWorth
        case .funds: return snapshot.cashAssets + snapshot.investmentAssets + snapshot.receivableAssets
        case .physical: return snapshot.physicalAssets
        case .total: return snapshot.totalAssets
        case .liabilities: return snapshot.liabilities
        }
    }
}

/// Display-only history. Scope/quality breaks are never interpolated or filled.
struct AssetOverviewProjection {
    let points: [NetWorthSnapshot]
    let segments: [[NetWorthSnapshot]]
    let breakCount: Int
    var hasTrend: Bool { segments.contains { $0.count >= 2 } }

    init(snapshots: [NetWorthSnapshot], range: AssetOverviewRange, now: Date,
         calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let cutoff = range == .all ? Date.distantPast : calendar.date(byAdding: .day, value: -range.rawValue, to: today)!
        let sorted = snapshots.filter {
            let day = calendar.startOfDay(for: $0.asOf)
            return day >= cutoff && day <= today && $0.baseCurrency == "CNY" && $0.scopeKey == "global"
        }.sorted {
            if $0.asOf != $1.asOf { return $0.asOf < $1.asOf }
            if $0.knowledgeCutoff != $1.knowledgeCutoff { return $0.knowledgeCutoff < $1.knowledgeCutoff }
            return $0.stableID.uuidString < $1.stableID.uuidString
        }
        var days: [NetWorthSnapshot] = []
        for snapshot in sorted {
            if let last = days.last, calendar.isDate(last.asOf, inSameDayAs: snapshot.asOf) {
                if snapshot.knowledgeCutoff >= last.knowledgeCutoff { days[days.count - 1] = snapshot }
            } else { days.append(snapshot) }
        }
        var result: [[NetWorthSnapshot]] = []
        var segment: [NetWorthSnapshot] = []
        var breaks = 0
        for (index, point) in days.enumerated() {
            let eligible = Self.eligible(point)
            if index > 0 && !Self.comparable(days[index - 1], point) {
                if !segment.isEmpty { result.append(segment) }
                segment = []
                breaks += 1
            }
            if eligible { segment.append(point) }
        }
        if !segment.isEmpty { result.append(segment) }
        points = days
        segments = result
        breakCount = breaks
    }

    private static func currencies(_ json: String) -> [String]? {
        guard let data = json.data(using: .utf8), let values = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        let normalized = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        guard normalized.allSatisfy({ !$0.isEmpty }) else { return nil }
        return Array(Set(normalized)).sorted()
    }

    private static func eligible(_ point: NetWorthSnapshot) -> Bool {
        guard point.scopeVersion > 0, point.calculationVersion > 0,
              let covered = currencies(point.coveredCurrenciesJSON), covered.contains("CNY"),
              let uncovered = currencies(point.uncoveredCurrenciesJSON),
              Set(covered).isDisjoint(with: Set(uncovered)),
              let data = point.reasonsJSON.data(using: .utf8),
              let reasons = try? JSONDecoder().decode([String].self, from: data) else { return false }
        switch point.quality {
        case .available:
            return uncovered.isEmpty && reasons.isEmpty
        case .partial:
            // Only the known currency-only omission has stable comparison coverage.
            // Missing/unknown valuation evidence must not turn into a growth rate.
            return !uncovered.isEmpty && !reasons.isEmpty
                && reasons.allSatisfy { $0 == "存在未换算外币" }
        default:
            return false
        }
    }

    private static func comparable(_ first: NetWorthSnapshot, _ last: NetWorthSnapshot) -> Bool {
        guard eligible(first), eligible(last),
              first.scopeVersion == last.scopeVersion,
              first.calculationVersion == last.calculationVersion,
              let firstCovered = currencies(first.coveredCurrenciesJSON),
              let lastCovered = currencies(last.coveredCurrenciesJSON),
              let firstUncovered = currencies(first.uncoveredCurrenciesJSON),
              let lastUncovered = currencies(last.uncoveredCurrenciesJSON) else { return false }
        return firstCovered == lastCovered && firstUncovered == lastUncovered
    }

    func delta(_ metric: AssetOverviewMetric, current: Decimal) -> Decimal? {
        guard points.count >= 2, segments.count == 1,
              segments[0].count == points.count,
              let first = points.first, let last = points.last,
              metric.value(last) == current else { return nil }
        return current - metric.value(first)
    }

    func percentage(_ metric: AssetOverviewMetric, current: Decimal) -> String? {
        guard current > 0, let delta = delta(metric, current: current), let first = points.first,
              metric.value(first) > 0 else { return nil }
        var raw = abs(delta) * 100 / metric.value(first)
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &raw, 1, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: rounded)).map { "\($0)%" }
    }
}
