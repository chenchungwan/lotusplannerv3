import SwiftUI

struct CalendarMonthView: View {
    let currentDate: Date
    let onDateSelected: (Date) -> Void
    
    @ObservedObject private var eventManager = EventManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    
    @State private var selectedEvent: GoogleCalendarEvent?
    @State private var monthEvents: [Date: [GoogleCalendarEvent]] = [:]
    @State private var personalEvents: [GoogleCalendarEvent] = []
    @State private var professionalEvents: [GoogleCalendarEvent] = []
    
    private let calendar = Calendar.mondayFirst
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Month grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
                    // Day headers
                    ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                        Text(day)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .frame(height: 30)
                    }
                    
                    // Day cells
                    ForEach(monthDays, id: \.self) { date in
                        if let date = date {
                            monthDayCell(date, cellWidth: geometry.size.width / 7)
                        } else {
                            Color.clear
                                .frame(width: geometry.size.width / 7)
                        }
                    }
                }
            }
        }
        .task {
            // Load events with filtering options
            let options = EventFilterOptions(hideRecurringEvents: appPrefs.hideRecurringEventsInMonth)
            monthEvents = await eventManager.getEvents(for: .month(currentDate), options: options)
            personalEvents = await eventManager.getPersonalEvents(for: .month(currentDate), options: options)
            professionalEvents = await eventManager.getProfessionalEvents(for: .month(currentDate), options: options)
        }
        .sheet(item: $selectedEvent) { event in
            CalendarEventDetailsView(event: event) {
                // Handle event deletion if needed
                if let selectedEvent = selectedEvent {
                    monthEvents.forEach { (date, events) in
                        if let index = events.firstIndex(where: { $0.id == selectedEvent.id }) {
                            monthEvents[date]?.remove(at: index)
                        }
                    }
                }
            }
        }
    }
    
    private var monthDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end) else {
            return []
        }
        
        let numberOfDays = calendar.dateComponents([.day], from: monthFirstWeek.start, to: monthLastWeek.end).day ?? 0
        let startDate = monthFirstWeek.start
        
        return (0..<numberOfDays).map { day in
            calendar.date(byAdding: .day, value: day, to: startDate)
        }
    }
    
    private func monthDayCell(_ date: Date, cellWidth: CGFloat) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isCurrentMonth = calendar.isDate(date, equalTo: currentDate, toGranularity: .month)
        let events = monthEvents[calendar.startOfDay(for: date)] ?? []
        
        return VStack(spacing: 2) {
            // Day number
            Text("\(calendar.component(.day, from: date))")
                .font(.callout)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(isToday ? .white : (isCurrentMonth ? .primary : .secondary))
                .frame(width: 24, height: 24)
                .background(isToday ? Circle().fill(Color.blue) : nil)
            
            // Events
            VStack(spacing: 1) {
                ForEach(events.prefix(3)) { event in
                    monthEventDot(for: event)
                }
                
                if events.count > 3 {
                    Text("+\(events.count - 3)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .frame(width: cellWidth, height: 60)
        .contentShape(Rectangle())
        .onTapGesture {
            onDateSelected(date)
        }
    }
    
    private func monthEventDot(for event: GoogleCalendarEvent) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let color = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            
            Text(event.summary)
                .font(.caption2)
                .lineLimit(1)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onTapGesture {
            selectedEvent = event
        }
    }
}

#Preview {
    CalendarMonthView(currentDate: Date()) { _ in }
}
