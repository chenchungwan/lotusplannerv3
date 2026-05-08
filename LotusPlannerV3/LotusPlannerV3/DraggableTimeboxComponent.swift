import SwiftUI
import UniformTypeIdentifiers

/// A timeline view of a single day's events and timed tasks where the user
/// can drag any item vertically to reschedule it.
///
/// Drop-in replacement for `TimeboxComponent` (same init signature) so day
/// view layouts can swap to it without further plumbing. The week-level
/// `TimeboxView` still uses the original — there each "day" is a narrow
/// column where finger-drag would be too cramped.
///
/// During a drag the original item follows the finger continuously while a
/// translucent "shadow" snaps to the 15-minute grid and shows the time the
/// item would land on if released. On drop, the new start time is committed:
///   - Events: `CalendarViewModel.moveEventToDateTime` (PATCH on Google Calendar)
///   - Tasks:  `TaskTimeWindowManager.saveTimeWindow`  (local time-of-day store;
///             Google Tasks doesn't expose time-of-day, so we keep `task.due`
///             on the same day and only adjust the local window)
struct DraggableTimeboxComponent: View {
    let date: Date
    let events: [GoogleCalendarEvent]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalTasks: [String: [GoogleTask]]
    let professionalTasks: [String: [GoogleTask]]
    let personalColor: Color
    let professionalColor: Color
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    let onTaskTap: ((GoogleTask, String) -> Void)?
    let onTaskToggle: ((GoogleTask, String) -> Void)?
    let showAllDaySection: Bool
    let isBulkEditMode: Bool
    let selectedTaskIds: Set<String>
    let onTaskSelectionToggle: ((GoogleTask) -> Void)?

    @ObservedObject private var timeWindowManager = TaskTimeWindowManager.shared
    @ObservedObject private var calendarVM = CalendarViewModel.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @ObservedObject private var appPrefs = AppPreferences.shared

    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    @State private var dragState: DragState?
    /// Snapped landing times we just committed, keyed by our internal
    /// item id (`"event_<id>"` / `"task_<id>"`). Holds the rendered
    /// position at the new time until the underlying data publishes the
    /// update — covers the async Google Calendar PATCH and prevents the
    /// "snaps back to old position then jumps forward" flicker.
    @State private var pendingStarts: [String: Date] = [:]
    /// Decoded payload of an in-flight drag from the Tasks component.
    /// Populated once on `dropEntered` (NSItemProvider load is async); we
    /// then use the cached value to update `dragState` continuously on
    /// `dropUpdated` so the snapped-time shadow tracks the cursor.
    @State private var externalDragInfo: DraggableTaskInfo?

    private let hourHeight: CGFloat = 60
    private let startHour = 0
    private let endHour = 24
    private let timeColumnWidth: CGFloat = 28
    private let snapMinutes = 15
    private let minItemHeight: CGFloat = 30

    init(
        date: Date,
        events: [GoogleCalendarEvent],
        personalEvents: [GoogleCalendarEvent],
        professionalEvents: [GoogleCalendarEvent],
        personalTasks: [String: [GoogleTask]] = [:],
        professionalTasks: [String: [GoogleTask]] = [:],
        personalColor: Color,
        professionalColor: Color,
        onEventTap: ((GoogleCalendarEvent) -> Void)? = nil,
        onTaskTap: ((GoogleTask, String) -> Void)? = nil,
        onTaskToggle: ((GoogleTask, String) -> Void)? = nil,
        showAllDaySection: Bool = true,
        isBulkEditMode: Bool = false,
        selectedTaskIds: Set<String> = [],
        onTaskSelectionToggle: ((GoogleTask) -> Void)? = nil
    ) {
        self.date = date
        self.events = events
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalTasks = personalTasks
        self.professionalTasks = professionalTasks
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.onEventTap = onEventTap
        self.onTaskTap = onTaskTap
        self.onTaskToggle = onTaskToggle
        self.showAllDaySection = showAllDaySection
        self.isBulkEditMode = isBulkEditMode
        self.selectedTaskIds = selectedTaskIds
        self.onTaskSelectionToggle = onTaskSelectionToggle
    }

