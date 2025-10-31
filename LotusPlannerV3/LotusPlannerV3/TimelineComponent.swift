import SwiftUI

struct TimelineComponent: View {
    let date: Date
    let events: [GoogleCalendarEvent]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    
    private let hourHeight: CGFloat = 100
    private let startHour = 0
    private let endHour = 24
    private let timeColumnWidth: CGFloat = 28
    
    // MARK: - Event Layout Model
    struct EventLayout {
        let event: GoogleCalendarEvent
        let startOffset: CGFloat
        let height: CGFloat
        let width: CGFloat
        let xOffset: CGFloat
        let isPersonal: Bool
    }
    
    
    
    // Separate all-day events from timed events
    private var allDayEvents: [GoogleCalendarEvent] {
        let filtered = events.filter { $0.isAllDay }
        return filtered
    }
    
    private var timedEvents: [GoogleCalendarEvent] {
        return events.filter { !$0.isAllDay }
    }
    
    init(date: Date, events: [GoogleCalendarEvent], personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self.date = date
        self.events = events
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.onEventTap = onEventTap
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                // All-day events section (only show if there are any)
                if !allDayEvents.isEmpty {
                    allDayEventsSection
                        .padding(.bottom, 8)
                }
                
                // Main timeline with hour grid and timed events
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
                                // Time label (left-aligned to match "Events" header)
                                Text(formatHour(endHour))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: timeColumnWidth, alignment: .leading)
                                
                                // Hour line
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 1)
                            }
                            .frame(height: 20)
                        }
                        
                        // Timed events overlay with layout calculation
                        let eventLayouts = calculateEventLayouts(events: timedEvents, width: geometry.size.width - timeColumnWidth - 1, offsetX: timeColumnWidth + 1)
                        ForEach(eventLayouts, id: \.event.id) { layout in
                            eventView(layout: layout)
                        }
                        
                        // Current time line (only show if date is today)
                        if Calendar.current.isDate(date, inSameDayAs: Date()) {
                            currentTimeLine
                        }
                    }
                }
                .frame(height: totalHeight)
                // debug border removed
                }
            }
            // Removed extra left padding to minimize gap next to time column
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
    
    // All-day events section at the top
    private var allDayEventsSection: some View {
        VStack(spacing: 0) {
            // All-day events list
            HStack(spacing: 0) {
                // Time column spacer to align with hour grid
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: timeColumnWidth + 1)
                
                // Events column
                VStack(spacing: 4) {
                    ForEach(allDayEvents, id: \.id) { event in
                        allDayEventBlock(event: event)
                    }
                }
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            // remove section background
            
            // Divider to separate from timed events
            Divider()
                .background(Color(.systemGray4))
        }
        // debug border removed
    }
    
    // Individual all-day event block
    private func allDayEventBlock(event: GoogleCalendarEvent) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let eventColor = isPersonal ? personalColor : professionalColor
        
        return HStack(spacing: 8) {
            Circle()
                .fill(eventColor)
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
                .fill(eventColor.opacity(0.1))
        )
        .onTapGesture { onEventTap?(event) }
        .onLongPressGesture { onEventTap?(event) }
    }
    
    private func timeSlot(hour: Int) -> some View {
        HStack(spacing: 0) {
            // Time label (left-aligned to match "Events" header)
            VStack {
                Text(formatHour(hour))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: timeColumnWidth, alignment: .leading)
                Spacer()
            }
            
            // Hour line and background
            Rectangle()
                .fill(Color.clear)
                .frame(height: hourHeight - 1)
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
        // debug border removed
    }
    
    private func formatHour(_ hour: Int) -> String {
        if hour == endHour { return "12a" }
        let normalizedHour = ((hour % 24) + 24) % 24
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: normalizedHour, minute: 0, second: 0, of: Date()) ?? Date()
        let timeString = formatter.string(from: date).lowercased()
        return timeString
    }
    
    private func eventView(layout: EventLayout) -> some View {
        let backgroundColor = layout.isPersonal ? personalColor : professionalColor
        
        return VStack(alignment: .leading, spacing: 2) {
            Text(layout.event.summary)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(layout.height > 40 ? 3 : 2)
            
            if layout.height > 40, let startTime = layout.event.startTime {
                let calendar = Calendar.current
                let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                if let startHour = startComponents.hour, let startMinute = startComponents.minute {
                    Text("\(String(format: "%02d:%02d", startHour, startMinute))")
                        .font(.body)
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
        .offset(x: layout.xOffset, y: layout.startOffset)
        .onTapGesture { onEventTap?(layout.event) }
        .onLongPressGesture { onEventTap?(layout.event) }
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
    
    // MARK: - Event Layout Calculation
    private func calculateEventLayouts(events: [GoogleCalendarEvent], width: CGFloat, offsetX: CGFloat) -> [EventLayout] {
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
                let endComponents = calendar.dateComponents([.hour, .minute], from: dayEndTime)
                
                let startHour = startComponents.hour ?? 0
                let startMinute = startComponents.minute ?? 0
                let endHour = endComponents.hour ?? 23
                let endMinute = endComponents.minute ?? 59
                
                let startOffset = CGFloat(startHour - self.startHour) * hourHeight + 
                                 CGFloat(startMinute) * (hourHeight / 60.0)
                
                // Calculate height based on duration for this day
                let dayDuration = dayEndTime.timeIntervalSince(dayStartTime)
                let height = max(30.0, CGFloat(dayDuration / 3600.0) * hourHeight)
                
                let isPersonal = personalEvents.contains { $0.id == event.id }
                
                let layout = EventLayout(
                    event: event,
                    startOffset: startOffset,
                    height: height,
                    width: columnWidth - 4, // Leave small gap
                    xOffset: offsetX + CGFloat(index) * columnWidth + 2,
                    isPersonal: isPersonal
                )
                
                layouts.append(layout)
            }
        }
        
        return layouts
    }
}

 
// MARK: - Preview
struct TimelineComponent_Previews: PreviewProvider {
    static var previews: some View {
        TimelineComponent(
            date: Date(),
            events: [],
            personalEvents: [],
            professionalEvents: [],
            personalColor: .purple,
            professionalColor: .green
        )
        .previewLayout(.sizeThatFits)
    }
} 