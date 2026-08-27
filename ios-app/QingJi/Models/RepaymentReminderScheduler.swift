import Foundation
import SwiftData
import UserNotifications

/// Android 还款提醒的 iOS 等价实现。
///
/// iOS 由系统维护本地通知，不能保证像 WorkManager 一样在任意后台时刻
/// 执行代码；因此这里只预排未来的提醒，不伪装成后台任务执行保证。
@MainActor
enum RepaymentReminderScheduler {
    private static let identifierPrefix = "feimiao.repayment."

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        )) ?? false
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await pendingRequests(center: center)
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func reschedule(context: ModelContext, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await pendingRequests(center: center)
        let oldIDs = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        if !oldIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        }

        let profiles = (try? context.fetch(FetchDescriptor<LiabilityProfile>())) ?? []
        for profile in profiles where profile.lifecycle == .active && profile.currentPrincipal > 0 {
            guard let dueDate = nextDueDate(for: profile, now: now) else { continue }
            let before = Calendar.current.date(byAdding: .day, value: -1, to: dueDate)
            if let before, before >= now {
                schedule(
                    center: center,
                    profile: profile,
                    date: before,
                    suffix: "before",
                    body: "\(profile.kind.label) 明天到还款日，当前本金 \(money(profile.currentPrincipal, currency: profile.currencyCode))"
                )
            }
            if dueDate >= now {
                schedule(
                    center: center,
                    profile: profile,
                    date: dueDate,
                    suffix: "due",
                    body: "\(profile.kind.label) 今天是还款日，当前本金 \(money(profile.currentPrincipal, currency: profile.currencyCode))"
                )
            }
        }
    }

    private static func schedule(
        center: UNUserNotificationCenter,
        profile: LiabilityProfile,
        date: Date,
        suffix: String,
        body: String
    ) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        let content = UNMutableNotificationContent()
        content.title = "肥喵还款提醒"
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)\(profile.stableID.uuidString).\(suffix)",
            content: content,
            trigger: trigger
        )
        center.add(request)
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

    private static func nextDueDate(for profile: LiabilityProfile, now: Date) -> Date? {
        let calendar = Calendar.current
        if let dueDate = profile.dueDate {
            return calendar.startOfDay(for: dueDate) >= calendar.startOfDay(for: now)
                ? calendar.startOfDay(for: dueDate)
                : nil
        }
        guard let paymentDay = profile.paymentDay,
              (1...31).contains(paymentDay) else { return nil }
        let today = calendar.startOfDay(for: now)
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = clampedDay(
            paymentDay,
            year: components.year ?? 2000,
            month: components.month ?? 1,
            calendar: calendar
        )
        guard var candidate = calendar.date(from: components) else { return nil }
        if candidate < today {
            candidate = calendar.date(byAdding: .month, value: 1, to: candidate) ?? candidate
            let nextComponents = calendar.dateComponents([.year, .month], from: candidate)
            components.year = nextComponents.year
            components.month = nextComponents.month
            components.day = clampedDay(
                paymentDay,
                year: nextComponents.year ?? 2000,
                month: nextComponents.month ?? 1,
                calendar: calendar
            )
            candidate = calendar.date(from: components) ?? candidate
        }
        return calendar.startOfDay(for: candidate)
    }

    private static func clampedDay(_ day: Int, year: Int, month: Int, calendar: Calendar) -> Int {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return min(max(day, 1), 28)
        }
        return min(max(day, 1), range.count)
    }

    private static func money(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency).presentation(.narrow))
    }
}
