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
    // Account 1/Account 2 task divider
    @State private var tasksAccount1Width: CGFloat
    @State private var isTasksDividerDragging = false
    
    init() {
        // Initialize divider position from AppPreferences
        self._tasksAccount1Width = State(initialValue: AppPreferences.shared.tasksViewAccount1Width)
    }
    @State private var showingTaskDetails = false
    @State private var showingNewTask = false
    @State private var showingAddEvent = false
    @State private var allSubfilter: AllTaskSubfilter = .all
    
    // MARK: - Filtered Tasks Caching
    @State private var cachedFilteredAccount1Tasks: [String: [GoogleTask]] = [:]
    @State private var cachedFilteredAccount2Tasks: [String: [GoogleTask]] = [:]
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
    private var filteredAccount1Tasks: [String: [GoogleTask]] {
        return getCachedFilteredTasks(for: viewModel.account1Tasks, accountKind: .account1)
    }
    
    private var filteredAccount2Tasks: [String: [GoogleTask]] {
        return getCachedFilteredTasks(for: viewModel.account2Tasks, accountKind: .account2)
    }
    
    private func getCachedFilteredTasks(for tasksDict: [String: [GoogleTask]], accountKind: GoogleAuthManager.AccountKind) -> [String: [GoogleTask]] {
        // Generate cache key from current filter state
        let currentFilterState = "\(selectedFilter.rawValue)-\(allSubfilter.rawValue)-\(referenceDate.timeIntervalSince1970)-\(appPrefs.hideCompletedTasks)"
        
        // Check if we can use cached results
        let cacheIsValid = lastFilterState == currentFilterState
        let cachedResults = accountKind == .account1 ? cachedFilteredAccount1Tasks : cachedFilteredAccount2Tasks
        
        // Return cached results if valid and non-empty, or if input is empty
        if cacheIsValid && !cachedResults.isEmpty {
            return cachedResults
        }
        
        // Otherwise, compute filtered tasks
        let filtered = filterTasks(tasksDict)
        
        // Update cache
        DispatchQueue.main.async {
            self.lastFilterState = currentFilterState
            if accountKind == .account1 {
                self.cachedFilteredAccount1Tasks = filtered
            } else {
                self.cachedFilteredAccount2Tasks = filtered
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
                // Account 1 Tasks Section
                if authManager.isLinked(kind: .account1) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(appPrefs.account1Name) Tasks")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(appPrefs.account1Color)
                            .padding(.horizontal, adaptivePadding)

                        TasksComponent(
                            taskLists: viewModel.account1TaskLists,
                            tasksDict: getDirectFilteredTasks(for: viewModel.account1Tasks, accountKind: .account1),
                            accentColor: appPrefs.account1Color,
                            accountType: .account1,
                            onTaskToggle: { task, listId in
                                Task {
                                    await viewModel.toggleTaskCompletion(task, in: listId, for: .account1)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .account1)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .account1)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await viewModel.updateTaskListOrder(newOrder, for: .account1)
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
                
                // Account 2 Tasks Section
                if authManager.isLinked(kind: .account2) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(appPrefs.account2Name) Tasks")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(appPrefs.account2Color)
                            .padding(.horizontal, adaptivePadding)

                        TasksComponent(
                            taskLists: viewModel.account2TaskLists,
                            tasksDict: getDirectFilteredTasks(for: viewModel.account2Tasks, accountKind: .account2),
                            accentColor: appPrefs.account2Color,
                            accountType: .account2,
                            onTaskToggle: { task, listId in
                                Task {
                                    await viewModel.toggleTaskCompletion(task, in: listId, for: .account2)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .account2)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .account2)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await viewModel.updateTaskListOrder(newOrder, for: .account2)
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
                if authManager.isLinked(kind: .account1) || authManager.isLinked(kind: .account2) {
                    mainContent(geometry: geometry)
                } else {
                    noAccountsView
                }
            }
            .onAppear {
                // Initialize screen-dependent values
                if tasksAccount1Width == 0 {
                    tasksAccount1Width = appPrefs.tasksViewAccount1Width
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleTasksBulkEdit)) { _ in
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
                accentColor: selection.accountKind == .account1 ? appPrefs.account1Color : appPrefs.account2Color,
                account1TaskLists: viewModel.account1TaskLists,
                account2TaskLists: viewModel.account2TaskLists,
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
            let account1Linked = authManager.isLinked(kind: .account1)
            let _ = authManager.isLinked(kind: .account2)
            let defaultAccount: GoogleAuthManager.AccountKind = selectedAccountKind ?? (account1Linked ? .account1 : .account2)
            let defaultLists = defaultAccount == .account1 ? viewModel.account1TaskLists : viewModel.account2TaskLists
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
                accentColor: defaultAccount == .account1 ? appPrefs.account1Color : appPrefs.account2Color,
                account1TaskLists: viewModel.account1TaskLists,
                account2TaskLists: viewModel.account2TaskLists,
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
                        visibleOpenTaskIds: filteredAccount1Tasks.openTaskIds
                            .union(filteredAccount2Tasks.openTaskIds)
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
                account1TaskLists: viewModel.account1TaskLists,
                account2TaskLists: viewModel.account2TaskLists,
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
                    accentColor: appPrefs.account1Color,
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddTask)) { _ in
            showingNewTask = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAllTasksRequested)) { _ in
            showAllTasks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .setAllTasksSubfilter)) { notification in
            if let subfilter = notification.object as? AllTaskSubfilter {
                allSubfilter = subfilter
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterTasksToCurrentDay)) { _ in
            applyTaskFilter(.day)
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterTasksToCurrentWeek)) { _ in
            applyTaskFilter(.week)
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterTasksToCurrentMonth)) { _ in
            applyTaskFilter(.month)
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterTasksToCurrentYear)) { _ in
            applyTaskFilter(.year)
        }
        .onChange(of: selectedFilter) { _, newValue in
            // Clear cache when filter changes
            cachedFilteredAccount1Tasks.removeAll()
            cachedFilteredAccount2Tasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: allSubfilter) { _, newValue in
            // Clear cache when subfilter changes
            cachedFilteredAccount1Tasks.removeAll()
            cachedFilteredAccount2Tasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: referenceDate) { _, newValue in
            // Clear cache when reference date changes
            cachedFilteredAccount1Tasks.removeAll()
            cachedFilteredAccount2Tasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: appPrefs.hideCompletedTasks) { _, newValue in
            // Clear cache when hide completed tasks setting changes
            cachedFilteredAccount1Tasks.removeAll()
            cachedFilteredAccount2Tasks.removeAll()
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
            cachedFilteredAccount1Tasks.removeAll()
            cachedFilteredAccount2Tasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: navigationManager.currentDate) { _, newValue in
            referenceDate = newValue
            // Clear cache when date changes
            cachedFilteredAccount1Tasks.removeAll()
            cachedFilteredAccount2Tasks.removeAll()
            lastFilterState = ""
        }
    }

    private func applyTaskFilter(_ filter: TaskFilter) {
        selectedFilter = filter
        referenceDate = Date()
        navigationManager.showingAllTasks = false
        switch filter {
        case .day:
            navigationManager.updateInterval(.day, date: referenceDate)
        case .week:
            navigationManager.updateInterval(.week, date: referenceDate)
        case .month:
            navigationManager.updateInterval(.month, date: referenceDate)
        case .year:
            navigationManager.updateInterval(.year, date: referenceDate)
        case .all:
            break
        }
        cachedFilteredAccount1Tasks.removeAll()
        cachedFilteredAccount2Tasks.removeAll()
        lastFilterState = ""
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
            // Account 1 Tasks
            if authManager.isLinked(kind: .account1) {
                TasksComponent(
                    taskLists: viewModel.account1TaskLists,
                    tasksDict: getDirectFilteredTasks(for: viewModel.account1Tasks, accountKind: .account1),
                    accentColor: appPrefs.account1Color,
                    accountType: .account1,
                    onTaskToggle: { task, listId in
                        Task {
                            await viewModel.toggleTaskCompletion(task, in: listId, for: .account1)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .account1)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .account1)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await viewModel.updateTaskListOrder(newOrder, for: .account1)
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

            // Account 2 Tasks
            if authManager.isLinked(kind: .account2) {
                TasksComponent(
                    taskLists: viewModel.account2TaskLists,
                    tasksDict: getDirectFilteredTasks(for: viewModel.account2Tasks, accountKind: .account2),
                    accentColor: appPrefs.account2Color,
                    accountType: .account2,
                    onTaskToggle: { task, listId in
                        Task {
                            await viewModel.toggleTaskCompletion(task, in: listId, for: .account2)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .account2)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .account2)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await viewModel.updateTaskListOrder(newOrder, for: .account2)
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
            // Account 1 Tasks Column
            if authManager.isLinked(kind: .account1) {
                TasksComponent(
                    taskLists: viewModel.account1TaskLists,
                    tasksDict: getDirectFilteredTasks(for: viewModel.account1Tasks, accountKind: .account1),
                    accentColor: appPrefs.account1Color,
                    accountType: .account1,
                    onTaskToggle: { task, listId in
                        Task {
                            await viewModel.toggleTaskCompletion(task, in: listId, for: .account1)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .account1)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .account1)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await viewModel.updateTaskListOrder(newOrder, for: .account1)
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
                .frame(width: authManager.isLinked(kind: .account2) ? tasksAccount1Width : geometry.size.width, alignment: .topLeading)
            }
            
            // Vertical divider (only show if both accounts are linked and not on mobile)
            if authManager.isLinked(kind: .account1) && authManager.isLinked(kind: .account2) && !shouldUseStackedLayout {
                tasksViewDivider(geometry: geometry)
            }
            
            // Account 2 Tasks Column
            if authManager.isLinked(kind: .account2) {
                TasksComponent(
                    taskLists: viewModel.account2TaskLists,
                    tasksDict: getDirectFilteredTasks(for: viewModel.account2Tasks, accountKind: .account2),
                    accentColor: appPrefs.account2Color,
                    accountType: .account2,
                    onTaskToggle: { task, listId in
                        Task {
                            await viewModel.toggleTaskCompletion(task, in: listId, for: .account2)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .account2)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .account2)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await viewModel.updateTaskListOrder(newOrder, for: .account2)
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
                .frame(width: authManager.isLinked(kind: .account1) ? (geometry.size.width - tasksAccount1Width - 8) : geometry.size.width, alignment: .topLeading)
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
                        let newWidth = tasksAccount1Width + value.translation.width
                        tasksAccount1Width = max(200, min(geometry.size.width - 200, newWidth))
                    }
                    .onEnded { _ in
                        isTasksDividerDragging = false
                        appPrefs.updateTasksViewAccount1Width(tasksAccount1Width)
                    }
            )
    }
    
    // Helper computed properties
    private var shouldShowDebugInfo: Bool {
        let hasLinkedAccounts = authManager.isLinked(kind: .account1) || authManager.isLinked(kind: .account2)
        let hasNoTasks = totalTaskCount == 0
        let isNotLoading = !viewModel.isLoading
        return hasLinkedAccounts && hasNoTasks && isNotLoading
    }
    
    private var totalTaskCount: Int {
        let account1Count = viewModel.account1Tasks.values.flatMap { $0 }.count
        let account2Count = viewModel.account2Tasks.values.flatMap { $0 }.count
        return account1Count + account2Count
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
        navigationManager.showingAllTasks = true
        navigationManager.updateInterval(.day, date: Date())
    }

    // MARK: - Bulk Edit Operations

    private func performBulkComplete() {
        // Get all selected tasks from both accounts
        let selectedIds = bulkEditManager.state.selectedTaskIds
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Collect from account 1 tasks
        for (listId, tasks) in viewModel.account1Tasks {
            for task in tasks where selectedIds.contains(task.id) && !task.isCompleted {
                allTasks.append((task: task, listId: listId, accountKind: .account1))
            }
        }

        // Collect from account 2 tasks
        for (listId, tasks) in viewModel.account2Tasks {
            for task in tasks where selectedIds.contains(task.id) && !task.isCompleted {
                allTasks.append((task: task, listId: listId, accountKind: .account2))
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
        // Get all selected tasks from both accounts
        let selectedIds = bulkEditManager.state.selectedTaskIds
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Collect from account 1 tasks
        for (listId, tasks) in viewModel.account1Tasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .account1))
            }
        }

        // Collect from account 2 tasks
        for (listId, tasks) in viewModel.account2Tasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .account2))
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

        // Get all selected tasks from both accounts
        let selectedIds = bulkEditManager.state.selectedTaskIds
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Collect from account 1 tasks
        for (listId, tasks) in viewModel.account1Tasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .account1))
            }
        }

        // Collect from account 2 tasks
        for (listId, tasks) in viewModel.account2Tasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .account2))
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
        // Get all selected tasks from both accounts
        let selectedIds = bulkEditManager.state.selectedTaskIds
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Collect from account 1 tasks
        for (listId, tasks) in viewModel.account1Tasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .account1))
            }
        }

        // Collect from account 2 tasks
        for (listId, tasks) in viewModel.account2Tasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .account2))
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
        // Get all selected tasks from both accounts
        let selectedIds = bulkEditManager.state.selectedTaskIds
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Collect from account 1 tasks
        for (listId, tasks) in viewModel.account1Tasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .account1))
            }
        }

        // Collect from account 2 tasks
        for (listId, tasks) in viewModel.account2Tasks {
            for task in tasks where selectedIds.contains(task.id) {
                allTasks.append((task: task, listId: listId, accountKind: .account2))
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
