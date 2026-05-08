import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif


struct WeeklyView: View {
    @EnvironmentObject var appPrefs: AppPreferences
    @ObservedObject var calendarViewModel = CalendarViewModel.shared
    @ObservedObject var tasksViewModel = TasksViewModel.shared
    @ObservedObject var authManager = GoogleAuthManager.shared
    @ObservedObject var navigationManager = NavigationManager.shared
    @ObservedObject var logsViewModel = LogsViewModel.shared
    @ObservedObject var healthKit = HealthKitManager.shared
    @ObservedObject var customLogManager = CustomLogManager.shared
    @ObservedObject var bulkEditManager: BulkEditManager

    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @State var selectedDate = Date()
    @State var viewMode: WeeklyViewMode = .week
    @State var selectedCalendarEvent: GoogleCalendarEvent?
    @State var selectedTask: GoogleTask?
    @State var selectedTaskListId: String?
    @State var selectedAccountKind: GoogleAuthManager.AccountKind?
    @State var weekDates: [Date] = []
    
    // MARK: - Expand/Collapse State (for vertical/column view only)
    @State var eventsExpanded = true
    @State var personalTasksExpanded = true
    @State var professionalTasksExpanded = true
    @State var logsExpanded = true
    struct WeeklyTaskSelection: Identifiable {
        let id = UUID()
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    @State var taskSheetSelection: WeeklyTaskSelection?
    @State var showingAddEvent = false
    @State var showingNewTask = false
    @State var scrollToCurrentDayTrigger = false
    @State var scrollToCurrentDayHorizontalTrigger = false
    @State var scrollToCurrentDayRowTrigger = false
    
    // MARK: - Adaptive Layout Properties
    var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    func visibleDaysCount(for geometry: GeometryProxy) -> Int {
        let w = geometry.size.width
        let h = geometry.size.height
        let isLandscape = w > h

        if isCompact {
            // iPhone: Show 2 days at a time
            return 2
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
    
    func dayColumnWidth(availableWidth: CGFloat, visibleDays: Int) -> CGFloat {
        return availableWidth / CGFloat(visibleDays)
    }
    
    func totalContentWidth(availableWidth: CGFloat, visibleDays: Int) -> CGFloat {
        // Total width for all 7 days
        return dayColumnWidth(availableWidth: availableWidth, visibleDays: visibleDays) * 7
    }
    
    // MARK: - Horizontal View Adaptive Properties
    func dateColumnWidth() -> CGFloat {
        return isCompact ? 80 : 100
    }
    
    func contentColumnWidth() -> CGFloat {
        // Adaptive width for content columns in horizontal view
        return isCompact ? 200 : 228.6
    }
    
    func logColumnWidth() -> CGFloat {
        // Fixed width for log columns - same as content columns
        return contentColumnWidth()
    }

    let hideNavBar: Bool

    init(bulkEditManager: BulkEditManager, hideNavBar: Bool = false) {
        self._bulkEditManager = ObservedObject(wrappedValue: bulkEditManager)
        self.hideNavBar = hideNavBar
    }

    // MARK: - Past-week summary

    /// True when `currentDate` falls in a week strictly before the week
    /// containing today. Drives the retrospective summary strip — hidden
    /// for the current week and any future week.
    var isPastWeek: Bool {
        let cal = Calendar.mondayFirst
        guard let nowWeek = cal.dateInterval(of: .weekOfYear, for: Date()),
              let dispWeek = cal.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
            return false
        }
        return dispWeek.end <= nowWeek.start
    }

    /// Half-open interval `[start, end)` of the displayed week. Used as
    /// the date filter for every summary stat.
    var displayedWeekRange: (start: Date, end: Date)? {
        let cal = Calendar.mondayFirst
        guard let interval = cal.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else { return nil }
        return (interval.start, interval.end)
    }

    /// Horizontally-scrollable strip of stat tiles for the displayed
    /// past week. Tier-1 (always shown): Goals, Tasks, Workouts.
    /// Tier-2 (only when their log type is enabled and has data):
    /// Sleep, Weight, Custom logs (per collection).
    var pastWeekSummaryStrip: some View {
        let stats = pastWeekStats()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(stats.indices, id: \.self) { i in
                    pastWeekStatTile(stats[i])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }

    struct PastWeekStat {
        let label: String
        let value: String
        let systemImage: String
        let tint: Color
    }

    func pastWeekStatTile(_ stat: PastWeekStat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: stat.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(stat.tint)
                Text(stat.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Text(stat.value)
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))
        )
    }

