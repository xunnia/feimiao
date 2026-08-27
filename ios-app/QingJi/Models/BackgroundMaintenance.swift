import BackgroundTasks
import Foundation
import SwiftData

/// iOS 的后台执行是系统择机调度，不能承诺 Android WorkManager 的固定时刻。
enum BackgroundMaintenance {
    static let reportRefreshIdentifier = "com.qingji.app.report-refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: reportRefreshIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task)
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: reportRefreshIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        Task { @MainActor in
            defer {
                task.setTaskCompleted(success: true)
                schedule()
            }
            let context = ModelContext(AppModelContainer.shared)
            guard let transactions = try? context.fetch(FetchDescriptor<MoneyTransaction>()),
                  let books = try? context.fetch(FetchDescriptor<Book>()) else { return }
            let now = AppClock.now
            for book in books where book.includeInTotal {
                let hasCurrentReport = (try? context.fetch(FetchDescriptor<ReportRecord>()))?.contains {
                    $0.bookID == book.stableID &&
                    Calendar.current.isDate($0.periodStart, equalTo: now, toGranularity: .month) &&
                    $0.type == "monthly"
                } ?? false
                if !hasCurrentReport {
                    _ = try? ReportStore.createMonthly(
                        in: context,
                        transactions: transactions,
                        bookID: book.stableID,
                        month: now
                    )
                }
            }
        }
    }
}
