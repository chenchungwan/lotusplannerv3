import SwiftUI
import Foundation



// MARK: - Tasks View
struct TasksView: View {
    @ObservedObject private var viewModel = TasksViewModel.shared
    @ObservedObject private var calendarViewModel = CalendarViewModel.shared
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @StateObject private var bulkEditManager = BulkEditManager()
    @State private var selectedFilter: TaskFilter = .day
    @State private var referenceDate: Date = Date()
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // Use an item-bound sheet selection to avoid first-click blank sheet
    struct TasksViewTaskSelection: Identifiable {
        let id = UUID()
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    @State private var taskSheetSelection: TasksViewTaskSelection?
    @State private var showingAddItem = false
    // Personal/Professional task divider
    @State private var tasksPersonalWidth: CGFloat
    @State private var isTasksDividerDragging = false
    
    init() {
        // Initialize divider position from AppPreferences
        self._tasksPersonalWidth = State(initialValue: AppPreferences.shared.tasksViewPersonalWidth)
    }
    @State private var showingTaskDetails = false
    @State private var showingNewTask = false
    @State private var showingAddEvent = false
    @State private var allSubfilter: AllTaskSubfilter = .all
    
    // MARK: - Filtered Tasks Caching
    @State private var cachedFilteredPersonalTasks: [String: [GoogleTask]] = [:]
    @State private var cachedFilteredProfessionalTasks: [String: [GoogleTask]] = [:]
    @State private var lastFilterState: String = "" // Tracks filter+date+prefs state
    
    // Navigation date picker state
    @State private var showingNavigationDatePicker = false
    @State private var selectedDateForNavigation = Date()
    