    // MARK: - Internal models

    fileprivate enum ItemKind {
        case event(GoogleCalendarEvent, isPersonal: Bool)
        case task(GoogleTask, listId: String, isPersonal: Bool)
    }

    private struct TimedItem: Identifiable {
        let id: String
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
        var isTask: Bool {
            switch kind {
            case .task: return true
            case .event: return false
            }
        }
    }

    /// Live-tracked translation + snapped landing time during a drag.
    fileprivate struct DragState {
        let itemId: String
        let originalStart: Date
        let duration: TimeInterval
        let kind: ItemKind
        /// True when the drag started from a row in the all-day section.
        /// On drop we route those through the all-day → timed conversion
        /// path (events: `scheduleEvent`; tasks: a fresh non-all-day window).
        let wasAllDay: Bool
        var translation: CGFloat
        var snappedStart: Date
        /// Cursor Y in the timeline's coordinate space. Used for all-day
        /// drags to suppress the shadow (and skip commit) until the user
        /// has actually dragged into the timeline area.
        var cursorY: CGFloat
    }

    private let defaultEventDuration: TimeInterval = 3600
    private let defaultTaskDuration: TimeInterval = 1800
    private let timelineCoordSpace = "draggableTimeline"

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    if showAllDaySection && (hasAllDayEvents || hasAllDayTasks) {
                        allDaySection
                            .padding(.bottom, 8)
                    }

