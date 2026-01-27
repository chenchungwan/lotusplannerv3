import SwiftUI

struct GlobalNavBar: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var calendarVM = DataManager.shared.calendarViewModel
    @ObservedObject private var auth = GoogleAuthManager.shared
    @ObservedObject private var logsVM = LogsViewModel.shared
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // Sheet states
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingReportIssues = false
    @State private var showingDatePicker = false
    @State private var showingAddEvent = false
    @State private var showingAddTask = false
    @State private var showingAddList = false
    @State private var newListName = ""
    @State private var newListAccountKind: GoogleAuthManager.AccountKind?
    @State private var showingAddLog = false

    // Sync alert states
    @State private var showingSyncAlert = false
    @State private var syncedDataMessage = ""

    // Date picker state
    @State private var selectedDateForPicker = Date()
    
    // Device-specific computed properties
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    private var isPortrait: Bool {
        verticalSizeClass == .regular
    }
    
    private var shouldShowTwoRows: Bool {
        isCompact && isPortrait
    }
    
    private var adaptivePadding: CGFloat {
        isCompact ? 8 : 12
    }
    
    private var adaptiveButtonSpacing: CGFloat {
        isCompact ? 8 : 10
    }
    
    private var adaptiveIconSize: Font {
        isCompact ? .body : .title2
    }
    
    private var adaptiveButtonSize: CGFloat {
        isCompact ? 36 : 44
    }
    
    private var dateLabel: String {
        // Show "Task Lists" when in Lists view
        if navigationManager.currentView == .lists {
            return "Task Lists"
        }
        
        // Show filtered goals title when in Goals view
        if navigationManager.currentView == .goals {
            switch navigationManager.currentInterval {
            case .day:
                return "All Goals"
            case .week:
                guard let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
                    return "Goals"
                }
                let start = weekInterval.start
                let end = Calendar.mondayFirst.date(byAdding: .day, value: 6, to: start) ?? start
                let weekNumber = Calendar.mondayFirst.component(.weekOfYear, from: start)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "M/d"
                let startString = dateFormatter.string(from: start)
                let endString = dateFormatter.string(from: end)
                return "W\(weekNumber): \(startString) - \(endString)"
            case .month:
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: navigationManager.currentDate)
            case .year:
                let year = Calendar.current.component(.year, from: navigationManager.currentDate)
                return "\(year)"
            }
        }
        
        // Show "All Tasks" when in Tasks view and showing all tasks
        if navigationManager.showTasksView && navigationManager.showingAllTasks {
            return "All Tasks"
        }
        
        // Show year when in yearly calendar view
        if navigationManager.currentView == .yearlyCalendar {
            let year = Calendar.current.component(.year, from: navigationManager.currentDate)
            return "\(year)"
        }
        
        switch navigationManager.currentInterval {
        case .year:
            let year = Calendar.current.component(.year, from: navigationManager.currentDate)
            return "\(year)"
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: navigationManager.currentDate)
        case .week:
            guard let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
                return ""
            }
            let start = weekInterval.start
            let end = Calendar.mondayFirst.date(byAdding: .day, value: 6, to: start) ?? start
            
            // Get week number
            let weekNumber = Calendar.mondayFirst.component(.weekOfYear, from: start)
            
            // Format dates as M/d
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/d"
            let startString = dateFormatter.string(from: start)
            let endString = dateFormatter.string(from: end)
            
            return "W\(weekNumber): \(startString) - \(endString)"
        case .day:
            let date = navigationManager.currentDate
            
            // Get day of week abbreviation
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            let dayOfWeek = dayFormatter.string(from: date).uppercased()
            
            // Format as M/d/yy
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/d/yy"
            let dateString = dateFormatter.string(from: date)
            
            return "\(dayOfWeek) \(dateString)"
        }
    }
    
    private var isCurrentPeriod: Bool {
        let now = Date()
        let currentDate = navigationManager.currentDate
        
        switch navigationManager.currentInterval {
        case .year:
            return Calendar.current.isDate(currentDate, equalTo: now, toGranularity: .year)
        case .month:
            return Calendar.current.isDate(currentDate, equalTo: now, toGranularity: .month)
        case .week:
            let mondayFirst = Calendar.mondayFirst
            guard let weekInterval = mondayFirst.dateInterval(of: .weekOfYear, for: currentDate),
                  let nowWeekInterval = mondayFirst.dateInterval(of: .weekOfYear, for: now) else {
                return false
            }
            return weekInterval.start == nowWeekInterval.start
        case .day:
            return Calendar.current.isDate(currentDate, inSameDayAs: now)
        }
    }
    
    private func handleTimeIntervalChange(_ interval: TimelineInterval) {
        if navigationManager.currentView == .goals {
            navigationManager.updateInterval(interval, date: Date())
        } else if navigationManager.showTasksView {
            // In Tasks view: filter to the interval
            navigationManager.showingAllTasks = false
            navigationManager.updateInterval(interval, date: Date())
        } else if navigationManager.currentView == .yearlyCalendar {
            // In Yearly Calendar view: switch to the new interval
            navigationManager.showingAllTasks = false
            if interval == .year {
                navigationManager.updateInterval(interval, date: Date())
                // Already in yearly view, just update interval
            } else {
                // Update interval first, then force view change
                navigationManager.updateInterval(interval, date: Date())

                // Use the existing switchToCalendar() function which should work properly
                navigationManager.switchToCalendar()
            }
        } else {
            // In Calendar view: go to the interval
            navigationManager.showingAllTasks = false
            if interval == .year {
                navigationManager.updateInterval(interval, date: Date())
                navigationManager.switchToYearlyCalendar()
            } else {
                // Update interval BEFORE switching view so switchToCalendar() sees the new interval
                navigationManager.updateInterval(interval, date: Date())
                navigationManager.switchToCalendar()
            }
        }
    }
    
    private func step(_ direction: Int) {
        // Handle year navigation when in yearly calendar view
        if navigationManager.currentView == .yearlyCalendar {
            if let newDate = Calendar.mondayFirst.date(byAdding: .year, value: direction, to: navigationManager.currentDate) {
                navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
            }
            return
        }
        
        // Handle journal day views navigation
        if navigationManager.currentView == .journalDayViews {
            let component = navigationManager.currentInterval.calendarComponent
            if let newDate = Calendar.mondayFirst.date(byAdding: component, value: direction, to: navigationManager.currentDate) {
                // Update the navigation manager
                navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)

                // Post notification for journal content refresh
                NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
            }
            return
        }
        
        let component = navigationManager.currentInterval.calendarComponent
        if let newDate = Calendar.mondayFirst.date(byAdding: component, value: direction, to: navigationManager.currentDate) {
            // First update the navigation
            navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
            
            // Then do a comprehensive data refresh
            Task {
                // Clear all caches first
                calendarVM.clearAllData()
                await tasksVM.loadTasks(forceClear: true)
                
                // Load fresh data based on interval
                switch navigationManager.currentInterval {
                case .day:
                    await calendarVM.loadCalendarData(for: newDate)
                case .week:
                    await calendarVM.loadCalendarDataForWeek(containing: newDate)
                case .month:
                    await calendarVM.loadCalendarDataForMonth(containing: newDate)
                case .year:
                    await calendarVM.loadCalendarDataForMonth(containing: newDate)
                }
                
                // Force UI refresh
                await MainActor.run {
                    // Reload logs data
                    LogsViewModel.shared.reloadData()
                    
                    // Post notifications for UI updates
                    NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                    NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
                    
                    // Force calendar refresh
                    calendarVM.objectWillChange.send()
                    tasksVM.objectWillChange.send()
                }
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let safeAreaLeading = geometry.safeAreaInsets.leading
            let safeAreaTrailing = geometry.safeAreaInsets.trailing
            let horizontalSafeInset = max(safeAreaLeading, safeAreaTrailing, 0)
            
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // First row: Main navigation
                HStack(spacing: isCompact ? 4 : adaptiveButtonSpacing) {
                    Menu {
                            Button(action: {
                                navigationManager.switchToCalendar()
                            }) {
                                Label("Calendar", systemImage: "calendar")
                            }
                            
                            Button(action: {
                                navigationManager.switchToTasks()
                            }) {
                                Label("Tasks", systemImage: "checklist")
                            }
                            
                            Button(action: {
                                navigationManager.switchToLists()
                            }) {
                                Label("Lists", systemImage: "list.bullet")
                            }
                            
                            Button(action: {
                                navigationManager.switchToJournalDayViews()
                            }) {
                                Label("Journals", systemImage: "book")
                            }
                            
                            if !appPrefs.hideGoals {
                                Button(action: {
                                    navigationManager.switchToGoals()
                                }) {
                                    Label("Goals (Beta)", systemImage: "target")
                                }
                            }
                            Divider()
                            
                            Button("Settings") {
                                showingSettings = true
                            }
                            Button("About") {
                                showingAbout = true
                            }
                            Button("Report Issue / Request Features") {
                                showingReportIssues = true
                            }

                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(adaptiveIconSize)
                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        
                        // Hide navigation arrows in Lists view and in Goals All Goals view
                        if navigationManager.currentView != .lists && !(navigationManager.currentView == .goals && navigationManager.currentInterval == .day) {
                            Button { step(-1) } label: {
                                Image(systemName: "chevron.left")
                                    .font(adaptiveIconSize)
                                    .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                            }
                        }
                        
                        Button {
                            // Only open date picker if not in Lists view or Goals All Goals view
                            if navigationManager.currentView != .lists && !(navigationManager.currentView == .goals && navigationManager.currentInterval == .day) {
                                selectedDateForPicker = navigationManager.currentDate
                                showingDatePicker = true
                            }
                        } label: {
                            Text(dateLabel)
                                .font(isCompact ? .headline : .title2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .foregroundColor(navigationManager.currentView == .lists || (navigationManager.showTasksView && navigationManager.showingAllTasks) || (navigationManager.currentView == .goals && navigationManager.currentInterval == .day) ? .primary : (isCurrentPeriod ? DateDisplayStyle.currentPeriodColor : .primary))
                        }
                        .disabled(navigationManager.currentView == .lists || (navigationManager.currentView == .goals && navigationManager.currentInterval == .day))
                        
                        // Hide navigation arrows in Lists view and in Goals All Goals view
                        if navigationManager.currentView != .lists && !(navigationManager.currentView == .goals && navigationManager.currentInterval == .day) {
                            Button { step(1) } label: {
                                Image(systemName: "chevron.right")
                                    .font(adaptiveIconSize)
                                    .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                            }
                        }
                        
                        Spacer()
                        
                        // Only show interval buttons in first row if NOT using two-row layout
                        if !shouldShowTwoRows {
                        // Show interval buttons in single row on all devices
                        // Hide navigation buttons in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                // In Simple Week View or Timebox View, show all buttons but highlight appropriate circle
                                if navigationManager.currentView == .simpleWeekView || navigationManager.currentView == .timebox {
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            handleTimeIntervalChange(.day)
                                        } label: {
                                            Image(systemName: "d.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Button {
                                        handleTimeIntervalChange(.week)
                                    } label: {
                                        Image(systemName: "w.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(.secondary)
                                    }
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            if navigationManager.currentView == .timebox {
                                                // Already in timebox, do nothing or stay
                                            } else {
                                                navigationManager.switchToTimebox()
                                            }
                                        } label: {
                                            Image(systemName: "t.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.currentView == .timebox ? .accentColor : .secondary)
                                        }
                                    }
                                } else {
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                                // In Tasks view with All Tasks filter: send notification to ensure proper update
                                                NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentDay"), object: nil)
                                            } else {
                                                // In other cases: use standard interval change
                                                handleTimeIntervalChange(.day)
                                            }
                                        } label: {
                                            Image(systemName: "d.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .day ? .accentColor : .secondary)))
                                        }
                                    }
                                    // Hide s.circle in Tasks view
                                    if navigationManager.currentView != .tasks {
                                        Button {
                                            // In other views: handle week interval change
                                            handleTimeIntervalChange(.week)
                                        } label: {
                                            Image(systemName: (navigationManager.currentView == .calendar || navigationManager.currentView == .yearlyCalendar || navigationManager.currentView == .simpleWeekView || navigationManager.currentView == .goals) ? "w.circle" : "s.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .week && navigationManager.currentView != .simpleWeekView ? .accentColor : .secondary)))
                                        }
                                    }
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                                // In Tasks view with All Tasks filter: send notification to ensure proper update
                                                NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentWeek"), object: nil)
                                            } else if navigationManager.currentView == .calendar || navigationManager.currentView == .yearlyCalendar {
                                                // In Calendar or Yearly Calendar view: switch to timebox view
                                                navigationManager.switchToTimebox()
                                            } else {
                                                // In other cases: use standard interval change
                                                handleTimeIntervalChange(.week)
                                            }
                                        } label: {
                                            Image(systemName: (navigationManager.currentView == .calendar || navigationManager.currentView == .yearlyCalendar) ? "t.circle" : "w.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentView == .timebox ? .accentColor : .secondary)))
                                        }
                                    }
                                }
                                Button {
                                    handleTimeIntervalChange(.month)
                                } label: {
                                    Image(systemName: "m.circle")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .month ? .accentColor : .secondary)))
                                }
                                Button {
                                    handleTimeIntervalChange(.year)
                                } label: {
                                    Image(systemName: "y.circle")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .accentColor : (navigationManager.currentInterval == .year ? .accentColor : .secondary)))
                                }
                            }
                            }
                            
                            // Only show action buttons in first row if NOT using two-row layout
                            if !shouldShowTwoRows {
                            
                            // Hide ellipsis.circle in calendar views, lists view, journal day views, simple week view, and timebox view
                            if navigationManager.currentView != .calendar && navigationManager.currentView != .yearlyCalendar && navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews && navigationManager.currentView != .simpleWeekView && navigationManager.currentView != .timebox {
                                if navigationManager.currentView == .goals {
                                    Button {
                                        navigationManager.updateInterval(.day, date: Date())
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(navigationManager.currentInterval == .day ? .accentColor : .secondary)
                                    }
                                } else {
                                    Menu {
                                        Button("All") {
                                            // Switch to "All" tasks view
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                        }
                                        Divider()
                                        Button("Has Due Date") {
                                            // Switch to All view with Has Due Date filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.hasDueDate)
                                        }
                                        Button("No Due Date") {
                                            // Switch to All view with No Due Date filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.noDueDate)
                                        }
                                        Button("Overdue") {
                                            // Switch to All view with Past Due filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.pastDue)
                                        }
                                        Button("Complete") {
                                            // Switch to All view with Complete filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.completed)
                                            // Turn off hide completed setting to show completed tasks
                                            appPrefs.updateHideCompletedTasks(false)
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(navigationManager.showingAllTasks ? .accentColor : .secondary)
                                    }
                                }
                            }
                            
                            // Hide vertical separator in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                Text("|")
                                    .font(adaptiveIconSize)
                            }
                            Button {
                                // Comprehensive data reload
                                Task {
                                    await reloadAllData()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(adaptiveIconSize)
                                    .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                            }
                            
                            // Hide completed tasks toggle (in Tasks, Lists, Calendar day/week views, and Timebox view)
                            if navigationManager.currentView == .tasks || navigationManager.currentView == .lists || 
                               (navigationManager.currentView == .calendar && (navigationManager.currentInterval == .day || navigationManager.currentInterval == .week)) ||
                               navigationManager.currentView == .timebox {
                                Button {
                                    appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks)
                                } label: {
                                    Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash" : "eye")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                            }

                            // Bulk edit toggle (in Calendar day view)
                            if navigationManager.currentView == .calendar && navigationManager.currentInterval == .day {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleCalendarBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle (in Calendar week view)
                            if navigationManager.currentView == .calendar && navigationManager.currentInterval == .week {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleWeeklyCalendarBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle (in Tasks view)
                            if navigationManager.currentView == .tasks {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleTasksBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle (in Lists view)
                            if navigationManager.currentView == .lists {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleListsBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // + menu based on current view
                            if navigationManager.currentView == .journalDayViews {
                                // In Journal Day Views: menu with Event and Task only
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else if navigationManager.currentView == .lists {
                                // In Lists view: menu with Event, Task, and List
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                    Button("List") {
                                        showingAddList = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else if navigationManager.currentView == .goals {
                                // In Goals view: menu with Event, Task, and Goal
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                    Button("Goal") {
                                        NotificationCenter.default.post(name: Notification.Name("ShowAddGoal"), object: nil)
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else {
                                // In other views: menu with Event and Task only
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            }
                            }
                    }
                    .padding(.horizontal, max(adaptivePadding + horizontalSafeInset, 4))
                    .padding(.top, 8)
                    .padding(.bottom, shouldShowTwoRows ? 2 : 8)
                    
                    // Second row on compact portrait devices: Interval and action buttons
                    if shouldShowTwoRows {
                        HStack(spacing: isCompact ? 4 : adaptiveButtonSpacing) {
                            // Hide navigation buttons in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                // In Simple Week View or Timebox View, show all buttons but highlight appropriate circle
                                if navigationManager.currentView == .simpleWeekView || navigationManager.currentView == .timebox {
                                    if navigationManager.currentView != .goals {
                                        Button {
                                        handleTimeIntervalChange(.day)
                                        } label: {
                                            Image(systemName: "d.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Button {
                                        handleTimeIntervalChange(.week)
                                    } label: {
                                        Image(systemName: "w.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(.secondary)
                                    }
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            if navigationManager.currentView == .timebox {
                                                // Already in timebox, do nothing or stay
                                            } else {
                                                navigationManager.switchToTimebox()
                                            }
                                        } label: {
                                            Image(systemName: "t.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.currentView == .timebox ? .accentColor : .secondary)
                                        }
                                    }
                                } else {
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                                // In Tasks view with All Tasks filter: send notification to ensure proper update
                                                NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentDay"), object: nil)
                                            } else {
                                                // In other cases: use standard interval change
                                                handleTimeIntervalChange(.day)
                                            }
                                        } label: {
                                            Image(systemName: "d.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .day ? .accentColor : .secondary)))
                                        }
                                    }
                                    // Hide s.circle in Tasks view
                                    if navigationManager.currentView != .tasks {
                                        Button {
                                            // In other views: handle week interval change
                                            handleTimeIntervalChange(.week)
                                        } label: {
                                            Image(systemName: (navigationManager.currentView == .calendar || navigationManager.currentView == .yearlyCalendar || navigationManager.currentView == .simpleWeekView || navigationManager.currentView == .goals) ? "w.circle" : "s.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .week && navigationManager.currentView != .simpleWeekView ? .accentColor : .secondary)))
                                        }
                                    }
                                    if navigationManager.currentView != .goals {
                                        Button {
                                            if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                                                // In Tasks view with All Tasks filter: send notification to ensure proper update
                                                NotificationCenter.default.post(name: Notification.Name("FilterTasksToCurrentWeek"), object: nil)
                                            } else if navigationManager.currentView == .calendar || navigationManager.currentView == .yearlyCalendar {
                                                // In Calendar or Yearly Calendar view: switch to timebox view
                                                navigationManager.switchToTimebox()
                                            } else {
                                                // In other cases: use standard interval change
                                                handleTimeIntervalChange(.week)
                                            }
                                        } label: {
                                            Image(systemName: (navigationManager.currentView == .calendar || navigationManager.currentView == .yearlyCalendar) ? "t.circle" : "w.circle")
                                                .font(adaptiveIconSize)
                                                .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                                .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentView == .timebox ? .accentColor : .secondary)))
                                        }
                                    }
                                }
                                Button {
                                    handleTimeIntervalChange(.month)
                                } label: {
                                    Image(systemName: "m.circle")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .month ? .accentColor : .secondary)))
                                }
                                Button {
                                    handleTimeIntervalChange(.year)
                                } label: {
                                    Image(systemName: "y.circle")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .accentColor : (navigationManager.currentInterval == .year ? .accentColor : .secondary)))
                                }
                            }
                             
                            Spacer()
                            
                            // Hide ellipsis.circle in calendar views, lists view, journal day views, simple week view, and timebox view
                            if navigationManager.currentView != .calendar && navigationManager.currentView != .yearlyCalendar && navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews && navigationManager.currentView != .simpleWeekView && navigationManager.currentView != .timebox {
                                if navigationManager.currentView == .goals {
                                    Button {
                                        navigationManager.updateInterval(.day, date: Date())
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(navigationManager.currentInterval == .day ? .accentColor : .secondary)
                                    }
                                } else {
                                    Menu {
                                        Button("All") {
                                            // Switch to "All" tasks view
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                        }
                                        Divider()
                                        Button("Has Due Date") {
                                            // Switch to All view with Has Due Date filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.hasDueDate)
                                        }
                                        Button("No Due Date") {
                                            // Switch to All view with No Due Date filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.noDueDate)
                                        }
                                        Button("Overdue") {
                                            // Switch to All view with Past Due filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.pastDue)
                                        }
                                        Button("Complete") {
                                            // Switch to All view with Complete filter
                                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                                            NotificationCenter.default.post(name: Notification.Name("SetAllTasksSubfilter"), object: AllTaskSubfilter.completed)
                                            // Turn off hide completed setting to show completed tasks
                                            appPrefs.updateHideCompletedTasks(false)
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(adaptiveIconSize)
                                            .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                            .foregroundColor(navigationManager.showingAllTasks ? .accentColor : .secondary)
                                    }
                                }
                            }
                            
                            // Hide vertical separator in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                Text("|")
                                    .font(adaptiveIconSize)
                            }
                            Button {
                                // Comprehensive data reload
                                Task {
                                    await reloadAllData()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(adaptiveIconSize)
                                    .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                            }
                            
                            // Hide completed tasks toggle (in Tasks, Lists, Calendar day/week views, and Timebox view)
                            if navigationManager.currentView == .tasks || navigationManager.currentView == .lists || 
                               (navigationManager.currentView == .calendar && (navigationManager.currentInterval == .day || navigationManager.currentInterval == .week)) ||
                               navigationManager.currentView == .timebox {
                                Button {
                                    appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks)
                                } label: {
                                    Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash" : "eye")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                            }

                            // Bulk edit toggle (in Calendar day view)
                            if navigationManager.currentView == .calendar && navigationManager.currentInterval == .day {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleCalendarBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle (in Calendar week view)
                            if navigationManager.currentView == .calendar && navigationManager.currentInterval == .week {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleWeeklyCalendarBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle (in Tasks view)
                            if navigationManager.currentView == .tasks {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleTasksBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bulk edit toggle (in Lists view)
                            if navigationManager.currentView == .lists {
                                Button {
                                    NotificationCenter.default.post(name: Notification.Name("ToggleListsBulkEdit"), object: nil)
                                } label: {
                                    Image(systemName: "checkmark.rectangle.stack")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            // + menu based on current view
                            if navigationManager.currentView == .journalDayViews {
                                // In Journal Day Views: menu with Event and Task only
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else if navigationManager.currentView == .lists {
                                // In Lists view: menu with Event, Task, and List
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                    Button("List") {
                                        showingAddList = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else if navigationManager.currentView == .goals {
                                // In Goals view: menu with Event, Task, and Goal
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                    Button("Goal") {
                                        NotificationCenter.default.post(name: Notification.Name("ShowAddGoal"), object: nil)
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            } else {
                                // In other views: menu with Event and Task only
                                Menu {
                                    Button("Event") {
                                        showingAddEvent = true
                                    }
                                    Button("Task") {
                                        showingAddTask = true
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(adaptiveIconSize)
                                        .frame(minWidth: adaptiveButtonSize, minHeight: adaptiveButtonSize)
                                }
                            }
                        }
                        .padding(.horizontal, max(adaptivePadding + horizontalSafeInset, 4))
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                    }
                }
                .frame(height: shouldShowTwoRows ? 100 : 50)
            }
        }
        .frame(height: shouldShowTwoRows ? 100 : 50)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingReportIssues) {
            ReportIssuesView()
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDateForPicker,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.calendar, Calendar.mondayFirst)
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading: Button("Cancel") { showingDatePicker = false },
                    trailing: Button("Done") {
                        // Navigate based on current view context
                        if navigationManager.showTasksView && navigationManager.showingAllTasks {
                            // If in Tasks view filtered to ALL, go to yearly view
                            navigationManager.updateInterval(.year, date: selectedDateForPicker)
                        } else {
                            // Otherwise, respect current interval but use selected date
                            navigationManager.updateInterval(navigationManager.currentInterval, date: selectedDateForPicker)
                        }
                        showingDatePicker = false
                    }
                )
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingAddEvent) {
            NavigationStack {
                AddItemView(
                    currentDate: navigationManager.currentDate,
                    tasksViewModel: tasksVM,
                    calendarViewModel: calendarVM,
                    appPrefs: appPrefs,
                    showEventOnly: true
                )
            }
        }
        .sheet(isPresented: $showingAddTask) {
            let personalLinked = auth.isLinked(kind: .personal)
            let defaultAccount: GoogleAuthManager.AccountKind = personalLinked ? .personal : .professional
            let defaultLists = defaultAccount == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
            let defaultListId = defaultLists.first?.id ?? ""
            let newTask = GoogleTask(
                id: UUID().uuidString,
                title: "",
                notes: nil,
                status: "needsAction",
                due: nil,
                completed: nil,
                updated: nil,
                position: "0"
            )
            
            NavigationStack {
                TaskDetailsView(
                    task: newTask,
                    taskListId: defaultListId,
                    accountKind: defaultAccount,
                    accentColor: defaultAccount == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    personalTaskLists: tasksVM.personalTaskLists,
                    professionalTaskLists: tasksVM.professionalTaskLists,
                    appPrefs: appPrefs,
                    viewModel: tasksVM,
                    onSave: { updatedTask in
                        Task {
                            await tasksVM.updateTask(updatedTask, in: defaultListId, for: defaultAccount)
                        }
                    },
                    onDelete: {
                        // No-op for new task creation
                    },
                    onMove: { updatedTask, targetListId in
                        Task {
                            await tasksVM.moveTask(updatedTask, from: defaultListId, to: targetListId, for: defaultAccount)
                        }
                    },
                    onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                        Task {
                            await tasksVM.crossAccountMoveTask(updatedTask, from: (defaultAccount, defaultListId), to: (targetAccount, targetListId))
                        }
                    },
                    isNew: true
                )
            }
        }
        .sheet(isPresented: $showingAddList) {
            NewListSheet(
                appPrefs: appPrefs,
                accountKind: newListAccountKind,
                hasPersonal: auth.isLinked(kind: .personal),
                hasProfessional: auth.isLinked(kind: .professional),
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                listName: $newListName,
                selectedAccount: $newListAccountKind,
                onCreate: {
                    createNewList()
                }
            )
            .onAppear {
                // Reset state when sheet appears
                newListName = ""
                newListAccountKind = nil
            }
        }
        .sheet(isPresented: $showingAddLog) {
            AddLogEntryView(viewModel: logsVM)
        }
        .alert("Sync Complete", isPresented: $showingSyncAlert) {
            Button("OK") {
                showingSyncAlert = false
            }
        } message: {
            Text(syncedDataMessage)
        }
    }
    
    // MARK: - Create New List Function
    private func createNewList() {
        guard let accountKind = newListAccountKind else { return }
        
        Task {
            let _ = await tasksVM.createTaskList(title: newListName.trimmingCharacters(in: .whitespacesAndNewlines), for: accountKind)
            await MainActor.run {
                showingAddList = false
                newListName = ""
                newListAccountKind = nil
            }
        }
    }
    
    // MARK: - Data Reload Functions
    private func reloadAllData() async {
        // FIRST: Force iCloud/CloudKit sync to push/pull changes
        iCloudManager.shared.forceCompleteSync()

        // Wait for CloudKit to sync
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        let currentDate = navigationManager.currentDate

        // Track synced data counts
        var syncedItems: [String] = []

        // Reload goals data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        let beforeGoals = DataManager.shared.goalsManager.goals.count
        DataManager.shared.goalsManager.refreshData()
        let afterGoals = DataManager.shared.goalsManager.goals.count
        if afterGoals > 0 {
            syncedItems.append("\(afterGoals) goal\(afterGoals == 1 ? "" : "s")")
        }

        // Reload custom logs data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        DataManager.shared.customLogManager.refreshData()

        // Wait for CloudKit to propagate
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // NOW reload all data from Core Data
        // Reload task time windows
        let timeWindowCount = await MainActor.run { () -> Int in
            let beforeCount = TaskTimeWindowManager.shared.timeWindows.count
            TaskTimeWindowManager.shared.loadTimeWindows()
            let afterCount = TaskTimeWindowManager.shared.timeWindows.count
            if afterCount != beforeCount {
                devLog("✅ GlobalNavBar: Task time windows changed (\(beforeCount) → \(afterCount))")
            }
            return afterCount
        }
        if timeWindowCount > 0 {
            syncedItems.append("\(timeWindowCount) task time window\(timeWindowCount == 1 ? "" : "s")")
        }

        // Reload calendar events based on current interval
        switch navigationManager.currentInterval {
        case .day:
            await calendarVM.loadCalendarData(for: currentDate)
        case .week:
            await calendarVM.loadCalendarDataForWeek(containing: currentDate)
        case .month:
            await calendarVM.loadCalendarDataForMonth(containing: currentDate)
        case .year:
            // For year view, load month data for the specific month
            await calendarVM.loadCalendarDataForMonth(containing: currentDate)
        }

        // Count calendar events
        let personalEventCount = calendarVM.personalEvents.count
        let professionalEventCount = calendarVM.professionalEvents.count
        let totalEvents = personalEventCount + professionalEventCount
        if totalEvents > 0 {
            syncedItems.append("\(totalEvents) calendar event\(totalEvents == 1 ? "" : "s")")
        }

        // Reload tasks with forced cache clear
        await tasksVM.loadTasks(forceClear: true)

        // Count tasks
        let personalTaskCount = tasksVM.personalTasks.values.flatMap { $0 }.count
        let professionalTaskCount = tasksVM.professionalTasks.values.flatMap { $0 }.count
        let totalTasks = personalTaskCount + professionalTaskCount
        if totalTasks > 0 {
            syncedItems.append("\(totalTasks) task\(totalTasks == 1 ? "" : "s")")
        }

        // Reload logs data
        LogsViewModel.shared.reloadData()

        // Count logs
        let weightCount = logsVM.weightEntries.count
        let workoutCount = logsVM.workoutEntries.count
        let foodCount = logsVM.foodEntries.count
        let waterCount = logsVM.waterEntries.count
        let sleepCount = logsVM.sleepEntries.count
        let totalLogs = weightCount + workoutCount + foodCount + waterCount + sleepCount
        if totalLogs > 0 {
            syncedItems.append("\(totalLogs) log entr\(totalLogs == 1 ? "y" : "ies")")
        }

        // Refresh view context
        await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            context.refreshAllObjects()
        }

        // Post notification to refresh journal content
        NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)

        // Update last sync time
        iCloudManager.shared.lastSyncDate = Date()

        // Build sync message
        await MainActor.run {
            if syncedItems.isEmpty {
                syncedDataMessage = "No data synced"
            } else {
                syncedDataMessage = "Synced:\n" + syncedItems.joined(separator: "\n")
            }
            showingSyncAlert = true
        }
    }

    private func reloadAllDataForDate(_ date: Date) async {
        // FIRST: Force iCloud/CloudKit sync to push/pull changes
        iCloudManager.shared.forceCompleteSync()

        // Wait for CloudKit to sync
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Reload goals data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        DataManager.shared.goalsManager.refreshData()

        // Reload custom logs data (forceSync removed - NSPersistentCloudKitContainer handles sync)
        DataManager.shared.customLogManager.refreshData()

        // Wait for CloudKit to propagate
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // NOW reload all data from Core Data
        // Reload task time windows
        await MainActor.run {
            let beforeCount = TaskTimeWindowManager.shared.timeWindows.count
            TaskTimeWindowManager.shared.loadTimeWindows()
            let afterCount = TaskTimeWindowManager.shared.timeWindows.count
            if afterCount != beforeCount {
                devLog("✅ GlobalNavBar: Task time windows changed (\(beforeCount) → \(afterCount))")
            }
        }
        
        // Reload calendar events based on current interval
        switch navigationManager.currentInterval {
        case .day:
            await calendarVM.loadCalendarData(for: date)
        case .week:
            await calendarVM.loadCalendarDataForWeek(containing: date)
        case .month:
            await calendarVM.loadCalendarDataForMonth(containing: date)
        case .year:
            // For year view, load month data for the specific month
            await calendarVM.loadCalendarDataForMonth(containing: date)
        }
        
        // Reload tasks with forced cache clear
        await tasksVM.loadTasks(forceClear: true)
        
        // Reload logs data
        LogsViewModel.shared.reloadData()
        
        // Refresh view context
        await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            context.refreshAllObjects()
        }
        
        // Post notification to refresh journal content
        NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
        
        // Update last sync time
        iCloudManager.shared.lastSyncDate = Date()
        
        devLog("✅ NAV BAR SYNC (for date): Completed successfully!")
    }
    
}


#Preview {
    GlobalNavBar()
}
