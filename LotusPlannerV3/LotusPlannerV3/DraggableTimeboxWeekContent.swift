import SwiftUI

/// 7-column drag-aware weekly timebox grid. Replaces the inner per-column
/// rendering inside `TimeboxView` so the user can drag any event or timed
/// task vertically to change the time AND horizontally to change the day,
/// with a translucent shadow that snaps to both the target column and the
/// 15-minute slot under the cursor.
///
/// All seven columns share a single named coordinate space so the drag
/// gesture's `value.location` gives `(cursorX, cursorY)` relative to the
/// week — `cursorX / columnWidth` resolves the target day, `cursorY -
/// allDayHeight` resolves the snapped time.
///
/// Persistence on drop:
///   - timed event → timeline:        `CalendarViewModel.moveEventToDateTime`
///   - all-day event → timeline:      `CalendarViewModel.scheduleEvent`
///   - any event → all-day area:      `CalendarViewModel.moveEventToDate`
///   - timed task → timeline:         updates `task.due` + `saveTimeWindow`
///   - all-day task → timeline:       same, with a 30-min default duration
///   - any task → all-day area:       updates `task.due` + deletes window
struct DraggableTimeboxWeekContent: View {
    let weekDates: [Date]
    let columnWidth: CGFloat
    let allDayHeight: CGFloat
    let eventsByDate: [Date: [GoogleCalendarEvent]]
    let tasksByDate: [Date: [String: [GoogleTask]]]
    let personalColor: Color
    let professionalColor: Color
    let isBulkEditMode: Bool
    let selectedTaskIds: Set<String>
    let onEventTap: (GoogleCalendarEvent) -> Void
    let onTaskTap: (GoogleTask, String) -> Void
    let onTaskToggle: (GoogleTask, String) -> Void
    let onTaskSelectionToggle: (GoogleTask) -> Void
    let onCommit: () -> Void

    @ObservedObject private var calendarVM = CalendarViewModel.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @ObservedObject private var timeWindowManager = TaskTimeWindowManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared

    @State private var dragState: WeekDragState?
    /// Optimistic overrides keyed by the same internal id we use for drag
    /// state. Each entry says: "render this item at this date+time until
    /// the data flow catches up." Cleared on the next data publish so a
    /// failed async update reverts to the real state.
    @State private var pendingMoves: [String: PendingMove] = [:]
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?

    /// Per-day laid-out timed items. Built by `recomputeRenderCaches()`
    /// only when source data actually changes — NOT on every `dragState`
    /// mutation. This is the core fix for drag-tick stutter: previously
    /// the body's ForEach called `laidOut(timedItems(...))` for all 7
    /// days on every drag frame, doing O(n²) lane packing per frame.
    @State private var laneCache: [Date: [LaidOutTimedItem]] = [:]
    /// Per-day pre-resolved all-day events + tasks. Avoids the per-render
    /// linear `tasksVM.personalTasks[listId]?.contains(where:)` lookup
    /// that ran inside `allDayBand` for every all-day task.
    @State private var allDayCache: [Date: AllDayCacheEntry] = [:]

    private let hourHeight: CGFloat = 60
    private let startHour = 0
    private let endHour = 24
    /// Width of the leading gutter that holds hour labels. Exposed as a
    /// static so the parent `TimeboxView` can keep its day-header columns
    /// aligned with the timeline columns below.
    static let timeColumnWidth: CGFloat = 40
    private var timeColumnWidth: CGFloat { Self.timeColumnWidth }
    private let snapMinutes = 15
    private let minItemHeight: CGFloat = 24
    private let coordSpaceName = "draggableWeekTimeline"
    private let defaultEventDuration: TimeInterval = 3600
    private let defaultTaskDuration: TimeInterval = 1800

    // MARK: - Internal models

    private enum ItemKind {
        case event(GoogleCalendarEvent, isPersonal: Bool)
        case task(GoogleTask, listId: String, isPersonal: Bool)
    }

    private struct TimedItem: Identifiable {
        let id: String  // "event_<id>" or "task_<id>"
        let kind: ItemKind
        let title: String
        let startTime: Date
        let endTime: Date
        var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
        var isPersonal: Bool {
            switch kind {
            case .event(_, let p): return p
            case .task(_, _, let p): return p
            }
        }
    }

    private struct PendingMove: Equatable {
        let date: Date
        let start: Date
        /// Pre-existing all-day status — used by render so we know whether
        /// the item should appear in the all-day section or the timeline
        /// while waiting for the data flow to catch up.
        let isAllDay: Bool
    }

