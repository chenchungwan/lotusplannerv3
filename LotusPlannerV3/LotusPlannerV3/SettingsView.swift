import SwiftUI

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
    case compactTwo = 1
    case defaultNew = 3
    case mobile = 4

    var id: Int { rawValue }
    static var allCases: [DayViewLayoutOption] { [.compact, .compactTwo, .defaultNew, .mobile] }

    var displayName: String {
        switch self {
        case .defaultNew: "Expanded"
        case .compact: "Classic"
        case .compactTwo: "Compact"
        case .mobile: "Mobile"
        }
    }
    
    var description: String {
        switch self {
        case .defaultNew: "Horizontal layout: Timeline & Tasks side-by-side, Logs row, then Journal"
        case .compact: "Classic layout with Timeline on left, Tasks and Journal on right with adjustable divider"
        case .compactTwo: "Compact layout with Tasks first, then Timeline + Logs column next to Journal"
        case .mobile: "Single column: Events, Personal Tasks, Professional Tasks, then Logs"
        }
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
    }
    
    @Published var currentView: CurrentView = .calendar
    @Published var showTasksView = false
    @Published var currentInterval: TimelineInterval = .day
    @Published var currentDate: Date = Date()
    @Published var showingSettings = false
    @Published var showingAllTasks = false
    
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
        // Check if goals are hidden
        if AppPreferences.shared.hideGoals {
            // Redirect to calendar view if goals are hidden
            switchToCalendar()
            return
        }
        
        currentView = .goals
        showTasksView = false
        
        // Set appropriate time interval based on current view
        if currentInterval == .day {
            // If coming from day view, switch to week view (show current week's goals)
            currentInterval = .week
        }
        // Otherwise keep the current interval (week, month, year)
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

