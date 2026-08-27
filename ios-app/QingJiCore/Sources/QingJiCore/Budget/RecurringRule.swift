import Foundation

/// 周期记账的频率。日期推进按设备当前日历计算，月末日期会夹取到目标月最后一天。
public enum RecurringPeriod: String, Codable, CaseIterable, Hashable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly

    public var label: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }

    /// 推进一次到期日。monthly/yearly 会保留初始锚定日，例如 31 号规则在
    /// 2 月落到 28 号，下一次仍回到 31 号，而不是永久漂移成 28 号。
    public func advance(
        _ date: Date,
        anchorDay: Int? = nil,
        calendar: Calendar = .current
    ) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            return advanceCalendarMonth(date, years: 0, anchorDay: anchorDay, calendar: calendar)
        case .yearly:
            return advanceCalendarMonth(date, years: 1, anchorDay: anchorDay, calendar: calendar)
        }
    }

    /// 预览规则接下来会生成的日期，不写入数据库。
    public func previewDates(
        from firstDue: Date,
        count: Int = 3,
        endDate: Date? = nil,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }
        let anchor = (self == .monthly || self == .yearly)
            ? calendar.component(.day, from: firstDue)
            : nil
        let end = endDate.map { endOfDay($0, calendar: calendar) }
        var result: [Date] = []
        var due = firstDue
        for _ in 0..<count {
            if let end, due > end { break }
            result.append(due)
            due = advance(due, anchorDay: anchor, calendar: calendar)
        }
        return result
    }

    private func advanceCalendarMonth(
        _ date: Date,
        years: Int,
        anchorDay: Int?,
        calendar: Calendar
    ) -> Date {
        let currentDay = calendar.component(.day, from: date)
        let requestedDay = min(max(anchorDay ?? currentDay, 1), 31)
        var startComponents = calendar.dateComponents([.year, .month], from: date)
        startComponents.day = 1
        guard let firstOfMonth = calendar.date(from: startComponents),
              let targetMonth = calendar.date(
                  byAdding: years == 0 ? .month : .year,
                  value: years == 0 ? 1 : years,
                  to: firstOfMonth
              ),
              let dayRange = calendar.range(of: .day, in: .month, for: targetMonth) else {
            return date
        }
        let targetDay = min(requestedDay, dayRange.count)
        var target = calendar.date(byAdding: .day, value: targetDay - 1, to: targetMonth) ?? targetMonth
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        target = calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: target
        ) ?? target
        return target
    }

    private func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, nanosecond: -1), to: start) ?? date
    }
}
