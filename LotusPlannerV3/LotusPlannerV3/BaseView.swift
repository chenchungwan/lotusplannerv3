import SwiftUI

enum ViewMode: String, CaseIterable, Hashable {
    case week
}

struct BaseView: View {
    @EnvironmentObject var appPrefs: AppPreferences
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    
    @State private var selectedDate = Date()
    @State private var viewMode: ViewMode = .week
    @State private var selectedCalendarEvent: GoogleCalendarEvent?
    @State private var showingEventDetails = false
    // Task-related state removed since this view only shows calendar events
    
    // Section width management removed since we only show calendar events now
    
    var body: some View {
        mainContent
            .sidebarToggleHidden()
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    principalToolbarContent
                }

                ToolbarItemGroup(placement: .principal) { EmptyView() }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    trailingToolbarButtons
                }
            }
        .sheet(item: Binding<GoogleCalendarEvent?>(
            get: { selectedCalendarEvent },
            set: { selectedCalendarEvent = $0 }
        )) { event in
            CalendarEventDetailsView(event: event) {
                // Handle event deletion if needed
            }
        }
        // Task details sheet removed since this view only shows calendar events
        .task {
            // Initialize selectedDate from navigation manager if available
            selectedDate = navigationManager.currentDate
            await calendarViewModel.loadCalendarData(for: selectedDate)
        }
        .onChange(of: selectedDate) { oldValue, newValue in
            Task {
                await calendarViewModel.loadCalendarData(for: newValue)
            }
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            selectedDate = newValue
        }
    }
    
    // MARK: - Toolbar Content
    private var principalToolbarContent: some View {
        HStack(spacing: 8) {
            SharedNavigationToolbar()
            
            Button(action: { step(-1) }) {
                Image(systemName: "chevron.left")
            }
            
            Button(action: { 
                selectedDate = Date() // Go to today
                navigationManager.updateInterval(.week, date: Date())
            }) {
                Text(titleText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            Button(action: { step(1) }) {
                Image(systemName: "chevron.right")
            }
        }
    }
    
    private var trailingToolbarButtons: some View {
        HStack(spacing: 12) {
            // Day button
            Button(action: {
                navigationManager.updateInterval(.day, date: selectedDate)
                navigationManager.currentDate = selectedDate
            }) {
                Image(systemName: "d.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentInterval == .day && navigationManager.currentView != .baseViewV2 ? .accentColor : .secondary)
            }
            
            // Week button (original BaseView)
            Button(action: {
                navigationManager.switchToCalendar()
                navigationManager.updateInterval(.week, date: selectedDate)
            }) {
                Image(systemName: "w.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentInterval == .week && navigationManager.currentView != .baseViewV2 ? .accentColor : .secondary)
            }
            
            // BaseViewV2 button (immediately after w.circle)
            Button(action: {
                navigationManager.switchToBaseViewV2()
            }) {
                Image(systemName: "v.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentView == .baseViewV2 ? .accentColor : .secondary)
            }
            
            // Month button
            Button(action: {
                navigationManager.updateInterval(.month, date: selectedDate)
                navigationManager.currentDate = selectedDate
            }) {
                Image(systemName: "m.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentInterval == .month && navigationManager.currentView != .baseViewV2 ? .accentColor : .secondary)
            }
            
            // Year button
            Button(action: {
                navigationManager.updateInterval(.year, date: selectedDate)
                navigationManager.currentDate = selectedDate
            }) {
                Image(systemName: "y.circle")
                    .font(.body)
                    .foregroundColor(navigationManager.currentInterval == .year && navigationManager.currentView != .baseViewV2 ? .accentColor : .secondary)
            }

            // Hide Completed toggle
            Button(action: { appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks) }) {
                Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash.circle" : "eye.circle")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            // Add button
            Button(action: { 
                // Add functionality would go here
            }) {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Main Content
    private var mainContent: some View {
        // Main content area with only calendar events (no tasks section)
        VStack(spacing: 0) {
            // Calendar events section - Full width
            ScrollView(.horizontal, showsIndicators: true) {
                customWeekTimelineView
            }
            .clipped() // Ensure content stays within bounds
            .task {
                await calendarViewModel.loadCalendarDataForWeek(containing: selectedDate)
            }
            .onChange(of: selectedDate) { oldValue, newValue in
                Task {
                    await calendarViewModel.loadCalendarDataForWeek(containing: newValue)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
            .padding(.all, 8)
        }
        .frame(minHeight: 0, maxHeight: .infinity)
    }
    }


// MARK: - Helpers

extension BaseView {
    // Task-related views removed since this view only shows calendar events
    
    // MARK: - Custom Week Timeline View
    private var customWeekTimelineView: some View {
        let fixedWidth: CGFloat = 1200 // Fixed width regardless of left section size
        let timeColumnWidth: CGFloat = 50
        let dayColumnWidth = (fixedWidth - timeColumnWidth) / 7
        
        return VStack(spacing: 0) {
            // Header with day labels only
            weekHeaderSection(dayColumnWidth: dayColumnWidth, timeColumnWidth: timeColumnWidth)
            
            // Scrollable content (all-day events and timeline only)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    // All-day events section
                    if hasAnyAllDayEventsInWeek {
                        weekAllDayEventsSection(dayColumnWidth: dayColumnWidth, timeColumnWidth: timeColumnWidth)
                    }
                    
                    // Timeline grid with events
                    weekTimelineSection(dayColumnWidth: dayColumnWidth, timeColumnWidth: timeColumnWidth)
                }
            }
        }
        .frame(width: fixedWidth)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    


    
    // Slider views removed since we only show calendar events now
    

    
    private var titleText: String {
        let calendar = Calendar.mondayFirst
        guard
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start,
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)
        else { return "Week" }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startString = formatter.string(from: weekStart)
        let endString = formatter.string(from: weekEnd)
        
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: selectedDate)
        
        return "\(startString) - \(endString), \(year)"
    }
    
    private func step(_ offset: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) {
            selectedDate = newDate
            navigationManager.updateInterval(.week, date: newDate)
        }
    }
    
    private func getAllEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        let personalEvents = calendarViewModel.personalEvents.filter { event in
            guard let startTime = event.startTime else { return false }
            return Calendar.current.isDate(startTime, inSameDayAs: date)
        }
        
        let professionalEvents = calendarViewModel.professionalEvents.filter { event in
            guard let startTime = event.startTime else { return false }
            return Calendar.current.isDate(startTime, inSameDayAs: date)
        }
        
        return personalEvents + professionalEvents
    }
    

    
    private func getWeekEventsGroupedByDate() -> [Date: [GoogleCalendarEvent]] {
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return [:]
        }
        
        var weekEvents: [Date: [GoogleCalendarEvent]] = [:]
        
        // Generate all days in the week (Monday to Sunday)
        var currentDate = weekInterval.start
        while currentDate < weekInterval.end {
            let dayStart = calendar.startOfDay(for: currentDate)
            let events = getAllEventsForDate(currentDate)
            
            if !events.isEmpty {
                weekEvents[dayStart] = events
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return weekEvents
    }
    
    // MARK: - Week Helper Properties for Custom Timeline
    private var hasAnyAllDayEventsInWeek: Bool {
        let weekEvents = getWeekEventsGroupedByDate()
        return weekDates.contains { date in
            let dayStart = Calendar.current.startOfDay(for: date)
            let events = weekEvents[dayStart] ?? []
            return events.contains { $0.isAllDay || isEvent24Hours($0) }
        }
    }
    
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return []
        }
        
        var days: [Date] = []
        var date = weekInterval.start
        
        // Get Monday to Sunday (7 days)
        for _ in 0..<7 {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        return days
    }
    
    private func isEvent24Hours(_ event: GoogleCalendarEvent) -> Bool {
        guard let startTime = event.startTime,
              let endTime = event.endTime else { return false }
        
        let duration = endTime.timeIntervalSince(startTime)
        let twentyFourHours: TimeInterval = 24 * 60 * 60
        
        return abs(duration - twentyFourHours) < 60
    }
    
    // All task-related functions removed since this view only shows calendar events
    
    // MARK: - Week Header Section
    private func weekHeaderSection(dayColumnWidth: CGFloat, timeColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Time column placeholder
            Spacer()
                .frame(width: timeColumnWidth, height: 60)
                .background(Color(.systemGray6))
            
            // Day headers
            ForEach(weekDates, id: \.self) { date in
                weekDayHeaderView(date: date)
                    .frame(width: dayColumnWidth, height: 60)
                    .background(Color(.systemGray6))
                    .overlay(
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
            }
        }
        .background(Color(.systemBackground))
    }
    
    private func weekDayHeaderView(date: Date) -> some View {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "E" // Mon, Tue, etc.
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d" // 1, 2, 3
        
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        
        return VStack(spacing: 4) {
            Text(dayFormatter.string(from: date))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(isToday ? .white : .secondary)
            
            Text(dateFormatter.string(from: date))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(isToday ? .white : .primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isToday ? Color.blue : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { 
            selectedDate = date 
        }
    }
    
    // MARK: - Week All-Day Events Section
    private func weekAllDayEventsSection(dayColumnWidth: CGFloat, timeColumnWidth: CGFloat) -> some View {
        let weekEvents = getWeekEventsGroupedByDate()
        let maxEvents = weekDates.map { date in
            let dayStart = Calendar.current.startOfDay(for: date)
            let events = weekEvents[dayStart] ?? []
            return events.filter { $0.isAllDay || isEvent24Hours($0) }.count
        }.max() ?? 0
        
        let sectionHeight = max(40, CGFloat(maxEvents) * 24 + 16)
        
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Time column with "All Day" label
                Text("All Day")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: timeColumnWidth, height: sectionHeight)
                    .background(Color(.systemGray6))
                
                // All-day events for each day
                ForEach(weekDates, id: \.self) { date in
                    weekAllDayEventsColumn(date: date, weekEvents: weekEvents)
                        .frame(width: dayColumnWidth, height: sectionHeight)
                        .background(Color(.systemBackground))
                        .overlay(
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                }
            }
            
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 0.5)
        }
    }
    
    private func weekAllDayEventsColumn(date: Date, weekEvents: [Date: [GoogleCalendarEvent]]) -> some View {
        let dayStart = Calendar.current.startOfDay(for: date)
        let events = weekEvents[dayStart] ?? []
        let allDayEvents = events.filter { $0.isAllDay || isEvent24Hours($0) }
        
        return VStack(spacing: 2) {
            ForEach(allDayEvents, id: \.id) { event in
                weekAllDayEventView(event: event)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func weekAllDayEventView(event: GoogleCalendarEvent) -> some View {
        let isPersonal = calendarViewModel.personalEvents.contains { $0.id == event.id }
        let color = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            
            Text(event.summary)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.15))
        )
        .onTapGesture { 
            selectedCalendarEvent = event
            showingEventDetails = true
        }
    }
    
    // MARK: - Week Timeline Section
    private func weekTimelineSection(dayColumnWidth: CGFloat, timeColumnWidth: CGFloat) -> some View {
        let weekEvents = getWeekEventsGroupedByDate()
        let startHour = 6
        let endHour = 22
        let hourHeight: CGFloat = 80
        
        return HStack(spacing: 0) {
            // Time column
            weekTimeColumn(startHour: startHour, endHour: endHour, hourHeight: hourHeight, timeColumnWidth: timeColumnWidth)
                .frame(width: timeColumnWidth)
                .background(Color(.systemGray6))
            
            // Day columns
            ForEach(weekDates, id: \.self) { date in
                weekDayTimelineColumn(
                    date: date, 
                    weekEvents: weekEvents, 
                    dayColumnWidth: dayColumnWidth,
                    startHour: startHour,
                    endHour: endHour,
                    hourHeight: hourHeight
                )
                .overlay(
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 0.5),
                    alignment: .trailing
                )
            }
        }
    }
    
    private func weekTimeColumn(startHour: Int, endHour: Int, hourHeight: CGFloat, timeColumnWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                VStack {
                    Text(formatHour(hour))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                    
                    Spacer()
                }
                .frame(height: hourHeight)
            }
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }
    
    private func weekDayTimelineColumn(date: Date, weekEvents: [Date: [GoogleCalendarEvent]], dayColumnWidth: CGFloat, startHour: Int, endHour: Int, hourHeight: CGFloat) -> some View {
        let dayStart = Calendar.current.startOfDay(for: date)
        let events = weekEvents[dayStart] ?? []
        let timedEvents = events.filter { !$0.isAllDay && !isEvent24Hours($0) }
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        
        return ZStack(alignment: .topLeading) {
            // Background grid
            weekTimelineGrid(startHour: startHour, endHour: endHour, hourHeight: hourHeight)
            
            // Events
            ForEach(timedEvents, id: \.id) { event in
                weekTimedEventView(event: event, dayColumnWidth: dayColumnWidth, startHour: startHour, hourHeight: hourHeight)
            }
            
            // Current time indicator
            if isToday {
                weekCurrentTimeIndicator(startHour: startHour, endHour: endHour, hourHeight: hourHeight)
            }
        }
        .frame(width: dayColumnWidth)
    }
    
    private func weekTimelineGrid(startHour: Int, endHour: Int, hourHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                Rectangle()
                    .fill(Color(.systemBackground))
                    .frame(height: hourHeight)
                    .overlay(
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 0.5)
                            
                            Spacer()
                            
                            Rectangle()
                                .fill(Color(.systemGray6))
                                .frame(height: 0.5)
                                .offset(y: -hourHeight/2)
                        }
                    )
            }
        }
    }
    
    private func weekTimedEventView(event: GoogleCalendarEvent, dayColumnWidth: CGFloat, startHour: Int, hourHeight: CGFloat) -> some View {
        guard let startTime = event.startTime,
              let endTime = event.endTime else {
            return AnyView(EmptyView())
        }
        
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let eventStartHour = startComponents.hour ?? 0
        let startMinute = startComponents.minute ?? 0
        
        let startOffset = CGFloat(eventStartHour - startHour) * hourHeight + 
                         CGFloat(startMinute) * (hourHeight / 60.0)
        
        let duration = endTime.timeIntervalSince(startTime)
        let height = max(20, CGFloat(duration / 3600.0) * hourHeight)
        
        let isPersonal = calendarViewModel.personalEvents.contains { $0.id == event.id }
        let color = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return AnyView(
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: dayColumnWidth - 8, height: height)
                .overlay(
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.summary)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(height > 30 ? 2 : 1)
                        
                        if height > 25 {
                            Text(formatEventTime(startTime))
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                )
                .offset(x: 4, y: startOffset)
                .onTapGesture { 
                    selectedCalendarEvent = event
                    showingEventDetails = true
                }
        )
    }
    
    private func formatEventTime(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: time)
    }
    
    private func weekCurrentTimeIndicator(startHour: Int, endHour: Int, hourHeight: CGFloat) -> some View {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        guard hour >= startHour && hour < endHour else {
            return AnyView(EmptyView())
        }
        
        let yOffset = CGFloat(hour - startHour) * hourHeight + CGFloat(minute) * (hourHeight / 60.0)
        
        return AnyView(
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(x: -3)
                
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 2)
            }
            .offset(y: yOffset)
        )
    }

}



extension ViewMode {
    var displayName: String {
        switch self {
        case .week: return "Week"
        }
    }
}