import SwiftUI

struct DayViewMobile: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    private let onEventTap: ((GoogleCalendarEvent) -> Void)?
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // MARK: - Selection State
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
    
    // MARK: - Adaptive Layout Properties
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }
    
    private var adaptiveSectionSpacing: CGFloat {
        2 // Minimize spacing between components for all devices
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: adaptiveSectionSpacing) {
                    // Events list (always list in Mobile layout)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Events")
                            .font(.headline)
                            .padding(.horizontal, adaptivePadding)
                        EventsListComponent(
                            events: filteredEventsForDay(navigationManager.currentDate),
                            personalEvents: calendarVM.personalEvents,
                            professionalEvents: calendarVM.professionalEvents,
                            personalColor: appPrefs.personalColor,
                            professionalColor: appPrefs.professionalColor,
                            onEventTap: { ev in onEventTap?(ev) },
                            date: navigationManager.currentDate
                        )
                    }
                
                // Personal tasks
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personal Tasks")
                        .font(.headline)
                        .foregroundColor(appPrefs.personalColor)
                        .padding(.horizontal, adaptivePadding)
                    
                    let personalTasks = filteredTasksDictForDay(tasksVM.personalTasks, on: navigationManager.currentDate)
                    let hasPersonalTasks = !personalTasks.isEmpty && auth.isLinked(kind: .personal)
                    let hasAnyLinkedAccount = auth.isLinked(kind: .personal) || auth.isLinked(kind: .professional)
                    
                    if hasPersonalTasks {
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
                            showEmptyState: false, // We handle empty state ourselves
                            horizontalCards: false,
                            isSingleDayView: true
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                    } else if !hasAnyLinkedAccount {
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
                        // Account linked but no tasks
                        Text("No tasks")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                
                // Professional tasks
                VStack(alignment: .leading, spacing: 2) {
                    Text("Professional Tasks")
                        .font(.headline)
                        .foregroundColor(appPrefs.professionalColor)
                        .padding(.horizontal, adaptivePadding)
                    
                    let professionalTasks = filteredTasksDictForDay(tasksVM.professionalTasks, on: navigationManager.currentDate)
                    let hasProfessionalTasks = !professionalTasks.isEmpty && auth.isLinked(kind: .professional)
                    let hasAnyLinkedAccount = auth.isLinked(kind: .personal) || auth.isLinked(kind: .professional)
                    
                    if hasProfessionalTasks {
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
                            showEmptyState: false, // We handle empty state ourselves
                            horizontalCards: false,
                            isSingleDayView: true
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                    } else if !hasAnyLinkedAccount {
                        // No accounts linked - show link account UI (only show once)
                        EmptyView() // This will be handled by the personal tasks section
                    } else {
                        // Account linked but no tasks
                        Text("No tasks")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                
                // Logs (only if any logs are enabled)
                if appPrefs.showAnyLogs {
                    VStack(alignment: .leading, spacing: 2) {
                        LogsComponent(currentDate: navigationManager.currentDate, horizontal: false, allowInternalScrolling: false)
                    }
                }
                
                // Journal
                VStack(alignment: .leading, spacing: 2) {
                    JournalView(currentDate: $navigationManager.currentDate, embedded: true, layoutType: .expanded)
                        .id(navigationManager.currentDate)
                        .frame(width: horizontalSizeClass == .compact ? .infinity : geometry.size.width * 0.95)
                        .frame(
                            minHeight: horizontalSizeClass == .compact ? 300 : geometry.size.height * 0.95,
                            idealHeight: horizontalSizeClass == .compact ? 500 : geometry.size.height * 0.95,
                            maxHeight: horizontalSizeClass == .compact ? 600 : geometry.size.height * 0.95,
                            alignment: .top
                        )
                        .padding(horizontalSizeClass == .compact ? adaptivePadding : 12)
                }
            }
            .padding(.horizontal, max(adaptivePadding, 0))
            .padding(.vertical, adaptivePadding)
            .safeAreaPadding(.horizontal, 8)
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
extension DayViewMobile {
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
    DayViewMobile()
}
