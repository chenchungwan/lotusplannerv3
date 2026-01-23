import SwiftUI

struct DayViewMobile: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    @ObservedObject private var bulkEditManager: BulkEditManager
    private let onEventTap: ((GoogleCalendarEvent) -> Void)?

    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

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
            VStack(spacing: 0) {
                // Bulk Edit Toolbar (shown when in bulk edit mode)
                if bulkEditManager.state.isActive {
                    BulkEditToolbarView(bulkEditManager: bulkEditManager)
                }

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
                        let personalTasks = filteredTasksDictForDay(tasksVM.personalTasks, on: navigationManager.currentDate)
                        TasksCompactComponent(
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
                        .padding(.horizontal, adaptivePadding)


                        // Empty state for no accounts (shown only once)
                        if !auth.isLinked(kind: .personal) && !auth.isLinked(kind: .professional) {
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
                        }

                        // Professional tasks
                        let professionalTasks = filteredTasksDictForDay(tasksVM.professionalTasks, on: navigationManager.currentDate)
                        TasksCompactComponent(
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
                        .padding(.horizontal, adaptivePadding)

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
}

// MARK: - Day Filters
extension DayViewMobile {
    private func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.mondayFirst.isDate(lhs, inSameDayAs: rhs)
    }
    
    private func filteredEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        calendarVM.events(for: date)
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
    DayViewMobile(bulkEditManager: BulkEditManager())
}
