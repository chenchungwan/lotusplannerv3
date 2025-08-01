import SwiftUI

struct WeekTimelineComponent: View {
    // MARK: - Properties
    let currentDate: Date
    let weekEvents: [Date: [GoogleCalendarEvent]]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let personalTasks: [GoogleTask]
    let professionalTasks: [GoogleTask]
    let hideCompletedTasks: Bool
    let initialUntimedRows: Int
    
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    let onDayTap: ((Date) -> Void)?
    
    // MARK: - State
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    
    // MARK: - Constants
    private let hourHeight: CGFloat = 80
    private let defaultStartHour = 6
    private let defaultEndHour = 22
    private let timeColumnWidth: CGFloat = 50
    private let dayHeaderHeight: CGFloat = 60
    private let allDayEventHeight: CGFloat = 24
    
    // MARK: - Initializer
    init(currentDate: Date, weekEvents: [Date: [GoogleCalendarEvent]], personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color, personalTasks: [GoogleTask] = [], professionalTasks: [GoogleTask] = [], hideCompletedTasks: Bool = false, initialUntimedRows: Int = 0, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil, onDayTap: ((Date) -> Void)? = nil) {
        self.currentDate = currentDate
        self.weekEvents = weekEvents
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.personalTasks = personalTasks
        self.professionalTasks = professionalTasks
        self.hideCompletedTasks = hideCompletedTasks
        self.initialUntimedRows = initialUntimedRows
        self.onEventTap = onEventTap
        self.onDayTap = onDayTap
    }
    
    // MARK: - Data Models
    struct EventLayout {
        let event: GoogleCalendarEvent
        let startOffset: CGFloat
        let height: CGFloat
        let width: CGFloat
        let xOffset: CGFloat
        let isPersonal: Bool
    }
    
    struct DayData {
        let date: Date
        let isToday: Bool
        let events: [GoogleCalendarEvent]
        let allDayEvents: [GoogleCalendarEvent]
        let timedEvents: [GoogleCalendarEvent]
        let tasks: [GoogleTask]
    }
    
