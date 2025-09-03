import SwiftUI

enum ViewModeV2: String, CaseIterable, Hashable {
    case week
}

struct BaseViewV2: View {
    @EnvironmentObject var appPrefs: AppPreferences
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    
    @State private var selectedDate = Date()
    @State private var viewMode: ViewModeV2 = .week
    @State private var selectedCalendarEvent: GoogleCalendarEvent?
    @State private var showingEventDetails = false
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    struct BaseV2TaskSelection: Identifiable {
        let id = UUID()
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    @State private var taskSheetSelection: BaseV2TaskSelection?
    @State private var showingAddEvent = false
    @State private var showingNewTask = false
    
    // No section width management needed since we removed the events section
    
    var body: some View {
        mainContent
            .sidebarToggleHidden()
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    principalToolbarContent
                }

                ToolbarItemGroup(placement: .principal) { EmptyView() }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    trailingToolbarButtons
                }
            }
        .sheet(item: Binding<GoogleCalendarEvent?>(
            get: { selectedCalendarEvent },
            set: { selectedCalendarEvent = $0 }
        )) { event in
            CalendarEventDetailsView(event: event) {
                // Handle event deletion if needed
            }
        }
        .sheet(isPresented: $showingAddEvent) {
            AddItemView(
                currentDate: selectedDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
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
        .sheet(isPresented: $showingNewTask) {
            // Create-task UI matching TasksView create flow
            let personalLinked = authManager.isLinked(kind: .personal)
            let professionalLinked = authManager.isLinked(kind: .professional)
            let defaultAccount: GoogleAuthManager.AccountKind = selectedAccountKind ?? (personalLinked ? .personal : .professional)
            let defaultLists = defaultAccount == .personal ? tasksViewModel.personalTaskLists : tasksViewModel.professionalTaskLists
            let defaultListId = defaultLists.first?.id ?? ""
            let newTask = GoogleTask(
                id: UUID().uuidString,
                title: "",
                notes: nil,
                status: "needsAction",
                due: nil,
                completed: nil,
                updated: nil
            )
            TaskDetailsView(
                task: newTask,
                taskListId: defaultListId,
                accountKind: defaultAccount,
                accentColor: defaultAccount == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { _ in },
                onDelete: {},
                onMove: { _, _ in },
                onCrossAccountMove: { _, _, _ in },
                isNew: true
            )
        }
        .task {
            // Initialize selectedDate from navigation manager if available
            selectedDate = navigationManager.currentDate
            await tasksViewModel.loadTasks()
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            selectedDate = newValue
        }
    }
    
    // MARK: - Toolbar Content
    private var principalToolbarContent: some View {
        HStack(spacing: 8) {
            SharedNavigationToolbar()
            
            Button(action: { step(-1) }) {
                Image(systemName: "chevron.left")
            }
            
            Button(action: { 
                selectedDate = Date() // Go to today
                navigationManager.updateInterval(.week, date: Date())
            }) {
                Text(titleText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            Button(action: { step(1) }) {
                Image(systemName: "chevron.right")
            }
        }
    }
    
    private var trailingToolbarButtons: some View {
        HStack(spacing: 12) {
            // Day button
            Button(action: {
                navigationManager.switchToCalendar()
                navigationManager.updateInterval(.day, date: selectedDate)
            }) {
                Image(systemName: "d.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentInterval == .day && navigationManager.currentView != .baseViewV2 ? .accentColor : .secondary)
            }
            
            // BaseViewV2 button (keep V only)
            Button(action: {
                navigationManager.switchToBaseViewV2()
            }) {
                Image(systemName: "v.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentView == .baseViewV2 ? .accentColor : .secondary)
            }
            
            // Hide Completed toggle
            Button(action: { appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks) }) {
                Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash.circle" : "eye.circle")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            // Add menu (Event or Task)
            Menu {
                Button("Event") { 
                    showingAddEvent = true
                }
                Button("Task") {
                    showingNewTask = true
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Main Content
    private var mainContent: some View {
        // Main content area with only tasks section (no events section)
        VStack(spacing: 0) {
            // Tasks section - Full width
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    // Week view - 7-column tasks layout
                    weekTasksView
                    
                    // If neither account is linked, show placeholder
                    if !authManager.isLinked(kind: .personal) && !authManager.isLinked(kind: .professional) {
                        VStack {
                            Text("No Task Accounts Linked")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Link your Google accounts in Settings to view tasks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.all, 8)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .padding(.all, 8)
        }
        .frame(minHeight: 0, maxHeight: .infinity)
    }
    }


// MARK: - Helpers

extension BaseViewV2 {
    // MARK: - Task Views

    
    private var weekTasksView: some View {
        let fixedWidth: CGFloat = 1600 // Increased width for wider day columns
        let timeColumnWidth: CGFloat = 50 // Same as timeline (kept for timeline compatibility)
        let dayColumnWidth = fixedWidth / 7 // Each day column now ~228 points (no time column)
        
        // Determine whether there are any tasks to show this week for each account
        let personalHasAny = weekDates.contains { date in
            let dict = getFilteredTasksForSpecificDate(tasksViewModel.personalTasks, date: date)
            return !dict.allSatisfy { $0.value.isEmpty }
        }
        let professionalHasAny = weekDates.contains { date in
            let dict = getFilteredTasksForSpecificDate(tasksViewModel.professionalTasks, date: date)
            return !dict.allSatisfy { $0.value.isEmpty }
        }

        return VStack(spacing: 0) {
            if personalHasAny || professionalHasAny {
                // Shared Date Header Row (only when there is at least one row to show)
                weekTasksDateHeader(dayColumnWidth: dayColumnWidth, timeColumnWidth: timeColumnWidth)
                // Divider below date header
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 1)
            }

            // Personal Tasks Row (top 50%)
            if authManager.isLinked(kind: .personal) && personalHasAny {
                VStack(alignment: .leading, spacing: 4) {
                    
                    // Fixed-width 7-day task columns
                    HStack(spacing: 0) {
                        // 7-day task columns with fixed width
                        ForEach(weekDates, id: \.self) { date in
                            weekTaskColumnPersonal(date: date)
                                .frame(width: dayColumnWidth) // Fixed width matching timeline
                                .background(Color(.systemBackground))
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                        }
                    }
                    .frame(width: fixedWidth) // Total fixed width
                }
                .padding(.all, 8)
                .background(Color(.systemGray6).opacity(0.3))
            }
            
            // Divider between task types
            if authManager.isLinked(kind: .personal) && authManager.isLinked(kind: .professional) && personalHasAny && professionalHasAny {
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 1)
            }
            
            // Professional Tasks Row (bottom 50%)
            if authManager.isLinked(kind: .professional) && professionalHasAny {
                VStack(alignment: .leading, spacing: 4) {
                    
                    // Fixed-width 7-day task columns
                    HStack(spacing: 0) {
                        // 7-day task columns with fixed width
                        ForEach(weekDates, id: \.self) { date in
                            weekTaskColumnProfessional(date: date)
                                .frame(width: dayColumnWidth) // Fixed width matching timeline
                                .background(Color(.systemBackground))
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                        }
                    }
                    .frame(width: fixedWidth) // Total fixed width
                }
                .padding(.all, 8)
                .background(Color(.systemGray6).opacity(0.3))
            }
        }
    }
    
    // Calendar-related views removed since we only show tasks now
    

    
    private var titleText: String {
        let calendar = Calendar.mondayFirst
        guard
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start,
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)
        else { return "Week" }
        
        // Standardized format: 12/25/24 - 12/31/24
        let startString = DateFormatter.standardDate.string(from: weekStart)
        let endString = DateFormatter.standardDate.string(from: weekEnd)
        
        return "\(startString) - \(endString)"
    }
    
    private func step(_ offset: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) {
            selectedDate = newDate
            navigationManager.updateInterval(.week, date: newDate)
        }
    }
    
    // Calendar event functions removed - only tasks are displayed now
    
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return []
        }
        
        var days: [Date] = []
        var date = weekInterval.start
        
        // Get Monday to Sunday (7 days)
        for _ in 0..<7 {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        return days
    }
    
    // Calendar event helper functions removed since we only show tasks now
    
    // MARK: - Week Task Functions
    private func weekTasksDateHeader(dayColumnWidth: CGFloat, timeColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Day headers
            ForEach(weekDates, id: \.self) { date in
                weekTaskDateHeaderView(date: date)
                    .frame(width: dayColumnWidth, height: 60)
                    .background(Color(.systemGray6))
                    .overlay(
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
            }
        }
        .background(Color(.systemBackground))
    }
    
    private func weekTaskDateHeaderView(date: Date) -> some View {
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        
        return VStack(spacing: 4) {
            // Standardized day of week format: MON, TUE, etc.
            Text(DateFormatter.standardDayOfWeek.string(from: date).uppercased())
                .font(DateDisplayStyle.bodyFont)
                .fontWeight(.semibold)
                .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.secondaryColor)
            
            // Standardized date format: m/d/yy
            Text(DateFormatter.standardDate.string(from: date))
                .font(DateDisplayStyle.titleFont)
                .fontWeight(.bold)
                .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.primaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isToday ? Color.blue : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { 
            selectedDate = date 
        }
    }
    
    private func weekTaskColumnPersonal(date: Date) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            // Personal Tasks using day view component
            let personalTasksForDate = getFilteredTasksForSpecificDate(tasksViewModel.personalTasks, date: date)
            if !personalTasksForDate.allSatisfy({ $0.value.isEmpty }) {
                TasksComponent(
                    taskLists: tasksViewModel.personalTaskLists,
                    tasksDict: personalTasksForDate,
                    accentColor: appPrefs.personalColor,
                    accountType: .personal,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = BaseV2TaskSelection(task: task, listId: listId, accountKind: .personal)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                        }
                    },
                    hideDueDateTag: true,
                    showEmptyState: false
                )
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
    
    private func weekTaskColumnProfessional(date: Date) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            // Professional Tasks using day view component
            let professionalTasksForDate = getFilteredTasksForSpecificDate(tasksViewModel.professionalTasks, date: date)
            if !professionalTasksForDate.allSatisfy({ $0.value.isEmpty }) {
                TasksComponent(
                    taskLists: tasksViewModel.professionalTaskLists,
                    tasksDict: professionalTasksForDate,
                    accentColor: appPrefs.professionalColor,
                    accountType: .professional,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = BaseV2TaskSelection(task: task, listId: listId, accountKind: .professional)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                        }
                    },
                    hideDueDateTag: true,
                    showEmptyState: false
                )
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
    
    // Helper function to get filtered tasks for a specific date (for weekly view)
    private func getFilteredTasksForSpecificDate(_ tasks: [String: [GoogleTask]], date: Date) -> [String: [GoogleTask]] {
        var filteredTasks: [String: [GoogleTask]] = [:]
        
        for (listId, taskList) in tasks {
            let dateFilteredTasks = taskList.filter { task in
                // Only show tasks that have a due date AND it matches the specified date
                guard let dueDate = task.dueDate else { 
                    return false // Tasks without due dates are NOT shown
                }
                
                // Check if the due date is the same day as the specified date
                return Calendar.current.isDate(dueDate, inSameDayAs: date)
            }
            
            // Only include the list if it has tasks after filtering
            if !dateFilteredTasks.isEmpty {
                filteredTasks[listId] = dateFilteredTasks
            }
        }
        
        return filteredTasks
    }
    
    private func findTaskListId(for task: GoogleTask, in accountKind: GoogleAuthManager.AccountKind) -> String? {
        let tasksDict = accountKind == .personal ? tasksViewModel.personalTasks : tasksViewModel.professionalTasks
        
        for (listId, tasks) in tasksDict {
            if tasks.contains(where: { $0.id == task.id }) {
                return listId
            }
        }
        
        return nil
    }
    
    // Calendar header functions removed since we only show tasks now
    
    // All calendar-related timeline functions removed since we only show tasks now

}



extension ViewModeV2 {
    var displayName: String {
        switch self {
        case .week: return "Week"
        }
    }
}
