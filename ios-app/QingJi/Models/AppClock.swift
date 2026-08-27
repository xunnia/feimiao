import Foundation

/// The app clock is real time in production and deterministic only for demo
/// screenshots. Keeping this switch in the app target avoids leaking test
/// environment concerns into QingJiCore's accounting rules.
enum AppClock {
    private static let demoDate: Date? = {
        guard ProcessInfo.processInfo.environment["QINGJI_DEMO"] == "1",
              let raw = ProcessInfo.processInfo.environment["QINGJI_DEMO_NOW"],
              !raw.isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashInDate, .withColonSeparatorInTime]
        return formatter.date(from: raw)
    }()

    static var now: Date { demoDate ?? Date() }
}
