import SwiftUI

struct WeekTimelineComponent: View {
    // MARK: - Properties
    let currentDate: Date
    let weekEvents: [Date: [GoogleCalendarEvent]]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let personalTaskLists: [GoogleTaskList]
    let personalTasks: [String: [GoogleTask]]
    let professionalTaskLists: [GoogleTaskList]
    let professionalTasks: [String: [GoogleTask]]
    // hideCompletedTasks removed
    let fixedStartHour: Int?
    let showTasksSection: Bool

    
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    let onDayTap: ((Date) -> Void)?
    let onTaskTap: ((GoogleTask, String) -> Void)?
    
    // MARK: - State
    @State private var currentTime = Date()
    @State private var currentTimeTimer: Timer?
    @State private var tasksRowHeight: CGFloat = 120 // Default height for tasks section
    @State private var isDraggingSlider: Bool = false
    @State private var dragStartHeight: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy? = nil
    
    // MARK: - Constants
    private let hourHeight: CGFloat = 80
    private let defaultStartHour = 0
    private let defaultEndHour = 24
    private let timeColumnWidth: CGFloat = 50
    private let dayHeaderHeight: CGFloat = 60
    private let allDayEventHeight: CGFloat = 24
    private let minTasksRowHeight: CGFloat = 20 // Minimum height for tasks section (allows near-complete collapse)
    private let minTimelineHeight: CGFloat = 100 // Minimum height for timeline section
    
    // MARK: - Initializer
    init(currentDate: Date, weekEvents: [Date: [GoogleCalendarEvent]], personalEvents: [GoogleCalendarEvent], professionalEvents: [GoogleCalendarEvent], personalColor: Color, professionalColor: Color, personalTaskLists: [GoogleTaskList] = [], personalTasks: [String: [GoogleTask]] = [:], professionalTaskLists: [GoogleTaskList] = [], professionalTasks: [String: [GoogleTask]] = [:], onEventTap: ((GoogleCalendarEvent) -> Void)? = nil, onDayTap: ((Date) -> Void)? = nil, onTaskTap: ((GoogleTask, String) -> Void)? = nil, showTasksSection: Bool = true, fixedStartHour: Int? = nil) {
        self.currentDate = currentDate
        self.weekEvents = weekEvents
        self.personalEvents = personalEvents
        self.professionalEvents = professionalEvents
        self.personalColor = personalColor
        self.professionalColor = professionalColor
        self.personalTaskLists = personalTaskLists
        self.personalTasks = personalTasks
        self.professionalTaskLists = professionalTaskLists
        self.professionalTasks = professionalTasks
        // hideCompletedTasks removed

        self.onEventTap = onEventTap
        self.onDayTap = onDayTap
        self.onTaskTap = onTaskTap
        self.showTasksSection = showTasksSection
        self.fixedStartHour = fixedStartHour
    }
    
    // MARK: - Data Models
    struct EventLayout {
        let event: GoogleCalendarEvent
        let startOffset: CGFloat
        let height: CGFloat
        let width: CGFloat
        let xOffset: CGFloat
        let isPersonal: Bool
    }
    
    struct DayData {
        let date: Date
        let isToday: Bool
        let events: [GoogleCalendarEvent]
        let allDayEvents: [GoogleCalendarEvent]
        let timedEvents: [GoogleCalendarEvent]
        let tasks: [GoogleTask]
    }
    