    /// Computes the tile values for the displayed past week. Each tile
    /// corresponds to one source of retrospective data; tier-2 tiles are
    /// suppressed when their log type is disabled or has no data.
    func pastWeekStats() -> [PastWeekStat] {
        guard let range = displayedWeekRange else { return [] }
        let cal = Calendar.current
        var stats: [PastWeekStat] = []

        // Goals — count weekly-timeframe goals due in this week and how
        // many were marked complete.
        let weekGoals = GoalsManager.shared.goals.filter { goal in
            goal.targetTimeframe == .week &&
            goal.dueDate >= range.start &&
            goal.dueDate < range.end
        }
        let goalsDone = weekGoals.filter { $0.isCompleted }.count
        stats.append(PastWeekStat(
            label: "Goals",
            value: "\(goalsDone) / \(weekGoals.count)",
            systemImage: "target",
            tint: .accentColor
        ))

        // Tasks completed — Google Tasks `completed` is the timestamp of
        // completion; we count tasks whose completion fell inside this
        // week, across both accounts.
        let tasksCompleted = countTasksCompleted(in: range)
        stats.append(PastWeekStat(
            label: "Tasks done",
            value: "\(tasksCompleted)",
            systemImage: "checkmark.circle",
            tint: .green
        ))

        // Workouts logged this week — only when workout logs are enabled.
        if appPrefs.showWorkoutLogs {
            let workoutCount = logsViewModel.workoutEntries.filter {
                $0.date >= range.start && $0.date < range.end
            }.count
            stats.append(PastWeekStat(
                label: "Workouts",
                value: "\(workoutCount)",
                systemImage: "figure.run",
                tint: .orange
            ))
        }

        // Sleep average — across non-empty sleep entries this week.
        if appPrefs.showSleepLogs {
            let entries = logsViewModel.sleepEntries.filter {
                $0.date >= range.start && $0.date < range.end
            }
            let durations: [TimeInterval] = entries.compactMap { e in
                guard let bed = e.bedTime, let wake = e.wakeUpTime else { return nil }
                let dur = wake.timeIntervalSince(bed)
                return dur > 0 ? dur : nil
            }
            if !durations.isEmpty {
                let avgSec = durations.reduce(0, +) / Double(durations.count)
                let h = Int(avgSec / 3600)
                let m = Int((avgSec.truncatingRemainder(dividingBy: 3600)) / 60)
                stats.append(PastWeekStat(
                    label: "Sleep avg",
                    value: String(format: "%dh %02dm", h, m),
                    systemImage: "bed.double",
                    tint: .indigo
                ))
            }
        }

        // Weight delta — last weight in this week vs. last weight before
        // this week. Skipped when the user has fewer than two readings.
        if appPrefs.showWeightLogs {
            let entries = logsViewModel.weightEntries
            let inWeek = entries
                .filter { $0.date >= range.start && $0.date < range.end }
                .sorted { $0.date < $1.date }
            let priorBefore = entries
                .filter { $0.date < range.start }
                .sorted { $0.date < $1.date }
                .last
            if let last = inWeek.last, let prior = priorBefore {
                let delta = last.weight - prior.weight
                let signed = delta > 0 ? "+\(String(format: "%.1f", delta))" : String(format: "%.1f", delta)
                stats.append(PastWeekStat(
                    label: "Weight Δ",
                    value: signed,
                    systemImage: "scalemass",
                    tint: .blue
                ))
            }
        }

        // Custom logs — per collection completion ratio (entries marked
        // complete this week / item-count × days-tracked).
        for collection in 0..<CustomLogManager.maxCollections where appPrefs.showCustomLogs(for: collection) {
            let items = customLogManager.items(in: collection).filter { $0.isEnabled }
            guard !items.isEmpty else { continue }
            // Count item-day completions falling in this week.
            let completions = customLogManager.entries.filter { entry in
                entry.collectionIndex == collection &&
                entry.isCompleted &&
                entry.date >= range.start && entry.date < range.end &&
                items.contains(where: { $0.id == entry.itemId })
            }.count
            // Possible total = items × days in the week.
            let dayCount = cal.dateComponents([.day], from: range.start, to: range.end).day ?? 7
            let total = items.count * max(1, dayCount)
            let name = appPrefs.customLogSectionName(for: collection)
            stats.append(PastWeekStat(
                label: name,
                value: "\(completions) / \(total)",
                systemImage: "list.bullet.rectangle",
                tint: .purple
            ))
        }

        return stats
    }