    // MARK: - Main Body
    var body: some View {
        GeometryReader { geometry in
            let dayColumnWidth = (geometry.size.width - timeColumnWidth) / 7
            
            VStack(spacing: 0) {
                // Fixed header with day labels
                headerSection(dayColumnWidth: dayColumnWidth)
                
                // Fixed daily tasks section at top
                dailyTasksSection(dayColumnWidth: dayColumnWidth)
                
                // Scrollable content (all-day events and timeline)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // All-day events section
                        if hasAnyAllDayEvents {
                            allDayEventsSection(dayColumnWidth: dayColumnWidth)
                        }
                        
                        // Timeline grid with events
                        timelineSection(dayColumnWidth: dayColumnWidth)
                    }
                }
            }
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }
    
    // MARK: - Computed Properties
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start else {
            return []
        }
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }
    
    private var timelineHours: (start: Int, end: Int) {
        let calendar = Calendar.current
        var earliestHour = defaultStartHour
        var latestHour = defaultEndHour
        
        // Check all events across the week to find the earliest and latest times
        for date in weekDates {
            let events = weekEvents[date] ?? []
            let timedEvents = events.filter { !$0.isAllDay }
            
            for event in timedEvents {
                if let startTime = event.startTime {
                    let startHour = calendar.component(.hour, from: startTime)
                    earliestHour = min(earliestHour, startHour)
                }
                
                if let endTime = event.endTime {
                    let endHour = calendar.component(.hour, from: endTime)
                    // If minutes are > 0, we need to show the next hour too
                    let endMinute = calendar.component(.minute, from: endTime)
                    let adjustedEndHour = endMinute > 0 ? endHour + 1 : endHour
                    latestHour = max(latestHour, adjustedEndHour)
                }
            }
        }
        
        // Ensure we have at least the default range and cap at 24-hour bounds
        return (
            start: max(0, min(earliestHour, defaultStartHour)),
            end: min(24, max(latestHour, defaultEndHour))
        )
    }
    
    private var startHour: Int {
        return timelineHours.start
    }
    
    private var endHour: Int {
        return timelineHours.end
    }
    
    private var hasAnyAllDayEvents: Bool {
        weekDates.contains { date in
            let events = weekEvents[date] ?? []
            return events.contains { $0.isAllDay }
        }
    }
    
    private func dayData(for date: Date) -> DayData {
        let events = weekEvents[date] ?? []
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        let allDayEvents = events.filter { $0.isAllDay }
        let timedEvents = events.filter { !$0.isAllDay && isEventInTimeRange($0) }
        let personalTasksForDate = filteredTasksForDate(personalTasks, date: date)
        let professionalTasksForDate = filteredTasksForDate(professionalTasks, date: date)
        let tasks = personalTasksForDate + professionalTasksForDate
        
        return DayData(
            date: date,
            isToday: isToday,
            events: events,
            allDayEvents: allDayEvents,
            timedEvents: timedEvents,
            tasks: tasks
        )
    }
    
    // MARK: - Header Section
    private func headerSection(dayColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Time column placeholder
            Text("Time")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: timeColumnWidth, height: dayHeaderHeight)
                .background(Color(.systemGray6))
            
            // Day headers
            ForEach(weekDates, id: \.self) { date in
                let data = dayData(for: date)
                dayHeaderView(data: data)
                    .frame(width: dayColumnWidth, height: dayHeaderHeight)
                    .background(Color(.systemGray6))
                    .overlay(
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
            }
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Daily Tasks Section
    private func dailyTasksSection(dayColumnWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Personal Tasks Row
            dailyTasksRow(
                title: "Personal",
                color: personalColor,
                tasks: personalTasksByDate,
                dayColumnWidth: dayColumnWidth
            )
            
            // Thin separator line between personal and professional
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 0.5)
            
            // Professional Tasks Row
            dailyTasksRow(
                title: "Professional", 
                color: professionalColor,
                tasks: professionalTasksByDate,
                dayColumnWidth: dayColumnWidth
            )
        }
    }
    
    private func dailyTasksRow(title: String, color: Color, tasks: [Date: [GoogleTask]], dayColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Task type indicator circle with checkmark
            VStack {
                Circle()
                    .fill(color)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
                Spacer()
            }
            .frame(width: timeColumnWidth, height: 60)
            .background(Color(.systemGray6))
            
            // Tasks for each day
            ForEach(weekDates, id: \.self) { date in
                let dayTasks = tasks[Calendar.current.startOfDay(for: date)] ?? []
                dailyTasksCell(tasks: dayTasks, color: color)
                    .frame(width: dayColumnWidth, height: 60)
                    .background(Color(.systemBackground))
                    .overlay(
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
            }
        }
    }
    
    private func dailyTasksCell(tasks: [GoogleTask], color: Color) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(tasks, id: \.id) { task in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(task.isCompleted ? Color.gray : color)
                            .frame(width: 4, height: 4)
                        
                        Text(task.title)
                            .font(.caption2)
                            .foregroundColor(task.isCompleted ? .gray : .primary)
                            .strikethrough(task.isCompleted)
                            .lineLimit(1)
                        
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    // MARK: - All-Day Events Section
    private func allDayEventsSection(dayColumnWidth: CGFloat) -> some View {
        let maxEvents = weekDates.map { date in
            dayData(for: date).allDayEvents.count
        }.max() ?? 0
        
        let sectionHeight = max(40, CGFloat(maxEvents) * allDayEventHeight + 16)
        
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Time column with "All Day" label
                Text("All Day")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: timeColumnWidth, height: sectionHeight)
                    .background(Color(.systemGray6))
                
                // All-day events for each day
                ForEach(weekDates, id: \.self) { date in
                    let data = dayData(for: date)
                    allDayEventsColumn(data: data)
                        .frame(width: dayColumnWidth, height: sectionHeight)
                        .background(Color(.systemBackground))
                        .overlay(
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                }
            }
            
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 0.5)
        }
    }
    
    // MARK: - Timeline Section
    private func timelineSection(dayColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Time column
            timeColumn()
                .frame(width: timeColumnWidth)
                .background(Color(.systemGray6))
            
            // Day columns
            ForEach(weekDates, id: \.self) { date in
                let data = dayData(for: date)
                dayTimelineColumn(data: data, width: dayColumnWidth)
                    .overlay(
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
            }
        }
    }
    
    // MARK: - Individual Components
    private func dayHeaderView(data: DayData) -> some View {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "E" // Mon, Tue, etc.
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d" // 1, 2, 3
        
        return VStack(spacing: 4) {
            Text(dayFormatter.string(from: data.date))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(data.isToday ? .white : .secondary)
            
            Text(dateFormatter.string(from: data.date))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(data.isToday ? .white : .primary)
            

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(data.isToday ? Color.blue : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { onDayTap?(data.date) }
    }
    
    private func allDayEventsColumn(data: DayData) -> some View {
        VStack(spacing: 2) {
            ForEach(data.allDayEvents, id: \.id) { event in
                allDayEventView(event: event)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func allDayEventView(event: GoogleCalendarEvent) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let color = isPersonal ? personalColor : professionalColor
        
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            
            Text(event.summary)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.15))
        )
        .onTapGesture { onEventTap?(event) }
    }
    
    private func timeColumn() -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                timeSlotLabel(hour: hour)
                    .frame(height: hourHeight)
            }
        }
    }
    
    private func timeSlotLabel(hour: Int) -> some View {
        VStack {
            Text(formatHour(hour))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
            
            Spacer()
        }
    }
    
    private func dayTimelineColumn(data: DayData, width: CGFloat) -> some View {
        let eventLayouts = calculateEventLayouts(events: data.timedEvents, width: width)
        
        return ZStack(alignment: .topLeading) {
            // Background grid
            timelineGrid()
            
            // Events
            ForEach(eventLayouts, id: \.event.id) { layout in
                timedEventView(layout: layout)
            }
            
            // Current time indicator
            if data.isToday {
                currentTimeIndicator()
            }
        }
        .frame(width: width)
    }
    
    private func timelineGrid() -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                Rectangle()
                    .fill(Color(.systemBackground))
                    .frame(height: hourHeight)
                    .overlay(
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 0.5)
                            
                            Spacer()
                            
                            Rectangle()
                                .fill(Color(.systemGray6))
                                .frame(height: 0.5)
                                .offset(y: -hourHeight/2)
                        }
                    )
            }
        }
    }
    
    private func timedEventView(layout: EventLayout) -> some View {
        let color = layout.isPersonal ? personalColor : professionalColor
        
        return RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: layout.width, height: layout.height)
            .overlay(
                VStack(alignment: .leading, spacing: 1) {
                    Text(layout.event.summary)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(layout.height > 30 ? 2 : 1)
                    
                    if layout.height > 25, let startTime = layout.event.startTime {
                        Text(formatEventTime(startTime))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
            .offset(x: layout.xOffset, y: layout.startOffset)
            .onTapGesture { onEventTap?(layout.event) }
    }
    
    private func currentTimeIndicator() -> some View {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        guard hour >= startHour && hour < endHour else {
            return AnyView(EmptyView())
        }
        
        let yOffset = CGFloat(hour - startHour) * hourHeight + CGFloat(minute) * (hourHeight / 60.0)
        
        return AnyView(
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(x: -3)
                
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 2)
            }
            .offset(y: yOffset)
        )
    }
    
    // MARK: - Helper Functions
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }
    
    private func formatEventTime(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: time)
    }
    
    private func isEventInTimeRange(_ event: GoogleCalendarEvent) -> Bool {
        guard let startTime = event.startTime else { return false }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour], from: startTime)
        let hour = components.hour ?? 0
        return hour >= startHour && hour < endHour
    }
    

    
    // MARK: - Task Grouping
    private var personalTasksByDate: [Date: [GoogleTask]] {
        groupTasksByDate(personalTasks)
    }
    
    private var professionalTasksByDate: [Date: [GoogleTask]] {
        groupTasksByDate(professionalTasks)
    }
    
    private func groupTasksByDate(_ tasks: [GoogleTask]) -> [Date: [GoogleTask]] {
        let calendar = Calendar.current
        var groupedTasks: [Date: [GoogleTask]] = [:]
        
        // Group tasks by each day in the week using the same logic as day view
        for date in weekDates {
            let tasksForDate = filteredTasksForDate(tasks, date: date)
            if !tasksForDate.isEmpty {
                groupedTasks[calendar.startOfDay(for: date)] = tasksForDate
            }
        }
        
        return groupedTasks
    }
    
    // Use the exact same filtering logic as the day view
    private func filteredTasksForDate(_ tasks: [GoogleTask], date: Date) -> [GoogleTask] {
        let calendar = Calendar.current
        
        var filteredTasks = tasks
        
        // First, filter by hide completed tasks setting if enabled
        if hideCompletedTasks {
            filteredTasks = filteredTasks.filter { !$0.isCompleted }
        }
        
        // Then filter tasks based on date logic (same as day view)
        filteredTasks = filteredTasks.compactMap { task in
            // For completed tasks, only show them on their completion date
            if task.isCompleted {
                guard let completionDate = task.completionDate else { return nil }
                return calendar.isDate(completionDate, inSameDayAs: date) ? task : nil
            } else {
                // For incomplete tasks, only show them on their exact due date
                guard let dueDate = task.dueDate else { return nil }
                
                // Only show tasks on their exact due date (not on future dates)
                return calendar.isDate(dueDate, inSameDayAs: date) ? task : nil
            }
        }
        
        return filteredTasks
    }
    
    // MARK: - Event Layout Calculation
    private func calculateEventLayouts(events: [GoogleCalendarEvent], width: CGFloat) -> [EventLayout] {
        var layouts: [EventLayout] = []
        let calendar = Calendar.current
        
        // Group overlapping events
        let sortedEvents = events.sorted { event1, event2 in
            guard let start1 = event1.startTime, let start2 = event2.startTime else {
                return false
            }
            return start1 < start2
        }
        
        var eventGroups: [[GoogleCalendarEvent]] = []
        
        for event in sortedEvents {
            guard let eventStart = event.startTime, let eventEnd = event.endTime else { continue }
            
            // Find which group this event belongs to (if any)
            var addedToGroup = false
            for groupIndex in 0..<eventGroups.count {
                let group = eventGroups[groupIndex]
                let overlapsWithGroup = group.contains { existingEvent in
                    guard let existingStart = existingEvent.startTime,
                          let existingEnd = existingEvent.endTime else { return false }
                    return eventStart < existingEnd && eventEnd > existingStart
                }
                
                if overlapsWithGroup {
                    eventGroups[groupIndex].append(event)
                    addedToGroup = true
                    break
                }
            }
            
            if !addedToGroup {
                eventGroups.append([event])
            }
        }
        
        // Calculate layouts for each group
        for group in eventGroups {
            let numColumns = group.count
            let columnWidth = width / CGFloat(numColumns)
            
            for (index, event) in group.enumerated() {
                guard let startTime = event.startTime,
                      let endTime = event.endTime else { continue }
                
                let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                
                let startHour = startComponents.hour ?? 0
                let startMinute = startComponents.minute ?? 0
                let _ = endComponents.hour ?? 0
                let _ = endComponents.minute ?? 0
                
                let startOffset = CGFloat(startHour - self.startHour) * hourHeight + 
                                 CGFloat(startMinute) * (hourHeight / 60.0)
                
                let duration = endTime.timeIntervalSince(startTime)
                let height = max(20, CGFloat(duration / 3600.0) * hourHeight)
                
                let isPersonal = personalEvents.contains { $0.id == event.id }
                
                let layout = EventLayout(
                    event: event,
                    startOffset: startOffset,
                    height: height,
                    width: columnWidth - 4, // Leave small gap
                    xOffset: CGFloat(index) * columnWidth + 2,
                    isPersonal: isPersonal
                )
                
                layouts.append(layout)
            }
        }
        
        return layouts
    }
    
    // MARK: - Timer Functions
    private func startTimer() {
        currentTimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            currentTime = Date()
        }
        currentTime = Date()
    }
    
    private func stopTimer() {
        currentTimeTimer?.invalidate()
        currentTimeTimer = nil
    }
}

// MARK: - Preview
struct WeekTimelineComponent_Previews: PreviewProvider {
    static var previews: some View {
        WeekTimelineComponent(
            currentDate: Date(),
            weekEvents: [:],
            personalEvents: [],
            professionalEvents: [],
            personalColor: .purple,
            professionalColor: .green,
            personalTasks: [],
            professionalTasks: [],
            hideCompletedTasks: false,
            initialUntimedRows: 0
        )
        .previewLayout(.sizeThatFits)
    }
}