import SwiftUI


struct CalendarWeekView: View {
    let currentDate: Date
    let onDateSelected: (Date) -> Void
    
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    
    @State private var selectedEvent: GoogleCalendarEvent? // PERFORMANCE ENHANCEMENT: Loading state
    
    private let calendar = Calendar.mondayFirst
    
    var body: some View {
        VStack(spacing: 0) {
            // Week header
            weekHeader
            
            // Timeline
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(weekDays, id: \.self) { date in
                        dayRow(date)
                    }
                }
            }
        }
        .padding(.leading, 2) // Add 2px left padding
        .task {
            // Load calendar data for the week
            await calendarViewModel.loadCalendarDataForWeek(containing: currentDate)
            
            // Load tasks
            if !tasksViewModel.isLoading {
                await tasksViewModel.loadTasks()
            }
        }
        // Event details sheet removed
    }
    
    private var weekHeader: some View {
        HStack(spacing: 0) {
            // Time column header
            Text("Time")
                .font(.caption)
                .frame(width: 50)
            
            // Day headers
            ForEach(weekDays, id: \.self) { date in
                dayHeader(date)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private func dayHeader(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isCurrentWeek = calendar.isDate(date, equalTo: currentDate, toGranularity: .weekOfYear)
        
        return VStack(spacing: 4) {
            // Standardized format: MON
            Text(DateFormatter.standardDayOfWeek.string(from: date).uppercased())
                .font(DateDisplayStyle.subtitleFont)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(DateDisplayStyle.dateColor(isToday: isToday, isCurrentPeriod: isCurrentWeek))
            
            // Standardized date format: 12/25/24
            Text(DateFormatter.standardDate.string(from: date))
                .font(DateDisplayStyle.subtitleFont)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(DateDisplayStyle.dateColor(isToday: isToday, isCurrentPeriod: isCurrentWeek))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(isToday ? Color.blue : Color.clear)
        .cornerRadius(8)
        .onTapGesture {
            onDateSelected(date)
        }
    }
    
    private func dayRow(_ date: Date) -> some View {
        let allEvents = calendarViewModel.personalEvents + calendarViewModel.professionalEvents
        let dayEvents = allEvents.filter { event in
            guard let startTime = event.startTime else { return event.isAllDay }
            
            if event.isAllDay {
                // For all-day events, check if the date falls within the event's date range
                guard let endTime = event.endTime else { return false }
                
                // For all-day events, Google Calendar typically sets the end time to the start of the next day
                // But for single-day events, end.date might equal start.date
                // So we need to check if the date falls within [startTime, endTime)
                let startDay = calendar.startOfDay(for: startTime)
                let endDay = calendar.startOfDay(for: endTime)
                let dateDay = calendar.startOfDay(for: date)
                
                // If endDay equals startDay (single-day event), check if date matches
                if endDay == startDay {
                    return dateDay == startDay
                }
                // Otherwise, check if date is within [startDay, endDay)
                return dateDay >= startDay && dateDay < endDay
            } else {
                // For timed events, check if the date falls within the event's date range
                guard let endTime = event.endTime else {
                    // If no end time, only show on start date
                    return calendar.isDate(startTime, inSameDayAs: date)
                }
                
                let startDay = calendar.startOfDay(for: startTime)
                let endDay = calendar.startOfDay(for: endTime)
                let dateDay = calendar.startOfDay(for: date)
                
                // If event is on the same day, show only if date matches
                if endDay == startDay {
                    return dateDay == startDay
                }
                
                // Otherwise, show if date is within [startDay, endDay]
                // Include both start and end days
                return dateDay >= startDay && dateDay <= endDay
            }
        }
        
        return HStack(spacing: 0) {
            TimelineComponent(
                date: date,
                events: dayEvents,
                personalEvents: calendarViewModel.personalEvents,
                professionalEvents: calendarViewModel.professionalEvents,
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                onEventTap: { event in selectedEvent = event }
            )
        }
    }
    
    private var weekDays: [Date] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: currentDate) else {
            return []
        }
        
        return (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: weekInterval.start)
        }
    }
}

#Preview {
    CalendarWeekView(currentDate: Date()) { _ in }
}
