import Foundation
import SwiftData
import UserNotifications

@Model
final class AIReportScheduleRecord {
    var stableID: UUID = UUID()
    var sessionID: UUID? = nil
    var title: String = ""
    var reportType: String = "monthly"
    var periodKind: String = "monthly"
    var dayValue: Int = 1
    var enabled: Bool = true
    var nextRunAt: Date = Date()
    var providerID: UUID? = nil
    var model: String = ""
    var effortRaw: String = "low"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        stableID: UUID = UUID(),
        sessionID: UUID? = nil,
        title: String,
        reportType: String = "monthly",
        periodKind: String = "monthly",
        dayValue: Int = 1,
        enabled: Bool = true,
        nextRunAt: Date = Date(),
        providerID: UUID? = nil,
        model: String = "",
        effortRaw: String = "low"
    ) {
        self.stableID = stableID
        self.sessionID = sessionID
        self.title = title
        self.reportType = reportType
        self.periodKind = periodKind
        self.dayValue = dayValue
        self.enabled = enabled
        self.nextRunAt = nextRunAt
        self.providerID = providerID
        self.model = model
        self.effortRaw = effortRaw
    }
}

enum AIReportScheduleStore {
    static func createMonthly(
        in context: ModelContext,
        provider: AIProviderAccount?
    ) throws -> AIReportScheduleRecord {
        let next = nextMonthlyDate(after: Date())
        let schedule = AIReportScheduleRecord(
            title: "每月账本报告",
            reportType: "monthly",
            periodKind: "monthly",
            dayValue: 1,
            nextRunAt: next,
            providerID: provider?.id,
            model: provider?.model ?? "",
            effortRaw: provider?.effort.rawValue ?? AIReasoningEffort.low.rawValue
        )
        context.insert(schedule)
        try context.save()
        return schedule
    }

    static func delete(_ schedule: AIReportScheduleRecord, in context: ModelContext) throws {
        context.delete(schedule)
        try context.save()
    }

    static func setEnabled(
        _ schedule: AIReportScheduleRecord,
        enabled: Bool,
        in context: ModelContext
    ) throws {
        schedule.enabled = enabled
        schedule.updatedAt = Date()
        try context.save()
    }

    private static func nextMonthlyDate(after date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? date
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start)
            ?? date.addingTimeInterval(31 * 86_400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextMonth)
            ?? nextMonth
    }
}

/// iOS 的定时报表对应 Android 的提醒入口。
///
/// iOS 不允许应用保证在固定时刻后台联网生成 AI 报告，所以这里排程的是
/// 本地通知：到期提醒用户打开 App，再由前台使用当前服务商生成报告。计划
/// 仍然持久化在 SwiftData，通知只是可重建的派生状态。
@MainActor
enum AIReportScheduleScheduler {
    private static let identifierPrefix = "feimiao.ai-report."

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        )) ?? false
    }

    static func rescheduleAll(in context: ModelContext, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await pendingRequests(center: center)
        let oldIDs = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        if !oldIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        }

        let schedules = (try? context.fetch(FetchDescriptor<AIReportScheduleRecord>())) ?? []
        var changed = false
        for schedule in schedules where schedule.enabled {
            let nextRun = normalizedNextRun(
                schedule.nextRunAt,
                periodKind: schedule.periodKind,
                now: now
            )
            if nextRun != schedule.nextRunAt {
                schedule.nextRunAt = nextRun
                schedule.updatedAt = now
                changed = true
            }
            scheduleNotification(center: center, schedule: schedule)
        }
        if changed { try? context.save() }
    }

    static func cancel(_ schedule: AIReportScheduleRecord) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationID(for: schedule)]
        )
    }

    private static func scheduleNotification(
        center: UNUserNotificationCenter,
        schedule: AIReportScheduleRecord
    ) {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: schedule.nextRunAt
        )
        let content = UNMutableNotificationContent()
        content.title = "肥喵定时报表"
        content.body = "\(schedule.title)已到时间，打开肥喵记账生成最新报告。"
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(
            identifier: notificationID(for: schedule),
            content: content,
            trigger: trigger
        ))
    }

    private static func notificationID(for schedule: AIReportScheduleRecord) -> String {
        "\(identifierPrefix)\(schedule.stableID.uuidString)"
    }

    private static func normalizedNextRun(
        _ date: Date,
        periodKind: String,
        now: Date
    ) -> Date {
        var candidate = notificationDate(date)
        repeat {
            guard candidate <= now else { return candidate }
            candidate = advance(candidate, periodKind: periodKind)
        } while true
    }

    private static func advance(_ date: Date, periodKind: String) -> Date {
        let calendar = Calendar.current
        switch periodKind {
        case "weekly":
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date.addingTimeInterval(7 * 86_400)
        case "daily":
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        default:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(31 * 86_400)
        }
    }

    private static func notificationDate(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private static func pendingRequests(
        center: UNUserNotificationCenter
    ) async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }
}
