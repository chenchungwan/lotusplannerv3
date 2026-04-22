import SwiftUI

/// Live day view driven by the user's saved custom layout.
/// The global nav bar at the top is provided by CalendarView via
/// `.safeAreaInset(edge: .top)`, so this view only renders the body area.
struct DayViewCustom: View {
    @ObservedObject private var bulkEditManager: BulkEditManager
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var calendarVM = DataManager.shared.calendarViewModel
    @ObservedObject private var auth = GoogleAuthManager.shared
    @ObservedObject private var logsVM = LogsViewModel.shared

    var onEventTap: ((GoogleCalendarEvent) -> Void)?

    @State private var configVersion: Int = 0
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedTaskAccount: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails = false
    @State private var selectedEvent: GoogleCalendarEvent?

    /// Identifiable wrapper so the configurator can be presented via
    /// `.fullScreenCover(item:)` and receive a concrete version id.
    private struct ConfiguratorTarget: Identifiable { let id: UUID }
    @State private var configuratorTarget: ConfiguratorTarget?

    /// The active version from the library (the one `DayViewCustom` renders).
    /// Returns `nil` when no versions exist or none is marked active.
    private var savedConfig: CustomDayViewConfig? {
        _ = configVersion
        return CustomDayViewLibrary.load().activeConfig
    }

    private var isConfigured: Bool { savedConfig != nil }

