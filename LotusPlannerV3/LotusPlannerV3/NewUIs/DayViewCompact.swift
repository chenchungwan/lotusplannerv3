import SwiftUI

struct DayViewCompact: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    private let onEventTap: ((GoogleCalendarEvent) -> Void)?

    // Task details state
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedTaskAccount: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails: Bool = false

    // Draggable divider state between Tasks (top) and Timeline/Logs+Journal (bottom)
    @State private var tasksSectionHeight: CGFloat
    @State private var isTopDividerDragging: Bool = false

    // Draggable divider state between Timeline+Logs (left) and Journal (right)
    @State private var leftColumnWidth: CGFloat
    @State private var isMiddleDividerDragging: Bool = false

    // Draggable divider within left column between Timeline and Logs
    @State private var leftTopHeight: CGFloat
    @State private var isLeftInnerDividerDragging: Bool = false

    init(onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self._navigationManager = ObservedObject(wrappedValue: NavigationManager.shared)
        self._appPrefs = ObservedObject(wrappedValue: AppPreferences.shared)
        self.calendarVM = DataManager.shared.calendarViewModel
        self._tasksVM = ObservedObject(wrappedValue: DataManager.shared.tasksViewModel)
        self._auth = ObservedObject(wrappedValue: GoogleAuthManager.shared)
        self.onEventTap = onEventTap
        
        // Initialize divider positions from AppPreferences
        self._tasksSectionHeight = State(initialValue: AppPreferences.shared.dayViewCompactTasksHeight)
        self._leftColumnWidth = State(initialValue: AppPreferences.shared.dayViewCompactLeftColumnWidth)
        self._leftTopHeight = State(initialValue: AppPreferences.shared.dayViewCompactLeftTopHeight)
    }

    var body: some View {
        GeometryReader { geo in
            let dividerH: CGFloat = 8
            let outerPad: CGFloat = 24 // 12 top + 12 bottom
            let availableH: CGFloat = max(0, geo.size.height - outerPad)
            let minTasks: CGFloat = 160
            let minBottom: CGFloat = 260 // leave reasonable space for bottom section
            let clampedTasks = max(minTasks, min(tasksSectionHeight, availableH - dividerH - minBottom))
            let bottomH = max(minBottom, availableH - clampedTasks - dividerH)

            VStack(spacing: 12) {
                // 1) Tasks (personal + professional)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tasks")
                        .font(.headline)
                        .padding(.horizontal, 8)
                    
                    HStack(alignment: .top, spacing: 12) {
                    let personalTasks = filteredTasksDictForDay(tasksVM.personalTasks, on: navigationManager.currentDate)
                    let professionalTasks = filteredTasksDictForDay(tasksVM.professionalTasks, on: navigationManager.currentDate)
                    let hasPersonalTasks = !personalTasks.isEmpty && auth.isLinked(kind: .personal)
                    let hasProfessionalTasks = !professionalTasks.isEmpty && auth.isLinked(kind: .professional)
                    let hasAnyLinkedAccount = auth.isLinked(kind: .personal) || auth.isLinked(kind: .professional)
                    
                    if hasPersonalTasks {
                        TasksComponent(
                            taskLists: tasksVM.personalTaskLists,
                            tasksDict: personalTasks,
                            accentColor: appPrefs.personalColor,
                            accountType: .personal,
                            onTaskToggle: { task, listId in
                                let viewModel = tasksVM // Capture the view model
                                Task { await viewModel.toggleTaskCompletion(task, in: listId, for: .personal) }
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
                            showEmptyState: true,
                            horizontalCards: false,
                            isSingleDayView: true
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                    }

                    if hasProfessionalTasks {
                        TasksComponent(
                            taskLists: tasksVM.professionalTaskLists,
                            tasksDict: professionalTasks,
                            accentColor: appPrefs.professionalColor,
                            accountType: .professional,
                            onTaskToggle: { task, listId in
                                let viewModel = tasksVM // Capture the view model
                                Task { await viewModel.toggleTaskCompletion(task, in: listId, for: .professional) }
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
                            showEmptyState: true,
                            horizontalCards: false,
                            isSingleDayView: true
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    
                    if !hasPersonalTasks && !hasProfessionalTasks {
                        if !hasAnyLinkedAccount {
                            // No accounts linked - show link account UI
                            Button(action: { NavigationManager.shared.showSettings() }) {
                                VStack(spacing: 16) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                    
                                    Text("Link Your Google Account")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    
                                    Text("Connect your Google account to view and manage your calendar events and tasks")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 40)
                                .padding(.horizontal, 20)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Accounts linked but no tasks
                            Text("No tasks for today")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        }
                    }
                    }
                }
                .frame(height: clampedTasks)

                // Draggable divider between Tasks and Timeline/Logs + Journal
                Rectangle()
                    .fill(isTopDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                    .frame(height: 8)
                    .overlay(
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundColor(isTopDividerDragging ? .white : .gray)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isTopDividerDragging = true
                                let newHeight = clampedTasks + value.translation.height
                                let maxTasksDyn: CGFloat = availableH - dividerH - minBottom
                                tasksSectionHeight = max(minTasks, min(maxTasksDyn, newHeight))
                            }
                            .onEnded { _ in 
                                isTopDividerDragging = false
                                appPrefs.updateDayViewCompactTasksHeight(tasksSectionHeight)
                            }
                    )

                // 2) HStack: VStack(Timeline, Logs) | Journal
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Events")
                                .font(.headline)
                                .padding(.horizontal, 8)
                            
                            Group {
                                if appPrefs.showEventsAsListInDay {
                                    EventsListComponent(
                                        events: filteredEventsForDay(navigationManager.currentDate),
                                        personalEvents: calendarVM.personalEvents,
                                        professionalEvents: calendarVM.professionalEvents,
                                        personalColor: appPrefs.personalColor,
                                        professionalColor: appPrefs.professionalColor,
                                        onEventTap: { ev in onEventTap?(ev) }
                                    )
                                } else {
                                    TimelineComponent(
                                        date: navigationManager.currentDate,
                                        events: filteredEventsForDay(navigationManager.currentDate),
                                        personalEvents: filteredPersonalEventsForDay(navigationManager.currentDate),
                                        professionalEvents: filteredProfessionalEventsForDay(navigationManager.currentDate),
                                        personalColor: appPrefs.personalColor,
                                        professionalColor: appPrefs.professionalColor,
                                        onEventTap: { ev in onEventTap?(ev) }
                                    )
                                }
                            }
                        }
                        // Clamp top (Timeline/Events list) height within left column
                        .frame(maxWidth: .infinity,
                               maxHeight: appPrefs.showAnyLogs ? max(200, min(leftTopHeight, bottomH - dividerH - 160)) : .infinity,
                               alignment: .top)

                        if appPrefs.showAnyLogs {
                            // Draggable divider between Timeline and Logs inside left column
                            Rectangle()
                                .fill(isLeftInnerDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                                .frame(height: 8)
                                .overlay(
                                    Image(systemName: "line.3.horizontal")
                                        .font(.caption)
                                        .foregroundColor(isLeftInnerDividerDragging ? .white : .gray)
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            isLeftInnerDividerDragging = true
                                            // dynamic bounds based on current bottomH
                                            let minTop: CGFloat = 200
                                            let minBottomLeft: CGFloat = 160
                                            let maxTop = bottomH - dividerH - minBottomLeft
                                            let newHeight = max(minTop, min(maxTop, leftTopHeight + value.translation.height))
                                            leftTopHeight = newHeight
                                        }
                                        .onEnded { _ in 
                                            isLeftInnerDividerDragging = false
                                            appPrefs.updateDayViewCompactLeftTopHeight(leftTopHeight)
                                        }
                                )

                            // Logs vertically: weight, workout, food
                            VStack(alignment: .leading, spacing: 6) {

                                
                                LogsComponent(currentDate: navigationManager.currentDate, horizontal: false)
                            }
                            .frame(height: max(160, bottomH - dividerH - max(200, min(leftTopHeight, bottomH - dividerH - 160))))
                        }
                    }
                    // Clamp left column width based on available width
                    .frame(width: appPrefs.showJournal ? max(180, min(leftColumnWidth, max(220, geo.size.width - 240))) : .infinity, alignment: .top)

                    if appPrefs.showJournal {
                        // Draggable vertical divider between left column and journal
                        Rectangle()
                            .fill(isMiddleDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                            .frame(width: 8)
                            .overlay(
                                Image(systemName: "line.3.vertical")
                                    .font(.caption)
                                    .foregroundColor(isMiddleDividerDragging ? .white : .gray)
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        isMiddleDividerDragging = true
                                        let minWidth: CGFloat = 180
                                        let maxWidth: CGFloat = max(220, geo.size.width - 240)
                                        let newWidth = leftColumnWidth + value.translation.width
                                        leftColumnWidth = max(minWidth, min(maxWidth, newWidth))
                                    }
                                    .onEnded { _ in 
                                        isMiddleDividerDragging = false
                                        appPrefs.updateDayViewCompactLeftColumnWidth(leftColumnWidth)
                                    }
                            )

                        JournalView(currentDate: navigationManager.currentDate, embedded: true, layoutType: .expanded)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .id(navigationManager.currentDate)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.bottom, 8)
                    }
                }
                .frame(height: bottomH)
            }
            .ignoresSafeArea(edges: .top)
            .padding(12)
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
                        let viewModel = tasksVM // Capture the view model
                        Task {
                            await viewModel.updateTask(updatedTask, in: listId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onDelete: {
                        let viewModel = tasksVM // Capture the view model
                        Task {
                            await viewModel.deleteTask(t, from: listId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onMove: { updatedTask, targetListId in
                        let viewModel = tasksVM // Capture the view model
                        Task {
                            await viewModel.moveTask(updatedTask, from: listId, to: targetListId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                        let viewModel = tasksVM // Capture the view model
                        Task {
                            await viewModel.crossAccountMoveTask(updatedTask, from: (account, listId), to: (targetAccount, targetListId))
                        }
                        showingTaskDetails = false
                    },
                    isNew: false
                )
            }
        }
    }
}

// MARK: - Day Filters
extension DayViewCompact {
    private func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.mondayFirst.isDate(lhs, inSameDayAs: rhs)
    }

    private func filteredEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        let all = calendarVM.personalEvents + calendarVM.professionalEvents
        return all.filter { ev in
            if let start = ev.startTime { return isSameDay(start, date) }
            return ev.isAllDay
        }
    }

    private func filteredPersonalEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        calendarVM.personalEvents.filter { ev in
            if let start = ev.startTime { return isSameDay(start, date) }
            return ev.isAllDay
        }
    }

    private func filteredProfessionalEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        calendarVM.professionalEvents.filter { ev in
            if let start = ev.startTime { return isSameDay(start, date) }
            return ev.isAllDay
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
                        return isSameDay(comp, date)
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
    DayViewCompact()
}