    /// Tasks across both accounts whose `completed` ISO timestamp falls
    /// within `range`. Iterates the in-memory task dictionaries directly
    /// since Google Tasks doesn't expose a "completed-within" query.
    func countTasksCompleted(in range: (start: Date, end: Date)) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        var count = 0
        let buckets = [tasksViewModel.personalTasks, tasksViewModel.professionalTasks]
        for dict in buckets {
            for (_, tasks) in dict {
                for task in tasks where task.isCompleted {
                    guard let completedString = task.completed else { continue }
                    let date = formatter.date(from: completedString) ?? fallback.date(from: completedString)
                    guard let date else { continue }
                    if date >= range.start && date < range.end {
                        count += 1
                    }
                }
            }
        }
        return count
    }

    var baseView: some View {
        VStack(spacing: 0) {
            // Bulk Edit Toolbar (shown when in bulk edit mode)
            if bulkEditManager.state.isActive {
                BulkEditToolbarView(
                    bulkEditManager: bulkEditManager,
                    visibleOpenTaskIds: visibleOpenTaskIdsForWeek()
                )
            }

            if !hideNavBar {
                GlobalNavBar()
                    .background(.ultraThinMaterial)
            }

            // Retrospective summary, only for past weeks. Hidden for the
            // current week and future weeks since there's nothing to look
            // back on.
            if isPastWeek {
                pastWeekSummaryStrip
            }

            mainContent
        }
    }

    var baseViewWithNavigation: some View {
        baseView
            .sidebarToggleHidden()
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
    }

