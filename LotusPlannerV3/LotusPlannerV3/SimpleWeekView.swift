import SwiftUI

struct SimpleWeekView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    
    @State private var selectedCalendarEvent: GoogleCalendarEvent?
    
    // MARK: - Computed Properties
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
            return []
        }
        let start = weekInterval.start
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }
    
    private func getEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        calendarViewModel.events(for: date)
    }
    
    private func isEventPersonal(_ event: GoogleCalendarEvent) -> Bool {
        return calendarViewModel.personalEvents.contains { $0.id == event.id }
    }
    
    private func contentColumnWidth(availableWidth: CGFloat) -> CGFloat {
        // Calculate width to fit all 7 columns in the view
        // Account for padding (12 * 2 = 24) and a bit of margin
        let availableContentWidth = availableWidth - 24
        return availableContentWidth / 7
    }
    
    private func unifiedWeekTimeline(availableWidth: CGFloat) -> some View {
        let columnWidth = contentColumnWidth(availableWidth: availableWidth)
        let timeColumnWidth: CGFloat = 28
        
        // Calculate the maximum height needed for all-day events across all days
        let maxAllDayHeight = weekDates.map { date in
            let eventsForDate = getEventsForDate(date)
            let allDayEvents = eventsForDate.filter { $0.isAllDay }
            return calculateAllDayEventsHeight(for: allDayEvents)
        }.max() ?? 20
        
        return GeometryReader { geometry in
            // Calculate dynamic hour height to fit exactly 10 hours in remaining space
            let availableHeight = geometry.size.height - maxAllDayHeight - 1 // -1 for divider line
            let hourHeight = availableHeight / 10.0 // 10 hours visible
            
            VStack(spacing: 0) {
            // Persistent all-day events row for all 7 days
            HStack(spacing: 0) {
                ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                    let eventsForDate = getEventsForDate(date)
                    let allDayEvents = eventsForDate.filter { $0.isAllDay }
                    
                    allDayEventsRow(
                        events: allDayEvents,
                        personalEvents: calendarViewModel.personalEvents,
                        professionalEvents: calendarViewModel.professionalEvents,
                        personalColor: appPrefs.personalColor,
                        professionalColor: appPrefs.professionalColor,
                        timeColumnWidth: timeColumnWidth
                    )
                    .frame(width: columnWidth, height: maxAllDayHeight)
                    
                    if index < weekDates.count - 1 {
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 1)
                    }
                }
            }
            
            // Divider line
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: timeColumnWidth, height: 1)
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 1)
            }
            
            // Unified scrollable timed events timeline
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            let eventsForDate = getEventsForDate(date)
                            let timedEvents = eventsForDate.filter { !$0.isAllDay }
                            
                            timedEventsColumn(
                                date: date,
                                events: timedEvents,
                                width: columnWidth,
                                hourHeight: hourHeight,
                                timeColumnWidth: timeColumnWidth
                            )
                            
                            if index < weekDates.count - 1 {
                                Rectangle()
                                    .fill(Color(.systemGray4))
                                    .frame(width: 1)
                            }
                        }
                    }
                }
                .frame(height: hourHeight * 10) // Dynamic height for exactly 10 hours
                .onAppear {
                    // Scroll to 8 AM by default
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(8, anchor: .top)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        }
    }
    
    private func timedEventsColumn(date: Date, events: [GoogleCalendarEvent], width: CGFloat, hourHeight: CGFloat, timeColumnWidth: CGFloat) -> some View {
        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Background grid - full 24 hours
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        timeSlot(hour: hour, width: width - timeColumnWidth - 1, timeColumnWidth: timeColumnWidth, hourHeight: hourHeight)
                            .frame(height: hourHeight)
                    }
                    
                    // Final 12a line at the end of the day
                    HStack(spacing: 0) {
                        Text(formatHour(24))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: timeColumnWidth, alignment: .leading)
                        
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 1)
                    }
                    .frame(height: 20)
                }
                
                // Timed events overlay
                let eventLayouts = calculateEventLayouts(events: events, width: width - timeColumnWidth - 1, offsetX: timeColumnWidth + 1, hourHeight: hourHeight, date: date, personalEvents: calendarViewModel.personalEvents, professionalEvents: calendarViewModel.professionalEvents, personalColor: appPrefs.personalColor, professionalColor: appPrefs.professionalColor)
                
                ZStack(alignment: .topLeading) {
                    ForEach(eventLayouts, id: \.event.id) { layout in
                        eventBlock(layout: layout, personalColor: appPrefs.personalColor, professionalColor: appPrefs.professionalColor)
                    }
                    
                    // Current time indicator (red line) - only for today
                    if shouldShowCurrentTimeIndicator(for: date) {
                        currentTimeIndicator(
                            width: width - timeColumnWidth - 1,
                            offsetX: timeColumnWidth + 1,
                            hourHeight: hourHeight,
                            startHour: 0
                        )
                    }
                }
            }
        }
        .frame(width: width, height: CGFloat(24) * hourHeight + 20) // Full 24 hours
    }
    
    private func timedEventsTimeline(date: Date, events: [GoogleCalendarEvent], hourHeight: CGFloat, personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color) -> some View {
        let startHour = 0
        let endHour = 24
        let timeColumnWidth: CGFloat = 28
        let allDayEventsRowHeight: CGFloat = 30
        
        // Separate all-day events from timed events
        let allDayEvents = events.filter { $0.isAllDay }
        let timedEvents = events.filter { !$0.isAllDay }
        
        return VStack(spacing: 0) {
            // All-day events row (always show for alignment)
            allDayEventsRow(events: allDayEvents, personalEvents: personalEvents, professionalEvents: professionalEvents, personalColor: personalColor, professionalColor: professionalColor, timeColumnWidth: timeColumnWidth)
                .frame(height: allDayEventsRowHeight)
            
            // Divider line
            HStack(spacing: 0) {
                // Time column spacer
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: timeColumnWidth, height: 1)
                
                // Content area line
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 1)
            }
            
            // Main timeline with hour grid and timed events
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // Background grid
                    VStack(spacing: 0) {
                        ForEach(startHour..<endHour, id: \.self) { hour in
                            timeSlot(hour: hour, width: geometry.size.width - timeColumnWidth - 1, timeColumnWidth: timeColumnWidth, hourHeight: hourHeight)
                                .frame(height: hourHeight)
                        }
                        
                        // Final 12a line at the end of the day
                        HStack(spacing: 0) {
                            Text(formatHour(endHour))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: timeColumnWidth, alignment: .leading)
                            
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 1)
                        }
                        .frame(height: 20)
                    }
                    
                    // Timed events overlay
                    let eventLayouts = calculateEventLayouts(events: timedEvents, width: geometry.size.width - timeColumnWidth - 1, offsetX: timeColumnWidth + 1, hourHeight: hourHeight, date: date, personalEvents: personalEvents, professionalEvents: professionalEvents, personalColor: personalColor, professionalColor: professionalColor)
                    
                    ZStack(alignment: .topLeading) {
                        ForEach(eventLayouts, id: \.event.id) { layout in
                            eventBlock(layout: layout, personalColor: personalColor, professionalColor: professionalColor)
                        }
                    }
                }
            }
            .frame(height: CGFloat(endHour - startHour) * hourHeight + 20)
        }
    }
    
    private func allDayEventsRow(events: [GoogleCalendarEvent], personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color, timeColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Time column spacer
            Rectangle()
                .fill(Color.clear)
                .frame(width: timeColumnWidth)
            
            // Events content area
            if events.isEmpty {
                // Empty spacer to maintain alignment
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(events, id: \.id) { event in
                        let isPersonal = personalEvents.contains { $0.id == event.id }
                        let color = isPersonal ? personalColor : professionalColor
                        
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color)
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
                                .fill(color.opacity(0.1))
                        )
                        .onTapGesture { 
                            selectedCalendarEvent = event
                        }
                        .onLongPressGesture { 
                            selectedCalendarEvent = event
                        }
                    }
                }
            }
            
            Spacer()
        }
        .background(Color(.systemGray6).opacity(0.3))
    }
    
    private func timeSlot(hour: Int, width: CGFloat, timeColumnWidth: CGFloat, hourHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Time label (left-aligned to match TimelineComponent)
            VStack {
                Text(formatHour(hour))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: timeColumnWidth, alignment: .leading)
                Spacer()
            }
            
            // Hour line and background (matching TimelineComponent)
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
    }
    
    private func calculateEventLayouts(events: [GoogleCalendarEvent], width: CGFloat, offsetX: CGFloat, hourHeight: CGFloat, date: Date, personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color) -> [EventLayout] {
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
                
                var calendar = Calendar.current
                calendar.timeZone = TimeZone.current
                calendar.locale = Locale.current
                
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
                let endHour = endComponents.hour ?? 0
                let endMinute = endComponents.minute ?? 0
                
                // Use the same calculation as TimelineComponent
                let startOffset = CGFloat(startHour - 0) * hourHeight + 
                                 CGFloat(startMinute) * (hourHeight / 60.0)
                
                // Calculate height based on duration for this day
                let dayDuration = dayEndTime.timeIntervalSince(dayStartTime)
                let height = max(20, CGFloat(dayDuration / 3600.0) * hourHeight)
                
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
    
    private func eventBlock(layout: EventLayout, personalColor: Color, professionalColor: Color) -> some View {
        let color = layout.isPersonal ? personalColor : professionalColor
        
        return VStack(alignment: .leading, spacing: 2) {
            Text(layout.event.summary)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(width: layout.width, height: layout.height, alignment: .leading)
        .background(color.opacity(0.8))
        .cornerRadius(4)
        .offset(x: layout.xOffset, y: layout.startOffset)
        .onTapGesture { 
            selectedCalendarEvent = layout.event
        }
        .onLongPressGesture { 
            selectedCalendarEvent = layout.event
        }
    }
    
    private func allDayEventsSection(events: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(events, id: \.id) { event in
                let isPersonal = calendarViewModel.personalEvents.contains { $0.id == event.id }
                let color = isPersonal ? personalColor : professionalColor
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    
                    Text(event.summary)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(4)
            }
        }
    }
    
    private struct EventLayout {
        let event: GoogleCalendarEvent
        let startOffset: CGFloat
        let height: CGFloat
        let width: CGFloat
        let xOffset: CGFloat
        let isPersonal: Bool
    }
    
    private func formatHour(_ hour: Int) -> String {
        let normalizedHour = ((hour % 24) + 24) % 24
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: normalizedHour, minute: 0, second: 0, of: Date()) ?? Date()
        var timeString = formatter.string(from: date).lowercased()
        timeString = timeString.replacingOccurrences(of: "m", with: "")
        if hour == 24 { return "12a" }
        return timeString
    }
    
    private func calculateAllDayEventsHeight(for events: [GoogleCalendarEvent]) -> CGFloat {
        if events.isEmpty {
            return 20 // Minimum height for empty state
        }
        
        // Each event takes: text height + vertical padding (2*2) + spacing (2)
        let eventHeight: CGFloat = 16 + 4 + 2 // text height + padding + spacing
        let totalHeight = CGFloat(events.count) * eventHeight + 4 // +4 for VStack padding
        
        return max(totalHeight, 20) // Minimum 20pt height
    }
    
    private func shouldShowCurrentTimeIndicator(for date: Date) -> Bool {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        calendar.locale = Locale.current
        let now = Date()
        
        // Only show on today's date
        guard calendar.isDate(date, inSameDayAs: now) else { return false }
        
        // Only show if current time is within our visible range (8 AM - 6 PM)
        let currentHour = calendar.component(.hour, from: now)
        return currentHour >= 8 && currentHour < 18
    }
    
    private func currentTimeIndicator(width: CGFloat, offsetX: CGFloat, hourHeight: CGFloat, startHour: Int) -> some View {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        calendar.locale = Locale.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        
        // Use the same calculation as TimelineComponent
        let yOffset = CGFloat(currentHour - 0) * hourHeight + CGFloat(currentMinute) * (hourHeight / 60.0)
        
        return Rectangle()
            .fill(Color.red)
            .frame(width: width, height: 2)
            .offset(x: offsetX, y: yOffset)
    }
    
    private func weekDayColumnSticky(date: Date, isToday: Bool) -> some View {
        Button(action: {
            // Navigate to day view for this date
            navigationManager.updateInterval(.day, date: date)
            navigationManager.switchToCalendar()
        }) {
            VStack(alignment: .center, spacing: 2) {
            Text(dayOfWeekAbbrev(from: date))
                .font(.system(size: 14, weight: .semibold))
                .fontWeight(.semibold)
                .foregroundColor(isToday ? .white : .secondary)
            
            Text(formatDateShort(from: date))
                .font(.system(size: 16, weight: .bold))
                .fontWeight(.bold)
                .foregroundColor(isToday ? .white : .primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isToday ? Color.blue : Color.clear)
    }
    
    private func dayOfWeekAbbrev(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
    
    private func formatDateShort(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy"
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            GlobalNavBar()
                .background(.ultraThinMaterial)
            
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        // Fixed header row with day dates (7 columns to match content)
                        HStack(spacing: 0) {
                            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                                let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
                                weekDayColumnSticky(date: date, isToday: isToday)
                                    .frame(width: contentColumnWidth(availableWidth: geometry.size.width))
                                    .background(Color(.systemGray6))
                                    .id("day_\(index)")
                                
                                // Divider between days (except for the last one)
                                if index < weekDates.count - 1 {
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 1)
                                }
                            }
                        }
                        .frame(height: 60)
                        .background(Color(.systemBackground))
                        
                    // Unified scrollable timeline for all 7 days
                    unifiedWeekTimeline(availableWidth: geometry.size.width)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // Scroll to today's position
                            let calendar = Calendar.mondayFirst
                            let today = Date()
                            
                            if let index = weekDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: today) }) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo("day_\(index)", anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sidebarToggleHidden()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .task {
            // Load calendar data for the current week
            await calendarViewModel.loadCalendarDataForWeek(containing: navigationManager.currentDate)
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            Task {
                // Load calendar data when the date changes
                await calendarViewModel.loadCalendarDataForWeek(containing: newValue)
            }
        }
        .sheet(item: Binding<GoogleCalendarEvent?>(
            get: { selectedCalendarEvent },
            set: { selectedCalendarEvent = $0 }
        )) { ev in
            let accountKind: GoogleAuthManager.AccountKind = calendarViewModel.personalEvents.contains(where: { $0.id == ev.id }) ? .personal : .professional
            AddItemView(
                currentDate: ev.startTime ?? Date(),
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                existingEvent: ev,
                accountKind: accountKind,
                showEventOnly: true
            )
        }
    }
}

