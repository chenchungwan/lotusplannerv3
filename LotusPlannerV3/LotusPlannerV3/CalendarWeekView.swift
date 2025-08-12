import SwiftUI

struct CalendarWeekView: View {
    let currentDate: Date
    let onDateSelected: (Date) -> Void
    
    @ObservedObject private var eventManager = EventManager.shared
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    
    @State private var selectedEvent: GoogleCalendarEvent?
    @State private var weekEvents: [Date: [GoogleCalendarEvent]] = [:]
    @State private var personalEvents: [GoogleCalendarEvent] = []
    @State private var professionalEvents: [GoogleCalendarEvent] = []
    
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
        .task {
            // Load events
            weekEvents = await eventManager.getEvents(for: .week(currentDate))
            personalEvents = await eventManager.getPersonalEvents(for: .week(currentDate))
            professionalEvents = await eventManager.getProfessionalEvents(for: .week(currentDate))
            
            // Load tasks
            await tasksViewModel.loadTasks()
        }
        .sheet(item: $selectedEvent) { event in
            CalendarEventDetailsView(event: event) {
                // Handle event deletion if needed
                if let selectedEvent = selectedEvent {
                    weekEvents.forEach { (date, events) in
                        if let index = events.firstIndex(where: { $0.id == selectedEvent.id }) {
                            weekEvents[date]?.remove(at: index)
                        }
                    }
                }
            }
        }
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
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE d"
        
        return VStack(spacing: 4) {
            Text(dayFormatter.string(from: date))
                .font(.caption)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(isToday ? .white : .primary)
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
        let events = weekEvents[calendar.startOfDay(for: date)] ?? []
        
        return HStack(spacing: 0) {
            TimelineBaseView(
                date: date,
                events: events,
                personalEvents: personalEvents,
                professionalEvents: professionalEvents,
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                config: TimelineConfig(
                    startHour: 6,
                    endHour: 22,
                    hourHeight: 80,
                    timeColumnWidth: 50,
                    showCurrentTime: true,
                    showAllDayEvents: true
                ),
                onEventTap: { event in
                    selectedEvent = event
                }
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
