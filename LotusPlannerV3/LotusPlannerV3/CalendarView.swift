import SwiftUI
import PencilKit
import PhotosUI
import Foundation
import Photos

// MARK: - Calendar View

struct CalendarView: View {
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var dataManager = DataManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var authManager = GoogleAuthManager.shared
    
    init() {
        // Initialize divider positions from AppPreferences
        self._dayLeftSectionWidth = State(initialValue: AppPreferences.shared.calendarDayLeftSectionWidth)
        self._dayRightColumn2Width = State(initialValue: AppPreferences.shared.calendarDayRightColumn2Width)
        self._rightSectionTopHeight = State(initialValue: AppPreferences.shared.calendarDayRightSectionTopHeight)
        self._topSectionHeight = State(initialValue: AppPreferences.shared.calendarTopSectionHeight)
        self._verticalTopRowHeight = State(initialValue: AppPreferences.shared.calendarVerticalTopRowHeight)
        self._verticalTopLeftWidth = State(initialValue: AppPreferences.shared.calendarVerticalTopLeftWidth)
        self._verticalBottomLeftWidth = State(initialValue: AppPreferences.shared.calendarVerticalBottomLeftWidth)
        self._weekTasksPersonalWidth = State(initialValue: AppPreferences.shared.calendarWeekTasksPersonalWidth)
        self._weekTopSectionHeight = State(initialValue: AppPreferences.shared.calendarWeekTopSectionHeight)
        self._longEventsLeftWidth = State(initialValue: AppPreferences.shared.calendarVerticalTopLeftWidth) // Reuse same preference
    }
    
    @State private var currentDate = Date()
    @State private var topSectionHeight: CGFloat
    @State private var rightSectionTopHeight: CGFloat
    // Vertical layout row height
    @State private var verticalTopRowHeight: CGFloat
    // Vertical layout column widths and drag states
    @State private var verticalTopLeftWidth: CGFloat
    @State private var isVerticalTopDividerDragging: Bool = false
    @State private var verticalBottomLeftWidth: CGFloat
    @State private var isVerticalBottomDividerDragging: Bool = false
    @State private var isDragging = false
    @State private var isRightDividerDragging = false
    @State private var pencilKitCanvasView = PKCanvasView()

    @State private var canvasView = PKCanvasView()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotoPermissionAlert = false
    @State private var showingPhotoPicker = false
    @State private var photoLibraryAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var selectedImages: [UIImage] = []
    @State private var showingTaskDetails = false
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    struct CalendarTaskSelection: Identifiable {
        let id = UUID()
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    @State private var taskSheetSelection: CalendarTaskSelection?
    @State private var showingAddItem = false
    @State private var currentTimeTimer: Timer?
    @State private var currentTimeSlot: Double = 0
    @State private var movablePhotos: [MovablePhoto] = []
    @State private var cachedPersonalTasks: [String: [GoogleTask]] = [:]
    @State private var cachedProfessionalTasks: [String: [GoogleTask]] = [:]
    @State private var weekTasksSectionWidth: CGFloat = UIScreen.main.bounds.width * 0.6
    @State private var weekCanvasView = PKCanvasView()
    @State private var cachedWeekPersonalTasks: [String: [GoogleTask]] = [:]
    @State private var cachedWeekProfessionalTasks: [String: [GoogleTask]] = [:]
    @State private var weekTopSectionHeight: CGFloat = 400

    // Bulk edit manager
    @StateObject private var bulkEditManager = BulkEditManager()
    @State private var isWeekDividerDragging = false
    @State private var monthCanvasView = PKCanvasView()
    @State private var cachedMonthPersonalTasks: [String: [GoogleTask]] = [:]
    @State private var cachedMonthProfessionalTasks: [String: [GoogleTask]] = [:]
    
    // Day view vertical slider state
    @State private var dayLeftSectionWidth: CGFloat
    @State private var isDayVerticalDividerDragging = false
    // Left section logs collapsible state
    @State private var isLogsSectionCollapsed: Bool = false
    

    
    // Day view right section column widths and divider state
    @State private var dayRightColumn2Width: CGFloat
    @State private var isDayRightColumnDividerDragging = false
    
    @State private var selectedCalendarEvent: GoogleCalendarEvent?
    @State private var showingEventDetails = false
    
    // Personal/Professional task divider widths for all views
    @State private var weekTasksPersonalWidth: CGFloat = UIScreen.main.bounds.width * 0.3
    @State private var isWeekTasksDividerDragging = false
    
    // Long layout adjustable sizes and drag states
    @State private var longTopRowHeight: CGFloat = UIScreen.main.bounds.height * 0.35
    @State private var isLongHorizontalDividerDragging: Bool = false
    @State private var longEventsLeftWidth: CGFloat
    @State private var isLongVerticalDividerDragging: Bool = false
    
    // Date picker state
    @State private var showingDatePicker = false
    @State private var selectedDateForPicker = Date()
    @State private var showingAddEvent = false
    @State private var showingNewTask = false
    
    private var baseContent: some View {
        GeometryReader { geometry in
            splitScreenContent(geometry: geometry)
        }
        .sidebarToggleHidden()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            GlobalNavBar()
                .background(.ultraThinMaterial)
        }
        .id("baseContent-\(currentDate)-\(navigationManager.currentInterval)")
    }

    // Break up sheet chain to avoid type-checker timeout
    private var baseContentWithEventSheet: some View {
        baseContent
        .sheet(item: Binding<GoogleCalendarEvent?>(
            get: { selectedCalendarEvent },
            set: { selectedCalendarEvent = $0 }
        )) { ev in
            let accountKind: GoogleAuthManager.AccountKind = calendarViewModel.personalEvents.contains(where: { $0.id == ev.id }) ? .personal : .professional
            AddItemView(
                currentDate: ev.startTime ?? Date(),
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                existingEvent: ev,
                accountKind: accountKind,
                showEventOnly: true
            )
        }
    }

    private var baseContentWithTaskSheet: some View {
        baseContentWithEventSheet
        .sheet(item: $taskSheetSelection) { sel in
            TaskDetailsView(
                task: sel.task,
                taskListId: sel.listId,
                accountKind: sel.accountKind,
                accentColor: sel.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { updatedTask in
                    Task {
                        await tasksViewModel.updateTask(updatedTask, in: sel.listId, for: sel.accountKind)
                        updateCachedTasks()
                    }
                },
                onDelete: {
                    Task {
                        await tasksViewModel.deleteTask(sel.task, from: sel.listId, for: sel.accountKind)
                        updateCachedTasks()
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksViewModel.moveTask(updatedTask, from: sel.listId, to: targetListId, for: sel.accountKind)
                        updateCachedTasks()
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksViewModel.crossAccountMoveTask(updatedTask, from: (sel.accountKind, sel.listId), to: (targetAccountKind, targetListId))
                        updateCachedTasks()
                    }
                }
            )
        }
    }

