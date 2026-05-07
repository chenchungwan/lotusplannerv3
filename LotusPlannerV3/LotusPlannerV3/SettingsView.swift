import SwiftUI
import CoreData
import CloudKit
#if os(iOS)
import UIKit
#endif

#Preview {
    SettingsView()
}
extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Day View Layout Option Enum
enum DayViewLayoutOption: Int, CaseIterable, Identifiable {
    case compact = 0
    case mobile = 4
    case timebox = 6
    case newClassic = 8
    case custom = 10

    var id: Int { rawValue }
    static var allCases: [DayViewLayoutOption] { [.newClassic, .compact, .timebox, .mobile, .custom] }

    var displayName: String {
        switch self {
        case .compact: "Compact"
        case .mobile: "Mobile"
        case .timebox: "Expanded"
        case .newClassic: "Classic"
        case .custom: "Custom"
        }
    }

    var description: String {
        switch self {
        case .compact: "Events and Tasks on left with collapsible logs, Journal on right"
        case .mobile: "Single column: Events, Personal Tasks, Professional Tasks, then Logs"
        case .timebox: "Timebox timeline on left with collapsible logs, Journal on right (swipe for 2nd page)"
        case .newClassic: "Timebox timeline with collapsible logs on left, Tasks and Journal on right (1 page)"
        case .custom: "A blank day view you can configure yourself."
        }
    }

    var isBeta: Bool {
        self == .custom
    }
}

// MARK: - Shared Timeline Interval
enum TimelineInterval: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", year = "Year"

    var id: String { rawValue }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day:     return .day
        case .week:    return .weekOfYear
        case .month:   return .month
        case .year:    return .year
        }
    }
    
    // SF Symbol for navigation buttons
    var sfSymbol: String {
        switch self {
        case .day: return "d.circle"
        case .week: return "w.circle"
        case .month: return "m.circle"
        case .year: return "y.circle"
        }
    }
    
    // Convert to TaskFilter
    var taskFilter: TaskFilter {
        switch self {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        }
    }
}

// Extension for TaskFilter to convert to TimelineInterval
extension TaskFilter {
    var timelineInterval: TimelineInterval? {
        switch self {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        case .all: return nil // .all doesn't have a calendar equivalent
        }
    }
}

// MARK: - Navigation Manager
@MainActor
class NavigationManager: ObservableObject {
    static let shared = NavigationManager()
    
    enum CurrentView {
        case calendar
        case tasks
        case lists
        case goals
        case journal
        case journalDayViews
        case weeklyView
        case gWeekView
        case yearlyCalendar
        case timebox
        case bookView
    }
    
    @Published var currentView: CurrentView = .calendar
    @Published var showTasksView = false
    @Published var currentInterval: TimelineInterval = .day
    @Published var currentDate: Date = Date()
    @Published var viewRefreshCounter: Int = 0
    @Published var showingSettings = false
    @Published var showingAllTasks = false
    @Published var isShowingTimebox = false

    private init() {}
    
    func switchToCalendar() {
        // Set the appropriate calendar view based on current interval
        if currentInterval == .year {
            currentView = .yearlyCalendar
        } else {
            currentView = .calendar
        }
        showTasksView = false
        // Trigger data refresh when switching to calendar view
        NotificationCenter.default.post(name: Notification.Name("RefreshCalendarData"), object: nil)
    }
    
    func switchToTasks() {
        currentView = .tasks
        showTasksView = true
        // Reset showingAllTasks to false so tasks view syncs with current calendar interval
        showingAllTasks = false
    }
    
    func switchToLists() {
        currentView = .lists
        showTasksView = false
    }
    
    func switchToGoals() {
        if AppPreferences.shared.hideGoals {
            switchToCalendar()
            return
        }

        currentView = .goals
        showTasksView = false

        if currentInterval == .day {
            currentInterval = .week
        }
    }
    
    func switchToJournal() {
        currentView = .journal
        showTasksView = false
    }
    
    func switchToJournalDayViews() {
        currentView = .journalDayViews
        showTasksView = false
        currentInterval = .day // Journal day views are always day view
    }
    
    func switchToWeeklyView() {
        currentView = .weeklyView
        showTasksView = false
        currentInterval = .week // WeeklyView is always week view
    }
    
    func switchToYearlyCalendar() {
        currentView = .yearlyCalendar
        showTasksView = false
    }
    
    func switchToTimebox() {
        currentView = .timebox
        showTasksView = false
        currentInterval = .week
        currentDate = Date()
        viewRefreshCounter += 1
    }

    func switchToBookView() {
        if AppPreferences.shared.hideBookView {
            switchToCalendar()
            return
        }
        currentView = .bookView
        showTasksView = false
    }

    func showSettings() {
        showingSettings = true
    }


    
    // Update the current interval and date from calendar view
    func updateInterval(_ interval: TimelineInterval, date: Date = Date()) {
        currentInterval = interval
        currentDate = date
    }
}

// MARK: - Color Extensions
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}

// MARK: - Built-in Log Type
enum BuiltInLogType: String, CaseIterable, Codable, Identifiable {
    case food, sleep, water, weight, workout

    var id: String { rawValue }
}

/// A single entry in the user-reorderable list of log sections. The custom
/// log section is a first-class entry alongside the built-in log types so
/// users can drag it anywhere in the list.
enum LogDisplayEntry: Hashable, Identifiable {
    case builtIn(BuiltInLogType)
    case custom

    var id: String { stringValue }

    var stringValue: String {
        switch self {
        case .builtIn(let t): return "builtin.\(t.rawValue)"
        case .custom:         return "custom"
        }
    }

    init?(stringValue: String) {
        if stringValue == "custom" {
            self = .custom
            return
        }
        if stringValue.hasPrefix("builtin."),
           let t = BuiltInLogType(rawValue: String(stringValue.dropFirst("builtin.".count))) {
            self = .builtIn(t)
            return
        }
        return nil
    }

    static let defaultOrder: [LogDisplayEntry] = BuiltInLogType.allCases.map { .builtIn($0) } + [.custom]
}

