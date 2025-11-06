import SwiftUI

// MARK: - Timeline Configuration
struct TimelineConfig {
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat
    let timeColumnWidth: CGFloat
    let showCurrentTime: Bool
    let showAllDayEvents: Bool
    
    static let `default` = TimelineConfig(
        startHour: 0,
        endHour: 24,
        hourHeight: 80,
        timeColumnWidth: 50,
        showCurrentTime: true,
        showAllDayEvents: true
    )
}

// MARK: - Timeline Base View
struct TimelineBaseView: View {
    let date: Date
    let events: [GoogleCalendarEvent]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let config: TimelineConfig
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    
    // MARK: - Event Layout Model
    struct EventLayout {
        let event: GoogleCalendarEvent
        let startOffset: CGFloat
        let height: CGFloat
        let width: CGFloat
        let xOffset: CGFloat
        let isPersonal: Bool
    }
    
    init(
        date: Date,
        events: [GoogleCalendarEvent],
        personalEvents: [GoogleCalendarEvent],
        professionalEvents: [GoogleCalendarEvent],
        personalColor: Color,
        professionalColor: Color,
        config: TimelineConfig = .default,
        onEventTap: ((GoogleCalendarEvent) -> Void)? = nil
    ) {
        self.date = date
        self.events = events
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.config = config
        self.onEventTap = onEventTap
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                if config.showAllDayEvents {
                    allDayEventsSection
                }
                
                timelineSection
            }
        }
        .padding(.leading, 2) // Add 2px left padding
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    // MARK: - All-Day Events Section
    private var allDayEventsSection: some View {
        let allDayEvents = events.filter { $0.isAllDay }
        
        return VStack(spacing: 0) {
            if !allDayEvents.isEmpty {
                HStack(spacing: 0) {
                    // Time column with "All Day" label
                    Text("All Day")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: config.timeColumnWidth)
                        .background(Color(.systemGray6))
                    
                    // All-day events
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(allDayEvents) { event in
                                allDayEventView(event)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
                .frame(height: 40)
                
                Divider()
            }
        }
    }
    
    // MARK: - Timeline Section
    private var timelineSection: some View {
        let totalHeight = CGFloat(config.endHour - config.startHour) * config.hourHeight + 20
        
        return GeometryReader { geometry in
            HStack(spacing: 0) {
                // Time column
                timeColumn
                    .frame(width: config.timeColumnWidth)
                    .background(Color(.systemGray6))
                
                // Events area
                ZStack(alignment: .topLeading) {
                    // Background grid
                    timelineGrid
                    
                    // Events with layout calculation
                    let timedEvents = events.filter { !$0.isAllDay }
                    let eventLayouts = calculateEventLayouts(events: timedEvents, width: geometry.size.width - config.timeColumnWidth)
                    ForEach(eventLayouts, id: \.event.id) { layout in
                        timelineEventView(layout: layout)
                    }
                    
                    // Current time indicator
                    if config.showCurrentTime && Calendar.current.isDate(date, inSameDayAs: Date()) {
                        currentTimeIndicator
                    }
                }
            }
        }
        .frame(height: totalHeight)
    }
    
    // MARK: - Component Views
    private var timeColumn: some View {
        VStack(spacing: 0) {
            ForEach(config.startHour..<config.endHour, id: \.self) { hour in
                VStack {
                    Text(formatHour(hour))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                    
                    Spacer()
                }
                .frame(height: config.hourHeight)
            }
            
            // Final 12a label at the end of the day
            Text(formatHour(config.endHour))
                .font(.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
                .frame(height: 20) // Small height for the final label
        }
    }
    
    private var timelineGrid: some View {
        VStack(spacing: 0) {
            ForEach(config.startHour..<config.endHour, id: \.self) { hour in
                VStack(spacing: 0) {
                    // Hour line
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 0.5)
                    
                    // Half-hour line
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .frame(height: 0.5)
                        .offset(y: config.hourHeight / 2)
                    
                    Spacer()
                }
                .frame(height: config.hourHeight)
                .background(Color(.systemBackground))
            }
            
            // Final 12a line at the end of the day
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: 0.5)
        }
    }
    
    private func allDayEventView(_ event: GoogleCalendarEvent) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let color = isPersonal ? personalColor : professionalColor
        
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(event.summary)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.1))
        )
        .onTapGesture {
            onEventTap?(event)
        }
    }
    
    private func timelineEventView(layout: EventLayout) -> some View {
        let color = layout.isPersonal ? personalColor : professionalColor
        
        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                Text(layout.event.summary)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                if layout.height > 40, let startTime = layout.event.startTime {
                    Text(formatEventTime(startTime))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(width: layout.width, height: layout.height)
            .background(color)
            .cornerRadius(4)
            .offset(x: layout.xOffset, y: layout.startOffset)
            .onTapGesture {
                onEventTap?(layout.event)
            }
        )
    }
    
    private var currentTimeIndicator: some View {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        let yOffset = CGFloat(hour - config.startHour) * config.hourHeight +
                     CGFloat(minute) * (config.hourHeight / 60.0)
        
        return HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
        }
        .offset(y: yOffset)
    }
    
    // MARK: - Helper Methods
    private func formatHour(_ hour: Int) -> String {
        let normalizedHour = ((hour % 24) + 24) % 24 // ensures 0-23
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: normalizedHour, minute: 0, second: 0, of: Date()) ?? Date()
        var timeString = formatter.string(from: date).lowercased()
        // Remove the "m" from "am/pm" to show "6a" instead of "6am"
        timeString = timeString.replacingOccurrences(of: "m", with: "")
        // Special-case 24 -> 12a (end-of-day label)
        if hour == 24 { return "12a" }
        return timeString
    }
    
    private func formatEventTime(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: time)
    }
    
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
                
                // Determine if this is a multi-day event and which day we're rendering
                let eventStartDay = calendar.startOfDay(for: startTime)
                let eventEndDay = calendar.startOfDay(for: endTime)
                let currentDay = calendar.startOfDay(for: date)
                
                // Calculate adjusted start and end times for this specific day
                let dayStartTime: Date
                let dayEndTime: Date
                
                if eventStartDay == eventEndDay {
                    // Single-day event
                    dayStartTime = startTime
                    dayEndTime = endTime
                } else if currentDay == eventStartDay {
                    // First day of multi-day event: use actual start time to end of day
                    dayStartTime = startTime
                    dayEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentDay) ?? endTime
                } else if currentDay == eventEndDay {
                    // Last day of multi-day event: use start of day to actual end time
                    dayStartTime = calendar.startOfDay(for: currentDay)
                    dayEndTime = endTime
                } else {
                    // Middle day(s): use start of day to end of day (full day)
                    dayStartTime = calendar.startOfDay(for: currentDay)
                    dayEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentDay) ?? currentDay
                }
                
                let startComponents = calendar.dateComponents([.hour, .minute], from: dayStartTime)
                
                let startHour = startComponents.hour ?? 0
                let startMinute = startComponents.minute ?? 0
                
                let startOffset = CGFloat(startHour - config.startHour) * config.hourHeight + 
                                 CGFloat(startMinute) * (config.hourHeight / 60.0)
                
                // Calculate height based on duration for this day
                let dayDuration = dayEndTime.timeIntervalSince(dayStartTime)
                let height = max(20, CGFloat(dayDuration / 3600.0) * config.hourHeight)
                
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
}


