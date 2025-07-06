import SwiftUI

struct WeekTimelineComponent: View {
    let currentDate: Date
    let weekEvents: [Date: [GoogleCalendarEvent]]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    // Task data
    let personalTasks: [GoogleTask]
    let professionalTasks: [GoogleTask]
    let hideCompletedTasks: Bool
    let initialUntimedRows: Int
    
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    let onDayTap: ((Date) -> Void)?
    
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    @State private var showTaskRows: Bool = true
    @State private var untimedRows: Int = 0
    @State private var dragStartRows: Int = 0
    
    private let hourHeight: CGFloat = 100
    private let startHour = 6
    private let endHour = 23
    private let timeColumnWidth: CGFloat = 60
    
    private var dividerGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let deltaRows = Int((value.translation.height / hourHeight).rounded())
                let newVal = max(0, dragStartRows + deltaRows)
                if newVal != untimedRows { untimedRows = newVal }
            }
            .onEnded { _ in
                dragStartRows = untimedRows
            }
    }
    
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
        _untimedRows = State(initialValue: initialUntimedRows)
        _dragStartRows = State(initialValue: initialUntimedRows)
    }
    
    // MARK: - Event Layout Models
    struct EventLayout {
        let event: GoogleCalendarEvent
        let column: Int
        let totalColumns: Int
        let topOffset: CGFloat
        let height: CGFloat
        let width: CGFloat
        let xOffset: CGFloat
    }
    
    struct EventTime {
        let event: GoogleCalendarEvent
        let startMinutes: Int
        let endMinutes: Int
        
        func overlaps(with other: EventTime) -> Bool {
            return startMinutes < other.endMinutes && endMinutes > other.startMinutes
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let dayColumnWidth = (geometry.size.width - timeColumnWidth) / 7
            
            VStack(spacing: 0) {
                // Frozen header section with only day titles (no all-day events)
                frozenHeaderSection(dayColumnWidth: dayColumnWidth)
                
                // Scrollable timeline section with Task rows + all-day events at the top
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // All-day events section (scrollable)
                        if hasAllDayEvents {
                            allDayEventsSection(dayColumnWidth: dayColumnWidth)
                        }
                        
                        // Regular timeline section
                        scrollableTimelineSection(dayColumnWidth: dayColumnWidth)
                    }
                }
            }
        }
        .onAppear {
            startCurrentTimeTimer()
        }
        .onDisappear {
            stopCurrentTimeTimer()
        }
    }
    
    // MARK: - Week Dates
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start else {
            return []
        }
        
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }
    
    // MARK: - All-Day Events Check
    private var hasAllDayEvents: Bool {
        return weekDates.contains { date in
            let events = weekEvents[date] ?? []
            return events.contains { $0.isAllDay }
        }
    }
    
    // MARK: - Frozen Header Section
    private func frozenHeaderSection(dayColumnWidth: CGFloat) -> some View {
        // Day headers row only (all-day events moved to scrollable area)
        HStack(spacing: 0) {
            // Time column header
            Text("Time")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: timeColumnWidth, height: 50)
                .background(Color(.systemGray5))
            
            // Day headers
            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                dayHeader(date: date, isToday: Calendar.current.isDate(date, inSameDayAs: Date()))
                    .frame(width: dayColumnWidth)
                    .overlay(
                        // Right border between days
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
            }
        }
        .background(Color(.systemBackground))
        .zIndex(1) // Ensure it stays on top
    }
    
    // MARK: - Scrollable Timeline Section
    private func scrollableTimelineSection(dayColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Time labels column (without header)
            VStack(spacing: 0) {
                ForEach(startHour..<endHour, id: \.self) { hour in
                    timeSlot(hour: hour)
                        .frame(height: hourHeight)
                }
                // Divider between timed and untimed
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 8)
                    .gesture(dividerGesture)
                ForEach(0..<untimedRows, id: \.self) { _ in
                    Rectangle().fill(Color.clear).frame(height: hourHeight)
                }
            }
            .frame(width: timeColumnWidth)
            .background(Color(.systemGray6).opacity(0.3))
            
            // Seven day columns (without headers)
            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                VStack(spacing: 0) {
                    dayTimelineColumn(date: date, width: dayColumnWidth)
                    // Divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                        .gesture(dividerGesture)
                    ForEach(0..<untimedRows, id: \.self) { _ in
                        Rectangle().fill(Color.clear).frame(height: hourHeight)
                    }
                }
                .overlay(
                    // Right border between days
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 0.5),
                    alignment: .trailing
                )
            }
        }
    }
    
    // MARK: - All-Day Events Section
    private func allDayEventsSection(dayColumnWidth: CGFloat) -> some View {
        let maxEventsInAnyDay = weekDates.map { date in
            let events = weekEvents[date] ?? []
            return events.filter { $0.isAllDay }.count
        }.max() ?? 0
        
        // Calculate height based on actual number of events (20pt per event + padding)
        let sectionHeight = max(40, CGFloat(maxEventsInAnyDay) * 24 + 16) // 24pt per event + 16pt total padding
        
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Time column spacer with "All Day" label
                VStack {
                    Text("All Day")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 4)
                    Spacer()
                }
                .frame(width: timeColumnWidth, height: sectionHeight)
                .background(Color(.systemGray6).opacity(0.3))
                
                // Day columns for all-day events
                ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                    allDayEventsForDay(date: date)
                        .frame(width: dayColumnWidth, height: sectionHeight)
                        .overlay(
                            // Right border between days
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                }
            }
            .background(Color(.systemGray6).opacity(0.1))
            
            // Divider to separate from timed events
            Divider()
                .background(Color(.systemGray4))
        }
    }
    
    // All-day events for a specific day
    private func allDayEventsForDay(date: Date) -> some View {
        let events = weekEvents[date] ?? []
        let allDayEvents = events.filter { $0.isAllDay }
        
        return VStack(spacing: 2) {
            ForEach(allDayEvents, id: \.id) { event in
                allDayEventBlock(event: event)
            }
            Spacer(minLength: 0) // Push events to top if there are fewer events
        }
        .padding(.all, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // Individual all-day event block
    private func allDayEventBlock(event: GoogleCalendarEvent) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let eventColor = isPersonal ? personalColor : professionalColor
        
        return HStack(spacing: 4) {
            Circle()
                .fill(eventColor)
                .frame(width: 6, height: 6)
            
            Text(event.summary)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(eventColor.opacity(0.1))
        )
        .highPriorityGesture(
            TapGesture().onEnded { _ in
                onEventTap?(event)
            }
        )
        .onLongPressGesture { onEventTap?(event) }
    }
    
    private func timeSlot(hour: Int) -> some View {
        VStack {
            Text(formatHour(hour))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)
            Spacer()
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }
    
    // MARK: - Day Column (Legacy - kept for reference)
    private func dayColumn(date: Date, width: CGFloat) -> some View {
        let events = weekEvents[date] ?? []
        let timedEvents = events.filter { !$0.isAllDay }
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        
        return VStack(spacing: 0) {
            // Day header
            dayHeader(date: date, isToday: isToday)
                .frame(width: width)
            
            // Timeline for this day
            ZStack(alignment: .topLeading) {
                // Background grid
                VStack(spacing: 0) {
                    ForEach(startHour..<endHour, id: \.self) { hour in
                        hourGrid
                            .frame(height: hourHeight)
                    }
                }
                
                // Timed events overlay
                ForEach(timedEvents, id: \.id) { event in
                    eventView(for: event, dayWidth: width)
                }
                
                // Current time line (only show if date is today)
                if isToday {
                    currentTimeLine
                }
            }
        }
        .frame(width: width)
    }
    
    // MARK: - Day Timeline Column (without header)
    private func dayTimelineColumn(date: Date, width: CGFloat) -> some View {
        let events = weekEvents[date] ?? []
        let timedEvents = events.filter { !$0.isAllDay }
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        
        // Calculate event layouts with overlap resolution
        let eventLayouts = calculateEventLayouts(for: timedEvents, dayWidth: width)
        
        return ZStack(alignment: .topLeading) {
            // Background grid
            VStack(spacing: 0) {
                ForEach(startHour..<endHour, id: \.self) { hour in
                    hourGrid
                        .frame(height: hourHeight)
                }
            }
            
            // Timed events overlay with proper positioning
            ForEach(eventLayouts, id: \.event.id) { layout in
                eventBlock(for: layout.event, layout: layout)
            }
            
            // Current time line (only show if date is today)
            if isToday {
                currentTimeLine
            }
        }
        .frame(width: width)
    }
    
    // Day header with day name and date
    private func dayHeader(date: Date, isToday: Bool) -> some View {
        let dayOfWeekFormatter = DateFormatter()
        dayOfWeekFormatter.dateFormat = "E" // Mon, Tue, etc.
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d" // 1, 2, 3, etc.
        
        return ZStack {
            // Background for the entire header
            Color(.systemGray5)
            
            // Content with conditional highlighting
            VStack(spacing: 2) {
                Text(dayOfWeekFormatter.string(from: date))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(isToday ? .white : .primary)
                
                Text(dayFormatter.string(from: date))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(isToday ? .white : .primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isToday ? 
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue) : 
                nil
            )
        }
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onDayTap?(date) }
    }
    
    // Hour grid background
    private var hourGrid: some View {
        Rectangle()
            .fill(Color(.systemGray6).opacity(0.3))
            .overlay(
                // Half-hour line
                Rectangle()
                    .fill(Color(.systemGray6))
                    .frame(height: 0.5)
                    .offset(y: hourHeight / 2)
            )
            .overlay(
                // Hour line
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 1)
                    .offset(y: -0.5),
                alignment: .top
            )
    }
    
    // MARK: - Event View with Overlap Handling
    @ViewBuilder
    private func eventView(for event: GoogleCalendarEvent, dayWidth: CGFloat) -> some View {
        // This is now handled by the dayTimelineColumn with overlap resolution
        EmptyView()
    }
    
    // MARK: - Current Time Line
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
                .offset(x: -3)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
        }
        .offset(y: yOffset)
        .opacity(hour >= startHour && hour <= endHour ? 1 : 0)
    }
    
    // MARK: - Event Layout Calculation
    private func calculateEventLayouts(for events: [GoogleCalendarEvent], dayWidth: CGFloat) -> [EventLayout] {
        // Convert events to EventTime objects and sort by start time
        let eventTimes = events.compactMap { event -> EventTime? in
            guard let startTime = event.startTime,
                  let endTime = event.endTime else { return nil }
            
            let calendar = Calendar.current
            let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
            
            guard let startHour = startComponents.hour,
                  let startMinute = startComponents.minute,
                  let endHour = endComponents.hour,
                  let endMinute = endComponents.minute,
                  startHour >= self.startHour && startHour <= self.endHour else { return nil }
            
            let startMinutes = (startHour - self.startHour) * 60 + startMinute
            let endMinutes = (endHour - self.startHour) * 60 + endMinute
            
            return EventTime(event: event, startMinutes: startMinutes, endMinutes: endMinutes)
        }.sorted { $0.startMinutes < $1.startMinutes }
        
        // Group overlapping events using a more sophisticated algorithm
        var eventGroups: [[EventTime]] = []
        
        for eventTime in eventTimes {
            var mergedGroups: [Int] = []
            
            // Find all groups that this event overlaps with
            for (groupIndex, group) in eventGroups.enumerated() {
                let overlapsWithGroup = group.contains { existingEvent in
                    eventTime.overlaps(with: existingEvent)
                }
                
                if overlapsWithGroup {
                    mergedGroups.append(groupIndex)
                }
            }
            
            if mergedGroups.isEmpty {
                // No overlap, create new group
                eventGroups.append([eventTime])
            } else if mergedGroups.count == 1 {
                // Overlaps with one group, add to it
                eventGroups[mergedGroups[0]].append(eventTime)
            } else {
                // Overlaps with multiple groups, merge them all
                var mergedGroup = [eventTime]
                
                // Collect all events from groups to merge (in reverse order to avoid index issues)
                for groupIndex in mergedGroups.sorted(by: >) {
                    mergedGroup.append(contentsOf: eventGroups[groupIndex])
                    eventGroups.remove(at: groupIndex)
                }
                
                eventGroups.append(mergedGroup)
            }
        }
        
        // Calculate layouts for each group
        var layouts: [EventLayout] = []
        
        for group in eventGroups {
            let totalColumns = group.count
            
            for (columnIndex, eventTime) in group.enumerated() {
                let topOffset = CGFloat(eventTime.startMinutes) * (hourHeight / 60.0)
                let duration = eventTime.endMinutes - eventTime.startMinutes
                let height = max(20.0, CGFloat(duration) * (hourHeight / 60.0))
                
                let columnWidth = dayWidth / CGFloat(totalColumns)
                let width = columnWidth - 4 // Leave small gap between columns
                let xOffset = CGFloat(columnIndex) * columnWidth + 2
                
                let layout = EventLayout(
                    event: eventTime.event,
                    column: columnIndex,
                    totalColumns: totalColumns,
                    topOffset: topOffset,
                    height: height,
                    width: width,
                    xOffset: xOffset
                )
                
                layouts.append(layout)
            }
        }
        
        return layouts
    }
    
    // MARK: - Event Block View
    @ViewBuilder
    private func eventBlock(for event: GoogleCalendarEvent, layout: EventLayout) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let backgroundColor = isPersonal ? personalColor : professionalColor
        
        RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
            .frame(width: layout.width, height: layout.height)
            .overlay(
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.summary)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(layout.height > 40 ? 2 : 1)
                    
                    if layout.height > 30, let startTime = event.startTime {
                        let calendar = Calendar.current
                        let components = calendar.dateComponents([.hour, .minute], from: startTime)
                        if let hour = components.hour, let minute = components.minute {
                            Text("\(String(format: "%02d:%02d", hour, minute))")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
            .offset(x: layout.xOffset, y: layout.topOffset)
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture().onEnded { _ in onEventTap?(event) }
            )
            .onLongPressGesture { onEventTap?(event) }
    }
    
    // MARK: - Timer Methods
    private func startCurrentTimeTimer() {
        currentTimeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func stopCurrentTimeTimer() {
        currentTimeTimer?.invalidate()
        currentTimeTimer = nil
    }
    
    // MARK: - Task Rows Section
    private func taskRowsSection(dayColumnWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Toggle row
            HStack(spacing: 0) {
                Button(action: { withAnimation { showTaskRows.toggle() } }) {
                    Image(systemName: showTaskRows ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .frame(width: timeColumnWidth, height: 24)
                .background(Color(.systemGray6).opacity(0.3))

                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 0.5)
            }
            if showTaskRows {
                // Personal Row
                taskRow(for: personalTasksByDate, color: personalColor, height: 40, dayColumnWidth: dayColumnWidth)
                // Professional Row
                taskRow(for: professionalTasksByDate, color: professionalColor, height: 40, dayColumnWidth: dayColumnWidth)
            }
        }
    }

    private func taskRow(for tasksByDate: [Date: [GoogleTask]], color: Color, height: CGFloat, dayColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color.opacity(0.3))
                .frame(width: timeColumnWidth, height: height)

            ForEach(weekDates, id: \..self) { date in
                let tasks = tasksByDate[Calendar.mondayFirst.startOfDay(for: date)] ?? []
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tasks.prefix(3)) { task in
                        Text(task.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    if tasks.count > 3 {
                        Text("+\(tasks.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: dayColumnWidth, height: height, alignment: .topLeading)
                .padding(4)
                .background(Color(.systemBackground))
                .overlay(
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 0.5), alignment: .trailing)
            }
        }
    }

    // Grouped tasks by date
    private var personalTasksByDate: [Date: [GoogleTask]] {
        groupTasks(personalTasks)
    }

    private var professionalTasksByDate: [Date: [GoogleTask]] {
        groupTasks(professionalTasks)
    }

    private func groupTasks(_ tasks: [GoogleTask]) -> [Date: [GoogleTask]] {
        let cal = Calendar.mondayFirst
        var dict: [Date: [GoogleTask]] = [:]
        for task in tasks {
            guard let dueDate = task.dueDate else { continue }
            if hideCompletedTasks && task.isCompleted { continue }
            let startOfDue = cal.startOfDay(for: dueDate)
            if weekDates.contains(where: { cal.isDate($0, inSameDayAs: startOfDue) }) {
                dict[startOfDue, default: []].append(task)
            }
        }
        return dict
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