    var baseViewWithSheets: some View {
        baseViewWithNavigation
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleWeeklyCalendarBulkEdit"))) { _ in
            bulkEditManager.state.isActive.toggle()
            if !bulkEditManager.state.isActive {
                bulkEditManager.state.selectedTaskIds.removeAll()
            }
        }
        .sheet(item: Binding<GoogleCalendarEvent?>(
            get: { selectedCalendarEvent },
            set: { selectedCalendarEvent = $0 }
        )) { ev in
            let accountKind = ev.ownerAccountKind
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
        .sheet(isPresented: $showingAddEvent) {
            AddItemView(
                currentDate: selectedDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
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
                    }
                },
                onDelete: {
                    Task {
                        await tasksViewModel.deleteTask(sel.task, from: sel.listId, for: sel.accountKind)
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksViewModel.moveTask(updatedTask, from: sel.listId, to: targetListId, for: sel.accountKind)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksViewModel.crossAccountMoveTask(updatedTask, from: (sel.accountKind, sel.listId), to: (targetAccountKind, targetListId))
                    }
                }
            )
        }
        .sheet(isPresented: $showingNewTask) {
            // Create-task UI matching TasksView create flow
            let personalLinked = authManager.isLinked(kind: .personal)
            let professionalLinked = authManager.isLinked(kind: .professional)
            let defaultAccount: GoogleAuthManager.AccountKind = selectedAccountKind ?? (personalLinked ? .personal : .professional)
            let defaultLists = defaultAccount == .personal ? tasksViewModel.personalTaskLists : tasksViewModel.professionalTaskLists
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
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { _ in },
                onDelete: {},
                onMove: { _, _ in },
                onCrossAccountMove: { _, _, _ in },
                isNew: true
            )
        }
    }

    var baseViewWithLifecycle: some View {
        baseViewWithSheets
        .task {
            // Initialize selectedDate from navigation manager if available
            selectedDate = navigationManager.currentDate
            regenerateWeekDates(for: selectedDate)

            // Load data for the week (no clearing — avoids blank flash and
            // prevents infinite refresh loops when embedded in BookView)
            await tasksViewModel.loadTasks()
            await calendarViewModel.loadCalendarDataForWeek(containing: selectedDate)
        }
        .onChange(of: selectedDate) { newValue in
            regenerateWeekDates(for: newValue)
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            selectedDate = newValue
            // Scroll to current day when date changes
            scrollToCurrentDayTrigger.toggle()
            scrollToCurrentDayHorizontalTrigger.toggle()
            scrollToCurrentDayRowTrigger.toggle()

            Task {
                await calendarViewModel.loadCalendarDataForWeek(containing: newValue)
            }
        }
        .onAppear {
            // Trigger initial scroll to current day with a slight delay
            // to ensure views are fully rendered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToCurrentDay()
            }
        }
    }

    var body: some View {
        baseViewWithLifecycle
        // Bulk edit confirmation dialogs
        .confirmationDialog("Complete Tasks", isPresented: $bulkEditManager.state.showingCompleteConfirmation) {
            Button("Complete \(bulkEditManager.state.selectedTaskIds.count) task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")") {
                Task {
                    let allTasks = getAllTasksForBulkEdit()
                    await bulkEditManager.bulkComplete(tasks: allTasks, tasksVM: tasksViewModel) { undoData in
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
                    await bulkEditManager.bulkDelete(tasks: allTasks, tasksVM: tasksViewModel) { undoData in
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
                        tasksVM: tasksViewModel
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
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                onSelect: { accountKind, listId in
                    Task {
                        let allTasks = getAllTasksForBulkEdit()
                        await bulkEditManager.bulkMove(
                            tasks: allTasks,
                            to: listId,
                            destinationAccountKind: accountKind,
                            tasksVM: tasksViewModel
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
                        tasksVM: tasksViewModel
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
    private func visibleOpenTaskIdsForWeek() -> Set<String> {
        var ids: Set<String> = []
        for date in weekDates {
            ids.formUnion(getFilteredTasksForSpecificDate(date: date, accountKind: .personal).openTaskIds)
            ids.formUnion(getFilteredTasksForSpecificDate(date: date, accountKind: .professional).openTaskIds)
        }
        return ids
    }

    private func getAllTasksForBulkEdit() -> [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] {
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []

        // Add personal tasks
        for (listId, tasks) in tasksViewModel.personalTasks {
            for task in tasks {
                allTasks.append((task: task, listId: listId, accountKind: .personal))
            }
        }

        // Add professional tasks
        for (listId, tasks) in tasksViewModel.professionalTasks {
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
    }

    // MARK: - Main Content
    @ViewBuilder
    var mainContent: some View {
        if appPrefs.useRowBasedWeeklyView {
            // Row-based layout: each day is a row
            weekRowBasedViewWithStickyColumn
        } else {
            // Column-based layout: 7 columns for days
            weekColumnBasedViewWithStickyHeader
        }
    }
    
    // MARK: - Column-Based View with Sticky Header
    var weekColumnBasedViewWithStickyHeader: some View {
        return GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let visibleDays = visibleDaysCount(for: geometry)
            let columnWidth = dayColumnWidth(availableWidth: availableWidth, visibleDays: visibleDays)
            let contentWidth = totalContentWidth(availableWidth: availableWidth, visibleDays: visibleDays)
            
            ScrollViewReader { horizontalProxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // Fixed header (stays at top when scrolling vertically)
                        weekTasksDateHeader(dayColumnWidth: columnWidth, timeColumnWidth: 50)
                            .frame(width: contentWidth)
                            .background(Color(.systemGray6))
                        
                        // Divider below date header
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(height: 1)
                        
                        // Scrollable content (scrolls vertically)
                        ScrollView(.vertical, showsIndicators: true) {
                            ScrollViewReader { verticalProxy in
                                weekTasksContent(dayColumnWidth: columnWidth, fixedWidth: contentWidth)
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            scrollToCurrentDayHorizontalWithProxy(horizontalProxy)
                                        }
                                    }
                                    .onChange(of: scrollToCurrentDayTrigger) { _ in
                                        scrollToCurrentDayHorizontalWithProxy(horizontalProxy)
                                    }
                                    .onChange(of: scrollToCurrentDayHorizontalTrigger) { _ in
                                        scrollToCurrentDayHorizontalWithProxy(horizontalProxy)
                                    }
                                    .padding([.horizontal, .bottom], 8)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(width: contentWidth)
                    .padding(.horizontal, 12)
                }
                .background(Color(.systemBackground))
            }
        }
    }
    }


