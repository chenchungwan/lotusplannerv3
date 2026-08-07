import SwiftUI

struct TimeboxComponent: View {
    let date: Date
    let events: [GoogleCalendarEvent]
    let account1Events: [GoogleCalendarEvent]
    let account2Events: [GoogleCalendarEvent]
    let account1Tasks: [String: [GoogleTask]]
    let account2Tasks: [String: [GoogleTask]]
    let account1Color: Color
    let account2Color: Color
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    let onTaskTap: ((GoogleTask, String) -> Void)?
    let onTaskToggle: ((GoogleTask, String) -> Void)?
    let isBulkEditMode: Bool
    let selectedTaskIds: Set<String>
    let onTaskSelectionToggle: ((GoogleTask) -> Void)?

    @ObservedObject private var timeWindowManager = TaskTimeWindowManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    
    private let hourHeight: CGFloat = 60
    private let startHour = 0
    private let endHour = 24
    private let timeColumnWidth: CGFloat = 28
    
    // MARK: - Unified Item Layout Model
    struct TimelineItemLayout {
        let id: String
        let title: String
        let startOffset: CGFloat
        let height: CGFloat
        let width: CGFloat
        let xOffset: CGFloat
        let isAccount1: Bool
        let isTask: Bool // true for task, false for event
        let item: Any // Either GoogleCalendarEvent or GoogleTask
    }
    
    let showAllDaySection: Bool
    
