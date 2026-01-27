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
        self.calendarVM = DataManager.shared.calendarViewModel
        self._tasksVM = ObservedObject(wrappedValue: DataManager.shared.tasksViewModel)
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
            // Main Content: Events + Tasks (left) | Journal (right)
            HStack(spacing: 0) {
                // Left Column: Events + Tasks + Logs with draggable divider
                leftColumn(geometry: geometry)
                    .frame(width: columnDividerPosition)

                // Draggable divider between columns
                columnDivider(geometry: geometry)

                // Right Column: Journal
                journalColumn
                    .frame(maxWidth: .infinity)
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
                    }
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

    private func columnDivider(geometry: GeometryProxy) -> some View {
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
                        let minWidth: CGFloat = 200
                        let maxWidth: CGFloat = geometry.size.width - 200
                        let newWidth = columnDividerPosition + value.translation.width
                        columnDividerPosition = max(minWidth, min(maxWidth, newWidth))
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
                                personalEvents: calendarVM.personalEvents,
                                professionalEvents: calendarVM.professionalEvents,
                                personalColor: appPrefs.personalColor,
                                professionalColor: appPrefs.professionalColor,
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
                    }
                } else {
                    // Show TimeboxComponent (timeline view)
                    TimeboxComponent(
                        date: navigationManager.currentDate,
                        events: filteredEventsForDay(navigationManager.currentDate),
                        personalEvents: calendarVM.personalEvents,
                        professionalEvents: calendarVM.professionalEvents,
                        personalTasks: filteredTasksDictForDay(tasksVM.personalTasks, on: navigationManager.currentDate),
                        professionalTasks: filteredTasksDictForDay(tasksVM.professionalTasks, on: navigationManager.currentDate),
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
                        showAllDaySection: false
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
                BulkEditToolbarView(bulkEditManager: bulkEditManager)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    // Personal Tasks
                    let personalTasks = filteredTasksDictForDay(tasksVM.personalTasks, on: navigationManager.currentDate)
                    if auth.isLinked(kind: .personal) && !personalTasks.isEmpty {
                        TasksComponent(
                            taskLists: tasksVM.personalTaskLists,
                            tasksDict: personalTasks,
                            accentColor: appPrefs.personalColor,
                            accountType: .personal,
                            onTaskToggle: { task, listId in
                                Task { await tasksVM.toggleTaskCompletion(task, in: listId, for: .personal) }
                            },
                            onTaskDetails: { task, listId in
                                selectedTask = task
                                selectedTaskListId = listId
                                selectedTaskAccount = .personal
                                showingTaskDetails = true
                            },
                            onListRename: { listId, newName in
                                Task { await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: .personal) }
                            },
                            onOrderChanged: { newOrder in
                                Task { await tasksVM.updateTaskListOrder(newOrder, for: .personal) }
                            },
                            hideDueDateTag: false,
                            showEmptyState: false,
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

                    // Professional Tasks
                    let professionalTasks = filteredTasksDictForDay(tasksVM.professionalTasks, on: navigationManager.currentDate)
                    if auth.isLinked(kind: .professional) && !professionalTasks.isEmpty {
                        TasksComponent(
                            taskLists: tasksVM.professionalTaskLists,
                            tasksDict: professionalTasks,
                            accentColor: appPrefs.professionalColor,
                            accountType: .professional,
                            onTaskToggle: { task, listId in
                                Task { await tasksVM.toggleTaskCompletion(task, in: listId, for: .professional) }
                            },
                            onTaskDetails: { task, listId in
                                selectedTask = task
                                selectedTaskListId = listId
                                selectedTaskAccount = .professional
                                showingTaskDetails = true
                            },
                            onListRename: { listId, newName in
                                Task { await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: .professional) }
                            },
                            onOrderChanged: { newOrder in
                                Task { await tasksVM.updateTaskListOrder(newOrder, for: .professional) }
                            },
                            hideDueDateTag: false,
                            showEmptyState: false,
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

                    // Empty state if no tasks
                    if (!auth.isLinked(kind: .personal) || personalTasks.isEmpty) &&
                       (!auth.isLinked(kind: .professional) || professionalTasks.isEmpty) {
                        if !auth.isLinked(kind: .personal) && !auth.isLinked(kind: .professional) {
                            // No accounts linked
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
                        } else {
                            Text("No tasks for today")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(24)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Helper Functions

    private func filteredEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        let allEvents = calendarVM.personalEvents + calendarVM.professionalEvents
        return allEvents.filter { event in
            guard let eventStart = event.startTime else { return false }
            return calendar.isDate(eventStart, inSameDayAs: date)
        }
    }

    private func filteredPersonalEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        return calendarVM.personalEvents.filter { event in
            guard let eventStart = event.startTime else { return false }
            return calendar.isDate(eventStart, inSameDayAs: date)
        }
    }

    private func filteredProfessionalEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        return calendarVM.professionalEvents.filter { event in
            guard let eventStart = event.startTime else { return false }
            return calendar.isDate(eventStart, inSameDayAs: date)
        }
    }

    private func filteredTasksDictForDay(_ dict: [String: [GoogleTask]], on date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

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
                    return dueDate >= startOfDay && dueDate < endOfDay
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
