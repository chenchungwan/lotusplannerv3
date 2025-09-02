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
    @State private var isLoadingEvents = false // PERFORMANCE ENHANCEMENT: Loading state
    
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
            // PERFORMANCE ENHANCEMENT: Progressive loading with loading state
            isLoadingEvents = true
            
            let options = EventFilterOptions()
            
            // FUNCTIONALITY PRESERVED: Same loading logic with loading state
            weekEvents = await eventManager.getEvents(for: .week(currentDate), options: options)
            personalEvents = await eventManager.getPersonalEvents(for: .week(currentDate), options: options)
            professionalEvents = await eventManager.getProfessionalEvents(for: .week(currentDate), options: options)
            
            // DEBUG: Print loaded events to verify fix
            print("📅 CalendarWeekView: Loaded events for week:")
            print("  Total weekEvents dictionary has \(weekEvents.count) date entries")
            for (date, events) in weekEvents.sorted(by: { $0.key < $1.key }) {
                print("  \(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)): \(events.count) events")
                for event in events.prefix(2) {
                    print("    - \(event.summary)")
                }
            }
            
            // DEBUG: Also check what dates we're expecting for the week
            print("📅 Week days we're displaying:")
            for day in weekDays {
                let startOfDay = calendar.startOfDay(for: day)
                let eventsForDay = weekEvents[startOfDay]?.count ?? 0
                print("  \(DateFormatter.localizedString(from: day, dateStyle: .short, timeStyle: .none)) (startOfDay key: \(DateFormatter.localizedString(from: startOfDay, dateStyle: .short, timeStyle: .none))): \(eventsForDay) events")
            }
            
            isLoadingEvents = false
            
            // Load tasks (only if not already loading) - FUNCTIONALITY PRESERVED
            if !tasksViewModel.isLoading {
                await tasksViewModel.loadTasks()
            }
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
        let startOfDay = calendar.startOfDay(for: date)
        let events = weekEvents[startOfDay] ?? []
        
        // DEBUG: Print what we're looking for vs what we have
        if weekEvents.count > 0 {
            print("🔍 dayRow for \(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)):")
            print("  Looking for key: \(DateFormatter.localizedString(from: startOfDay, dateStyle: .short, timeStyle: .none)) \(startOfDay)")
            print("  Found \(events.count) events")
            print("  Available keys in weekEvents:")
            for key in weekEvents.keys.sorted() {
                print("    - \(DateFormatter.localizedString(from: key, dateStyle: .short, timeStyle: .none)) \(key): \(weekEvents[key]?.count ?? 0) events")
            }
        }
        
        return HStack(spacing: 0) {
            // FUNCTIONALITY PRESERVED: Same TimelineBaseView with optional loading overlay
            ZStack {
                TimelineBaseView(
                    date: date,
                    events: events,
                    personalEvents: personalEvents,
                    professionalEvents: professionalEvents,
                    personalColor: appPrefs.personalColor,
                    professionalColor: appPrefs.professionalColor,
                    config: TimelineConfig(
                        startHour: 0,
                        endHour: 24,
                        hourHeight: 80,
                        timeColumnWidth: 50,
                        showCurrentTime: true,
                        showAllDayEvents: true
                    ),
                    onEventTap: { event in
                        selectedEvent = event
                    }
                )
                
                // PERFORMANCE ENHANCEMENT: Subtle loading indicator (non-intrusive)
                if isLoadingEvents && events.isEmpty {
                    VStack {
                        ProgressView()
                            .scaleEffect(0.8)
                            .opacity(0.6)
                        Text("Loading events...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .opacity(0.6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground).opacity(0.8))
                }
            }
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
