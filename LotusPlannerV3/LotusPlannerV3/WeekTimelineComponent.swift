import SwiftUI

struct WeekTimelineComponent: View {
    let currentDate: Date
    let weekEvents: [Date: [GoogleCalendarEvent]]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    
    private let hourHeight: CGFloat = 100
    private let startHour = 6
    private let endHour = 23
    private let timeColumnWidth: CGFloat = 60
    
    init(currentDate: Date, weekEvents: [Date: [GoogleCalendarEvent]], personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self.currentDate = currentDate
        self.weekEvents = weekEvents
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.onEventTap = onEventTap
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
                
                // Scrollable timeline section with all-day events at the top
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
            }
            .frame(width: timeColumnWidth)
            .background(Color(.systemGray6).opacity(0.3))
            
            // Seven day columns (without headers)
            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                dayTimelineColumn(date: date, width: dayColumnWidth)
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
        .onTapGesture {
            onEventTap?(event)
        }
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
            .onTapGesture {
                onEventTap?(event)
            }
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
}



// MARK: - Week2TimelineComponent (Vertical Layout)
struct Week2TimelineComponent: View {
    let currentDate: Date
    let weekEvents: [Date: [GoogleCalendarEvent]]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    @State private var dividerPosition: CGFloat = 0.6 // 60% for timeline, 40% for tasks
    
    private let hourHeight: CGFloat = 100
    private let startHour = 6
    private let endHour = 23
    private let timeColumnWidth: CGFloat = 60
    
