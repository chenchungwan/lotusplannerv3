import SwiftUI

struct DayViewExpandedTwo: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    private let onEventTap: ((GoogleCalendarEvent) -> Void)?

    // Divider state between top row and logs
    @State private var topRowHeight: CGFloat = UIScreen.main.bounds.height * 0.5
    @State private var isTopDividerDragging: Bool = false

    // Divider state between timeline (left) and tasks (right)
    @State private var leftTimelineWidth: CGFloat = UIScreen.main.bounds.width * 0.25
    @State private var isLeftDividerDragging: Bool = false

    // Divider state between logs and notes
    @State private var logsHeight: CGFloat = UIScreen.main.bounds.height * 0.25

    // MARK: - Selection State
    @State private var selectedEvent: GoogleCalendarEvent?
    @State private var showingEventDetails: Bool = false
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedTaskAccount: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails: Bool = false

    init(onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self._navigationManager = ObservedObject(wrappedValue: NavigationManager.shared)
        self._appPrefs = ObservedObject(wrappedValue: AppPreferences.shared)
        self.calendarVM = DataManager.shared.calendarViewModel
        self._tasksVM = ObservedObject(wrappedValue: DataManager.shared.tasksViewModel)
        self._auth = ObservedObject(wrappedValue: GoogleAuthManager.shared)
        self.onEventTap = onEventTap
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 0) {
                // Left Column: Timeline + Tasks + Logs
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 12) {
                            // 1) Timeline + Tasks side-by-side
                            HStack(alignment: .top, spacing: 12) {
                                // Timeline or Events List (based on preference)
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
                                            onEventTap: { event in
                                                onEventTap?(event)
                                            }
                                        )
                                    }
                                }
                                .frame(
                                    width: leftTimelineWidth,
                                    height: appPrefs.showAnyLogs ? topRowHeight : UIScreen.main.bounds.height - 24,
                                    alignment: .topLeading
                                )

                                // Vertical draggable divider between timeline and tasks
                                Rectangle()
                                    .fill(isLeftDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: appPrefs.showAnyLogs ? topRowHeight : UIScreen.main.bounds.height - 24)
                                    .overlay(
                                        Image(systemName: "line.3.vertical")
                                            .font(.caption)
                                            .foregroundColor(isLeftDividerDragging ? .white : .gray)
                                    )
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                isLeftDividerDragging = true
                                                let newWidth = leftTimelineWidth + value.translation.width
                                                let minWidth: CGFloat = 150
                                                let maxWidth: CGFloat = max(200, UIScreen.main.bounds.width - 300)
                                                leftTimelineWidth = max(minWidth, min(maxWidth, newWidth))
                                            }
                                            .onEnded { _ in
                                                isLeftDividerDragging = false
                                            }
                                    )

                                // Tasks (two side-by-side columns)
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
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: appPrefs.showAnyLogs ? topRowHeight : UIScreen.main.bounds.height - 24,
                                    alignment: .top
                                )
                            }

                            if appPrefs.showAnyLogs {
                                // Draggable divider between top row and logs
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
                                                let newHeight = topRowHeight + value.translation.height
                                                let minHeight: CGFloat = 200
                                                let maxHeight: CGFloat = max(200, UIScreen.main.bounds.height - 300)
                                                topRowHeight = max(minHeight, min(maxHeight, newHeight))
                                            }
                                            .onEnded { _ in
                                                isTopDividerDragging = false
                                            }
                                    )

                                // 2) Logs laid out side-by-side (weight, workout, food)
                                LogsComponent(currentDate: navigationManager.currentDate, horizontal: true)
                                    .frame(height: logsHeight)
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                    .padding(12)
                }
                .frame(width: UIScreen.main.bounds.width)
                
                // Right Column: Journal
                VStack(alignment: .leading, spacing: 6) {
                    Text("Journal")
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .padding(.top, 12)
                    JournalView(currentDate: navigationManager.currentDate, embedded: true, layoutType: .expanded)
                }
                .id(navigationManager.currentDate)
                .frame(width: UIScreen.main.bounds.width*0.95)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(12)
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
extension DayViewExpandedTwo {
    private func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.mondayFirst.isDate(lhs, inSameDayAs: rhs)
    }

    private func filteredEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        let all = calendarVM.personalEvents + calendarVM.professionalEvents
        return all.filter { ev in
            if let start = ev.startTime { return isSameDay(start, date) }
            return ev.isAllDay // keep all-day events if date unknown
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

    // Removed custom events list; using EventsListComponent instead
}

#Preview {
    DayViewExpandedTwo()
}