// MARK: - App Preferences
class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    
    static var isRunningOniPhone: Bool {
#if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
#else
        return false
#endif
    }
    
    @Published var isDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
        }
    }
    
    
    @Published var personalColor: Color {
        didSet {
            UserDefaults.standard.set(personalColor.toHex(), forKey: "personalColor")
        }
    }
    
    @Published var professionalColor: Color {
        didSet {
            UserDefaults.standard.set(professionalColor.toHex(), forKey: "professionalColor")
        }
    }

    // Custom account names (editable by user)
    @Published var personalAccountName: String {
        didSet {
            let trimmed = String(personalAccountName.prefix(30))
            if trimmed != personalAccountName {
                personalAccountName = trimmed
            }
            UserDefaults.standard.set(personalAccountName, forKey: "personalAccountName")
        }
    }

    @Published var professionalAccountName: String {
        didSet {
            let trimmed = String(professionalAccountName.prefix(30))
            if trimmed != professionalAccountName {
                professionalAccountName = trimmed
            }
            UserDefaults.standard.set(professionalAccountName, forKey: "professionalAccountName")
        }
    }

    // Helper function to get account name by kind
    func accountName(for kind: GoogleAuthManager.AccountKind) -> String {
        switch kind {
        case .personal:
            return personalAccountName
        case .professional:
            return professionalAccountName
        }
    }

    // Hide recurring events setting
    @Published var hideRecurringEventsInMonth: Bool {
        didSet {
            UserDefaults.standard.set(hideRecurringEventsInMonth, forKey: "hideRecurringEventsInMonth")
        }
    }
    
    // useDayViewDefault removed; handled by dayViewLayout radio

    
    // Day view layout preference
    @Published var dayViewLayout: DayViewLayoutOption {
        didSet {
            UserDefaults.standard.set(dayViewLayout.rawValue, forKey: "dayViewLayout")
        }
    }
    
    // Available day view layout options based on screen width
    var availableDayViewLayouts: [DayViewLayoutOption] {
        if AppPreferences.isRunningOniPhone {
            return [.mobile]
        }
        return DayViewLayoutOption.allCases
    }
    
    // Show events as list vs timeline in Day view
    @Published var showEventsAsListInDay: Bool {
        didSet {
            UserDefaults.standard.set(showEventsAsListInDay, forKey: "showEventsAsListInDay")
        }
    }
    
    // Show custom logs (collection 0 — the legacy single custom log)
    @Published var showCustomLogs: Bool {
        didSet {
            UserDefaults.standard.set(showCustomLogs, forKey: "showCustomLogs")
        }
    }

    // Show custom logs (collection 1 — second checklist set)
    @Published var showCustomLogs2: Bool {
        didSet {
            UserDefaults.standard.set(showCustomLogs2, forKey: "showCustomLogs2")
        }
    }

    /// Convenience: returns the visibility flag for a specific collection
    /// index. Returns `false` for any out-of-range index so callers don't
    /// have to special-case beyond the two collections we ship today.
    func showCustomLogs(for collection: Int) -> Bool {
        switch collection {
        case 0: return showCustomLogs
        case 1: return showCustomLogs2
        default: return false
        }
    }

    func updateShowCustomLogs(_ value: Bool, for collection: Int) {
        switch collection {
        case 0: showCustomLogs = value
        case 1: showCustomLogs2 = value
        default: break
        }
    }

    /// True if any custom log collection is currently shown — used by
    /// `showAnyLogs` and any other "are custom logs visible at all" checks.
    var anyCustomLogsShown: Bool {
        showCustomLogs || showCustomLogs2
    }

    // Custom log section name (synced via iCloud KVS).
    // This is the name for collection 0 — the legacy single custom log.
    @Published var customLogSectionName: String {
        didSet {
            let trimmed = String(customLogSectionName.prefix(30))
            if trimmed != customLogSectionName {
                customLogSectionName = trimmed
            }
            NSUbiquitousKeyValueStore.default.set(customLogSectionName, forKey: "customLogSectionName")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    // Custom log section name for collection 1 (the second checklist
    // collection added when multi-log support shipped). Defaults to
    // "Custom Logs 2" until the user renames it.
    @Published var customLogSectionName2: String {
        didSet {
            let trimmed = String(customLogSectionName2.prefix(30))
            if trimmed != customLogSectionName2 {
                customLogSectionName2 = trimmed
            }
            NSUbiquitousKeyValueStore.default.set(customLogSectionName2, forKey: "customLogSectionName2")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// Convenience: returns the section name for a given collection index
    /// (0 or 1). Falls back to a sensible default if a name is empty.
    func customLogSectionName(for collection: Int) -> String {
        switch collection {
        case 0:
            return customLogSectionName.isEmpty ? "Custom Logs" : customLogSectionName
        case 1:
            return customLogSectionName2.isEmpty ? "Custom Logs 2" : customLogSectionName2
        default:
            return "Custom Logs"
        }
    }

    func updateCustomLogSectionName(_ value: String, for collection: Int) {
        switch collection {
        case 0: customLogSectionName = value
        case 1: customLogSectionName2 = value
        default: break
        }
    }

    // Hide completed tasks
    @Published var hideCompletedTasks: Bool {
        didSet {
            UserDefaults.standard.set(hideCompletedTasks, forKey: "hideCompletedTasks")
        }
    }
    
    // Hide goals
    @Published var hideGoals: Bool {
        didSet {
            UserDefaults.standard.set(hideGoals, forKey: "hideGoals")
        }
    }

    // Goal view layout: false = category cards (default), true = individual goal cards
    @Published var useGoalCardView: Bool {
        didSet {
            UserDefaults.standard.set(useGoalCardView, forKey: "useGoalCardView")
        }
    }

    // Hide book view
    @Published var hideBookView: Bool {
        didSet {
            UserDefaults.standard.set(hideBookView, forKey: "hideBookView")
        }
    }
    
    // Use alternative row-based weekly view layout
    @Published var useRowBasedWeeklyView: Bool {
        didSet {
            UserDefaults.standard.set(useRowBasedWeeklyView, forKey: "useRowBasedWeeklyView")
        }
    }
    
    // Tasks view layout preference
    @Published var tasksLayoutHorizontal: Bool {
        didSet {
            UserDefaults.standard.set(tasksLayoutHorizontal, forKey: "tasksLayoutHorizontal")
        }
    }
    
    // Developer logging preference
    @Published var verboseLoggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(verboseLoggingEnabled, forKey: DevLogger.verboseLoggingDefaultsKey)
        }
    }
    
    // Logs visibility preferences
    @Published var showWeightLogs: Bool {
        didSet {
            UserDefaults.standard.set(showWeightLogs, forKey: "showWeightLogs")
        }
    }
    
    @Published var showWorkoutLogs: Bool {
        didSet {
            UserDefaults.standard.set(showWorkoutLogs, forKey: "showWorkoutLogs")
        }
    }
    
    @Published var showFoodLogs: Bool {
        didSet {
            UserDefaults.standard.set(showFoodLogs, forKey: "showFoodLogs")
        }
    }

    @Published var showWaterLogs: Bool {
        didSet {
            UserDefaults.standard.set(showWaterLogs, forKey: "showWaterLogs")
        }
    }

    @Published var showSleepLogs: Bool {
        didSet {
            UserDefaults.standard.set(showSleepLogs, forKey: "showSleepLogs")
        }
    }

    var showAnyLogs: Bool {
        showWeightLogs || showWorkoutLogs || showFoodLogs || showWaterLogs || showSleepLogs || showCustomLogs || showCustomLogs2
    }

    @Published var logDisplayOrder: [LogDisplayEntry] {
        didSet {
            let stringValues = logDisplayOrder.map { $0.stringValue }
            UserDefaults.standard.set(stringValues, forKey: "logDisplayOrder")
        }
    }

    func moveLog(from source: IndexSet, to destination: Int) {
        logDisplayOrder.move(fromOffsets: source, toOffset: destination)
    }

    // Selected workout types (which types appear in the picker when adding/editing)
    @Published var selectedWorkoutTypes: Set<WorkoutType> {
        didSet {
            let rawValues = Array(selectedWorkoutTypes.map { $0.rawValue })
            UserDefaults.standard.set(rawValues, forKey: "selectedWorkoutTypes")
            NSUbiquitousKeyValueStore.default.set(rawValues, forKey: "selectedWorkoutTypes")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    var sortedSelectedWorkoutTypes: [WorkoutType] {
        WorkoutType.allCases.filter { selectedWorkoutTypes.contains($0) }
    }

    // Show rolling 7-day workout streak in weekly view
    @Published var showWorkoutStreak: Bool {
        didSet {
            UserDefaults.standard.set(showWorkoutStreak, forKey: "showWorkoutStreak")
            NSUbiquitousKeyValueStore.default.set(showWorkoutStreak, forKey: "showWorkoutStreak")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    // MARK: - Apple Health Kit Preferences
    //
    // Each `showHK*` flag gates a single chip in the Health Bar. Toggling one
    // on triggers HealthKitManager's lazy auth prompt the next time the bar
    // tries to fetch the corresponding metric.

    @Published var showActivityRings: Bool {
        didSet {
            UserDefaults.standard.set(showActivityRings, forKey: "showActivityRings")
        }
    }

    @Published var showHKSteps: Bool {
        didSet { UserDefaults.standard.set(showHKSteps, forKey: "showHKSteps") }
    }

    @Published var showHKActiveEnergy: Bool {
        didSet { UserDefaults.standard.set(showHKActiveEnergy, forKey: "showHKActiveEnergy") }
    }

    @Published var showHKRestingEnergy: Bool {
        didSet { UserDefaults.standard.set(showHKRestingEnergy, forKey: "showHKRestingEnergy") }
    }

    /// Source of the Health Bar's *weight* chip. Picking `.appleHealth` reads
    /// from HealthKit's body-mass samples; `.app` reads from the in-app
    /// `WeightLog` Core Data store the user has been writing manually.
    enum WeightSource: String, CaseIterable, Identifiable {
        case app
        case appleHealth
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .app: return "App"
            case .appleHealth: return "Apple Health"
            }
        }
    }
    @Published var weightSource: WeightSource {
        didSet { UserDefaults.standard.set(weightSource.rawValue, forKey: "weightSource") }
    }

    /// Source of the Health Bar's *workouts* chips. Same idea as
    /// `WeightSource`: app-tracked `WorkoutLog` entries vs. HealthKit
    /// `HKWorkout` samples (Apple Watch, third-party trackers, etc).
    enum WorkoutSource: String, CaseIterable, Identifiable {
        case app
        case appleHealth
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .app: return "App"
            case .appleHealth: return "Apple Health"
            }
        }
    }
    @Published var workoutSource: WorkoutSource {
        didSet { UserDefaults.standard.set(workoutSource.rawValue, forKey: "workoutSource") }
    }

    // MARK: - Health Bar

    /// User-configured order of items rendered in the Health Bar component.
    /// Toggling an item off removes it from `healthBarHiddenItems` instead of
    /// the order array, so its position is preserved across on/off cycles.
    @Published var healthBarOrder: [HealthBarItem] {
        didSet {
            let raw = healthBarOrder.map { $0.rawValue }
            UserDefaults.standard.set(raw, forKey: "healthBarOrder")
            NSUbiquitousKeyValueStore.default.set(raw, forKey: "healthBarOrder")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// Set of `HealthBarItem.rawValue`s the user has turned off in Settings.
    /// Stored as an array for UserDefaults/KVS Codable compatibility.
    @Published var healthBarHiddenItems: Set<String> {
        didSet {
            let raw = Array(healthBarHiddenItems)
            UserDefaults.standard.set(raw, forKey: "healthBarHiddenItems")
            NSUbiquitousKeyValueStore.default.set(raw, forKey: "healthBarHiddenItems")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    func isHealthBarItemVisible(_ item: HealthBarItem) -> Bool {
        !healthBarHiddenItems.contains(item.rawValue)
    }

    func setHealthBarItem(_ item: HealthBarItem, visible: Bool) {
        if visible {
            healthBarHiddenItems.remove(item.rawValue)
        } else {
            healthBarHiddenItems.insert(item.rawValue)
        }
    }

    func moveHealthBarItem(from source: IndexSet, to destination: Int) {
        healthBarOrder.move(fromOffsets: source, toOffset: destination)
    }

    // Per-workout-type icon colors (rawValue → hex string)
    @Published var workoutTypeColors: [String: String] {
        didSet {
            UserDefaults.standard.set(workoutTypeColors, forKey: "workoutTypeColors")
            NSUbiquitousKeyValueStore.default.set(workoutTypeColors, forKey: "workoutTypeColors")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    func colorForWorkoutType(_ type: WorkoutType) -> Color {
        if let hex = workoutTypeColors[type.rawValue], let color = Color(hex: hex) {
            return color
        }
        return .gray
    }

    func setColorForWorkoutType(_ type: WorkoutType, color: Color) {
        workoutTypeColors[type.rawValue] = color.toHex()
    }

    // Day View Divider Positions
    @Published var dayViewCompactTasksHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewCompactTasksHeight, forKey: "dayViewCompactTasksHeight")
        }
    }
    
    @Published var dayViewCompactLeftColumnWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewCompactLeftColumnWidth, forKey: "dayViewCompactLeftColumnWidth")
        }
    }
    
    @Published var dayViewCompactLeftTopHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewCompactLeftTopHeight, forKey: "dayViewCompactLeftTopHeight")
        }
    }
    
    @Published var dayViewExpandedTopRowHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewExpandedTopRowHeight, forKey: "dayViewExpandedTopRowHeight")
        }
    }
    
    @Published var dayViewExpandedLeftTimelineWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewExpandedLeftTimelineWidth, forKey: "dayViewExpandedLeftTimelineWidth")
        }
    }
    
    @Published var dayViewExpandedLogsHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewExpandedLogsHeight, forKey: "dayViewExpandedLogsHeight")
        }
    }

    // DayViewStandard Divider Positions
    @Published var dayViewStandardEventTaskDividerPosition: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewStandardEventTaskDividerPosition, forKey: "dayViewStandardEventTaskDividerPosition")
        }
    }

    @Published var dayViewStandardColumnDividerPosition: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewStandardColumnDividerPosition, forKey: "dayViewStandardColumnDividerPosition")
        }
    }

    @Published var dayViewStandardLogsSectionCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(dayViewStandardLogsSectionCollapsed, forKey: "dayViewStandardLogsSectionCollapsed")
        }
    }

    // DayViewClassic2 Divider Positions
    @Published var dayViewClassic2EventsHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewClassic2EventsHeight, forKey: "dayViewClassic2EventsHeight")
        }
    }
    
    @Published var dayViewClassic2LogsHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewClassic2LogsHeight, forKey: "dayViewClassic2LogsHeight")
        }
    }
    
    // DayViewClassic3 Divider Positions
    @Published var dayViewClassic3TasksHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewClassic3TasksHeight, forKey: "dayViewClassic3TasksHeight")
        }
    }
    
    // Calendar View Day Divider Positions
    @Published var calendarDayLeftSectionWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarDayLeftSectionWidth, forKey: "calendarDayLeftSectionWidth")
        }
    }
    
    @Published var calendarDayRightColumn2Width: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarDayRightColumn2Width, forKey: "calendarDayRightColumn2Width")
        }
    }
    
    @Published var calendarDayLeftTimelineHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarDayLeftTimelineHeight, forKey: "calendarDayLeftTimelineHeight")
        }
    }
    
    @Published var calendarDayRightSectionTopHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarDayRightSectionTopHeight, forKey: "calendarDayRightSectionTopHeight")
        }
    }
    
    // DayViewTimebox Divider Positions
    @Published var dayViewTimeboxLeftSectionWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewTimeboxLeftSectionWidth, forKey: "dayViewTimeboxLeftSectionWidth")
        }
    }
    
    @Published var dayViewTimeboxTasksSectionHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewTimeboxTasksSectionHeight, forKey: "dayViewTimeboxTasksSectionHeight")
        }
    }
    
    @Published var dayViewTimeboxLogsSectionHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(dayViewTimeboxLogsSectionHeight, forKey: "dayViewTimeboxLogsSectionHeight")
        }
    }
    
    @Published var dayViewTimeboxTasksSectionCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(dayViewTimeboxTasksSectionCollapsed, forKey: "dayViewTimeboxTasksSectionCollapsed")
        }
    }
    
    @Published var dayViewTimeboxLogsSectionCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(dayViewTimeboxLogsSectionCollapsed, forKey: "dayViewTimeboxLogsSectionCollapsed")
        }
    }
    
    // CalendarView Additional Divider Positions
    @Published var calendarTopSectionHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarTopSectionHeight, forKey: "calendarTopSectionHeight")
        }
    }
    
    @Published var calendarVerticalTopRowHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarVerticalTopRowHeight, forKey: "calendarVerticalTopRowHeight")
        }
    }
    
    @Published var calendarVerticalTopLeftWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarVerticalTopLeftWidth, forKey: "calendarVerticalTopLeftWidth")
        }
    }
    
    @Published var calendarVerticalBottomLeftWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarVerticalBottomLeftWidth, forKey: "calendarVerticalBottomLeftWidth")
        }
    }
    
    @Published var calendarWeekTasksPersonalWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarWeekTasksPersonalWidth, forKey: "calendarWeekTasksPersonalWidth")
        }
    }
    
    @Published var calendarWeekTopSectionHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarWeekTopSectionHeight, forKey: "calendarWeekTopSectionHeight")
        }
    }
    
    // TasksView Divider Positions
    @Published var tasksViewPersonalWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(tasksViewPersonalWidth, forKey: "tasksViewPersonalWidth")
        }
    }
    
    // WeekTimelineComponent Divider Positions
    @Published var weekTimelineTasksRowHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(weekTimelineTasksRowHeight, forKey: "weekTimelineTasksRowHeight")
        }
    }
    

    

    

    

    
    private init() {
        self.isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        self.hideRecurringEventsInMonth = UserDefaults.standard.bool(forKey: "hideRecurringEventsInMonth")

        // useDayViewDefault removed

        
        // Load day view layout preference (default to Classic layout)
        let layoutRaw = UserDefaults.standard.integer(forKey: "dayViewLayout")
#if os(iOS)
        let screenWidth = UIScreen.main.bounds.width
#else
        let screenWidth: CGFloat = 1024
#endif
        
        if AppPreferences.isRunningOniPhone || screenWidth < 768 {
            self.dayViewLayout = .mobile
        } else if UserDefaults.standard.object(forKey: "dayViewLayout") == nil {
            // If no layout has been explicitly chosen (key doesn't exist), use Classic Day in 1-page
            self.dayViewLayout = .newClassic // Classic Day in 1-page layout
        } else {
            // Otherwise use the saved layout or fallback to Classic Day in 1-page if invalid
            self.dayViewLayout = DayViewLayoutOption(rawValue: layoutRaw) ?? .newClassic
        }
        
        // Load events-as-list preference (default false)
        self.showEventsAsListInDay = UserDefaults.standard.bool(forKey: "showEventsAsListInDay")

        // Load row-based weekly view preference (default false - column layout)
        self.useRowBasedWeeklyView = UserDefaults.standard.bool(forKey: "useRowBasedWeeklyView")

        // Load tasks layout preference (default false - vertical layout)
        var storedTasksLayoutHorizontal = UserDefaults.standard.bool(forKey: "tasksLayoutHorizontal")
        if AppPreferences.isRunningOniPhone && storedTasksLayoutHorizontal {
            storedTasksLayoutHorizontal = false
            UserDefaults.standard.set(false, forKey: "tasksLayoutHorizontal")
        }
        self.tasksLayoutHorizontal = storedTasksLayoutHorizontal

        // Load logs visibility preferences (default all visible)
        self.showWeightLogs = UserDefaults.standard.object(forKey: "showWeightLogs") as? Bool ?? true
        self.showWorkoutLogs = UserDefaults.standard.object(forKey: "showWorkoutLogs") as? Bool ?? true
        self.showFoodLogs = UserDefaults.standard.object(forKey: "showFoodLogs") as? Bool ?? true
        self.showWaterLogs = UserDefaults.standard.object(forKey: "showWaterLogs") as? Bool ?? true
        self.showSleepLogs = UserDefaults.standard.object(forKey: "showSleepLogs") as? Bool ?? true
        self.showCustomLogs = UserDefaults.standard.object(forKey: "showCustomLogs") as? Bool ?? false
        self.showCustomLogs2 = UserDefaults.standard.object(forKey: "showCustomLogs2") as? Bool ?? false
        self.customLogSectionName = NSUbiquitousKeyValueStore.default.string(forKey: "customLogSectionName") ?? "Custom Logs"
        self.customLogSectionName2 = NSUbiquitousKeyValueStore.default.string(forKey: "customLogSectionName2") ?? "Custom Logs 2"

        // Load log display order. Legacy saves stored only `BuiltInLogType`
        // rawValues (e.g. "food", "sleep"); current format also supports the
        // custom entry as "custom" and built-ins as "builtin.<raw>".
        if let saved = UserDefaults.standard.stringArray(forKey: "logDisplayOrder") {
            var decoded: [LogDisplayEntry] = []
            for value in saved {
                if let entry = LogDisplayEntry(stringValue: value) {
                    decoded.append(entry)
                } else if let t = BuiltInLogType(rawValue: value) {
                    decoded.append(.builtIn(t))
                }
            }
            // Make sure every built-in and the custom entry are present, even
            // if the saved list was incomplete or predates new additions.
            for t in BuiltInLogType.allCases where !decoded.contains(.builtIn(t)) {
                decoded.append(.builtIn(t))
            }
            if !decoded.contains(.custom) {
                decoded.append(.custom)
            }
            self.logDisplayOrder = decoded
        } else {
            self.logDisplayOrder = LogDisplayEntry.defaultOrder
        }

        // Pull latest iCloud KVS data before reading workout settings
        NSUbiquitousKeyValueStore.default.synchronize()

        // Load selected workout types (iCloud KVS → UserDefaults → default all)
        let kvsWorkoutTypes = NSUbiquitousKeyValueStore.default.array(forKey: "selectedWorkoutTypes") as? [String]
        let localWorkoutTypes = UserDefaults.standard.stringArray(forKey: "selectedWorkoutTypes")
        if let savedWorkoutTypes = kvsWorkoutTypes ?? localWorkoutTypes {
            let decoded = savedWorkoutTypes.compactMap { WorkoutType(rawValue: $0) }
            self.selectedWorkoutTypes = Set(decoded.isEmpty ? WorkoutType.allCases : decoded)
        } else {
            self.selectedWorkoutTypes = Set(WorkoutType.allCases)
        }

        // Load workout streak preference (iCloud KVS → UserDefaults → default off)
        if NSUbiquitousKeyValueStore.default.object(forKey: "showWorkoutStreak") != nil {
            self.showWorkoutStreak = NSUbiquitousKeyValueStore.default.bool(forKey: "showWorkoutStreak")
        } else {
            self.showWorkoutStreak = UserDefaults.standard.object(forKey: "showWorkoutStreak") as? Bool ?? false
        }

        // Load per-workout-type icon colors (iCloud KVS → UserDefaults → default empty)
        let kvsColors = NSUbiquitousKeyValueStore.default.dictionary(forKey: "workoutTypeColors") as? [String: String]
        let localColors = UserDefaults.standard.dictionary(forKey: "workoutTypeColors") as? [String: String]
        self.workoutTypeColors = kvsColors ?? localColors ?? [:]

        self.showActivityRings = UserDefaults.standard.object(forKey: "showActivityRings") as? Bool ?? false
        self.showHKSteps = UserDefaults.standard.object(forKey: "showHKSteps") as? Bool ?? false
        self.showHKActiveEnergy = UserDefaults.standard.object(forKey: "showHKActiveEnergy") as? Bool ?? false
        self.showHKRestingEnergy = UserDefaults.standard.object(forKey: "showHKRestingEnergy") as? Bool ?? false
        let savedWeightSource = UserDefaults.standard.string(forKey: "weightSource") ?? WeightSource.app.rawValue
        self.weightSource = WeightSource(rawValue: savedWeightSource) ?? .app
        let savedWorkoutSource = UserDefaults.standard.string(forKey: "workoutSource") ?? WorkoutSource.app.rawValue
        self.workoutSource = WorkoutSource(rawValue: savedWorkoutSource) ?? .app

        // Load Health Bar order (iCloud KVS → UserDefaults → default).
        // Any known items missing from the saved list are appended so new
        // items added in future versions show up automatically.
        let kvsHealthBarOrder = NSUbiquitousKeyValueStore.default.array(forKey: "healthBarOrder") as? [String]
        let localHealthBarOrder = UserDefaults.standard.stringArray(forKey: "healthBarOrder")
        if let saved = kvsHealthBarOrder ?? localHealthBarOrder {
            var decoded = saved.compactMap { HealthBarItem(rawValue: $0) }
            for item in HealthBarItem.allCases where !decoded.contains(item) {
                decoded.append(item)
            }
            self.healthBarOrder = decoded
        } else {
            self.healthBarOrder = HealthBarItem.defaultOrder
        }

        // Load Health Bar hidden-items set (iCloud KVS → UserDefaults → empty).
        let kvsHealthBarHidden = NSUbiquitousKeyValueStore.default.array(forKey: "healthBarHiddenItems") as? [String]
        let localHealthBarHidden = UserDefaults.standard.stringArray(forKey: "healthBarHiddenItems")
        self.healthBarHiddenItems = Set(kvsHealthBarHidden ?? localHealthBarHidden ?? [])

        self.hideCompletedTasks = UserDefaults.standard.object(forKey: "hideCompletedTasks") as? Bool ?? false
        self.hideGoals = UserDefaults.standard.object(forKey: "hideGoals") as? Bool ?? true
        self.useGoalCardView = UserDefaults.standard.object(forKey: "useGoalCardView") as? Bool ?? false
        self.hideBookView = UserDefaults.standard.object(forKey: "hideBookView") as? Bool ?? true
        self.verboseLoggingEnabled = UserDefaults.standard.object(forKey: DevLogger.verboseLoggingDefaultsKey) as? Bool ?? false
        
        


        
        // Load colors from UserDefaults or use defaults
        let personalHex = UserDefaults.standard.string(forKey: "personalColor") ?? "#dcd6ff"
        let professionalHex = UserDefaults.standard.string(forKey: "professionalColor") ?? "#38eb50"
        
        self.personalColor = Color(hex: personalHex) ?? Color(hex: "#dcd6ff") ?? .purple
        self.professionalColor = Color(hex: professionalHex) ?? Color(hex: "#38eb50") ?? .green

        // Load custom account names or use defaults
        self.personalAccountName = UserDefaults.standard.string(forKey: "personalAccountName") ?? "Linked Account 1"
        self.professionalAccountName = UserDefaults.standard.string(forKey: "professionalAccountName") ?? "Linked Account 2"

        // Load divider positions from UserDefaults or use defaults
        self.dayViewCompactTasksHeight = UserDefaults.standard.object(forKey: "dayViewCompactTasksHeight") as? CGFloat ?? 300
        self.dayViewCompactLeftColumnWidth = UserDefaults.standard.object(forKey: "dayViewCompactLeftColumnWidth") as? CGFloat ?? 200
        self.dayViewCompactLeftTopHeight = UserDefaults.standard.object(forKey: "dayViewCompactLeftTopHeight") as? CGFloat ?? 260
        self.dayViewExpandedTopRowHeight = UserDefaults.standard.object(forKey: "dayViewExpandedTopRowHeight") as? CGFloat ?? 400
        self.dayViewExpandedLeftTimelineWidth = UserDefaults.standard.object(forKey: "dayViewExpandedLeftTimelineWidth") as? CGFloat ?? 200
        self.dayViewExpandedLogsHeight = UserDefaults.standard.object(forKey: "dayViewExpandedLogsHeight") as? CGFloat ?? 300
        self.dayViewStandardEventTaskDividerPosition = UserDefaults.standard.object(forKey: "dayViewStandardEventTaskDividerPosition") as? CGFloat ?? 300
        self.dayViewStandardColumnDividerPosition = UserDefaults.standard.object(forKey: "dayViewStandardColumnDividerPosition") as? CGFloat ?? 600
        self.dayViewStandardLogsSectionCollapsed = UserDefaults.standard.object(forKey: "dayViewStandardLogsSectionCollapsed") as? Bool ?? true
        self.dayViewClassic2EventsHeight = UserDefaults.standard.object(forKey: "dayViewClassic2EventsHeight") as? CGFloat ?? 250
        self.dayViewClassic2LogsHeight = UserDefaults.standard.object(forKey: "dayViewClassic2LogsHeight") as? CGFloat ?? 200
        self.dayViewClassic3TasksHeight = UserDefaults.standard.object(forKey: "dayViewClassic3TasksHeight") as? CGFloat ?? 300
        self.calendarDayLeftSectionWidth = UserDefaults.standard.object(forKey: "calendarDayLeftSectionWidth") as? CGFloat ?? 200
        self.calendarDayRightColumn2Width = UserDefaults.standard.object(forKey: "calendarDayRightColumn2Width") as? CGFloat ?? 200
        self.calendarDayLeftTimelineHeight = UserDefaults.standard.object(forKey: "calendarDayLeftTimelineHeight") as? CGFloat ?? 500
        self.calendarDayRightSectionTopHeight = UserDefaults.standard.object(forKey: "calendarDayRightSectionTopHeight") as? CGFloat ?? 500
        
        // Load DayViewTimebox divider positions
        self.dayViewTimeboxLeftSectionWidth = UserDefaults.standard.object(forKey: "dayViewTimeboxLeftSectionWidth") as? CGFloat ?? 300
        self.dayViewTimeboxTasksSectionHeight = UserDefaults.standard.object(forKey: "dayViewTimeboxTasksSectionHeight") as? CGFloat ?? 400
        self.dayViewTimeboxLogsSectionHeight = UserDefaults.standard.object(forKey: "dayViewTimeboxLogsSectionHeight") as? CGFloat ?? 300
        self.dayViewTimeboxTasksSectionCollapsed = UserDefaults.standard.object(forKey: "dayViewTimeboxTasksSectionCollapsed") as? Bool ?? false
        self.dayViewTimeboxLogsSectionCollapsed = UserDefaults.standard.object(forKey: "dayViewTimeboxLogsSectionCollapsed") as? Bool ?? false
        
        // Load CalendarView additional divider positions
        self.calendarTopSectionHeight = UserDefaults.standard.object(forKey: "calendarTopSectionHeight") as? CGFloat ?? UIScreen.main.bounds.height * 0.85
        self.calendarVerticalTopRowHeight = UserDefaults.standard.object(forKey: "calendarVerticalTopRowHeight") as? CGFloat ?? UIScreen.main.bounds.height * 0.55
        self.calendarVerticalTopLeftWidth = UserDefaults.standard.object(forKey: "calendarVerticalTopLeftWidth") as? CGFloat ?? UIScreen.main.bounds.width * 0.5
        self.calendarVerticalBottomLeftWidth = UserDefaults.standard.object(forKey: "calendarVerticalBottomLeftWidth") as? CGFloat ?? UIScreen.main.bounds.width * 0.5
        self.calendarWeekTasksPersonalWidth = UserDefaults.standard.object(forKey: "calendarWeekTasksPersonalWidth") as? CGFloat ?? UIScreen.main.bounds.width * 0.3
        self.calendarWeekTopSectionHeight = UserDefaults.standard.object(forKey: "calendarWeekTopSectionHeight") as? CGFloat ?? 400
        
        // Load TasksView divider positions
        self.tasksViewPersonalWidth = UserDefaults.standard.object(forKey: "tasksViewPersonalWidth") as? CGFloat ?? UIScreen.main.bounds.width * 0.5
        
        // Load WeekTimelineComponent divider positions
        self.weekTimelineTasksRowHeight = UserDefaults.standard.object(forKey: "weekTimelineTasksRowHeight") as? CGFloat ?? 120

        // Listen for iCloud KVS changes from other devices
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let kvs = NSUbiquitousKeyValueStore.default

            // Log sync event for diagnostics
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            devLog("☁️ iCloud KVS external change - reason: \(reason ?? -1), keys: \(changedKeys)", level: .info, category: .sync)

            if changedKeys.isEmpty || changedKeys.contains("customLogSectionName") {
                let newName = kvs.string(forKey: "customLogSectionName") ?? "Custom Logs"
                if self.customLogSectionName != newName {
                    self.customLogSectionName = newName
                }
            }

            if changedKeys.isEmpty || changedKeys.contains("customLogSectionName2") {
                let newName = kvs.string(forKey: "customLogSectionName2") ?? "Custom Logs 2"
                if self.customLogSectionName2 != newName {
                    self.customLogSectionName2 = newName
                }
            }

            // Sync selected workout types
            if changedKeys.isEmpty || changedKeys.contains("selectedWorkoutTypes") {
                if let rawTypes = kvs.array(forKey: "selectedWorkoutTypes") as? [String] {
                    let decoded = Set(rawTypes.compactMap { WorkoutType(rawValue: $0) })
                    if !decoded.isEmpty && decoded != self.selectedWorkoutTypes {
                        self.selectedWorkoutTypes = decoded
                        devLog("☁️ Synced selectedWorkoutTypes: \(decoded.count) types", level: .info, category: .sync)
                    }
                }
            }

            // Sync workout streak preference
            if changedKeys.isEmpty || changedKeys.contains("showWorkoutStreak") {
                if kvs.object(forKey: "showWorkoutStreak") != nil {
                    let newStreak = kvs.bool(forKey: "showWorkoutStreak")
                    if self.showWorkoutStreak != newStreak {
                        self.showWorkoutStreak = newStreak
                        devLog("☁️ Synced showWorkoutStreak: \(newStreak)", level: .info, category: .sync)
                    }
                }
            }

            // Sync workout type colors
            if changedKeys.isEmpty || changedKeys.contains("workoutTypeColors") {
                if let newColors = kvs.dictionary(forKey: "workoutTypeColors") as? [String: String] {
                    if self.workoutTypeColors != newColors {
                        self.workoutTypeColors = newColors
                        devLog("☁️ Synced workoutTypeColors: \(newColors.count) colors", level: .info, category: .sync)
                    }
                }
            }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    func updateDarkMode(_ value: Bool) {
        isDarkMode = value
    }
    
    
    func updatePersonalColor(_ color: Color) {
        personalColor = color
    }
    
    func updateProfessionalColor(_ color: Color) {
        professionalColor = color
    }
    
    func updateShowCustomLogs(_ value: Bool) {
        // Legacy single-toggle entry point — sets collection 0 only.
        showCustomLogs = value
    }
    

    func updateHideCompletedTasks(_ value: Bool) {
        hideCompletedTasks = value
    }
    
    func updateHideGoals(_ value: Bool) {
        hideGoals = value
    }

    func updateHideBookView(_ value: Bool) {
        hideBookView = value
    }

    func updateHideRecurringEventsInMonth(_ value: Bool) {
        hideRecurringEventsInMonth = value
    }
    
    func updateDayViewLayout(_ layout: DayViewLayoutOption) {
        if AppPreferences.isRunningOniPhone {
            dayViewLayout = .mobile
        } else {
            dayViewLayout = layout
        }
    }
    
    func updateShowEventsAsListInDay(_ value: Bool) {
        showEventsAsListInDay = value
    }
    
    func updateUseRowBasedWeeklyView(_ value: Bool) {
        useRowBasedWeeklyView = value
    }
    
    func updateTasksLayoutHorizontal(_ value: Bool) {
        if AppPreferences.isRunningOniPhone {
            tasksLayoutHorizontal = false
        } else {
            tasksLayoutHorizontal = value
        }
    }
    
    func updateVerboseLogging(_ value: Bool) {
        verboseLoggingEnabled = value
    }
    
    
    // Day View Divider Position Update Methods
    func updateDayViewCompactTasksHeight(_ value: CGFloat) {
        dayViewCompactTasksHeight = value
    }
    
    func updateDayViewCompactLeftColumnWidth(_ value: CGFloat) {
        dayViewCompactLeftColumnWidth = value
    }
    
    func updateDayViewCompactLeftTopHeight(_ value: CGFloat) {
        dayViewCompactLeftTopHeight = value
    }
    
    func updateDayViewExpandedTopRowHeight(_ value: CGFloat) {
        dayViewExpandedTopRowHeight = value
    }
    
    func updateDayViewExpandedLeftTimelineWidth(_ value: CGFloat) {
        dayViewExpandedLeftTimelineWidth = value
    }
    
    func updateDayViewExpandedLogsHeight(_ value: CGFloat) {
        dayViewExpandedLogsHeight = value
    }

    func updateDayViewStandardEventTaskDividerPosition(_ value: CGFloat) {
        dayViewStandardEventTaskDividerPosition = value
    }

    func updateDayViewStandardColumnDividerPosition(_ value: CGFloat) {
        dayViewStandardColumnDividerPosition = value
    }

    func updateDayViewStandardLogsSectionCollapsed(_ value: Bool) {
        dayViewStandardLogsSectionCollapsed = value
    }

    func updateDayViewClassic2EventsHeight(_ value: CGFloat) {
        dayViewClassic2EventsHeight = value
    }
    
    func updateDayViewClassic2LogsHeight(_ value: CGFloat) {
        dayViewClassic2LogsHeight = value
    }
    
    func updateDayViewClassic3TasksHeight(_ value: CGFloat) {
        dayViewClassic3TasksHeight = value
    }
    
    func updateCalendarDayLeftSectionWidth(_ value: CGFloat) {
        calendarDayLeftSectionWidth = value
    }
    
    func updateCalendarDayRightColumn2Width(_ value: CGFloat) {
        calendarDayRightColumn2Width = value
    }
    
    func updateCalendarDayLeftTimelineHeight(_ value: CGFloat) {
        calendarDayLeftTimelineHeight = value
    }
    
    func updateCalendarDayRightSectionTopHeight(_ value: CGFloat) {
        calendarDayRightSectionTopHeight = value
    }
    
    // DayViewTimebox Divider Position Update Methods
    func updateDayViewTimeboxLeftSectionWidth(_ value: CGFloat) {
        dayViewTimeboxLeftSectionWidth = value
    }
    
    func updateDayViewTimeboxTasksSectionHeight(_ value: CGFloat) {
        dayViewTimeboxTasksSectionHeight = value
    }
    
    func updateDayViewTimeboxLogsSectionHeight(_ value: CGFloat) {
        dayViewTimeboxLogsSectionHeight = value
    }
    
    func updateDayViewTimeboxTasksSectionCollapsed(_ value: Bool) {
        dayViewTimeboxTasksSectionCollapsed = value
    }
    
    func updateDayViewTimeboxLogsSectionCollapsed(_ value: Bool) {
        dayViewTimeboxLogsSectionCollapsed = value
    }
    
    // CalendarView Additional Divider Position Update Methods
    func updateCalendarTopSectionHeight(_ value: CGFloat) {
        calendarTopSectionHeight = value
    }
    
    func updateCalendarVerticalTopRowHeight(_ value: CGFloat) {
        calendarVerticalTopRowHeight = value
    }
    
    func updateCalendarVerticalTopLeftWidth(_ value: CGFloat) {
        calendarVerticalTopLeftWidth = value
    }
    
    func updateCalendarVerticalBottomLeftWidth(_ value: CGFloat) {
        calendarVerticalBottomLeftWidth = value
    }
    
    func updateCalendarWeekTasksPersonalWidth(_ value: CGFloat) {
        calendarWeekTasksPersonalWidth = value
    }
    
    func updateCalendarWeekTopSectionHeight(_ value: CGFloat) {
        calendarWeekTopSectionHeight = value
    }
    
    // TasksView Divider Position Update Methods
    func updateTasksViewPersonalWidth(_ value: CGFloat) {
        tasksViewPersonalWidth = value
    }
    
    // WeekTimelineComponent Divider Position Update Methods
    func updateWeekTimelineTasksRowHeight(_ value: CGFloat) {
        weekTimelineTasksRowHeight = value
    }

    // removed updateUseDayViewDefault
    
    // Removed visibility update methods
    

    

    

}