    // MARK: - Main Body
    var body: some View {
        GeometryReader { geometry in
            let dayColumnWidth = geometry.size.width * 0.3 // Each day column is 30% of screen width

            // Calculate maximum allowed height for tasks section
            // Available space = total height - header height - slider height - minimum timeline height
            let maxTasksRowHeight = geometry.size.height - dayHeaderHeight - 20 - minTimelineHeight

            VStack(spacing: 0) {
                // Single horizontal scroll view containing all sections
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Fixed header with day labels
                            headerSection(dayColumnWidth: dayColumnWidth)

                            // Optional top tasks section with slider
                            if showTasksSection {
                                // Fixed daily tasks section at top (conditionally shown)
                                dailyTasksSection(dayColumnWidth: dayColumnWidth)
                                    .padding(.top, 2) // Small gap between header and tasks to prevent overlap

                                // Slider between tasks and events
                                sliderSection(maxHeight: maxTasksRowHeight)
                            }

                            // Scrollable content (all-day events and timeline)
                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(spacing: 0) {
                                    // All-day events section
                                    if hasAnyAllDayEvents {
                                        allDayEventsSection(dayColumnWidth: dayColumnWidth)
                                    }

                                    // Timeline grid with events
                                    timelineSection(dayColumnWidth: dayColumnWidth)
                                }
                            }
                        }
                        .frame(width: geometry.size.width + (dayColumnWidth * 7) - timeColumnWidth)
                    }
                    .onAppear {
                        scrollProxy = proxy
                    }
                }
            }
        }
        .onAppear {
            startTimer()
            // Initialize tasks row height based on content if not already set
            if tasksRowHeight == 120 {
                let personalHeight = calculateRowHeight(for: personalTasksByDate)
                let professionalHeight = calculateRowHeight(for: professionalTasksByDate)
                let calculatedHeight = personalHeight + professionalHeight + 0.5 // Add separator height
                tasksRowHeight = max(minTasksRowHeight, calculatedHeight)
            }
        }
        .onDisappear { stopTimer() }
    }
    
    // MARK: - Computed Properties
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start else {
            return []
        }
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }
    
    private var timelineHours: (start: Int, end: Int) {
        let calendar = Calendar.current
        var earliestHour = defaultStartHour
        var latestHour = defaultEndHour
        
        // Check all events across the week to find the earliest and latest times
        for date in weekDates {
            let events = weekEvents[date] ?? []
            let timedEvents = events.filter { !$0.isAllDay && !isEvent24Hours($0) }
            
            for event in timedEvents {
                if let startTime = event.startTime {
                    let startHour = calendar.component(.hour, from: startTime)
                    earliestHour = min(earliestHour, startHour)
                }
                
                if let endTime = event.endTime {
                    let endHour = calendar.component(.hour, from: endTime)
                    // If minutes are > 0, we need to show the next hour too
                    let endMinute = calendar.component(.minute, from: endTime)
                    let adjustedEndHour = endMinute > 0 ? endHour + 1 : endHour
                    latestHour = max(latestHour, adjustedEndHour)
                }
            }
        }
        
        // If a fixed start hour is provided, honor it (bounded to 0...24)
        if let fixedStartHour = fixedStartHour {
            let boundedStart = min(24, max(0, fixedStartHour))
            return (
                start: boundedStart,
                end: min(24, max(latestHour, defaultEndHour))
            )
        }
        // Ensure we have at least the default range and cap at 24-hour bounds (retain existing behavior)
        return (
            start: max(0, min(earliestHour, defaultStartHour)),
            end: min(24, max(latestHour, defaultEndHour))
        )
    }
    
    private var startHour: Int {
        return timelineHours.start
    }
    
    private var endHour: Int {
        return timelineHours.end
    }
    
    private var hasAnyAllDayEvents: Bool {
        weekDates.contains { date in
            let events = weekEvents[date] ?? []
            return events.contains { $0.isAllDay || isEvent24Hours($0) }
        }
    }
    
    private func dayData(for date: Date) -> DayData {
        let events = weekEvents[date] ?? []
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        let allDayEvents = events.filter { $0.isAllDay || isEvent24Hours($0) }
        let timedEvents = events.filter { !$0.isAllDay && !isEvent24Hours($0) && isEventInTimeRange($0) }
        let personalTasksForDate = filteredTasksForDate(personalTasks.values.flatMap { $0 }, date: date)
        let professionalTasksForDate = filteredTasksForDate(professionalTasks.values.flatMap { $0 }, date: date)
        let tasks = personalTasksForDate + professionalTasksForDate
        
        return DayData(
            date: date,
            isToday: isToday,
            events: events,
            allDayEvents: allDayEvents,
            timedEvents: timedEvents,
            tasks: tasks
        )
    }
    
    // MARK: - Header Section
    private func headerSection(dayColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Time column placeholder
            Spacer()
                .frame(width: timeColumnWidth, height: dayHeaderHeight)
                .background(Color.gray.opacity(0.1))

            // Day headers (now part of main horizontal scroll)
            HStack(spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    let data = dayData(for: date)
                    dayHeaderView(data: data)
                        .frame(width: dayColumnWidth, height: dayHeaderHeight)
                        .background(Color.gray.opacity(0.1))
                        .overlay(
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
    
    // MARK: - Daily Tasks Section
    private func dailyTasksSection(dayColumnWidth: CGFloat) -> some View {
        // Calculate optimal heights for each row based on content
        let personalRowHeight = calculateOptimalRowHeight(for: personalTasksByDate, isPersonal: true, dayColumnWidth: dayColumnWidth)
        let professionalRowHeight = calculateOptimalRowHeight(for: professionalTasksByDate, isPersonal: false, dayColumnWidth: dayColumnWidth)

        // Use the user's preferred height as the maximum, but allow shrinking for less content
        let maxIndividualHeight = (tasksRowHeight - 0.5) / 2 // Account for separator line
        let constrainedPersonalHeight = min(personalRowHeight, maxIndividualHeight)
        let constrainedProfessionalHeight = min(professionalRowHeight, maxIndividualHeight)

        return VStack(spacing: 0) {
            // Personal Tasks Row
            dailyTasksRow(
                title: "Personal",
                color: personalColor,
                tasks: personalTasksByDate,
                dayColumnWidth: dayColumnWidth,
                rowHeight: constrainedPersonalHeight,
                optimalHeight: personalRowHeight,
                isPersonal: true
            )

            // Thin separator line between personal and professional
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 0.5)

            // Professional Tasks Row
            dailyTasksRow(
                title: "Professional",
                color: professionalColor,
                tasks: professionalTasksByDate,
                dayColumnWidth: dayColumnWidth,
                rowHeight: constrainedProfessionalHeight,
                optimalHeight: professionalRowHeight,
                isPersonal: false
            )
        }
        .frame(height: constrainedPersonalHeight + constrainedProfessionalHeight + 0.5)
    }
    
    private func dailyTasksRow(title: String, color: Color, tasks: [Date: [GoogleTask]], dayColumnWidth: CGFloat, rowHeight: CGFloat, optimalHeight: CGFloat, isPersonal: Bool) -> some View {
        HStack(spacing: 0) {
            // Task type indicator circle with checkmark
            VStack {
                if rowHeight > 20 {
                    Circle()
                        .fill(color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                    Spacer()
                } else {
                    // Condensed indicator for collapsed state
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                    Spacer()
                }
            }
            .frame(width: timeColumnWidth, height: rowHeight)
            .background(Color.gray.opacity(0.1))
            
            // Tasks for each day (now part of main horizontal scroll)
            HStack(spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    let dayTasks = tasks[Calendar.current.startOfDay(for: date)] ?? []
                    dailyTasksCell(
                        tasks: dayTasks,
                        color: color,
                        rowHeight: rowHeight,
                        optimalHeight: optimalHeight,
                        isPersonal: isPersonal
                    )
                    .frame(width: dayColumnWidth, height: rowHeight)
                    .background(Color(uiColor: .systemBackground))
                    .overlay(
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
                }
            }
        }
    }
    
    private func dailyTasksCell(tasks: [GoogleTask], color: Color, rowHeight: CGFloat, optimalHeight: CGFloat, isPersonal: Bool) -> some View {
        let taskLists = isPersonal ? personalTaskLists : professionalTaskLists
        let tasksDict = isPersonal ? personalTasks : professionalTasks
        // Always enable scrolling when there are tasks to ensure each cell can scroll independently
        let needsScrolling = !tasks.isEmpty && rowHeight > 20
        
        if rowHeight > 40 {
            let groupedTasks = groupTasksByList(tasks, color: color, taskLists: taskLists, tasksDict: tasksDict)
            
            if !groupedTasks.isEmpty {
                let cardsContent = VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(groupedTasks.keys.sorted()), id: \.self) { taskListTitle in
                        if let taskGroup = groupedTasks[taskListTitle] {
                            WeeklyTaskListCard(
                                title: taskListTitle,
                                tasks: taskGroup.tasks,
                                color: taskGroup.color,
                                rowHeight: min(rowHeight, 80), // Limit individual card height for better display
                                onTaskTap: { task in
                                    // Find the task list ID for this task
                                    if let taskListId = personalTasks.first(where: { $0.value.contains { $0.id == task.id } })?.key {
                                        onTaskTap?(task, taskListId)
                                    } else if let taskListId = professionalTasks.first(where: { $0.value.contains { $0.id == task.id } })?.key {
                                        onTaskTap?(task, taskListId)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                
                if needsScrolling {
                    // Scrollable content when optimal height exceeds available space
                    return AnyView(
                        ScrollView(.vertical, showsIndicators: false) {
                            cardsContent
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(height: rowHeight)
                        .clipped()
                    )
                } else {
                    // Non-scrollable content when it fits
                    return AnyView(
                        cardsContent
                            .frame(maxWidth: .infinity, maxHeight: rowHeight, alignment: .top)
                    )
                }
            } else {
                // Empty state
                return AnyView(
                    Spacer()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                )
            }
        } else if rowHeight > 20 {
            // Reduced height: show condensed cards
            let groupedTasks = groupTasksByList(tasks, color: color, taskLists: taskLists, tasksDict: tasksDict)
            
            let condensedContent = VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(groupedTasks.keys.sorted()), id: \.self) { taskListTitle in
                    if let taskGroup = groupedTasks[taskListTitle] {
                        WeeklyTaskListCard(
                            title: taskListTitle,
                            tasks: taskGroup.tasks,
                            color: taskGroup.color,
                            rowHeight: rowHeight,
                            onTaskTap: { task in
                                // Find the task list ID for this task
                                if let taskListId = personalTasks.first(where: { $0.value.contains { $0.id == task.id } })?.key {
                                    onTaskTap?(task, taskListId)
                                } else if let taskListId = professionalTasks.first(where: { $0.value.contains { $0.id == task.id } })?.key {
                                    onTaskTap?(task, taskListId)
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            
            if needsScrolling {
                return AnyView(
                    ScrollView(.vertical, showsIndicators: false) {
                        condensedContent
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(height: rowHeight)
                    .clipped()
                )
            } else {
                return AnyView(
                    condensedContent
                        .frame(maxWidth: .infinity, maxHeight: rowHeight, alignment: .top)
                )
            }
        } else if !tasks.isEmpty {
            // Condensed view: just show task count when collapsed
            return AnyView(
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                    
                    Text("\(tasks.count) task\(tasks.count == 1 ? "" : "s")")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            )
        } else {
            return AnyView(
                Spacer()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            )
        }
    }
    
    private func calculateRowHeight(for tasksByDate: [Date: [GoogleTask]]) -> CGFloat {
        let maxTasksInAnyDay = tasksByDate.values.map { $0.count }.max() ?? 0
        
        // Minimum height of 40 points, then add 16 points for each task
        // 16 points accounts for: caption2 font (~12) + spacing (2) + some buffer (2)
        let baseHeight: CGFloat = 40
        let taskHeight: CGFloat = 16
        let calculatedHeight = baseHeight + CGFloat(maxTasksInAnyDay) * taskHeight
        
        // Ensure minimum height and reasonable maximum
        return max(40, min(calculatedHeight, 200))
    }
    
    private func calculateOptimalRowHeight(for tasksByDate: [Date: [GoogleTask]], isPersonal: Bool, dayColumnWidth: CGFloat) -> CGFloat {
        let taskLists = isPersonal ? personalTaskLists : professionalTaskLists
        let tasksDict = isPersonal ? personalTasks : professionalTasks
        
        var maxRequiredHeight: CGFloat = minTasksRowHeight
        
        // Check each day in the week to find the maximum height needed
        for date in weekDates {
            let dayStartDate = Calendar.current.startOfDay(for: date)
            let dayTasks = tasksByDate[dayStartDate] ?? []
            
            if !dayTasks.isEmpty {
                let groupedTasks = groupTasksByList(dayTasks, color: isPersonal ? personalColor : professionalColor, taskLists: taskLists, tasksDict: tasksDict)
                
                var dayHeight: CGFloat = 8 // Base padding
                
                for (_, taskGroup) in groupedTasks {
                    // Calculate height for each task list card
                    let cardBaseHeight: CGFloat = 35 // Header + padding
                    let taskRowHeight: CGFloat = 18 // Height per task row
                    let actualTaskCount = max(1, taskGroup.tasks.count) // Use actual task count
                    
                    let cardHeight = cardBaseHeight + (CGFloat(actualTaskCount) * taskRowHeight)
                    dayHeight += cardHeight + 3 // Add spacing between cards
                }
                
                maxRequiredHeight = max(maxRequiredHeight, dayHeight)
            }
        }
        
        // Add some buffer and ensure reasonable bounds
        let bufferedHeight = maxRequiredHeight + 10
        return max(minTasksRowHeight, min(bufferedHeight, 300)) // Cap at 300pt max
    }
    
    // MARK: - Slider Section
    private func sliderSection(maxHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Left column (matching time column width)
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: timeColumnWidth, height: 20)
            
            // Draggable slider area
            Rectangle()
                .fill(isDraggingSlider ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2))
                .frame(height: 20)
                .overlay(
                    HStack {
                        // Draggable handle with visual indicators
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(isDraggingSlider ? Color.gray.opacity(0.5) : Color.gray.opacity(0.4))
                                .frame(width: 30, height: isDraggingSlider ? 6 : 4)
                                .cornerRadius(3)
                                .animation(.easeInOut(duration: 0.2), value: isDraggingSlider)
                            
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundColor(isDraggingSlider ? Color.gray.opacity(0.5) : Color.gray.opacity(0.4))
                                .scaleEffect(isDraggingSlider ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: isDraggingSlider)
                        }
                    }
                )
                .animation(.easeInOut(duration: 0.2), value: isDraggingSlider)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDraggingSlider {
                                isDraggingSlider = true
                                dragStartHeight = tasksRowHeight
                            }
                            let newHeight = dragStartHeight + value.translation.height
                            tasksRowHeight = max(minTasksRowHeight, min(maxHeight, newHeight))
                        }
                        .onEnded { _ in
                            isDraggingSlider = false
                            dragStartHeight = 0
                        }
                )
        }
    }

    // MARK: - All-Day Events Section
    private func allDayEventsSection(dayColumnWidth: CGFloat) -> some View {
        let maxEvents = weekDates.map { date in
            dayData(for: date).allDayEvents.count
        }.max() ?? 0

        let sectionHeight = max(40, CGFloat(maxEvents) * allDayEventHeight + 16)

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Time column with "All Day" label
                Text("All Day")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: timeColumnWidth, height: sectionHeight)
                    .background(Color.gray.opacity(0.1))

                // All-day events for each day (now part of main horizontal scroll)
                HStack(spacing: 0) {
                    ForEach(weekDates, id: \.self) { date in
                        let data = dayData(for: date)
                        allDayEventsColumn(data: data)
                            .frame(width: dayColumnWidth, height: sectionHeight)
                            .background(Color(uiColor: .systemBackground))
                            .overlay(
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 0.5),
                                alignment: .trailing
                            )
                    }
                }
            }

            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 0.5)
        }
    }
    
    // MARK: - Timeline Section
    private func timelineSection(dayColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Time column
            timeColumn()
                .frame(width: timeColumnWidth)
                .background(Color.gray.opacity(0.1))

            // Day columns (now part of main horizontal scroll)
            HStack(spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    let data = dayData(for: date)
                    dayTimelineColumn(data: data, width: dayColumnWidth)
                        .overlay(
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                }
            }
        }
    }
    
    // MARK: - Individual Components
    private func dayHeaderView(data: DayData) -> some View {
        return VStack(spacing: 4) {
            // Standardized day of week format: MON, TUE, etc.
            Text(DateFormatter.standardDayOfWeek.string(from: data.date).uppercased())
                .font(DateDisplayStyle.bodyFont)
                .fontWeight(.semibold)
                .foregroundColor(data.isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.secondaryColor)
            
            // Standardized date format: m/d/yy
            Text(DateFormatter.standardDate.string(from: data.date))
                .font(DateDisplayStyle.subtitleFont)
                .fontWeight(.bold)
                .foregroundColor(data.isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.primaryColor)
            

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(data.isToday ? Color.blue : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { onDayTap?(data.date) }
    }
    
    private func allDayEventsColumn(data: DayData) -> some View {
        VStack(spacing: 2) {
            ForEach(data.allDayEvents, id: \.id) { event in
                allDayEventView(event: event)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func allDayEventView(event: GoogleCalendarEvent) -> some View {
        let isPersonal = personalEvents.contains { $0.id == event.id }
        let color = isPersonal ? personalColor : professionalColor
        
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
        .onTapGesture { onEventTap?(event) }
    }
    
    private func timeColumn() -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                timeSlotLabel(hour: hour)
                    .frame(height: hourHeight)
            }
            
            // Final 12a label at the end of the day
            Text(formatHour(endHour))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
                .frame(height: 20) // Small height for the final label
        }
    }
    
    private func timeSlotLabel(hour: Int) -> some View {
        VStack {
            Text(formatHour(hour))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
            
            Spacer()
        }
    }
    
    private func dayTimelineColumn(data: DayData, width: CGFloat) -> some View {
        let eventLayouts = calculateEventLayouts(events: data.timedEvents, width: width)
        
        return ZStack(alignment: .topLeading) {
            // Background grid
            timelineGrid()
            
            // Events
            ForEach(eventLayouts, id: \.event.id) { layout in
                timedEventView(layout: layout)
            }
            
            // Current time indicator
            if data.isToday {
                currentTimeIndicator()
            }
        }
        .frame(width: width)
    }
    
    private func timelineGrid() -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                Rectangle()
                    .fill(Color(uiColor: .systemBackground))
                    .frame(height: hourHeight)
                    .overlay(
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 0.5)
                            
                            Spacer()
                            
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 0.5)
                                .offset(y: -hourHeight/2)
                        }
                    )
            }
            
            // Final 12a line at the end of the day
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 0.5)
        }
    }
    
    private func timedEventView(layout: EventLayout) -> some View {
        let color = layout.isPersonal ? personalColor : professionalColor
        
        return RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: layout.width, height: layout.height)
            .overlay(
                VStack(alignment: .leading, spacing: 1) {
                    Text(layout.event.summary)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(layout.height > 30 ? 2 : 1)
                    
                    if layout.height > 25, let startTime = layout.event.startTime {
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
            .offset(x: layout.xOffset, y: layout.startOffset)
            .onTapGesture { onEventTap?(layout.event) }
    }
    
    private func currentTimeIndicator() -> some View {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentTime)
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
    
    // MARK: - Helper Functions
    private func formatHour(_ hour: Int) -> String {
        if hour == endHour { return "12a" }
        let normalizedHour = ((hour % 24) + 24) % 24
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: normalizedHour, minute: 0, second: 0, of: Date()) ?? Date()
        let timeString = formatter.string(from: date).lowercased()
        return timeString.replacingOccurrences(of: "m", with: "")
    }
    
    private func formatEventTime(_ time: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: time)
    }
    
    private func isEventInTimeRange(_ event: GoogleCalendarEvent) -> Bool {
        guard let startTime = event.startTime else { return false }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour], from: startTime)
        let hour = components.hour ?? 0
        return hour >= startHour && hour < endHour
    }
    
    private func isEvent24Hours(_ event: GoogleCalendarEvent) -> Bool {
        guard let startTime = event.startTime,
              let endTime = event.endTime else { return false }
        
        let duration = endTime.timeIntervalSince(startTime)
        let twentyFourHours: TimeInterval = 24 * 60 * 60 // 24 hours in seconds
        
        // Check if the event duration is exactly 24 hours (with small tolerance for floating point precision)
        return abs(duration - twentyFourHours) < 60 // Within 1 minute tolerance
    }
    
    // MARK: - Task Grouping
    private var personalTasksByDate: [Date: [GoogleTask]] {
        groupTasksByDate(personalTasks)
    }
    
    // MARK: - Task List Grouping
    private struct TaskGroup {
        let tasks: [GoogleTask]
        let color: Color
    }
    
    private func groupTasksByList(_ tasks: [GoogleTask], color: Color, taskLists: [GoogleTaskList], tasksDict: [String: [GoogleTask]]) -> [String: TaskGroup] {
        var groupedTasks: [String: [GoogleTask]] = [:]
        
        // Group tasks by their actual task list
        for taskList in taskLists {
            if let tasksInList = tasksDict[taskList.id] {
                // Filter the tasks for this specific day that belong to this task list
                let relevantTasks = tasks.filter { task in
                    tasksInList.contains { $0.id == task.id }
                }
                
                if !relevantTasks.isEmpty {
                    groupedTasks[taskList.title] = relevantTasks
                }
            }
        }
        
        return groupedTasks.mapValues { TaskGroup(tasks: $0, color: color) }
    }
    
    private var professionalTasksByDate: [Date: [GoogleTask]] {
        groupTasksByDate(professionalTasks)
    }
    
    private func groupTasksByDate(_ tasksDict: [String: [GoogleTask]]) -> [Date: [GoogleTask]] {
        let calendar = Calendar.current
        var groupedTasks: [Date: [GoogleTask]] = [:]
        
        // Flatten all tasks from all task lists first
        let allTasks = tasksDict.values.flatMap { $0 }
        
        // Group tasks by each day in the week using the same logic as day view
        for date in weekDates {
            let tasksForDate = filteredTasksForDate(allTasks, date: date)
            if !tasksForDate.isEmpty {
                groupedTasks[calendar.startOfDay(for: date)] = tasksForDate
            }
        }
        
        return groupedTasks
    }
    
    // Use the exact same filtering logic as the day view
    private func filteredTasksForDate(_ tasks: [GoogleTask], date: Date) -> [GoogleTask] {
        let calendar = Calendar.current
        
        var filteredTasks = tasks
        
        // No longer filtering by hide completed tasks setting
        
        // Then filter tasks based on date logic (same as day view)
        filteredTasks = filteredTasks.compactMap { task in
            // For completed tasks, only show them on their completion date
            if task.isCompleted {
                guard let completionDate = task.completionDate else { return nil }
                return calendar.isDate(completionDate, inSameDayAs: date) ? task : nil
            } else {
                // For incomplete tasks, show them on due date OR if overdue (only on today)
                guard let dueDate = task.dueDate else { return nil }
                
                let isDueOnViewedDate = calendar.isDate(dueDate, inSameDayAs: date)
                let isViewingToday = calendar.isDate(date, inSameDayAs: Date())
                let startOfDueDate = calendar.startOfDay(for: dueDate)
                let startOfToday = calendar.startOfDay(for: Date())
                let isOverdueRelativeToToday = startOfDueDate < startOfToday
                
                // Show tasks on their due date OR if we're viewing today and the task is overdue
                return isDueOnViewedDate || (isViewingToday && isOverdueRelativeToToday) ? task : nil
            }
        }
        
        return filteredTasks
    }
    
    // MARK: - Event Layout Calculation
    private func calculateEventLayouts(events: [GoogleCalendarEvent], width: CGFloat) -> [EventLayout] {
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
                let _ = endComponents.hour ?? 0
                let _ = endComponents.minute ?? 0
                
                let startOffset = CGFloat(startHour - self.startHour) * hourHeight + 
                                 CGFloat(startMinute) * (hourHeight / 60.0)
                
                let duration = endTime.timeIntervalSince(startTime)
                let height = max(20, CGFloat(duration / 3600.0) * hourHeight)
                
                let isPersonal = personalEvents.contains { $0.id == event.id }
                
                let layout = EventLayout(
                    event: event,
                    startOffset: startOffset,
                    height: height,
                    width: columnWidth - 4, // Leave small gap
                    xOffset: CGFloat(index) * columnWidth + 2,
                    isPersonal: isPersonal
                )
                
                layouts.append(layout)
            }
        }
        
        return layouts
    }
    
    // MARK: - Timer Functions
    private func startTimer() {
        currentTimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            currentTime = Date()
        }
        currentTime = Date()
    }
    
    private func stopTimer() {
        currentTimeTimer?.invalidate()
        currentTimeTimer = nil
    }
}

