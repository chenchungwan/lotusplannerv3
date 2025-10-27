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
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    init(currentDate: Date, monthEvents: [Date: [GoogleCalendarEvent]], personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color, onEventTap: ((GoogleCalendarEvent) -> Void)? = nil, onDayTap: ((Date) -> Void)? = nil) {
        self.currentDate = currentDate
        self.monthEvents = monthEvents
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.onEventTap = onEventTap
        self.onDayTap = onDayTap
    }
    
    // MARK: - Priority 1: Adaptive Configuration
    private func adaptiveConfig(columnWidth: CGFloat) -> (fontSize: Font, showTime: Bool, maxVisibleEvents: Int) {
        switch columnWidth {
        case ..<40:  // Very small screens (iPhone SE portrait)
            return (.caption2, false, 2)
        case 40..<55:  // Small screens
            return (.caption, false, 3)
        case 55..<70:  // Medium screens
            return (.footnote, true, 3)
        default:  // Large screens (iPad)
            return (.body, true, 5)
        }
    }
    
    // MARK: - Priority 2: Responsive Day Names
    private func dayNames(columnWidth: CGFloat) -> [String] {
        if columnWidth < 45 {
            return ["M", "T", "W", "T", "F", "S", "S"]
        } else if columnWidth < 60 {
            return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        } else {
            return ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        }
    }
    
    // MARK: - Priority 4: Adaptive Spacing & Heights
    private var adaptiveMinHeight: CGFloat {
        switch (horizontalSizeClass, verticalSizeClass) {
        case (.compact, .compact):  // iPhone landscape
            return 60
        case (.compact, .regular):  // iPhone portrait
            return 70
        default:  // iPad
            return 80
        }
    }
    
    private var adaptiveWeekSpacing: CGFloat {
        horizontalSizeClass == .compact ? 6 : 10
    }
    
    private var adaptiveEventSpacing: CGFloat {
        horizontalSizeClass == .compact ? 1 : 2
    }
    
    private func adaptivePadding(columnWidth: CGFloat) -> CGFloat {
        columnWidth < 50 ? 2 : 4
    }
    
    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 7
            let config = adaptiveConfig(columnWidth: columnWidth)
            
            // Calculate weeks needed for this month
            let weeksNeeded = calculateWeeksNeeded()
            
            // Calculate available height for grid (subtract header ~30pt)
            let availableHeight = geometry.size.height - 30
            let preferredCellHeight = availableHeight / CGFloat(weeksNeeded)
            
            VStack(spacing: 0) {
                // Month header with day names
                monthHeader(columnWidth: columnWidth, config: config)
                
                // Month grid with expanded cells - scrollable if content exceeds space
                ScrollView(.vertical, showsIndicators: false) {
                    monthGrid(columnWidth: columnWidth, config: config, preferredCellHeight: preferredCellHeight)
                }
            }
        }
    }
    
    // MARK: - Month Header
    private func monthHeader(columnWidth: CGFloat, config: (fontSize: Font, showTime: Bool, maxVisibleEvents: Int)) -> some View {
        // Day names header with responsive names
        HStack(spacing: 0) {
            ForEach(Array(dayNames(columnWidth: columnWidth).enumerated()), id: \.offset) { index, dayName in
                Text(dayName)
                    .font(config.fontSize)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: columnWidth, height: 30)
                    .background(Color(.systemGray5))
            }
        }
    }
    
    // Calculate how many weeks are needed for the month
    private func calculateWeeksNeeded() -> Int {
        let calendar = Calendar.mondayFirst
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate))!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let offset = (firstWeekday + 5) % 7 // Convert to Monday-first
        
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentDate)?.count ?? 30
        let totalDaysShown = offset + daysInMonth
        let weeks = (totalDaysShown + 6) / 7
        return max(weeks, 5) // Minimum 5 weeks
    }
    
    // MARK: - Month Grid
    private func monthGrid(columnWidth: CGFloat, config: (fontSize: Font, showTime: Bool, maxVisibleEvents: Int), preferredCellHeight: CGFloat) -> some View {
        let weeksNeeded = calculateWeeksNeeded()
        return VStack(spacing: adaptiveWeekSpacing) {
            ForEach(0..<weeksNeeded, id: \.self) { weekIndex in
                weekRow(weekIndex: weekIndex, columnWidth: columnWidth, config: config, preferredHeight: preferredCellHeight)
            }
        }
    }
    
    private func weekRow(weekIndex: Int, columnWidth: CGFloat, config: (fontSize: Font, showTime: Bool, maxVisibleEvents: Int), preferredHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<7, id: \.self) { dayIndex in
                dayCell(weekIndex: weekIndex, dayIndex: dayIndex, columnWidth: columnWidth, config: config, preferredHeight: preferredHeight)
            }
        }
    }
    
    private func dayCell(weekIndex: Int, dayIndex: Int, columnWidth: CGFloat, config: (fontSize: Font, showTime: Bool, maxVisibleEvents: Int), preferredHeight: CGFloat) -> some View {
        let dayNumber = getDayNumber(weekIndex: weekIndex, dayIndex: dayIndex)
        let date = getDateForDay(dayNumber: dayNumber)
        let isValidDay = dayNumber > 0 && dayNumber <= daysInMonth
        let isToday = isValidDay && date != nil && Calendar.current.isDate(date!, inSameDayAs: Date())
        let isCurrentMonth = isValidDay
        let padding = adaptivePadding(columnWidth: columnWidth)
        
        return VStack(alignment: .leading, spacing: 0) {
            if isValidDay, let dayDate = date {
                // Day number header
                Text("\(dayNumber)")
                    .font(config.fontSize)
                    .fontWeight(isToday ? .bold : .medium)
                    .foregroundColor(isToday ? .white : (isCurrentMonth ? .primary : .secondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, padding)
                    .padding(.top, padding)
                    .background(isToday ? Color.blue : Color.clear)
                
                // Events area - shows limited events based on config
                eventsArea(for: dayDate, columnWidth: columnWidth, config: config)
                    .padding(.bottom, padding)
                
                // Spacer to push content to top and expand cell
                Spacer()
            } else {
                // Empty day cell
                Color.clear
            }
        }
        .frame(width: columnWidth)
        .frame(minHeight: max(adaptiveMinHeight, preferredHeight), maxHeight: preferredHeight)
        .background(isCurrentMonth ? Color(.systemBackground) : Color(.systemGray6).opacity(0.3))
        .contentShape(Rectangle())
        .onTapGesture {
            if let validDate = date {
                onDayTap?(validDate)
            }
        }
    }
    
    // MARK: - Priority 3: Events Area with Smart Overflow
    private func eventsArea(for date: Date, columnWidth: CGFloat, config: (fontSize: Font, showTime: Bool, maxVisibleEvents: Int)) -> some View {
        let events = monthEvents[date] ?? []
        let sortedEvents = events.sorted { first, second in
            // Sort all-day events first, then by start time
            if first.isAllDay && !second.isAllDay { return true }
            if !first.isAllDay && second.isAllDay { return false }
            return (first.startTime ?? Date.distantPast) < (second.startTime ?? Date.distantPast)
        }
        
        let maxVisible = config.maxVisibleEvents
        let visibleEvents = Array(sortedEvents.prefix(maxVisible))
        let hiddenCount = sortedEvents.count - maxVisible
        let padding = adaptivePadding(columnWidth: columnWidth)
        
        return VStack(alignment: .leading, spacing: adaptiveEventSpacing) {
            ForEach(visibleEvents, id: \.id) { event in
                eventBlock(event: event, columnWidth: columnWidth, config: config)
            }
            
            // Show "+N more" indicator for overflow events
            if hiddenCount > 0 {
                Text("+\(hiddenCount) more")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, padding)
                    .padding(.vertical, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, padding)
        .padding(.top, padding)
    }
    
    // MARK: - Priority 5: Compact Event Display (No Dot, No Time)
    private func eventBlock(event: GoogleCalendarEvent, columnWidth: CGFloat, config: (fontSize: Font, showTime: Bool, maxVisibleEvents: Int)) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let eventColor = isPersonal ? personalColor : professionalColor
        let padding = adaptivePadding(columnWidth: columnWidth)
        
        // Very small screens: just colored bar
        if columnWidth < 40 {
            return AnyView(
                Rectangle()
                    .fill(eventColor)
                    .frame(height: 3)
                    .cornerRadius(1.5)
                    .padding(.horizontal, padding)
                    .onTapGesture {
                        onEventTap?(event)
                    }
            )
        }
        
        // Display only event summary (no time, no dot)
        let displayText = event.summary
        
        return AnyView(
            Text(displayText)
                .font(config.fontSize)
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, padding)
                .padding(.vertical, columnWidth < 50 ? 0.5 : 1)
                .background(
                    RoundedRectangle(cornerRadius: columnWidth < 50 ? 3 : 5)
                        .fill(eventColor.opacity(columnWidth < 50 ? 0.15 : 0.1))
                )
                .highPriorityGesture(
                    TapGesture().onEnded { _ in
                        onEventTap?(event)
                    }
                )
                .onLongPressGesture { onEventTap?(event) }
        )
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

 