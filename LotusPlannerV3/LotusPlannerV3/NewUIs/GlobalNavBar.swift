import SwiftUI

struct GlobalNavBar: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var calendarVM = DataManager.shared.calendarViewModel
    @ObservedObject private var auth = GoogleAuthManager.shared
    
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
    @State private var showingAddGoal = false
    @State private var showingAddCategory = false
    
    // Date picker state
    @State private var selectedDateForPicker = Date()
    
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
                
                // Get week number
                let weekNumber = Calendar.mondayFirst.component(.weekOfYear, from: start)
                
                // Format dates as M/d/yy
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "M/d/yy"
                let startString = dateFormatter.string(from: start)
                let endString = dateFormatter.string(from: end)
                
                return "Week\(weekNumber): \(startString) - \(endString)"
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
            
            // Format dates as M/d/yy
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/d/yy"
            let startString = dateFormatter.string(from: start)
            let endString = dateFormatter.string(from: end)
            
            return "Week\(weekNumber): \(startString) - \(endString)"
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
            // In Goals view: just update the interval to filter goals
            navigationManager.updateInterval(interval, date: Date())
        } else if navigationManager.showTasksView {
            // In Tasks view: filter to the interval
            navigationManager.showingAllTasks = false
            navigationManager.updateInterval(interval, date: Date())
        } else {
            // In Calendar view: go to the interval
            navigationManager.showingAllTasks = false
            if interval == .year {
                navigationManager.updateInterval(interval, date: Date())
                navigationManager.switchToYearlyCalendar()
            } else {
                navigationManager.switchToCalendar()
                navigationManager.updateInterval(interval, date: Date())
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
            print("🔄 GlobalNavBar: Step called for journalDayViews, direction: \(direction)")
            let component = navigationManager.currentInterval.calendarComponent
            if let newDate = Calendar.mondayFirst.date(byAdding: component, value: direction, to: navigationManager.currentDate) {
                print("🔄 GlobalNavBar: Updating date from \(navigationManager.currentDate) to \(newDate)")
                // Update the navigation manager
                navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
                
                // Post notification for journal content refresh
                NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
                print("🔄 GlobalNavBar: Posted RefreshJournalContent notification")
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
        VStack(spacing: 0) {
            GeometryReader { geo in
                let isNarrow = geo.size.width < 450
                VStack(alignment: .leading) {
                    HStack() {
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
                                    Label("Goals", systemImage: "target")
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
                                .font(.title2)
                                .frame(width: 25, height: 25)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .padding(.trailing, 10)
                        
                        // Hide navigation arrows in Lists view and in Goals All Goals view
                        if navigationManager.currentView != .lists && !(navigationManager.currentView == .goals && navigationManager.currentInterval == .day) {
                            Button { step(-1) } label: {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                            }
                            .padding(.trailing, 15)
                        }
                        
                        Button {
                            // Only open date picker if not in Lists view or Goals All Goals view
                            if navigationManager.currentView != .lists && !(navigationManager.currentView == .goals && navigationManager.currentInterval == .day) {
                                selectedDateForPicker = navigationManager.currentDate
                                showingDatePicker = true
                            }
                        } label: {
                            Text(dateLabel)
                                .font(.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundColor(navigationManager.currentView == .lists || (navigationManager.showTasksView && navigationManager.showingAllTasks) ? .primary : (isCurrentPeriod ? DateDisplayStyle.currentPeriodColor : .primary))
                        }
                        .disabled(navigationManager.currentView == .lists || (navigationManager.currentView == .goals && navigationManager.currentInterval == .day))
                        .padding(.trailing, 15)
                        
                        // Hide navigation arrows in Lists view and in Goals All Goals view
                        if navigationManager.currentView != .lists && !(navigationManager.currentView == .goals && navigationManager.currentInterval == .day) {
                            Button { step(1) } label: {
                                Image(systemName: "chevron.right")
                                    .font(.title2)
                            }
                        }
                        
                        if !isNarrow {
                        Spacer()
                            // Hide navigation buttons in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                // Only show d.circle in non-Goals views
                                if navigationManager.currentView != .goals {
                                    Button {
                                        if navigationManager.showTasksView {
                                            // In Tasks view: filter to current day
                                            navigationManager.showingAllTasks = false
                                            navigationManager.updateInterval(.day, date: Date())
                                        } else {
                                            // In Calendar view: go to current day
                                            navigationManager.showingAllTasks = false
                                            navigationManager.switchToCalendar()
                                            navigationManager.updateInterval(.day, date: Date())
                                        }
                                    } label: {
                                        Image(systemName: "d.circle")
                                            .font(.title2)
                                            .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .day ? .accentColor : .secondary)))
                                    }
                                }
                                Button {
                                    handleTimeIntervalChange(.week)
                                } label: {
                                    Image(systemName: "w.circle")
                                        .font(.title2)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .week ? .accentColor : .secondary)))
                                }
                                Button {
                                    handleTimeIntervalChange(.month)
                                } label: {
                                    Image(systemName: "m.circle")
                                        .font(.title2)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .month ? .accentColor : .secondary)))
                                }
                                Button {
                                    handleTimeIntervalChange(.year)
                                } label: {
                                    Image(systemName: "y.circle")
                                        .font(.title2)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .accentColor : (navigationManager.currentInterval == .year ? .accentColor : .secondary)))
                                }
                            }
                            
                            
                            // Hide ellipsis.circle in calendar views, lists view, and journal day views
                            if navigationManager.currentView != .calendar && navigationManager.currentView != .yearlyCalendar && navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                if navigationManager.currentView == .goals {
                                    // In Goals view: button to show all goals
                                    Button {
                                        navigationManager.updateInterval(.day, date: Date())
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title2)
                                            .foregroundColor(navigationManager.currentInterval == .day ? .accentColor : .secondary)
                                    }
                                } else {
                                    // In Tasks view: full menu
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
                                            .font(.title2)
                                            .foregroundColor(navigationManager.showingAllTasks ? .accentColor : .secondary)
                                    }
                                }
                            }
                            
                            // Hide vertical separator in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                Text("|")
                                    .font(.title2)
                            }
                            Button {
                                // Comprehensive data reload
                                Task {
                                    await reloadAllData()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                            }
                            
                            // Hide completed tasks toggle (in Tasks, Calendar, and Lists views)
                            if navigationManager.currentView == .tasks || navigationManager.currentView == .calendar || navigationManager.currentView == .lists {
                                Button {
                                    appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks)
                                } label: {
                                    Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash" : "eye")
                                        .font(.title2)
                                }
                            }
                            
                            // Hide all icons to the right of > when in journalDayViews
                            if navigationManager.currentView != .journalDayViews {
                                if navigationManager.currentView == .goals {
                                    // In Goals view: menu with all options
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
                                        Button("Goal") {
                                            NotificationCenter.default.post(name: Notification.Name("ShowAddGoal"), object: nil)
                                        }
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.title2)
                                    }
                                } else {
                                    // In other views: menu with multiple options
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
                                            .font(.title2)
                                    }
                                }
                            }
                        }
                    }
                    
                    
                    
                    if isNarrow {
                        HStack{
                            // Hide navigation buttons in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                // Only show d.circle in non-Goals views
                                if navigationManager.currentView != .goals {
                                    Button {
                                        if navigationManager.showTasksView {
                                            // In Tasks view: filter to current day
                                            navigationManager.showingAllTasks = false
                                            navigationManager.updateInterval(.day, date: Date())
                                        } else {
                                            // In Calendar view: go to current day
                                            navigationManager.showingAllTasks = false
                                            navigationManager.switchToCalendar()
                                            navigationManager.updateInterval(.day, date: Date())
                                        }
                                    } label: {
                                        Image(systemName: "d.circle")
                                            .font(.title2)
                                            .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .day ? .accentColor : .secondary)))
                                    }
                                }
                                Button {
                                    handleTimeIntervalChange(.week)
                                } label: {
                                    Image(systemName: "w.circle")
                                        .font(.title2)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .week ? .accentColor : .secondary)))
                                }
                                Button {
                                    handleTimeIntervalChange(.month)
                                } label: {
                                    Image(systemName: "m.circle")
                                        .font(.title2)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .secondary : (navigationManager.currentInterval == .month ? .accentColor : .secondary)))
                                }
                                Button {
                                    handleTimeIntervalChange(.year)
                                } label: {
                                    Image(systemName: "y.circle")
                                        .font(.title2)
                                        .foregroundColor(navigationManager.showingAllTasks ? .secondary : (navigationManager.currentView == .yearlyCalendar ? .accentColor : (navigationManager.currentInterval == .year ? .accentColor : .secondary)))
                                }
                            }
                            
                            
                            // Hide ellipsis.circle in calendar views, lists view, and journal day views
                            if navigationManager.currentView != .calendar && navigationManager.currentView != .yearlyCalendar && navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                if navigationManager.currentView == .goals {
                                    // In Goals view: button to show all goals
                                    Button {
                                        navigationManager.updateInterval(.day, date: Date())
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title2)
                                            .foregroundColor(navigationManager.currentInterval == .day ? .accentColor : .secondary)
                                    }
                                } else {
                                    // In Tasks view: full menu
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
                                            .font(.title2)
                                            .foregroundColor(navigationManager.showingAllTasks ? .accentColor : .secondary)
                                    }
                                }
                            }
                            
                            // Hide vertical separator in Lists view and Journal Day Views
                            if navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews {
                                Text("|")
                                    .font(.title2)
                            }
                            Button {
                                // Comprehensive data reload
                                Task {
                                    await reloadAllData()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                            }
                            
                            // Hide completed tasks toggle (in Tasks, Calendar, and Lists views)
                            if navigationManager.currentView == .tasks || navigationManager.currentView == .calendar || navigationManager.currentView == .lists {
                                Button {
                                    appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks)
                                } label: {
                                    Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash" : "eye")
                                        .font(.title2)
                                }
                            }
                            
                            // Hide all icons to the right of > when in journalDayViews
                            if navigationManager.currentView != .journalDayViews {
                                if navigationManager.currentView == .goals {
                                    // In Goals view: menu with all options
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
                                        Button("Goal") {
                                            NotificationCenter.default.post(name: Notification.Name("ShowAddGoal"), object: nil)
                                        }
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.title2)
                                    }
                                } else {
                                    // In other views: menu with multiple options
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
                                            .font(.title2)
                                    }
                                }
                            }
                        }
                    }
                    
                }.padding()
            }
        }
        .frame(height: UIScreen.main.bounds.width < 450 ? 100 : 50)
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
            .presentationDetents([.height(UIScreen.main.bounds.height * 0.5 + 30)])
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
                    onSave: { _ in },
                    onDelete: {},
                    onMove: { _, _ in },
                    onCrossAccountMove: { _, _, _ in },
                    isNew: true
                )
            }
        }
        .sheet(isPresented: $showingAddList) {
            NewListSheet(
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
    }
    
    // MARK: - Create New List Function
    private func createNewList() {
        guard let accountKind = newListAccountKind else { return }
        
        Task {
            await tasksVM.createTaskList(title: newListName.trimmingCharacters(in: .whitespacesAndNewlines), for: accountKind)
            await MainActor.run {
                showingAddList = false
                newListName = ""
                newListAccountKind = nil
            }
        }
    }
    
    // MARK: - Data Reload Functions
    private func reloadAllData() async {
        let currentDate = navigationManager.currentDate
        
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
        
        // Reload tasks with forced cache clear
        await tasksVM.loadTasks(forceClear: true)
        
        // Reload goals data
        await DataManager.shared.goalsManager.forceSync()
        
        // Reload custom logs data
        await DataManager.shared.customLogManager.forceSync()
        
        // Reload logs data
        LogsViewModel.shared.reloadData()
        
        // Post notification to refresh journal content
        NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
    }
    
    private func reloadAllDataForDate(_ date: Date) async {
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
        
        // Reload goals data
        await DataManager.shared.goalsManager.forceSync()
        
        // Reload custom logs data
        await DataManager.shared.customLogManager.forceSync()
        
        // Reload logs data
        LogsViewModel.shared.reloadData()
        
        // Post notification to refresh journal content
        NotificationCenter.default.post(name: Notification.Name("RefreshJournalContent"), object: nil)
    }
    
}


#Preview {
    GlobalNavBar()
}