// MARK: - Weekly Task List Card Component
struct WeeklyTaskListCard: View {
    let title: String
    let tasks: [GoogleTask]
    let color: Color
    let rowHeight: CGFloat
    let onTaskTap: ((GoogleTask) -> Void)?
    

    
    private var visibleTasks: [GoogleTask] {
        return tasks // Show all tasks
    }
    

    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Card header - always show for identification
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            
            // Task list
            VStack(alignment: .leading, spacing: 1) {
                ForEach(visibleTasks, id: \.id) { task in
                    WeeklyTaskRow(task: task, color: color, isCompact: rowHeight <= 60, onTap: onTaskTap)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Weekly Task Row Component
struct WeeklyTaskRow: View {
    let task: GoogleTask
    let color: Color
    let isCompact: Bool
    let onTap: ((GoogleTask) -> Void)?
    
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(task.isCompleted ? Color.gray : color)
                .frame(width: isCompact ? 3 : 4, height: isCompact ? 3 : 4)

            Text(task.title)
                .font(isCompact ? .body : .title3)
                .foregroundColor(task.isCompleted ? .gray : .primary)
                .strikethrough(task.isCompleted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?(task)
        }
    }
    

}

// MARK: - Preview
struct WeekTimelineComponent_Previews: PreviewProvider {
    static var previews: some View {
        WeekTimelineComponent(
            currentDate: Date(),
            weekEvents: [:],
            personalEvents: [],
            professionalEvents: [],
            personalColor: .purple,
            professionalColor: .green,
            personalTaskLists: [],
            personalTasks: [:],
            professionalTaskLists: [],
            professionalTasks: [:],
            // hideCompletedTasks removed
        )
        .previewLayout(.sizeThatFits)
    }
}