import SwiftUI

struct SimpleWeekView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    
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
        let calendar = Calendar.mondayFirst
        return (calendarViewModel.personalEvents + calendarViewModel.professionalEvents).filter { event in
            if let startTime = event.startTime {
                return calendar.isDate(startTime, inSameDayAs: date)
            }
            // For all-day events, check if the all-day event applies to this date
            return event.isAllDay
        }
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
    
    private func weekDayRowEventsColumn(date: Date) -> some View {
        let eventsForDate = getEventsForDate(date)
        
        // Create timeline content without its own ScrollView
        return timelineContent(
            date: date,
            events: eventsForDate,
            personalEvents: calendarViewModel.personalEvents,
            professionalEvents: calendarViewModel.professionalEvents,
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor
        )
        .padding(.horizontal, 4)
        .frame(height: 991) // Fixed height: all-day row (30) + divider (1) + 24 hours * 40pt (960)
    }
    
    private func timelineContent(date: Date, events: [GoogleCalendarEvent], personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color) -> some View {
        let hourHeight: CGFloat = 40
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
                    let eventLayouts = calculateEventLayouts(events: timedEvents, width: geometry.size.width - timeColumnWidth - 1, offsetX: timeColumnWidth + 1, personalEvents: personalEvents, professionalEvents: professionalEvents, personalColor: personalColor, professionalColor: professionalColor)
                    
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
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(events, id: \.id) { event in
                        let isPersonal = personalEvents.contains { $0.id == event.id }
                        let color = isPersonal ? personalColor : professionalColor
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(color)
                                .frame(width: 6, height: 6)
                            
                            Text(event.summary)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                }
            }
            
            Spacer()
        }
        .background(Color(.systemGray6).opacity(0.3))
    }
    
    private func timeSlot(hour: Int, width: CGFloat, timeColumnWidth: CGFloat, hourHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(formatHour(hour))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: timeColumnWidth, alignment: .leading)
            
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: 1)
        }
    }
    
    private func calculateEventLayouts(events: [GoogleCalendarEvent], width: CGFloat, offsetX: CGFloat, personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color) -> [EventLayout] {
        let hourHeight: CGFloat = 40
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
                
                let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                
                let startHour = startComponents.hour ?? 0
                let startMinute = startComponents.minute ?? 0
                let endHour = endComponents.hour ?? 0
                let endMinute = endComponents.minute ?? 0
                
                let startMinutes = CGFloat(startHour * 60 + startMinute)
                let endMinutes = CGFloat(endHour * 60 + endMinute)
                
                let startOffset = startMinutes * (hourHeight / 60.0)
                let height = max(20, (endMinutes - startMinutes) * (hourHeight / 60.0))
                
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
    
    private func weekDayColumnSticky(date: Date, isToday: Bool) -> some View {
        Button(action: {
            // Navigate to day view for this date
            navigationManager.updateInterval(.day, date: date)
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
                        
                    // Scrollable content with 7 Event columns (one for each day) - single scroll
                    ScrollView(.vertical, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                                // Events column for each day
                                weekDayRowEventsColumn(date: date)
                                .frame(width: contentColumnWidth(availableWidth: geometry.size.width))
                                .background(Color(.systemBackground))
                                
                                // Divider between days (except for the last one)
                                if index < weekDates.count - 1 {
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 1)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
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
    }
}

