import SwiftUI

struct DayViewNewExpanded: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    @ObservedObject private var bulkEditManager: BulkEditManager
    private let onEventTap: ((GoogleCalendarEvent) -> Void)?

    // MARK: - State Variables
    @State private var dayLeftSectionWidth: CGFloat
    @State private var isDayVerticalDividerDragging = false
    @State private var tasksSectionHeight: CGFloat = 400
    @State private var isTasksDividerDragging = false
    @State private var isLogsSectionCollapsed: Bool = false
    @State private var account1TasksHeight: CGFloat = 300
    @State private var isAccount1Account2DividerDragging = false

    // MARK: - Selection State
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedTaskAccount: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails: Bool = false
    @State private var selectedEvent: GoogleCalendarEvent?

    init(bulkEditManager: BulkEditManager, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self._navigationManager = ObservedObject(wrappedValue: NavigationManager.shared)
        self._appPrefs = ObservedObject(wrappedValue: AppPreferences.shared)
        self.calendarVM = CalendarViewModel.shared
        self._tasksVM = ObservedObject(wrappedValue: TasksViewModel.shared)
        self._auth = ObservedObject(wrappedValue: GoogleAuthManager.shared)
        self._bulkEditManager = ObservedObject(wrappedValue: bulkEditManager)
        self.onEventTap = onEventTap
        
        // Initialize state variables with stored values from AppPreferences
        self._dayLeftSectionWidth = State(initialValue: AppPreferences.shared.dayViewTimeboxLeftSectionWidth)
        self._tasksSectionHeight = State(initialValue: AppPreferences.shared.dayViewTimeboxTasksSectionHeight)
        self._isTasksDividerDragging = State(initialValue: false)
        self._isLogsSectionCollapsed = State(initialValue: AppPreferences.shared.dayViewTimeboxLogsSectionCollapsed)
        self._account1TasksHeight = State(initialValue: 300)
        self._isAccount1Account2DividerDragging = State(initialValue: false)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let leftSectionWidth = clampedLeftSectionWidth(for: availableWidth)
            let middleSectionWidth = max(0, availableWidth - leftSectionWidth - 8)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    // First column: Timeline + Tasks
                    HStack(alignment: .top, spacing: 0) {
                        // Left section (dynamic width) - TimeboxComponent and Logs
                        leftDaySectionWithDivider(geometry: geometry)
                            .frame(width: leftSectionWidth)

                        // Vertical divider
                        dayVerticalDivider(availableWidth: availableWidth)

                        // Middle section (Tasks only, no journal)
                        middleDaySectionWithoutJournal(geometry: geometry)
                            .frame(width: middleSectionWidth)
                    }
                    .frame(width: availableWidth)

                    // Second column: Journal (swipeable)
                    JournalView(currentDate: $navigationManager.currentDate, embedded: true, layoutType: .expanded)
                        .id(navigationManager.currentDate)
                        .frame(width: max(0, availableWidth - 24))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(12)
                }
            }
            .frame(width: availableWidth, height: geometry.size.height)
            .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayHorizontalScrollID))
            .onAppear {
                dayLeftSectionWidth = leftSectionWidth
            }
            .onChange(of: availableWidth) { _, newWidth in
                dayLeftSectionWidth = clampedLeftSectionWidth(for: newWidth)
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
                    accentColor: account == .account1 ? appPrefs.account1Color : appPrefs.account2Color,
                    account1TaskLists: tasksVM.account1TaskLists,
                    account2TaskLists: tasksVM.account2TaskLists,
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
            let accountKind = ev.ownerAccountKind
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

    private func clampedLeftSectionWidth(for availableWidth: CGFloat) -> CGFloat {
        clampedLeftSectionWidth(dayLeftSectionWidth, for: availableWidth)
    }

    private func clampedLeftSectionWidth(_ proposedWidth: CGFloat, for availableWidth: CGFloat) -> CGFloat {
        let dividerWidth: CGFloat = 8
        let preferredMinimum: CGFloat = 200
        let remainingMinimum: CGFloat = 220
        let usableWidth = max(0, availableWidth - dividerWidth)

        guard usableWidth > 0 else { return 0 }

        if usableWidth < preferredMinimum + remainingMinimum {
            return usableWidth * 0.42
        }

        let maxWidth = min(500, usableWidth - remainingMinimum)
        return min(max(proposedWidth, preferredMinimum), maxWidth)
    }

    // MARK: - Left Section
    private func leftDaySectionWithDivider(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Events section - TimeboxComponent or EventsListComponent based on user preference
            Group {
                if appPrefs.showEventsAsListInDay {
                // Show events as list
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Events")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 8)

                    ScrollView(.vertical, showsIndicators: true) {
                        EventsListComponent(
                            events: getAllEventsForDate(navigationManager.currentDate).sorted { (a, b) in
                                let aDate = a.startTime ?? Date.distantPast
                                let bDate = b.startTime ?? Date.distantPast
                                return aDate < bDate
                            },
                            account1Events: calendarVM.account1Events,
                            account2Events: calendarVM.account2Events,
                            account1Color: appPrefs.account1Color,
                            account2Color: appPrefs.account2Color,
                            onEventTap: { ev in
                                if let onEventTap = onEventTap {
                                    onEventTap(ev)
                                } else {
                                    selectedEvent = ev
                                }
                            },
                            date: navigationManager.currentDate
                        )
                    }
                    .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            } else {
                // Show events in 24-hour timeline (drag-to-reschedule).
                DraggableTimeboxComponent(
                    date: navigationManager.currentDate,
                    events: getAllEventsForDate(navigationManager.currentDate),
                    account1Events: calendarVM.account1Events,
                    account2Events: calendarVM.account2Events,
                    account1Tasks: filteredTasksForDate(tasksVM.account1Tasks, date: navigationManager.currentDate),
                    account2Tasks: filteredTasksForDate(tasksVM.account2Tasks, date: navigationManager.currentDate),
                    account1Color: appPrefs.account1Color,
                    account2Color: appPrefs.account2Color,
                    onEventTap: { ev in
                        if let onEventTap = onEventTap {
                            onEventTap(ev)
                        } else {
                            selectedEvent = ev
                        }
                    },
                    onTaskTap: { task, listId in
                        // Determine account kind
                        let accountKind: GoogleAuthManager.AccountKind = tasksVM.account1Tasks[listId] != nil ? .account1 : .account2
                        selectedTask = task
                        selectedTaskListId = listId
                        selectedTaskAccount = accountKind
                        showingTaskDetails = true
                    },
                    onTaskToggle: { task, listId in
                        // Determine account kind
                        let accountKind: GoogleAuthManager.AccountKind = tasksVM.account1Tasks[listId] != nil ? .account1 : .account2
                        Task {
                            await tasksVM.toggleTaskCompletion(task, in: listId, for: accountKind)
                        }
                    },
                    showAllDaySection: true
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                }
            }
            .id("eventsDisplay-\(appPrefs.showEventsAsListInDay)")

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
                            .padding(.vertical, 4)
                    }
                    .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
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
    private func middleDaySectionWithoutJournal(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Tasks section (always visible)
            tasksSection
                .frame(maxHeight: .infinity) // Take full height since no journal
        }
    }

    private func middleDaySection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Tasks section (always visible)
            tasksSection
                .frame(height: tasksSectionHeight)

            // Draggable divider between Tasks and Journal
            tasksJournalDivider

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
            // Bulk Edit Toolbar (shown when in bulk edit mode)
            if bulkEditManager.state.isActive {
                BulkEditToolbarView(
                    bulkEditManager: bulkEditManager,
                    visibleOpenTaskIds: filteredTasksForDate(tasksVM.account1Tasks, date: navigationManager.currentDate).openTaskIds
                        .union(filteredTasksForDate(tasksVM.account2Tasks, date: navigationManager.currentDate).openTaskIds)
                )
            }

            // Show different layouts based on which accounts are linked
            if auth.isLinked(kind: .account1) && auth.isLinked(kind: .account2) {
                // Both accounts linked - show split view with divider
                // Account 1 Tasks section (top)
                ScrollView(.vertical, showsIndicators: true) {
                    account1TasksSection
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
                .frame(height: account1TasksHeight)
                .background(Color(.systemBackground))

                // Draggable divider between Account 1 and Account 2 tasks
                account1Account2TasksDivider

                // Account 2 Tasks section (bottom)
                ScrollView(.vertical, showsIndicators: true) {
                    account2TasksSection
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
                .frame(maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if auth.isLinked(kind: .account1) {
                // Only account 1 linked - take full height
                ScrollView(.vertical, showsIndicators: true) {
                    account1TasksSection
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
                .frame(maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if auth.isLinked(kind: .account2) {
                // Only account 2 linked - take full height
                ScrollView(.vertical, showsIndicators: true) {
                    account2TasksSection
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
                .frame(maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else {
                // No accounts linked - show empty state
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Link Your Google Account")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Connect your Google account to view and manage your tasks")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
    }
    
    // MARK: - Task Sections
    private var account1TasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let account1Filtered = filteredTasksForDate(tasksVM.account1Tasks, date: navigationManager.currentDate)
            if auth.isLinked(kind: .account1) {
                TasksComponent(
                    taskLists: tasksVM.account1TaskLists,
                    tasksDict: account1Filtered,
                    accentColor: appPrefs.account1Color,
                    accountType: .account1,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksVM.toggleTaskCompletion(task, in: listId, for: .account1)
                        }
                    },
                    onTaskDetails: { task, listId in
                        selectedTask = task
                        selectedTaskListId = listId
                        selectedTaskAccount = .account1
                        showingTaskDetails = true
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: .account1)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksVM.updateTaskListOrder(newOrder, for: .account1)
                        }
                    },
                    hideDueDateTag: false,
                    showEmptyState: true,
                    horizontalCards: false,
                    isSingleDayView: true,
                    showTaskStartTime: true,
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private var account2TasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let account2Filtered = filteredTasksForDate(tasksVM.account2Tasks, date: navigationManager.currentDate)
            if auth.isLinked(kind: .account2) {
                TasksComponent(
                    taskLists: tasksVM.account2TaskLists,
                    tasksDict: account2Filtered,
                    accentColor: appPrefs.account2Color,
                    accountType: .account2,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksVM.toggleTaskCompletion(task, in: listId, for: .account2)
                        }
                    },
                    onTaskDetails: { task, listId in
                        selectedTask = task
                        selectedTaskListId = listId
                        selectedTaskAccount = .account2
                        showingTaskDetails = true
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: .account2)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksVM.updateTaskListOrder(newOrder, for: .account2)
                        }
                    },
                    hideDueDateTag: false,
                    showEmptyState: true,
                    horizontalCards: false,
                    isSingleDayView: true,
                    showTaskStartTime: true,
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private func dayVerticalDivider(availableWidth: CGFloat) -> some View {
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
                        dayLeftSectionWidth = clampedLeftSectionWidth(newWidth, for: availableWidth)
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

    private var account1Account2TasksDivider: some View {
        Rectangle()
            .fill(isAccount1Account2DividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isAccount1Account2DividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isAccount1Account2DividerDragging = true
                        let newHeight = account1TasksHeight + value.translation.height
                        let minHeight: CGFloat = 150
                        let maxHeight: CGFloat = 600
                        account1TasksHeight = max(minHeight, min(maxHeight, newHeight))
                    }
                    .onEnded { _ in
                        isAccount1Account2DividerDragging = false
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
    DayViewNewExpanded(bulkEditManager: BulkEditManager())
}
