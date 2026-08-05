import SwiftUI
import Combine
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct TimeboxView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var calendarVM = CalendarViewModel.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @ObservedObject private var bulkEditManager: BulkEditManager

    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State private var selectedEvent: GoogleCalendarEvent?
    @State private var taskSheetSelection: TimeboxTaskSelection?

    struct TimeboxTaskSelection: Identifiable {
        let id: String
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }

    // MARK: - Computed Properties
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
            return []
        }
        let start = weekInterval.start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Per-day events derived from CalendarViewModel's day-keyed cache.
    /// Cheap to recompute: 7 × O(1) hash lookups on already-built caches.
    /// Replaces the prior `@State weeklyEventsCache` + `refreshWeekCaches`
    /// pattern, which fired on four separate `.onReceive` listeners and
    /// rebuilt the dict four times per change wave.
    private var weeklyEventsByDate: [Date: [GoogleCalendarEvent]] {
        var map: [Date: [GoogleCalendarEvent]] = [:]
        for date in weekDates {
            map[date] = calendarVM.events(for: date)
        }
        return map
    }

    /// Per-day merged personal+professional tasks from TasksViewModel's
    /// day-keyed cache (built once via didSet on the published task dicts).
    /// Personal wins on a duplicate listId.
    private var weeklyTasksByDate: [Date: [String: [GoogleTask]]] {
        var map: [Date: [String: [GoogleTask]]] = [:]
        for date in weekDates {
            let p = tasksVM.tasksForDay(date, kind: .personal)
            let pr = tasksVM.tasksForDay(date, kind: .professional)
            map[date] = p.merging(pr) { lhs, _ in lhs }
        }
        return map
    }
    
    // MARK: - Adaptive Layout Properties
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    private func visibleDaysCount(for geometry: GeometryProxy) -> Int {
        let w = geometry.size.width
        let h = geometry.size.height
        let isLandscape = w > h

        if isCompact {
            // iPhone: 1 day in portrait, 2 in landscape
            return isLandscape ? 2 : 1
        }

        // For screens larger than iPad (laptops): show all 7 days
        if w > 1200 {
            return 7
        }

#if os(iOS)
        // iPad: 4 columns in portrait (fit across width), 7 in landscape (full week fits)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return isLandscape ? 7 : 4
        }