    init(currentDate: Date, weekEvents: [Date: [GoogleCalendarEvent]], personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self.currentDate = currentDate
        self.weekEvents = weekEvents
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.onEventTap = onEventTap
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Timeline section (left side)
                VStack(spacing: 0) {
                    frozenHeaderSection(width: geometry.size.width * dividerPosition)
                    
                    // Scrollable timeline
                    ScrollView(.vertical, showsIndicators: false) {
                        scrollableTimelineSection(width: geometry.size.width * dividerPosition)
                    }
                    .coordinateSpace(name: "timeline")
                }
                .frame(width: geometry.size.width * dividerPosition)
                
                // Vertical Divider
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newPosition = (geometry.size.width * dividerPosition + value.translation.width) / geometry.size.width
                                dividerPosition = max(0.3, min(0.8, newPosition))
                            }
                    )
                
                // Tasks section (right side)
                VStack(spacing: 0) {
                    // Tasks header
                    HStack {
                        Text("Tasks")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6).opacity(0.3))
                    
                    // Tasks content
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            PersonalTasksComponent(
                                taskLists: [],
                                tasksDict: [:],
                                accentColor: personalColor,
                                onTaskToggle: { _, _ in },
                                onTaskDetails: { _, _ in }
                            )
                            
                            ProfessionalTasksComponent(
                                taskLists: [],
                                tasksDict: [:],
                                accentColor: professionalColor,
                                onTaskToggle: { _, _ in },
                                onTaskDetails: { _, _ in }
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
                .frame(width: geometry.size.width * (1 - dividerPosition) - 2)
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
    
    // Frozen header section
    private func frozenHeaderSection(width: CGFloat) -> some View {
        let dayColumnWidth = (width - timeColumnWidth) / 7
        
        return VStack(spacing: 0) {
            // Day headers
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
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                }
            }
            .background(Color(.systemBackground))
            
            Divider()
                .background(Color(.systemGray4))
        }
    }
    
    // Day header
    private func dayHeader(date: Date, isToday: Bool) -> some View {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "E"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d"
        
        return VStack(spacing: 2) {
            Text(dayFormatter.string(from: date))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(dateFormatter.string(from: date))
                .font(.title3)
                .fontWeight(isToday ? .bold : .medium)
                .foregroundColor(isToday ? .white : .primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            ZStack {
                Color.clear
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
            }
        )
    }
    
    // Scrollable timeline section
    private func scrollableTimelineSection(width: CGFloat) -> some View {
        let dayColumnWidth = (width - timeColumnWidth) / 7
        
        return VStack(spacing: 0) {
            // All-day events section if any exist
            if hasAllDayEvents {
                allDayEventsSection(width: width, dayColumnWidth: dayColumnWidth)
            }
            
            // Regular timeline
            HStack(spacing: 0) {
                // Time labels column
                VStack(spacing: 0) {
                    ForEach(startHour..<endHour, id: \.self) { hour in
                        timeSlot(hour: hour)
                            .frame(height: hourHeight)
                    }
                }
                .frame(width: timeColumnWidth)
                .background(Color(.systemGray6).opacity(0.3))
                
                // Day columns with events
                ZStack(alignment: .topLeading) {
                    // Day columns background
                    HStack(spacing: 0) {
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            dayTimelineColumn(date: date, width: dayColumnWidth)
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                        }
                    }
                    
                    // Events overlay
                    ForEach(weekDates.indices, id: \.self) { dayIndex in
                        let date = weekDates[dayIndex]
                        let dayEvents = weekEvents[date]?.filter { !$0.isAllDay } ?? []
                        let eventLayouts = calculateEventLayouts(for: dayEvents, dayIndex: dayIndex, dayColumnWidth: dayColumnWidth)
                        
                        ForEach(eventLayouts, id: \.event.id) { layout in
                            eventBlock(layout: layout)
                        }
                    }
                    
                    // Current time line
                    currentTimeLine(width: width)
                }
            }
        }
    }
    
    // All-day events section
    private func allDayEventsSection(width: CGFloat, dayColumnWidth: CGFloat) -> some View {
        let maxEventsInAnyDay = weekDates.map { date in
            let events = weekEvents[date] ?? []
            return events.filter { $0.isAllDay }.count
        }.max() ?? 0
        
        let sectionHeight = max(40, CGFloat(maxEventsInAnyDay) * 24 + 16)
        
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
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                }
            }
            .background(Color(.systemGray6).opacity(0.1))
            
            Divider()
                .background(Color(.systemGray4))
        }
    }
    
    private func allDayEventsForDay(date: Date) -> some View {
        let allDayEvents = weekEvents[date]?.filter { $0.isAllDay } ?? []
        
        return VStack(spacing: 2) {
            ForEach(allDayEvents, id: \.id) { event in
                allDayEventBlock(event: event)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
    
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
            
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(eventColor.opacity(0.1))
        )
        .onTapGesture {
            onEventTap?(event)
        }
    }
    
    private func timeSlot(hour: Int) -> some View {
        VStack {
            Text(formatHour(hour))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)
            Spacer()
        }
        .frame(height: hourHeight)
    }
    
    private func dayTimelineColumn(date: Date, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                Rectangle()
                    .fill(Color(.systemGray6).opacity(0.1))
                    .frame(height: hourHeight)
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
        .frame(width: width)
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }
    
    private func calculateEventLayouts(for events: [GoogleCalendarEvent], dayIndex: Int, dayColumnWidth: CGFloat) -> [EventLayout] {
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
            let endMinutes = min((endHour - self.startHour) * 60 + endMinute, (self.endHour - self.startHour) * 60)
            
            return EventTime(event: event, startMinutes: startMinutes, endMinutes: endMinutes)
        }
        
        // Group overlapping events
        var eventGroups: [[EventTime]] = []
        var processedEvents: Set<String> = []
        
        for eventTime in eventTimes {
            if processedEvents.contains(eventTime.event.id) { continue }
            
            var group = [eventTime]
            processedEvents.insert(eventTime.event.id)
            
            for otherEventTime in eventTimes {
                if processedEvents.contains(otherEventTime.event.id) { continue }
                
                if group.contains(where: { $0.overlaps(with: otherEventTime) }) {
                    group.append(otherEventTime)
                    processedEvents.insert(otherEventTime.event.id)
                }
            }
            
            eventGroups.append(group)
        }
        
        // Create layouts
        var layouts: [EventLayout] = []
        
        for group in eventGroups {
            let sortedGroup = group.sorted { $0.startMinutes < $1.startMinutes }
            let columnWidth = dayColumnWidth / CGFloat(sortedGroup.count)
            
            for (columnIndex, eventTime) in sortedGroup.enumerated() {
                let topOffset = CGFloat(eventTime.startMinutes) * (hourHeight / 60.0)
                let height = max(30.0, CGFloat(eventTime.endMinutes - eventTime.startMinutes) * (hourHeight / 60.0))
                let xOffset = timeColumnWidth + CGFloat(dayIndex) * dayColumnWidth + CGFloat(columnIndex) * columnWidth
                
                let layout = EventLayout(
                    event: eventTime.event,
                    column: columnIndex,
                    totalColumns: sortedGroup.count,
                    topOffset: topOffset,
                    height: height,
                    width: columnWidth - 2,
                    xOffset: xOffset + 1
                )
                layouts.append(layout)
            }
        }
        
        return layouts
    }
    
    private func eventBlock(layout: EventLayout) -> some View {
        let isPersonal = personalEvents.contains { $0.id == layout.event.id }
        let backgroundColor = isPersonal ? personalColor : professionalColor
        
        return VStack(alignment: .leading, spacing: 2) {
            Text(layout.event.summary)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(layout.height > 40 ? 3 : 2)
            
            if layout.height > 40,
               let startTime = layout.event.startTime {
                let components = Calendar.current.dateComponents([.hour, .minute], from: startTime)
                Text("\(String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .offset(x: layout.xOffset, y: layout.topOffset)
        .onTapGesture {
            onEventTap?(layout.event)
        }
    }
    
    private func currentTimeLine(width: CGFloat) -> some View {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        let yOffset = CGFloat(hour - startHour) * hourHeight + CGFloat(minute) * (hourHeight / 60.0)
        
        return HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .offset(x: timeColumnWidth - 10)
            
            Rectangle()
                .fill(Color.red)
                .frame(width: width - timeColumnWidth, height: 2)
                .offset(x: timeColumnWidth - 6)
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
}

// MARK: - Helper Structures for Week2TimelineComponent
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

// MARK: - Preview
struct WeekTimelineComponent_Previews: PreviewProvider {
    static var previews: some View {
        WeekTimelineComponent(
            currentDate: Date(),
            weekEvents: [:],
            personalEvents: [],
            professionalEvents: [],
            personalColor: .purple,
            professionalColor: .green
        )
        .previewLayout(.sizeThatFits)
    }
} 