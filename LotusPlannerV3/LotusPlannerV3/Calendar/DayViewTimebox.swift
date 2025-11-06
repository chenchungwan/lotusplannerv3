import SwiftUI

struct DayViewTimebox: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    private let onEventTap: ((GoogleCalendarEvent) -> Void)?
    
    // MARK: - State Variables
    @State private var dayLeftSectionWidth: CGFloat
    @State private var isDayVerticalDividerDragging = false
    @State private var isTasksSectionCollapsed: Bool = false
    @State private var tasksSectionHeight: CGFloat = 400
    @State private var isTasksDividerDragging = false
    @State private var isLogsSectionCollapsed: Bool = false
    
    // MARK: - Selection State
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedTaskAccount: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails: Bool = false
    @State private var selectedEvent: GoogleCalendarEvent?
    
    init(onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self._navigationManager = ObservedObject(wrappedValue: NavigationManager.shared)
        self._appPrefs = ObservedObject(wrappedValue: AppPreferences.shared)
        self.calendarVM = DataManager.shared.calendarViewModel
        self._tasksVM = ObservedObject(wrappedValue: DataManager.shared.tasksViewModel)
        self._auth = ObservedObject(wrappedValue: GoogleAuthManager.shared)
        self.onEventTap = onEventTap
        
        // Initialize state variables with stored values from AppPreferences
        self._dayLeftSectionWidth = State(initialValue: AppPreferences.shared.dayViewTimeboxLeftSectionWidth)
        self._isTasksSectionCollapsed = State(initialValue: AppPreferences.shared.dayViewTimeboxTasksSectionCollapsed)
        self._tasksSectionHeight = State(initialValue: AppPreferences.shared.dayViewTimeboxTasksSectionHeight)
        self._isTasksDividerDragging = State(initialValue: false)
        self._isLogsSectionCollapsed = State(initialValue: AppPreferences.shared.dayViewTimeboxLogsSectionCollapsed)
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                // Left section (dynamic width) - TimeboxComponent and Logs
                leftDaySectionWithDivider(geometry: geometry)
                    .frame(width: dayLeftSectionWidth)
                
                // Vertical divider
                dayVerticalDivider
                
                // Middle section (Tasks and Journal) - expands to fill remaining space
                middleDaySection(geometry: geometry)
                    .frame(width: geometry.size.width - dayLeftSectionWidth - 8) // 8 for divider width
            }
        }
        // Task details sheet
        .sheet(isPresented: Binding(
            get: { showingTaskDetails && selectedTask != nil && selectedTaskListId != nil && selectedTaskAccount != nil },
            set: { showingTaskDetails = $0 }
        )) {
            if let t = selectedTask, let listId = selectedTaskListId, let account = selectedTaskAccount {
                TaskDetailsView(
                    task: t,
                    taskListId: listId,
                    accountKind: account,
                    accentColor: account == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    personalTaskLists: tasksVM.personalTaskLists,
                    professionalTaskLists: tasksVM.professionalTaskLists,
                    appPrefs: appPrefs,
                    viewModel: tasksVM,
                    onSave: { updatedTask in
                        Task {
                            await tasksVM.updateTask(updatedTask, in: listId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onDelete: {
                        Task {
                            await tasksVM.deleteTask(t, from: listId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onMove: { updatedTask, targetListId in
                        Task {
                            await tasksVM.moveTask(updatedTask, from: listId, to: targetListId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                        Task {
                            await tasksVM.crossAccountMoveTask(updatedTask, from: (account, listId), to: (targetAccount, targetListId))
                        }
                        showingTaskDetails = false
                    },
                    isNew: false
                )
            }
        }
        // Event details sheet
        .sheet(item: Binding<GoogleCalendarEvent?>(
            get: { selectedEvent },
            set: { selectedEvent = $0 }
        )) { ev in
            let accountKind: GoogleAuthManager.AccountKind = calendarVM.personalEvents.contains(where: { $0.id == ev.id }) ? .personal : .professional
            AddItemView(
                currentDate: ev.startTime ?? Date(),
                tasksViewModel: tasksVM,
                calendarViewModel: calendarVM,
                appPrefs: appPrefs,
                existingEvent: ev,
                accountKind: accountKind,
                showEventOnly: true
            )
        }
    }
    
    // MARK: - Left Section
    private func leftDaySectionWithDivider(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // TimeboxComponent section
            TimeboxComponent(
                date: navigationManager.currentDate,
                events: getAllEventsForDate(navigationManager.currentDate),
                personalEvents: calendarVM.personalEvents,
                professionalEvents: calendarVM.professionalEvents,
                personalTasks: filteredTasksForDate(tasksVM.personalTasks, date: navigationManager.currentDate),
                professionalTasks: filteredTasksForDate(tasksVM.professionalTasks, date: navigationManager.currentDate),
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                onEventTap: { ev in
                    if let onEventTap = onEventTap {
                        onEventTap(ev)
                    } else {
                        selectedEvent = ev
                    }
                },
                onTaskTap: { task, listId in
                    // Determine account kind
                    let accountKind: GoogleAuthManager.AccountKind = tasksVM.personalTasks[listId] != nil ? .personal : .professional
                    selectedTask = task
                    selectedTaskListId = listId
                    selectedTaskAccount = accountKind
                    showingTaskDetails = true
                },
                onTaskToggle: { task, listId in
                    // Determine account kind
                    let accountKind: GoogleAuthManager.AccountKind = tasksVM.personalTasks[listId] != nil ? .personal : .professional
                    Task {
                        await tasksVM.toggleTaskCompletion(task, in: listId, for: accountKind)
                    }
                },
                showAllDaySection: true
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            
            // Logs section (collapsible)
            if appPrefs.showAnyLogs {
                if !isLogsSectionCollapsed {
                    // Expand/collapse button
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLogsSectionCollapsed = true
                                appPrefs.updateDayViewTimeboxLogsSectionCollapsed(true)
                            }
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                    .padding(.vertical, 4)
                    .background(Color(.systemBackground))
                    
                    // Logs content
                    ScrollView(.vertical, showsIndicators: true) {
                        LogsComponent(currentDate: navigationManager.currentDate, horizontal: false)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Collapsed state - show expand button
                    expandLogsButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Middle Section (Tasks and Journal)
    private func middleDaySection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Tasks section (collapsible)
            if !isTasksSectionCollapsed {
                tasksSection
                    .frame(height: tasksSectionHeight)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Expand button when collapsed
                expandTasksButton
            }
            
            // Draggable divider between Tasks and Journal (only show if tasks section is visible)
            if !isTasksSectionCollapsed {
                tasksJournalDivider
            }
            
            // Journal section (expands to fill remaining space)
            VStack(alignment: .leading, spacing: 6) {
                JournalView(currentDate: $navigationManager.currentDate, embedded: true, layoutType: .compact)
            }
            .id(navigationManager.currentDate)
            .frame(maxHeight: .infinity)
            .padding(.all, 8)
            .background(Color(.systemBackground))
            .clipped()
        }
    }
    
    // MARK: - Tasks Section
    private var tasksSection: some View {
        VStack(spacing: 0) {
            // Header with collapse button in top-right corner
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTasksSectionCollapsed = true
                        appPrefs.updateDayViewTimeboxTasksSectionCollapsed(true)
                    }
                }) {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .padding(.vertical, 4)
            .background(Color(.systemBackground))
            
            // Tasks content - side by side
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 8) {
                    // Personal Tasks section
                    personalTasksSection
                        .frame(maxWidth: .infinity)
                    
                    // Divider between personal and professional
                    Divider()
                    
                    // Professional Tasks section
                    professionalTasksSection
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Task Sections
    private var personalTasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let personalFiltered = filteredTasksForDate(tasksVM.personalTasks, date: navigationManager.currentDate)
            if auth.isLinked(kind: .personal) && !personalFiltered.values.flatMap({ $0 }).isEmpty {
                TasksComponent(
                    taskLists: tasksVM.personalTaskLists,
                    tasksDict: personalFiltered,
                    accentColor: appPrefs.personalColor,
                    accountType: .personal,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksVM.toggleTaskCompletion(task, in: listId, for: .personal)
                        }
                    },
                    onTaskDetails: { task, listId in
                        selectedTask = task
                        selectedTaskListId = listId
                        selectedTaskAccount = .personal
                        showingTaskDetails = true
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksVM.updateTaskListOrder(newOrder, for: .personal)
                        }
                    },
                    isSingleDayView: true
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if !auth.isLinked(kind: .personal) && !auth.isLinked(kind: .professional) {
                // Empty state - show link account UI
                Button(action: { NavigationManager.shared.showSettings() }) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("Link Your Google Account")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("Connect your Google account to view and manage your tasks")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // Account linked but no personal tasks
                Text("No tasks")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private var professionalTasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let professionalFiltered = filteredTasksForDate(tasksVM.professionalTasks, date: navigationManager.currentDate)
            if auth.isLinked(kind: .professional) && !professionalFiltered.values.flatMap({ $0 }).isEmpty {
                TasksComponent(
                    taskLists: tasksVM.professionalTaskLists,
                    tasksDict: professionalFiltered,
                    accentColor: appPrefs.professionalColor,
                    accountType: .professional,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksVM.toggleTaskCompletion(task, in: listId, for: .professional)
                        }
                    },
                    onTaskDetails: { task, listId in
                        selectedTask = task
                        selectedTaskListId = listId
                        selectedTaskAccount = .professional
                        showingTaskDetails = true
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksVM.updateTaskListOrder(newOrder, for: .professional)
                        }
                    },
                    isSingleDayView: true
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                // Account linked but no professional tasks
                Text("No tasks")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private var dayVerticalDivider: some View {
        Rectangle()
            .fill(isDayVerticalDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isDayVerticalDividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDayVerticalDividerDragging = true
                        let newWidth = dayLeftSectionWidth + value.translation.width
                        let minWidth: CGFloat = 200
                        let maxWidth: CGFloat = 500
                        dayLeftSectionWidth = max(minWidth, min(maxWidth, newWidth))
                    }
                    .onEnded { _ in
                        isDayVerticalDividerDragging = false
                        appPrefs.updateDayViewTimeboxLeftSectionWidth(dayLeftSectionWidth)
                    }
            )
    }
    
    private var expandLogsButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isLogsSectionCollapsed = false
                appPrefs.updateDayViewTimeboxLogsSectionCollapsed(false)
            }
        }) {
            HStack {
                Image(systemName: "chevron.up")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Logs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
    }
    
    private var expandTasksButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isTasksSectionCollapsed = false
                appPrefs.updateDayViewTimeboxTasksSectionCollapsed(false)
            }
        }) {
            HStack {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Tasks")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
    }
    
    private var tasksJournalDivider: some View {
        Rectangle()
            .fill(isTasksDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isTasksDividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isTasksDividerDragging = true
                        let newHeight = tasksSectionHeight + value.translation.height
                        let minHeight: CGFloat = 200
                        let maxHeight: CGFloat = 800
                        tasksSectionHeight = max(minHeight, min(maxHeight, newHeight))
                    }
                    .onEnded { _ in
                        isTasksDividerDragging = false
                        appPrefs.updateDayViewTimeboxTasksSectionHeight(tasksSectionHeight)
                    }
            )
    }
    
    // MARK: - Helper Functions
    private func getAllEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.mondayFirst
        let all = calendarVM.personalEvents + calendarVM.professionalEvents
        return all.filter { ev in
            guard let startTime = ev.startTime else { return ev.isAllDay }
            
            if ev.isAllDay {
                // For all-day events, check if the date falls within the event's date range
                guard let endTime = ev.endTime else { return false }
                
                // For all-day events, Google Calendar typically sets the end time to the start of the next day
                // But for single-day events, end.date might equal start.date
                // So we need to check if the date falls within [startTime, endTime)
                let startDay = calendar.startOfDay(for: startTime)
                let endDay = calendar.startOfDay(for: endTime)
                let dateDay = calendar.startOfDay(for: date)
                
                // If endDay equals startDay (single-day event), check if date matches
                if endDay == startDay {
                    return dateDay == startDay
                }
                // Otherwise, check if date is within [startDay, endDay)
                return dateDay >= startDay && dateDay < endDay
            } else {
                // For timed events, check if the date falls within the event's date range
                guard let endTime = ev.endTime else {
                    // If no end time, only show on start date
                    return calendar.isDate(startTime, inSameDayAs: date)
                }
                
                let startDay = calendar.startOfDay(for: startTime)
                let endDay = calendar.startOfDay(for: endTime)
                let dateDay = calendar.startOfDay(for: date)
                
                // If event is on the same day, show only if date matches
                if endDay == startDay {
                    return dateDay == startDay
                }
                
                // Otherwise, show if date is within [startDay, endDay]
                // Include both start and end days
                return dateDay >= startDay && dateDay <= endDay
            }
        }
    }
    
    private func filteredTasksForDate(_ dict: [String: [GoogleTask]], date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.mondayFirst
        let startOfViewedDate = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: Date())
        let isViewingToday = startOfViewedDate == startOfToday
        
        var result: [String: [GoogleTask]] = [:]
        for (listId, tasks) in dict {
            let filtered = tasks.filter { task in
                // For completed tasks, show only on completion date
                if task.isCompleted {
                    if let comp = task.completionDate {
                        return Calendar.mondayFirst.isDate(comp, inSameDayAs: date)
                    }
                    return false
                }
                
                // For incomplete tasks
                if let dueDate = task.dueDate {
                    let startOfDueDate = calendar.startOfDay(for: dueDate)
                    let isViewingDueDate = startOfViewedDate == startOfDueDate
                    let isOverdue = startOfDueDate < startOfToday
                    
                    // Show if:
                    // 1. We're viewing its due date (past or future), OR
                    // 2. We're viewing today AND it's overdue
                    return isViewingDueDate || (isViewingToday && isOverdue)
                }
                return false
            }
            if !filtered.isEmpty { result[listId] = filtered }
        }
        return result
    }
}

#Preview {
    DayViewTimebox()
}