    private var isRunningOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp
    }

    init(bulkEditManager: BulkEditManager, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self._bulkEditManager = ObservedObject(wrappedValue: bulkEditManager)
        self.onEventTap = onEventTap
    }

    var body: some View {
        Group {
            if let config = savedConfig {
                liveView(config: config)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .fullScreenCover(item: $configuratorTarget, onDismiss: {
            configVersion &+= 1
        }) { target in
            DayViewCustomConfigurator(versionId: target.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: CustomDayViewLibrary.didChangeNotification)) { _ in
            configVersion &+= 1
        }
        .sheet(isPresented: Binding(
            get: { showingTaskDetails && selectedTask != nil && selectedTaskListId != nil && selectedTaskAccount != nil },
            set: { showingTaskDetails = $0 }
        )) {
            if let t = selectedTask,
               let listId = selectedTaskListId,
               let account = selectedTaskAccount {
                TaskDetailsView(
                    task: t,
                    taskListId: listId,
                    accountKind: account,
                    accentColor: account == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    personalTaskLists: tasksVM.personalTaskLists,
                    professionalTaskLists: tasksVM.professionalTaskLists,
                    appPrefs: appPrefs,
                    viewModel: tasksVM,
                    onSave: { updated in
                        Task { await tasksVM.updateTask(updated, in: listId, for: account) }
                        showingTaskDetails = false
                    },
                    onDelete: {
                        Task { await tasksVM.deleteTask(t, from: listId, for: account) }
                        showingTaskDetails = false
                    },
                    onMove: { updated, targetListId in
                        Task { await tasksVM.moveTask(updated, from: listId, to: targetListId, for: account) }
                        showingTaskDetails = false
                    },
                    onCrossAccountMove: { updated, targetAccount, targetListId in
                        Task { await tasksVM.crossAccountMoveTask(updated, from: (account, listId), to: (targetAccount, targetListId)) }
                        showingTaskDetails = false
                    },
                    isNew: false
                )
            }
        }
        .sheet(item: Binding<GoogleCalendarEvent?>(
            get: { selectedEvent },
            set: { selectedEvent = $0 }
        )) { ev in
            let accountKind: GoogleAuthManager.AccountKind = calendarVM.personalEvents.contains(where: { $0.id == ev.id }) ? .personal : .professional
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
    }

    // MARK: - Live layout

    @ViewBuilder
    private func liveView(config: CustomDayViewConfig) -> some View {
        if config.pageMode == 2, let page2 = config.page2 {
            TabView {
                pageView(pageConfig: config.page1).tag(1)
                pageView(pageConfig: page2).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        } else {
            pageView(pageConfig: config.page1)
        }
    }

    /// Rows that contain a single-row Health Bar placement render at this
    /// fixed height instead of stretching to their share of the page. Keeps
    /// the bar flush against the next row's top instead of leaving a gap.
    private let compactRowHeight: CGFloat = 36

    private func pageView(pageConfig: CustomDayViewConfig.PageConfig) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 6
            let padding: CGFloat = 8
            let innerW = proxy.size.width - padding * 2
            let innerH = proxy.size.height - padding * 2
            let cellW = max(0, (innerW - spacing * CGFloat(pageConfig.cols - 1)) / CGFloat(pageConfig.cols))
            let rowHs = rowHeights(pageConfig: pageConfig, innerH: innerH, spacing: spacing)

            ZStack(alignment: .topLeading) {
                // Plain / merged cells that are NOT part of any group.
                ForEach(visibleCells(pageConfig: pageConfig)) { cell in
                    if !cellIsInGroup(row: cell.row, col: cell.col, pageConfig: pageConfig) {
                        let region = mergedRegion(at: cell.row, col: cell.col, in: pageConfig)
                        let rowSpan = region?.rowSpan ?? 1
                        let colSpan = region?.colSpan ?? 1
                        let width = CGFloat(colSpan) * cellW + CGFloat(colSpan - 1) * spacing
                        let height = spannedRowsHeight(startRow: cell.row, rowSpan: rowSpan, rowHeights: rowHs, spacing: spacing)
                        let x = CGFloat(cell.col) * (cellW + spacing) + padding
                        let y = rowYStart(row: cell.row, rowHeights: rowHs, spacing: spacing, padding: padding)
                        let placement = pageConfig.placements.first {
                            $0.row == cell.row && $0.col == cell.col
                        }
                        let component = placement.flatMap { CustomComponent(rawValue: $0.component) }

                        liveCell(component: component)
                            .frame(width: width, height: height)
                            .position(x: x + width / 2, y: y + height / 2)
                    }
                }

                // Each group renders as a single tight-packed flex container
                // occupying the union of its cells.
                let groups: [CustomDayViewConfig.GroupDTO] = pageConfig.groups ?? []
                ForEach(Array(groups.enumerated()), id: \.offset) { _, dto in
                    let (rs, cs) = dto.resolvedSpans()
                    let width = CGFloat(cs) * cellW + CGFloat(cs - 1) * spacing
                    let height = spannedRowsHeight(startRow: dto.startRow, rowSpan: rs, rowHeights: rowHs, spacing: spacing)
                    let x = CGFloat(dto.startCol) * (cellW + spacing) + padding
                    let y = rowYStart(row: dto.startRow, rowHeights: rowHs, spacing: spacing, padding: padding)
                    groupContainer(dto: dto, pageConfig: pageConfig, width: width, height: height, x: x, y: y)
                }
            }
        }
    }

    // MARK: - Row height calculation

    /// Which rows should be rendered at `compactRowHeight` — i.e. host a
    /// single-row Health Bar. Multi-row merges containing a Health Bar are
    /// respected: if the user merged vertically, we keep their requested
    /// height instead of forcing the row small.
    private func compactRows(pageConfig: CustomDayViewConfig.PageConfig) -> Set<Int> {
        var set: Set<Int> = []
        for placement in pageConfig.placements where placement.component == CustomComponent.healthBar.rawValue {
            let region = mergedRegion(at: placement.row, col: placement.col, in: pageConfig)
            let rowSpan = region?.rowSpan ?? 1
            if rowSpan == 1 {
                set.insert(placement.row)
            }
        }
        return set
    }

    /// Returns the height for every row on the page. Compact rows get
    /// `compactRowHeight` and the remaining inner height is split evenly
    /// across the other rows.
    private func rowHeights(pageConfig: CustomDayViewConfig.PageConfig, innerH: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let rows = pageConfig.rows
        guard rows > 0 else { return [] }
        let compact = compactRows(pageConfig: pageConfig)
        let totalSpacing = spacing * CGFloat(max(0, rows - 1))
        let compactTotal = CGFloat(compact.count) * compactRowHeight
        let remaining = max(0, innerH - totalSpacing - compactTotal)
        let regularCount = rows - compact.count
        let regularRowH = regularCount > 0 ? remaining / CGFloat(regularCount) : 0
        return (0..<rows).map { compact.contains($0) ? compactRowHeight : regularRowH }
    }

    /// Y offset of the top of `row`, in the page's inner space.
    private func rowYStart(row: Int, rowHeights: [CGFloat], spacing: CGFloat, padding: CGFloat) -> CGFloat {
        var y = padding
        for r in 0..<row where r < rowHeights.count {
            y += rowHeights[r] + spacing
        }
        return y
    }

    /// Total rendered height for a cell that spans `rowSpan` rows starting at
    /// `startRow`, including spacing between the rows it spans.
    private func spannedRowsHeight(startRow: Int, rowSpan: Int, rowHeights: [CGFloat], spacing: CGFloat) -> CGFloat {
        let endExclusive = min(startRow + rowSpan, rowHeights.count)
        var h: CGFloat = 0
        for r in startRow..<endExclusive {
            h += rowHeights[r]
        }
        h += spacing * CGFloat(max(0, endExclusive - startRow - 1))
        return h
    }

    private struct VisiblePosition: Identifiable {
        let row: Int
        let col: Int
        var id: String { "\(row)_\(col)" }
    }

    private func visibleCells(pageConfig: CustomDayViewConfig.PageConfig) -> [VisiblePosition] {
        var result: [VisiblePosition] = []
        for row in 0..<pageConfig.rows {
            for col in 0..<pageConfig.cols {
                let hidden = pageConfig.merges.contains { region in
                    row >= region.topRow && row < region.topRow + region.rowSpan &&
                    col >= region.leftCol && col < region.leftCol + region.colSpan &&
                    !(row == region.topRow && col == region.leftCol)
                }
                if !hidden {
                    result.append(VisiblePosition(row: row, col: col))
                }
            }
        }
        return result
    }

    private func mergedRegion(at row: Int, col: Int, in pageConfig: CustomDayViewConfig.PageConfig) -> CustomDayViewConfig.MergeDTO? {
        pageConfig.merges.first { $0.topRow == row && $0.leftCol == col }
    }

    private func cellIsInGroup(row: Int, col: Int, pageConfig: CustomDayViewConfig.PageConfig) -> Bool {
        for dto in (pageConfig.groups ?? []) {
            let (rs, cs) = dto.resolvedSpans()
            if row >= dto.startRow && row < dto.startRow + rs &&
               col >= dto.startCol && col < dto.startCol + cs {
                return true
            }
        }
        return false
    }

    /// Collects component placements inside a group's rect, sorted along the
    /// group's primary axis.
    private func groupComponents(dto: CustomDayViewConfig.GroupDTO,
                                 pageConfig: CustomDayViewConfig.PageConfig) -> [CustomComponent] {
        let (rs, cs) = dto.resolvedSpans()
        let isHorizontal = dto.orientation == "horizontal"
        let filtered = pageConfig.placements.filter { placement in
            let insideRow = placement.row >= dto.startRow && placement.row < dto.startRow + rs
            let insideCol = placement.col >= dto.startCol && placement.col < dto.startCol + cs
            return insideRow && insideCol
        }
        let sorted = isHorizontal
            ? filtered.sorted { $0.col < $1.col }
            : filtered.sorted { $0.row < $1.row }
        return sorted.compactMap { CustomComponent(rawValue: $0.component) }
    }

    /// Renders a group: a flex container at the union of its cells with
    /// minimal spacing between contained components, so shorter components
    /// pack tight and taller ones scroll instead of truncating.
    @ViewBuilder
    private func groupContainer(
        dto: CustomDayViewConfig.GroupDTO,
        pageConfig: CustomDayViewConfig.PageConfig,
        width: CGFloat,
        height: CGFloat,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        let isHorizontal = dto.orientation == "horizontal"
        let components = groupComponents(dto: dto, pageConfig: pageConfig)

        Group {
            if isHorizontal {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                            liveCell(component: component)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                            liveCell(component: component)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .position(x: x + width / 2, y: y + height / 2)
    }

    // MARK: - Cell content

    @ViewBuilder
    private func liveCell(component: CustomComponent?) -> some View {
        if let component = component {
            componentView(component)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        }
    }

    @ViewBuilder
    private func componentView(_ component: CustomComponent) -> some View {
        let date = navigationManager.currentDate
        switch component {
        case .eventsTimeline:
            eventsTimelineView(date: date)
        case .eventsList:
            eventsListView(date: date)
        case .tasksPersonalGrouped:
            tasksGroupedView(for: .personal, date: date)
        case .tasksProfessionalGrouped:
            tasksGroupedView(for: .professional, date: date)
        case .tasksPersonalCompact:
            tasksCompactView(for: .personal, date: date)
        case .tasksProfessionalCompact:
            tasksCompactView(for: .professional, date: date)
        case .logWeight:
            singleLogSection(date: date, builtIn: .weight)
        case .logWorkout:
            singleLogSection(date: date, builtIn: .workout)
        case .logFood:
            singleLogSection(date: date, builtIn: .food)
        case .logWater:
            singleLogSection(date: date, builtIn: .water)
        case .logSleep:
            singleLogSection(date: date, builtIn: .sleep)
        case .logCustom:
            LogsComponent(
                currentDate: date,
                horizontal: false,
                allowInternalScrolling: true,
                visibleLogsOverride: [],
                includeCustomOverride: true,
                showHeader: false
            )
        case .logCustomWeek:
            CustomLogWeekComponent(currentDate: date)
        case .logsAll:
            LogsComponent(currentDate: date, horizontal: false, allowInternalScrolling: true)
        case .journal:
            JournalView(currentDate: $navigationManager.currentDate,
                        embedded: true,
                        layoutType: .compact)
                .id(date)
        case .healthBar:
            HealthBarComponent(date: date)
        case .goalsWeek:
            GoalsTimeframeComponent(timeframe: .week, date: date)
        case .goalsMonth:
            GoalsTimeframeComponent(timeframe: .month, date: date)
        case .goalsYear:
            GoalsTimeframeComponent(timeframe: .year, date: date)
        case .goalsPicker:
            GoalsTimeframePickerComponent(date: date)
        case .weightGraph:
            WeightGraphComponent(currentDate: date)
        case .weightGraphWeek:
            WeightGraphComponent(currentDate: date, fixedTimeframe: .week)
        case .weightGraphMonth:
            WeightGraphComponent(currentDate: date, fixedTimeframe: .month)
        case .weightGraphYear:
            WeightGraphComponent(currentDate: date, fixedTimeframe: .year)
        case .workoutStreakGraph:
            WorkoutStreakGraphComponent(currentDate: date)
        case .workoutStreakGraphWeek:
            WorkoutStreakGraphComponent(currentDate: date, fixedTimeframe: .week)
        case .workoutStreakGraphMonth:
            WorkoutStreakGraphComponent(currentDate: date, fixedTimeframe: .month)
        case .workoutStreakGraphYear:
            WorkoutStreakGraphComponent(currentDate: date, fixedTimeframe: .year)
        }
    }

    // MARK: - Events

    private func eventsTimelineView(date: Date) -> some View {
        let personalEvents = calendarVM.personalEvents.filter { Calendar.current.isDate($0.startTime ?? .distantPast, inSameDayAs: date) }
        let professionalEvents = calendarVM.professionalEvents.filter { Calendar.current.isDate($0.startTime ?? .distantPast, inSameDayAs: date) }
        let all = calendarVM.events(for: date)
        // `TimeboxComponent` owns its own ScrollView + ScrollViewReader and
        // auto-scrolls to the current hour on appear. Wrapping it in another
        // ScrollView here would swallow that programmatic scroll, so render
        // it directly — this keeps the "now" redline in view on first render.
        return TimeboxComponent(
            date: date,
            events: all,
            personalEvents: personalEvents,
            professionalEvents: professionalEvents,
            personalTasks: filteredTasksDictForDay(tasksVM.personalTasks, on: date),
            professionalTasks: filteredTasksDictForDay(tasksVM.professionalTasks, on: date),
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor,
            onEventTap: { ev in
                onEventTap?(ev)
                selectedEvent = ev
            },
            onTaskTap: { task, listId in
                let accountKind: GoogleAuthManager.AccountKind = tasksVM.personalTasks[listId] != nil ? .personal : .professional
                selectedTask = task
                selectedTaskListId = listId
                selectedTaskAccount = accountKind
                showingTaskDetails = true
            },
            onTaskToggle: { task, listId in
                let accountKind: GoogleAuthManager.AccountKind = tasksVM.personalTasks[listId] != nil ? .personal : .professional
                Task { await tasksVM.toggleTaskCompletion(task, in: listId, for: accountKind) }
            },
            showAllDaySection: true,
            isBulkEditMode: false,
            selectedTaskIds: [],
            onTaskSelectionToggle: nil
        )
    }

    private func eventsListView(date: Date) -> some View {
        EventsListComponent(
            events: calendarVM.events(for: date),
            personalEvents: calendarVM.personalEvents,
            professionalEvents: calendarVM.professionalEvents,
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor,
            onEventTap: { ev in
                onEventTap?(ev)
                selectedEvent = ev
            },
            date: date
        )
        .padding(8)
    }

    // MARK: - Tasks

    @ViewBuilder
    private func tasksGroupedView(for account: GoogleAuthManager.AccountKind, date: Date) -> some View {
        if auth.isLinked(kind: account) {
            let dict = account == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
            let lists = account == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
            ScrollView(.vertical, showsIndicators: true) {
                TasksComponent(
                    taskLists: lists,
                    tasksDict: filteredTasksDictForDay(dict, on: date),
                    accentColor: account == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    accountType: account,
                    onTaskToggle: { task, listId in
                        Task { await tasksVM.toggleTaskCompletion(task, in: listId, for: account) }
                    },
                    onTaskDetails: { task, listId in
                        selectedTask = task
                        selectedTaskListId = listId
                        selectedTaskAccount = account
                        showingTaskDetails = true
                    },
                    onListRename: nil,
                    hideDueDateTag: false,
                    showEmptyState: true,
                    horizontalCards: false,
                    isSingleDayView: true,
                    showTitle: true,
                    showTaskStartTime: true
                )
            }
        } else {
            notLinkedPlaceholder(for: account)
        }
    }

    @ViewBuilder
    private func tasksCompactView(for account: GoogleAuthManager.AccountKind, date: Date) -> some View {
        if auth.isLinked(kind: account) {
            let dict = account == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
            let lists = account == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
            ScrollView(.vertical, showsIndicators: true) {
                TasksCompactComponent(
                    taskLists: lists,
                    tasksDict: filteredTasksDictForDay(dict, on: date),
                    accentColor: account == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    accountType: account,
                    onTaskToggle: { task, listId in
                        Task { await tasksVM.toggleTaskCompletion(task, in: listId, for: account) }
                    },
                    onTaskDetails: { task, listId in
                        selectedTask = task
                        selectedTaskListId = listId
                        selectedTaskAccount = account
                        showingTaskDetails = true
                    }
                )
                .padding(8)
            }
        } else {
            notLinkedPlaceholder(for: account)
        }
    }

    private func notLinkedPlaceholder(for account: GoogleAuthManager.AccountKind) -> some View {
        let name = account == .personal ? appPrefs.personalAccountName : appPrefs.professionalAccountName
        return Text("\(name) account not linked")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // Matches the per-day filter used elsewhere: show the date's tasks + today's
    // overdue tasks when viewing today; completed tasks appear on completion day.
    private func filteredTasksDictForDay(_ dict: [String: [GoogleTask]], on date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.mondayFirst
        let startOfViewedDate = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: Date())
        let isViewingToday = startOfViewedDate == startOfToday

        var result: [String: [GoogleTask]] = [:]
        for (listId, tasks) in dict {
            let filtered = tasks.filter { task in
                if task.isCompleted {
                    if let comp = task.completionDate {
                        return calendar.isDate(comp, inSameDayAs: date)
                    }
                    return false
                }
                if let dueDate = task.dueDate {
                    let startOfDueDate = calendar.startOfDay(for: dueDate)
                    let isViewingDueDate = startOfViewedDate == startOfDueDate
                    let isOverdue = startOfDueDate < startOfToday
                    return isViewingDueDate || (isViewingToday && isOverdue)
                }
                return false
            }
            if !filtered.isEmpty { result[listId] = filtered }
        }
        return result
    }

    // MARK: - Individual logs

    /// Uses LogsComponent with an override that shows only the requested
    /// built-in log type, matching the rendering used elsewhere in the app.
    private func singleLogSection(date: Date, builtIn: BuiltInLogType) -> some View {
        LogsComponent(
            currentDate: date,
            horizontal: false,
            allowInternalScrolling: true,
            visibleLogsOverride: [builtIn],
            includeCustomOverride: false,
            showHeader: false
        )
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        if isRunningOnMac {
            macEmptyState
        } else {
            iPadEmptyState
        }
    }

    private var iPadEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Your custom day view is empty.")
                .font(.title3)
                .foregroundColor(.primary)

            Text("Drag and drop components into a 1- or 2-page layout to make it your own.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                configuratorTarget = ConfiguratorTarget(id: UUID())
            } label: {
                Label("Configure", systemImage: "slider.horizontal.3")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private var macEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "ipad")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Configure on iPad first")
                .font(.title3)
                .foregroundColor(.primary)

            Text("The custom day view configuration is currently only supported on iPad. Set up your layout on iPad and it'll appear here once saved.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    DayViewCustom(bulkEditManager: BulkEditManager())
}