struct SettingsView: View {
    @ObservedObject private var auth = GoogleAuthManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @Environment(\.dismiss) private var dismiss

    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    // State for show/hide account toggles (placeholder for future implementation)
    @State private var showPersonalAccount = true
    @State private var showProfessionalAccount = true

    // State for color picker modals
    @State private var showingPersonalColorPicker = false
    @State private var showingProfessionalColorPicker = false
    @State private var showingDeleteAllAlert = false
    @State private var showingDeleteSuccessAlert = false
    @State private var showingDeleteGoalsAlert = false
    @State private var pendingUnlink: GoogleAuthManager.AccountKind?
    /// Non-nil when a custom-day-view version is being edited; drives the
    /// configurator sheet. `UUID` identifies the slot in
    /// `CustomDayViewLibrary` being edited (pre-existing or brand-new).
    private struct ConfiguratorTarget: Identifiable { let id: UUID }
    @State private var configuratorTarget: ConfiguratorTarget?
    /// Used on Mac Catalyst to open the configurator in its own native window
    /// instead of the cramped .fullScreenCover sheet.
    @Environment(\.openWindow) private var openWindow
    @State private var pendingDeleteVersionId: UUID?
    /// Bumped after the configurator dismisses or the library changes so the
    /// versions list re-renders with the latest names / active selection.
    @State private var customConfigVersion = 0