                    let totalHeight = CGFloat(endHour - startHour) * hourHeight + 20
                    GeometryReader { geometry in
                        let contentOriginX = timeColumnWidth + 1
                        let contentWidth = max(0, geometry.size.width - contentOriginX)

                        ZStack(alignment: .topLeading) {
                            // Transparent rectangle fills the full frame so
                            // the drop target reliably accepts hits across
                            // the entire timeline (including any gaps
                            // between hour-grid stripes).
                            Color.clear
                                .contentShape(Rectangle())

                            hourGrid
                            itemsLayer(contentOriginX: contentOriginX, contentWidth: contentWidth)

                            // Drag shadow — semi-transparent ghost at the
                            // snapped landing time, with a time label so
                            // the user knows exactly where they'll drop.
                            // For an all-day origin we suppress the shadow
                            // until the cursor is actually inside the
                            // timeline — otherwise the user would see a
                            // ghost at midnight before they've even
                            // dragged into the grid.
                            if let s = dragState, !(s.wasAllDay && s.cursorY <= 0) {
                                let snappedY = yFromTime(s.snappedStart)
                                let height = max(minItemHeight, CGFloat(s.duration / 3600.0) * hourHeight)
                                shadowView(state: s, width: contentWidth, height: height)
                                    .frame(width: contentWidth, height: height, alignment: .topLeading)
                                    .offset(x: contentOriginX, y: snappedY)
                                    .zIndex(50)
                            }

                            if Calendar.current.isDate(date, inSameDayAs: Date()) {
                                currentTimeLine
                                    .zIndex(30)
                            }
                        }
                    }
                    .frame(height: totalHeight)
                    // Accept tasks dragged in from the Tasks component
                    // (which broadcasts a DraggableTaskInfo). The
                    // DropDelegate variant fires `dropUpdated` continuously
                    // while the cursor is over the timeline, letting us
                    // drive the same shadow renderer used for in-timeline
                    // drags so the snapped target time tracks the finger
                    // live. Attached on the outer .frame() so the drop
                    // area matches the full visual timeline height.
                    // Modern Transferable → drop-only path. Reliably
                    // commits the task drop at the dropped Y. Pairs with
                    // the legacy delegate below for live hover tracking
                    // (the modern API doesn't expose continuous location).
                    .dropDestination(for: DraggableTaskInfo.self) { items, location in
                        return handleExternalTaskDrop(items: items, atY: location.y)
                    }
                    // Legacy delegate purely for the live snapped-time
                    // shadow. validateDrop always accepts so dropEntered /
                    // dropUpdated fire regardless of how the bridged
                    // NSItemProvider advertises its types. If the payload
                    // can't be decoded the delegate just no-ops.
                    .onDrop(
                        of: [UTType.json, UTType.data, UTType.text],
                        delegate: TimelineExternalTaskDropDelegate(
                            dragState: $dragState,
                            externalInfo: $externalDragInfo,
                            onLocationChanged: { info, y in
                                updateExternalDragState(info: info, atY: y)
                            },
                            onPerformDrop: { _, _ in
                                // Commit is owned by .dropDestination
                                // above. Returning false here lets the
                                // modern handler take over.
                                return false
                            }
                        )
                    )
                    // The all-day rows above use this name to report the
                    // drag cursor in timeline-local coordinates so we can
                    // map cursor Y → snapped time directly.
                    .coordinateSpace(name: timelineCoordSpace)
                }
            }
            .onAppear {
                startCurrentTimeTimer()
                scrollToCurrentHour(proxy: proxy)
            }
            .onDisappear {
                stopCurrentTimeTimer()
            }
        }
    }

    // MARK: - Hour grid

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                // Top-align the HStack so the label sits at the same Y as
                // the hour line, then nudge the label up half its height
                // so the line passes through the text's vertical centre
                // — that's how Google Calendar renders hour labels.
                HStack(alignment: .top, spacing: 0) {
                    Text(formatHour(hour))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: timeColumnWidth, alignment: .leading)
                        .offset(y: -6)

                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 1)
                        Spacer()
                        Rectangle()
                            .fill(Color(.systemGray6))
                            .frame(height: 0.5)
                            .opacity(0.6)
                        Spacer()
                    }
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }

            HStack(alignment: .top, spacing: 0) {
                Text(formatHour(endHour))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: timeColumnWidth, alignment: .leading)
                    .offset(y: -6)

                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 1)
            }
            .frame(height: 20, alignment: .top)
        }
    }

    // MARK: - Items overlay

    private func itemsLayer(contentOriginX: CGFloat, contentWidth: CGFloat) -> some View {
        let items = timedItems()
        let columns = columnAssignment(items: items)

        return ForEach(items) { item in
            let assignment = columns[item.id] ?? (col: 0, total: 1)
            let columnW = max(0, contentWidth / CGFloat(assignment.total))
            let baseX = contentOriginX + CGFloat(assignment.col) * columnW
            let baseY = yFromTime(item.startTime)
            let height = max(minItemHeight, CGFloat(item.duration / 3600.0) * hourHeight)

            // While this item is being dragged, follow the finger directly
            // (continuous), independent of the snap grid that the shadow
            // shows. Other items stay anchored at their saved positions.
            let isDragging = dragState?.itemId == item.id
            let renderedY = isDragging
                ? baseY + (dragState?.translation ?? 0)
                : baseY

            itemView(item: item)
                .frame(width: max(0, columnW - 2), height: height, alignment: .topLeading)
                .opacity(isDragging ? 0.85 : 1.0)
                .offset(x: baseX, y: renderedY)
                .zIndex(isDragging ? 40 : 10)
                .gesture(dragGesture(item: item, baseY: baseY))
        }
    }

    @ViewBuilder
    private func itemView(item: TimedItem) -> some View {
        switch item.kind {
        case .event(let event, let isPersonal):
            eventCard(event: event, isPersonal: isPersonal)
        case .task(let task, let listId, let isPersonal):
            taskCard(task: task, listId: listId, isPersonal: isPersonal)
        }
    }

    private func eventCard(event: GoogleCalendarEvent, isPersonal: Bool) -> some View {
        let bg = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.8))
                Text(event.summary)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            if let start = event.startTime {
                Text(timeLabel(for: start))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(bg))
        .contentShape(Rectangle())
        .onTapGesture { onEventTap?(event) }
    }

    private func taskCard(task: GoogleTask, listId: String, isPersonal: Bool) -> some View {
        let accent = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        let isSelected = selectedTaskIds.contains(task.id)
        return HStack(spacing: 6) {
            if isBulkEditMode {
                Button { onTaskSelectionToggle?(task) } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.callout)
                        .foregroundColor(isSelected ? accent : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button { onTaskToggle?(task, listId) } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.callout)
                        .foregroundColor(task.isCompleted ? accent : .secondary)
                }
                .buttonStyle(.plain)
            }

            Text(task.title)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(task.isCompleted ? .secondary : .primary)
                .strikethrough(task.isCompleted)
                .lineLimit(2)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(accent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(accent.opacity(0.4), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onTaskTap?(task, listId) }
    }

    // MARK: - Drag

    private func dragGesture(item: TimedItem, baseY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let translation = value.translation.height
                let snappedStart = snappedStartTime(forBaseY: baseY, translation: translation, duration: item.duration)
                if dragState?.itemId == item.id {
                    dragState?.translation = translation
                    dragState?.snappedStart = snappedStart
                } else {
                    dragState = DragState(
                        itemId: item.id,
                        originalStart: item.startTime,
                        duration: item.duration,
                        kind: item.kind,
                        wasAllDay: false,
                        translation: translation,
                        snappedStart: snappedStart,
                        cursorY: baseY + translation
                    )
                }
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

    /// Drag gesture for an all-day row. Reports the cursor's Y in the
    /// timeline's named coordinate space, so the shadow tracks where the
    /// dropped item would actually land. Picks a default duration since
    /// all-day items don't carry one (60 min for events, 30 min for tasks).
    private func allDayDragGesture(itemId: String, kind: ItemKind, defaultDuration: TimeInterval) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(timelineCoordSpace))
            .onChanged { value in
                let cursorY = value.location.y
                let snappedStart = snappedTimeFromAbsoluteY(max(0, cursorY), duration: defaultDuration)
                if dragState?.itemId == itemId {
                    dragState?.snappedStart = snappedStart
                    dragState?.cursorY = cursorY
                } else {
                    dragState = DragState(
                        itemId: itemId,
                        originalStart: Calendar.current.startOfDay(for: date),
                        duration: defaultDuration,
                        kind: kind,
                        wasAllDay: true,
                        translation: 0,
                        snappedStart: snappedStart,
                        cursorY: cursorY
                    )
                }
            }
            .onEnded { value in
                guard let s = dragState, s.itemId == itemId else {
                    dragState = nil
                    return
                }
                // Only commit if the user actually dragged into the timeline
                // — a tiny wiggle still in the all-day section shouldn't
                // accidentally schedule the item at midnight.
                if value.location.y > 0 {
                    commitDrag(state: s)
                }
                dragState = nil
            }
    }

    private func snappedTimeFromAbsoluteY(_ y: CGFloat, duration: TimeInterval) -> Date {
        let minutesPerPoint = 60.0 / Double(hourHeight)
        let rawMinutes = Double(y) * minutesPerPoint
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

    /// Translate (item base Y + finger drag) → snapped target start time.
    private func snappedStartTime(forBaseY baseY: CGFloat, translation: CGFloat, duration: TimeInterval) -> Date {
        // Where the top of the item would land in raw Y.
        let proposedY = baseY + translation
        // Convert Y → minutes-since-startHour, snap, clamp so the item
        // stays inside [startHour, endHour].
        let minutesPerPoint = 60.0 / Double(hourHeight)
        let rawMinutes = Double(proposedY) * minutesPerPoint
        let snapped = (Int(rawMinutes.rounded()) / snapMinutes) * snapMinutes
        let durationMinutes = Int(duration / 60)
        let maxStart = (endHour - startHour) * 60 - max(durationMinutes, snapMinutes)
        let clamped = max(0, min(snapped, maxStart))
        let totalMinutesFromStartHour = clamped
        return Calendar.current.date(
            bySettingHour: startHour + totalMinutesFromStartHour / 60,
            minute: totalMinutesFromStartHour % 60,
            second: 0,
            of: date
        ) ?? date
    }

    /// Builds (or refreshes) `dragState` for an external task drag while
    /// the cursor is over the timeline. Re-uses the same `DragState` model
    /// that in-timeline drags use, so the existing shadow renderer paints
    /// the ghost + time label without any branching.
    @MainActor
    private func updateExternalDragState(info: DraggableTaskInfo, atY y: CGFloat) {
        let kind: GoogleAuthManager.AccountKind = info.accountKind == "personal" ? .personal : .professional
        let dict = kind == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
        guard let task = dict[info.listId]?.first(where: { $0.id == info.taskId }) else { return }

        // Preserve prior duration when present; default to 30 min for tasks
        // that have no time window yet.
        let priorWindow = timeWindowManager.getTimeWindow(for: task.id)
        let duration: TimeInterval
        if let priorWindow, !priorWindow.isAllDay {
            duration = max(60, priorWindow.endTime.timeIntervalSince(priorWindow.startTime))
        } else {
            duration = 30 * 60
        }

        let snappedStart = snappedTimeFromAbsoluteY(max(0, y), duration: duration)
        let isPersonal = kind == .personal
        let internalId = "external_task_\(task.id)"

        if dragState?.itemId == internalId {
            dragState?.snappedStart = snappedStart
            dragState?.cursorY = y
        } else {
            dragState = DragState(
                itemId: internalId,
                originalStart: snappedStart,
                duration: duration,
                kind: .task(task, listId: info.listId, isPersonal: isPersonal),
                wasAllDay: false,
                translation: 0,
                snappedStart: snappedStart,
                cursorY: y
            )
        }
    }

    /// Handles a drop of `DraggableTaskInfo` payloads from the Tasks
    /// component onto the timeline. Converts the drop Y coordinate (in
    /// the GeometryReader's local space) into a snapped time via the same
    /// math used for in-timeline drags, writes a TaskTimeWindow, and
    /// updates the task's `due` so it lands on this view's day. Existing
    /// duration is preserved if the task already had a non-all-day
    /// window; otherwise defaults to 30 minutes.
    @MainActor
    private func handleExternalTaskDrop(items: [DraggableTaskInfo], atY y: CGFloat) -> Bool {
        guard !items.isEmpty else { return false }
        var didCommit = false

        for info in items {
            guard let resolved = TaskScheduler.resolveTask(info) else { continue }
            let duration = TaskScheduler.resolvedDuration(forTaskId: resolved.task.id)
            let snappedStart = snappedTimeFromAbsoluteY(max(0, y), duration: duration)
            TaskScheduler.scheduleTimed(
                task: resolved.task,
                listId: info.listId,
                kind: resolved.kind,
                start: snappedStart,
                duration: duration
            )
            didCommit = true
        }

        return didCommit
    }

    private func commitDrag(state: DragState) {
        // Skip if nothing actually changed (sub-snap drag).
        if state.snappedStart == state.originalStart { return }

        // Hold the rendered item at the new position until the data flow
        // catches up, then drop the override. Three seconds is plenty for
        // the Google Calendar PATCH; tasks update synchronously and would
        // be fine without this, but the override is harmless there.
        let internalId = state.itemId
        pendingStarts[internalId] = state.snappedStart
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            pendingStarts.removeValue(forKey: internalId)
        }

        switch state.kind {
        case .event(let event, _):
            Task { @MainActor in
                if state.wasAllDay {
                    // Convert all-day → timed at the dropped position. Use
                    // the explicit `scheduleEvent` so duration is the new
                    // default (60 min) rather than the all-day 24-hour span.
                    await calendarVM.scheduleEvent(event, startTime: state.snappedStart, duration: state.duration)
                } else {
                    await calendarVM.moveEventToDateTime(event, to: state.snappedStart)
                }
            }
        case .task(let task, _, _):
            // Save against the *real* Google Task id — `state.itemId` is
            // our internal "task_<id>" prefix, which would never round-trip
            // back through `getTimeWindow(for:)` and was the reason drops
            // appeared to revert. For all-day → timed conversion this same
            // call writes a fresh non-all-day window (the manager replaces
            // any prior all-day window on save).
            let newEnd = state.snappedStart.addingTimeInterval(state.duration)
            timeWindowManager.saveTimeWindow(
                taskId: task.id,
                startTime: state.snappedStart,
                endTime: newEnd,
                isAllDay: false
            )
        }
    }

    // MARK: - Shadow view

    /// Floating time label anchored to the time-column area at the
    /// snapped landing time. Lives outside `shadowView` so its position
    /// is decoupled from the shadow rectangle's frame — keeps the time
    /// readable even when the cursor or system drag preview overlaps the
    /// shadow.
    private func snappedTimePill(time: Date, isPersonal: Bool) -> some View {
        let accent = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        return Text(timeLabel(for: time))
            .font(.caption.weight(.semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color(.systemBackground).opacity(0.95))
                    .overlay(Capsule().stroke(accent.opacity(0.85), lineWidth: 1.5))
            )
    }

    private func shadowView(state: DragState, width: CGFloat, height: CGFloat) -> some View {
        let isPersonal: Bool = {
            switch state.kind {
            case .event(_, let p): return p
            case .task(_, _, let p): return p
            }
        }()
        let accent = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor

        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(accent.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accent.opacity(0.18))
                )

            Text(timeLabel(for: state.snappedStart))
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color(.systemBackground).opacity(0.92))
                        .overlay(Capsule().stroke(accent.opacity(0.6), lineWidth: 1))
                )
                .padding(4)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Now indicator

    private var currentTimeLine: some View {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: currentTime)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let yOffset = CGFloat(hour - startHour) * hourHeight + CGFloat(minute) * (hourHeight / 60.0)

        return HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .offset(x: timeColumnWidth - 3)
            Rectangle()
                .fill(Color.red)
                .frame(height: 1.5)
                .offset(x: timeColumnWidth + 1)
        }
        .offset(y: yOffset)
        .opacity(hour >= startHour && hour <= endHour ? 1 : 0)
    }

    // MARK: - All-day section

    private var hasAllDayEvents: Bool { events.contains { $0.isAllDay } }
    private var hasAllDayTasks: Bool {
        let dateAllDay = { (id: String) -> Bool in
            guard let win = self.timeWindowManager.getTimeWindow(for: id) else { return true }
            return win.isAllDay
        }
        for tasks in personalTasks.values {
            if tasks.contains(where: { dateAllDay($0.id) && taskIsOnThisDate($0) }) { return true }
        }
        for tasks in professionalTasks.values {
            if tasks.contains(where: { dateAllDay($0.id) && taskIsOnThisDate($0) }) { return true }
        }
        return false
    }

    private var allDaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(events.filter { $0.isAllDay }, id: \.id) { event in
                let isPersonal = event.ownerAccountKind == .personal
                let bg = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
                let id = "event_\(event.id)"
                let isDragging = dragState?.itemId == id
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                    Text(event.summary)
                        .font(.callout)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(bg))
                .opacity(isDragging ? 0.5 : 1.0)
                .contentShape(Rectangle())
                .onTapGesture { onEventTap?(event) }
                .gesture(allDayDragGesture(
                    itemId: id,
                    kind: .event(event, isPersonal: isPersonal),
                    defaultDuration: defaultEventDuration
                ))
            }
            ForEach(allDayTaskRows(), id: \.task.id) { row in
                let accent = row.isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
                let id = "task_\(row.task.id)"
                let isDragging = dragState?.itemId == id
                HStack(spacing: 6) {
                    Button { onTaskToggle?(row.task, row.listId) } label: {
                        Image(systemName: row.task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(row.task.isCompleted ? accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    Text(row.task.title)
                        .font(.callout)
                        .strikethrough(row.task.isCompleted)
                        .foregroundColor(row.task.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accent.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(accent.opacity(0.4), lineWidth: 1)
                        )
                )
                .opacity(isDragging ? 0.5 : 1.0)
                .contentShape(Rectangle())
                .onTapGesture { onTaskTap?(row.task, row.listId) }
                .gesture(allDayDragGesture(
                    itemId: id,
                    kind: .task(row.task, listId: row.listId, isPersonal: row.isPersonal),
                    defaultDuration: defaultTaskDuration
                ))
            }
        }
        .padding(.horizontal, 4)
    }

    private struct AllDayTaskRow {
        let task: GoogleTask
        let listId: String
        let isPersonal: Bool
    }

    private func allDayTaskRows() -> [AllDayTaskRow] {
        var rows: [AllDayTaskRow] = []
        for (listId, tasks) in personalTasks {
            for task in tasks where taskIsOnThisDate(task) && taskIsAllDay(task) {
                rows.append(AllDayTaskRow(task: task, listId: listId, isPersonal: true))
            }
        }
        for (listId, tasks) in professionalTasks {
            for task in tasks where taskIsOnThisDate(task) && taskIsAllDay(task) {
                rows.append(AllDayTaskRow(task: task, listId: listId, isPersonal: false))
            }
        }
        return rows
    }

    private func taskIsAllDay(_ task: GoogleTask) -> Bool {
        guard let win = timeWindowManager.getTimeWindow(for: task.id) else { return true }
        return win.isAllDay
    }

    private func taskIsOnThisDate(_ task: GoogleTask) -> Bool {
        let cal = Calendar.current
        if let win = timeWindowManager.getTimeWindow(for: task.id), !win.isAllDay {
            return cal.isDate(win.startTime, inSameDayAs: date)
        }
        if let due = task.dueDate {
            return cal.isDate(due, inSameDayAs: date)
        }
        return false
    }

    // MARK: - Timed-item assembly

    private func timedItems() -> [TimedItem] {
        var result: [TimedItem] = []

        for event in events where !event.isAllDay {
            guard let start = event.startTime, let end = event.endTime,
                  Calendar.current.isDate(start, inSameDayAs: date) else { continue }
            let isPersonal = event.ownerAccountKind == .personal
            let id = "event_\(event.id)"
            let duration = end.timeIntervalSince(start)
            let effStart = pendingStarts[id] ?? start
            let effEnd = effStart.addingTimeInterval(duration)
            result.append(TimedItem(
                id: id,
                kind: .event(event, isPersonal: isPersonal),
                title: event.summary,
                startTime: effStart,
                endTime: effEnd
            ))
        }

        for (listId, tasks) in personalTasks {
            for task in tasks {
                guard let win = timeWindowManager.getTimeWindow(for: task.id),
                      !win.isAllDay,
                      Calendar.current.isDate(win.startTime, inSameDayAs: date) else { continue }
                let id = "task_\(task.id)"
                let duration = win.endTime.timeIntervalSince(win.startTime)
                let effStart = pendingStarts[id] ?? win.startTime
                let effEnd = effStart.addingTimeInterval(duration)
                result.append(TimedItem(
                    id: id,
                    kind: .task(task, listId: listId, isPersonal: true),
                    title: task.title,
                    startTime: effStart,
                    endTime: effEnd
                ))
            }
        }
        for (listId, tasks) in professionalTasks {
            for task in tasks {
                guard let win = timeWindowManager.getTimeWindow(for: task.id),
                      !win.isAllDay,
                      Calendar.current.isDate(win.startTime, inSameDayAs: date) else { continue }
                let id = "task_\(task.id)"
                let duration = win.endTime.timeIntervalSince(win.startTime)
                let effStart = pendingStarts[id] ?? win.startTime
                let effEnd = effStart.addingTimeInterval(duration)
                result.append(TimedItem(
                    id: id,
                    kind: .task(task, listId: listId, isPersonal: false),
                    title: task.title,
                    startTime: effStart,
                    endTime: effEnd
                ))
            }
        }

        return result.sorted { $0.startTime < $1.startTime }
    }

    /// Mirrors T view's `DraggableTimeboxWeekContent.laidOut` so D view and
    /// T view render overlapping items the same way: sort by start, partition
    /// into transitive-overlap groups (a new group starts when the next item
    /// begins on or after every prior end), then greedy lane-pack within
    /// each group. Items that don't overlap with anything land in their own
    /// group and get `total = 1` (full width); shared widths only kick in
    /// for items that actually collide.
    private func columnAssignment(items: [TimedItem]) -> [String: (col: Int, total: Int)] {
        let sorted = items.sorted { $0.startTime < $1.startTime }

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

        var result: [String: (col: Int, total: Int)] = [:]
        for group in groups {
            var laneEnds: [Date] = []
            var assigned: [(id: String, lane: Int)] = []
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
                assigned.append((item.id, slot))
            }
            let total = max(laneEnds.count, 1)
            for entry in assigned {
                result[entry.id] = (entry.lane, total)
            }
        }
        return result
    }

    // MARK: - Time math

    private func yFromTime(_ time: Date) -> CGFloat {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        return CGFloat(hour - startHour) * hourHeight + CGFloat(minute) * (hourHeight / 60.0)
    }

    private func formatHour(_ hour: Int) -> String {
        let normalized = hour % 24
        let display = normalized == 0 ? 12 : (normalized > 12 ? normalized - 12 : normalized)
        let suffix = normalized < 12 ? "a" : "p"
        return "\(display)\(suffix)"
    }

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

    private func scrollToCurrentHour(proxy: ScrollViewProxy) {
        guard Calendar.current.isDate(date, inSameDayAs: Date()) else { return }
        let currentHour = Calendar.current.component(.hour, from: Date())
        let target = min(max(currentHour, startHour), endHour - 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo(target, anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }
}

// MARK: - External task drop delegate

/// Bridges `NSItemProvider`-based drops onto the timeline into the same
/// `DragState`-driven shadow that in-timeline drags use. The async load
/// of the JSON payload happens once on `dropEntered`; subsequent
/// `dropUpdated` calls re-use the cached `DraggableTaskInfo` and only
/// recompute the snapped target time from the new cursor location.
private struct TimelineExternalTaskDropDelegate: DropDelegate {
    @Binding var dragState: DraggableTimeboxComponent.DragState?
    @Binding var externalInfo: DraggableTaskInfo?
    let onLocationChanged: (DraggableTaskInfo, CGFloat) -> Void
    let onPerformDrop: (DraggableTaskInfo, CGFloat) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        // Always accept so dropEntered / dropUpdated fire. The Transferable
        // bridge sometimes advertises non-obvious type identifiers; we'll
        // try to decode opportunistically inside loadPayload.
        return true
    }

    func dropEntered(info: DropInfo) {
        // If the cache is already populated (drag re-entered the timeline
        // after a brief exit), just refresh position immediately.
        if let cached = externalInfo {
            onLocationChanged(cached, info.location.y)
            return
        }
        loadPayload(from: info) { decoded, location in
            externalInfo = decoded
            onLocationChanged(decoded, location.y)
        }
    }

    /// Iterates every provider attached to the drop and tries each of its
    /// registered type identifiers until one yields JSON data we can
    /// decode into a DraggableTaskInfo. Used for the live-hover path
    /// only; the modern .dropDestination handles the actual commit.
    private func loadPayload(from info: DropInfo, completion: @escaping (DraggableTaskInfo, CGPoint) -> Void) {
        let location = info.location
        // `.item` matches everything — gets us all providers attached to
        // this drop, regardless of how the source advertised them.
        for provider in info.itemProviders(for: [UTType.item]) {
            for identifier in provider.registeredTypeIdentifiers {
                provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    guard let data,
                          let decoded = try? JSONDecoder().decode(DraggableTaskInfo.self, from: data) else { return }
                    DispatchQueue.main.async {
                        completion(decoded, location)
                    }
                }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let cached = externalInfo {
            // Synchronous refresh — keeps the shadow tightly attached to
            // the cursor without waiting on another async load.
            onLocationChanged(cached, info.location.y)
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // Cursor left the timeline area — drop the ghost. Re-entry will
        // restore it from the cache on the next `dropEntered`.
        DispatchQueue.main.async {
            dragState = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let location = info.location
        if let cached = externalInfo {
            _ = onPerformDrop(cached, location.y)
            DispatchQueue.main.async {
                dragState = nil
                externalInfo = nil
            }
            return true
        }
        // Fallback: cache wasn't populated yet (very fast drop). Try
        // loading via the same broad-UTI path used during hover.
        loadPayload(from: info) { decoded, loc in
            _ = onPerformDrop(decoded, loc.y)
            dragState = nil
            externalInfo = nil
        }
        return true
    }
}
