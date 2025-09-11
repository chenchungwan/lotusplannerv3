import SwiftUI

struct GWeekView: View {
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    
    @State private var currentDate: Date = Date()
    @State private var showingDatePicker = false
    @State private var selectedDateForPicker = Date()

    struct GWeekTaskSelection: Identifiable {
        let id = UUID()
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    @State private var taskSheetSelection: GWeekTaskSelection?

    @State private var selectedEvent: GoogleCalendarEvent?

    private let calendar = Calendar.mondayFirst
    
    var body: some View {
        mainContent
            .sidebarToggleHidden()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    principalToolbarContent
                }
                ToolbarItemGroup(placement: .principal) { EmptyView() }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    trailingToolbarButtons
                }
            }
            .task {
            currentDate = navigationManager.currentDate
            await calendarViewModel.loadCalendarDataForWeek(containing: currentDate)
        }
        .onChange(of: navigationManager.currentDate) { _, newValue in
            currentDate = newValue
            Task { await calendarViewModel.loadCalendarDataForWeek(containing: newValue) }
        }
        .sheet(item: $taskSheetSelection) { sel in
            TaskDetailsView(
                task: sel.task,
                taskListId: sel.listId,
                accountKind: sel.accountKind,
                accentColor: sel.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { updatedTask in
                    Task {
                        await tasksViewModel.updateTask(updatedTask, in: sel.listId, for: sel.accountKind)
                    }
                },
                onDelete: {
                    Task {
                        await tasksViewModel.deleteTask(sel.task, from: sel.listId, for: sel.accountKind)
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksViewModel.moveTask(updatedTask, from: sel.listId, to: targetListId, for: sel.accountKind)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksViewModel.crossAccountMoveTask(updatedTask, from: (sel.accountKind, sel.listId), to: (targetAccountKind, targetListId))
                    }
                }
            )
        }
    }
    
    private var mainContent: some View {
        HStack(spacing: 8) {
            // Left: Weekly calendar timeline (events)
            WeekTimelineComponent(
                currentDate: currentDate,
                weekEvents: weekEventsDict,
                personalEvents: calendarViewModel.personalEvents,
                professionalEvents: calendarViewModel.professionalEvents,
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                personalTasks: weekPersonalTasks,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                professionalTasks: weekProfessionalTasks,
                hideCompletedTasks: appPrefs.hideCompletedTasks,
                onEventTap: { event in
                    // Navigate to day view with the event's date
                    let eventDate = Calendar.current.startOfDay(for: event.startTime ?? Date())
                    navigationManager.switchToCalendar()
                    navigationManager.updateInterval(.day, date: eventDate)
                },
                onDayTap: { date in
                    navigationManager.switchToCalendar()
                    navigationManager.updateInterval(.day, date: date)
                },
                onTaskTap: { task, listId in
                    // Determine account kind based on task list
                    let accountKind: GoogleAuthManager.AccountKind
                    if tasksViewModel.personalTaskLists.contains(where: { $0.id == listId }) {
                        accountKind = .personal
                    } else {
                        accountKind = .professional
                    }
                    taskSheetSelection = GWeekTaskSelection(task: task, listId: listId, accountKind: accountKind)
                },
                showTasksSection: false,
                fixedStartHour: 8
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right: Weekly tasks (personal + professional)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Personal tasks
                    if authManager.isLinked(kind: GoogleAuthManager.AccountKind.personal) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Personal Tasks")
                                .font(.headline)
                                .padding(.horizontal, 4)
                            TasksComponent(
                                taskLists: tasksViewModel.personalTaskLists,
                                tasksDict: weekPersonalTasks,
                                accentColor: appPrefs.personalColor,
                                accountType: GoogleAuthManager.AccountKind.personal,
                                onTaskToggle: { task, listId in
                                    Task {
                                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: GoogleAuthManager.AccountKind.personal)
                                    }
                                },
                                onTaskDetails: { task, listId in
                                    taskSheetSelection = GWeekTaskSelection(task: task, listId: listId, accountKind: .personal)
                                },
                                onListRename: { listId, newName in
                                    Task { await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: GoogleAuthManager.AccountKind.personal) }
                                },
                                onOrderChanged: { newOrder in
                                    Task { await tasksViewModel.updateTaskListOrder(newOrder, for: GoogleAuthManager.AccountKind.personal) }
                                },
                                hideDueDateTag: false,
                                showEmptyState: true,
                                horizontalCards: false
                            )
                        }
                    }

                    // Professional tasks
                    if authManager.isLinked(kind: GoogleAuthManager.AccountKind.professional) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Professional Tasks")
                                .font(.headline)
                                .padding(.horizontal, 4)
                            TasksComponent(
                                taskLists: tasksViewModel.professionalTaskLists,
                                tasksDict: weekProfessionalTasks,
                                accentColor: appPrefs.professionalColor,
                                accountType: GoogleAuthManager.AccountKind.professional,
                                onTaskToggle: { task, listId in
                                    Task {
                                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: GoogleAuthManager.AccountKind.professional)
                                    }
                                },
                                onTaskDetails: { task, listId in
                                    taskSheetSelection = GWeekTaskSelection(task: task, listId: listId, accountKind: .professional)
                                },
                                onListRename: { listId, newName in
                                    Task { await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: GoogleAuthManager.AccountKind.professional) }
                                },
                                onOrderChanged: { newOrder in
                                    Task { await tasksViewModel.updateTaskListOrder(newOrder, for: GoogleAuthManager.AccountKind.professional) }
                                },
                                hideDueDateTag: false,
                                showEmptyState: true,
                                horizontalCards: false
                            )
                        }
                    }
                }
                .padding(8)
            }
            .frame(width: min(UIScreen.main.bounds.width * 0.4, 420))
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 8)
    }
    
    private var weekTitle: String {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start,
              let end = calendar.date(byAdding: .day, value: 6, to: start) else { return "Week" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        let startStr = df.string(from: start)
        let endStr = df.string(from: end)
        df.dateFormat = "yyyy"
        let yearStr = df.string(from: start)
        return "\(startStr) – \(endStr), \(yearStr)"
    }
    
    private var weekDates: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    
    private var weekEventsDict: [Date: [GoogleCalendarEvent]] {
        let allEvents = calendarViewModel.personalEvents + calendarViewModel.professionalEvents
        var dict: [Date: [GoogleCalendarEvent]] = [:]
        for date in weekDates {
            let dayStart = calendar.startOfDay(for: date)
            dict[dayStart] = allEvents.filter { ev in
                guard let st = ev.startTime else { return false }
                return calendar.isDate(st, inSameDayAs: date)
            }
        }
        return dict
    }

    private var weekInterval: DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: currentDate)
    }

    private func tasksForWeek(from tasksDict: [String: [GoogleTask]]) -> [String: [GoogleTask]] {
        guard let interval = weekInterval else { return [:] }
        var result: [String: [GoogleTask]] = [:]
        for (listId, tasks) in tasksDict {
            let filtered = tasks.filter { task in
                if task.isCompleted, let completion = task.completionDate {
                    return interval.contains(completion)
                }
                if let due = task.dueDate {
                    // Include tasks due within the week or overdue as of week end
                    return interval.contains(due) || due < interval.end
                }
                return false
            }
            if !filtered.isEmpty {
                result[listId] = filtered
            }
        }
        return result
    }

    private var weekPersonalTasks: [String: [GoogleTask]] {
        tasksForWeek(from: tasksViewModel.personalTasks)
    }

    private var weekProfessionalTasks: [String: [GoogleTask]] {
        tasksForWeek(from: tasksViewModel.professionalTasks)
    }
    
    private func step(_ dir: Int) {
        if let newDate = calendar.date(byAdding: .weekOfYear, value: dir, to: currentDate) {
            currentDate = newDate
            navigationManager.updateInterval(.week, date: newDate)
            Task { await calendarViewModel.loadCalendarDataForWeek(containing: newDate) }
        }
    }

    // MARK: - Toolbar Content (match other calendar views)
    private var principalToolbarContent: some View {
        HStack(spacing: 8) {
            SharedNavigationToolbar()
            
            Button(action: { step(-1) }) {
                Image(systemName: "chevron.left")
            }
            
            Button(action: {
                selectedDateForPicker = currentDate
                showingDatePicker = true
            }) {
                Text(titleText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(isCurrentWeekTitle ? DateDisplayStyle.currentPeriodColor : .primary)
            }
            
            Button(action: { step(1) }) {
                Image(systemName: "chevron.right")
            }
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
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { showingDatePicker = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            currentDate = selectedDateForPicker
                            navigationManager.updateInterval(.week, date: selectedDateForPicker)
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }
    
    private var trailingToolbarButtons: some View {
        HStack(spacing: 12) {
            // Day button
            Button(action: {
                navigationManager.switchToCalendar()
                navigationManager.updateInterval(.day, date: currentDate)
            }) {
                Image(systemName: "d.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentInterval == .day && navigationManager.currentView != .weeklyView ? .accentColor : .secondary)
            }
            
            // Standard WeeklyView button
            Button(action: {
                let now = Date()
                navigationManager.switchToWeeklyView()
                navigationManager.updateInterval(.week, date: now)
            }) {
                Image(systemName: "w.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentView == .weeklyView ? .accentColor : .secondary)
            }
            
            // GWeekView button (active)
            Button(action: {
                navigationManager.currentView = .gWeekView
                navigationManager.updateInterval(.week, date: currentDate)
            }) {
                Image(systemName: "g.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentView == .gWeekView ? .accentColor : .secondary)
            }

            // Hide Completed toggle
            Button(action: { appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks) }) {
                Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash.circle" : "eye.circle")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            // Refresh button (sync)
            Button(action: {
                Task {
                    await calendarViewModel.loadCalendarDataForWeek(containing: currentDate)
                    await tasksViewModel.loadTasks()
                }
            }) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            // Add menu (Event or Task)
            Menu {
                Button("Event") {
                    NotificationCenter.default.post(name: Notification.Name("LPV3_ShowAddEvent"), object: nil)
                }
                Button("Task") {
                    NotificationCenter.default.post(name: Notification.Name("LPV3_ShowAddTask"), object: nil)
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Title helpers (match WeeklyView)
    private var isCurrentWeekTitle: Bool {
        let cal = Calendar.mondayFirst
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
              let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else { return false }
        return currentDate >= weekStart && currentDate <= weekEnd
    }

    private var titleText: String {
        let calendar = Calendar.mondayFirst
        guard
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start,
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)
        else { return "Week" }
        let startString = DateFormatter.standardDate.string(from: weekStart)
        let endString = DateFormatter.standardDate.string(from: weekEnd)
        return "\(startString) - \(endString)"
    }
}

#Preview {
    GWeekView()
}
