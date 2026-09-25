import Foundation

public struct MonthlyPaceSample: Equatable, Sendable {
    public let label: String
    public let full: Decimal
    public let pace: Decimal
    public let isCurrent: Bool
}

public struct MonthlyPaceProjection: Equatable, Sendable {
    public let samples: [MonthlyPaceSample]
    public let average: Decimal
    public let current: Decimal
    public let cutoffDay: Int
    public let title: String
}

/// The current month compared with the same day in each of the previous six months.
public enum MonthlyPaceEngine {
    public static func project(
        records: [TransactionRecord], year: Int, month: Int,
        now: Date, calendar: Calendar = .current
    ) -> MonthlyPaceProjection {
        let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1))
            ?? calendar.startOfDay(for: now)
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let isCurrent = today.year == year && today.month == month
        let lastDay = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let cutoff = isCurrent ? min(today.day ?? 1, lastDay) : lastDay

        let months: [Date] = (0...6).map { offset in
            calendar.date(byAdding: .month, value: offset - 6, to: monthStart) ?? monthStart
        }
        var cutoffs: [Int: Int] = [:]
        for date in months {
            let parts = calendar.dateComponents([.year, .month], from: date)
            let key = (parts.year ?? year) * 100 + (parts.month ?? month)
            let days = calendar.range(of: .day, in: .month, for: date)?.count ?? cutoff
            cutoffs[key] = key == year * 100 + month ? cutoff : min(cutoff, days)
        }

        var fullByMonth: [Int: Decimal] = [:]
        var paceByMonth: [Int: Decimal] = [:]
        for record in LedgerPolicy.userRecords(from: records) where record.kind == .expense {
            let parts = calendar.dateComponents([.year, .month, .day], from: record.date)
            let key = (parts.year ?? 0) * 100 + (parts.month ?? 0)
            guard let limit = cutoffs[key] else { continue }
            fullByMonth[key, default: 0] += record.amount
            if (parts.day ?? 0) <= limit {
                paceByMonth[key, default: 0] += record.amount
            }
        }

        let samples: [MonthlyPaceSample] = months.map { date in
            let parts = calendar.dateComponents([.year, .month], from: date)
            let valueMonth = parts.month ?? month
            let key = (parts.year ?? year) * 100 + valueMonth
            let current = key == year * 100 + month
            let pace = paceByMonth[key] ?? 0
            return MonthlyPaceSample(
                label: "\(valueMonth)月", full: current ? pace : (fullByMonth[key] ?? 0),
                pace: pace, isCurrent: current
            )
        }
        let comparable = samples.filter { !$0.isCurrent && $0.pace > 0 }.map(\.pace)
        let average: Decimal
        if comparable.isEmpty {
            average = 0
        } else {
            var raw = comparable.reduce(Decimal.zero, +) / Decimal(comparable.count)
            var rounded = Decimal.zero
            NSDecimalRound(&rounded, &raw, 2, .plain)
            average = rounded
        }
        let current = samples.last?.pace ?? 0
        let relation: String
        if average <= 0 {
            relation = "已有支出记录"
        } else {
            let change = (NSDecimalNumber(decimal: current).doubleValue -
                          NSDecimalNumber(decimal: average).doubleValue) /
                          NSDecimalNumber(decimal: average).doubleValue
            relation = abs(change) <= 0.08 ? "基本持平" : (change > 0 ? "偏高" : "偏低")
        }
        let title = average <= 0
            ? "截至 \(month)月\(cutoff)日，本月已有支出记录"
            : "截至 \(month)月\(cutoff)日，本月支出与往常\(relation)"
        return MonthlyPaceProjection(samples: samples, average: average,
                                     current: current, cutoffDay: cutoff, title: title)
    }
}
