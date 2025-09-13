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
    
    // Date picker state
    @State private var selectedDateForPicker = Date()
    
    private var dateLabel: String {
        switch navigationManager.currentInterval {
        case .year:
            return String(Calendar.current.component(.year, from: navigationManager.currentDate))
        case .month:
            let formatter = DateFormatter.standardMonthYear
            return formatter.string(from: navigationManager.currentDate)
        case .week:
            let cal = Calendar.mondayFirst
            guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
                return ""
            }
            let start = weekInterval.start
            let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
            
            let monthFormatter = DateFormatter.standardMonth
            let dayFormatter = DateFormatter.standardDay
            
            if cal.isDate(start, equalTo: end, toGranularity: .month) {
                // Same month: "September 11-17"
                return "\(monthFormatter.string(from: start)) \(dayFormatter.string(from: start))-\(dayFormatter.string(from: end))"
            } else {
                // Different months: "Sep 30-Oct 6"
                let shortMonthFormatter = DateFormatter.standardShortMonth
                return "\(shortMonthFormatter.string(from: start)) \(dayFormatter.string(from: start))-\(shortMonthFormatter.string(from: end)) \(dayFormatter.string(from: end))"
            }
        case .day:
            let formatter = DateFormatter.standardMonthDay
            return formatter.string(from: navigationManager.currentDate)
        }
    }
    
    private func step(_ direction: Int) {
        let cal = Calendar.mondayFirst
        let component = navigationManager.currentInterval.calendarComponent
        if let newDate = cal.date(byAdding: component, value: direction, to: navigationManager.currentDate) {
            navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
        }
    }
    
    var body: some View {
        VStack() {
            GeometryReader { geo in
                let isNarrow = geo.size.width < 450
                VStack(alignment: .leading) {
                    HStack() {
                        Menu {
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
                                .font(.body)
                                .frame(width: 20, height: 20)
                                .foregroundColor(.secondary)
                        }
                        // Quick nav to Tasks view
                        Button {
                            navigationManager.switchToTasks()
                            NotificationCenter.default.post(name: Notification.Name("ShowAllTasksRequested"), object: nil)
                        } label: {
                            Image(systemName: "checklist")
                        }
                        // Quick nav to Calendar Day view
                        Button {
                            navigationManager.switchToCalendar()
                            navigationManager.updateInterval(.day, date: Date())
                        } label: {
                            Image(systemName: "calendar")
                        }
                        
                        
                        Button { step(-1) } label: {
                            Image(systemName: "chevron.left")
                        }
                        Button {
                            selectedDateForPicker = navigationManager.currentDate
                            showingDatePicker = true
                        } label: {
                            Text(dateLabel)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Button { step(1) } label: {
                            Image(systemName: "chevron.right")
                        }
                        
                        if !isNarrow {
                            Spacer()
                            Button {
                                navigationManager.updateInterval(.day, date: navigationManager.currentDate)
                            } label: {
                                Image(systemName: "d.circle")
                                    .foregroundColor(navigationManager.currentInterval == .day ? .accentColor : .secondary)
                            }
                            Button {
                                navigationManager.updateInterval(.week, date: navigationManager.currentDate)
                            } label: {
                                Image(systemName: "w.circle")
                                    .foregroundColor(navigationManager.currentInterval == .week ? .accentColor : .secondary)
                            }
                            Button {
                                navigationManager.updateInterval(.month, date: navigationManager.currentDate)
                            } label: {
                                Image(systemName: "m.circle")
                                    .foregroundColor(navigationManager.currentInterval == .month ? .accentColor : .secondary)
                            }
                            Button {
                                navigationManager.updateInterval(.year, date: navigationManager.currentDate)
                            } label: {
                                Image(systemName: "y.circle")
                                    .foregroundColor(navigationManager.currentInterval == .year ? .accentColor : .secondary)
                            }
                            Button {
                                navigationManager.updateInterval(.year, date: navigationManager.currentDate)
                            } label: {
                                Image(systemName: "a.circle")
                                    .foregroundColor(navigationManager.currentInterval == .year ? .accentColor : .secondary)
                            }
                            Menu {
                                Button("Has Due Date") {
                                    //code
                                }
                                Button("No Due Date") {
                                    //code
                                }
                                Button("Overd") {
                                    //code
                                }
                                Button("Complete") {
                                    //code
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            
                            Text("|")
                            Button {
                                appPrefs.hideCompletedTasks.toggle()
                            } label: {
                                Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash.circle" : "eye.circle")
                            }
                            Button {
                                //code
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            Button {
                                let calVM = calendarVM
                                let tVM = tasksVM
                                let date = navigationManager.currentDate
                                Task {
                                    await calVM.preloadMonthIntoCache(containing: date)
                                    await tVM.loadTasks()
                                }
                            } label: {
                                Image(systemName: "arrow.trianglepath")
                            }
                            Menu {
                                Button("Event") {
                                    showingAddEvent = true
                                }
                                Button("Task") {
                                    showingAddTask = true
                                }
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                    
                    
                    
                    if isNarrow {
                        HStack{
                            
                            Button {
                                navigationManager.updateInterval(.day, date: navigationManager.currentDate)
                            } label: {
                                Image(systemName: "d.circle")
                                    .foregroundColor(navigationManager.currentInterval == .day ? .accentColor : .secondary)
                            }
                            Button {
                                navigationManager.updateInterval(.week, date: navigationManager.currentDate)
                            } label: {
                                Image(systemName: "w.circle")
                                    .foregroundColor(navigationManager.currentInterval == .week ? .accentColor : .secondary)
                            }
                            Button {
                                navigationManager.updateInterval(.month, date: navigationManager.currentDate)
                            } label: {
                                Image(systemName: "m.circle")
                                    .foregroundColor(navigationManager.currentInterval == .month ? .accentColor : .secondary)
                            }
                            Button {
                                navigationManager.updateInterval(.year, date: navigationManager.currentDate)
                            } label: {
                                Image(systemName: "y.circle")
                                    .foregroundColor(navigationManager.currentInterval == .year ? .accentColor : .secondary)
                            }
                            Button {
                                navigationManager.updateInterval(.year, date: navigationManager.currentDate)
                            } label: {
                                Image(systemName: "a.circle")
                                    .foregroundColor(navigationManager.currentInterval == .year ? .accentColor : .secondary)
                            }
                            Menu {
                                Button("Has Due Date") {
                                    //code
                                }
                                Button("No Due Date") {
                                    //code
                                }
                                Button("Overd") {
                                    //code
                                }
                                Button("Complete") {
                                    //code
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            
                            Text("|")
                            Button {
                                appPrefs.hideCompletedTasks.toggle()
                            } label: {
                                Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash.circle" : "eye.circle")
                            }
                            Button {
                                //code
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            Button {
                                let calVM = calendarVM
                                let tVM = tasksVM
                                let date = navigationManager.currentDate
                                Task {
                                    await calVM.preloadMonthIntoCache(containing: date)
                                    await tVM.loadTasks()
                                }
                            } label: {
                                Image(systemName: "arrow.trianglepath")
                            }
                            Menu {
                                Button("Event") {
                                    showingAddEvent = true
                                }
                                Button("Task") {
                                    showingAddTask = true
                                }
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                    
                }.padding()
            }
            .frame(height: 84)
            
        }
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
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading: Button("Cancel") { showingDatePicker = false },
                    trailing: Button("Done") {
                        navigationManager.updateInterval(navigationManager.currentInterval, date: selectedDateForPicker)
                        showingDatePicker = false
                    }
                )
            }
            .presentationDetents([.medium])
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
    }
    
}


#Preview {
    GlobalNavBar()
}