    // Check if device forces stacked layout (iPhone portrait)
    private var shouldUseStackedLayout: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    /// Reading `customConfigVersion` creates a SwiftUI dependency so this
    /// recomputes after the configurator saves a new version.
    private var customDayViewLibrary: CustomDayViewLibrary {
        _ = customConfigVersion
        return CustomDayViewLibrary.load()
    }

    private var isCustomDayViewConfigured: Bool {
        !customDayViewLibrary.versions.isEmpty
    }

    /// The custom day view configurator currently only runs on iPad; layouts
    /// saved there sync to Mac via iCloud but Mac doesn't show the edit UI.
    private var isRunningOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp
    }

    // MARK: - Custom day view versions

    /// Sub-rows rendered under the Custom option in Daily View Preferences:
    /// each saved version (up to `CustomDayViewLibrary.maxVersions`) with
    /// radio-button selection of the live version, plus per-row Edit / Delete
    /// actions and an "Add Version" button when capacity remains.
    @ViewBuilder
    private var customDayViewVersionRows: some View {
        let library = customDayViewLibrary
        let canAddMore = library.versions.count < CustomDayViewLibrary.maxVersions

        ForEach(library.versions) { version in
            customDayViewVersionRow(version: version, activeId: library.resolvedActiveId)
        }

        if canAddMore {
            Button {
                addCustomDayViewVersion()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundColor(.accentColor)
                    Text(library.versions.isEmpty ? "Add Version" : "Add Another Version")
                        .font(.footnote)
                        .foregroundColor(.accentColor)
                    Spacer()
                    Text("\(library.versions.count) / \(CustomDayViewLibrary.maxVersions)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 28)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            Text("You've reached the limit of \(CustomDayViewLibrary.maxVersions) versions. Delete one to add another.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 28)
        }
    }

    @ViewBuilder
    private func customDayViewVersionRow(version: NamedCustomDayViewConfig, activeId: UUID?) -> some View {
        let isActive = version.id == activeId
        HStack(spacing: 10) {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .foregroundColor(isActive ? .accentColor : .secondary)
                .font(.body)
                .contentShape(Rectangle())
                .onTapGesture {
                    setActiveCustomDayViewVersion(id: version.id)
                }

            // Inline editable name — reads from the library, writes back on
            // every change so renames persist without opening the configurator.
            TextField("Version name", text: Binding(
                get: {
                    customDayViewLibrary.versions.first(where: { $0.id == version.id })?.name ?? version.name
                },
                set: { newName in
                    renameCustomDayViewVersion(id: version.id, to: newName)
                }
            ))
            .textFieldStyle(.plain)
            .font(.footnote)
            .fontWeight(isActive ? .semibold : .regular)
            .lineLimit(1)
            .submitLabel(.done)

            Spacer(minLength: 4)

            Button {
                #if targetEnvironment(macCatalyst)
                openWindow(id: "configurator", value: version.id)
                #else
                configuratorTarget = ConfiguratorTarget(id: version.id)
                #endif
            } label: {
                Text("Edit Layout")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                pendingDeleteVersionId = version.id
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 28)
    }

    /// Creates a blank new version with a default name and immediately opens
    /// the configurator to edit it. The version isn't persisted until the
    /// user taps Save in the configurator.
    private func addCustomDayViewVersion() {
        let library = customDayViewLibrary
        guard library.versions.count < CustomDayViewLibrary.maxVersions else { return }
        let newId = UUID()
        #if targetEnvironment(macCatalyst)
        openWindow(id: "configurator", value: newId)
        #else
        configuratorTarget = ConfiguratorTarget(id: newId)
        #endif
    }

    private func setActiveCustomDayViewVersion(id: UUID) {
        let library = CustomDayViewLibrary.load()
        guard library.versions.contains(where: { $0.id == id }) else { return }
        // Per-device selection. Does NOT touch the synced library, so
        // selecting a different version on this device leaves other devices'
        // selections untouched.
        guard CustomDayViewLibrary.localActiveId != id else { return }
        CustomDayViewLibrary.localActiveId = id
    }

    /// Persists an inline name change for a specific version. Called on every
    /// keystroke from the TextField in the settings row.
    private func renameCustomDayViewVersion(id: UUID, to newName: String) {
        var library = CustomDayViewLibrary.load()
        guard let idx = library.versions.firstIndex(where: { $0.id == id }) else { return }
        guard library.versions[idx].name != newName else { return }
        library.versions[idx].name = newName
        CustomDayViewLibrary.save(library)
    }

    private func deleteCustomDayViewVersion(id: UUID) {
        var library = CustomDayViewLibrary.load()
        library.versions.removeAll { $0.id == id }
        if library.activeId == id {
            // Fall back to the first remaining version (if any) so the Custom
            // day view keeps rendering something sensible on devices that
            // had no per-device override.
            library.activeId = library.versions.first?.id
        }
        if CustomDayViewLibrary.localActiveId == id {
            // This device pointed at the deleted version; clear so it falls
            // back to the synced default (or the first remaining version).
            CustomDayViewLibrary.localActiveId = nil
        }
        CustomDayViewLibrary.save(library)
    }



    var body: some View {
        NavigationStack {
            Form {
                Section("Linked Accounts") {
                    accountRow(
                        kind: appPrefs.personalAccountName,
                        kindEnum: .personal,
                        isVisible: $showPersonalAccount,
                        accountColor: $appPrefs.personalColor,
                        showingColorPicker: $showingPersonalColorPicker
                    )
                    accountRow(
                        kind: appPrefs.professionalAccountName,
                        kindEnum: .professional,
                        isVisible: $showProfessionalAccount,
                        accountColor: $appPrefs.professionalColor,
                        showingColorPicker: $showingProfessionalColorPicker
                    )
                }
                
                // Task Management section removed (Hide Completed Tasks now controlled via eye icon)

                if !AppPreferences.isRunningOniPhone {
                    Section("Events View Preferences") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: !appPrefs.showEventsAsListInDay ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(!appPrefs.showEventsAsListInDay ? .accentColor : .secondary)
                                        .font(.title2)
                                    
                                    Text("Events in a 24-hour timeline")
                                        .font(.body)
                                        .fontWeight(!appPrefs.showEventsAsListInDay ? .semibold : .regular)
                                }
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appPrefs.updateShowEventsAsListInDay(false)
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: appPrefs.showEventsAsListInDay ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(appPrefs.showEventsAsListInDay ? .accentColor : .secondary)
                                        .font(.title2)
                                    
                                    Text("Events in a list")
                                        .font(.body)
                                        .fontWeight(appPrefs.showEventsAsListInDay ? .semibold : .regular)
                                }
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appPrefs.updateShowEventsAsListInDay(true)
                        }
                    }
                }

                Section("Daily View Preferences") {
                    // Day View Layout Options with Radio Buttons
                    ForEach(appPrefs.availableDayViewLayouts) { option in
                        Group {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: appPrefs.dayViewLayout == option ? "largecircle.fill.circle" : "circle")
                                            .foregroundColor(appPrefs.dayViewLayout == option ? .accentColor : .secondary)
                                            .font(.title2)

                                        Text(option.displayName)
                                            .font(.body)
                                            .fontWeight(appPrefs.dayViewLayout == option ? .semibold : .regular)

                                        if option.isBeta {
                                            Text("Beta")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule().fill(Color.orange)
                                                )
                                        }

                                        if option == .custom, isCustomDayViewConfigured {
                                            Text("Configured")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule().fill(Color.green)
                                                )
                                        }
                                    }

                                    Text(option.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 28)
                                }

                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appPrefs.updateDayViewLayout(option)
                            }

                            // Render the saved-versions manager as sub-rows
                            // directly under the Custom option, so users can
                            // add / rename / pick active versions without
                            // leaving the Daily View Preferences section.
                            if option == .custom {
                                customDayViewVersionRows
                            }
                        }
                    }
                }

                // Weekly View Preference
                Section("Weekly View Preferences") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: !appPrefs.useRowBasedWeeklyView ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(!appPrefs.useRowBasedWeeklyView ? .accentColor : .secondary)
                                    .font(.title2)
                                
                                Text("Vertical Layout (week in 7 columns)")
                                    .font(.body)
                                    .fontWeight(!appPrefs.useRowBasedWeeklyView ? .semibold : .regular)
                            }
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appPrefs.updateUseRowBasedWeeklyView(false)
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: appPrefs.useRowBasedWeeklyView ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(appPrefs.useRowBasedWeeklyView ? .accentColor : .secondary)
                                    .font(.title2)
                                
                                Text("Horizontal Layout (week in 7 rows)")
                                    .font(.body)
                                    .fontWeight(appPrefs.useRowBasedWeeklyView ? .semibold : .regular)
                            }
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appPrefs.updateUseRowBasedWeeklyView(true)
                    }
                }

                // Tasks View Preference
                Section("Tasks View Preferences") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: !appPrefs.tasksLayoutHorizontal ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(!appPrefs.tasksLayoutHorizontal ? .accentColor : .secondary)
                                    .font(.title2)
                                
                                Text("Vertical stacks")
                                    .font(.body)
                                    .fontWeight(!appPrefs.tasksLayoutHorizontal ? .semibold : .regular)
                            }
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appPrefs.updateTasksLayoutHorizontal(false)
                    }
                    
                    if !AppPreferences.isRunningOniPhone {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: appPrefs.tasksLayoutHorizontal ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(appPrefs.tasksLayoutHorizontal ? .accentColor : .secondary)
                                        .font(.title2)
                                    
                                    Text("Horizontal stacks")
                                        .font(.body)
                                        .fontWeight(appPrefs.tasksLayoutHorizontal ? .semibold : .regular)
                                }
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appPrefs.updateTasksLayoutHorizontal(true)
                        }
                    }
                }

                Section("Log Preferences") {
                    ForEach(appPrefs.logDisplayOrder) { entry in
                        switch entry {
                        case .builtIn(let logType):
                            logToggleRow(for: logType)
                        case .custom:
                            customLogToggleRow
                        }
                    }
                    .onMove { source, destination in
                        appPrefs.moveLog(from: source, to: destination)
                    }
                }

                Section("Health Bar Preferences") {
                    Text("Contents of the Health Bar component in the Custom Day View, in the order they appear. Drag to reorder and toggle to show or hide.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(appPrefs.healthBarOrder) { item in
                        healthBarItemRow(item)
                    }
                    .onMove { source, destination in
                        appPrefs.moveHealthBarItem(from: source, to: destination)
                    }
                }

                Section("Apple Health Kit Preferences") {
                    appleHealthKitSection()
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { !appPrefs.hideGoals },
                        set: { appPrefs.updateHideGoals(!$0) }
                    )) {
                        HStack {
                            Image(systemName: "target")
                                .foregroundColor(appPrefs.hideGoals ? .secondary : .accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Goals")
                                    .font(.body)
                                Text("Enable goal management features")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if !appPrefs.hideGoals {
                        Toggle(isOn: $appPrefs.useGoalCardView) {
                            HStack {
                                Image(systemName: "square.grid.2x2")
                                    .foregroundColor(appPrefs.useGoalCardView ? .accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Goal Card View")
                                        .font(.body)
                                    Text("Show goals as individual cards instead of grouped by category")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        GoalCategoriesInlineView()
                            .padding(.leading, 20)
                            .padding(.top, 8)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text("Goal Preferences")
                        Text("Beta")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                // Book View section - temporarily hidden
//                Section {
//                    Toggle(isOn: Binding(
//                        get: { !appPrefs.hideBookView },
//                        set: { appPrefs.updateHideBookView(!$0) }
//                    )) {
//                        HStack {
//                            Image(systemName: "book.pages")
//                                .foregroundColor(appPrefs.hideBookView ? .secondary : .accentColor)
//                            VStack(alignment: .leading, spacing: 2) {
//                                Text("Enable Book View")
//                                    .font(.body)
//                                Text("Show Book View option in navigation menu")
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                            }
//                        }
//                    }
//                } header: {
//                    HStack(spacing: 8) {
//                        Text("Book View")
//                        Text("Beta")
//                            .font(.caption2)
//                            .fontWeight(.semibold)
//                            .foregroundColor(.white)
//                            .padding(.horizontal, 6)
//                            .padding(.vertical, 2)
//                            .background(Color.orange)
//                            .clipShape(RoundedRectangle(cornerRadius: 4))
//                    }
//                } footer: {
//                    Text("Book View lets you swipe through your planner like a book. This feature is still in beta.")
//                }

                Section("App Preferences") {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.secondary)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dark Mode")
                                .font(.body)
                            Text("Use dark appearance")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { appPrefs.isDarkMode },
                            set: { appPrefs.updateDarkMode($0) }
                        ))
                    }
                    
                }
                
                
                // Components Visibility section removed: Logs and Journal are always visible
                
                
                

                Section("Danger Zone") {
                    Button(role: .destructive) {
                        showingDeleteGoalsAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "target")
                                .foregroundColor(.red)
                            Text("Delete All Goals Data")
                        }
                    }
                    .alert("Delete All Goals?", isPresented: $showingDeleteGoalsAlert) {
                        Button("Cancel", role: .cancel) {}
                        Button("Delete All Goals", role: .destructive) {
                            GoalsManager.shared.deleteAllData()
                        }
                    } message: {
                        Text("This will permanently delete all goals and goal categories. This action cannot be undone.")
                    }

                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Delete All Data")
                        }
                    }
                    .alert("Delete All Data?", isPresented: $showingDeleteAllAlert) {
                        Button("Cancel", role: .cancel) {}
                        Button("Delete", role: .destructive) {
                            handleDeleteAllData()
                        }
                    } message: {
                        Text("This action will unlink all your linked Google accounts but will not delete the events or tasks data from your Google accounts. \n\nLogs data, however, will be deleted from your iCloud and cannot be undone.")
                    }
                    .alert("Data Deleted Successfully", isPresented: $showingDeleteSuccessAlert) {
                        Button("OK") {}
                    } message: {
                        Text("All app data has been deleted successfully. The current view has been refreshed to reflect the changes.")
                    }
                }
                

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Toggle the source binding directly. On Mac Catalyst,
                        // `@Environment(\.dismiss)` becomes unreliable once the
                        // sheet's content has mutated state — dismiss() silently
                        // no-ops, leaving the user unable to close Settings until
                        // backgrounding the app. Setting `showingSettings = false`
                        // sidesteps that path. Also calling `dismiss()` as a
                        // belt-and-suspenders for non-Catalyst contexts.
                        navigationManager.showingSettings = false
                        dismiss()
                    }
                }
            }
            .alert(
                "Unlink Account?",
                isPresented: Binding(
                    get: { pendingUnlink != nil },
                    set: { if !$0 { pendingUnlink = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { pendingUnlink = nil }
                Button("Unlink", role: .destructive) {
                    if let kind = pendingUnlink {
                        handleTap(kind)
                        pendingUnlink = nil
                    }
                }
            } message: {
                Text("You will stop syncing data for this account. You can re-link anytime in Settings.")
            }
            #if !targetEnvironment(macCatalyst)
            .fullScreenCover(item: $configuratorTarget, onDismiss: {
                customConfigVersion &+= 1
            }) { target in
                DayViewCustomConfigurator(versionId: target.id)
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: CustomDayViewLibrary.didChangeNotification)) { _ in
                customConfigVersion &+= 1
            }
            .confirmationDialog(
                "Delete this custom day view?",
                isPresented: Binding(
                    get: { pendingDeleteVersionId != nil },
                    set: { if !$0 { pendingDeleteVersionId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDeleteVersionId {
                        deleteCustomDayViewVersion(id: id)
                    }
                    pendingDeleteVersionId = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteVersionId = nil
                }
            } message: {
                Text("The layout for this version will be removed. This cannot be undone.")
            }
        }
    }
    
    @ViewBuilder
    private func accountRow(
        kind: String,
        kindEnum: GoogleAuthManager.AccountKind,
        isVisible: Binding<Bool>,
        accountColor: Binding<Color>,
        showingColorPicker: Binding<Bool>
    ) -> some View {
        let isLinked = auth.linkedStates[kindEnum] ?? false
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                // Account icon
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)

                // Color picker circle
                Button {
                    showingColorPicker.wrappedValue = true
                } label: {
                    Circle()
                        .fill(accountColor.wrappedValue)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .sheet(isPresented: showingColorPicker) {
                    ColorPickerSheet(
                        title: "\(kind) Account Color",
                        selectedColor: accountColor,
                        onColorChange: { color in
                            switch kindEnum {
                            case .personal:
                                appPrefs.updatePersonalColor(color)
                            case .professional:
                                appPrefs.updateProfessionalColor(color)
                            }
                        }
                    )
                }

                // Account info
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Account name", text: kindEnum == .personal ? $appPrefs.personalAccountName : $appPrefs.professionalAccountName)
                        .font(.body)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 200)
                    Text(isLinked ? (auth.getEmail(for: kindEnum).isEmpty ? "Linked" : auth.getEmail(for: kindEnum)) : "Not Linked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Link/Unlink button
                Button(isLinked ? "Unlink" : "Link") {
                    if isLinked {
                        pendingUnlink = kindEnum
                    } else {
                        handleTap(kindEnum)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func handleTap(_ kind: GoogleAuthManager.AccountKind) {
        if auth.isLinked(kind: kind) {
            auth.unlink(kind: kind)
        } else {
            Task {
                do {
                    try await auth.link(kind: kind, presenting: nil)
                } catch GoogleAuthManager.AuthError.missingClientID {
                    // Show user-friendly error message
                } catch GoogleAuthManager.AuthError.noRefreshToken {
                } catch GoogleAuthManager.AuthError.tokenRefreshFailed {
                } catch {
                }
            }
        }
    }
    
    private func handleDeleteAllData() {
        // Unlink all Google accounts
        GoogleAuthManager.shared.clearAllAuthState()
        
        // Clear calendar caches
        DataManager.shared.calendarViewModel.clearAllData()
        
        // Delete all Logs data (Core Data + CloudKit)
        CoreDataManager.shared.deleteAllLogs()
        LogsViewModel.shared.reloadData()
        LogsViewModel.shared.loadLogsForCurrentDate()
        
        // Delete all Custom Logs data (Core Data + CloudKit)
        CustomLogManager.shared.deleteAllData()
        
        // Delete all Goals data (Core Data + CloudKit)
        GoalsManager.shared.deleteAllData()
        
        // Delete all journal data (drawings, photos, background PDFs)
        JournalManager.shared.deleteAllJournalData()
        
        // Force comprehensive UI refresh
        Task {
            await refreshAllViewsAfterDelete()
            
            // Show success confirmation
            DispatchQueue.main.async {
                showingDeleteSuccessAlert = true
            }
        }
    }
    
    @ViewBuilder
    private var customLogToggleRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            // One toggle + inline editor per collection. Each toggle
            // independently controls visibility of its collection in
            // day views; the user can turn one, the other, or both on.
            ForEach(0..<CustomLogManager.maxCollections, id: \.self) { collection in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { appPrefs.showCustomLogs(for: collection) },
                        set: { appPrefs.updateShowCustomLogs($0, for: collection) }
                    )) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundColor(appPrefs.showCustomLogs(for: collection) ? .accentColor : .secondary)
                            TextField(
                                collection == 0 ? "Custom Logs" : "Custom Logs \(collection + 1)",
                                text: Binding(
                                    get: { appPrefs.customLogSectionName(for: collection) },
                                    set: { appPrefs.updateCustomLogSectionName($0, for: collection) }
                                )
                            )
                            .font(.body)
                            .textFieldStyle(.plain)
                        }
                    }

                    if appPrefs.showCustomLogs(for: collection) {
                        CustomLogItemsInlineView(collectionIndex: collection)
                            .padding(.leading, 20)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func healthBarItemRow(_ item: HealthBarItem) -> some View {
        let visible = appPrefs.isHealthBarItemVisible(item)
        Toggle(isOn: Binding(
            get: { visible },
            set: { appPrefs.setHealthBarItem(item, visible: $0) }
        )) {
            HStack {
                Image(systemName: item.systemImage)
                    .foregroundColor(visible ? .accentColor : .secondary)
                    .frame(width: 22)
                Text(item.displayName)
                    .font(.body)
            }
        }
    }

    @ViewBuilder
    private func logToggleRow(for logType: BuiltInLogType) -> some View {
        switch logType {
        case .food:
            Toggle(isOn: Binding(
                get: { appPrefs.showFoodLogs },
                set: { appPrefs.showFoodLogs = $0 }
            )) {
                HStack {
                    Image(systemName: "fork.knife")
                        .foregroundColor(appPrefs.showFoodLogs ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Food Logs")
                            .font(.body)
                        Text("Show food tracking in day views")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        case .sleep:
            Toggle(isOn: Binding(
                get: { appPrefs.showSleepLogs },
                set: { appPrefs.showSleepLogs = $0 }
            )) {
                HStack {
                    Image(systemName: "bed.double.fill")
                        .foregroundColor(appPrefs.showSleepLogs ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep Logs")
                            .font(.body)
                        Text("Track wake up time and bed time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        case .water:
            Toggle(isOn: Binding(
                get: { appPrefs.showWaterLogs },
                set: { appPrefs.showWaterLogs = $0 }
            )) {
                HStack {
                    Image(systemName: "drop.fill")
                        .foregroundColor(appPrefs.showWaterLogs ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Water Logs")
                            .font(.body)
                        Text("Track daily water intake in cups")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        case .weight:
            Toggle(isOn: Binding(
                get: { appPrefs.showWeightLogs },
                set: { appPrefs.showWeightLogs = $0 }
            )) {
                HStack {
                    Image(systemName: "scalemass")
                        .foregroundColor(appPrefs.showWeightLogs ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weight Logs")
                            .font(.body)
                        Text("Show weight tracking in day views")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        case .workout:
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(
                    get: { appPrefs.showWorkoutLogs },
                    set: { appPrefs.showWorkoutLogs = $0 }
                )) {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundColor(appPrefs.showWorkoutLogs ? .accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Workout Logs")
                                .font(.body)
                            Text("Show workout tracking in day views")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if appPrefs.showWorkoutLogs {
                    Divider().padding(.vertical, 8)

                    NavigationLink {
                        WorkoutTypeSelectionView()
                    } label: {
                        HStack {
                            Image(systemName: "figure.run")
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Workout Types")
                                    .font(.body)
                                Text("\(appPrefs.selectedWorkoutTypes.count) of \(WorkoutType.allCases.count) selected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 20)

                    Divider().padding(.vertical, 8)

                    Toggle(isOn: $appPrefs.showWorkoutStreak) {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(appPrefs.showWorkoutStreak ? .orange : .secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Workout Streak")
                                    .font(.body)
                                Text("Show rolling 7-day workout count in weekly view")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 20)
                    // Activity Rings + other Apple Health toggles now live in
                    // their own "Apple Health Kit Preferences" section.
                }
            }
        }
    }

    @ViewBuilder
    private func appleHealthKitSection() -> some View {
        if HealthKitManager.shared.isHealthKitAvailable {
            Toggle(isOn: $appPrefs.showActivityRings) {
                healthKitRowLabel(
                    icon: "circle.circle",
                    iconColor: appPrefs.showActivityRings ? .red : .secondary,
                    title: "Activity Rings",
                    subtitle: "Move, Exercise, and Stand rings"
                )
            }

            Toggle(isOn: $appPrefs.showHKSteps) {
                healthKitRowLabel(
                    icon: "shoeprints.fill",
                    iconColor: appPrefs.showHKSteps ? .green : .secondary,
                    title: "Steps",
                    subtitle: "Daily step count from Apple Health"
                )
            }

            Toggle(isOn: $appPrefs.showHKActiveEnergy) {
                healthKitRowLabel(
                    icon: "figure.arms.open",
                    iconColor: appPrefs.showHKActiveEnergy ? .orange : .secondary,
                    title: "Active Energy",
                    subtitle: "Calories burned moving today"
                )
            }

            Toggle(isOn: $appPrefs.showHKRestingEnergy) {
                healthKitRowLabel(
                    icon: "gauge.medium",
                    iconColor: appPrefs.showHKRestingEnergy ? .indigo : .secondary,
                    title: "Resting Energy",
                    subtitle: "Basal calories burned today"
                )
            }

            Picker(selection: $appPrefs.weightSource) {
                ForEach(AppPreferences.WeightSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            } label: {
                healthKitRowLabel(
                    icon: "scalemass.fill",
                    iconColor: .teal,
                    title: "Weight Source",
                    subtitle: "Where the Weight chip's value comes from"
                )
            }

            Picker(selection: $appPrefs.workoutSource) {
                ForEach(AppPreferences.WorkoutSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            } label: {
                healthKitRowLabel(
                    icon: "figure.run",
                    iconColor: .pink,
                    title: "Workout Source",
                    subtitle: "Where the Workout chips come from"
                )
            }
        } else {
            healthKitRowLabel(
                icon: "heart.slash",
                iconColor: .secondary,
                title: "Apple Health unavailable",
                subtitle: "This device does not support Apple Health."
            )
        }
    }

    @ViewBuilder
    private func healthKitRowLabel(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
        }
    }


    private func refreshAllViewsAfterDelete() async {
        let currentDate = NavigationManager.shared.currentDate
        
        // Reload calendar events based on current interval
        switch NavigationManager.shared.currentInterval {
        case .day:
            await DataManager.shared.calendarViewModel.loadCalendarData(for: currentDate)
        case .week:
            await DataManager.shared.calendarViewModel.loadCalendarDataForWeek(containing: currentDate)
        case .month:
            await DataManager.shared.calendarViewModel.loadCalendarDataForMonth(containing: currentDate)
        case .year:
            await DataManager.shared.calendarViewModel.loadCalendarDataForMonth(containing: currentDate)
        }
        
        // Reload tasks with forced cache clear
        await DataManager.shared.tasksViewModel.loadTasks(forceClear: true)

        // Reload goals data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        DataManager.shared.goalsManager.refreshData()

        // Reload custom log data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        DataManager.shared.customLogManager.refreshData()

        // Reload logs data
        LogsViewModel.shared.reloadData()
        LogsViewModel.shared.loadLogsForCurrentDate()
        
        // Post comprehensive refresh notifications
        NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("RefreshAllData"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("iCloudDataChanged"), object: nil)
        
        // Force NavigationManager refresh to update all UI components
        let current = NavigationManager.shared.currentDate
        NavigationManager.shared.updateInterval(NavigationManager.shared.currentInterval, date: current)
    }
    
    private func testGoogleSignInConfig() {
        
        // Check Info.plist configuration
        _ = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        
        _ = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
        
        // Check URL schemes
        _ = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        
        // Check current authentication states
        _ = auth.isLinked(kind: .personal)
        _ = auth.getEmail(for: .personal)
        _ = auth.isLinked(kind: .professional)
        _ = auth.getEmail(for: .professional)
        
        // Check UserDefaults for tokens
        let _ = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.contains("google") }
        
        // Completed test
    }
    
    private func clearAllAuthTokens() {
        
        // Get all Google-related UserDefaults keys
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        let googleKeys = allKeys.filter { $0.contains("google") }
        
        // Remove all Google-related keys
        for key in googleKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        // Force update authentication states
        auth.unlink(kind: .personal)
        auth.unlink(kind: .professional)
        
        // Cleared tokens
    }
}

// MARK: - Color Picker Sheet Component
struct ColorPickerSheet: View {
    let title: String
    @Binding var selectedColor: Color
    let onColorChange: (Color) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ColorPicker("Select Color", selection: $selectedColor, supportsOpacity: false)
                    .labelsHidden()
                    .padding()
                
                Button("Done") {
                    onColorChange(selectedColor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Color Picker Row Component (Legacy)
struct ColorPickerRow: View {
    let title: String
    let icon: String
    @Binding var selectedColor: Color
    let onColorChange: (Color) -> Void
    
    @State private var showingColorPicker = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(selectedColor)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text("Tap to customize")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Color preview circle
            Circle()
                .fill(selectedColor)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingColorPicker = true
        }
        .sheet(isPresented: $showingColorPicker) {
            ColorPickerSheet(
                title: title,
                selectedColor: $selectedColor,
                onColorChange: onColorChange
            )
        }
    }
}

// MARK: - Custom Logs Items Inline View
struct CustomLogItemsInlineView: View {
    /// Which collection (0 or 1) this inline editor manages.
    let collectionIndex: Int

    @ObservedObject private var customLogManager = CustomLogManager.shared
    @State private var showingAddItem = false
    @State private var newItemTitle = ""
    @State private var editingItem: CustomLogItemData?

    private let maxItems = 10
    private let maxItemLength = 20

    private var collectionItems: [CustomLogItemData] {
        customLogManager.items(in: collectionIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with add button
            HStack {
                Text("Items (\(collectionItems.count)/\(maxItems))")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if collectionItems.count < maxItems {
                    Button(action: { showingAddItem = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Items list
            if collectionItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)

                    Text("No custom log items")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Tap + to add your first item")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(collectionItems) { item in
                        CustomLogItemInlineRow(
                            item: item,
                            onEdit: { editingItem = $0 },
                            onDelete: { customLogManager.deleteItem($0) },
                            onToggle: { customLogManager.updateItem($0) }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddCustomLogItemInlineView(
                maxLength: maxItemLength,
                onSave: { title in
                    let newItem = CustomLogItemData(
                        title: title,
                        displayOrder: collectionItems.count,
                        collectionIndex: collectionIndex
                    )
                    customLogManager.addItem(newItem)
                }
            )
        }
        .sheet(item: $editingItem) { item in
            EditCustomLogItemInlineView(
                item: item,
                maxLength: maxItemLength,
                onSave: { updatedItem in
                    customLogManager.updateItem(updatedItem)
                }
            )
        }
    }
}

struct CustomLogItemInlineRow: View {
    let item: CustomLogItemData
    let onEdit: (CustomLogItemData) -> Void
    let onDelete: (UUID) -> Void
    let onToggle: (CustomLogItemData) -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                var updatedItem = item
                updatedItem.isEnabled.toggle()
                onToggle(updatedItem)
            }) {
                Image(systemName: item.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isEnabled ? .accentColor : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
            
            Text(item.title)
                .font(.body)
                .strikethrough(!item.isEnabled)
                .foregroundColor(item.isEnabled ? .primary : .secondary)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: { onEdit(item) }) {
                Image(systemName: "pencil")
                    .foregroundColor(.accentColor)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            
            Button(action: { showingDeleteAlert = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .alert("Delete Item", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete(item.id)
            }
        } message: {
            Text("Are you sure you want to delete '\(item.title)'?")
        }
    }
}

struct AddCustomLogItemInlineView: View {
    @Environment(\.dismiss) private var dismiss
    let maxLength: Int
    let onSave: (String) -> Void
    
    @State private var title = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item title", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > maxLength {
                                title = String(newValue.prefix(maxLength))
                            }
                        }
                    
                    Text("\(title.count)/\(maxLength) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Custom Logs Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

struct EditCustomLogItemInlineView: View {
    @Environment(\.dismiss) private var dismiss
    let item: CustomLogItemData
    let maxLength: Int
    let onSave: (CustomLogItemData) -> Void
    
    @State private var title: String
    @State private var isEnabled: Bool
    
    init(item: CustomLogItemData, maxLength: Int, onSave: @escaping (CustomLogItemData) -> Void) {
        self.item = item
        self.maxLength = maxLength
        self.onSave = onSave
        self._title = State(initialValue: item.title)
        self._isEnabled = State(initialValue: item.isEnabled)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item title", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > maxLength {
                                title = String(newValue.prefix(maxLength))
                            }
                        }
                    
                    Text("\(title.count)/\(maxLength) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("Enabled", isOn: $isEnabled)
                }
            }
            .navigationTitle("Edit Custom Logs Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updatedItem = item
                        updatedItem.title = title
                        updatedItem.isEnabled = isEnabled
                        updatedItem.updatedAt = Date()
                        onSave(updatedItem)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}



// MARK: - Goal Categories Inline View
struct GoalCategoriesInlineView: View {
    @ObservedObject private var goalsManager = GoalsManager.shared
    @State private var showingAddCategory = false
    @State private var editingCategory: GoalCategoryData?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Goal Categories")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if goalsManager.canAddCategory {
                    Button {
                        showingAddCategory = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Max \(GoalsManager.maxCategories)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if goalsManager.categories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    
                    Text("No goal categories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Tap + to add your first category")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition })) { category in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                                .font(.body)
                            
                            Text(category.title)
                                .font(.body)
                            
                            Spacer()
                            
                            let goalCount = goalsManager.getGoalsForCategory(category.id).count
                            Text("\(goalCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                            
                            Button {
                                editingCategory = category
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddGoalCategorySheet { title in
                goalsManager.addCategory(title: title)
            }
        }
        .sheet(item: $editingCategory) { category in
            EditGoalCategorySheet(category: category) { updatedCategory in
                goalsManager.updateCategory(updatedCategory)
            } onDelete: {
                goalsManager.deleteCategory(category.id)
            }
        }
    }
}

// MARK: - Add Goal Category Sheet
struct AddGoalCategorySheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    
    private let maxLength = 50
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category Name", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > maxLength {
                                title = String(newValue.prefix(maxLength))
                            }
                        }
                    
                    Text("\(title.count)/\(maxLength) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Goal Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                    .fontWeight(.semibold)
                    .foregroundColor(!title.isEmpty ? .accentColor : .secondary)
                    .opacity(!title.isEmpty ? 1.0 : 0.5)
                }
            }
        }
    }
}

// MARK: - Edit Goal Category Sheet
struct EditGoalCategorySheet: View {
    let category: GoalCategoryData
    let onSave: (GoalCategoryData) -> Void
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var showingDeleteAlert = false
    
    private let maxLength = 50
    
    init(category: GoalCategoryData, onSave: @escaping (GoalCategoryData) -> Void, onDelete: @escaping () -> Void) {
        self.category = category
        self.onSave = onSave
        self.onDelete = onDelete
        self._title = State(initialValue: category.title)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category Name", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > maxLength {
                                title = String(newValue.prefix(maxLength))
                            }
                        }
                    
                    Text("\(title.count)/\(maxLength) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Category")
                        }
                    }
                }
            }
            .navigationTitle("Edit Goal Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updatedCategory = category
                        updatedCategory.title = title
                        updatedCategory.updatedAt = Date()
                        onSave(updatedCategory)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .alert("Delete Category?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This will delete the category and all goals in it. This action cannot be undone.")
            }
        }
    }
}

// MARK: - Workout Type Selection View
struct WorkoutTypeSelectionView: View {
    @ObservedObject private var appPrefs = AppPreferences.shared
    @State private var searchText = ""
    @State private var colorPickerType: WorkoutType?

    private var filteredTypes: [WorkoutType] {
        if searchText.isEmpty {
            return WorkoutType.allCases.map { $0 }
        }
        return WorkoutType.allCases.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                Button("Select All") {
                    appPrefs.selectedWorkoutTypes = Set(WorkoutType.allCases)
                }
                Button("Deselect All") {
                    appPrefs.selectedWorkoutTypes = []
                }
            }

            Section {
                ForEach(filteredTypes) { type in
                    HStack {
                        Button {
                            toggleType(type)
                        } label: {
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundColor(appPrefs.colorForWorkoutType(type))
                                    .frame(width: 24)
                                Text(type.displayName)
                                    .foregroundColor(.primary)
                            }
                        }

                        Spacer()

                        if appPrefs.selectedWorkoutTypes.contains(type) {
                            // Color circle
                            Button {
                                colorPickerType = type
                            } label: {
                                Circle()
                                    .fill(appPrefs.colorForWorkoutType(type))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle().stroke(Color(.systemGray3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            } footer: {
                Text("Selected types will appear in the workout type picker when adding or editing entries. Tap the color circle to change an icon's color.")
            }
        }
        .searchable(text: $searchText, prompt: "Search workout types")
        .navigationTitle("Workout Types")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $colorPickerType) { type in
            ColorPickerSheet(
                title: "\(type.displayName) Icon Color",
                selectedColor: Binding(
                    get: { appPrefs.colorForWorkoutType(type) },
                    set: { appPrefs.setColorForWorkoutType(type, color: $0) }
                ),
                onColorChange: { color in
                    appPrefs.setColorForWorkoutType(type, color: color)
                }
            )
        }
    }

    private func toggleType(_ type: WorkoutType) {
        if appPrefs.selectedWorkoutTypes.contains(type) {
            appPrefs.selectedWorkoutTypes.remove(type)
        } else {
            appPrefs.selectedWorkoutTypes.insert(type)
        }
    }
}