    // MARK: - Adaptive Layout Properties
    private var shouldUseStackedLayout: Bool {
        // Use stacked (vertical) layout on iPhone portrait for better space utilization
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    private var adaptiveSpacing: CGFloat {
        horizontalSizeClass == .compact ? 12 : 16
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 16
    }
    
    private var isCurrentToolbarPeriod: Bool {
        let cal = Calendar.mondayFirst
        switch selectedFilter {
        case .day:
            return cal.isDate(referenceDate, inSameDayAs: Date())
        case .week:
            if let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
               let end = cal.date(byAdding: .day, value: 6, to: start) {
                return referenceDate >= start && referenceDate <= end
            }
            return false
        case .month:
            return cal.isDate(referenceDate, equalTo: Date(), toGranularity: .month)
        case .year:
            return cal.isDate(referenceDate, equalTo: Date(), toGranularity: .year)
        case .all:
            return false
        }
    }
    
    // MARK: - Local Filtering (No API calls)
    private var filteredPersonalTasks: [String: [GoogleTask]] {
        return getCachedFilteredTasks(for: viewModel.personalTasks, accountKind: .personal)
    }
    
    private var filteredProfessionalTasks: [String: [GoogleTask]] {
        return getCachedFilteredTasks(for: viewModel.professionalTasks, accountKind: .professional)
    }
    
    private func getCachedFilteredTasks(for tasksDict: [String: [GoogleTask]], accountKind: GoogleAuthManager.AccountKind) -> [String: [GoogleTask]] {
        // Generate cache key from current filter state
        let currentFilterState = "\(selectedFilter.rawValue)-\(allSubfilter.rawValue)-\(referenceDate.timeIntervalSince1970)-\(appPrefs.hideCompletedTasks)"
        
        // Check if we can use cached results
        let cacheIsValid = lastFilterState == currentFilterState
        let cachedResults = accountKind == .personal ? cachedFilteredPersonalTasks : cachedFilteredProfessionalTasks
        
        // Return cached results if valid and non-empty, or if input is empty
        if cacheIsValid && !cachedResults.isEmpty {
            return cachedResults
        }
        
        // Otherwise, compute filtered tasks
        let filtered = filterTasks(tasksDict)
        
        // Update cache
        DispatchQueue.main.async {
            self.lastFilterState = currentFilterState
            if accountKind == .personal {
                self.cachedFilteredPersonalTasks = filtered
            } else {
                self.cachedFilteredProfessionalTasks = filtered
            }
        }
        
        return filtered
    }
    
    // Direct filtering function that bypasses caching - like day views
    private func getDirectFilteredTasks(for tasksDict: [String: [GoogleTask]], accountKind: GoogleAuthManager.AccountKind) -> [String: [GoogleTask]] {
        let result = filterTasks(tasksDict)
        return result
    }
    
    private func filterTasks(_ tasksDict: [String: [GoogleTask]]) -> [String: [GoogleTask]] {
        return tasksDict.mapValues { tasks in
            filterTasksList(tasks)
        }
    }
    
    private func filterTasksList(_ tasks: [GoogleTask]) -> [GoogleTask] {
        let calendar = Calendar.mondayFirst
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        
        var filteredTasks = tasks
        
        // Apply subfilter when in "All"
        if selectedFilter == .all {
            filteredTasks = applyAllSubfilter(filteredTasks, calendar: calendar, startOfToday: startOfToday)
        } else {
            // Apply time-based filter
            filteredTasks = applyTimeBasedFilter(filteredTasks, calendar: calendar, now: now, startOfToday: startOfToday)
        }

        return filteredTasks
    }
    
    private func applyAllSubfilter(_ tasks: [GoogleTask], calendar: Calendar, startOfToday: Date) -> [GoogleTask] {
        var filteredTasks = tasks
        
        switch allSubfilter {
        case .all:
            break
        case .hasDueDate:
            filteredTasks = filteredTasks.filter { $0.dueDate != nil }
        case .noDueDate:
            filteredTasks = filteredTasks.filter { $0.dueDate == nil }
        case .pastDue:
            filteredTasks = filteredTasks.filter { task in
                if let due = task.dueDate {
                    return calendar.startOfDay(for: due) < startOfToday && !task.isCompleted
                }
                return false
            }
        case .completed:
            filteredTasks = filteredTasks.filter { $0.isCompleted }
        }
        
        // Hide completed tasks if setting is enabled
        if appPrefs.hideCompletedTasks {
            filteredTasks = filteredTasks.filter { !$0.isCompleted }
        }
        
        return filteredTasks
    }
    
    private func applyTimeBasedFilter(_ tasks: [GoogleTask], calendar: Calendar, now: Date, startOfToday: Date) -> [GoogleTask] {
        return tasks.filter { task in
            if task.isCompleted {
                return matchesCompletionDate(task, calendar: calendar)
            } else {
                return matchesDueDate(task, calendar: calendar, now: now, startOfToday: startOfToday)
            }
        }
    }
    
    private func matchesCompletionDate(_ task: GoogleTask, calendar: Calendar) -> Bool {
        guard let completionDate = task.completionDate else { return false }
        
        switch selectedFilter {
        case .day:
            return calendar.isDate(completionDate, inSameDayAs: referenceDate)
        case .week:
            return calendar.isDate(completionDate, equalTo: referenceDate, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(completionDate, equalTo: referenceDate, toGranularity: .month)
        case .year:
            return calendar.isDate(completionDate, equalTo: referenceDate, toGranularity: .year)
        case .all:
            return true
        }
    }
    
    private func matchesDueDate(_ task: GoogleTask, calendar: Calendar, now: Date, startOfToday: Date) -> Bool {
        guard let dueDate = task.dueDate else { return false }
        
        switch selectedFilter {
        case .day:
            // Show task on due date OR, if viewing today, show overdue (relative to today)
            let isDueOnViewedDate = calendar.isDate(dueDate, inSameDayAs: referenceDate)
            let isViewingToday = calendar.isDate(referenceDate, inSameDayAs: now)
            let startOfDueDate = calendar.startOfDay(for: dueDate)
            let isOverdueRelativeToToday = startOfDueDate < startOfToday
            return isDueOnViewedDate || (isViewingToday && isOverdueRelativeToToday)
        case .week:
            return calendar.isDate(dueDate, equalTo: referenceDate, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(dueDate, equalTo: referenceDate, toGranularity: .month)
        case .year:
            return calendar.isDate(dueDate, equalTo: referenceDate, toGranularity: .year)
        case .all:
            return true
        }
    }
    
    // MARK: - Stacked Layout for Mobile Portrait
    private func stackedTasksView(geometry: GeometryProxy) -> some View {
        ScrollView {
            VStack(spacing: adaptiveSpacing) {
                // Personal Tasks Section
                if authManager.isLinked(kind: .personal) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(appPrefs.personalAccountName) Tasks")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(appPrefs.personalColor)
                            .padding(.horizontal, adaptivePadding)

                        TasksComponent(
                            taskLists: viewModel.personalTaskLists,
                            tasksDict: getDirectFilteredTasks(for: viewModel.personalTasks, accountKind: .personal),
                            accentColor: appPrefs.personalColor,
                            accountType: .personal,
                            onTaskToggle: { task, listId in
                                Task {
                                    await viewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .personal)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await viewModel.updateTaskListOrder(newOrder, for: .personal)
                                }
                            },
                            horizontalCards: false,
                            isSingleDayView: selectedFilter == .day,
                            showTitle: false,
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
                
                // Professional Tasks Section
                if authManager.isLinked(kind: .professional) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(appPrefs.professionalAccountName) Tasks")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(appPrefs.professionalColor)
                            .padding(.horizontal, adaptivePadding)

                        TasksComponent(
                            taskLists: viewModel.professionalTaskLists,
                            tasksDict: getDirectFilteredTasks(for: viewModel.professionalTasks, accountKind: .professional),
                            accentColor: appPrefs.professionalColor,
                            accountType: .professional,
                            onTaskToggle: { task, listId in
                                Task {
                                    await viewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .professional)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await viewModel.updateTaskListOrder(newOrder, for: .professional)
                                }
                            },
                            horizontalCards: false,
                            isSingleDayView: selectedFilter == .day,
                            showTitle: false,
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
            }
            .padding(.horizontal, adaptivePadding)
            .padding(.vertical, adaptivePadding)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                if authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional) {
                    mainContent(geometry: geometry)
                } else {
                    noAccountsView
                }
            }
            .onAppear {
                // Initialize screen-dependent values
                if tasksPersonalWidth == 0 {
                    tasksPersonalWidth = appPrefs.tasksViewPersonalWidth
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .sidebarToggleHidden()
        .onAppear {
            Task {
                await viewModel.loadTasks()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleTasksBulkEdit"))) { _ in
            bulkEditManager.state.isActive.toggle()
            if !bulkEditManager.state.isActive {
                bulkEditManager.state.selectedTaskIds.removeAll()
            }
        }
        .sheet(item: $taskSheetSelection) { selection in
            TaskDetailsView(
                task: selection.task,
                taskListId: selection.listId,
                accountKind: selection.accountKind,
                accentColor: selection.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: viewModel.personalTaskLists,
                professionalTaskLists: viewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: viewModel,
                onSave: { updatedTask in
                    Task { await viewModel.updateTask(updatedTask, in: selection.listId, for: selection.accountKind) }
                },
                onDelete: {
                    Task { await viewModel.deleteTask(selection.task, from: selection.listId, for: selection.accountKind) }
                },
                onMove: { updatedTask, newListId in
                    Task { await viewModel.moveTask(updatedTask, from: selection.listId, to: newListId, for: selection.accountKind) }
                },
                onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                    Task { await viewModel.crossAccountMoveTask(updatedTask, from: (selection.accountKind, selection.listId), to: (targetAccount, targetListId)) }
                }
            )
        }
        .sheet(isPresented: $showingNewTask) {
            // Use the same UI as Task Details for creating a task
            let personalLinked = authManager.isLinked(kind: .personal)
            let _ = authManager.isLinked(kind: .professional)
            let defaultAccount: GoogleAuthManager.AccountKind = selectedAccountKind ?? (personalLinked ? .personal : .professional)
            let defaultLists = defaultAccount == .personal ? viewModel.personalTaskLists : viewModel.professionalTaskLists
            let defaultListId = defaultLists.first?.id ?? ""
            let newTask = GoogleTask(
                id: UUID().uuidString,
                title: "",
                notes: nil,
                status: "needsAction",
                due: nil,
                completed: nil,
                updated: nil
            )
            TaskDetailsView(
                task: newTask,
                taskListId: defaultListId,
                accountKind: defaultAccount,
                accentColor: defaultAccount == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: viewModel.personalTaskLists,
                professionalTaskLists: viewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: viewModel,
                onSave: { _ in },
                onDelete: {},
                onMove: { _, _ in },
                onCrossAccountMove: { _, _, _ in },
                isNew: true
            )
        }
        .sheet(isPresented: $showingNavigationDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDateForNavigation,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .overlay(alignment: .topTrailing) {
                    HStack {
                        Button("Cancel") {
                            showingNavigationDatePicker = false
                        }
                        .padding(.leading)
                        
                        Spacer()
                        
                        Button("Done") {
                            navigateToDate(selectedDateForNavigation)
                            showingNavigationDatePicker = false
                        }
                        .padding(.trailing)
                    }
                    .padding(.top, 8)
                }
            }
            .presentationDetents([.large])
        }
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                GlobalNavBar()
                    .background(.ultraThinMaterial)

                if bulkEditManager.state.isActive {
                    BulkEditToolbarView(
                        bulkEditManager: bulkEditManager,
                        visibleOpenTaskIds: filteredPersonalTasks.openTaskIds
                            .union(filteredProfessionalTasks.openTaskIds)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showingAddEvent) {
            // Launch event creation modal from Tasks view
            AddItemView(
                currentDate: referenceDate,
                tasksViewModel: viewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        // MARK: - Bulk Edit Confirmations and Sheets
        .confirmationDialog(
            "Complete \(bulkEditManager.state.selectedTaskIds.count) task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")?",
            isPresented: $bulkEditManager.state.showingCompleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Complete") {
                performBulkComplete()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(bulkEditManager.state.selectedTaskIds.count) task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")?",
            isPresented: $bulkEditManager.state.showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performBulkDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $bulkEditManager.state.showingDueDatePicker) {
            BulkUpdateDueDatePicker(
                selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                onSave: { date, isAllDay, startTime, endTime in
                    bulkEditManager.state.pendingDueDate = date
                    bulkEditManager.state.pendingIsAllDay = isAllDay
                    bulkEditManager.state.pendingStartTime = startTime
                    bulkEditManager.state.pendingEndTime = endTime
                    performBulkUpdateDueDate()
                }
            )
        }
        .sheet(isPresented: $bulkEditManager.state.showingMoveDestinationPicker) {
            BulkMoveDestinationPicker(
                personalTaskLists: viewModel.personalTaskLists,
                professionalTaskLists: viewModel.professionalTaskLists,
                onSelect: { accountKind, listId in
                    bulkEditManager.state.pendingMoveDestination = (listId: listId, accountKind: accountKind)
                    performBulkMove()
                }
            )
        }
        .sheet(isPresented: $bulkEditManager.state.showingPriorityPicker) {
            BulkUpdatePriorityPicker(
                selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                onSave: { priority in
                    bulkEditManager.state.pendingPriority = priority
                    performBulkUpdatePriority()
                }
            )
        }
        // Undo Toast
        .overlay(alignment: .bottom) {
            if bulkEditManager.state.showingUndoToast,
               let action = bulkEditManager.state.undoAction,
               let undoData = bulkEditManager.state.undoData {
                UndoToast(
                    action: action,
                    count: undoData.count,
                    accentColor: appPrefs.personalColor,
                    onUndo: {
                        performUndo(action: action, data: undoData)
                        bulkEditManager.state.showingUndoToast = false
                        bulkEditManager.state.undoAction = nil
                        bulkEditManager.state.undoData = nil
                    },
                    onDismiss: {
                        bulkEditManager.state.showingUndoToast = false
                        bulkEditManager.state.undoAction = nil
                        bulkEditManager.state.undoData = nil
                    }
                )
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(), value: bulkEditManager.state.showingUndoToast)
            }
        }
        .onAppear {
            // Load tasks on-demand when TasksView appears (performance optimization)
            Task {
                await viewModel.loadTasksOnDemand()
            }
            
            // Sync with navigation manager state when view appears
            if navigationManager.showingAllTasks {
                selectedFilter = .all
            } else {
                switch navigationManager.currentInterval {
                case .day:
                    selectedFilter = .day
                case .week:
                    selectedFilter = .week
                case .month:
                    selectedFilter = .month
                case .year:
                    selectedFilter = .year
                }
            }
            referenceDate = navigationManager.currentDate
            
            // Listen for external requests to show Add Task so behavior matches Calendar
            NotificationCenter.default.addObserver(forName: Notification.Name("LPV3_ShowAddTask"), object: nil, queue: .main) { _ in
                showingNewTask = true
            }
            // Listen for request to switch to All
            NotificationCenter.default.addObserver(forName: Notification.Name("ShowAllTasksRequested"), object: nil, queue: .main) { _ in
                selectedFilter = .all
                allSubfilter = .all
                referenceDate = Date()
                Task { @MainActor in
                    navigationManager.showingAllTasks = true
                }
                // Clear the current interval since "All Tasks" doesn't correspond to a specific time interval
                // This ensures other icons (D, W, M, Y) are properly unhighlighted
            }
            // Listen for request to set All tasks subfilter
            NotificationCenter.default.addObserver(forName: Notification.Name("SetAllTasksSubfilter"), object: nil, queue: .main) { notification in
                if let subfilter = notification.object as? AllTaskSubfilter {
                    allSubfilter = subfilter
                }
            }
            // Listen for request to filter tasks to current day (when coming from All Tasks filter)
            NotificationCenter.default.addObserver(forName: Notification.Name("FilterTasksToCurrentDay"), object: nil, queue: .main) { _ in
                selectedFilter = .day
                referenceDate = Date()
                Task { @MainActor in
                    navigationManager.showingAllTasks = false
                }
                // Clear cache to ensure fresh filtering
                cachedFilteredPersonalTasks.removeAll()
                cachedFilteredProfessionalTasks.removeAll()
                lastFilterState = ""
            }
            // Listen for request to filter tasks to current week (when coming from All Tasks filter)
            NotificationCenter.default.addObserver(forName: Notification.Name("FilterTasksToCurrentWeek"), object: nil, queue: .main) { _ in
                selectedFilter = .week
                referenceDate = Date()
                Task { @MainActor in
                    navigationManager.showingAllTasks = false
                }
                // Clear cache to ensure fresh filtering
                cachedFilteredPersonalTasks.removeAll()
                cachedFilteredProfessionalTasks.removeAll()
                lastFilterState = ""
            }
            // Listen for request to filter tasks to current month (when coming from All Tasks filter)
            NotificationCenter.default.addObserver(forName: Notification.Name("FilterTasksToCurrentMonth"), object: nil, queue: .main) { _ in
                selectedFilter = .month
                referenceDate = Date()
                Task { @MainActor in
                    navigationManager.showingAllTasks = false
                }
                // Clear cache to ensure fresh filtering
                cachedFilteredPersonalTasks.removeAll()
                cachedFilteredProfessionalTasks.removeAll()
                lastFilterState = ""
            }
            // Listen for request to filter tasks to current year (when coming from All Tasks filter)
            NotificationCenter.default.addObserver(forName: Notification.Name("FilterTasksToCurrentYear"), object: nil, queue: .main) { _ in
                selectedFilter = .year
                referenceDate = Date()
                Task { @MainActor in
                    navigationManager.showingAllTasks = false
                }
                // Clear cache to ensure fresh filtering
                cachedFilteredPersonalTasks.removeAll()
                cachedFilteredProfessionalTasks.removeAll()
                lastFilterState = ""
            }
        }
        .onChange(of: selectedFilter) { _, newValue in
            // Clear cache when filter changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: allSubfilter) { _, newValue in
            // Clear cache when subfilter changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: referenceDate) { _, newValue in
            // Clear cache when reference date changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: appPrefs.hideCompletedTasks) { _, newValue in
            // Clear cache when hide completed tasks setting changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: navigationManager.currentInterval) { _, newValue in
            // Update selectedFilter based on navigation interval
            switch newValue {
            case .day:
                selectedFilter = .day
            case .week:
                selectedFilter = .week
            case .month:
                selectedFilter = .month
            case .year:
                selectedFilter = .year
            }
            // Update reference date to current date when interval changes
            referenceDate = Date()
            // Clear cache when interval changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: navigationManager.currentDate) { _, newValue in
            referenceDate = newValue
            // Clear cache when date changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
    }
    
    private func mainContent(geometry: GeometryProxy) -> some View {
        Group {
            if shouldUseStackedLayout {
                // Mobile portrait: Full-width stacked layout
                stackedTasksView(geometry: geometry)
            } else if appPrefs.tasksLayoutHorizontal && !AppPreferences.isRunningOniPhone {
                // Horizontal cards layout
                horizontalTasksView
            } else {
                // Vertical layout
                verticalTasksView(geometry: geometry)
            }
        }
    }
    
    private var horizontalTasksView: some View {
        VStack(spacing: 0) {
            // Personal Tasks
            if authManager.isLinked(kind: .personal) {
                TasksComponent(
                    taskLists: viewModel.personalTaskLists,
                    tasksDict: getDirectFilteredTasks(for: viewModel.personalTasks, accountKind: .personal),
                    accentColor: appPrefs.personalColor,
                    accountType: .personal,
                    onTaskToggle: { task, listId in
                        Task {
                            await viewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .personal)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await viewModel.updateTaskListOrder(newOrder, for: .personal)
                        }
                    },
                    horizontalCards: true,
                    isSingleDayView: selectedFilter == .day,
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
            if authManager.isLinked(kind: .professional) {
                TasksComponent(
                    taskLists: viewModel.professionalTaskLists,
                    tasksDict: getDirectFilteredTasks(for: viewModel.professionalTasks, accountKind: .professional),
                    accentColor: appPrefs.professionalColor,
                    accountType: .professional,
                    onTaskToggle: { task, listId in
                        Task {
                            await viewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .professional)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await viewModel.updateTaskListOrder(newOrder, for: .professional)
                        }
                    },
                    horizontalCards: true,
                    isSingleDayView: selectedFilter == .day,
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
        .padding(.horizontal, 0)
        .padding(.vertical, adaptivePadding)
    }
    
    private func verticalTasksView(geometry: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Personal Tasks Column
            if authManager.isLinked(kind: .personal) {
                TasksComponent(
                    taskLists: viewModel.personalTaskLists,
                    tasksDict: getDirectFilteredTasks(for: viewModel.personalTasks, accountKind: .personal),
                    accentColor: appPrefs.personalColor,
                    accountType: .personal,
                    onTaskToggle: { task, listId in
                        Task {
                            await viewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .personal)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await viewModel.updateTaskListOrder(newOrder, for: .personal)
                        }
                    },
                    horizontalCards: false,
                    isSingleDayView: selectedFilter == .day,
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
                .frame(width: authManager.isLinked(kind: .professional) ? tasksPersonalWidth : geometry.size.width, alignment: .topLeading)
            }
            
            // Vertical divider (only show if both accounts are linked and not on mobile)
            if authManager.isLinked(kind: .personal) && authManager.isLinked(kind: .professional) && !shouldUseStackedLayout {
                tasksViewDivider(geometry: geometry)
            }
            
            // Professional Tasks Column
            if authManager.isLinked(kind: .professional) {
                TasksComponent(
                    taskLists: viewModel.professionalTaskLists,
                    tasksDict: getDirectFilteredTasks(for: viewModel.professionalTasks, accountKind: .professional),
                    accentColor: appPrefs.professionalColor,
                    accountType: .professional,
                    onTaskToggle: { task, listId in
                        Task {
                            await viewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .professional)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await viewModel.updateTaskListOrder(newOrder, for: .professional)
                        }
                    },
                    horizontalCards: false,
                    isSingleDayView: selectedFilter == .day,
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
                .frame(width: authManager.isLinked(kind: .personal) ? (geometry.size.width - tasksPersonalWidth - 8) : geometry.size.width, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, adaptivePadding)
    }
    
    private var noAccountsView: some View {
        VStack(spacing: 16) {
            Button(action: { NavigationManager.shared.showSettings() }) {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Link Your Google Account")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Connect your Google account to view and manage your calendar events and tasks")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 40)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func tasksViewDivider(geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(isTasksDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 4)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isTasksDividerDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isTasksDividerDragging = true
                        let newWidth = tasksPersonalWidth + value.translation.width
                        tasksPersonalWidth = max(200, min(geometry.size.width - 200, newWidth))
                    }
                    .onEnded { _ in
                        isTasksDividerDragging = false
                        appPrefs.updateTasksViewPersonalWidth(tasksPersonalWidth)
                    }
            )
    }
    
    // Helper computed properties
    private var shouldShowDebugInfo: Bool {
        let hasLinkedAccounts = authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional)
        let hasNoTasks = totalTaskCount == 0
        let isNotLoading = !viewModel.isLoading
        return hasLinkedAccounts && hasNoTasks && isNotLoading
    }
    
    private var totalTaskCount: Int {
        let personalCount = viewModel.personalTasks.values.flatMap { $0 }.count
        let professionalCount = viewModel.professionalTasks.values.flatMap { $0 }.count
        return personalCount + professionalCount
    }
    
    // MARK: - Helper Methods
    
    private func isDueDateOverdue(dueDate: Date) -> Bool {
        let calendar = Calendar.mondayFirst
        let today = calendar.startOfDay(for: Date())
        return dueDate < today
    }
    
    // MARK: - Subtitle helper
    private func subtitleForFilter(_ filter: TaskFilter) -> String {
        let cal = Calendar.mondayFirst
        switch filter {
        case .all:
            // Show subfilter name if not "All"
            if allSubfilter != .all {
                return "All Tasks - \(allSubfilter.rawValue)"
            }
            return "All Tasks"
        case .day:
            // Standardized format: MON 12/25/24
            let dayOfWeek = DateFormatter.standardDayOfWeek.string(from: referenceDate).uppercased()
            let date = DateFormatter.standardDate.string(from: referenceDate)
            return "\(dayOfWeek) \(date)"
        case .week:
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: referenceDate)?.start,
                  let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
            // Standardized format: 12/25/24 - 12/31/24
            let startStr = DateFormatter.standardDate.string(from: weekStart)
            let endStr = DateFormatter.standardDate.string(from: weekEnd)
            return "\(startStr) - \(endStr)"
        case .month:
            // Updated format: January 2025
            return DateFormatter.standardMonthYear.string(from: referenceDate)
        case .year:
            // Standardized format: 2024
            let year = cal.component(.year, from: referenceDate)
            return "\(year)"
        }
    }
    
    private func navigateToDate(_ selectedDate: Date) {
        // Always navigate to day view of the selected date
        selectedFilter = .day
        referenceDate = selectedDate
        navigationManager.updateInterval(.day, date: selectedDate)
    }
    
    // MARK: - Step helper
    private func step(_ direction: Int) {
        switch selectedFilter {
        case .day:
            if let newDate = Calendar.mondayFirst.date(byAdding: .day, value: direction, to: referenceDate) {
                referenceDate = newDate
                navigationManager.updateInterval(.day, date: newDate)
            }
        case .week:
            if let newDate = Calendar.mondayFirst.date(byAdding: .weekOfYear, value: direction, to: referenceDate) {
                referenceDate = newDate
                navigationManager.updateInterval(.week, date: newDate)
            }
        case .month:
            if let newDate = Calendar.mondayFirst.date(byAdding: .month, value: direction, to: referenceDate) {
                referenceDate = newDate
                navigationManager.updateInterval(.month, date: newDate)
            }
        case .year:
            if let newDate = Calendar.mondayFirst.date(byAdding: .year, value: direction, to: referenceDate) {
                referenceDate = newDate
                navigationManager.updateInterval(.year, date: newDate)
            }
        case .all:
            break
        }
    }
    
    // MARK: - Show All Tasks
    private func showAllTasks() {
        // Set filter to show all tasks
        selectedFilter = .all
        allSubfilter = .all
        referenceDate = Date()
        navigationManager.updateInterval(.day, date: Date())
    }

    // MARK: - Bulk Edit Operations

    private func performBulkComplete() {
        // Get all selected tasks from both personal and professional accounts
        let selectedIds = bulkEditManager.state.selectedTaskIds
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Collect from personal tasks
        for (listId, tasks) in viewModel.personalTasks {
            for task in tasks where selectedIds.contains(task.id) && !task.isCompleted {
                allTasks.append((task: task, listId: listId, accountKind: .personal))
            }
        }

        // Collect from professional tasks
        for (listId, tasks) in viewModel.professionalTasks {
            for task in tasks where selectedIds.contains(task.id) && !task.isCompleted {
                allTasks.append((task: task, listId: listId, accountKind: .professional))
            }
        }

        guard !allTasks.isEmpty else { return }

        // Pass tasks with their list/account info
        bulkEditManager.bulkComplete(
            tasks: allTasks,
            tasksVM: viewModel
        ) { undoData in
            bulkEditManager.state.undoAction = .complete
            bulkEditManager.state.undoData = undoData
            bulkEditManager.state.showingUndoToast = true

            // Auto-dismiss toast after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if bulkEditManager.state.undoAction == .complete {
                    bulkEditManager.state.showingUndoToast = false
                    bulkEditManager.state.undoAction = nil
                    bulkEditManager.state.undoData = nil
                }
            }
        }
    }

    private func performBulkDelete() {
        // Get all selected tasks from both personal and professional accounts
        let selectedIds = bulkEditManager.state.selectedTaskIds
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Collect from personal tasks
        for (listId, tasks) in viewModel.personalTasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .personal))
            }
        }

        // Collect from professional tasks
        for (listId, tasks) in viewModel.professionalTasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .professional))
            }
        }

        guard !allTasks.isEmpty else { return }

        bulkEditManager.bulkDelete(
            tasks: allTasks,
            tasksVM: viewModel
        ) { undoData in
            bulkEditManager.state.undoAction = .delete
            bulkEditManager.state.undoData = undoData
            bulkEditManager.state.showingUndoToast = true

            // Auto-dismiss toast after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if bulkEditManager.state.undoAction == .delete {
                    bulkEditManager.state.showingUndoToast = false
                    bulkEditManager.state.undoAction = nil
                    bulkEditManager.state.undoData = nil
                }
            }
        }
    }

    private func performBulkMove() {
        guard let destination = bulkEditManager.state.pendingMoveDestination else { return }

        // Get all selected tasks from both personal and professional accounts
        let selectedIds = bulkEditManager.state.selectedTaskIds
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Collect from personal tasks
        for (listId, tasks) in viewModel.personalTasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .personal))
            }
        }

        // Collect from professional tasks
        for (listId, tasks) in viewModel.professionalTasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .professional))
            }
        }

        guard !allTasks.isEmpty else { return }

        bulkEditManager.bulkMove(
            tasks: allTasks,
            to: destination.listId,
            destinationAccountKind: destination.accountKind,
            tasksVM: viewModel
        ) { undoData in
            bulkEditManager.state.undoAction = .move
            bulkEditManager.state.undoData = undoData
            bulkEditManager.state.showingUndoToast = true

            // Auto-dismiss toast after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if bulkEditManager.state.undoAction == .move {
                    bulkEditManager.state.showingUndoToast = false
                    bulkEditManager.state.undoAction = nil
                    bulkEditManager.state.undoData = nil
                }
            }
        }
    }

    private func performBulkUpdateDueDate() {
        // Get all selected tasks from both personal and professional accounts
        let selectedIds = bulkEditManager.state.selectedTaskIds
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Collect from personal tasks
        for (listId, tasks) in viewModel.personalTasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .personal))
            }
        }

        // Collect from professional tasks
        for (listId, tasks) in viewModel.professionalTasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .professional))
            }
        }

        guard !allTasks.isEmpty else { return }

        bulkEditManager.bulkUpdateDueDate(
            tasks: allTasks,
            dueDate: bulkEditManager.state.pendingDueDate,
            isAllDay: bulkEditManager.state.pendingIsAllDay,
            startTime: bulkEditManager.state.pendingStartTime,
            endTime: bulkEditManager.state.pendingEndTime,
            tasksVM: viewModel
        ) { undoData in
            bulkEditManager.state.undoAction = .updateDueDate
            bulkEditManager.state.undoData = undoData
            bulkEditManager.state.showingUndoToast = true

            // Auto-dismiss toast after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if bulkEditManager.state.undoAction == .updateDueDate {
                    bulkEditManager.state.showingUndoToast = false
                    bulkEditManager.state.undoAction = nil
                    bulkEditManager.state.undoData = nil
                }
            }
        }
    }

    private func performBulkUpdatePriority() {
        // Get all selected tasks from both personal and professional accounts
        let selectedIds = bulkEditManager.state.selectedTaskIds
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Collect from personal tasks
        for (listId, tasks) in viewModel.personalTasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .personal))
            }
        }

        // Collect from professional tasks
        for (listId, tasks) in viewModel.professionalTasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .professional))
            }
        }

        guard !allTasks.isEmpty else { return }

        bulkEditManager.bulkUpdatePriority(
            tasks: allTasks,
            priority: bulkEditManager.state.pendingPriority,
            tasksVM: viewModel
        ) { undoData in
            bulkEditManager.state.undoAction = .updatePriority
            bulkEditManager.state.undoData = undoData
            bulkEditManager.state.showingUndoToast = true

            // Auto-dismiss toast after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if bulkEditManager.state.undoAction == .updatePriority {
                    bulkEditManager.state.showingUndoToast = false
                    bulkEditManager.state.undoAction = nil
                    bulkEditManager.state.undoData = nil
                }
            }
        }
    }

    private func performUndo(action: BulkEditAction, data: BulkEditUndoData) {
        switch action {
        case .complete:
            bulkEditManager.undoComplete(data: data, tasksVM: viewModel)
        case .delete:
            bulkEditManager.undoDelete(data: data, tasksVM: viewModel)
        case .move:
            bulkEditManager.undoMove(data: data, tasksVM: viewModel)
        case .updateDueDate:
            bulkEditManager.undoUpdateDueDate(data: data, tasksVM: viewModel)
        case .updatePriority:
            bulkEditManager.undoUpdatePriority(data: data, tasksVM: viewModel)
        }
    }
}

