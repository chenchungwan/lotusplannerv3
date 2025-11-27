import SwiftUI

struct TimeboxComponent: View {
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
    
    @ObservedObject private var timeWindowManager = TaskTimeWindowManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    
    private let hourHeight: CGFloat = 100
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
        let isPersonal: Bool
        let isTask: Bool // true for task, false for event
        let item: Any // Either GoogleCalendarEvent or GoogleTask
    }
    
    let showAllDaySection: Bool
    
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
        showAllDaySection: Bool = true
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
                // Auto-scroll to current hour when viewing today
                if Calendar.current.isDate(date, inSameDayAs: Date()) {
                    let currentHour = Calendar.current.component(.hour, from: Date())
                    let targetHour = min(max(currentHour, startHour), endHour - 1)
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(targetHour, anchor: .top)
                        }
                    }
                }
            }
            .onDisappear {
                stopCurrentTimeTimer()
            }
        }
    }
    
    // MARK: - All-Day Items
    private var allDayEventsData: [(event: GoogleCalendarEvent, isPersonal: Bool)] {
        guard showAllDaySection else { return [] }
        return events
            .filter { $0.isAllDay }
            .map { event in
            let isPersonal = personalEvents.contains { $0.id == event.id }
                return (event, isPersonal)
            }
        }
        
    private var allDayTasksData: [(task: GoogleTask, listId: String, isPersonal: Bool)] {
        guard showAllDaySection else { return [] }
        let allTasks = getTasksForDate(date).filter { task in
            if let timeWindow = timeWindowManager.getTimeWindow(for: task.id) {
                return timeWindow.isAllDay
            }
            return true
        }
        
        return allTasks.map { task in
            let (listId, isPersonal) = findTaskListAndKind(for: task)
            return (task, listId, isPersonal)
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
                    .background(Color(.systemGray4))
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
                    allDayEventBlock(event: item.event, isPersonal: item.isPersonal)
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
                    allDayTaskBlock(task: item.task, listId: item.listId, isPersonal: item.isPersonal)
                }
            }
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
    
    private func allDayEventBlock(event: GoogleCalendarEvent, isPersonal: Bool) -> some View {
        let itemColor = isPersonal ? personalColor : professionalColor
        
        return HStack(spacing: 8) {
            Circle()
                .fill(itemColor)
                .frame(width: 8, height: 8)
            
            Text(event.summary)
                .font(.body)
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
    
    private func allDayTaskBlock(task: GoogleTask, listId: String, isPersonal: Bool) -> some View {
        let itemColor = isPersonal ? personalColor : professionalColor
        
        return HStack(spacing: 8) {
                    Button(action: {
                        onTaskToggle?(task, listId)
                    }) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundColor(task.isCompleted ? itemColor : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text(task.title)
                        .font(.body)
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
                    onTaskTap?(task, listId)
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
        let backgroundColor = layout.isPersonal ? personalColor : professionalColor
        
        if layout.isTask, let task = layout.item as? GoogleTask {
            // Task style matching all-day task style (light tinted background)
            let (listId, _) = findTaskListAndKind(for: task)
            let accentColor = layout.isPersonal ? personalColor : professionalColor
            
            HStack(spacing: 6) {
                // Checkmark circle button - tappable to toggle completion
                Button(action: {
                    onTaskToggle?(task, listId)
                }) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundColor(task.isCompleted ? accentColor : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Task title
                Text(task.title)
                    .font(.body)
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
                onTaskTap?(task, listId)
            }
            .offset(x: layout.xOffset, y: layout.startOffset)
            .allowsHitTesting(true)
        } else {
            // Event style (unchanged)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(layout.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(layout.height > 40 ? 3 : 2)
                }
                
                if layout.height > 40, let event = layout.item as? GoogleCalendarEvent, let startTime = event.startTime {
                    let calendar = Calendar.current
                    let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                    if let startHour = startComponents.hour, let startMinute = startComponents.minute {
                        Text("\(String(format: "%02d:%02d", startHour, startMinute))")
                            .font(.caption)
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
                .frame(width: 8, height: 8)
                .offset(x: timeColumnWidth - 4)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
                .offset(x: timeColumnWidth + 1)
        }
        .offset(y: yOffset)
        .opacity(hour >= startHour && hour <= endHour ? 1 : 0)
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
        
        // Get tasks from both personal and professional
        for (_, tasks) in personalTasks {
            allTasks.append(contentsOf: tasks)
        }
        for (_, tasks) in professionalTasks {
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
    
    private func findTaskListAndKind(for task: GoogleTask) -> (listId: String, isPersonal: Bool) {
        // Check personal tasks first
        for (listId, tasks) in personalTasks {
            if tasks.contains(where: { $0.id == task.id }) {
                return (listId, true)
            }
        }
        
        // Check professional tasks
        for (listId, tasks) in professionalTasks {
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
            if let timeWindow = timeWindowManager.getTimeWindow(for: task.id) {
                return !timeWindow.isAllDay
            }
            return false // No time window means it's all-day, so don't include here
        }
        
        // Combine events and tasks into a unified array
        var allItems: [(isTask: Bool, item: Any, startTime: Date, endTime: Date, isPersonal: Bool)] = []
        
        // Add events
        for event in timedEvents {
            guard let startTime = event.startTime, let endTime = event.endTime else { continue }
            let isPersonal = personalEvents.contains { $0.id == event.id }
            allItems.append((isTask: false, item: event, startTime: startTime, endTime: endTime, isPersonal: isPersonal))
        }
        
        // Add tasks
        for task in timedTasks {
            guard let timeWindow = timeWindowManager.getTimeWindow(for: task.id) else { continue }
            let (_, isPersonal) = findTaskListAndKind(for: task)
            allItems.append((isTask: true, item: task, startTime: timeWindow.startTime, endTime: timeWindow.endTime, isPersonal: isPersonal))
        }
        
        // Sort by start time
        allItems.sort { $0.startTime < $1.startTime }
        
        // Group overlapping items
        var itemGroups: [[(isTask: Bool, item: Any, startTime: Date, endTime: Date, isPersonal: Bool)]] = []
        
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
                let endComponents = calendar.dateComponents([.hour, .minute], from: item.endTime)
                
                let startHour = startComponents.hour ?? 0
                let startMinute = startComponents.minute ?? 0
                let endHour = endComponents.hour ?? 23
                let endMinute = endComponents.minute ?? 59
                
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
                    isPersonal: item.isPersonal,
                    isTask: item.isTask,
                    item: item.item
                )
                
                layouts.append(layout)
            }
        }
        
        return layouts
    }
}

