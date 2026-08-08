import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    
    
    @Published var account1Color: Color {
        didSet {
            UserDefaults.standard.set(account1Color.toHex(), forKey: "personalColor")
        }
    }
    
    @Published var account2Color: Color {
        didSet {
            UserDefaults.standard.set(account2Color.toHex(), forKey: "professionalColor")
        }
    }

    // Custom account names (editable by user)
    @Published var account1Name: String {
        didSet {
            let trimmed = String(account1Name.prefix(30))
            if trimmed != account1Name {
                account1Name = trimmed
            }
            UserDefaults.standard.set(account1Name, forKey: "personalAccountName")
        }
    }

    @Published var account2Name: String {
        didSet {
            let trimmed = String(account2Name.prefix(30))
            if trimmed != account2Name {
                account2Name = trimmed
            }
            UserDefaults.standard.set(account2Name, forKey: "professionalAccountName")
        }
    }

    // Helper function to get account name by kind
    func accountName(for kind: GoogleAuthManager.AccountKind) -> String {
        switch kind {
        case .account1:
            return account1Name
        case .account2:
            return account2Name
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

    @Published var showWeeklySummarySection: Bool {
        didSet {
            UserDefaults.standard.set(showWeeklySummarySection, forKey: "showWeeklySummarySection")
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
    
    @Published var calendarWeekTasksAccount1Width: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarWeekTasksAccount1Width, forKey: "calendarWeekTasksPersonalWidth")
        }
    }
    
    @Published var calendarWeekTopSectionHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(calendarWeekTopSectionHeight, forKey: "calendarWeekTopSectionHeight")
        }
    }
    
    // TasksView Divider Positions
    @Published var tasksViewAccount1Width: CGFloat {
        didSet {
            UserDefaults.standard.set(tasksViewAccount1Width, forKey: "tasksViewPersonalWidth")
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
        self.showWeeklySummarySection = UserDefaults.standard.object(forKey: "showWeeklySummarySection") as? Bool ?? false

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
            if !decoded.contains(.custom2) {
                decoded.append(.custom2)
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
        self.hideBookView = UserDefaults.standard.object(forKey: "hideBookView") as? Bool ?? true
        // One-time migration: force verbose logging off so users running
        // a build that left it on previously see the new default. The
        // sentinel key ensures this only happens once; subsequent toggles
        // by the user are respected.
        let resetSentinelKey = "verboseLoggingResetToOffOnce.v1"
        if !UserDefaults.standard.bool(forKey: resetSentinelKey) {
            UserDefaults.standard.set(false, forKey: DevLogger.verboseLoggingDefaultsKey)
            UserDefaults.standard.set(true, forKey: resetSentinelKey)
        }
        self.verboseLoggingEnabled = UserDefaults.standard.object(forKey: DevLogger.verboseLoggingDefaultsKey) as? Bool ?? false
        
        


        
        // Load colors from UserDefaults or use defaults
        let account1Hex = UserDefaults.standard.string(forKey: "personalColor") ?? "#dcd6ff"
        let account2Hex = UserDefaults.standard.string(forKey: "professionalColor") ?? "#38eb50"
        
        self.account1Color = Color(hex: account1Hex) ?? Color(hex: "#dcd6ff") ?? .purple
        self.account2Color = Color(hex: account2Hex) ?? Color(hex: "#38eb50") ?? .green

        // Load custom account names or use defaults
        self.account1Name = UserDefaults.standard.string(forKey: "personalAccountName") ?? "Linked Account 1"
        self.account2Name = UserDefaults.standard.string(forKey: "professionalAccountName") ?? "Linked Account 2"

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
        self.calendarWeekTasksAccount1Width = UserDefaults.standard.object(forKey: "calendarWeekTasksPersonalWidth") as? CGFloat ?? UIScreen.main.bounds.width * 0.3
        self.calendarWeekTopSectionHeight = UserDefaults.standard.object(forKey: "calendarWeekTopSectionHeight") as? CGFloat ?? 400
        
        // Load TasksView divider positions
        self.tasksViewAccount1Width = UserDefaults.standard.object(forKey: "tasksViewPersonalWidth") as? CGFloat ?? UIScreen.main.bounds.width * 0.5
        
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
    
    
    func updateAccount1Color(_ color: Color) {
        account1Color = color
    }
    
    func updateAccount2Color(_ color: Color) {
        account2Color = color
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
        } else if layout == .custom && CustomDayViewLibrary.load().versions.isEmpty {
            return
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

    func updateShowWeeklySummarySection(_ value: Bool) {
        showWeeklySummarySection = value
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
    
    func updateCalendarWeekTasksAccount1Width(_ value: CGFloat) {
        calendarWeekTasksAccount1Width = value
    }
    
    func updateCalendarWeekTopSectionHeight(_ value: CGFloat) {
        calendarWeekTopSectionHeight = value
    }
    
    // TasksView Divider Position Update Methods
    func updateTasksViewAccount1Width(_ value: CGFloat) {
        tasksViewAccount1Width = value
    }
    
    // WeekTimelineComponent Divider Position Update Methods
    func updateWeekTimelineTasksRowHeight(_ value: CGFloat) {
        weekTimelineTasksRowHeight = value
    }

    // removed updateUseDayViewDefault
    
    // Removed visibility update methods
    

    

    

}
