import SwiftUI

enum WeeklyViewMode: String, CaseIterable, Hashable {
    case week
}

struct WeeklyView: View {
    @EnvironmentObject var appPrefs: AppPreferences
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    
    @State private var selectedDate = Date()
    @State private var viewMode: WeeklyViewMode = .week
    @State private var selectedCalendarEvent: GoogleCalendarEvent?
    @State private var showingEventDetails = false
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    struct WeeklyTaskSelection: Identifiable {
        let id = UUID()
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    @State private var taskSheetSelection: WeeklyTaskSelection?
    @State private var showingAddEvent = false
    @State private var showingNewTask = false
    @State private var showingDatePicker = false
    @State private var selectedDateForPicker = Date()
    @State private var v2TopTasksHeight: CGFloat = 300
    @State private var isV2DividerDragging: Bool = false
    
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
        // Event details sheet removed
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
                selectedDateForPicker = selectedDate
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
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { showingDatePicker = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            selectedDate = selectedDateForPicker
                            navigationManager.switchToWeeklyView()
                            navigationManager.updateInterval(.week, date: selectedDateForPicker)
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }
    
    private var isCurrentWeekTitle: Bool {
        let cal = Calendar.mondayFirst
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
              let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else { return false }
        return selectedDate >= weekStart && selectedDate <= weekEnd
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
                    .foregroundColor(navigationManager.currentInterval == .day && navigationManager.currentView != .weeklyView ? .accentColor : .secondary)
            }
            
            // WeeklyView button
            Button(action: {
                let now = Date()
                selectedDate = now
                navigationManager.switchToWeeklyView()
                navigationManager.updateInterval(.week, date: now)
                Task { await tasksViewModel.loadTasks() }
            }) {
                Image(systemName: "w.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentView == .weeklyView ? .accentColor : .secondary)
            }

            // g.circle removed
            
            // Hide Completed toggle
            Button(action: { appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks) }) {
                Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash.circle" : "eye.circle")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            // Refresh button
            Button(action: {
                Task {
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
                        Button(action: { NavigationManager.shared.showSettings() }) {
                            VStack(spacing: 8) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No Task Accounts Linked")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Link your Google accounts in Settings to view tasks")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
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

extension WeeklyView {
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
                .frame(height: (authManager.isLinked(kind: .professional) && professionalHasAny) ? v2TopTasksHeight : nil, alignment: .top)
                .clipped()
            }
            
            // Draggable divider between task types (only when both present)
            if authManager.isLinked(kind: .personal) && authManager.isLinked(kind: .professional) && personalHasAny && professionalHasAny {
                Rectangle()
                    .fill(isV2DividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                    .frame(height: 8)
                    .overlay(
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundColor(isV2DividerDragging ? .white : .gray)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isV2DividerDragging = true
                                let newHeight = v2TopTasksHeight + value.translation.height
                                let minHeight: CGFloat = 150
                                let maxHeight: CGFloat = max(250, UIScreen.main.bounds.height - 350)
                                v2TopTasksHeight = max(minHeight, min(maxHeight, newHeight))
                            }
                            .onEnded { _ in
                                isV2DividerDragging = false
                            }
                    )
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
                .frame(maxHeight: .infinity, alignment: .top)
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
                        taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: .personal)
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
                        taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: .professional)
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



extension WeeklyViewMode {
    var displayName: String {
        switch self {
        case .week: return "Week"
        }
    }
}
