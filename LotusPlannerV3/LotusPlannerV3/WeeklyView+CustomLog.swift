import SwiftUI

/// Whether-any-custom-logs-exist guards used by the per-collection visibility logic. Small enough to keep in its own file because it mirrors the per-collection symmetry (collection 0 vs collection 1) visible from the call sites.
extension WeeklyView {

    /// True when collection 0 has any enabled items. Legacy helper; new
    /// callers should pass an explicit collection index.
    func hasCustomLogsForWeek() -> Bool {
        hasCustomLogsForWeek(in: 0)
    }

    func hasCustomLogsForDate(_ date: Date) -> Bool {
        hasCustomLogsForDate(date, in: 0)
    }

    func hasCustomLogsForWeek(in collection: Int) -> Bool {
        customLogManager.items(in: collection).contains { $0.isEnabled }
    }

    func hasCustomLogsForDate(_ date: Date, in collection: Int) -> Bool {
        customLogManager.items(in: collection).contains { $0.isEnabled }
    }
}
