import Foundation

/// Centralized task scheduling helpers used by every drag-and-drop drop
/// site. Before this existed, three near-identical commit blocks lived
/// in WeeklyView, DraggableTimeboxComponent, and DraggableTimeboxWeekContent
/// — each independently formatting `task.due`, deciding whether to keep
/// or delete the time window, and resolving the previous duration. One
/// of them (WeeklyView) used a UTC-format string that caused dates to
/// roll forward by one day in negative-offset timezones; the others had
/// already been migrated to local `yyyy-MM-dd`. Centralizing here lets
/// us write the formatting / window logic once and remove duplication.
///
/// Stateless: every entry point takes the data it needs and returns a
/// resolved value (or fires async work). No `static let shared` — this
/// is a namespace, not a manager.
@MainActor
enum TaskScheduler {

    // MARK: - Resolving tasks from a DraggableTaskInfo

    /// Looks up the task referenced by a `DraggableTaskInfo` payload in
    /// `TasksViewModel.shared` and returns it along with its account.
    /// Returns nil when the task can't be found (e.g. it was deleted
    /// between drag start and drop).
    static func resolveTask(_ info: DraggableTaskInfo) -> (task: GoogleTask, kind: GoogleAuthManager.AccountKind)? {
        let kind: GoogleAuthManager.AccountKind = info.accountKind == "personal" ? .account1 : .account2
        let dict = kind == .account1 ? TasksViewModel.shared.account1Tasks : TasksViewModel.shared.account2Tasks
        guard let task = dict[info.listId]?.first(where: { $0.id == info.taskId }) else { return nil }
        return (task, kind)
    }

    // MARK: - Date formatting

    /// Local-time-zone `yyyy-MM-dd` string. Google Tasks discards the
    /// time portion of `due`, so storing in local time keeps the date
    /// the user actually picked.
    static func formatDueDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    // MARK: - Duration resolution

    /// Returns a duration in seconds for a task being dropped onto the
    /// timeline. Reuses the task's existing non-all-day window duration
    /// when available, otherwise returns `fallback` (default 30 minutes).
    static func resolvedDuration(forTaskId taskId: String, fallback: TimeInterval = 30 * 60) -> TimeInterval {
        guard let prior = TaskTimeWindowManager.shared.getTimeWindow(for: taskId), !prior.isAllDay else {
            return fallback
        }
        return max(60, prior.endTime.timeIntervalSince(prior.startTime))
    }

    // MARK: - Schedule actions

    /// Drop / move a task to a date as **all-day**: writes the local
    /// `yyyy-MM-dd` to `due` and removes any existing time window.
    /// No-ops if `due` is already that date — caller can still rely on
    /// the return value to know whether anything changed.
    @discardableResult
    static func scheduleAllDay(
        task: GoogleTask,
        listId: String,
        kind: GoogleAuthManager.AccountKind,
        on date: Date
    ) -> Bool {
        let newDueString = formatDueDate(date)
        let dueChanged = task.due != newDueString
        TaskTimeWindowManager.shared.deleteTimeWindow(for: task.id)
        if dueChanged {
            var updated = task
            updated.due = newDueString
            Task { await TasksViewModel.shared.updateTask(updated, in: listId, for: kind) }
        }
        return dueChanged
    }

    /// Drop / move a task to a date+time. Writes the local-date `due`
    /// for the day, writes a non-all-day TaskTimeWindow with the given
    /// start + duration, and persists. End time is clamped to the same
    /// day so `saveTimeWindow`'s same-day validator always passes.
    @discardableResult
    static func scheduleTimed(
        task: GoogleTask,
        listId: String,
        kind: GoogleAuthManager.AccountKind,
        start: Date,
        duration: TimeInterval
    ) -> Bool {
        let cal = Calendar.current
        let rawEnd = start.addingTimeInterval(duration)
        let endTime: Date
        if cal.isDate(start, inSameDayAs: rawEnd) {
            endTime = rawEnd
        } else {
            // Edge case: drop at e.g. 23:45 with a 30-min duration crosses
            // midnight. Clamp to end of same day so the window stays valid.
            endTime = cal.date(bySettingHour: 23, minute: 59, second: 0, of: start) ?? start
        }

        TaskTimeWindowManager.shared.saveTimeWindow(
            taskId: task.id,
            startTime: start,
            endTime: endTime,
            isAllDay: false
        )

        let newDueString = formatDueDate(start)
        let dueChanged = task.due != newDueString
        if dueChanged {
            var updated = task
            updated.due = newDueString
            Task { await TasksViewModel.shared.updateTask(updated, in: listId, for: kind) }
        }
        return dueChanged
    }
}
