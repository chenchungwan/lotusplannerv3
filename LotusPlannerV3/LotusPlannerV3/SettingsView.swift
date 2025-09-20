import SwiftUI

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
        case .compact: "Compact One"
        case .compactTwo: "Compact Two"
        case .mobile: "Column"
        
        }
    }
    
    var description: String {
        switch self {
        case .defaultNew: "Timeline & Tasks side-by-side, Logs row, then Journal"
        case .compact: "Timeline on left, tasks and journal on right with adjustable divider"
        case .compactTwo: "Tasks first, then Timeline + Logs column next to Journal"
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
        case journal
        case weeklyView
        case gWeekView
    }
    
    @Published var currentView: CurrentView = .calendar
    @Published var showTasksView = false
    @Published var currentInterval: TimelineInterval = .day
    @Published var currentDate: Date = Date()
    @Published var showingSettings = false
    @Published var showingAllTasks = false
    
    private init() {}
    
    func switchToCalendar() {
        currentView = .calendar
        showTasksView = false
    }
    
    func switchToTasks() {
        currentView = .tasks
        showTasksView = true
    }
    

    
    func switchToJournal() {
        currentView = .journal
        showTasksView = false
    }
    
    func switchToWeeklyView() {
        currentView = .weeklyView
        showTasksView = false
        currentInterval = .week // WeeklyView is always week view
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
    
    @Published var hideCompletedTasks: Bool {
        didSet {
            UserDefaults.standard.set(hideCompletedTasks, forKey: "hideCompletedTasks")
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
    
    // Show events as list vs timeline in Day view
    @Published var showEventsAsListInDay: Bool {
        didSet {
            UserDefaults.standard.set(showEventsAsListInDay, forKey: "showEventsAsListInDay")
        }
    }
    
    // Tasks view layout preference
    @Published var tasksLayoutHorizontal: Bool {
        didSet {
            UserDefaults.standard.set(tasksLayoutHorizontal, forKey: "tasksLayoutHorizontal")
        }
    }
    
    // Visibility toggles removed: Logs and Journal always shown
    

    

    

    

    
    private init() {
        self.isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        self.hideCompletedTasks = UserDefaults.standard.bool(forKey: "hideCompletedTasks")
        self.hideRecurringEventsInMonth = UserDefaults.standard.bool(forKey: "hideRecurringEventsInMonth")

        // useDayViewDefault removed

        
        // Load day view layout preference (default to Compact One layout if unset)
        let layoutRaw = UserDefaults.standard.integer(forKey: "dayViewLayout")
        self.dayViewLayout = DayViewLayoutOption(rawValue: layoutRaw) ?? .compact
        
        // Load events-as-list preference (default false)
        self.showEventsAsListInDay = UserDefaults.standard.bool(forKey: "showEventsAsListInDay")

        // Load tasks layout preference (default false - vertical layout)
        self.tasksLayoutHorizontal = UserDefaults.standard.bool(forKey: "tasksLayoutHorizontal")


        
        // Load colors from UserDefaults or use defaults
        let personalHex = UserDefaults.standard.string(forKey: "personalColor") ?? "#dcd6ff"
        let professionalHex = UserDefaults.standard.string(forKey: "professionalColor") ?? "#38eb50"
        
        self.personalColor = Color(hex: personalHex) ?? Color(hex: "#dcd6ff") ?? .purple
        self.professionalColor = Color(hex: professionalHex) ?? Color(hex: "#38eb50") ?? .green
    }
    
    func updateDarkMode(_ value: Bool) {
        isDarkMode = value
    }
    
    func updateHideCompletedTasks(_ value: Bool) {
        hideCompletedTasks = value
    }
    
    func updatePersonalColor(_ color: Color) {
        personalColor = color
    }
    
    func updateProfessionalColor(_ color: Color) {
        professionalColor = color
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
    
    func updateTasksLayoutHorizontal(_ value: Bool) {
        tasksLayoutHorizontal = value
    }

    // removed updateUseDayViewDefault
    
    // Removed visibility update methods
    

    

    

}

struct SettingsView: View {
    @ObservedObject private var auth = GoogleAuthManager.shared
    @StateObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // State for show/hide account toggles (placeholder for future implementation)
    @State private var showPersonalAccount = true
    @State private var showProfessionalAccount = true
    
    // State for color picker modals
    @State private var showingPersonalColorPicker = false
    @State private var showingProfessionalColorPicker = false
    @State private var showingDeleteAllAlert = false
    @State private var showingDeleteSuccessAlert = false
    @State private var pendingUnlink: GoogleAuthManager.AccountKind?
    



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

                Section("Daily View Preference") {
                    // Day View Layout Options with Radio Buttons
                    ForEach(DayViewLayoutOption.allCases) { option in
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
                    
                    Toggle(isOn: Binding(
                        get: { appPrefs.showEventsAsListInDay },
                        set: { appPrefs.updateShowEventsAsListInDay($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Events as List in Day View")
                                .font(.body)
                            Text("Replaces timeline with a simple chronological list")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Tasks View Preference
                Section("Tasks View Preference") {
                    Toggle(isOn: Binding(
                        get: { appPrefs.tasksLayoutHorizontal },
                        set: { appPrefs.updateTasksLayoutHorizontal($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Horizontal Task Lists")
                                .font(.body)
                            Text("Display task lists side by side in a scrollable row")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
                
                // Components Visibility section removed: Logs and Journal are always visible
                
                
                
                Section("Troubleshooting") {
                    Button {
                        GoogleAuthManager.shared.clearAllAuthState()
                    } label: {
                        HStack {
                            Image(systemName: "key.slash")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Clear Auth State")
                                    .font(.body)
                                Text("Fix authentication issues by clearing all Google auth data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

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



#Preview {
    SettingsView()
} 