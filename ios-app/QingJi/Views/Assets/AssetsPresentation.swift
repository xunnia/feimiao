import Foundation
import QingJiCore

enum AssetsFundsFilter: String, CaseIterable, Identifiable {
    case all, accounts, investment, receivables, liabilities
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "全部"
        case .accounts: return "账户"
        case .investment: return "投资"
        case .receivables: return "权益"
        case .liabilities: return "负债"
        }
    }
    func includes(_ kind: AccountKind, balance: Decimal = 0) -> Bool {
        switch self {
        case .all: return true
        case .accounts: return !kind.isLiability && kind != .investment
        case .investment: return kind == .investment
        case .receivables: return false
        case .liabilities: return kind.isLiability || balance < 0
        }
    }
}

enum AssetsFundsSort: String, CaseIterable, Identifiable {
    case recent, name, manual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return "最近更新"
        case .name: return "名称"
        case .manual: return "自定义顺序"
        }
    }
}

/// Read-only presentation rules; no balance, cost, or checkpoint is written here.
enum AssetsPresentation {
    static func matches(_ query: String, values: String...) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || values.contains { $0.localizedStandardContains(text) }
    }

    static func physicalDailyValue(_ metrics: PhysicalAssetMetrics?, costSource: String) -> Decimal? {
        costSource == AssetAcquisitionCostSource.manualUnknown.rawValue ? nil : metrics?.dailyHoldingCost.value
    }

    static func latestCalibration(accountID: UUID, checkpoints: [AccountBalanceCheckpointRecord],
                                  now: Date) -> AccountBalanceCheckpointRecord? {
        let records = checkpoints.filter { $0.accountID == accountID }
        let reversed = Set(records.filter {
            $0.eventKindRaw == "reversal" && $0.status == "active" && $0.effectiveAt <= now
        }.compactMap(\.reversalOfID))
        return records.filter {
            $0.eventKindRaw == "anchor" && $0.status == "active" && $0.effectiveAt <= now
                && !reversed.contains($0.stableID)
        }.max {
            if $0.effectiveAt != $1.effectiveAt { return $0.effectiveAt < $1.effectiveAt }
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.createdAt < $1.createdAt
        }
    }

    static func calibrationText(_ checkpoint: AccountBalanceCheckpointRecord?, now: Date,
                                calendar: Calendar = .current) -> String {
        guard let checkpoint else { return "从未校准" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: checkpoint.effectiveAt),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days == 0 { return "今天校准" }
        return days > 30 ? "\(days) 天未校准" : "\(days) 天前校准"
    }

    struct VerifiedChange {
        let earlierDate: Date
        let laterDate: Date
        let amount: Decimal
    }

    static func verifiedChange(_ records: [NetWorthVerifiedCheckpointRecord], now: Date) -> VerifiedChange? {
        // Compare complete frozen headers, never today's live balance or a partial checkpoint.
        let latest = records.filter {
            $0.statusRaw == "active" && $0.completenessRaw == "complete" && $0.asOf <= now
        }
            .sorted { $0.asOf == $1.asOf ? $0.createdAt > $1.createdAt : $0.asOf > $1.asOf }
        guard latest.count >= 2 else { return nil }
        let later = latest[0], earlier = latest[1]
        guard earlier.asOf < later.asOf, eligible(earlier), eligible(later),
              earlier.knowledgeCutoff <= now, later.knowledgeCutoff <= now,
              earlier.scopeVersion == later.scopeVersion,
              earlier.calculationVersion == later.calculationVersion,
              coverage(earlier.currencyCoverageJSON) == coverage(later.currencyCoverageJSON) else { return nil }
        return VerifiedChange(earlierDate: earlier.asOf, laterDate: later.asOf,
                              amount: later.netWorth - earlier.netWorth)
    }

    private static func coverage(_ raw: String) -> [String]? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["base_currency"] as? String == "CNY",
              let covered = object["covered"] as? [String], covered.contains("CNY"),
              let uncovered = object["uncovered"] as? [String], uncovered.isEmpty else { return nil }
        return Array(Set(covered)).sorted()
    }

    private static func eligible(_ record: NetWorthVerifiedCheckpointRecord) -> Bool {
        guard record.completenessRaw == "complete", record.scopeVersion > 0,
              record.calculationVersion > 0, record.knowledgeCutoff >= record.asOf,
              record.totalAssets >= 0, record.totalLiabilities >= 0,
              record.netWorth == record.totalAssets - record.totalLiabilities,
              coverage(record.currencyCoverageJSON) != nil,
              let reasonData = record.reasonsJSON.data(using: .utf8),
              let reasons = try? JSONSerialization.jsonObject(with: reasonData) as? [Any], reasons.isEmpty,
              let itemData = record.itemsJSON.data(using: .utf8) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let items = try? decoder.decode([BackupNetWorthVerifiedCheckpointItem].self, from: itemData),
              !items.isEmpty || (record.totalAssets == 0 && record.totalLiabilities == 0) else { return false }
        let keys = items.map { "\($0.objectType)/\($0.objectUUID)" }
        guard Set(keys).count == keys.count && items.allSatisfy({
            $0.checkpointID == record.stableID
                && ["account", "liability_profile", "physical_asset", "receivable_asset"].contains($0.objectType)
                && !$0.objectUUID.isEmpty
                && !$0.valueSource.isEmpty && !["unknown", "missing_valuation"].contains($0.valueSource)
                && ["exact", "confirmed", "accepted_stale", "legacy_hybrid"].contains($0.quality)
                && $0.currencyCode == "CNY"
                && $0.valueEffectiveAt <= record.asOf
        }) else { return false }
        let assets = items.filter { $0.confirmedAmount >= 0 }.reduce(Decimal.zero) { $0 + $1.confirmedAmount }
        let liabilities = items.filter { $0.confirmedAmount < 0 }.reduce(Decimal.zero) { $0 - $1.confirmedAmount }
        return assets == record.totalAssets && liabilities == record.totalLiabilities
    }
}