    private var baseContentWithBulkEditDialogs: some View {
        baseContentWithTaskSheet
        // Bulk edit confirmation dialogs
        .confirmationDialog("Complete Tasks", isPresented: $bulkEditManager.state.showingCompleteConfirmation) {
            Button("Complete \(bulkEditManager.state.selectedTaskIds.count) task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")") {
                Task {
                    let allTasks = getAllTasksForBulkEdit()
                    await bulkEditManager.bulkComplete(tasks: allTasks, tasksVM: tasksViewModel) { undoData in
                        bulkEditManager.state.undoAction = .complete
                        bulkEditManager.state.undoData = undoData
                        bulkEditManager.state.showingUndoToast = true

                        // Update cached tasks
                        updateCachedTasks()
                        updateMonthCachedTasks()

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
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete Tasks", isPresented: $bulkEditManager.state.showingDeleteConfirmation) {
            Button("Delete \(bulkEditManager.state.selectedTaskIds.count) task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")", role: .destructive) {
                Task {
                    let allTasks = getAllTasksForBulkEdit()
                    await bulkEditManager.bulkDelete(tasks: allTasks, tasksVM: tasksViewModel) { undoData in
                        bulkEditManager.state.undoAction = .delete
                        bulkEditManager.state.undoData = undoData
                        bulkEditManager.state.showingUndoToast = true

                        // Update cached tasks
                        updateCachedTasks()
                        updateMonthCachedTasks()

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
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var baseContentWithBulkEditSheets: some View {
        baseContentWithBulkEditDialogs
        .sheet(isPresented: $bulkEditManager.state.showingDueDatePicker) {
            BulkUpdateDueDatePicker(selectedTaskIds: bulkEditManager.state.selectedTaskIds) { date, isAllDay, startTime, endTime in
                Task {
                    let allTasks = getAllTasksForBulkEdit()
                    await bulkEditManager.bulkUpdateDueDate(
                        tasks: allTasks,
                        dueDate: date,
                        isAllDay: isAllDay,
                        startTime: startTime,
                        endTime: endTime,
                        tasksVM: tasksViewModel
                    ) { undoData in
                        bulkEditManager.state.undoAction = .updateDueDate
                        bulkEditManager.state.undoData = undoData
                        bulkEditManager.state.showingUndoToast = true

                        // Update cached tasks
                        updateCachedTasks()
                        updateMonthCachedTasks()

                        // Auto-dismiss toast after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            if bulkEditManager.state.undoAction == .updateDueDate {
                                bulkEditManager.state.showingUndoToast = false
                                bulkEditManager.state.undoAction = nil
                                bulkEditManager.state.undoData = nil
                            }
                        }
                    }
                    bulkEditManager.state.showingDueDatePicker = false
                }
            }
        }
        .sheet(isPresented: $bulkEditManager.state.showingMoveDestinationPicker) {
            BulkMoveDestinationPicker(
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                onSelect: { targetAccount, targetListId in
                    Task {
                        let allTasks = getAllTasksForBulkEdit()
                        await bulkEditManager.bulkMove(
                            tasks: allTasks,
                            to: targetListId,
                            destinationAccountKind: targetAccount,
                            tasksVM: tasksViewModel
                        ) { undoData in
                            bulkEditManager.state.undoAction = .move
                            bulkEditManager.state.undoData = undoData
                            bulkEditManager.state.showingUndoToast = true

                            // Update cached tasks
                            updateCachedTasks()
                            updateMonthCachedTasks()

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
                    bulkEditManager.state.showingMoveDestinationPicker = false
                }
            )
        }
        .sheet(isPresented: $bulkEditManager.state.showingPriorityPicker) {
            BulkUpdatePriorityPicker(selectedTaskIds: bulkEditManager.state.selectedTaskIds) { priority in
                Task {
                    let allTasks = getAllTasksForBulkEdit()
                    await bulkEditManager.bulkUpdatePriority(
                        tasks: allTasks,
                        priority: priority,
                        tasksVM: tasksViewModel
                    ) { undoData in
                        bulkEditManager.state.undoAction = .updatePriority
                        bulkEditManager.state.undoData = undoData
                        bulkEditManager.state.showingUndoToast = true

                        // Update cached tasks
                        updateCachedTasks()
                        updateMonthCachedTasks()

                        // Auto-dismiss toast after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            if bulkEditManager.state.undoAction == .updatePriority {
                                bulkEditManager.state.showingUndoToast = false
                                bulkEditManager.state.undoAction = nil
                                bulkEditManager.state.undoData = nil
                            }
                        }
                    }
                    bulkEditManager.state.showingPriorityPicker = false
                }
            }
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
    }

    private var toolbarAndSheetsContent: some View {
        baseContentWithBulkEditSheets
        .onChange(of: authManager.linkedStates) { oldValue, newValue in
            // When an account is unlinked, clear associated tasks and calendar events
            if !(newValue[.personal] ?? false) {
                tasksViewModel.clearTasks(for: .personal)
                // Safely clear calendar data on main actor
                Task { @MainActor in
                    calendarViewModel.personalEvents = []
                    calendarViewModel.personalCalendars = []
                }
            }
            if !(newValue[.professional] ?? false) {
                tasksViewModel.clearTasks(for: .professional)
                // Safely clear calendar data on main actor
                Task { @MainActor in
                    calendarViewModel.professionalEvents = []
                    calendarViewModel.professionalCalendars = []
                }
            }
            // When an account becomes linked, load tasks and calendar data immediately
            let personalJustLinked = (newValue[.personal] ?? false) && !(oldValue[.personal] ?? false)
            let professionalJustLinked = (newValue[.professional] ?? false) && !(oldValue[.professional] ?? false)
            if personalJustLinked || professionalJustLinked {
                Task {
                    await tasksViewModel.loadTasks()
                    await calendarViewModel.refreshDataForCurrentView()
                    await MainActor.run {
                        updateCachedTasks()
                        updateMonthCachedTasks()
                    }
                }
            } else {
                updateCachedTasks()
                updateMonthCachedTasks()
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemView(
                currentDate: currentDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        .sheet(isPresented: $showingAddEvent) {
            AddItemView(
                currentDate: currentDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        .sheet(isPresented: $showingNewTask) {
            // Create-task UI matching TasksView create flow
            let personalLinked = authManager.isLinked(kind: GoogleAuthManager.AccountKind.personal)
            let defaultAccount: GoogleAuthManager.AccountKind = personalLinked ? GoogleAuthManager.AccountKind.personal : GoogleAuthManager.AccountKind.professional
            let defaultLists = defaultAccount == GoogleAuthManager.AccountKind.personal ? tasksViewModel.personalTaskLists : tasksViewModel.professionalTaskLists
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
                accentColor: defaultAccount == GoogleAuthManager.AccountKind.personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { updatedTask in
                    Task {
                        await tasksViewModel.updateTask(updatedTask, in: defaultListId, for: defaultAccount)
                    }
                },
                onDelete: {
                    // No-op for new task creation
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksViewModel.moveTask(updatedTask, from: defaultListId, to: targetListId, for: defaultAccount)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                    Task {
                        await tasksViewModel.crossAccountMoveTask(updatedTask, from: (defaultAccount, defaultListId), to: (targetAccount, targetListId))
                    }
                },
                isNew: true
            )
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDateForPicker,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            // Navigate based on current view context
                            if navigationManager.showTasksView && navigationManager.showingAllTasks {
                                // If in Tasks view filtered to ALL, go to yearly view
                                currentDate = selectedDateForPicker
                                navigationManager.updateInterval(.year, date: selectedDateForPicker)
                            } else {
                                // Otherwise, respect current interval but use selected date
                                currentDate = selectedDateForPicker
                                navigationManager.updateInterval(navigationManager.currentInterval, date: selectedDateForPicker)
                            }
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    private var finalContent: some View {
        toolbarAndSheetsContent
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleCalendarBulkEdit"))) { _ in
            devLog("CalendarView received ToggleCalendarBulkEdit notification, current: \(bulkEditManager.state.isActive)", level: .info, category: .calendar)
            bulkEditManager.state.isActive.toggle()
            devLog("Bulk edit toggled, new state: \(bulkEditManager.state.isActive)", level: .info, category: .calendar)
            if !bulkEditManager.state.isActive {
                // Exit bulk edit mode - clear selections
                bulkEditManager.state.selectedTaskIds.removeAll()
                devLog("Bulk edit selections cleared", level: .info, category: .calendar)
            }
        }
        .onChange(of: authManager.linkedStates) { oldValue, newValue in
            // When an account is unlinked, clear associated tasks and calendar events
            if !(newValue[.personal] ?? false) {
                tasksViewModel.clearTasks(for: .personal)
                // Safely clear calendar data on main actor
                Task { @MainActor in
                    calendarViewModel.personalEvents = []
                    calendarViewModel.personalCalendars = []
                }
            }
            if !(newValue[.professional] ?? false) {
                tasksViewModel.clearTasks(for: .professional)
                // Safely clear calendar data on main actor
                Task { @MainActor in
                    calendarViewModel.professionalEvents = []
                    calendarViewModel.professionalCalendars = []
                }
            }
            // When an account becomes linked, load tasks and calendar data immediately
            let personalJustLinked = (newValue[.personal] ?? false) && !(oldValue[.personal] ?? false)
            let professionalJustLinked = (newValue[.professional] ?? false) && !(oldValue[.professional] ?? false)
            if personalJustLinked || professionalJustLinked {
                Task {
                    await tasksViewModel.loadTasks()
                    await calendarViewModel.refreshDataForCurrentView()
                    await MainActor.run {
                        updateCachedTasks()
                        updateMonthCachedTasks()
                    }
                }
            } else {
                updateCachedTasks()
                updateMonthCachedTasks()
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemView(
                currentDate: currentDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        .sheet(isPresented: $showingAddEvent) {
            AddItemView(
                currentDate: currentDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        .sheet(isPresented: $showingNewTask) {
            // Create-task UI matching TasksView create flow
            let personalLinked = authManager.isLinked(kind: GoogleAuthManager.AccountKind.personal)
            let defaultAccount: GoogleAuthManager.AccountKind = personalLinked ? GoogleAuthManager.AccountKind.personal : GoogleAuthManager.AccountKind.professional
            let defaultLists = defaultAccount == GoogleAuthManager.AccountKind.personal ? tasksViewModel.personalTaskLists : tasksViewModel.professionalTaskLists
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
                accentColor: defaultAccount == GoogleAuthManager.AccountKind.personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { updatedTask in
                    Task {
                        await tasksViewModel.updateTask(updatedTask, in: defaultListId, for: defaultAccount)
                    }
                },
                onDelete: {
                    // No-op for new task creation
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksViewModel.moveTask(updatedTask, from: defaultListId, to: targetListId, for: defaultAccount)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                    Task {
                        await tasksViewModel.crossAccountMoveTask(updatedTask, from: (defaultAccount, defaultListId), to: (targetAccount, targetListId))
                    }
                },
                isNew: true
            )
        }
        .sheet(isPresented: $showingTaskDetails) {
            if let task = selectedTask, let taskListId = selectedTaskListId, let accountKind = selectedAccountKind {
                TaskDetailsView(
                    task: task,
                    taskListId: taskListId,
                    accountKind: accountKind,
                    accentColor: accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    personalTaskLists: tasksViewModel.personalTaskLists,
                    professionalTaskLists: tasksViewModel.professionalTaskLists,
                    appPrefs: appPrefs,
                    viewModel: tasksViewModel,
                    onSave: { updatedTask in
                        Task {
                            await tasksViewModel.updateTask(updatedTask, in: taskListId, for: accountKind)
                            updateCachedTasks()
                        }
                    },
                    onDelete: {
                        Task {
                            await tasksViewModel.deleteTask(task, from: taskListId, for: accountKind)
                            updateCachedTasks()
                        }
                    },
                    onMove: { updatedTask, targetListId in
                        Task {
                            await tasksViewModel.moveTask(updatedTask, from: taskListId, to: targetListId, for: accountKind)
                            updateCachedTasks()
                        }
                    },
                    onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                        Task {
                            await tasksViewModel.crossAccountMoveTask(updatedTask, from: (accountKind, taskListId), to: (targetAccountKind, targetListId))
                            updateCachedTasks()
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDateForPicker,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            // Navigate based on current view context
                            if navigationManager.showTasksView && navigationManager.showingAllTasks {
                                // If in Tasks view filtered to ALL, go to yearly view
                                currentDate = selectedDateForPicker
                                navigationManager.updateInterval(.year, date: selectedDateForPicker)
                            } else {
                                // Otherwise, respect current interval but use selected date
                                currentDate = selectedDateForPicker
                                navigationManager.updateInterval(navigationManager.currentInterval, date: selectedDateForPicker)
                            }
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    var body: some View {
        finalContent
            .id("CalendarView-\(currentDate)-\(navigationManager.currentInterval)")
    }

    private func splitScreenContent(geometry: GeometryProxy) -> some View {
        // Just show the main content without any overlay panels
        mainContentView
    }
    

    
    private var leadingToolbarButtons: some View {
        EmptyView() // arrows moved to principal, Today moved to trailing
    }
    
    private var principalToolbarContent: some View {
        HStack(spacing: 8) {
            SharedNavigationToolbar()
            
            Button(action: { step(-1) }) {
                Image(systemName: "chevron.left")
            }
            if navigationManager.currentInterval == .year {
                Button(action: {
                    selectedDateForPicker = currentDate
                    showingDatePicker = true
                }) {
                    Text(String(Calendar.current.component(.year, from: currentDate)))
                        .font(DateDisplayStyle.titleFont)
                        .fontWeight(.semibold)
                        .foregroundColor(isCurrentYear ? DateDisplayStyle.currentPeriodColor : DateDisplayStyle.primaryColor)
                }
            } else if navigationManager.currentInterval == .month {
                Button(action: {
                    selectedDateForPicker = currentDate
                    showingDatePicker = true
                }) {
                    Text(monthYearTitle)
                        .font(DateDisplayStyle.titleFont)
                        .fontWeight(.semibold)
                        .foregroundColor(isCurrentMonth ? DateDisplayStyle.currentPeriodColor : DateDisplayStyle.primaryColor)
                }
            } else if navigationManager.currentInterval == .week {
                Button(action: {
                    selectedDateForPicker = currentDate
                    showingDatePicker = true
                }) {
                    Text(weekTitle)
                        .font(DateDisplayStyle.titleFont)
                        .fontWeight(.semibold)
                        .foregroundColor(isCurrentWeek ? DateDisplayStyle.currentPeriodColor : DateDisplayStyle.primaryColor)
                }
            } else if navigationManager.currentInterval == .day {
                Button(action: {
                    selectedDateForPicker = currentDate
                    showingDatePicker = true
                }) {
                    Text(dayTitle)
                        .font(DateDisplayStyle.titleFont)
                        .fontWeight(.semibold)
                        .foregroundColor(isToday ? DateDisplayStyle.currentPeriodColor : DateDisplayStyle.primaryColor)
                }
            }
            Button(action: { step(1) }) {
                Image(systemName: "chevron.right")
            }
        }
        .id("toolbar-\(navigationManager.currentInterval)-\(currentDate)")
    }
    
    private var trailingToolbarButtons: some View {
        HStack(spacing: 12) {
            // Day button
            Button(action: {
                navigationManager.updateInterval(.day, date: Date())
                currentDate = Date()
            }) {
                Image(systemName: "d.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentInterval == .day && navigationManager.currentView != .weeklyView ? .accentColor : .secondary)
            }
            
            // WeeklyView button
            Button(action: {
                let now = Date()
                navigationManager.switchToWeeklyView()
                navigationManager.updateInterval(.week, date: now)
            }) {
                Image(systemName: "w.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentView == .weeklyView ? .accentColor : .secondary)
            }
            
            // g.circle removed
            
            // Show eye and plus only in Day view
            if navigationManager.currentInterval == .day {
                // Hide Completed toggle removed
                
                // Refresh button
                Button(action: {
                    Task {
                        await calendarViewModel.refreshDataForCurrentView()
                        await tasksViewModel.loadTasks()
                        await MainActor.run { updateCachedTasks() }
                    }
                }) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // Add menu (Event or Task) for Day view
                Menu {
                    Button("Event") { 
                        showingAddEvent = true
                    }
                    Button("Task") {
                        showingNewTask = true
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var mainContentView: some View {
        Group {
            if navigationManager.currentInterval == .year {
                yearView
                    .onAppear {
                        devLog("📅 CalendarView: Rendering YEAR view")
                    }
            } else if navigationManager.currentInterval == .month {
                monthView
                    .onAppear {
                        devLog("📅 CalendarView: Rendering MONTH view")
                    }
            } else if navigationManager.currentInterval == .day {
                AnyView(setupDayView())
                    .onAppear {
                        devLog("📅 CalendarView: Rendering DAY view")
                    }
            } else {
                Text("Calendar View")
                    .font(.largeTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .onAppear {
                        devLog("📅 CalendarView: Rendering DEFAULT/OTHER view")
                    }
            }
        }
        .id("mainContent-\(currentDate)-\(navigationManager.currentInterval)")
    }

    private func step(_ direction: Int) {
        if let newDate = Calendar.mondayFirst.date(byAdding: navigationManager.currentInterval.calendarComponent,
                                                   value: direction,
                                                   to: currentDate) {
            // First update the navigation manager
            navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
            
            // Then do a comprehensive data refresh
            Task {
                // Clear all caches first
                calendarViewModel.clearAllData()
                await tasksViewModel.loadTasks(forceClear: true)
                
                // Load fresh data based on interval
                switch navigationManager.currentInterval {
                case .day:
                    await calendarViewModel.loadCalendarData(for: newDate)
                case .week:
                    await calendarViewModel.loadCalendarDataForWeek(containing: newDate)
                case .month:
                    await calendarViewModel.forceLoadCalendarDataForMonth(containing: newDate)
                case .year:
                    await calendarViewModel.forceLoadCalendarDataForMonth(containing: newDate)
                }
                
                await MainActor.run {
                    // Update local state after data is loaded
                    currentDate = newDate
                    updateCachedTasks()
                    // Force view updates
                    calendarViewModel.objectWillChange.send()
                    tasksViewModel.objectWillChange.send()
                }
            }
        }
    }
    
    private var yearView: some View {
        monthsSection
            .background(Color(.systemBackground))
            .id("yearView-\(currentDate)")
            .task {
                // Load fresh data for the current year when view appears
                let navDate = await navigationManager.currentDate
                // Update local currentDate to match navigation manager
                currentDate = navDate
                await calendarViewModel.forceLoadCalendarDataForMonth(containing: navDate)
            }
            .onChange(of: currentDate) { oldValue, newValue in
                // Load data when currentDate changes
                Task {
                    await calendarViewModel.forceLoadCalendarDataForMonth(containing: newValue)
                }
            }
            .onChange(of: navigationManager.currentDate) { oldValue, newValue in
                // Load data when navigation manager's date changes
                Task {
                    await calendarViewModel.forceLoadCalendarDataForMonth(containing: newValue)
                }
            }
    }
    
    private var monthsSection: some View {
        GeometryReader { geometry in
            let padding: CGFloat = 16
            let gridSpacing: CGFloat = 16
            let columnSpacing: CGFloat = 12
            let availableHeight = geometry.size.height - (padding * 2)
            let rows = 4 // 12 months ÷ 3 columns = 4 rows
            let monthCardHeight = (availableHeight - (gridSpacing * CGFloat(rows - 1))) / CGFloat(rows)
            
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: 3), spacing: gridSpacing) {
                    ForEach(1...12, id: \.self) { month in
                        let calendar = Calendar.mondayFirst
                        let monthDate = calendar.date(from: DateComponents(year: Calendar.current.component(.year, from: currentDate), month: month, day: 1))!

                        MonthCardView(
                            month: month,
                            year: Calendar.current.component(.year, from: currentDate),
                            currentDate: monthDate,
                            onDayTap: { date in
                                currentDate = date
                                navigationManager.updateInterval(.day, date: date)
                            },
                            onMonthTap: {
                                currentDate = monthDate
                                navigationManager.updateInterval(.month, date: monthDate)
                            },
                            onWeekTap: { date in
                                currentDate = date
                                navigationManager.updateInterval(.week, date: date)
                            }
                        )
                        .frame(height: monthCardHeight)
                    }
                }
                .padding(padding)
            }
        }
    }
    
    private var dividerSection: some View {
        Rectangle()
            .fill(isDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newHeight = topSectionHeight + value.translation.height
                        topSectionHeight = max(300, min(UIScreen.main.bounds.height - 150, newHeight))
                    }
                    .onEnded { _ in
                        isDragging = false
                        appPrefs.updateCalendarTopSectionHeight(topSectionHeight)
                    }
            )
    }
    
    private var bulkEditToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                bulkEditExitButton
                bulkEditSelectionCount
                Spacer()
                bulkEditActionButtons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            Divider()
        }
    }

    private var bulkEditExitButton: some View {
        Button {
            bulkEditManager.state.isActive = false
            bulkEditManager.state.selectedTaskIds.removeAll()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
    }

    private var bulkEditSelectionCount: some View {
        Text("\(bulkEditManager.state.selectedTaskIds.count) selected")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }

    private var bulkEditActionButtons: some View {
        HStack(spacing: 8) {
            bulkEditCompleteButton
            bulkEditDueDateButton
            bulkEditMoveButton
            bulkEditDeleteButton
        }
    }

    private var bulkEditCompleteButton: some View {
        Button {
            bulkEditManager.state.showingCompleteConfirmation = true
        } label: {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .primary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(bulkEditManager.state.selectedTaskIds.isEmpty ? Color(.systemGray6) : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
        .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)
    }

    private var bulkEditDueDateButton: some View {
        Button {
            bulkEditManager.state.showingDueDatePicker = true
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .primary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(bulkEditManager.state.selectedTaskIds.isEmpty ? Color(.systemGray6) : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
        .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)
    }

    private var bulkEditMoveButton: some View {
        Button {
            bulkEditManager.state.showingMoveDestinationPicker = true
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .primary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(bulkEditManager.state.selectedTaskIds.isEmpty ? Color(.systemGray6) : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
        .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)
    }

    private var bulkEditDeleteButton: some View {
        Button {
            bulkEditManager.state.showingDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(bulkEditManager.state.selectedTaskIds.isEmpty ? .secondary : .primary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(bulkEditManager.state.selectedTaskIds.isEmpty ? Color(.systemGray6) : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
        .disabled(bulkEditManager.state.selectedTaskIds.isEmpty)
    }

    private var bottomSection: some View {
        VStack(spacing: 0) {
            // Bulk Edit Toolbar (shown when in bulk edit mode)
            if bulkEditManager.state.isActive {
                bulkEditToolbar
            }

            HStack(spacing: 0) {
                // Personal Tasks Component
                TasksComponent(
                    taskLists: tasksViewModel.personalTaskLists,
                    tasksDict: cachedMonthPersonalTasks,
                    accentColor: appPrefs.personalColor,
                    accountType: .personal,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                            updateCachedTasks()
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .personal)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                        }
                    },
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.all, 8)
            
            // Professional Tasks Component
            TasksComponent(
                taskLists: tasksViewModel.professionalTaskLists,
                tasksDict: cachedMonthProfessionalTasks,
                accentColor: appPrefs.professionalColor,
                accountType: .professional,
                onTaskToggle: { task, listId in
                    Task {
                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                        updateCachedTasks()
                    }
                },
                onTaskDetails: { task, listId in
                    taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .professional)
                },
                onListRename: { listId, newName in
                    Task {
                        await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                    }
                },
                onOrderChanged: { newOrder in
                    Task {
                        await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                    }
                },
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            // Bottom section - Journal
            JournalView(currentDate: $currentDate, embedded: true)
                .id(currentDate)
                .frame(maxHeight: .infinity)
                .padding(.all, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Week Bottom Section
    
    private var weekBottomSection: some View {
        GeometryReader { geometry in
            if !authManager.isLinked(kind: .personal) && !authManager.isLinked(kind: .professional) {
                // Centered empty state for weekly view
                Button(action: { NavigationManager.shared.showSettings() }) {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Link Your Google Account")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text("Connect your Google account to view and manage your calendar events and tasks")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 40)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            } else {
                HStack(spacing: 0) {
                    // Tasks section (personal and professional columns)
                    weekTasksSection
                        .frame(width: weekTasksSectionWidth)
                    
                    // Resizable divider
                    weekTasksDivider
                    
                    // Apple Pencil section
                    weekPencilSection
                        .frame(width: geometry.size.width - weekTasksSectionWidth - 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var weekTasksSection: some View {
        HStack(spacing: 0) {
            // Personal Tasks
            TasksComponent(
                taskLists: tasksViewModel.personalTaskLists,
                tasksDict: cachedWeekPersonalTasks,
                accentColor: appPrefs.personalColor,
                accountType: .personal,
                onTaskToggle: { task, listId in
                    Task {
                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                        updateCachedTasks()
                    }
                },
                onTaskDetails: { task, listId in
                    taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .personal)
                },
                onListRename: { listId, newName in
                    Task {
                        await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                    }
                },
                onOrderChanged: { newOrder in
                    Task {
                        await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                    }
                },
                isSingleDayView: true,
                showTitle: false
            )
            .frame(width: weekTasksPersonalWidth, alignment: .topLeading)
            
            // Vertical divider
            weekTasksDivider
            
            // Professional Tasks
            TasksComponent(
                taskLists: tasksViewModel.professionalTaskLists,
                tasksDict: cachedWeekProfessionalTasks,
                accentColor: appPrefs.professionalColor,
                accountType: .professional,
                onTaskToggle: { task, listId in
                    Task {
                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                        updateCachedTasks()
                    }
                },
                onTaskDetails: { task, listId in
                    taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .professional)
                },
                onListRename: { listId, newName in
                    Task {
                        await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                    }
                },
                onOrderChanged: { newOrder in
                    Task {
                        await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                    }
                },
                isSingleDayView: true,
                showTitle: false
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    
    private var weekTasksDivider: some View {
        VStack(spacing: 4) {
            // Handle lines on left
            HStack(spacing: 4) {
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 1.5, height: 20)
                Spacer()
            }
            // Main divider line
            Rectangle()
                .fill(isWeekTasksDividerDragging ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2))
                .frame(width: 1)
            // Handle lines on right
            HStack(spacing: 4) {
                Spacer()
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 1.5, height: 20)
            }
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    isWeekTasksDividerDragging = true
                    let newWidth = weekTasksPersonalWidth + value.translation.width
                    weekTasksPersonalWidth = max(150, min(UIScreen.main.bounds.width * 0.6, newWidth))
                }
                .onEnded { _ in
                    isWeekTasksDividerDragging = false
                    appPrefs.updateCalendarWeekTasksPersonalWidth(weekTasksPersonalWidth)
                }
        )
    }
    
    private var weekPencilSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notes & Sketches")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    weekCanvasView.drawing = PKDrawing()
                }) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Canvas area
            WeekPencilKitView(canvasView: $weekCanvasView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
        .padding(.all, 8)
    }

    private var monthView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Single month calendar takes up full space
                singleMonthSection
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Color(.systemBackground))
        .task {
            let navDate = await navigationManager.currentDate
            // Update local currentDate to match navigation manager
            currentDate = navDate
            // Load fresh data for the current month when view appears
            await calendarViewModel.forceLoadCalendarDataForMonth(containing: navDate)
        }
        .onChange(of: currentDate) { oldValue, newValue in
            // Load data when currentDate changes
            Task {
                await calendarViewModel.forceLoadCalendarDataForMonth(containing: newValue)
            }
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            // Load data when navigation manager's date changes
            Task {
                await calendarViewModel.forceLoadCalendarDataForMonth(containing: newValue)
            }
        }
    }

    private var monthYearTitle: String {
        // Updated format: January 2025
        return DateFormatter.standardMonthYear.string(from: currentDate)
    }
    

    
    private var weekTitle: String {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return "Week"
        }
        
        // Standardized format: 12/25/24 - 12/31/24
        let startString = DateFormatter.standardDate.string(from: weekStart)
        let endString = DateFormatter.standardDate.string(from: weekEnd)
        let result = "\(startString) - \(endString)"
        
        return result
    }
    
    private var dayTitle: String {
        // Standardized format: MON 12/25/24
        let dayOfWeek = DateFormatter.standardDayOfWeek.string(from: currentDate).uppercased()
        let date = DateFormatter.standardDate.string(from: currentDate)
        return "\(dayOfWeek) \(date)"
    }

    private var isToday: Bool {
        Calendar.current.isDate(currentDate, inSameDayAs: Date())
    }
    private var isCurrentWeek: Bool {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return false }
        return currentDate >= weekStart && currentDate <= weekEnd
    }
    private var isCurrentMonth: Bool {
        let calendar = Calendar.current
        let todayComponents = calendar.dateComponents([.year, .month], from: Date())
        let currentComponents = calendar.dateComponents([.year, .month], from: currentDate)
        return todayComponents.year == currentComponents.year && todayComponents.month == currentComponents.month
    }
    private var isCurrentYear: Bool {
        Calendar.current.component(.year, from: Date()) == Calendar.current.component(.year, from: currentDate)
    }
    
    private func navigateToDate(_ selectedDate: Date) {
        let newDate: Date
        
        switch navigationManager.currentInterval {
        case .day:
            // For day view, navigate directly to the selected date
            newDate = selectedDate
        case .week:
            // For week view, navigate to the week containing the selected date
            let calendar = Calendar.mondayFirst
            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start {
                newDate = weekStart
            } else {
                newDate = selectedDate
            }
        case .month:
            // For month view, navigate to the month containing the selected date
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            if let firstOfMonth = calendar.date(from: components) {
                newDate = firstOfMonth
            } else {
                newDate = selectedDate
            }
        case .year:
            // For year view, navigate to the year containing the selected date
            let calendar = Calendar.current
            let year = calendar.component(.year, from: selectedDate)
            if let firstOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) {
                newDate = firstOfYear
            } else {
                newDate = selectedDate
            }
        }
        
        currentDate = newDate
        navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
    }
    

    

    

    

    



    

    
    private var singleMonthSection: some View {
        let monthEvents = getMonthEventsGroupedByDate()
        let personalEvents = calendarViewModel.personalEvents
        let professionalEvents = calendarViewModel.professionalEvents
        
        
        return MonthTimelineComponent(
            currentDate: currentDate,
            monthEvents: monthEvents,
            personalEvents: personalEvents,
            professionalEvents: professionalEvents,
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor,
            onEventTap: { ev in
                selectedCalendarEvent = ev
                showingEventDetails = true
            },
            onDayTap: { date in
                currentDate = date
                navigationManager.updateInterval(.day, date: date)
            }
        )
        .task {
            await calendarViewModel.forceLoadCalendarDataForMonth(containing: currentDate)
        }
        .onChange(of: currentDate) { oldValue, newValue in
            // Only load data if the date actually changed to a different month
            let calendar = Calendar.current
            if !calendar.isDate(oldValue, equalTo: newValue, toGranularity: .month) {
                Task {
                    await calendarViewModel.forceLoadCalendarDataForMonth(containing: newValue)
                }
            }
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            // Only update currentDate if it's actually different
            if currentDate != newValue {
                currentDate = newValue
            }
        }
    }
    
    private var dayView: some View {
        dayViewBase
            .task {
                // Clear caches and load fresh data
                calendarViewModel.clearAllData()
                await tasksViewModel.loadTasks(forceClear: true)
                await calendarViewModel.refreshDataForCurrentView()

                await MainActor.run {
                    updateCachedTasks()
                    // Force view updates
                    calendarViewModel.objectWillChange.send()
                    tasksViewModel.objectWillChange.send()
                }
            }
            .onChange(of: currentDate) { oldValue, newValue in
                Task {
                    // Clear caches and load fresh data
                    calendarViewModel.clearAllData()
                    await tasksViewModel.loadTasks(forceClear: true)
                    await calendarViewModel.loadCalendarData(for: newValue)
                    
                    await MainActor.run {
                        updateCachedTasks()
                        // Force view updates
                        calendarViewModel.objectWillChange.send()
                        tasksViewModel.objectWillChange.send()
                    }
                }
            }
            .onChange(of: navigationManager.currentInterval) { oldValue, newValue in
                Task {
                    // Clear caches and load fresh data
                    calendarViewModel.clearAllData()
                    await tasksViewModel.loadTasks(forceClear: true)
                    
                    // Load data based on interval
                    switch newValue {
                    case .day:
                        await calendarViewModel.refreshDataForCurrentView()
                    case .week:
                        await calendarViewModel.loadCalendarDataForWeek(containing: currentDate)
                    case .month:
                        await calendarViewModel.forceLoadCalendarDataForMonth(containing: currentDate)
                    case .year:
                        await calendarViewModel.forceLoadCalendarDataForMonth(containing: currentDate)
                    }
                    
                    await MainActor.run {
                        updateCachedTasks()
                        // Force view updates
                        calendarViewModel.objectWillChange.send()
                        tasksViewModel.objectWillChange.send()
                    }
                }
            }
            .onChange(of: navigationManager.currentDate) { oldValue, newValue in
                currentDate = newValue
            }
            .onChange(of: tasksViewModel.personalTasks) { oldValue, newValue in
                updateCachedTasks()
                // Force view update
                tasksViewModel.objectWillChange.send()
            }
            .onChange(of: tasksViewModel.professionalTasks) { oldValue, newValue in
                updateCachedTasks()
                // Force view update
                tasksViewModel.objectWillChange.send()
            }
            .onChange(of: dataManager.isInitializing) { oldValue, newValue in
                if !newValue {
                    updateCachedTasks()
                    // Force view updates
                    calendarViewModel.objectWillChange.send()
                    tasksViewModel.objectWillChange.send()
                }
            }
            // hideCompletedTasks onChange removed

            .onAppear {
                startCurrentTimeTimer()
                // Sync currentDate with navigation manager's current date
                Task {
                    let navDate = await navigationManager.currentDate
                    currentDate = navDate
                }
                // Ensure tasks are cached when view appears
                updateCachedTasks()
                // Listen for external add requests
                NotificationCenter.default.addObserver(forName: Notification.Name("LPV3_ShowAddTask"), object: nil, queue: .main) { _ in
                    Task { @MainActor in
                        navigationManager.switchToTasks()
                    }
                }
                NotificationCenter.default.addObserver(forName: Notification.Name("LPV3_ShowAddEvent"), object: nil, queue: .main) { _ in
                    showingAddItem = true
                }
                // Listen for calendar data refresh requests
                NotificationCenter.default.addObserver(forName: Notification.Name("RefreshCalendarData"), object: nil, queue: .main) { _ in
                    Task {
                        // Update local currentDate to match navigation manager
                        let navDate = await navigationManager.currentDate
                        currentDate = navDate
                        // Force load both accounts directly
                        await calendarViewModel.forceLoadCalendarDataForMonth(containing: navDate)
                        await MainActor.run {
                            updateCachedTasks()
                            calendarViewModel.objectWillChange.send()
                            tasksViewModel.objectWillChange.send()
                        }
                    }
                }
            }
            .onDisappear {
                stopCurrentTimeTimer()
            }
    }
    
    private var dayViewBase: some View {
        GeometryReader { outerGeometry in
            ScrollView(.horizontal, showsIndicators: true) {
                dayViewContent(geometry: outerGeometry)
                    .frame(width: outerGeometry.size.width) // 100% of device width
            }
        }
        .background(Color(.systemBackground))
        .overlay(loadingOverlay)
        .alert("Calendar Error", isPresented: $calendarViewModel.showError) {
            Button("OK") {
                calendarViewModel.showError = false
                calendarViewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = calendarViewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhoto,
            matching: .images
        )
        .alert("Photo Library Access", isPresented: $showingPhotoPermissionAlert) {
            Button("Settings") {
                openAppSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("LotusPlannerV3 needs access to your photo library to add photos to your daily notes. You can enable this in Settings > Privacy & Security > Photos.")
        }
        .onChange(of: selectedPhoto) { oldValue, newValue in
            if let newPhoto = newValue {
                handleSelectedPhoto(newPhoto)
            }
        }
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if calendarViewModel.isLoading {
            ProgressView()
                .padding()
                .background(Color(.systemBackground).opacity(0.9))
                .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private var taskDetailsSheet: some View {
        if let task = selectedTask, 
           let listId = selectedTaskListId,
           let accountKind = selectedAccountKind {
            TaskDetailsView(
                task: task,
                taskListId: listId,
                accountKind: accountKind,
                accentColor: accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { updatedTask in
                    Task {
                        await tasksViewModel.updateTask(updatedTask, in: listId, for: accountKind)
                        updateCachedTasks()
                    }
                },
                onDelete: {
                    Task {
                        await tasksViewModel.deleteTask(task, from: listId, for: accountKind)
                        updateCachedTasks()
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksViewModel.moveTask(updatedTask, from: listId, to: targetListId, for: accountKind)
                        updateCachedTasks() // Refresh cached tasks after move
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksViewModel.crossAccountMoveTask(updatedTask, from: (accountKind, listId), to: (targetAccountKind, targetListId))
                        updateCachedTasks()
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private var eventDetailsSheet: some View {
        if let ev = selectedCalendarEvent {
            let accountKind: GoogleAuthManager.AccountKind = calendarViewModel.personalEvents.contains(where: { $0.id == ev.id }) ? .personal : .professional
            AddItemView(
                currentDate: ev.startTime ?? Date(),
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                existingEvent: ev,
                accountKind: accountKind
            )
        }
    }
    
    // MARK: - Current Time Timer Functions
    private func startCurrentTimeTimer() {
        // Update every 5 minutes instead of every minute to reduce performance impact
        currentTimeTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { _ in
            updateCurrentTimeSlot()
        }
        updateCurrentTimeSlot() // Initial update
    }
    
    private func stopCurrentTimeTimer() {
        currentTimeTimer?.invalidate()
        currentTimeTimer = nil
    }
    
    private func updateCurrentTimeSlot() {
        let currentTime = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        currentTimeSlot = Double(hour) * 2.0 + Double(minute) / 30.0
    }
    
    @ViewBuilder
    private func dayViewContent(geometry: GeometryProxy) -> some View {
        switch appPrefs.dayViewLayout {
        case .compact:
            DayViewNewCompact(
                bulkEditManager: bulkEditManager,
                onEventTap: { ev in
                    selectedCalendarEvent = ev
                    showingEventDetails = true
                }
            )
        case .mobile:
            DayViewMobile(
                bulkEditManager: bulkEditManager,
                onEventTap: { ev in
                    selectedCalendarEvent = ev
                    showingEventDetails = true
                }
            )
        case .timebox:
            DayViewNewExpanded(
                bulkEditManager: bulkEditManager,
                onEventTap: { ev in
                    selectedCalendarEvent = ev
                    showingEventDetails = true
                }
            )
        case .newClassic:
            DayViewNewClassic(
                bulkEditManager: bulkEditManager,
                onEventTap: { ev in
                    selectedCalendarEvent = ev
                    showingEventDetails = true
                }
            )
        default:
            dayViewContentCompact(geometry: geometry)
        }
    }
    
    private func dayViewContentCompact(geometry: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Left section (dynamic width)
            leftDaySectionWithDivider(geometry: geometry)
                .frame(width: dayLeftSectionWidth)
            
            // Vertical divider
            dayVerticalDivider

            // Right section expands to fill remaining space
            rightDaySection(geometry: geometry)
                .frame(maxWidth: .infinity)
        }
    }
    
    private func rightDaySection(geometry: GeometryProxy) -> some View {
        // The total content width is 100% of device width
        let totalWidth = geometry.size.width
        let _ = totalWidth - dayLeftSectionWidth - 8 // divider width (unused but kept for clarity)
        
        return VStack(spacing: 0) {
            // Top section - Tasks
            VStack(spacing: 0) {
                // Bulk Edit Toolbar (shown when in bulk edit mode)
                if bulkEditManager.state.isActive {
                    bulkEditToolbar
                }

                // Personal & Professional tasks (full width) with vertical scrolling
                ScrollView(.vertical, showsIndicators: true) {
                    topLeftDaySection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                }
            }
            .frame(height: rightSectionTopHeight, alignment: .top)
            .padding(.all, 8)
            .background(Color(.systemBackground))
            .clipped()
            .zIndex(0) // Ensure Tasks section is below Journal section when overlapping
            
            // Draggable divider
            rightSectionDivider
            
            // Bottom section - Journal
            VStack(alignment: .leading, spacing: 6) {
              
                JournalView(currentDate: $currentDate, embedded: true, layoutType: .compact)
            }
            .id(currentDate)
            .frame(maxHeight: .infinity)
            .padding(.all, 8)
            .background(Color(.systemBackground))
            .clipped()
            .zIndex(1) // Ensure Journal section overrides Tasks section when overlapping
        }
    }
    
        private func setupDayView() -> some View {
        dayView
    }
    
    private func leftDaySectionWithDivider(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Timeline section
            ScrollView(.vertical, showsIndicators: true) {
                eventsTimelineCard(height: nil)
                    .padding(.leading, 16 + geometry.safeAreaInsets.leading)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)
            .background(Color(.systemBackground))
            .clipped()

            // Logs section (collapsible drawer, only if any logs are enabled)
            if appPrefs.showAnyLogs {
                if !isLogsSectionCollapsed {
                    // Collapse button
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLogsSectionCollapsed = true
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
                        LogsComponent(currentDate: currentDate, horizontal: false)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Expand button when collapsed
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogsSectionCollapsed = false
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
            }
        }
        .frame(height: geometry.size.height, alignment: .top)
        .padding(.top, 0)
        .padding(.bottom, 8)
    }
    
    private var leftTimelineSection: some View {
        Group {
            if appPrefs.showEventsAsListInDay {
                ScrollView(.vertical, showsIndicators: true) {
                    dayEventsList
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                TimelineComponent(
                    date: currentDate,
                    events: getAllEventsForDate(currentDate),
                    personalEvents: calendarViewModel.personalEvents,
                    professionalEvents: calendarViewModel.professionalEvents,
                    personalColor: appPrefs.personalColor,
                    professionalColor: appPrefs.professionalColor,
                    onEventTap: { ev in
                        selectedCalendarEvent = ev
                        showingEventDetails = true
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // Shared Events timeline card used by all layouts
    private func eventsTimelineCard(height: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Events")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 8)
            leftTimelineSection
        }
        .frame(height: height, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 8)
        .padding(.bottom, 0)
        .padding(.leading, 8)
    }
    
    private var dayEventsList: some View {
        let events = getAllEventsForDate(currentDate)
            .sorted { (a, b) in
                let aDate = a.startTime ?? Date.distantPast
                let bDate = b.startTime ?? Date.distantPast
                return aDate < bDate
            }
        return EventsListComponent(
            events: events,
            personalEvents: calendarViewModel.personalEvents,
            professionalEvents: calendarViewModel.professionalEvents,
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor,
            onEventTap: { ev in
                selectedCalendarEvent = ev
                showingEventDetails = true
            },
            date: currentDate
        )
    }
    
    private var rightSectionDivider: some View {
        Rectangle()
            .fill(isRightDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isRightDividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isRightDividerDragging = true
                        let newHeight = rightSectionTopHeight + value.translation.height
                        rightSectionTopHeight = max(200, min(UIScreen.main.bounds.height - 300, newHeight))
                    }
                    .onEnded { _ in
                        isRightDividerDragging = false
                        appPrefs.updateCalendarDayRightSectionTopHeight(rightSectionTopHeight)
                    }
            )
    }
    
    
    private var weekDivider: some View {
        Rectangle()
            .fill(isWeekDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isWeekDividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isWeekDividerDragging = true
                        let newHeight = weekTopSectionHeight + value.translation.height
                        weekTopSectionHeight = max(200, min(UIScreen.main.bounds.height - 200, newHeight))
                    }
                    .onEnded { _ in
                        isWeekDividerDragging = false
                        appPrefs.updateCalendarWeekTopSectionHeight(weekTopSectionHeight)
                    }
            )
    }
    
    private var dayVerticalDivider: some View {
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
                        // Constrain to reasonable bounds: minimum 200pt, maximum 80% of screen width
                        dayLeftSectionWidth = max(200, min(UIScreen.main.bounds.width * 0.8, newWidth))
                    }
                    .onEnded { _ in
                        isDayVerticalDividerDragging = false
                        appPrefs.updateCalendarDayLeftSectionWidth(dayLeftSectionWidth)
                    }
            )
    }
    
    private var dayRightColumnDivider: some View {
        VStack(spacing: 4) {
            // Handle lines on left
            HStack(spacing: 4) {
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 1.5, height: 20)
                Spacer()
            }
            // Main divider line
            Rectangle()
                .fill(isDayRightColumnDividerDragging ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2))
                .frame(width: 1)
            // Handle lines on right
            HStack(spacing: 4) {
                Spacer()
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 1.5, height: 20)
            }
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDayRightColumnDividerDragging = true
                    let newWidth = dayRightColumn2Width + value.translation.width
                    // Constrain to reasonable bounds: minimum 150pt, maximum to leave space for other columns
                    dayRightColumn2Width = max(150, min(UIScreen.main.bounds.width * 0.4, newWidth))
                }
                .onEnded { _ in
                    isDayRightColumnDividerDragging = false
                    appPrefs.updateCalendarDayRightColumn2Width(dayRightColumn2Width)
                }
        )
    }
    

    
    private var timelineWithEvents: some View {
        ZStack(alignment: .topLeading) {
            // Background timeline grid
            VStack(spacing: 0) {
                ForEach(0..<48, id: \.self) { slot in
                    timelineSlot(slot: slot, showEvents: false)
                }
            }
            
            // Current time red line
            if Calendar.current.isDate(currentDate, inSameDayAs: Date()) {
                currentTimeRedLine
            }
            
            // Overlay events with smart positioning
            eventLayoutView
        }
    }
    
    private var currentTimeRedLine: some View {
        let currentTime = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        // Calculate position using same precise logic as events
        // Each hour = 100pt, each minute = 100pt / 60min = 1.667pt per minute
        let hourOffset = CGFloat(hour) * 100.0
        let minuteOffset = CGFloat(minute) * (100.0 / 60.0)
        let yOffset = hourOffset + minuteOffset
        
        return HStack(spacing: 0) {
            Spacer().frame(width: 43) // Space for time labels (35pt + 8pt spacing)
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
            Spacer().frame(width: 8)
        }
        .offset(y: yOffset)
        .zIndex(100)
    }
    
    private var eventLayoutView: some View {
        let timelineEvents = getTimelineEvents(date: currentDate)
        
        return GeometryReader { geometry in
            // The geometry here is for the timelineWithEvents view, which already accounts for the timeline column
            // Available width = total width - time labels (43) - spacing (8)
            let availableWidth = geometry.size.width - 43 - 8
            
            ForEach(timelineEvents, id: \.id) { event in
                let overlappingEvents = getOverlappingEvents(for: event, in: timelineEvents)
                let eventIndex = overlappingEvents.firstIndex(where: { $0.id == event.id }) ?? 0
                let totalOverlapping = overlappingEvents.count
                let eventWidth = totalOverlapping == 1 ? availableWidth : availableWidth / CGFloat(totalOverlapping)
                
                eventBlockView(event: event)
                    .frame(width: eventWidth)
                    .frame(height: event.height)
                    .offset(x: 43 + CGFloat(eventIndex) * eventWidth, 
                           y: event.topOffset)
            }
        }
    }
    

    
    private func timelineSlot(slot: Int, showEvents: Bool = true) -> some View {
        let hour = slot / 2
        let minute = (slot % 2) * 30
        let time = String(format: "%02d:%02d", hour, minute)
        let isHour = minute == 0
        _ = hour >= 7 && hour < 19 // 7am to 7pm default view
        
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Time label
                if isHour {
                    Text(time)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .trailing)
                } else {
                    Text(time)
                        .font(.caption2)
                        .foregroundColor(Color(.tertiaryLabel))
                        .frame(width: 35, alignment: .trailing)
                }
                
                // Timeline line and events
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(isHour ? Color(.systemGray3) : Color(.systemGray5))
                        .frame(height: isHour ? 1 : 0.5)
                    
                    // Event slots (only show when showEvents is true - for old implementation)
                    if showEvents {
                        HStack(spacing: 2) {
                            // Personal events column
                            if let personalEvent = getPersonalEvent(for: slot) {
                                eventBlock(event: personalEvent, color: .blue, isPersonal: true)
                            } else {
                                Spacer()
                                    .frame(height: 20)
                            }
                            
                            // Professional events column  
                            if let professionalEvent = getProfessionalEvent(for: slot) {
                                eventBlock(event: professionalEvent, color: .green, isPersonal: false)
                            } else {
                                Spacer()
                                    .frame(height: 20)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        // Just show empty space for timeline grid
                        Spacer()
                            .frame(maxWidth: .infinity)
                            .frame(height: 20)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 50) // Doubled from 25 to 50
        }
        .id(slot)
    }
    
    private func eventBlock(event: String, color: Color, isPersonal: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(0.2))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Text(event)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: 1)
            )
            // No long-press action for placeholder string events
    }
    
    

    
    private var pencilKitSection: some View {
        GeometryReader { geometry in
            ZStack {
                // Background canvas
                VStack(spacing: 12) {
                    HStack {
                        Text("Notes & Sketches")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        // Photo picker button
                        Button(action: {
                            requestPhotoLibraryAccess()
                        }) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // PencilKit Canvas
                    PencilKitView(canvasView: $canvasView)
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                        .frame(minHeight: 200)
                        .padding(.horizontal)
                        .padding(.bottom)
                }
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                
                // Moveable photos overlay
                ForEach(movablePhotos.indices, id: \.self) { index in
                    MovablePhotoView(
                        photo: $movablePhotos[index],
                        containerSize: geometry.size,
                        onDelete: {
                            movablePhotos.remove(at: index)
                        }
                    )
                }
            }
        }
        .padding(.all, 8)
        .onChange(of: selectedImages) { oldValue, newValue in
            // Convert new images to movable photos
            for (i, image) in newValue.enumerated() {
                if i >= oldValue.count {
                    // This is a new image
                    let position = CGPoint(
                        x: CGFloat.random(in: 50...200),
                        y: CGFloat.random(in: 80...150)
                    )
                    movablePhotos.append(MovablePhoto(image: image, position: position))
                }
            }
            // Clear the selectedImages array after converting
            if !newValue.isEmpty {
                selectedImages.removeAll()
            }
        }
    }
    
    // MARK: - Movable Photo View
    struct MovablePhotoView: View {
        @Binding var photo: MovablePhoto
        let containerSize: CGSize
        let onDelete: () -> Void
        @State private var isDragging = false
        
        var body: some View {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: photo.size.width, height: photo.size.height)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(isDragging ? 0.3 : 0.1), radius: isDragging ? 8 : 4)
                    .scaleEffect(isDragging ? 1.05 : 1.0)
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Circle())
                }
                .offset(x: 8, y: -8)
            }
            .position(photo.position)
            .animation(.easeOut(duration: 0.2), value: isDragging)
        }
    }
    
    // MARK: - Data Structures
    struct MovablePhoto: Identifiable {
        let id = UUID()
        let image: UIImage
        var position: CGPoint
        var size: CGSize = CGSize(width: 100, height: 100)
    }
    
    struct TimelineEvent: Identifiable, Hashable {
        let id = UUID()
        let event: GoogleCalendarEvent
        let startSlot: Int
        let endSlot: Int
        let isPersonal: Bool
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: TimelineEvent, rhs: TimelineEvent) -> Bool {
            return lhs.id == rhs.id
        }
        
        var topOffset: CGFloat {
            // Calculate from slots (which are already adjusted for multi-day events)
            // Each slot = 30 minutes = 50pt, so startSlot * 50 = offset
            return CGFloat(startSlot) * 50.0
        }
        
        var height: CGFloat {
            // Calculate from slots (which are already adjusted for multi-day events)
            // Each slot = 30 minutes = 50pt
            let slotDuration = endSlot - startSlot
            let calculatedHeight = CGFloat(slotDuration) * 50.0
            
            // Minimum height of 25pt for very short events
            return max(25.0, calculatedHeight)
        }
    }
    
    // MARK: - Timeline Calculation Methods

    private func getTimelineEvents(date: Date) -> [TimelineEvent] {
        var timelineEvents: [TimelineEvent] = []
        let calendar = Calendar.current
        
        // Process personal events
        for event in calendarViewModel.personalEvents {
            if event.isAllDay { continue }
            
            guard let startTime = event.startTime,
                  let endTime = event.endTime else { continue }
            
            // Determine if this is a multi-day event and which day we're rendering
            let eventStartDay = calendar.startOfDay(for: startTime)
            let eventEndDay = calendar.startOfDay(for: endTime)
            let currentDay = calendar.startOfDay(for: date)
            
            // Calculate adjusted start and end times for this specific day
            let dayStartTime: Date
            let dayEndTime: Date
            
            if eventStartDay == eventEndDay {
                // Single-day event
                dayStartTime = startTime
                dayEndTime = endTime
            } else if currentDay == eventStartDay {
                // First day of multi-day event: use actual start time to end of day
                dayStartTime = startTime
                dayEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentDay) ?? endTime
            } else if currentDay == eventEndDay {
                // Last day of multi-day event: use start of day to actual end time
                dayStartTime = calendar.startOfDay(for: currentDay)
                dayEndTime = endTime
            } else {
                // Middle day(s): use start of day to end of day (full day)
                dayStartTime = calendar.startOfDay(for: currentDay)
                dayEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentDay) ?? currentDay
            }
            
            let startSlot = timeToSlot(dayStartTime, isEndTime: false)
            let endSlot = timeToSlot(dayEndTime, isEndTime: true)
            
            if startSlot < 48 && endSlot > 0 { // Event is within our 24-hour view
                timelineEvents.append(TimelineEvent(
                    event: event,
                    startSlot: max(0, startSlot),
                    endSlot: min(48, endSlot),
                    isPersonal: true
                ))
            }
        }
        
        // Process professional events
        for event in calendarViewModel.professionalEvents {
            if event.isAllDay { continue }
            
            guard let startTime = event.startTime,
                  let endTime = event.endTime else { continue }
            
            // Determine if this is a multi-day event and which day we're rendering
            let eventStartDay = calendar.startOfDay(for: startTime)
            let eventEndDay = calendar.startOfDay(for: endTime)
            let currentDay = calendar.startOfDay(for: date)
            
            // Calculate adjusted start and end times for this specific day
            let dayStartTime: Date
            let dayEndTime: Date
            
            if eventStartDay == eventEndDay {
                // Single-day event
                dayStartTime = startTime
                dayEndTime = endTime
            } else if currentDay == eventStartDay {
                // First day of multi-day event: use actual start time to end of day
                dayStartTime = startTime
                dayEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentDay) ?? endTime
            } else if currentDay == eventEndDay {
                // Last day of multi-day event: use start of day to actual end time
                dayStartTime = calendar.startOfDay(for: currentDay)
                dayEndTime = endTime
            } else {
                // Middle day(s): use start of day to end of day (full day)
                dayStartTime = calendar.startOfDay(for: currentDay)
                dayEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentDay) ?? currentDay
            }
            
            let startSlot = timeToSlot(dayStartTime, isEndTime: false)
            let endSlot = timeToSlot(dayEndTime, isEndTime: true)
            
            if startSlot < 48 && endSlot > 0 { // Event is within our 24-hour view
                timelineEvents.append(TimelineEvent(
                    event: event,
                    startSlot: max(0, startSlot),
                    endSlot: min(48, endSlot),
                    isPersonal: false
                ))
            }
        }
        
        return timelineEvents.sorted { $0.startSlot < $1.startSlot }
    }
    
    private func getOverlappingEvents(for event: TimelineEvent, in events: [TimelineEvent]) -> [TimelineEvent] {
        return events.filter { otherEvent in
            eventsOverlap(event, otherEvent)
        }.sorted { $0.startSlot < $1.startSlot }
    }
    
    private func eventsOverlap(_ event1: TimelineEvent, _ event2: TimelineEvent) -> Bool {
        return event1.startSlot < event2.endSlot && event2.startSlot < event1.endSlot
    }
    
    private func timeToSlot(_ time: Date, isEndTime: Bool = false) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        // For start times, round down to the nearest 30-minute slot
        // For end times, round up to ensure events show up even if they're shorter than 30 minutes
        if isEndTime {
            // If minute is > 0, round up to the next 30-minute slot
            return hour * 2 + (minute > 0 ? (minute >= 30 ? 2 : 1) : 0)
        } else {
            // For start times, round down as before
            return hour * 2 + (minute >= 30 ? 1 : 0)
        }
    }
    
    private func eventBlockView(event: TimelineEvent) -> some View {
        let color: Color = event.isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(0.2))
            .overlay(
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.event.summary)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                    
                    if event.height >= 50 { // Show time only if event is tall enough
                        Text(formatEventTime(event.event))
                            .font(.caption2)
                            .foregroundColor(color.opacity(0.8))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: 1.5)
            )
            // No long-press action for placeholder string events
            .onLongPressGesture {
                selectedCalendarEvent = event.event
                showingEventDetails = true
            }
    }
    
    private func formatEventTime(_ event: GoogleCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        guard let startTime = event.startTime,
              let endTime = event.endTime else { return "" }
        
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    

    
    // Group month events by date for the MonthTimelineComponent
    // MARK: - Event Query Methods

    private func getMonthEventsGroupedByDate() -> [Date: [GoogleCalendarEvent]] {
        let monthDates = getMonthDates()
        var eventsGroupedByDate: [Date: [GoogleCalendarEvent]] = [:]
        
        var allEvents: [GoogleCalendarEvent] = []
        if authManager.isLinked(kind: .personal) {
            allEvents += calendarViewModel.personalEvents
        }
        if authManager.isLinked(kind: .professional) {
            allEvents += calendarViewModel.professionalEvents
        }
        
        
        // Filter out recurring events if the setting is enabled
        if appPrefs.hideRecurringEventsInMonth {
            let allEventsForRecurringDetection = allEvents
            let recurringEvents = allEvents.filter { $0.isLikelyRecurring(among: allEventsForRecurringDetection) }
            for _ in recurringEvents {
            }
            allEvents = allEvents.filter { !$0.isLikelyRecurring(among: allEventsForRecurringDetection) }
        }
        
        for date in monthDates {
            let calendar = Calendar.current
            let eventsForDate = allEvents.filter { event in
                guard let startTime = event.startTime else { return event.isAllDay }
                
                if event.isAllDay {
                    // For all-day events, check if the date falls within the event's date range
                    guard let endTime = event.endTime else { return false }
                    
                    // For all-day events, Google Calendar typically sets the end time to the start of the next day
                    // But for single-day events, end.date might equal start.date
                    // So we need to check if the date falls within [startTime, endTime)
                    let startDay = calendar.startOfDay(for: startTime)
                    let endDay = calendar.startOfDay(for: endTime)
                    let dateDay = calendar.startOfDay(for: date)
                    
                    // For properly formed all-day events, endDay should be exclusive (start + n days)
                    if endDay <= startDay {
                        return dateDay == startDay
                    }
                    // Otherwise, include dates in [startDay, endDay)
                    return dateDay >= startDay && dateDay < endDay
                } else {
                    // For timed events, check if the date falls within the event's date range
                    guard let endTime = event.endTime else {
                        // If no end time, only show on start date
                        return calendar.isDate(startTime, inSameDayAs: date)
                    }
                    
                    let startDay = calendar.startOfDay(for: startTime)
                    let endDay = calendar.startOfDay(for: endTime)
                    let dateDay = calendar.startOfDay(for: date)
                    
                    // If event is on the same day, show only if date matches
                    if endDay == startDay {
                        return dateDay == startDay
                    }
                    
                    // Otherwise, show if date is within [startDay, endDay]
                    // Include both start and end days
                    return dateDay >= startDay && dateDay <= endDay
                }
            }
            eventsGroupedByDate[date] = eventsForDate
            
            if !eventsForDate.isEmpty {
            }
        }
        
        let totalEventsInGrouped = eventsGroupedByDate.values.flatMap { $0 }.count
        
        return eventsGroupedByDate
    }
    
    private func getMonthDates() -> [Date] {
        let calendar = Calendar.mondayFirst
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate) else {
            return []
        }
        
        var dates: [Date] = []
        var date = monthInterval.start
        
        while date < monthInterval.end {
            dates.append(date)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }
        
        return dates
    }
    
    private func getEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        calendarViewModel.events(for: date).filter { !$0.isAllDay }
    }
    
    // New function that includes ALL events (both all-day and timed) for the TimelineComponent
    private func getAllEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        calendarViewModel.events(for: date)
    }
    
    private func getAllDayEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        calendarViewModel.events(for: date).filter { $0.isAllDay }
    }
    

    // Real event data from Google Calendar
    private func getPersonalEvent(for slot: Int) -> String? {
        return getEventForTimeSlot(slot, events: calendarViewModel.personalEvents)
    }
    
    private func getProfessionalEvent(for slot: Int) -> String? {
        return getEventForTimeSlot(slot, events: calendarViewModel.professionalEvents)
    }
    
    private func getEventForTimeSlot(_ slot: Int, events: [GoogleCalendarEvent]) -> String? {
        let hour = slot / 2
        let minute = (slot % 2) * 30
        
        let calendar = Calendar.current
        let slotTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: currentDate) ?? currentDate
        
        // Find events that overlap with this time slot (excluding all-day events)
        for event in events {
            // Skip all-day events (they are shown separately at the top)
            if event.isAllDay { continue }
            
            guard let startTime = event.startTime,
                  let endTime = event.endTime else { continue }
            
            // Check if the slot time falls within the event duration
            if slotTime >= startTime && slotTime < endTime {
                return event.summary
            }
        }
        
        return nil
    }
    
    private func getAllDayEvents() -> [GoogleCalendarEvent] {
        let allEvents = (authManager.isLinked(kind: .personal) ? calendarViewModel.personalEvents : []) +
                        (authManager.isLinked(kind: .professional) ? calendarViewModel.professionalEvents : [])
        return allEvents.filter { $0.isAllDay }
    }
    
    private func allDayEventBlock(event: GoogleCalendarEvent) -> some View {
        let isPersonal = calendarViewModel.personalEvents.contains { $0.id == event.id }
        let color: Color = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(event.summary)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var topLeftDaySection: some View {
        HStack(spacing: 8) {
            // Personal Tasks
            let personalFiltered = filteredTasksForDate(tasksViewModel.personalTasks, date: currentDate)
            if authManager.isLinked(kind: .personal) && !personalFiltered.values.flatMap({ $0 }).isEmpty {
                TasksComponent(
                    taskLists: tasksViewModel.personalTaskLists,
                    tasksDict: personalFiltered,
                    accentColor: appPrefs.personalColor,
                    accountType: .personal,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                            updateCachedTasks()
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .personal)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                        }
                    },
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if !authManager.isLinked(kind: .personal) && !authManager.isLinked(kind: .professional) {
                // Empty state in Day view, placed in Tasks area
                Button(action: { NavigationManager.shared.showSettings() }) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Link Your Google Account")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Connect your Google account to view and manage your calendar events and tasks")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // Professional Tasks
            let professionalFiltered = filteredTasksForDate(tasksViewModel.professionalTasks, date: currentDate)
            if authManager.isLinked(kind: .professional) && !professionalFiltered.values.flatMap({ $0 }).isEmpty {
                TasksComponent(
                    taskLists: tasksViewModel.professionalTaskLists,
                    tasksDict: professionalFiltered,
                    accentColor: appPrefs.professionalColor,
                    accountType: .professional,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                            updateCachedTasks()
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = CalendarTaskSelection(task: task, listId: listId, accountKind: .professional)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                        }
                    },
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    // MARK: - Task Card Views

    }
    

    
    private func personalTaskListCard(taskList: GoogleTaskList, tasks: [GoogleTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Task list header
            HStack {
                Text(taskList.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(appPrefs.personalColor)
                
                Spacer()
                
                // Removed task count display
            }
            
            // Tasks for this list
            VStack(spacing: 4) {
                ForEach(tasks, id: \.id) { task in
                    personalTaskRow(task: task, taskListId: taskList.id)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    private func isDueDateOverdue(_ dueDate: Date) -> Bool {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return dueDate < startOfToday
    }
    

    
    private func personalTaskRow(task: GoogleTask, taskListId: String) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                Task {
                    await tasksViewModel.toggleTaskCompletion(task, in: taskListId, for: .personal)
                }
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(task.isCompleted ? appPrefs.personalColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            HStack(spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                if let dueDate = task.dueDate {
                    HStack(spacing: 2) {
                        Text(dueDate, formatter: Self.dateFormatter)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isDueDateOverdue(dueDate) && !task.isCompleted ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
                    )
                    .foregroundColor(isDueDateOverdue(dueDate) && !task.isCompleted ? .red : .secondary)
                }
            }
        }
        .onLongPressGesture {
            selectedTask = task
            selectedTaskListId = taskListId
            selectedAccountKind = .personal
            DispatchQueue.main.async {
                showingTaskDetails = true
            }
        }
    }
    
    private var topRightDaySection: some View {
        TasksComponent(
            taskLists: tasksViewModel.professionalTaskLists,
            tasksDict: filteredTasksForDate(tasksViewModel.professionalTasks, date: currentDate),
            accentColor: appPrefs.professionalColor,
            accountType: .professional,
            onTaskToggle: { task, listId in
                Task {
                    await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                    updateCachedTasks()
                }
            },
            onTaskDetails: { task, listId in
                selectedTask = task
                selectedTaskListId = listId
                selectedAccountKind = .professional
                DispatchQueue.main.async {
                    showingTaskDetails = true
                }
            },
            onListRename: { listId, newName in
                Task {
                    await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                }
            },
            onOrderChanged: { newOrder in
                Task {
                    await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                }
            },
            isSingleDayView: true
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private var topThirdDaySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Third Column")
                    .font(.headline)
                Spacer()
                Text("Available for future features")
                    .foregroundColor(.secondary)
                Spacer()
             }
         }
        .frame(maxHeight: .infinity)
        .padding(12)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(8)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private func professionalTaskListCard(taskList: GoogleTaskList, tasks: [GoogleTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Task list header
            HStack {
                Text(taskList.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(appPrefs.professionalColor)
                
                Spacer()
                
                // Removed task count display
            }
            
            // Tasks for this list
            VStack(spacing: 4) {
                ForEach(tasks, id: \.id) { task in
                    professionalTaskRow(task: task, taskListId: taskList.id)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    private func professionalTaskRow(task: GoogleTask, taskListId: String) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                Task {
                    await tasksViewModel.toggleTaskCompletion(task, in: taskListId, for: .professional)
                }
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(task.isCompleted ? appPrefs.professionalColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            HStack(spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                if let dueDate = task.dueDate {
                    HStack(spacing: 2) {
                        Text(dueDate, formatter: Self.dateFormatter)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isDueDateOverdue(dueDate) && !task.isCompleted ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
                    )
                    .foregroundColor(isDueDateOverdue(dueDate) && !task.isCompleted ? .red : .secondary)
                }
            }
        }
        .onLongPressGesture {
            selectedTask = task
            selectedTaskListId = taskListId
            selectedAccountKind = .professional
            DispatchQueue.main.async {
                showingTaskDetails = true
            }
        }
    }
    

    
    // MARK: - Photo Library Permission Methods
    private func requestPhotoLibraryAccess() {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch currentStatus {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    self.photoLibraryAuthorizationStatus = status
                    if status == .authorized || status == .limited {
                        self.showingPhotoPicker = true
                    } else {
                        self.showingPhotoPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showingPhotoPermissionAlert = true
        case .authorized, .limited:
            showingPhotoPicker = true
        @unknown default:
            showingPhotoPermissionAlert = true
        }
    }
    
    private func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    private func handleSelectedPhoto(_ photo: PhotosPickerItem) {
        Task {
            if let data = try? await photo.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    // Add the image to our array of selected images
                    selectedImages.append(uiImage)
                    
                    // Reset the selection for next time
                    selectedPhoto = nil
                }
            }
        }
    }
    // MARK: - Task Management Methods

    

    
    // MARK: - Helper Methods for Real Tasks
    private func getAllTasksForBulkEdit() -> [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] {
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Add personal tasks
        for (listId, tasks) in cachedMonthPersonalTasks {
            for task in tasks {
                allTasks.append((task: task, listId: listId, accountKind: .personal))
            }
        }

        // Add professional tasks
        for (listId, tasks) in cachedMonthProfessionalTasks {
            for task in tasks {
                allTasks.append((task: task, listId: listId, accountKind: .professional))
            }
        }

        return allTasks
    }

    private func performUndo(action: BulkEditAction, data: BulkEditUndoData) {
        switch action {
        case .complete:
            bulkEditManager.undoComplete(data: data, tasksVM: tasksViewModel)
        case .delete:
            bulkEditManager.undoDelete(data: data, tasksVM: tasksViewModel)
        case .move:
            bulkEditManager.undoMove(data: data, tasksVM: tasksViewModel)
        case .updateDueDate:
            bulkEditManager.undoUpdateDueDate(data: data, tasksVM: tasksViewModel)
        case .updatePriority:
            bulkEditManager.undoUpdatePriority(data: data, tasksVM: tasksViewModel)
        }

        // Update cached tasks after undo
        updateCachedTasks()
        updateMonthCachedTasks()
    }

    private func updateCachedTasks() {

        cachedPersonalTasks = authManager.isLinked(kind: .personal) ? filteredTasksForDate(tasksViewModel.personalTasks, date: currentDate) : [:]
        cachedProfessionalTasks = authManager.isLinked(kind: .professional) ? filteredTasksForDate(tasksViewModel.professionalTasks, date: currentDate) : [:]


        // Debug: Print first few task titles to verify content
        let _ = cachedPersonalTasks.values.flatMap { $0 }.prefix(3).map { $0.title }
        let _ = cachedProfessionalTasks.values.flatMap { $0 }.prefix(3).map { $0.title }

        // Force UI update
        DispatchQueue.main.async {
            // This should trigger a UI refresh
        }

        updateMonthCachedTasks() // Also update month cached tasks
    }
    

    // MARK: - Task Filtering Methods

    
    private func updateMonthCachedTasks() {
        cachedMonthPersonalTasks = authManager.isLinked(kind: .personal) ? filteredTasksForMonth(tasksViewModel.personalTasks, date: currentDate) : [:]
        cachedMonthProfessionalTasks = authManager.isLinked(kind: .professional) ? filteredTasksForMonth(tasksViewModel.professionalTasks, date: currentDate) : [:]
    }
    
    private func filteredTasksForDate(_ tasksDict: [String: [GoogleTask]], date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.current
        
        return tasksDict.mapValues { tasks in
            var filteredTasks = tasks
            
            // Filter out completed tasks if hideCompletedTasks is enabled
            if appPrefs.hideCompletedTasks {
                filteredTasks = filteredTasks.filter { !$0.isCompleted }
            }
            
            // Then filter tasks based on date logic
            filteredTasks = filteredTasks.compactMap { task in
                // For completed tasks, only show them on their completion date
                if task.isCompleted {
                    guard let completionDate = task.completionDate else { return nil }
                    let isOnSameDay = calendar.isDate(completionDate, inSameDayAs: date)
                    
                    // Debug logging for completion date issues
                    if !isOnSameDay {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .short
                        formatter.timeStyle = .short
                    }
                    
                    return isOnSameDay ? task : nil
                } else {
                    // For incomplete tasks, show them on due date OR, if viewing today, show overdue
                    guard let dueDate = task.dueDate else { return nil }

                    let startOfViewedDate = calendar.startOfDay(for: date)
                    let startOfDueDate = calendar.startOfDay(for: dueDate)
                    let startOfToday = calendar.startOfDay(for: Date())
                    
                    let isDueOnViewedDate = calendar.isDate(dueDate, inSameDayAs: date)
                    let isViewingToday = calendar.isDate(date, inSameDayAs: Date())
                    let isViewingDueDate = startOfViewedDate == startOfDueDate
                    let isOverdue = startOfDueDate < startOfToday
                    
                    // Show task if:
                    // 1. We're viewing its due date (past or future), OR
                    // 2. We're viewing today AND it's overdue
                    let include = isViewingDueDate || (isViewingToday && isOverdue)
                    
                    return include ? task : nil
                }
            }
            
            return filteredTasks
        }
    }
    
    private func filteredTasksForWeek(_ tasksDict: [String: [GoogleTask]], date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return [:]
        }
        
        return tasksDict.mapValues { tasks in
            var filteredTasks = tasks
            
            // No longer filtering by hide completed tasks setting
            
            // Then filter tasks based on week date logic
            filteredTasks = filteredTasks.compactMap { task in
                // For completed tasks, only show them on their completion date
                if task.isCompleted {
                    guard let completionDate = task.completionDate else { return nil }
                    return completionDate >= weekStart && completionDate < weekEnd ? task : nil
                } else {
                    // For incomplete tasks, show them if their due date is within the week OR if they're overdue
                    guard let dueDate = task.dueDate else { return nil }
                    
                    let isWithinWeek = dueDate >= weekStart && dueDate < weekEnd
                    let isOverdue = dueDate < calendar.startOfDay(for: Date())
                    
                    // Include tasks within the week OR overdue tasks (they'll appear on today's column)
                    return isWithinWeek || isOverdue ? task : nil
                }
            }
            
            return filteredTasks
        }
    }
    
    private func filteredTasksForMonth(_ tasksDict: [String: [GoogleTask]], date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start,
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return [:]
        }
        
        return tasksDict.mapValues { tasks in
            var filteredTasks = tasks
            
            // No longer filtering by hide completed tasks setting
            
            // Then filter tasks based on month date logic
            filteredTasks = filteredTasks.compactMap { task in
                // For completed tasks, only show them on their completion date
                if task.isCompleted {
                    guard let completionDate = task.completionDate else { return nil }
                    return completionDate >= monthStart && completionDate < monthEnd ? task : nil
                } else {
                    // For incomplete tasks, only show them if their due date is within the month
                    guard let dueDate = task.dueDate else { return nil }
                    
                    // Only include tasks with due dates within the month (no overdue tasks from previous months)
                    return dueDate >= monthStart && dueDate < monthEnd ? task : nil
                }
            }
            
            return filteredTasks
        }
    }
    
    private func onEventLongPress(_ ev: GoogleCalendarEvent) {
        selectedCalendarEvent = ev
        showingEventDetails = true
    }
}

// MARK: - Week PencilKit View
