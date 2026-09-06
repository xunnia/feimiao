import Foundation

/// Calendar factory for budget civil-day calculations.
///
/// Budget dates are local calendar dates, not elapsed 24-hour durations.  A
/// plan therefore carries a named IANA time-zone identifier so opening the app
/// after travelling does not move a cycle boundary to a different day.
public enum BudgetBusinessCalendar {
    /// Older Android rows may not have a real time-zone identifier.  Keep this
    /// marker readable; callers fall back to the device zone only for those
    /// legacy rows because their original zone cannot be reconstructed.
    public static let legacyDeviceLocalIdentifier = "device_local"

    /// The identifier to persist for a newly created plan on this device.
    public static var currentTimeZoneIdentifier: String {
        persistentTimeZoneIdentifier(for: .current)
    }

    /// Returns a stable identifier suitable for a newly persisted record.
    public static func persistentTimeZoneIdentifier(for timeZone: TimeZone) -> String {
        let identifier = timeZone.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            return offsetIdentifier(for: timeZone)
        }
        return identifier
    }

    /// Validates a stored identifier without rewriting the legacy marker.
    public static func normalizedIdentifier(
        _ rawIdentifier: String?,
        fallback: TimeZone = .current
    ) -> String {
        let value = rawIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            return persistentTimeZoneIdentifier(for: fallback)
        }
        if value == legacyDeviceLocalIdentifier {
            return value
        }
        return TimeZone(identifier: value) == nil
            ? persistentTimeZoneIdentifier(for: fallback)
            : value
    }

    /// Builds a Gregorian calendar in the plan's business time zone.
    /// `device_local` and invalid identifiers intentionally use `fallback` for
    /// backwards compatibility with old records that did not persist a zone.
    public static func calendar(
        for rawIdentifier: String?,
        fallback: Calendar = .current
    ) -> Calendar {
        let value = rawIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty,
              value != legacyDeviceLocalIdentifier,
              let timeZone = TimeZone(identifier: value) else {
            return fallback
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = fallback.locale
        calendar.firstWeekday = fallback.firstWeekday
        calendar.minimumDaysInFirstWeek = fallback.minimumDaysInFirstWeek
        return calendar
    }

    private static func offsetIdentifier(for timeZone: TimeZone) -> String {
        let totalMinutes = abs(timeZone.secondsFromGMT()) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let sign = timeZone.secondsFromGMT() < 0 ? "-" : "+"
        return String(format: "GMT%@%02d%02d", sign, hours, minutes)
    }
}
