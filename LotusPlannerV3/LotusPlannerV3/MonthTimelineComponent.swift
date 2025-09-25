import SwiftUI

struct MonthTimelineComponent: View {
    let currentDate: Date
    let monthEvents: [Date: [GoogleCalendarEvent]]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    let onDayTap: ((Date) -> Void)?
    
    // dayHeight will be calculated dynamically based on available space
    
    init(currentDate: Date, monthEvents: [Date: [GoogleCalendarEvent]], personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil, onDayTap: ((Date) -> Void)? = nil) {
        self.currentDate = currentDate
        self.monthEvents = monthEvents
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.onEventTap = onEventTap
        self.onDayTap = onDayTap
        
        print("DEBUG: MonthTimelineComponent init - Personal events: \(personalEvents.count), Professional events: \(professionalEvents.count)")
        print("DEBUG: MonthTimelineComponent init - Month events: \(monthEvents.count) dates")
        let totalEventsInMonth = monthEvents.values.flatMap { $0 }.count
        print("DEBUG: MonthTimelineComponent init - Total events in month: \(totalEventsInMonth)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 7
            
            VStack(spacing: 0) {
                // Month header with day names
                monthHeader(columnWidth: columnWidth)
                
                // Month grid with events (takes up remaining space)
                monthGrid(columnWidth: columnWidth, availableHeight: geometry.size.height)
            }
        }
    }
    
    // MARK: - Month Header
    private func monthHeader(columnWidth: CGFloat) -> some View {
        // Day names header only
        HStack(spacing: 0) {
            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { dayName in
                Text(dayName)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: columnWidth, height: 30)
                    .background(Color(.systemGray5))
            }
        }
    }
    
    // MARK: - Month Grid
    private func monthGrid(columnWidth: CGFloat, availableHeight: CGFloat) -> some View {
        let headerHeight: CGFloat = 30 // Height of the day names header
        let gridHeight = availableHeight - headerHeight
        let rowHeight = gridHeight / 6 // Divide available space by 6 weeks
        
        return VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { weekIndex in
                weekRow(weekIndex: weekIndex, columnWidth: columnWidth, rowHeight: rowHeight)
            }
        }
    }
    
    private func weekRow(weekIndex: Int, columnWidth: CGFloat, rowHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { dayIndex in
                dayCell(weekIndex: weekIndex, dayIndex: dayIndex, columnWidth: columnWidth, rowHeight: rowHeight)
            }
        }
    }
    
    private func dayCell(weekIndex: Int, dayIndex: Int, columnWidth: CGFloat, rowHeight: CGFloat) -> some View {
        let dayNumber = getDayNumber(weekIndex: weekIndex, dayIndex: dayIndex)
        let date = getDateForDay(dayNumber: dayNumber)
        let isValidDay = dayNumber > 0 && dayNumber <= daysInMonth
        let isToday = isValidDay && date != nil && Calendar.current.isDate(date!, inSameDayAs: Date())
        let isCurrentMonth = isValidDay
        
        return VStack(spacing: 0) {
            if isValidDay, let dayDate = date {
                // Day number header
                Text("\(dayNumber)")
                    .font(.body)
                    .fontWeight(isToday ? .bold : .medium)
                    .foregroundColor(isToday ? .white : (isCurrentMonth ? .primary : .secondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .background(isToday ? Color.blue : Color.clear)
                
                // Events area (show first 3 events)
                eventsArea(for: dayDate)
                    .frame(maxHeight: .infinity)
                
                Spacer(minLength: 0)
            } else {
                // Empty day cell
                Color.clear
            }
        }
        .frame(width: columnWidth, height: rowHeight)
        .background(isCurrentMonth ? Color(.systemBackground) : Color(.systemGray6).opacity(0.3))
        .contentShape(Rectangle())
        .onTapGesture {
            if let validDate = date {
                onDayTap?(validDate)
            }
        }
    }
    
    // MARK: - Events Area
    private func eventsArea(for date: Date) -> some View {
        let events = monthEvents[date] ?? []
        let sortedEvents = events.sorted { first, second in
            // Sort all-day events first, then by start time
            if first.isAllDay && !second.isAllDay { return true }
            if !first.isAllDay && second.isAllDay { return false }
            return (first.startTime ?? Date.distantPast) < (second.startTime ?? Date.distantPast)
        }
        let displayEvents = Array(sortedEvents.prefix(5)) // Show only first 5 events
        
        print("DEBUG: MonthTimelineComponent eventsArea - Date: \(date), Events: \(events.count), DisplayEvents: \(displayEvents.count)")
        
        return VStack(spacing: 2) {
            ForEach(displayEvents, id: \.id) { event in
                eventBlock(event: event)
            }
            
            // Show "+X more" if there are more than 5 events
            if events.count > 5 {
                Text("+\(events.count - 5) more")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
    
    private func eventBlock(event: GoogleCalendarEvent) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let eventColor = isPersonal ? personalColor : professionalColor
        let displayText = event.isAllDay ? event.summary : "\(formatTime(event.startTime)) \(event.summary)"
        
        return HStack(spacing: 2) {
            Circle()
                .fill(eventColor)
                .frame(width: 4, height: 4)
            
            Text(displayText)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(eventColor.opacity(0.1))
        )
        .highPriorityGesture(
            TapGesture().onEnded { _ in
                onEventTap?(event)
            }
        )
        .onLongPressGesture { onEventTap?(event) }
    }
    
    // MARK: - Helper Functions
    private var monthYearTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentDate)
    }
    
    private var daysInMonth: Int {
        let calendar = Calendar.mondayFirst
        return calendar.range(of: .day, in: .month, for: currentDate)?.count ?? 30
    }
    
    private var firstDayOffset: Int {
        let calendar = Calendar.mondayFirst
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate))!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        return (firstWeekday + 5) % 7 // Convert to Monday-first (Monday = 0)
    }
    
    private func getDayNumber(weekIndex: Int, dayIndex: Int) -> Int {
        return weekIndex * 7 + dayIndex - firstDayOffset + 1
    }
    
    private func getDateForDay(dayNumber: Int) -> Date? {
        guard dayNumber > 0 && dayNumber <= daysInMonth else { return nil }
        let calendar = Calendar.mondayFirst
        var components = calendar.dateComponents([.year, .month], from: currentDate)
        components.day = dayNumber
        return calendar.date(from: components)
    }
    
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

 