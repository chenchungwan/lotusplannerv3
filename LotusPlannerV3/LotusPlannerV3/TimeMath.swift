import Foundation

/// Time-of-day arithmetic shared across views that schedule events
/// and tasks. Centralizing the "next half-hour boundary" rule means
/// one source of truth — previously TaskDetailsView, AddEventView,
/// and BulkEditComponents each had their own copy.
enum TimeMath {

    /// Default duration applied to an item being newly scheduled (or
    /// converted from all-day to timed) when no prior duration is
    /// known. 30 minutes feels short enough to require a deliberate
    /// extension, long enough to be useful out of the box.
    static let defaultEventDuration: TimeInterval = 30 * 60

    /// Returns the next 30-minute boundary strictly after `reference`
    /// (typically `Date()`), expressed as `(hour, minute)` in 24-hour.
    /// Examples: 12:17 → (12, 30), 12:30 → (13, 0), 12:45 → (13, 0).
    static func nextHalfHour(after reference: Date = Date()) -> (hour: Int, minute: Int) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: reference)
        let hour = comps.hour ?? 9
        let minute = comps.minute ?? 0
        if minute < 30 {
            return (hour, 30)
        } else {
            return ((hour + 1) % 24, 0)
        }
    }

    /// Default time-of-day window when converting an all-day item to
    /// timed: start = next half-hour boundary after `referenceTime`,
    /// re-anchored onto `date`'s calendar day. End = start + 30 min.
    ///
    /// The hour/minute is rebound onto `date` so the user can be
    /// editing a task whose due date isn't today and still get a
    /// sensible default time of day.
    static func defaultTimedWindow(
        on date: Date,
        referenceTime: Date = Date()
    ) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let (h, m) = nextHalfHour(after: referenceTime)
        let start = cal.date(bySettingHour: h, minute: m, second: 0, of: date)
            ?? cal.startOfDay(for: date)
        let end = cal.date(byAdding: .minute, value: 30, to: start)
            ?? start.addingTimeInterval(defaultEventDuration)
        return (start, end)
    }
}