    /// Pre-resolved per-day all-day section data. Built once per data
    /// change so the render path is a simple ForEach with no filters or
    /// lookups.
    private struct AllDayCacheEntry {
        let events: [GoogleCalendarEvent]
        let tasks: [AllDayTaskRow]
    }
    private struct AllDayTaskRow: Identifiable {
        let task: GoogleTask
        let listId: String
        let isPersonal: Bool
        var id: String { task.id }
    }

    private struct WeekDragState {
        let itemId: String
        let kind: ItemKind
        /// The day this item is currently on (before drag).
        let originalDate: Date
        /// Original start time (for timed items); start of `originalDate`
        /// for all-day items.
        let originalStart: Date
        let duration: TimeInterval
        /// True when the drag began on a row in the all-day section.
        let wasAllDay: Bool
        var translation: CGSize
        /// Snapped target date (one of `weekDates`).
        var snappedDate: Date
        /// Snapped target start time (date component matches `snappedDate`).
        var snappedStart: Date
        /// True when cursor is below the all-day band — i.e. the drop
        /// would land in the timeline area, not the all-day section.
        var inTimeline: Bool
    }

    // MARK: - Body
    //
    // The week view is one big absolute-positioned ZStack. Every layer
    // — hour gridlines, hour labels in the gutter, all-day bands per
    // column, timed items, the now-line, and the drag shadow — uses
    // the SAME y formula (`yForHour`, `yForTime`) so alignment is a
    // mathematical guarantee rather than a layout-system promise. This
    // sidesteps the SwiftUI gotcha where an HStack of (label + grid
    // row) doesn't put a label at its row's top edge.

    /// y position (in the outer ZStack coordinate space) of the start
    /// of `hour` — i.e. where the full-hour gridline is drawn.
    private func yForHour(_ hour: Int) -> CGFloat {
        allDayHeight + 1 + CGFloat(hour - startHour) * hourHeight
    }

    /// y position (in the outer ZStack coordinate space) of an
    /// arbitrary time on the day — used by timed items and the
    /// now-line so they align with `yForHour` to the pixel.
    private func yForTime(_ date: Date) -> CGFloat {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        return allDayHeight + 1 + CGFloat(h - startHour) * hourHeight + CGFloat(m) * (hourHeight / 60.0)
    }

    var body: some View {
        let totalH = yForHour(endHour) + 1  // +1 for the closing-line pixel

        ZStack(alignment: .topLeading) {
            // 1. Hour & half-hour gridlines, full-width below the gutter.
            gridlinesLayer()

            // 2. Hour labels in the left gutter, vertically centered on
            //    each gridline.
            gutterLabels()

            // 3. All-day band divider (a 1pt line just above the
            //    timeline). Spans the full content width so it visually
            //    closes off the all-day region across all 7 columns.
            Rectangle()
                .fill(Color(.systemGray3))
                .frame(height: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: timeColumnWidth, y: allDayHeight)

            // 4. Per-day all-day bands, anchored at y = 0 in their
            //    columns. Each column's content sits at columnX...
            //    columnX + columnWidth. Reads from `allDayCache` so a
            //    drag-tick body re-render doesn't re-run `tasksVM.contains`
            //    or `timeWindowManager.getTimeWindow` for every task.
            ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                let columnX = self.columnX(for: index)
                let entry = allDayCache[date] ?? AllDayCacheEntry(events: [], tasks: [])
                allDayBand(date: date, entry: entry)
                    .frame(width: columnWidth, height: allDayHeight, alignment: .top)
                    .clipped()
                    .offset(x: columnX, y: 0)
            }

            // 5. Vertical dividers between day columns.
            ForEach(0..<max(0, weekDates.count - 1), id: \.self) { index in
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 1, height: totalH)
                    .offset(x: columnX(for: index) + columnWidth, y: 0)
            }

