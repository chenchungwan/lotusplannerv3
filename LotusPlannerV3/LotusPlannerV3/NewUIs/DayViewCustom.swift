import SwiftUI

/// Live day view driven by the user's saved custom layout.
/// The global nav bar at the top is provided by CalendarView via
/// `.safeAreaInset(edge: .top)`, so this view only renders the body area.
struct DayViewCustom: View {
    @ObservedObject private var bulkEditManager: BulkEditManager
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @ObservedObject private var calendarVM = CalendarViewModel.shared
    @ObservedObject private var auth = GoogleAuthManager.shared
    @ObservedObject private var logsVM = LogsViewModel.shared

    var onEventTap: ((GoogleCalendarEvent) -> Void)?

    @State private var configVersion: Int = 0
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedTaskAccount: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails = false
    @State private var selectedEvent: GoogleCalendarEvent?
    @State private var rowWeightsByPage: [Int: [CGFloat]] = [:]
    @State private var colWeightsByPage: [Int: [CGFloat]] = [:]
    @State private var draggingHorizontalDivider = false
    @State private var draggingVerticalDivider = false
    @State private var horizontalDragBaseWeights: [CGFloat]?
    @State private var verticalDragBaseWeights: [CGFloat]?

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

    private var activeVersionId: UUID? {
        _ = configVersion
        return CustomDayViewLibrary.load().resolvedActiveId
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
        VStack(spacing: 0) {
            // Bulk Edit Toolbar (shown when in bulk edit mode). Mirrors the
            // pattern used by DayViewNewClassic so the
            // nav bar's "checkmark.rectangle.stack" toggle works identically
            // when the active layout is `.custom`.
            if bulkEditManager.state.isActive {
                BulkEditToolbarView(
                    bulkEditManager: bulkEditManager,
                    visibleOpenTaskIds: filteredTasksDictForDay(tasksVM.account1Tasks, on: navigationManager.currentDate).openTaskIds
                        .union(filteredTasksDictForDay(tasksVM.account2Tasks, on: navigationManager.currentDate).openTaskIds)
                )
            }

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
                    accentColor: account == .account1 ? appPrefs.account1Color : appPrefs.account2Color,
                    account1TaskLists: tasksVM.account1TaskLists,
                    account2TaskLists: tasksVM.account2TaskLists,
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
            let accountKind = ev.ownerAccountKind
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
                pageView(pageIndex: 1, pageConfig: config.page1).tag(1)
                pageView(pageIndex: 2, pageConfig: page2).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayHorizontalScrollID))
        } else {
            pageView(pageIndex: 1, pageConfig: config.page1)
        }
    }

    /// Rows that contain a single-row Health Bar placement render at this
    /// fixed height instead of stretching to their share of the page. Keeps
    /// the bar flush against the next row's top instead of leaving a gap.
    private let compactRowHeight: CGFloat = 36
    private let dividerThickness: CGFloat = 12

    private func pageView(pageIndex: Int, pageConfig: CustomDayViewConfig.PageConfig) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 6
            let padding: CGFloat = 8
            let innerW = proxy.size.width - padding * 2
            let innerH = proxy.size.height - padding * 2
            let colWs = columnWidths(pageIndex: pageIndex, pageConfig: pageConfig, innerW: innerW, spacing: spacing)
            let rowHs = rowHeights(pageIndex: pageIndex, pageConfig: pageConfig, innerH: innerH, spacing: spacing)

            ZStack(alignment: .topLeading) {
                // Plain / merged cells that are NOT part of any group.
                ForEach(visibleCells(pageConfig: pageConfig)) { cell in
                    if !cellIsInGroup(row: cell.row, col: cell.col, pageConfig: pageConfig) {
                        let region = mergedRegion(at: cell.row, col: cell.col, in: pageConfig)
                        let rowSpan = region?.rowSpan ?? 1
                        let colSpan = region?.colSpan ?? 1
                        let width = spannedColumnsWidth(startCol: cell.col, colSpan: colSpan, colWidths: colWs, spacing: spacing)
                        let height = spannedRowsHeight(startRow: cell.row, rowSpan: rowSpan, rowHeights: rowHs, spacing: spacing)
                        let x = colXStart(col: cell.col, colWidths: colWs, spacing: spacing, padding: padding)
                        let y = rowYStart(row: cell.row, rowHeights: rowHs, spacing: spacing, padding: padding)
                        let placement = pageConfig.placements.first {
                            $0.row == cell.row && $0.col == cell.col
                        }
                        let component = placement.flatMap { CustomComponent(rawValue: $0.component) }

                        if component?.isCustomDivider == true {
                            customDividerView(
                                component: component,
                                pageIndex: pageIndex,
                                row: cell.row,
                                col: cell.col,
                                pageConfig: pageConfig,
                                rowHeights: rowHs,
                                colWidths: colWs,
                                spacing: spacing,
                                padding: padding
                            )
                        } else {
                            liveCell(component: component)
                                .frame(width: width, height: height)
                                .position(x: x + width / 2, y: y + height / 2)
                        }
                    }
                }

                // Each group renders as a single tight-packed flex container
                // occupying the union of its cells.
                let groups: [CustomDayViewConfig.GroupDTO] = pageConfig.groups ?? []
                ForEach(Array(groups.enumerated()), id: \.offset) { _, dto in
                    let (rs, cs) = dto.resolvedSpans()
                    let width = spannedColumnsWidth(startCol: dto.startCol, colSpan: cs, colWidths: colWs, spacing: spacing)
                    let height = spannedRowsHeight(startRow: dto.startRow, rowSpan: rs, rowHeights: rowHs, spacing: spacing)
                    let x = colXStart(col: dto.startCol, colWidths: colWs, spacing: spacing, padding: padding)
                    let y = rowYStart(row: dto.startRow, rowHeights: rowHs, spacing: spacing, padding: padding)
                    groupContainer(dto: dto, pageConfig: pageConfig, width: width, height: height, x: x, y: y)
                }
            }
            .onAppear {
                normalizeSizingState(pageIndex: pageIndex, rows: pageConfig.rows, cols: pageConfig.cols)
            }
            .onChange(of: pageConfig.rows) { _, rows in
                normalizeSizingState(pageIndex: pageIndex, rows: rows, cols: pageConfig.cols)
            }
            .onChange(of: pageConfig.cols) { _, cols in
                normalizeSizingState(pageIndex: pageIndex, rows: pageConfig.rows, cols: cols)
            }
        }
    }

    // MARK: - Row height calculation

    /// Which rows should be rendered at `compactRowHeight` — i.e. host a
    /// single-row strip-style component (Health Bar or Weekly Goals Bar).
    /// Multi-row merges containing one of these components are respected:
    /// if the user merged vertically, we keep their requested height
    /// instead of forcing the row small.
    private func compactRows(pageConfig: CustomDayViewConfig.PageConfig) -> Set<Int> {
        var set: Set<Int> = []
        let compactComponents: Set<String> = [
            CustomComponent.healthBar.rawValue,
            CustomComponent.weeklyGoalsBar.rawValue,
            CustomComponent.horizontalDivider.rawValue
        ]
        for placement in pageConfig.placements where compactComponents.contains(placement.component) {
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
    private func normalizeSizingState(pageIndex: Int, rows: Int, cols: Int) {
        if rowWeightsByPage[pageIndex]?.count != rows {
            rowWeightsByPage[pageIndex] = storedWeights(axis: "rows", pageIndex: pageIndex, count: rows)
        }
        if colWeightsByPage[pageIndex]?.count != cols {
            colWeightsByPage[pageIndex] = storedWeights(axis: "cols", pageIndex: pageIndex, count: cols)
        }
    }

    private func sizingStorageKey(axis: String, pageIndex: Int) -> String? {
        guard let id = activeVersionId else { return nil }
        return "customDayViewDividerSizing.\(id.uuidString).page\(pageIndex).\(axis).v1"
    }

    private func storedWeights(axis: String, pageIndex: Int, count: Int) -> [CGFloat] {
        guard let key = sizingStorageKey(axis: axis, pageIndex: pageIndex),
              let values = UserDefaults.standard.array(forKey: key) as? [Double],
              values.count == count else {
            return Array(repeating: 1, count: max(0, count))
        }
        return values.map { max(0.2, CGFloat($0)) }
    }

    private func saveWeights(_ weights: [CGFloat], axis: String, pageIndex: Int) {
        guard let key = sizingStorageKey(axis: axis, pageIndex: pageIndex) else { return }
        UserDefaults.standard.set(weights.map(Double.init), forKey: key)
    }

    private func weights(for pageIndex: Int, count: Int, store: [Int: [CGFloat]]) -> [CGFloat] {
        let existing = store[pageIndex] ?? []
        guard existing.count == count else { return Array(repeating: 1, count: max(0, count)) }
        return existing.map { max(0.2, $0) }
    }

    private func rowHeights(pageIndex: Int, pageConfig: CustomDayViewConfig.PageConfig, innerH: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let rows = pageConfig.rows
        guard rows > 0 else { return [] }
        let compact = compactRows(pageConfig: pageConfig)
        let totalSpacing = spacing * CGFloat(max(0, rows - 1))
        let compactTotal = compact.reduce(CGFloat(0)) { total, row in
            let isDivider = pageConfig.placements.contains {
                $0.row == row && $0.component == CustomComponent.horizontalDivider.rawValue
            }
            return total + (isDivider ? dividerThickness : compactRowHeight)
        }
        let remaining = max(0, innerH - totalSpacing - compactTotal)
        let rowWeights = weights(for: pageIndex, count: rows, store: rowWeightsByPage)
        let regularWeightTotal = (0..<rows)
            .filter { !compact.contains($0) }
            .reduce(CGFloat(0)) { total, row in total + rowWeights[row] }

        return (0..<rows).map { row in
            if compact.contains(row) {
                let isDivider = pageConfig.placements.contains {
                    $0.row == row && $0.component == CustomComponent.horizontalDivider.rawValue
                }
                return isDivider ? dividerThickness : compactRowHeight
            }
            guard regularWeightTotal > 0 else { return 0 }
            return remaining * rowWeights[row] / regularWeightTotal
        }
    }

    private func columnWidths(pageIndex: Int, pageConfig: CustomDayViewConfig.PageConfig, innerW: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let cols = pageConfig.cols
        guard cols > 0 else { return [] }
        let totalSpacing = spacing * CGFloat(max(0, cols - 1))
        let dividerCols = dividerColumns(pageConfig: pageConfig)
        let dividerTotal = CGFloat(dividerCols.count) * dividerThickness
        let available = max(0, innerW - totalSpacing - dividerTotal)
        let colWeights = weights(for: pageIndex, count: cols, store: colWeightsByPage)
        let totalWeight = (0..<cols)
            .filter { !dividerCols.contains($0) }
            .reduce(CGFloat(0)) { total, col in total + colWeights[col] }
        guard totalWeight > 0 else { return Array(repeating: 0, count: cols) }
        return (0..<cols).map { col in
            dividerCols.contains(col) ? dividerThickness : available * colWeights[col] / totalWeight
        }
    }

    private func dividerColumns(pageConfig: CustomDayViewConfig.PageConfig) -> Set<Int> {
        var set: Set<Int> = []
        for placement in pageConfig.placements where placement.component == CustomComponent.verticalDivider.rawValue {
            let region = mergedRegion(at: placement.row, col: placement.col, in: pageConfig)
            let colSpan = region?.colSpan ?? 1
            if colSpan == 1 {
                set.insert(placement.col)
            }
        }
        return set
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

    private func colXStart(col: Int, colWidths: [CGFloat], spacing: CGFloat, padding: CGFloat) -> CGFloat {
        var x = padding
        for c in 0..<col where c < colWidths.count {
            x += colWidths[c] + spacing
        }
        return x
    }

    private func spannedColumnsWidth(startCol: Int, colSpan: Int, colWidths: [CGFloat], spacing: CGFloat) -> CGFloat {
        let endExclusive = min(startCol + colSpan, colWidths.count)
        var w: CGFloat = 0
        for c in startCol..<endExclusive {
            w += colWidths[c]
        }
        w += spacing * CGFloat(max(0, endExclusive - startCol - 1))
        return w
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

    private func componentContaining(row: Int, col: Int, pageConfig: CustomDayViewConfig.PageConfig) -> CustomComponent? {
        if let region = pageConfig.merges.first(where: { region in
            row >= region.topRow && row < region.topRow + region.rowSpan &&
            col >= region.leftCol && col < region.leftCol + region.colSpan
        }) {
            return pageConfig.placements.first {
                $0.row == region.topRow && $0.col == region.leftCol
            }.flatMap { CustomComponent(rawValue: $0.component) }
        }

        return pageConfig.placements.first {
            $0.row == row && $0.col == col
        }.flatMap { CustomComponent(rawValue: $0.component) }
    }

    private func blocksDividerExtent(row: Int, col: Int, pageConfig: CustomDayViewConfig.PageConfig) -> Bool {
        if cellIsInGroup(row: row, col: col, pageConfig: pageConfig) { return true }
        guard let component = componentContaining(row: row, col: col, pageConfig: pageConfig) else { return false }
        return !component.isCustomDivider
    }

    private func dividerHorizontalSpan(row: Int, col: Int, pageConfig: CustomDayViewConfig.PageConfig) -> (startCol: Int, colSpan: Int) {
        var start = col
        while start > 0 && !blocksDividerExtent(row: row, col: start - 1, pageConfig: pageConfig) {
            start -= 1
        }

        var end = col
        while end + 1 < pageConfig.cols && !blocksDividerExtent(row: row, col: end + 1, pageConfig: pageConfig) {
            end += 1
        }

        return (start, end - start + 1)
    }

    private func dividerVerticalSpan(row: Int, col: Int, pageConfig: CustomDayViewConfig.PageConfig) -> (startRow: Int, rowSpan: Int) {
        var start = row
        while start > 0 && !blocksDividerExtent(row: start - 1, col: col, pageConfig: pageConfig) {
            start -= 1
        }

        var end = row
        while end + 1 < pageConfig.rows && !blocksDividerExtent(row: end + 1, col: col, pageConfig: pageConfig) {
            end += 1
        }

        return (start, end - start + 1)
    }

    @ViewBuilder
    private func customDividerView(
        component: CustomComponent?,
        pageIndex: Int,
        row: Int,
        col: Int,
        pageConfig: CustomDayViewConfig.PageConfig,
        rowHeights: [CGFloat],
        colWidths: [CGFloat],
        spacing: CGFloat,
        padding: CGFloat
    ) -> some View {
        switch component {
        case .horizontalDivider:
            let span = dividerHorizontalSpan(row: row, col: col, pageConfig: pageConfig)
            let width = spannedColumnsWidth(startCol: span.startCol, colSpan: span.colSpan, colWidths: colWidths, spacing: spacing)
            let x = colXStart(col: span.startCol, colWidths: colWidths, spacing: spacing, padding: padding)
            let y = rowYStart(row: row, rowHeights: rowHeights, spacing: spacing, padding: padding)
                + (row < rowHeights.count ? rowHeights[row] / 2 : 0)
            let isActive = row > 0 && row + 1 < pageConfig.rows

            draggableDividerHandle(axis: .horizontal, isActive: isActive)
                .frame(width: width, height: 12)
                .position(x: x + width / 2, y: y)
                .gesture(horizontalDividerGesture(pageIndex: pageIndex, row: row))

        case .verticalDivider:
            let span = dividerVerticalSpan(row: row, col: col, pageConfig: pageConfig)
            let height = spannedRowsHeight(startRow: span.startRow, rowSpan: span.rowSpan, rowHeights: rowHeights, spacing: spacing)
            let x = colXStart(col: col, colWidths: colWidths, spacing: spacing, padding: padding)
                + (col < colWidths.count ? colWidths[col] / 2 : 0)
            let y = rowYStart(row: span.startRow, rowHeights: rowHeights, spacing: spacing, padding: padding)
            let isActive = col > 0 && col + 1 < pageConfig.cols

            draggableDividerHandle(axis: .vertical, isActive: isActive)
                .frame(width: 12, height: height)
                .position(x: x, y: y + height / 2)
                .gesture(verticalDividerGesture(pageIndex: pageIndex, col: col))

        default:
            EmptyView()
        }
    }

    private enum CustomDividerAxis {
        case horizontal
        case vertical
    }

    private func draggableDividerHandle(axis: CustomDividerAxis, isActive: Bool) -> some View {
        Rectangle()
            .fill((axis == .horizontal ? draggingHorizontalDivider : draggingVerticalDivider) ? Color.blue.opacity(0.55) : Color.gray.opacity(isActive ? 0.35 : 0.18))
            .overlay(
                Image(systemName: axis == .horizontal ? "line.3.horizontal" : "line.3.vertical")
                    .font(.caption)
                    .foregroundColor(isActive ? .gray : .secondary.opacity(0.5))
            )
            .contentShape(Rectangle())
    }

    private func horizontalDividerGesture(pageIndex: Int, row: Int) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard row > 0 else { return }
                draggingHorizontalDivider = true
                if horizontalDragBaseWeights == nil {
                    horizontalDragBaseWeights = rowWeightsByPage[pageIndex]
                }
                adjustRowWeights(
                    pageIndex: pageIndex,
                    upperRow: row - 1,
                    lowerRow: row + 1,
                    translation: value.translation.height,
                    baseWeights: horizontalDragBaseWeights
                )
            }
            .onEnded { _ in
                draggingHorizontalDivider = false
                horizontalDragBaseWeights = nil
                if let weights = rowWeightsByPage[pageIndex] {
                    saveWeights(weights, axis: "rows", pageIndex: pageIndex)
                }
            }
    }

    private func verticalDividerGesture(pageIndex: Int, col: Int) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard col > 0 else { return }
                draggingVerticalDivider = true
                if verticalDragBaseWeights == nil {
                    verticalDragBaseWeights = colWeightsByPage[pageIndex]
                }
                adjustColWeights(
                    pageIndex: pageIndex,
                    leftCol: col - 1,
                    rightCol: col + 1,
                    translation: value.translation.width,
                    baseWeights: verticalDragBaseWeights
                )
            }
            .onEnded { _ in
                draggingVerticalDivider = false
                verticalDragBaseWeights = nil
                if let weights = colWeightsByPage[pageIndex] {
                    saveWeights(weights, axis: "cols", pageIndex: pageIndex)
                }
            }
    }

    private func adjustRowWeights(pageIndex: Int, upperRow: Int, lowerRow: Int, translation: CGFloat, baseWeights: [CGFloat]?) {
        guard var weights = baseWeights ?? rowWeightsByPage[pageIndex],
              weights.indices.contains(upperRow),
              weights.indices.contains(lowerRow) else { return }

        let delta = translation / 80
        let combined = max(0.4, weights[upperRow] + weights[lowerRow])
        let upper = min(max(0.2, weights[upperRow] + delta), combined - 0.2)
        weights[upperRow] = upper
        weights[lowerRow] = combined - upper
        rowWeightsByPage[pageIndex] = weights
    }

    private func adjustColWeights(pageIndex: Int, leftCol: Int, rightCol: Int, translation: CGFloat, baseWeights: [CGFloat]?) {
        guard var weights = baseWeights ?? colWeightsByPage[pageIndex],
              weights.indices.contains(leftCol),
              weights.indices.contains(rightCol) else { return }

        let delta = translation / 80
        let combined = max(0.4, weights[leftCol] + weights[rightCol])
        let left = min(max(0.2, weights[leftCol] + delta), combined - 0.2)
        weights[leftCol] = left
        weights[rightCol] = combined - left
        colWeightsByPage[pageIndex] = weights
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
                .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
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
        case .tasksAccount1Grouped:
            tasksGroupedView(for: .account1, date: date)
        case .tasksAccount2Grouped:
            tasksGroupedView(for: .account2, date: date)
        case .tasksAccount1TwoColumn:
            tasksTwoColumnView(for: .account1, date: date)
        case .tasksAccount2TwoColumn:
            tasksTwoColumnView(for: .account2, date: date)
        case .tasksAccount1Compact:
            tasksCompactView(for: .account1, date: date)
        case .tasksAccount2Compact:
            tasksCompactView(for: .account2, date: date)
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
        case .logCustom2:
            // Direct CustomLogView render for the second collection — wraps
            // the body in the same boxed-section styling LogsComponent uses
            // for `customLogSection`, with the second collection's name.
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(AppPreferences.shared.customLogSectionName(for: 1))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                }
                CustomLogView(collectionIndex: 1)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        case .logCustomWeek:
            CustomLogWeekComponent(currentDate: date)
        case .logCustomWeek2:
            CustomLogWeekComponent(currentDate: date, collectionIndex: 1)
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
        case .weeklyGoalsBar:
            WeeklyGoalsBarComponent(currentDate: date)
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
        case .horizontalDivider, .verticalDivider:
            EmptyView()
        }
    }

    // MARK: - Events

    private func eventsTimelineView(date: Date) -> some View {
        let account1Events = calendarVM.account1Events.filter { Calendar.current.isDate($0.startTime ?? .distantPast, inSameDayAs: date) }
        let account2Events = calendarVM.account2Events.filter { Calendar.current.isDate($0.startTime ?? .distantPast, inSameDayAs: date) }
        let all = calendarVM.events(for: date)
        // `DraggableTimeboxComponent` owns its own ScrollView + ScrollViewReader
        // and auto-scrolls to the current hour on appear. Wrapping it in another
        // ScrollView here would swallow that programmatic scroll, so render
        // it directly — this keeps the "now" redline in view on first render.
        return DraggableTimeboxComponent(
            date: date,
            events: all,
            account1Events: account1Events,
            account2Events: account2Events,
            account1Tasks: filteredTasksDictForDay(tasksVM.account1Tasks, on: date),
            account2Tasks: filteredTasksDictForDay(tasksVM.account2Tasks, on: date),
            account1Color: appPrefs.account1Color,
            account2Color: appPrefs.account2Color,
            onEventTap: { ev in
                onEventTap?(ev)
                selectedEvent = ev
            },
            onTaskTap: { task, listId in
                let accountKind: GoogleAuthManager.AccountKind = tasksVM.account1Tasks[listId] != nil ? .account1 : .account2
                selectedTask = task
                selectedTaskListId = listId
                selectedTaskAccount = accountKind
                showingTaskDetails = true
            },
            onTaskToggle: { task, listId in
                let accountKind: GoogleAuthManager.AccountKind = tasksVM.account1Tasks[listId] != nil ? .account1 : .account2
                Task { await tasksVM.toggleTaskCompletion(task, in: listId, for: accountKind) }
            },
            showAllDaySection: true,
            isBulkEditMode: bulkEditManager.state.isActive,
            selectedTaskIds: bulkEditManager.state.selectedTaskIds,
            onTaskSelectionToggle: { task in
                if bulkEditManager.state.selectedTaskIds.contains(task.id) {
                    bulkEditManager.state.selectedTaskIds.remove(task.id)
                } else {
                    bulkEditManager.state.selectedTaskIds.insert(task.id)
                }
            }
        )
    }

    private func eventsListView(date: Date) -> some View {
        EventsListComponent(
            events: calendarVM.events(for: date),
            account1Events: calendarVM.account1Events,
            account2Events: calendarVM.account2Events,
            account1Color: appPrefs.account1Color,
            account2Color: appPrefs.account2Color,
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
            let dict = account == .account1 ? tasksVM.account1Tasks : tasksVM.account2Tasks
            let lists = account == .account1 ? tasksVM.account1TaskLists : tasksVM.account2TaskLists
            ScrollView(.vertical, showsIndicators: true) {
                TasksComponent(
                    taskLists: lists,
                    tasksDict: filteredTasksDictForDay(dict, on: date),
                    accentColor: account == .account1 ? appPrefs.account1Color : appPrefs.account2Color,
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
                    showTaskStartTime: true,
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
            .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
        } else {
            notLinkedPlaceholder(for: account)
        }
    }

    @ViewBuilder
    private func tasksTwoColumnView(for account: GoogleAuthManager.AccountKind, date: Date) -> some View {
        if auth.isLinked(kind: account) {
            let dict = account == .account1 ? tasksVM.account1Tasks : tasksVM.account2Tasks
            let lists = account == .account1 ? tasksVM.account1TaskLists : tasksVM.account2TaskLists
            ScrollView(.vertical, showsIndicators: true) {
                TwoColumnTasksComponent(
                    taskLists: lists,
                    tasksDict: filteredTasksDictForDay(dict, on: date),
                    accentColor: account == .account1 ? appPrefs.account1Color : appPrefs.account2Color,
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
                    onOrderChanged: { newOrder in
                        Task { await tasksVM.updateTaskListOrder(newOrder, for: account) }
                    },
                    hideDueDateTag: false,
                    showEmptyState: true,
                    isSingleDayView: true,
                    showTitle: true,
                    showTaskStartTime: true,
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
            .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
        } else {
            notLinkedPlaceholder(for: account)
        }
    }

    @ViewBuilder
    private func tasksCompactView(for account: GoogleAuthManager.AccountKind, date: Date) -> some View {
        if auth.isLinked(kind: account) {
            let dict = account == .account1 ? tasksVM.account1Tasks : tasksVM.account2Tasks
            let lists = account == .account1 ? tasksVM.account1TaskLists : tasksVM.account2TaskLists
            ScrollView(.vertical, showsIndicators: true) {
                TasksCompactComponent(
                    taskLists: lists,
                    tasksDict: filteredTasksDictForDay(dict, on: date),
                    accentColor: account == .account1 ? appPrefs.account1Color : appPrefs.account2Color,
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
                .padding(8)
            }
            .background(WeekExportScrollTagger(identifier: PrintDayHelper.dayVerticalScrollID))
        } else {
            notLinkedPlaceholder(for: account)
        }
    }

    private func notLinkedPlaceholder(for account: GoogleAuthManager.AccountKind) -> some View {
        let name = account == .account1 ? appPrefs.account1Name : appPrefs.account2Name
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