// MARK: - App Preferences
class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    
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
        let screenWidth = UIScreen.main.bounds.width
        if screenWidth < 700 {
            // Only show mobile layout for small screens
            return [.mobile]
        } else {
            // Show all layouts for larger screens
            return DayViewLayoutOption.allCases
        }
    }
    
    // Show events as list vs timeline in Day view
    @Published var showEventsAsListInDay: Bool {
        didSet {
            UserDefaults.standard.set(showEventsAsListInDay, forKey: "showEventsAsListInDay")
        }
    }
    
    // Show custom logs
    @Published var showCustomLogs: Bool {
        didSet {
            UserDefaults.standard.set(showCustomLogs, forKey: "showCustomLogs")
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
    
    var showAnyLogs: Bool {
        showWeightLogs || showWorkoutLogs || showFoodLogs || showWaterLogs
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
    

    

    

    

    
    private init() {
        self.isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        self.hideRecurringEventsInMonth = UserDefaults.standard.bool(forKey: "hideRecurringEventsInMonth")

        // useDayViewDefault removed

        
        // Load day view layout preference (default to Classic layout)
        let layoutRaw = UserDefaults.standard.integer(forKey: "dayViewLayout")
        let screenWidth = UIScreen.main.bounds.width
        
        // If screen width is less than iPad mini (768pt), force mobile layout
        // iPad mini portrait width is 768pt, so anything smaller (iPhone, etc.) uses mobile view
        if screenWidth < 768 {
            self.dayViewLayout = .mobile
        } else if UserDefaults.standard.object(forKey: "dayViewLayout") == nil {
            // If no layout has been explicitly chosen (key doesn't exist), use Classic
            self.dayViewLayout = .compact // Classic layout
        } else {
            // Otherwise use the saved layout or fallback to Classic if invalid
            self.dayViewLayout = DayViewLayoutOption(rawValue: layoutRaw) ?? .compact
        }
        
        // Load events-as-list preference (default false)
        self.showEventsAsListInDay = UserDefaults.standard.bool(forKey: "showEventsAsListInDay")

        // Load row-based weekly view preference (default false - column layout)
        self.useRowBasedWeeklyView = UserDefaults.standard.bool(forKey: "useRowBasedWeeklyView")

        // Load tasks layout preference (default false - vertical layout)
        self.tasksLayoutHorizontal = UserDefaults.standard.bool(forKey: "tasksLayoutHorizontal")

        // Load logs visibility preferences (default all visible)
        self.showWeightLogs = UserDefaults.standard.object(forKey: "showWeightLogs") as? Bool ?? true
        self.showWorkoutLogs = UserDefaults.standard.object(forKey: "showWorkoutLogs") as? Bool ?? true
        self.showFoodLogs = UserDefaults.standard.object(forKey: "showFoodLogs") as? Bool ?? true
        self.showWaterLogs = UserDefaults.standard.object(forKey: "showWaterLogs") as? Bool ?? true
        self.showCustomLogs = UserDefaults.standard.object(forKey: "showCustomLogs") as? Bool ?? false
        self.hideCompletedTasks = UserDefaults.standard.object(forKey: "hideCompletedTasks") as? Bool ?? false
        self.hideGoals = UserDefaults.standard.object(forKey: "hideGoals") as? Bool ?? false
        
        


        
        // Load colors from UserDefaults or use defaults
        let personalHex = UserDefaults.standard.string(forKey: "personalColor") ?? "#dcd6ff"
        let professionalHex = UserDefaults.standard.string(forKey: "professionalColor") ?? "#38eb50"
        
        self.personalColor = Color(hex: personalHex) ?? Color(hex: "#dcd6ff") ?? .purple
        self.professionalColor = Color(hex: professionalHex) ?? Color(hex: "#38eb50") ?? .green
        
        // Load divider positions from UserDefaults or use defaults
        self.dayViewCompactTasksHeight = UserDefaults.standard.object(forKey: "dayViewCompactTasksHeight") as? CGFloat ?? UIScreen.main.bounds.height * 0.35
        self.dayViewCompactLeftColumnWidth = UserDefaults.standard.object(forKey: "dayViewCompactLeftColumnWidth") as? CGFloat ?? UIScreen.main.bounds.width * 0.25
        self.dayViewCompactLeftTopHeight = UserDefaults.standard.object(forKey: "dayViewCompactLeftTopHeight") as? CGFloat ?? 260
        self.dayViewExpandedTopRowHeight = UserDefaults.standard.object(forKey: "dayViewExpandedTopRowHeight") as? CGFloat ?? UIScreen.main.bounds.height * 0.5
        self.dayViewExpandedLeftTimelineWidth = UserDefaults.standard.object(forKey: "dayViewExpandedLeftTimelineWidth") as? CGFloat ?? UIScreen.main.bounds.width * 0.25
        self.dayViewExpandedLogsHeight = UserDefaults.standard.object(forKey: "dayViewExpandedLogsHeight") as? CGFloat ?? UIScreen.main.bounds.height * 0.25
        self.calendarDayLeftSectionWidth = UserDefaults.standard.object(forKey: "calendarDayLeftSectionWidth") as? CGFloat ?? UIScreen.main.bounds.width * 0.25
        self.calendarDayRightColumn2Width = UserDefaults.standard.object(forKey: "calendarDayRightColumn2Width") as? CGFloat ?? UIScreen.main.bounds.width * 0.25
        self.calendarDayLeftTimelineHeight = UserDefaults.standard.object(forKey: "calendarDayLeftTimelineHeight") as? CGFloat ?? UIScreen.main.bounds.height * 0.6
        self.calendarDayRightSectionTopHeight = UserDefaults.standard.object(forKey: "calendarDayRightSectionTopHeight") as? CGFloat ?? UIScreen.main.bounds.height * 0.6
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
        showCustomLogs = value
    }
    
    func updateHideCompletedTasks(_ value: Bool) {
        hideCompletedTasks = value
    }
    
    func updateHideGoals(_ value: Bool) {
        hideGoals = value
    }
    
    func updateHideRecurringEventsInMonth(_ value: Bool) {
        hideRecurringEventsInMonth = value
    }
    
    func updateDayViewLayout(_ layout: DayViewLayoutOption) {
        dayViewLayout = layout
    }
    
    func updateShowEventsAsListInDay(_ value: Bool) {
        showEventsAsListInDay = value
    }
    
    func updateUseRowBasedWeeklyView(_ value: Bool) {
        useRowBasedWeeklyView = value
    }
    
    func updateTasksLayoutHorizontal(_ value: Bool) {
        tasksLayoutHorizontal = value
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

    // removed updateUseDayViewDefault
    
    // Removed visibility update methods
    

    

    

}

struct SettingsView: View {
    @ObservedObject private var auth = GoogleAuthManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var iCloudManagerInstance = iCloudManager.shared
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
    @State private var pendingUnlink: GoogleAuthManager.AccountKind?
    
    // Check if device forces stacked layout (iPhone portrait)
    private var shouldUseStackedLayout: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    



    var body: some View {
        NavigationStack {
            Form {
                Section("Linked Accounts") {
                    accountRow(
                        kind: "Personal", 
                        kindEnum: .personal,
                        isVisible: $showPersonalAccount,
                        accountColor: $appPrefs.personalColor,
                        showingColorPicker: $showingPersonalColorPicker
                    )
                    accountRow(
                        kind: "Professional", 
                        kindEnum: .professional,
                        isVisible: $showProfessionalAccount,
                        accountColor: $appPrefs.professionalColor,
                        showingColorPicker: $showingProfessionalColorPicker
                    )
                }
                
                // Task Management section removed (Hide Completed Tasks now controlled via eye icon)

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

                Section("Daily View Preferences") {
                    // Day View Layout Options with Radio Buttons
                    ForEach(appPrefs.availableDayViewLayouts) { option in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: appPrefs.dayViewLayout == option ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(appPrefs.dayViewLayout == option ? .accentColor : .secondary)
                                        .font(.title2)
                                    
                                    Text(option.displayName)
                                        .font(.body)
                                        .fontWeight(appPrefs.dayViewLayout == option ? .semibold : .regular)
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

                // Tasks View Preference (hide on iPhone portrait where stacked layout is forced)
                if !shouldUseStackedLayout {
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
                                Text("Show water intake tracking in day views")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
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
                    
                    Toggle(isOn: Binding(
                        get: { appPrefs.showCustomLogs },
                        set: { appPrefs.updateShowCustomLogs($0) }
                    )) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundColor(appPrefs.showCustomLogs ? .accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom Logs")
                                    .font(.body)
                                Text("Show custom checklist items in day views")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Custom Logs Items subsection
                    if appPrefs.showCustomLogs {
                        VStack(alignment: .leading, spacing: 0) {
                            CustomLogItemsInlineView()
                        }
                        .padding(.leading, 20)
                        .padding(.top, 8)
                    }
                }
                
                // Goal Preferences section
                Section("Goal Preferences") {
                    Toggle(isOn: Binding(
                        get: { !appPrefs.hideGoals },
                        set: { appPrefs.updateHideGoals(!$0) }
                    )) {
                        HStack {
                            Image(systemName: "target")
                                .foregroundColor(appPrefs.hideGoals ? .secondary : .accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show Goals")
                                    .font(.body)
                                Text("Show goals in all views")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Goal Categories subsection
                    if !appPrefs.hideGoals {
                        GoalCategoriesInlineView()
                            .padding(.leading, 20)
                            .padding(.top, 8)
                    }
                }
                
                
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
                
                Section("iCloud Sync") {
                    iCloudSyncSection()
                }
                
                // Components Visibility section removed: Logs and Journal are always visible
                
                
                

                Section("Danger Zone") {
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
                Text(kind)
                    .font(.body)
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
    private func iCloudSyncSection() -> some View {
        VStack(spacing: 12) {
            // iCloud Status
            HStack {
                Image(systemName: iCloudManagerInstance.iCloudAvailable ? "icloud.fill" : "icloud.slash")
                    .foregroundColor(iCloudManagerInstance.iCloudAvailable ? .blue : .red)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Status")
                        .font(.body)
                    Text(iCloudManagerInstance.syncStatus.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Sync Progress (if syncing)
            if case .syncing = iCloudManagerInstance.syncStatus {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle())
            }
            
            // Manual Sync Button
            Button(action: {
                Task {
                    await performManualSync()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled({
                if case .syncing = iCloudManagerInstance.syncStatus {
                    return true
                }
                return false
            }())
            
            // Last Sync Time
            if let lastSync = iCloudManagerInstance.lastSyncDate {
                Text("Last sync: \(lastSync, formatter: DateFormatter.shortDateTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Debug iCloud Inspection Button
            Button(action: {
                JournalStorageNew.shared.inspectiCloudContents()
            }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("🔍 Inspect iCloud Contents")
                }
            }
            .buttonStyle(.bordered)
            .foregroundColor(.blue)
        }
    }
    
    private func performManualSync() async {
        // Force iCloud sync
        iCloudManagerInstance.forceCompleteSync()
        
        // Force goals sync
        await DataManager.shared.goalsManager.forceSync()
        
        // Force custom log sync
        await DataManager.shared.customLogManager.forceSync()
        
        // Update last sync time
        iCloudManagerInstance.lastSyncDate = Date()
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
        
        // Reload goals data
        await DataManager.shared.goalsManager.forceSync()
        
        // Reload custom log data
        await DataManager.shared.customLogManager.forceSync()
        
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
    @ObservedObject private var customLogManager = CustomLogManager.shared
    @State private var showingAddItem = false
    @State private var newItemTitle = ""
    @State private var editingItem: CustomLogItemData?
    
    private let maxItems = 10
    private let maxItemLength = 20
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with add button
            HStack {
                Text("Items (\(customLogManager.items.count)/\(maxItems))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if customLogManager.items.count < maxItems {
                    Button(action: { showingAddItem = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Items list
            if customLogManager.items.isEmpty {
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
                    ForEach(customLogManager.items) { item in
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
                        displayOrder: customLogManager.items.count
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
            // Header with title and + button
            HStack {
                Text("Goal Categories")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Show + button only if we can add more categories
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
            
            // Categories list
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
                            
                            // Show goal count for this category
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
                        .onChange(of: title) { oldValue, newValue in
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
                        .onChange(of: title) { oldValue, newValue in
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

#Preview {
    SettingsView()
} 
