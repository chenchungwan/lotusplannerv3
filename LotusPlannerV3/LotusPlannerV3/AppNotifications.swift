import Foundation

extension Notification.Name {
    // MARK: - App Navigation
    static let bookViewNavigateToDay = Notification.Name("BookViewNavigateToDay")
    static let bookViewNavigateToWeek = Notification.Name("BookViewNavigateToWeek")
    static let bookViewNavigateToMonth = Notification.Name("BookViewNavigateToMonth")
    static let bookViewNavigateToYear = Notification.Name("BookViewNavigateToYear")
    static let bookViewNavigateToTimebox = Notification.Name("BookViewNavigateToTimebox")

    // MARK: - Calendar
    static let refreshCalendarData = Notification.Name("RefreshCalendarData")
    static let toggleCalendarBulkEdit = Notification.Name("ToggleCalendarBulkEdit")
    static let toggleWeeklyCalendarBulkEdit = Notification.Name("ToggleWeeklyCalendarBulkEdit")

    // MARK: - Tasks
    static let showAddTask = Notification.Name("LPV3_ShowAddTask")
    static let showAddEvent = Notification.Name("LPV3_ShowAddEvent")
    static let showAllTasksRequested = Notification.Name("ShowAllTasksRequested")
    static let setAllTasksSubfilter = Notification.Name("SetAllTasksSubfilter")
    static let filterTasksToCurrentDay = Notification.Name("FilterTasksToCurrentDay")
    static let filterTasksToCurrentWeek = Notification.Name("FilterTasksToCurrentWeek")
    static let filterTasksToCurrentMonth = Notification.Name("FilterTasksToCurrentMonth")
    static let filterTasksToCurrentYear = Notification.Name("FilterTasksToCurrentYear")
    static let toggleTasksBulkEdit = Notification.Name("ToggleTasksBulkEdit")
    static let toggleListsBulkEdit = Notification.Name("ToggleListsBulkEdit")
    static let toggleTimeboxBulkEdit = Notification.Name("ToggleTimeboxBulkEdit")
    static let toggleBookViewBulkEdit = Notification.Name("ToggleBookViewBulkEdit")

    // MARK: - Goals and Journal
    static let showAddGoal = Notification.Name("ShowAddGoal")
    static let showAddCategory = Notification.Name("ShowAddCategory")
    static let refreshAllGoalsView = Notification.Name("RefreshAllGoalsView")
    static let refreshJournalContent = Notification.Name("RefreshJournalContent")
    static let refreshAllData = Notification.Name("RefreshAllData")
    static let journalFileChangedFromICloud = Notification.Name("JournalFileChangedFromiCloud")
    static let triggerJournalAutoSave = Notification.Name("TriggerJournalAutoSave")

    // MARK: - Sync
    static let iCloudDataChanged = Notification.Name("iCloudDataChanged")
    static let cloudKitImportCompleted = Notification.Name("cloudKitImportCompleted")
}
