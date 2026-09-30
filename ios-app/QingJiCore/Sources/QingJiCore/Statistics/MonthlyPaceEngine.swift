import Foundation

public struct MonthlyPaceSample: Equatable, Sendable {
    public let label: String
    public let full: Decimal
    public let pace: Decimal
    public let isCurrent: Bool
    /// 这个月在「开始记账」之后。之前的月是缺数据，不进平均；
    /// 之后的月哪怕一分没花（真实 0）也要进平均的分母（07 案例 63）。
    public let isTracked: Bool
}

public struct MonthlyPaceProjection: Equatable, Sendable {
    public let samples: [MonthlyPaceSample]
    public let average: Decimal
    public let current: Decimal
    public let cutoffDay: Int
    public let title: String
    /// 可用历史月达到 [MonthlyPaceEngine.minSamples]。false 时界面显示「--」。
    public let hasAverage: Bool
    public let sampleCount: Int
}

/// The current month compared with the same day in each of the previous six months.
/// 统计页进度卡和桌面小组件共用（07 案例 74），规则和安卓 core/statistics/monthly_pace.dart 一致。
public enum MonthlyPaceEngine {
    /// 「同期平均」至少要几个历史月（用户 2026-09-30 定：2 个月）。
    public static let minSamples = 2
    /// 「基本持平」的上下界：和平均差不超过 8%。
    public static let flatBand = 0.08

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
        var firstKey: Int?
        for record in LedgerPolicy.userRecords(from: records) {
            let parts = calendar.dateComponents([.year, .month, .day], from: record.date)
            let key = (parts.year ?? 0) * 100 + (parts.month ?? 0)
            // 开始记账的月份：看任何一条记录（收入、转账也算在用）。
            if firstKey.map({ key < $0 }) ?? true { firstKey = key }
            // 非正额（全额退款的原单、老数据负数冲账）不计入。
            guard record.kind == .expense, record.amount > 0, let limit = cutoffs[key] else { continue }
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
                pace: pace, isCurrent: current,
                isTracked: current || (firstKey.map { key >= $0 } ?? false)
            )
        }
        let comparable = samples.filter { !$0.isCurrent && $0.isTracked }.map(\.pace)
        let hasAverage = comparable.count >= minSamples
        let average: Decimal
        if hasAverage {
            var raw = comparable.reduce(Decimal.zero, +) / Decimal(comparable.count)
            var rounded = Decimal.zero
            NSDecimalRound(&rounded, &raw, 2, .plain)
            average = rounded
        } else {
            average = 0
        }
        let current = samples.last?.pace ?? 0
        // 翻到过去的月份不能再写「本月」；和周视图的「该周」、安卓一致。
        let periodName = isCurrent ? "本月" : "该月"
        let title: String
        if hasAverage {
            title = "截至 \(month)月\(cutoff)日，\(periodName)支出与往常\(relation(current: current, average: average))"
        } else {
            title = current > 0
                ? "截至 \(month)月\(cutoff)日，\(periodName)已有支出记录"
                : "截至 \(month)月\(cutoff)日，\(periodName)还没有支出"
        }
        return MonthlyPaceProjection(samples: samples, average: average,
                                     current: current, cutoffDay: cutoff, title: title,
                                     hasAverage: hasAverage, sampleCount: comparable.count)
    }

    /// 偏高 / 基本持平 / 偏低。平均是 0 时：本期也是 0 算持平，否则偏高。
    public static func relation(current: Decimal, average: Decimal) -> String {
        let cur = NSDecimalNumber(decimal: current).doubleValue
        let avg = NSDecimalNumber(decimal: average).doubleValue
        if avg <= 0 { return cur <= 0 ? "基本持平" : "偏高" }
        let change = (cur - avg) / avg
        if abs(change) <= flatBand { return "基本持平" }
        return change > 0 ? "偏高" : "偏低"
    }
}
