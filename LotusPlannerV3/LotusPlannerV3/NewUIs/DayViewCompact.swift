import SwiftUI

struct DayViewCompact: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    @ObservedObject private var bulkEditManager: BulkEditManager
    private let onEventTap: ((GoogleCalendarEvent) -> Void)?

    // MARK: - State Variables
    @State private var dayLeftSectionWidth: CGFloat
    @State private var leftTimelineHeight: CGFloat
    @State private var isLeftTimelineDividerDragging = false
    @State private var eventsHeight: CGFloat
    @State private var isEventsTasksDividerDragging = false
    @State private var logsHeight: CGFloat
    @State private var isLogsDividerDragging = false
    @State private var isDayVerticalDividerDragging = false
    @State private var isLogsSectionCollapsed: Bool = false

    // MARK: - Selection State
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedTaskAccount: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails: Bool = false

    init(bulkEditManager: BulkEditManager, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self._navigationManager = ObservedObject(wrappedValue: NavigationManager.shared)
        self._appPrefs = ObservedObject(wrappedValue: AppPreferences.shared)
        self.calendarVM = DataManager.shared.calendarViewModel
        self._tasksVM = ObservedObject(wrappedValue: DataManager.shared.tasksViewModel)
        self._auth = ObservedObject(wrappedValue: GoogleAuthManager.shared)
        self._bulkEditManager = ObservedObject(wrappedValue: bulkEditManager)
        self.onEventTap = onEventTap
        
        // Initialize state variables with stored values from AppPreferences
        self._dayLeftSectionWidth = State(initialValue: AppPreferences.shared.dayViewCompactLeftColumnWidth)
        self._leftTimelineHeight = State(initialValue: AppPreferences.shared.dayViewCompactLeftTopHeight)
        self._eventsHeight = State(initialValue: AppPreferences.shared.dayViewClassic2EventsHeight)
        self._logsHeight = State(initialValue: AppPreferences.shared.dayViewClassic2LogsHeight)
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                // Left section (dynamic width)
                leftDaySectionWithDivider(geometry: geometry)
                    .frame(width: dayLeftSectionWidth)
                
                // Vertical divider
                dayVerticalDivider
                
                // Right section expands to fill remaining space
                rightDaySection(geometry: geometry)
                    .frame(maxWidth: .infinity)
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
    }
    
    // MARK: - Left Section
    private func leftDaySectionWithDivider(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Events section - scrollable
            ScrollView(.vertical, showsIndicators: true) {
                eventsTimelineCard()
                    .padding(.leading, 16 + geometry.safeAreaInsets.leading)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)

            // Logs section at the bottom (collapsible, only if any logs are enabled)
            if appPrefs.showAnyLogs {
                if !isLogsSectionCollapsed {
                    // Draggable divider
                    logsDivider

                    // Collapse button
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLogsSectionCollapsed = true
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
                    .frame(height: logsHeight)
                    .background(Color(.systemBackground))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Expand button when collapsed
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogsSectionCollapsed = false
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Right Section
    private func rightDaySection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top section: Tasks arranged horizontally - takes natural height based on content
            tasksSection
            
            // Horizontal divider
            Divider()
            
            // Bottom section: Journal - expands to fill remaining space
            journalSection
                .frame(maxHeight: .infinity)
        }
    }
    
    @ViewBuilder
    private var tasksSection: some View {
        VStack(spacing: 0) {
            // Bulk Edit Toolbar (shown when in bulk edit mode)
            if bulkEditManager.state.isActive {
                BulkEditToolbarView(bulkEditManager: bulkEditManager)
            }

            HStack(alignment: .top, spacing: 12) {
                // Personal Tasks on the left
                personalTasksSection
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Professional Tasks on the right
                professionalTasksSection
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var journalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            JournalView(currentDate: $navigationManager.currentDate, embedded: true, layoutType: .compact)
        }
        .id(navigationManager.currentDate)
        .padding(.all, 8)
        .background(Color(.systemBackground))
        .clipped()
    }
    
    // MARK: - Components
    
    private var leftTimelineSection: some View {
        // Always show events as a list in compact view
        dayEventsList
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    // Shared Events timeline card used by all layouts
    private func eventsTimelineCard() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Events")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 8)
            leftTimelineSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .padding(.bottom, 0)
        .padding(.leading, 8)
    }
    
    private var dayEventsList: some View {
        let events = getAllEventsForDate(navigationManager.currentDate)
            .sorted { (a, b) in
                let aDate = a.startTime ?? Date.distantPast
                let bDate = b.startTime ?? Date.distantPast
                return aDate < bDate
            }
        return EventsListComponent(
            events: events,
            personalEvents: calendarVM.personalEvents,
            professionalEvents: calendarVM.professionalEvents,
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor,
            onEventTap: { ev in
                onEventTap?(ev)
            },
            date: navigationManager.currentDate
        )
    }
    
    // MARK: - Task Sections
    @ViewBuilder
    private var personalTasksSection: some View {
        let personalFiltered = filteredTasksForDate(tasksVM.personalTasks, date: navigationManager.currentDate)
        if !auth.isLinked(kind: .personal) && !auth.isLinked(kind: .professional) {
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
            TasksCompactComponent(
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
                isBulkEditMode: bulkEditManager.state.isActive,
                selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                onTaskSelectionToggle: { taskId in
                    if bulkEditManager.state.selectedTaskIds.contains(taskId) {
                        bulkEditManager.state.selectedTaskIds.remove(taskId)
                    } else {
                        bulkEditManager.state.selectedTaskIds.insert(taskId)
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private var professionalTasksSection: some View {
        let professionalFiltered = filteredTasksForDate(tasksVM.professionalTasks, date: navigationManager.currentDate)
        TasksCompactComponent(
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
            isBulkEditMode: bulkEditManager.state.isActive,
            selectedTaskIds: bulkEditManager.state.selectedTaskIds,
            onTaskSelectionToggle: { taskId in
                if bulkEditManager.state.selectedTaskIds.contains(taskId) {
                    bulkEditManager.state.selectedTaskIds.remove(taskId)
                } else {
                    bulkEditManager.state.selectedTaskIds.insert(taskId)
                }
            }
        )
    }
    
    
    private var eventsTasksDivider: some View {
        Rectangle()
            .fill(isEventsTasksDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isEventsTasksDividerDragging ? .white : .gray)
            )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isEventsTasksDividerDragging = true
                                let newHeight = eventsHeight + value.translation.height
                                let minHeight: CGFloat = 150
                                let maxHeight: CGFloat = 400
                                eventsHeight = max(minHeight, min(maxHeight, newHeight))
                            }
                            .onEnded { _ in
                                isEventsTasksDividerDragging = false
                                appPrefs.updateDayViewClassic2EventsHeight(eventsHeight)
                            }
                    )
    }
    
    private var logsDivider: some View {
        Rectangle()
            .fill(isLogsDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isLogsDividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isLogsDividerDragging = true
                        let newHeight = logsHeight - value.translation.height
                        let minHeight: CGFloat = 100
                        let maxHeight: CGFloat = 600
                        logsHeight = max(minHeight, min(maxHeight, newHeight))
                    }
                    .onEnded { _ in
                        isLogsDividerDragging = false
                        appPrefs.updateDayViewClassic2LogsHeight(logsHeight)
                    }
            )
    }
    
    private var leftTimelineDivider: some View {
        Rectangle()
            .fill(isLeftTimelineDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isLeftTimelineDividerDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isLeftTimelineDividerDragging = true
                        let newHeight = leftTimelineHeight + value.translation.height
                        let minHeight: CGFloat = 200
                        let maxHeight: CGFloat = 500
                        leftTimelineHeight = max(minHeight, min(maxHeight, newHeight))
                    }
                    .onEnded { _ in
                        isLeftTimelineDividerDragging = false
                        appPrefs.updateDayViewCompactLeftTopHeight(leftTimelineHeight)
                    }
            )
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
                        appPrefs.updateDayViewCompactLeftColumnWidth(dayLeftSectionWidth)
                    }
            )
    }
    
    // MARK: - Helper Functions
    private func getAllEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        calendarVM.events(for: date)
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
    DayViewCompact(bulkEditManager: BulkEditManager())
}
