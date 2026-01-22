//
//  DayViewStandard.swift
//  LotusPlannerV3
//
//  Standard day view layout with collapsible logs, journal, events, and tasks
//

import SwiftUI

struct DayViewStandard: View {
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

    // Logs section collapsible state
    @State private var logsExpanded: Bool = true

    // Task selection state
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

        // Initialize divider position (40% for events, 60% for tasks by default)
        self._eventsTasksDividerPosition = State(initialValue: AppPreferences.shared.dayViewStandardEventTaskDividerPosition)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Collapsible Logs Section
                if appPrefs.showAnyLogs {
                    logsSection
                }

                // Main Content: Journal (left) | Events + Tasks (right)
                HStack(spacing: 0) {
                    // Left Column: Journal
                    journalColumn
                        .frame(width: geometry.size.width * 0.4)

                    Divider()
                        .frame(width: 1)

                    // Right Column: Events + Tasks with draggable divider
                    rightColumn(geometry: geometry)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
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
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        VStack(spacing: 0) {
            // Header with collapse button
            HStack {
                Text("Daily Logs")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        logsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: logsExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))

            // Logs content (collapsible)
            if logsExpanded {
                LogsComponent(currentDate: navigationManager.currentDate, horizontal: true)
                    .padding(8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
        }
    }

    // MARK: - Journal Column

    private var journalColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Journal")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))

            JournalView(currentDate: .constant(navigationManager.currentDate), embedded: true, layoutType: .compact)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Right Column (Events + Tasks)

    private func rightColumn(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Events Section
            eventsSection
                .frame(height: eventsTasksDividerPosition)

            // Draggable divider
            eventTaskDivider(geometry: geometry)

            // Tasks Section
            tasksSection
                .frame(maxHeight: .infinity)
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Events")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))

            ScrollView(.vertical, showsIndicators: true) {
                if appPrefs.showEventsAsListInDay {
                    EventsListComponent(
                        events: filteredEventsForDay(navigationManager.currentDate),
                        personalEvents: calendarVM.personalEvents,
                        professionalEvents: calendarVM.professionalEvents,
                        personalColor: appPrefs.personalColor,
                        professionalColor: appPrefs.professionalColor,
                        onEventTap: { ev in onEventTap?(ev) },
                        date: navigationManager.currentDate
                    )
                    .padding(8)
                } else {
                    TimelineComponent(
                        date: navigationManager.currentDate,
                        events: filteredEventsForDay(navigationManager.currentDate),
                        personalEvents: filteredPersonalEventsForDay(navigationManager.currentDate),
                        professionalEvents: filteredProfessionalEventsForDay(navigationManager.currentDate),
                        personalColor: appPrefs.personalColor,
                        professionalColor: appPrefs.professionalColor,
                        onEventTap: { event in
                            onEventTap?(event)
                        }
                    )
                    .padding(8)
                }
            }
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

            HStack {
                Text("Tasks")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))

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
    DayViewStandard(bulkEditManager: BulkEditManager())
}