    init(
        date: Date,
        events: [GoogleCalendarEvent],
        account1Events: [GoogleCalendarEvent],
        account2Events: [GoogleCalendarEvent],
        account1Tasks: [String: [GoogleTask]] = [:],
        account2Tasks: [String: [GoogleTask]] = [:],
        account1Color: Color,
        account2Color: Color,
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
        self.account1Events = account1Events
        self.account2Events = account2Events
        self.account1Tasks = account1Tasks
        self.account2Tasks = account2Tasks
        self.account1Color = account1Color
        self.account2Color = account2Color
        self.onEventTap = onEventTap
        self.onTaskTap = onTaskTap
        self.onTaskToggle = onTaskToggle
        self.showAllDaySection = showAllDaySection
        self.isBulkEditMode = isBulkEditMode
        self.selectedTaskIds = selectedTaskIds
        self.onTaskSelectionToggle = onTaskSelectionToggle
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    // All-day items section (events and tasks) - only show if enabled
                    if showAllDaySection && (hasAllDayEvents || hasAllDayTasks) {
                        allDayItemsSection
                            .padding(.bottom, 8)
                    }
                    
                    // Main timeline with hour grid, events, and tasks
                    let totalHeight = CGFloat(endHour - startHour) * hourHeight + 20
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            // Background grid
                            VStack(spacing: 0) {
                                ForEach(startHour..<endHour, id: \.self) { hour in
                                    timeSlot(hour: hour)
                                        .frame(height: hourHeight)
                                        .id(hour)
                                }
                                
                                // Final 12a line at the end of the day
                                HStack(spacing: 0) {
                                    Text(formatHour(endHour))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(width: timeColumnWidth, alignment: .leading)
                                    
                                    Rectangle()
                                        .fill(Color(.systemGray5))
                                        .frame(height: 1)
                                }
                                .frame(height: 20)
                            }
                            
                            // Combined events and tasks overlay
                            let allLayouts = calculateAllLayouts(width: geometry.size.width - timeColumnWidth - 1, offsetX: timeColumnWidth + 1)
                            ForEach(allLayouts, id: \.id) { layout in
                                timelineItemView(layout: layout)
                                    .zIndex(10)
                            }
                            
                            // Current time line (only show if date is today)
                            if Calendar.current.isDate(date, inSameDayAs: Date()) {
                                currentTimeLine
                            }
                        }
                    }
                    .frame(height: totalHeight)
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
    
    // MARK: - All-Day Items
    private var allDayEventsData: [(event: GoogleCalendarEvent, isAccount1: Bool)] {
        guard showAllDaySection else { return [] }
        return events
            .filter { $0.isAllDay }
            .map { event in
            let isAccount1 = event.ownerAccountKind == .account1
                return (event, isAccount1)
            }
        }
        
    private var allDayTasksData: [(task: GoogleTask, listId: String, isAccount1: Bool)] {
        guard showAllDaySection else { return [] }
        let allTasks = getTasksForDate(date).filter { task in
            if let timeWindow = timeWindowManager.getTimeWindow(for: task.id) {
                return timeWindow.isAllDay
            }
            return true
        }
        
        return allTasks.map { task in
            let (listId, isAccount1) = findTaskListAndKind(for: task)
            return (task, listId, isAccount1)
        }
    }
    
    private var hasAllDayEvents: Bool {
        showAllDaySection && !allDayEventsData.isEmpty
    }
    
    private var hasAllDayTasks: Bool {
        showAllDaySection && !allDayTasksData.isEmpty
    }
    
    private var allDayItemsSection: some View {
        VStack(spacing: 0) {
            if hasAllDayEvents {
                allDayEventsRow
            }
            
            if hasAllDayTasks {
                allDayTasksRow
            }
            
            if hasAllDayEvents || hasAllDayTasks {
                Divider()
            }
        }
    }
    
    private var allDayEventsRow: some View {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: timeColumnWidth + 1)
                
                VStack(spacing: 4) {
                ForEach(allDayEventsData, id: \.event.id) { item in
                    allDayEventBlock(event: item.event, isAccount1: item.isAccount1)
                    }
                }
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
    }
    
    private var allDayTasksRow: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: timeColumnWidth + 1)
            
            VStack(spacing: 4) {
                ForEach(allDayTasksData, id: \.task.id) { item in
                    allDayTaskBlock(task: item.task, listId: item.listId, isAccount1: item.isAccount1)
                }
            }
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
    
    private func allDayEventBlock(event: GoogleCalendarEvent, isAccount1: Bool) -> some View {
        let itemColor = isAccount1 ? account1Color : account2Color

        return HStack(spacing: 8) {
            Circle()
                .fill(itemColor)
                .frame(width: 6, height: 6)

            Text(event.summary)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(itemColor.opacity(0.1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onEventTap?(event)
        }
    }
    
    private func allDayTaskBlock(task: GoogleTask, listId: String, isAccount1: Bool) -> some View {
        let itemColor = isAccount1 ? account1Color : account2Color
        let isSelected = selectedTaskIds.contains(task.id)

        return HStack(spacing: 8) {
                    if isBulkEditMode {
                        // Bulk edit selection checkbox
                        Button(action: {
                            onTaskSelectionToggle?(task)
                        }) {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .font(.callout)
                                .foregroundColor(isSelected ? .accentColor : .secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // Normal completion checkbox
                        Button(action: {
                            onTaskToggle?(task, listId)
                        }) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.callout)
                                .foregroundColor(task.isCompleted ? itemColor : .secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Text(task.title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(itemColor.opacity(0.1))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if isBulkEditMode {
                        onTaskSelectionToggle?(task)
                    } else {
                        onTaskTap?(task, listId)
                    }
        }
    }
    
    private func dueDateTag(for task: GoogleTask, accentColor: Color) -> (text: String, textColor: Color, backgroundColor: Color)? {
        // Only show due date tag for incomplete tasks
        if task.isCompleted {
            return nil
        }
        
        guard let dueDate = task.dueDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: dueDate)
        
        if calendar.isDate(dueDay, inSameDayAs: today) {
            return ("Today", .white, accentColor)
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                  calendar.isDate(dueDay, inSameDayAs: tomorrow) {
            return ("Tomorrow", .white, .cyan)
        } else if dueDay < today {
            return ("Overdue", .white, .red)
        } else {
            // Future date
            return (Self.dueDateFormatter.string(from: dueDate), .primary, Color(.systemGray5))
        }
    }

    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()

    // MARK: - Timeline Views
    private func timeSlot(hour: Int) -> some View {
        HStack(spacing: 0) {
            VStack {
                Text(formatHour(hour))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: timeColumnWidth, alignment: .leading)
                Spacer()
            }
            
            Rectangle()
                .fill(Color.clear)
                .frame(height: hourHeight - 1)
                .overlay(
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .frame(height: 0.5)
                        .offset(y: hourHeight / 2)
                )
                .overlay(
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 1)
                        .offset(y: -0.5),
                    alignment: .top
                )
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        if hour == endHour { return "12a" }
        let normalizedHour = ((hour % 24) + 24) % 24
        let date = Calendar.current.date(bySettingHour: normalizedHour, minute: 0, second: 0, of: Date()) ?? Date()
        let timeString = Self.hourFormatter.string(from: date).lowercased()
        // Remove "m" from "am" and "pm"
        return timeString.replacingOccurrences(of: "am", with: "a").replacingOccurrences(of: "pm", with: "p")
    }
    
    @ViewBuilder
    private func timelineItemView(layout: TimelineItemLayout) -> some View {
        let backgroundColor = layout.isAccount1 ? account1Color : account2Color
        
        if layout.isTask, let task = layout.item as? GoogleTask {
            // Task style matching all-day task style (light tinted background)
            let (listId, _) = findTaskListAndKind(for: task)
            let accentColor = layout.isAccount1 ? account1Color : account2Color
            let isSelected = selectedTaskIds.contains(task.id)

            HStack(spacing: 6) {
                if isBulkEditMode {
                    // Bulk edit selection checkbox
                    Button(action: {
                        onTaskSelectionToggle?(task)
                    }) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.callout)
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Normal completion checkbox
                    Button(action: {
                        onTaskToggle?(task, listId)
                    }) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.callout)
                            .foregroundColor(task.isCompleted ? accentColor : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Task title
                Text(task.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(layout.height > 30 ? 2 : 1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(width: layout.width, height: layout.height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(accentColor.opacity(0.1))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if isBulkEditMode {
                    onTaskSelectionToggle?(task)
                } else {
                    onTaskTap?(task, listId)
                }
            }
            .onDrag {
                let kind: GoogleAuthManager.AccountKind = layout.isAccount1 ? .account1 : .account2
                let json: [String: String] = ["type": "task", "id": task.id, "listId": listId, "accountKind": kind.rawValue]
                let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
                return NSItemProvider(object: (String(data: data, encoding: .utf8) ?? "") as NSString)
            }
            .offset(x: layout.xOffset, y: layout.startOffset)
            .allowsHitTesting(true)
        } else {
            // Event style
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.8))

                    Text(layout.title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(layout.height > 24 ? 2 : 1)
                }

                if layout.height > 24, let event = layout.item as? GoogleCalendarEvent, let startTime = event.startTime {
                    let calendar = Calendar.current
                    let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                    if let startHour = startComponents.hour, let startMinute = startComponents.minute {
                        Text("\(String(format: "%02d:%02d", startHour, startMinute))")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(width: layout.width, height: layout.height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if let event = layout.item as? GoogleCalendarEvent {
                    onEventTap?(event)
                }
            }
            .onDrag {
                if let event = layout.item as? GoogleCalendarEvent {
                    let kind: GoogleAuthManager.AccountKind = layout.isAccount1 ? .account1 : .account2
                    let json: [String: String] = ["type": "event", "id": event.id, "accountKind": kind.rawValue, "calendarId": event.calendarId ?? "primary"]
                    let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
                    return NSItemProvider(object: (String(data: data, encoding: .utf8) ?? "") as NSString)
                }
                return NSItemProvider()
            }
            .offset(x: layout.xOffset, y: layout.startOffset)
            .allowsHitTesting(true)
        }
    }
    
    private var currentTimeLine: some View {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
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
    
    /// Scrolls so the current-time redline is visible on first render. Only
    /// meaningful when viewing today. We fire the scroll twice with growing
    /// delays because on iPad the outer ScrollView's content layout isn't
    /// finished when `.onAppear` first runs — a synchronous `scrollTo` at
    /// that point silently no-ops because the target `.id(hour)` view
    /// doesn't have a position yet. The two-shot approach covers both the
    /// quick iPhone case and the slower iPad layout pass.
    private func scrollToCurrentHour(proxy: ScrollViewProxy) {
        guard Calendar.current.isDate(date, inSameDayAs: Date()) else { return }
        let currentHour = Calendar.current.component(.hour, from: Date())
        let targetHour = min(max(currentHour, startHour), endHour - 1)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo(targetHour, anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(targetHour, anchor: .top)
            }
        }
    }

    private func startCurrentTimeTimer() {
        currentTimeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func stopCurrentTimeTimer() {
        currentTimeTimer?.invalidate()
        currentTimeTimer = nil
    }
    
    // MARK: - Helper Methods
    private func getTasksForDate(_ date: Date) -> [GoogleTask] {
        let calendar = Calendar.current
        var allTasks: [GoogleTask] = []
        
        // Get tasks from both account 1 and account 2
        for (_, tasks) in account1Tasks {
            allTasks.append(contentsOf: tasks)
        }
        for (_, tasks) in account2Tasks {
            allTasks.append(contentsOf: tasks)
        }
        
        // Filter out completed tasks if hideCompletedTasks is enabled
        if appPrefs.hideCompletedTasks {
            allTasks = allTasks.filter { !$0.isCompleted }
        }
        
        // Filter tasks for the given date
        return allTasks.filter { task in
            // For completed tasks, show on completion date
            if task.isCompleted {
                guard let completionDate = task.completionDate else { return false }
                return calendar.isDate(completionDate, inSameDayAs: date)
            }
            
            // For incomplete tasks, show on due date
            guard let dueDate = task.dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: date)
        }
    }
    
    private func findTaskListAndKind(for task: GoogleTask) -> (listId: String, isAccount1: Bool) {
        // Check account 1 tasks first
        for (listId, tasks) in account1Tasks {
            if tasks.contains(where: { $0.id == task.id }) {
                return (listId, true)
            }
        }
        
        // Check account 2 tasks
        for (listId, tasks) in account2Tasks {
            if tasks.contains(where: { $0.id == task.id }) {
                return (listId, false)
            }
        }
        
        // Default fallback
        return ("", true)
    }
    
    // MARK: - Layout Calculation
    private func calculateAllLayouts(width: CGFloat, offsetX: CGFloat) -> [TimelineItemLayout] {
        var layouts: [TimelineItemLayout] = []
        let calendar = Calendar.current
        
        // Get timed events (non all-day)
        let timedEvents = events.filter { !$0.isAllDay }
        
        // Get timed tasks (tasks with time windows that are not all-day)
        let tasks = getTasksForDate(date)
        let timedTasks = tasks.filter { task in
            // First check: task must have a specific due time (not all-day format)
            guard task.hasSpecificDueTime else { return false }

            // Second check: task must have a time window that's not marked as all-day
            if let timeWindow = timeWindowManager.getTimeWindow(for: task.id) {
                return !timeWindow.isAllDay
            }
            return false // No time window means it's all-day, so don't include here
        }
        
        // Combine events and tasks into a unified array
        var allItems: [(isTask: Bool, item: Any, startTime: Date, endTime: Date, isAccount1: Bool)] = []
        
        // Add events
        for event in timedEvents {
            guard let startTime = event.startTime, let endTime = event.endTime else { continue }
            let isAccount1 = event.ownerAccountKind == .account1
            allItems.append((isTask: false, item: event, startTime: startTime, endTime: endTime, isAccount1: isAccount1))
        }
        
        // Add tasks
        for task in timedTasks {
            guard let timeWindow = timeWindowManager.getTimeWindow(for: task.id) else { continue }
            let (_, isAccount1) = findTaskListAndKind(for: task)
            allItems.append((isTask: true, item: task, startTime: timeWindow.startTime, endTime: timeWindow.endTime, isAccount1: isAccount1))
        }
        
        // Sort by start time
        allItems.sort { $0.startTime < $1.startTime }
        
        // Group overlapping items
        var itemGroups: [[(isTask: Bool, item: Any, startTime: Date, endTime: Date, isAccount1: Bool)]] = []
        
        for item in allItems {
            var addedToGroup = false
            for groupIndex in 0..<itemGroups.count {
                let group = itemGroups[groupIndex]
                let overlapsWithGroup = group.contains { existingItem in
                    return item.startTime < existingItem.endTime && item.endTime > existingItem.startTime
                }
                
                if overlapsWithGroup {
                    itemGroups[groupIndex].append(item)
                    addedToGroup = true
                    break
                }
            }
            
            if !addedToGroup {
                itemGroups.append([item])
            }
        }
        
        // Calculate layouts for each group
        for group in itemGroups {
            let numColumns = group.count
            let columnWidth = width / CGFloat(numColumns)
            
            for (index, item) in group.enumerated() {
                let startComponents = calendar.dateComponents([.hour, .minute], from: item.startTime)
                let startHour = startComponents.hour ?? 0
                let startMinute = startComponents.minute ?? 0
                
                let startOffset = CGFloat(startHour - self.startHour) * hourHeight +
                                 CGFloat(startMinute) * (hourHeight / 60.0)
                
                let duration = item.endTime.timeIntervalSince(item.startTime)
                let height = max(30.0, CGFloat(duration / 3600.0) * hourHeight)
                
                let layout = TimelineItemLayout(
                    id: item.isTask ? (item.item as! GoogleTask).id : (item.item as! GoogleCalendarEvent).id,
                    title: item.isTask ? (item.item as! GoogleTask).title : (item.item as! GoogleCalendarEvent).summary,
                    startOffset: startOffset,
                    height: height,
                    width: columnWidth - 4,
                    xOffset: offsetX + CGFloat(index) * columnWidth + 2,
                    isAccount1: item.isAccount1,
                    isTask: item.isTask,
                    item: item.item
                )
                
                layouts.append(layout)
            }
        }
        
        return layouts
    }
}