            // 6. Vertical divider between the gutter and the first day.
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 1, height: totalH)
                .offset(x: timeColumnWidth, y: 0)

            // 7. Timed items, absolutely positioned in the outer
            //    coordinate space using yForTime so they align with the
            //    gridlines pixel-for-pixel. Overlapping items are laned
            //    side-by-side via `laidOut(_:)` so each one stays
            //    legible instead of stacking on top of the others.
            //    `laneCache` is populated by `recomputeRenderCaches()`
            //    and is NOT recomputed when `dragState` changes — the
            //    fix for drag-tick stutter.
            ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                let columnX = self.columnX(for: index)
                let laned = laneCache[date] ?? []
                ForEach(laned, id: \.item.id) { entry in
                    timedItemPositioned(
                        item: entry.item,
                        columnX: columnX,
                        columnDate: date,
                        lane: entry.lane,
                        laneCount: entry.laneCount
                    )
                }
            }

            // 8. Drop shadow during a drag.
            if let s = dragState {
                shadowOverlay(state: s)
            }

            // 9. Now-line on today's column.
            if let todayIdx = todayColumnIndex {
                nowLine(columnIndex: todayIdx)
                    .zIndex(20)
            }
        }
        .frame(height: totalH)
        .coordinateSpace(name: coordSpaceName)
        .onAppear {
            startCurrentTimeTimer()
            recomputeRenderCaches()
        }
        .onDisappear { stopCurrentTimeTimer() }
        // Keep render caches in sync with the source data. Cache rebuilds
        // are intentionally NOT tied to `dragState` — the whole point is
        // that drag ticks read from the cache without recomputing.
        .onChange(of: weekDates) { _, _ in recomputeRenderCaches() }
        .onChange(of: pendingMoves) { _, _ in recomputeRenderCaches() }
        .onReceive(calendarVM.$personalEvents) { _ in recomputeRenderCaches() }
        .onReceive(calendarVM.$professionalEvents) { _ in recomputeRenderCaches() }
        .onReceive(tasksVM.$personalTasks) { _ in recomputeRenderCaches() }
        .onReceive(tasksVM.$professionalTasks) { _ in recomputeRenderCaches() }
        .onReceive(timeWindowManager.$timeWindows) { _ in recomputeRenderCaches() }
        .onReceive(appPrefs.$hideCompletedTasks) { _ in recomputeRenderCaches() }
    }

    // MARK: - Render cache build

    /// Rebuilds `laneCache` and `allDayCache` for the current week. Single
    /// pass over all 7 days; runs ~O(N log N) total per call (where N is
    /// items in the visible week). Call sites: initial `onAppear`, every
    /// publisher fire from upstream view models, and after a drag commit
    /// updates `pendingMoves`.
    private func recomputeRenderCaches() {
        var freshLanes: [Date: [LaidOutTimedItem]] = [:]
        var freshAllDay: [Date: AllDayCacheEntry] = [:]
        for date in weekDates {
            let events = eventsByDate[date] ?? []
            let tasksDict = tasksByDate[date] ?? [:]
            freshLanes[date] = laidOut(timedItems(date: date, events: events, tasksDict: tasksDict))
            freshAllDay[date] = makeAllDayEntry(events: events, tasksDict: tasksDict)
        }
        laneCache = freshLanes
        allDayCache = freshAllDay
    }

    /// Builds a single day's all-day entry. Replaces the per-render
    /// `tasksVM.personalTasks[listId]?.contains(where:)` linear search
    /// inside `allDayBand` — that lookup now happens once per data
    /// change instead of every drag frame.
    private func makeAllDayEntry(events: [GoogleCalendarEvent], tasksDict: [String: [GoogleTask]]) -> AllDayCacheEntry {
        let allDayEvents = events.filter { $0.isAllDay }
        // O(P) once instead of O(P) per task.
        let personalListIds = Set(tasksVM.personalTasks.keys)

        var allDayTasks: [AllDayTaskRow] = []
        for (listId, tasks) in tasksDict {
            let isPersonal = personalListIds.contains(listId)
            for task in tasks {
                let pending = pendingMoves["task_\(task.id)"]
                let isAllDay: Bool = {
                    if let p = pending { return p.isAllDay }
                    if let win = timeWindowManager.getTimeWindow(for: task.id) {
                        return win.isAllDay
                    }
                    return true
                }()
                guard isAllDay else { continue }
                if appPrefs.hideCompletedTasks && task.isCompleted { continue }
                allDayTasks.append(AllDayTaskRow(task: task, listId: listId, isPersonal: isPersonal))
            }
        }
        return AllDayCacheEntry(events: allDayEvents, tasks: allDayTasks)
    }

    /// Cumulative x offset of day column `index`, accounting for the
    /// leading gutter and the 1pt vertical divider between each pair
    /// of columns.
    private func columnX(for index: Int) -> CGFloat {
        timeColumnWidth + 1 + CGFloat(index) * (columnWidth + 1)
    }

    // MARK: - Background layers

    private func gridlinesLayer() -> some View {
        let gridStartX = timeColumnWidth + 1
        return ZStack(alignment: .topLeading) {
            // Full-hour lines: draw one per hour 0...24 (24 is the
            // closing line).
            ForEach(startHour...endHour, id: \.self) { hour in
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: gridStartX, y: yForHour(hour))
            }
            // Half-hour lines: drawn at hour + 30 minutes.
            ForEach(startHour..<endHour, id: \.self) { hour in
                Rectangle()
                    .fill(Color(.systemGray6))
                    .opacity(0.7)
                    .frame(height: 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: gridStartX, y: yForHour(hour) + hourHeight / 2)
            }
        }
    }

    private func gutterLabels() -> some View {
        ZStack(alignment: .topLeading) {
            // "all-day" gutter label, vertically centered in the
            // all-day band region.
            Text("all-day")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(width: timeColumnWidth, height: allDayHeight, alignment: .center)
                .offset(x: 0, y: 0)

            // Hour labels at 0...24, each centered on its full-hour
            // gridline. The 14-tall fixed frame plus -7pt shift gives
            // a vertical center exactly at yForHour(hour).
            ForEach(startHour...endHour, id: \.self) { hour in
                Text(formatHour(hour))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: timeColumnWidth - 4, height: 14, alignment: .trailing)
                    .offset(x: 0, y: yForHour(hour) - 7)
            }
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        if h == 0 { return "12a" }
        if h == 12 { return "12p" }
        return h < 12 ? "\(h)a" : "\(h - 12)p"
    }

    // MARK: - Per-day timed item rendering

    @ViewBuilder
    private func timedItemPositioned(
        item: TimedItem,
        columnX: CGFloat,
        columnDate: Date,
        lane: Int,
        laneCount: Int
    ) -> some View {
        let baseY = yForTime(item.startTime)
        let height = max(minItemHeight, CGFloat(item.duration / 3600.0) * hourHeight)
        let isDragging = dragState?.itemId == item.id
        let translation = isDragging ? (dragState?.translation ?? .zero) : .zero
        // Day column has a 4pt inset (2pt on each side). Within that
        // inset we divide horizontally into `laneCount` lanes; each
        // lane is `laneWidth` wide and starts at `laneOffsetX`.
        let usableWidth = max(0, columnWidth - 4)
        let lanes = max(1, laneCount)
        let laneWidth = usableWidth / CGFloat(lanes)
        let laneOffsetX: CGFloat = CGFloat(lane) * laneWidth
        let renderedX: CGFloat = isDragging ? translation.width : 0
        let renderedY: CGFloat = baseY + (isDragging ? translation.height : 0)

        timedItemView(item: item)
            .frame(width: max(0, laneWidth - 1), height: height, alignment: .topLeading)
            .opacity(isDragging ? 0.85 : 1.0)
            .offset(x: columnX + 2 + laneOffsetX + renderedX, y: renderedY)
            .zIndex(isDragging ? 40 : 10)
            .gesture(timedDragGesture(item: item, originalDate: columnDate, baseY: baseY))
    }

    // MARK: - Overlap laning

    /// One timed item plus its assigned lane within an overlap group.
    /// `lane` is 0-indexed; `laneCount` is the total lanes in the group
    /// the item belongs to (so width = columnInteriorWidth / laneCount).
    private struct LaidOutTimedItem {
        let item: TimedItem
        let lane: Int
        let laneCount: Int
    }

    /// Greedy lane-packing: items are sorted by start time, then each is
    /// placed in the lowest-indexed lane whose previous occupant ends
    /// before the new item starts. Items that overlap any active lane
    /// open a new one. Within an overlap group, every item is then
    /// rewritten to share the maximum lane count seen during the group
    /// so all overlapping items get the same width.
    private func laidOut(_ items: [TimedItem]) -> [LaidOutTimedItem] {
        guard !items.isEmpty else { return [] }
        let sorted = items.sorted { $0.startTime < $1.startTime }

        // Build overlap groups. A new group starts when the next item
        // begins after the latest end seen so far in the current group.
        var groups: [[TimedItem]] = []
        var current: [TimedItem] = []
        var currentMaxEnd: Date = .distantPast
        for item in sorted {
            if current.isEmpty || item.startTime < currentMaxEnd {
                current.append(item)
                if item.endTime > currentMaxEnd { currentMaxEnd = item.endTime }
            } else {
                groups.append(current)
                current = [item]
                currentMaxEnd = item.endTime
            }
        }
        if !current.isEmpty { groups.append(current) }

        var result: [LaidOutTimedItem] = []
        for group in groups {
            // Assign each item the smallest available lane.
            var laneEnds: [Date] = []
            var assigned: [Int] = []
            for item in group {
                var slot = -1
                for i in 0..<laneEnds.count where laneEnds[i] <= item.startTime {
                    slot = i
                    break
                }
                if slot == -1 {
                    slot = laneEnds.count
                    laneEnds.append(item.endTime)
                } else {
                    laneEnds[slot] = item.endTime
                }
                assigned.append(slot)
            }
            let laneCount = max(1, laneEnds.count)
            for (idx, item) in group.enumerated() {
                result.append(LaidOutTimedItem(
                    item: item,
                    lane: assigned[idx],
                    laneCount: laneCount
                ))
            }
        }
        return result
    }

    // MARK: All-day band

    private func allDayBand(date: Date, entry: AllDayCacheEntry) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(entry.events, id: \.id) { event in
                    let isPersonal = calendarVM.accountKind(for: event) == .personal
                    allDayEventCard(event: event, isPersonal: isPersonal, columnDate: date)
                }
                ForEach(entry.tasks) { row in
                    allDayTaskCard(task: row.task, listId: row.listId, isPersonal: row.isPersonal, columnDate: date)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    private func allDayEventCard(event: GoogleCalendarEvent, isPersonal: Bool, columnDate: Date) -> some View {
        let bg = isPersonal ? personalColor : professionalColor
        let id = "event_\(event.id)"
        let isDragging = dragState?.itemId == id
        return HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
            Text(event.summary)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(bg))
        .opacity(isDragging ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { onEventTap(event) }
        .gesture(allDayDragGesture(
            itemId: id,
            kind: .event(event, isPersonal: isPersonal),
            originalDate: columnDate,
            duration: defaultEventDuration
        ))
    }

    private func allDayTaskCard(task: GoogleTask, listId: String, isPersonal: Bool, columnDate: Date) -> some View {
        let accent = isPersonal ? personalColor : professionalColor
        let id = "task_\(task.id)"
        let isDragging = dragState?.itemId == id
        let isSelected = selectedTaskIds.contains(task.id)
        return HStack(spacing: 8) {
            if isBulkEditMode {
                Button { onTaskSelectionToggle(task) } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.body)
                        .foregroundColor(isSelected ? accent : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button { onTaskToggle(task, listId) } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundColor(task.isCompleted ? accent : .secondary)
                }
                .buttonStyle(.plain)
            }
            Text(task.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(task.isCompleted ? .secondary : .primary)
                .strikethrough(task.isCompleted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(accent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(accent.opacity(0.4), lineWidth: 1)
                )
        )
        .opacity(isDragging ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { onTaskTap(task, listId) }
        .gesture(allDayDragGesture(
            itemId: id,
            kind: .task(task, listId: listId, isPersonal: isPersonal),
            originalDate: columnDate,
            duration: defaultTaskDuration
        ))
    }

    // MARK: Timed item rendering

    @ViewBuilder
    private func timedItemView(item: TimedItem) -> some View {
        switch item.kind {
        case .event(let event, let isPersonal):
            timedEventCard(event: event, isPersonal: isPersonal)
        case .task(let task, let listId, let isPersonal):
            timedTaskCard(task: task, listId: listId, isPersonal: isPersonal)
        }
    }

    private func timedEventCard(event: GoogleCalendarEvent, isPersonal: Bool) -> some View {
        let bg = isPersonal ? personalColor : professionalColor
        return VStack(alignment: .leading, spacing: 1) {
            Text(event.summary)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 5).fill(bg))
        .contentShape(Rectangle())
        .onTapGesture { onEventTap(event) }
    }

    private func timedTaskCard(task: GoogleTask, listId: String, isPersonal: Bool) -> some View {
        let accent = isPersonal ? personalColor : professionalColor
        let isSelected = selectedTaskIds.contains(task.id)
        return HStack(spacing: 8) {
            if isBulkEditMode {
                Button { onTaskSelectionToggle(task) } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.body)
                        .foregroundColor(isSelected ? accent : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button { onTaskToggle(task, listId) } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundColor(task.isCompleted ? accent : .secondary)
                }
                .buttonStyle(.plain)
            }
            Text(task.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(task.isCompleted ? .secondary : .primary)
                .strikethrough(task.isCompleted)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(accent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(accent.opacity(0.4), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onTaskTap(task, listId) }
    }

    // MARK: - Shadow overlay

    @ViewBuilder
    private func shadowOverlay(state: WeekDragState) -> some View {
        let dayIdx = weekDates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: state.snappedDate) }) ?? 0
        let cx = columnX(for: dayIdx)

        if state.inTimeline {
            let snappedY = yForTime(state.snappedStart)
            let height = max(minItemHeight, CGFloat(state.duration / 3600.0) * hourHeight)
            shadowBox(state: state, label: timeLabel(for: state.snappedStart))
                .frame(width: max(0, columnWidth - 4), height: height, alignment: .topLeading)
                .offset(x: cx + 2, y: snappedY)
                .zIndex(50)
        } else {
            // Dropping into the all-day band — draw a slimmer pill at the
            // top of the target column.
            shadowBox(state: state, label: "All-day")
                .frame(width: max(0, columnWidth - 4), height: 20, alignment: .topLeading)
                .offset(x: cx + 2, y: max(0, allDayHeight - 22))
                .zIndex(50)
        }
    }

    private func shadowBox(state: WeekDragState, label: String) -> some View {
        let isPersonal: Bool = {
            switch state.kind {
            case .event(_, let p): return p
            case .task(_, _, let p): return p
            }
        }()
        let accent = isPersonal ? personalColor : professionalColor
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(accent.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(accent.opacity(0.18))
                )
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(Color(.systemBackground).opacity(0.92))
                        .overlay(Capsule().stroke(accent.opacity(0.6), lineWidth: 1))
                )
                .padding(2)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Now indicator

    private var todayColumnIndex: Int? {
        let cal = Calendar.current
        return weekDates.firstIndex { cal.isDate($0, inSameDayAs: currentTime) }
    }

    private func nowLine(columnIndex: Int) -> some View {
        let y = yForTime(currentTime)
        let cx = columnX(for: columnIndex)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.red.opacity(0.85))
                .frame(width: columnWidth, height: 1.5)
                .offset(x: cx, y: y)
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .offset(x: cx - 3, y: y - 3)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drag gestures

    private func timedDragGesture(item: TimedItem, originalDate: Date, baseY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(coordSpaceName))
            .onChanged { value in
                updateDragState(
                    itemId: item.id,
                    kind: item.kind,
                    originalDate: originalDate,
                    originalStart: item.startTime,
                    duration: item.duration,
                    wasAllDay: false,
                    translation: value.translation,
                    cursor: value.location
                )
            }
            .onEnded { _ in
                guard let s = dragState, s.itemId == item.id else {
                    dragState = nil
                    return
                }
                commitDrag(state: s)
                dragState = nil
            }
    }

    private func allDayDragGesture(itemId: String, kind: ItemKind, originalDate: Date, duration: TimeInterval) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(coordSpaceName))
            .onChanged { value in
                let originalStart = Calendar.current.startOfDay(for: originalDate)
                updateDragState(
                    itemId: itemId,
                    kind: kind,
                    originalDate: originalDate,
                    originalStart: originalStart,
                    duration: duration,
                    wasAllDay: true,
                    translation: value.translation,
                    cursor: value.location
                )
            }
            .onEnded { _ in
                guard let s = dragState, s.itemId == itemId else {
                    dragState = nil
                    return
                }
                commitDrag(state: s)
                dragState = nil
            }
    }

    private func updateDragState(
        itemId: String,
        kind: ItemKind,
        originalDate: Date,
        originalStart: Date,
        duration: TimeInterval,
        wasAllDay: Bool,
        translation: CGSize,
        cursor: CGPoint
    ) {
        // (cursor.x - gutter - gutter divider) / column stride → day index.
        // Day columns are laid out at columnX(for: i) = timeColumnWidth +
        // 1 + i * (columnWidth + 1), matching the rendering math.
        let stride = max(1, columnWidth + 1)
        let dayLocalX = cursor.x - timeColumnWidth - 1
        let rawDayIdx = Int(floor(dayLocalX / stride))
        let dayIdx = max(0, min(weekDates.count - 1, rawDayIdx))
        let targetDate = weekDates[dayIdx]

        // Cursor Y - all-day band - 1pt divider → snapped time on the
        // target date. Mirrors the +1 in `yForHour` so the snapped slot
        // lines up with the gridline under the cursor.
        let timelineY = cursor.y - allDayHeight - 1
        let inTimeline = timelineY > 0
        let snappedStart = snappedTimeOnDate(targetDate, atTimelineY: timelineY, duration: duration)

        if dragState?.itemId == itemId {
            dragState?.translation = translation
            dragState?.snappedDate = targetDate
            dragState?.snappedStart = snappedStart
            dragState?.inTimeline = inTimeline
        } else {
            dragState = WeekDragState(
                itemId: itemId,
                kind: kind,
                originalDate: originalDate,
                originalStart: originalStart,
                duration: duration,
                wasAllDay: wasAllDay,
                translation: translation,
                snappedDate: targetDate,
                snappedStart: snappedStart,
                inTimeline: inTimeline
            )
        }
    }

    private func snappedTimeOnDate(_ date: Date, atTimelineY y: CGFloat, duration: TimeInterval) -> Date {
        let minutesPerPoint = 60.0 / Double(hourHeight)
        let rawMinutes = Double(max(0, y)) * minutesPerPoint
        let snapped = (Int(rawMinutes.rounded()) / snapMinutes) * snapMinutes
        let durationMinutes = Int(duration / 60)
        let maxStart = (endHour - startHour) * 60 - max(durationMinutes, snapMinutes)
        let clamped = max(0, min(snapped, maxStart))
        return Calendar.current.date(
            bySettingHour: startHour + clamped / 60,
            minute: clamped % 60,
            second: 0,
            of: date
        ) ?? date
    }

    // MARK: - Commit

    private func commitDrag(state: WeekDragState) {
        // Skip if nothing changed.
        let cal = Calendar.current
        let targetIsAllDay = !state.inTimeline
        let sameDate = cal.isDate(state.originalDate, inSameDayAs: state.snappedDate)
        let sameTime = !state.wasAllDay && state.originalStart == state.snappedStart
        if sameDate && (targetIsAllDay == state.wasAllDay) && (state.wasAllDay || sameTime) {
            return
        }

        // Record optimistic override so the item shows at the new spot
        // immediately while the async API call is in flight. Cleared after
        // 3 seconds — a failed update will then revert visually.
        let internalId = state.itemId
        let pending = PendingMove(
            date: state.snappedDate,
            start: targetIsAllDay ? cal.startOfDay(for: state.snappedDate) : state.snappedStart,
            isAllDay: targetIsAllDay
        )
        pendingMoves[internalId] = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            pendingMoves.removeValue(forKey: internalId)
            onCommit()
        }

        switch state.kind {
        case .event(let event, _):
            commitEvent(event: event, state: state, targetIsAllDay: targetIsAllDay)
        case .task(let task, let listId, _):
            commitTask(task: task, listId: listId, state: state, targetIsAllDay: targetIsAllDay)
        }
    }

    private func commitEvent(event: GoogleCalendarEvent, state: WeekDragState, targetIsAllDay: Bool) {
        Task { @MainActor in
            if targetIsAllDay {
                // Land in the all-day band → keep all-day status (or
                // convert timed → all-day on the new date).
                await calendarVM.moveEventToDate(event, to: state.snappedDate, forceAllDay: true)
            } else if state.wasAllDay {
                // All-day → timed at the dropped slot on (possibly) a new day.
                await calendarVM.scheduleEvent(event, startTime: state.snappedStart, duration: state.duration)
            } else {
                // Timed → timed at the dropped slot (same or different day).
                await calendarVM.moveEventToDateTime(event, to: state.snappedStart)
            }
            onCommit()
        }
    }

    private func commitTask(task: GoogleTask, listId: String, state: WeekDragState, targetIsAllDay: Bool) {
        // Determine which account this task belongs to from the in-memory
        // task dictionaries — the drag state doesn't carry it.
        let isPersonal = tasksVM.personalTasks[listId]?.contains(where: { $0.id == task.id }) ?? false
        let kind: GoogleAuthManager.AccountKind = isPersonal ? .personal : .professional

        if targetIsAllDay {
            TaskScheduler.scheduleAllDay(
                task: task,
                listId: listId,
                kind: kind,
                on: state.snappedDate
            )
        } else {
            // Prefer prior window's duration so the visual size is
            // preserved across days; fall back to the drag's duration.
            let duration = TaskScheduler.resolvedDuration(forTaskId: task.id, fallback: state.duration)
            TaskScheduler.scheduleTimed(
                task: task,
                listId: listId,
                kind: kind,
                start: state.snappedStart,
                duration: duration
            )
        }
        onCommit()
    }

    // MARK: - Item assembly

    private func timedItems(date: Date, events: [GoogleCalendarEvent], tasksDict: [String: [GoogleTask]]) -> [TimedItem] {
        var result: [TimedItem] = []

        for event in events where !event.isAllDay {
            guard let start = event.startTime, let end = event.endTime else { continue }
            let isPersonal = calendarVM.accountKind(for: event) == .personal
            let id = "event_\(event.id)"
            let dur = end.timeIntervalSince(start)
            // Apply pending optimistic override.
            if let p = pendingMoves[id] {
                if p.isAllDay { continue }
                let onThisDate = Calendar.current.isDate(p.date, inSameDayAs: date)
                guard onThisDate else { continue }
                result.append(TimedItem(
                    id: id,
                    kind: .event(event, isPersonal: isPersonal),
                    title: event.summary,
                    startTime: p.start,
                    endTime: p.start.addingTimeInterval(dur)
                ))
                continue
            }
            // Default: render where the data says.
            guard Calendar.current.isDate(start, inSameDayAs: date) else { continue }
            result.append(TimedItem(
                id: id,
                kind: .event(event, isPersonal: isPersonal),
                title: event.summary,
                startTime: start,
                endTime: end
            ))
        }

        for (listId, tasks) in tasksDict {
            for task in tasks {
                let id = "task_\(task.id)"
                let isPersonal = tasksVM.personalTasks[listId]?.contains(where: { $0.id == task.id }) ?? false
                if let p = pendingMoves[id] {
                    if p.isAllDay { continue }
                    let onThisDate = Calendar.current.isDate(p.date, inSameDayAs: date)
                    guard onThisDate else { continue }
                    let dur: TimeInterval
                    if let win = timeWindowManager.getTimeWindow(for: task.id), !win.isAllDay {
                        dur = win.endTime.timeIntervalSince(win.startTime)
                    } else {
                        dur = defaultTaskDuration
                    }
                    result.append(TimedItem(
                        id: id,
                        kind: .task(task, listId: listId, isPersonal: isPersonal),
                        title: task.title,
                        startTime: p.start,
                        endTime: p.start.addingTimeInterval(dur)
                    ))
                    continue
                }
                guard let win = timeWindowManager.getTimeWindow(for: task.id),
                      !win.isAllDay else { continue }
                if appPrefs.hideCompletedTasks && task.isCompleted { continue }
                // Anchor the window's hour/minute to this column's date.
                // The window may have been saved on a different calendar
                // day than the task's current `dueDate` (recurrence
                // respawn or dueDate edit without re-saving the window);
                // matching strictly on `win.startTime`'s day would drop
                // the task out of both bands.
                let cal = Calendar.current
                let startTOD = cal.dateComponents([.hour, .minute, .second], from: win.startTime)
                let endTOD = cal.dateComponents([.hour, .minute, .second], from: win.endTime)
                let anchoredStart = cal.date(
                    bySettingHour: startTOD.hour ?? 0,
                    minute: startTOD.minute ?? 0,
                    second: startTOD.second ?? 0,
                    of: date
                ) ?? date
                let anchoredEndCandidate = cal.date(
                    bySettingHour: endTOD.hour ?? 0,
                    minute: endTOD.minute ?? 0,
                    second: endTOD.second ?? 0,
                    of: date
                ) ?? anchoredStart
                let anchoredEnd = anchoredEndCandidate > anchoredStart
                    ? anchoredEndCandidate
                    : anchoredStart.addingTimeInterval(defaultTaskDuration)
                result.append(TimedItem(
                    id: id,
                    kind: .task(task, listId: listId, isPersonal: isPersonal),
                    title: task.title,
                    startTime: anchoredStart,
                    endTime: anchoredEnd
                ))
            }
        }
        return result
    }

    // MARK: - Time math

    private func timeLabel(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }

    // MARK: - Now timer

    private func startCurrentTimeTimer() {
        currentTimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            DispatchQueue.main.async { self.currentTime = Date() }
        }
        currentTime = Date()
    }

    private func stopCurrentTimeTimer() {
        currentTimeTimer?.invalidate()
        currentTimeTimer = nil
    }
}