#endif

        // Other (e.g. Mac): 3 portrait, 5 landscape
        return isLandscape ? 5 : 3
    }
    
    private func dayColumnWidth(availableWidth: CGFloat, visibleDays: Int) -> CGFloat {
        // Account for padding (12 * 2 = 24) and the leading time-label
        // gutter that the timeline draws to host hour numbers.
        let availableContentWidth = availableWidth - 24 - DraggableTimeboxWeekContent.timeColumnWidth
        return availableContentWidth / CGFloat(visibleDays)
    }

    private func totalContentWidth(availableWidth: CGFloat, visibleDays: Int) -> CGFloat {
        // Total width = gutter + 7 day columns
        return DraggableTimeboxWeekContent.timeColumnWidth + dayColumnWidth(availableWidth: availableWidth, visibleDays: visibleDays) * 7
    }
    
    private func visibleOpenTaskIdsForWeek() -> Set<String> {
        var ids: Set<String> = []
        for date in weekDates {
            let dict = weeklyTasksByDate[date] ?? [:]
            ids.formUnion(dict.openTaskIds)
        }
        return ids
    }

    private func weekDayColumnHeader(date: Date, isToday: Bool) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(dayOfWeekAbbrev(from: date))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isToday ? .white : .secondary)
            
            Text(formatDateShort(from: date))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(isToday ? .white : .primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(isToday ? Color.blue : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            // Navigate to the selected day's day view
            if hideNavBar {
                // Inside BookView: use notification so currentView stays .bookView
                NotificationCenter.default.post(name: .bookViewNavigateToDay, object: date)
            } else {
                navigationManager.switchToCalendar()
                navigationManager.updateInterval(.day, date: date)
            }
        }
    }
    
    /// Static formatters — DateFormatter() is expensive to instantiate
    /// (~5-10ms) and was being created on every header render.
    private static let dayAbbrevFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private func dayOfWeekAbbrev(from date: Date) -> String {
        Self.dayAbbrevFormatter.string(from: date).uppercased()
    }

    private func formatDateShort(from date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }

    private let hideNavBar: Bool

    init(bulkEditManager: BulkEditManager, hideNavBar: Bool = false) {
        self._bulkEditManager = ObservedObject(wrappedValue: bulkEditManager)
        self.hideNavBar = hideNavBar
    }

    private var baseView: some View {
        VStack(spacing: 0) {
            // Bulk Edit Toolbar (shown when in bulk edit mode)
            if bulkEditManager.state.isActive {
                BulkEditToolbarView(
                    bulkEditManager: bulkEditManager,
                    visibleOpenTaskIds: visibleOpenTaskIdsForWeek()
                )
            }

            // Global Navigation Bar
            if !hideNavBar {
                GlobalNavBar()
                    .background(.ultraThinMaterial)
            }
            
            GeometryReader { geometry in
                let availableWidth = geometry.size.width
                let visibleDays = visibleDaysCount(for: geometry)
                let columnWidth = dayColumnWidth(availableWidth: availableWidth, visibleDays: visibleDays)
                let contentWidth = totalContentWidth(availableWidth: availableWidth, visibleDays: visibleDays)
                
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            if weekDates.count == 7 {
                                // Fixed header row with day dates (7 columns).
                                // Leading clear gutter matches the timeline's
                                // hour-label column below so day headers line
                                // up directly over their day columns.
                                HStack(spacing: 0) {
                                    Color.clear
                                        .frame(width: DraggableTimeboxWeekContent.timeColumnWidth, height: 60)
                                    ForEach(0..<weekDates.count, id: \.self) { index in
                                        let date = weekDates[index]
                                        let calendar = Calendar.mondayFirst
                                        let isToday = calendar.isDate(date, inSameDayAs: Date())
                                        weekDayColumnHeader(date: date, isToday: isToday)
                                            .frame(width: columnWidth)
                                            .background(Color(.systemGray6))
                                            .id("day_\(index)")

                                        // Divider between days (except for the last one)
                                        if index < weekDates.count - 1 {
                                            Rectangle()
                                                .fill(Color(.systemGray4))
                                                .frame(width: 1)
                                        }
                                    }
                                }
                                .frame(width: contentWidth, height: 60)
                                .background(Color(.systemBackground))
                                
                                // Unified scrollable timeline with drag-aware
                                // 7-column rendering. Owns SwiftUI gestures
                                // so users can drag events/tasks across
                                // both time and day axes.
                                let eventsByDate = weeklyEventsByDate
                                let tasksByDate = weeklyTasksByDate
                                let allDayHeight = calculateMaxAllDayHeight(
                                    eventsCache: eventsByDate,
                                    tasksCache: tasksByDate
                                )
                                ScrollView(.vertical, showsIndicators: true) {
                                    DraggableTimeboxWeekContent(
                                        weekDates: weekDates,
                                        columnWidth: columnWidth,
                                        allDayHeight: allDayHeight,
                                        eventsByDate: eventsByDate,
                                        tasksByDate: tasksByDate,
                                        personalColor: appPrefs.personalColor,
                                        professionalColor: appPrefs.professionalColor,
                                        isBulkEditMode: bulkEditManager.state.isActive,
                                        selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                                        onEventTap: { event in selectedEvent = event },
                                        onTaskTap: { task, listId in
                                            let accountKind: GoogleAuthManager.AccountKind = tasksVM.personalTasks[listId] != nil ? .personal : .professional
                                            taskSheetSelection = TimeboxTaskSelection(
                                                id: task.id,
                                                task: task,
                                                listId: listId,
                                                accountKind: accountKind
                                            )
                                        },
                                        onTaskToggle: { task, listId in
                                            let accountKind: GoogleAuthManager.AccountKind = tasksVM.personalTasks[listId] != nil ? .personal : .professional
                                            Task { await tasksVM.toggleTaskCompletion(task, in: listId, for: accountKind) }
                                        },
                                        onTaskSelectionToggle: { task in
                                            if bulkEditManager.state.selectedTaskIds.contains(task.id) {
                                                bulkEditManager.state.selectedTaskIds.remove(task.id)
                                            } else {
                                                bulkEditManager.state.selectedTaskIds.insert(task.id)
                                            }
                                        },
                                        // SwiftUI re-renders this view automatically when
                                        // the underlying VMs publish, so onCommit has no
                                        // additional work to do.
                                        onCommit: { }
                                    )
                                    .frame(width: contentWidth)
                                    .padding(.horizontal, 12)
                                }
                            } else {
                                // Fallback if week dates couldn't be calculated
                                Text("Unable to load week dates")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(width: contentWidth)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // Scroll to today's position
                            let calendar = Calendar.mondayFirst
                            let today = Date()
                            
                            if let index = weekDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: today) }) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo("day_\(index)", anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var baseViewWithNavigation: some View {
        baseView
        .sidebarToggleHidden()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
    }

    private var baseViewWithLifecycle: some View {
        baseViewWithNavigation
        .task {
            // Load calendar data for the current week
            await calendarVM.loadCalendarDataForWeek(containing: navigationManager.currentDate)
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            Task {
                // Load calendar data when the date changes
                await calendarVM.loadCalendarDataForWeek(containing: newValue)
            }
        }
        .sheet(item: Binding<GoogleCalendarEvent?>(
            get: { selectedEvent },
            set: { selectedEvent = $0 }
        )) { ev in
            let accountKind = calendarVM.accountKind(for: ev)
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
        .sheet(item: $taskSheetSelection) { sel in
            TaskDetailsView(
                task: sel.task,
                taskListId: sel.listId,
                accountKind: sel.accountKind,
                accentColor: sel.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksVM.personalTaskLists,
                professionalTaskLists: tasksVM.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksVM,
                onSave: { updatedTask in
                    Task {
                        await tasksVM.updateTask(updatedTask, in: sel.listId, for: sel.accountKind)
                    }
                },
                onDelete: {
                    Task {
                        // Delete the task
                        await tasksVM.deleteTask(sel.task, from: sel.listId, for: sel.accountKind)
                        // Also delete the time window for this task
                        TaskTimeWindowManager.shared.deleteTimeWindow(for: sel.task.id)
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksVM.moveTask(updatedTask, from: sel.listId, to: targetListId, for: sel.accountKind)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksVM.crossAccountMoveTask(updatedTask, from: (sel.accountKind, sel.listId), to: (targetAccountKind, targetListId))
                    }
                }
            )
        }
    }

    var body: some View {
        baseViewWithLifecycle
        .onAppear {
            // Listen for bulk edit toggle notification
            NotificationCenter.default.addObserver(
                forName: Notification.Name("ToggleTimeboxBulkEdit"),
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    bulkEditManager.state.isActive.toggle()
                    if !bulkEditManager.state.isActive {
                        bulkEditManager.state.selectedTaskIds.removeAll()
                    }
                }
            }
        }
        // Bulk edit confirmation dialogs
        .confirmationDialog("Complete Tasks", isPresented: $bulkEditManager.state.showingCompleteConfirmation) {
            Button("Complete \(bulkEditManager.state.selectedTaskIds.count) task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")") {
                Task {
                    let allTasks = getAllTasksForBulkEdit()
                    await bulkEditManager.bulkComplete(tasks: allTasks, tasksVM: tasksVM) { undoData in
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
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete Tasks", isPresented: $bulkEditManager.state.showingDeleteConfirmation) {
            Button("Delete \(bulkEditManager.state.selectedTaskIds.count) task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")", role: .destructive) {
                Task {
                    let allTasks = getAllTasksForBulkEdit()
                    await bulkEditManager.bulkDelete(tasks: allTasks, tasksVM: tasksVM) { undoData in
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
            }
            Button("Cancel", role: .cancel) {}
        }
        // Bulk edit sheets
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
                        tasksVM: tasksVM
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

                    bulkEditManager.state.showingDueDatePicker = false
                }
            }
        }
        .sheet(isPresented: $bulkEditManager.state.showingMoveDestinationPicker) {
            BulkMoveDestinationPicker(
                personalTaskLists: tasksVM.personalTaskLists,
                professionalTaskLists: tasksVM.professionalTaskLists,
                onSelect: { accountKind, listId in
                    Task {
                        let allTasks = getAllTasksForBulkEdit()
                        await bulkEditManager.bulkMove(
                            tasks: allTasks,
                            to: listId,
                            destinationAccountKind: accountKind,
                            tasksVM: tasksVM
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

                        bulkEditManager.state.showingMoveDestinationPicker = false
                    }
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
                        tasksVM: tasksVM
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

    // MARK: - Bulk Edit Helper
    private func getAllTasksForBulkEdit() -> [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] {
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Add personal tasks
        for (listId, tasks) in tasksVM.personalTasks {
            for task in tasks {
                allTasks.append((task: task, listId: listId, accountKind: .personal))
            }
        }

        // Add professional tasks
        for (listId, tasks) in tasksVM.professionalTasks {
            for task in tasks {
                allTasks.append((task: task, listId: listId, accountKind: .professional))
            }
        }

        return allTasks
    }

    private func performUndo(action: BulkEditAction, data: BulkEditUndoData) {
        switch action {
        case .complete:
            bulkEditManager.undoComplete(data: data, tasksVM: tasksVM)
        case .delete:
            bulkEditManager.undoDelete(data: data, tasksVM: tasksVM)
        case .move:
            bulkEditManager.undoMove(data: data, tasksVM: tasksVM)
        case .updateDueDate:
            bulkEditManager.undoUpdateDueDate(data: data, tasksVM: tasksVM)
        case .updatePriority:
            bulkEditManager.undoUpdatePriority(data: data, tasksVM: tasksVM)
        }
    }


    // Calculate max all-day height across all days in the week
    private func calculateMaxAllDayHeight(eventsCache: [Date: [GoogleCalendarEvent]], tasksCache: [Date: [String: [GoogleTask]]]) -> CGFloat {
        guard !weekDates.isEmpty else { return 20 }
        let lineHeight: CGFloat = 20 + 12 + 4 // approximate per-line height
        let timeWindowManager = TaskTimeWindowManager.shared
        
        let maxHeight = weekDates.map { date -> CGFloat in
            let eventsForDate = eventsCache[date] ?? []
            let tasksForDate = tasksCache[date] ?? [:]
            
            let allDayEvents = eventsForDate.filter { $0.isAllDay }
            var allDayTasks = tasksForDate.values.flatMap { $0 }.filter { task in
                if let timeWindow = timeWindowManager.getTimeWindow(for: task.id) {
                    return timeWindow.isAllDay
                }
                return true // If no time window, treat as all-day
            }
            
            if appPrefs.hideCompletedTasks {
                allDayTasks = allDayTasks.filter { !$0.isCompleted }
            }
            
            let eventsRowHeight: CGFloat = allDayEvents.isEmpty ? 0 : CGFloat(allDayEvents.count) * lineHeight
            let tasksRowHeight: CGFloat = allDayTasks.isEmpty ? 0 : CGFloat(allDayTasks.count) * lineHeight
            let spacing: CGFloat = (allDayEvents.isEmpty || allDayTasks.isEmpty) ? 0 : 4
            
            let totalHeight = eventsRowHeight + tasksRowHeight + spacing
            return max(totalHeight, 20)
        }.max() ?? 20
        
        return maxHeight
    }
    
}
