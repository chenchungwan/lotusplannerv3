//
//  DayViewNewCompact.swift
//  LotusPlannerV3
//
//  Compact day view layout with collapsible logs, journal, events, and tasks
//

import SwiftUI

struct DayViewNewCompact: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    @ObservedObject private var bulkEditManager: BulkEditManager
    private let onEventTap: ((GoogleCalendarEvent) -> Void)?

    // Divider state between events and tasks
    @State private var eventsTasksDividerPosition: CGFloat
    @State private var isEventTaskDividerDragging: Bool = false

    // Divider state between columns (events/tasks and journal)
    @State private var columnDividerPosition: CGFloat
    @State private var isColumnDividerDragging: Bool = false

    // Logs section collapsible state (defaults to collapsed)
    @State private var logsExpanded: Bool

    // Task selection state
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

        // Initialize divider positions and collapsed state from AppPreferences
        self._eventsTasksDividerPosition = State(initialValue: AppPreferences.shared.dayViewStandardEventTaskDividerPosition)
        self._columnDividerPosition = State(initialValue: AppPreferences.shared.dayViewStandardColumnDividerPosition)
        self._logsExpanded = State(initialValue: !AppPreferences.shared.dayViewStandardLogsSectionCollapsed)
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let leftColumnWidth = clampedColumnDividerPosition(for: availableWidth)

            // Main Content: Events + Tasks (left) | Journal (right)
            HStack(spacing: 0) {
                // Left Column: Events + Tasks + Logs with draggable divider
                leftColumn(geometry: geometry)
                    .frame(width: leftColumnWidth)

                // Draggable divider between columns
                columnDivider(availableWidth: availableWidth)

                // Right Column: Journal
                journalColumn
                    .frame(maxWidth: .infinity)
            }
            .frame(width: availableWidth, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .onAppear {
                columnDividerPosition = leftColumnWidth
            }
            .onChange(of: availableWidth) { _, newWidth in
                columnDividerPosition = clampedColumnDividerPosition(for: newWidth)
            }
        }
        .background(Color(.systemBackground))
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
                    }
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

    // MARK: - Logs Section

    private var logsSection: some View {
        VStack(spacing: 0) {
            Divider()

            // Logs content (collapsible)
            if logsExpanded {
                // Collapse button
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            logsExpanded = false
                            appPrefs.updateDayViewStandardLogsSectionCollapsed(true)
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

                ScrollView(.vertical, showsIndicators: true) {
                    LogsComponent(currentDate: navigationManager.currentDate, horizontal: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                // Expand button when collapsed
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        logsExpanded = true
                        appPrefs.updateDayViewStandardLogsSectionCollapsed(false)
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Journal Column

    private var journalColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            JournalView(currentDate: .constant(navigationManager.currentDate), embedded: true, layoutType: .compact)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Column Divider

    private func clampedColumnDividerPosition(for availableWidth: CGFloat) -> CGFloat {
        clampedColumnDividerPosition(columnDividerPosition, for: availableWidth)
    }

    private func clampedColumnDividerPosition(_ proposedWidth: CGFloat, for availableWidth: CGFloat) -> CGFloat {
        let dividerWidth: CGFloat = 8
        let preferredMinimum: CGFloat = 200
        let remainingMinimum: CGFloat = 220
        let usableWidth = max(0, availableWidth - dividerWidth)

        guard usableWidth > 0 else { return 0 }

        if usableWidth < preferredMinimum + remainingMinimum {
            return usableWidth * 0.5
        }

        let maxWidth = usableWidth - remainingMinimum
        return min(max(proposedWidth, preferredMinimum), maxWidth)
    }

    private func columnDivider(availableWidth: CGFloat) -> some View {
        Rectangle()
            .fill(isColumnDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isColumnDividerDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isColumnDividerDragging = true
                        let newWidth = columnDividerPosition + value.translation.width
                        columnDividerPosition = clampedColumnDividerPosition(newWidth, for: availableWidth)
                    }
                    .onEnded { _ in
                        isColumnDividerDragging = false
                        appPrefs.updateDayViewStandardColumnDividerPosition(columnDividerPosition)
                    }
            )
    }

    // MARK: - Left Column (Events + Tasks + Logs)

    private func leftColumn(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Events Section
            eventsSection
                .frame(height: eventsTasksDividerPosition)

            // Draggable divider
            eventTaskDivider(geometry: geometry)

            // Tasks Section
            tasksSection
                .frame(maxHeight: .infinity)

            // Collapsible Logs Section (at bottom of left column)
            if appPrefs.showAnyLogs {
                logsSection
            }
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if appPrefs.showEventsAsListInDay {
                    // Show EventsListComponent (list view)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Events")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)

                        ScrollView(.vertical, showsIndicators: true) {
                            EventsListComponent(
                                events: filteredEventsForDay(navigationManager.currentDate).sorted { (e1, e2) in
                                    guard let t1 = e1.startTime, let t2 = e2.startTime else { return false }
                                    return t1 < t2
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
                } else {
                    // Show drag-to-reschedule timeline.
                    DraggableTimeboxComponent(
                        date: navigationManager.currentDate,
                        events: filteredEventsForDay(navigationManager.currentDate),
                        account1Events: calendarVM.account1Events,
                        account2Events: calendarVM.account2Events,
                        account1Tasks: filteredTasksDictForDay(tasksVM.account1Tasks, on: navigationManager.currentDate),
                        account2Tasks: filteredTasksDictForDay(tasksVM.account2Tasks, on: navigationManager.currentDate),
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
        }
        .background(Color(.systemBackground))
    }

    private func eventTaskDivider(geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(isEventTaskDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isEventTaskDividerDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isEventTaskDividerDragging = true
                        let minHeight: CGFloat = 100
                        let maxHeight: CGFloat = geometry.size.height - 200
                        let newHeight = eventsTasksDividerPosition + value.translation.height
                        eventsTasksDividerPosition = max(minHeight, min(maxHeight, newHeight))
                    }
                    .onEnded { _ in
                        isEventTaskDividerDragging = false
                        appPrefs.updateDayViewStandardEventTaskDividerPosition(eventsTasksDividerPosition)
                    }
            )
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Bulk Edit Toolbar (shown when in bulk edit mode)
            if bulkEditManager.state.isActive {
                BulkEditToolbarView(
                    bulkEditManager: bulkEditManager,
                    visibleOpenTaskIds: filteredTasksDictForDay(tasksVM.account1Tasks, on: navigationManager.currentDate).openTaskIds
                        .union(filteredTasksDictForDay(tasksVM.account2Tasks, on: navigationManager.currentDate).openTaskIds)
                )
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    // Account 1 Tasks
                    let account1Tasks = filteredTasksDictForDay(tasksVM.account1Tasks, on: navigationManager.currentDate)
                    if auth.isLinked(kind: .account1) {
                        TasksComponent(
                            taskLists: tasksVM.account1TaskLists,
                            tasksDict: account1Tasks,
                            accentColor: appPrefs.account1Color,
                            accountType: .account1,
                            onTaskToggle: { task, listId in
                                Task { await tasksVM.toggleTaskCompletion(task, in: listId, for: .account1) }
                            },
                            onTaskDetails: { task, listId in
                                selectedTask = task
                                selectedTaskListId = listId
                                selectedTaskAccount = .account1
                                showingTaskDetails = true
                            },
                            onListRename: { listId, newName in
                                Task { await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: .account1) }
                            },
                            onOrderChanged: { newOrder in
                                Task { await tasksVM.updateTaskListOrder(newOrder, for: .account1) }
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
                    }

                    // Account 2 Tasks
                    let account2Tasks = filteredTasksDictForDay(tasksVM.account2Tasks, on: navigationManager.currentDate)
                    if auth.isLinked(kind: .account2) {
                        TasksComponent(
                            taskLists: tasksVM.account2TaskLists,
                            tasksDict: account2Tasks,
                            accentColor: appPrefs.account2Color,
                            accountType: .account2,
                            onTaskToggle: { task, listId in
                                Task { await tasksVM.toggleTaskCompletion(task, in: listId, for: .account2) }
                            },
                            onTaskDetails: { task, listId in
                                selectedTask = task
                                selectedTaskListId = listId
                                selectedTaskAccount = .account2
                                showingTaskDetails = true
                            },
                            onListRename: { listId, newName in
                                Task { await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: .account2) }
                            },
                            onOrderChanged: { newOrder in
                                Task { await tasksVM.updateTaskListOrder(newOrder, for: .account2) }
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
                    }

                    // Empty state if no accounts linked
                    if !auth.isLinked(kind: .account1) && !auth.isLinked(kind: .account2) {
                        Button(action: { NavigationManager.shared.showSettings() }) {
                            VStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("Link Your Google Account")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Connect to view and manage tasks")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                            }
                            .padding(24)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(8)
            }
            .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Helper Functions

    private func filteredEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        let allEvents = calendarVM.account1Events + calendarVM.account2Events
        return allEvents.filter { event in
            guard let eventStart = event.startTime else { return false }
            return calendar.isDate(eventStart, inSameDayAs: date)
        }
    }

    private func filteredAccount1EventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        return calendarVM.account1Events.filter { event in
            guard let eventStart = event.startTime else { return false }
            return calendar.isDate(eventStart, inSameDayAs: date)
        }
    }

    private func filteredAccount2EventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        return calendarVM.account2Events.filter { event in
            guard let eventStart = event.startTime else { return false }
            return calendar.isDate(eventStart, inSameDayAs: date)
        }
    }

    private func filteredTasksDictForDay(_ dict: [String: [GoogleTask]], on date: Date) -> [String: [GoogleTask]] {
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
                        return calendar.isDate(comp, inSameDayAs: date)
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
            if !filtered.isEmpty {
                result[listId] = filtered
            }
        }
        return result
    }
}

#Preview {
    DayViewNewCompact(bulkEditManager: BulkEditManager())
}