// MARK: - Tasks Section View
struct TasksSectionView: View {
    let title: String
    let icon: String
    let accentColor: Color
    let isLinked: Bool
    let taskLists: [GoogleTaskList]
    let tasksDict: [String: [GoogleTask]]
    let accountKind: GoogleAuthManager.AccountKind
    let filter: TaskFilter
    let onTaskToggle: (GoogleTask, String) -> Void
    let onTaskDetails: (GoogleTask, String) -> Void
    let width: CGFloat
    
    private var isCurrentToolbarPeriod: Bool {
        let cal = Calendar.mondayFirst
        let refDate = NavigationManager.shared.currentDate
        switch filter {
        case .day:
            return cal.isDate(refDate, inSameDayAs: Date())
        case .week:
            if let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
               let end = cal.date(byAdding: .day, value: 6, to: start) {
                return refDate >= start && refDate <= end
            }
            return false
        case .month:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .month)
        case .year:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .year)
        case .all:
            return false
        }
    }

    private var isCurrentPeriod: Bool {
        let cal = Calendar.mondayFirst
        let refDate = NavigationManager.shared.currentDate
        switch filter {
        case .day:
            return cal.isDate(refDate, inSameDayAs: Date())
        case .week:
            if let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
               let end = cal.date(byAdding: .day, value: 6, to: start) {
                return refDate >= start && refDate <= end
            }
            return false
        case .month:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .month)
        case .year:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .year)
        case .all:
            return false
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            contentArea
        }
        .frame(width: width)
        .background(backgroundView)
    }
    
    private var sectionHeader: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(headerColor)
                .font(.title2)
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(headerColor)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(headerBackground)
    }
    
    private var headerColor: Color {
        isCurrentPeriod ? DateDisplayStyle.currentPeriodColor : accentColor
    }
    
    private var headerBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(headerColor.opacity(0.1))
    }
    
    private var contentArea: some View {
        Group {
            if isLinked {
                linkedContent
            } else {
                unlinkedContent
            }
        }
    }
    
    private var linkedContent: some View {
        Group {
            if taskLists.isEmpty {
                loadingView
            } else {
                taskListsGrid
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Loading tasks...")
                .foregroundColor(.secondary)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
    
    private var taskListsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(taskLists) { taskList in
                    taskListCard(for: taskList)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }
    
    private func taskListCard(for taskList: GoogleTaskList) -> some View {
        let filteredTasks = tasksDict[taskList.id] ?? []
        return Group {
            if !filteredTasks.isEmpty || filter == .all {
                TaskListCard(
                    taskList: taskList,
                    tasks: filteredTasks,
                    accountKind: accountKind,
                    accentColor: accentColor,
                    filter: filter,
                    onTaskToggle: { task in
                        onTaskToggle(task, taskList.id)
                    },
                    onTaskDetails: { task, listId in
                        onTaskDetails(task, listId)
                    }
                )
            }
        }
    }
    
    private var unlinkedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: unlinkedIcon)
                .font(.system(size: 50))
                .foregroundColor(accentColor.opacity(0.6))
            Text("Link \(title) Account")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(accentColor)
            Text("Connect your \(title.lowercased()) Google account to view and manage your calendar events and tasks")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .font(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
    
    private var unlinkedIcon: String {
        icon.replacingOccurrences(of: ".circle.fill", with: ".badge.plus")
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.systemBackground))
            .shadow(color: accentColor.opacity(0.2), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Task List Card Component
struct TaskListCard: View {
    let taskList: GoogleTaskList
    let tasks: [GoogleTask]
    let accountKind: GoogleAuthManager.AccountKind
    let accentColor: Color
    let filter: TaskFilter
    let onTaskToggle: (GoogleTask) -> Void
    let onTaskDetails: (GoogleTask, String) -> Void
    
    @State private var isExpanded = false
    
    private let maxVisibleTasks = 3
    private let collapsedHeight: CGFloat = 200 // Fixed height for collapsed state
    
    var completedTasks: Int {
        tasks.filter { $0.isCompleted }.count
    }
    
    var visibleTasks: [GoogleTask] {
        if isExpanded || tasks.count <= maxVisibleTasks {
            return tasks
        } else {
            return Array(tasks.prefix(maxVisibleTasks))
        }
    }
    
    var hasMoreTasks: Bool {
        tasks.count > maxVisibleTasks
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(taskList.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if tasks.isEmpty && filter != .all {
                        Text("No tasks for \(filter.rawValue.lowercased())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                
                Spacer()
                
                // Expand/Collapse button (only show when there are more than 3 tasks)
                if hasMoreTasks {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Task List Content
            VStack(alignment: .leading, spacing: 0) {
                if tasks.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.secondary)
                        Text("No tasks")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleTasks) { task in
                            TaskRow(
                                task: task, 
                                accentColor: accentColor, 
                                onToggle: {
                                    onTaskToggle(task)
                                },
                                onLongPress: {
                                    onTaskDetails(task, taskList.id)
                                }
                            )
                            
                            if task.id != visibleTasks.last?.id {
                                Divider()
                                    .opacity(0.5)
                            }
                        }
                    }
                    
                    // Show more tasks indicator
                    if hasMoreTasks && !isExpanded {
                        VStack(spacing: 8) {
                            Divider()
                                .opacity(0.5)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isExpanded = true
                                }
                            }) {
                                HStack {
                                    Text("Show \(tasks.count - maxVisibleTasks) more tasks")
                                        .font(.caption)
                                        .foregroundColor(accentColor)
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(accentColor)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(minHeight: isExpanded ? nil : collapsedHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Task Row Component
struct TaskRow: View {
    let task: GoogleTask
    let accentColor: Color
    let onToggle: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Completion Button
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(task.isCompleted ? accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Task Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.title3)
                        .foregroundColor(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted)
                    

                    
                    Spacer()
                }
                
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Due Date
            if let dueDate = task.dueDate {
                Text(DateFormatter.standardDate.string(from: dueDate))
                    .font(DateDisplayStyle.subtitleFont)
                    .foregroundColor(DateDisplayStyle.secondaryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isDueDateOverdue(dueDate: dueDate) ? Color.red.opacity(0.1) : Color(.systemGray6))
                    )
                    .foregroundColor(isDueDateOverdue(dueDate: dueDate) ? .red : .secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onLongPress() // Use the same callback for both tap and long press
        }
        .onLongPressGesture {
            onLongPress()
        }
    }
    
    private func isDueDateOverdue(dueDate: Date) -> Bool {
        let calendar = Calendar.mondayFirst
        let today = calendar.startOfDay(for: Date())
        return dueDate < today
    }
}
