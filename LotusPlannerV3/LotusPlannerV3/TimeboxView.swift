import SwiftUI
import Combine

struct TimeboxView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var calendarVM = DataManager.shared.calendarViewModel
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State private var selectedEvent: GoogleCalendarEvent?
    @State private var taskSheetSelection: TimeboxTaskSelection?
    @State private var weeklyEventsCache: [Date: [GoogleCalendarEvent]] = [:]
    @State private var weeklyTasksCache: [Date: [String: [GoogleTask]]] = [:]
    @State private var cachedMaxAllDayHeight: CGFloat = 20
    @State private var cachedWeekStart: Date?
    
    struct TimeboxTaskSelection: Identifiable {
        let id: String
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    
    // MARK: - Computed Properties
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
            return []
        }
        let start = weekInterval.start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    
    private func refreshWeekCaches(force: Bool = false) {
        guard !weekDates.isEmpty else { return }
        guard let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
            return
        }
        let normalizedWeekStart = weekInterval.start
        if !force, let cachedStart = cachedWeekStart, Calendar.mondayFirst.isDate(cachedStart, inSameDayAs: normalizedWeekStart) {
            return
        }
        cachedWeekStart = normalizedWeekStart
        
        var eventsCache: [Date: [GoogleCalendarEvent]] = [:]
        var tasksCache: [Date: [String: [GoogleTask]]] = [:]
        
        for date in weekDates {
            eventsCache[date] = getAllEventsForDate(date)
            tasksCache[date] = getTasksForDate(date)
        }
        
        weeklyEventsCache = eventsCache
        weeklyTasksCache = tasksCache
        cachedMaxAllDayHeight = calculateMaxAllDayHeight(eventsCache: eventsCache, tasksCache: tasksCache)
    }
    
    // MARK: - Adaptive Layout Properties
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    private func visibleDaysCount(for geometry: GeometryProxy) -> Int {
        if isCompact {
            // iPhone: 1 day in portrait, 2 in landscape
            let isLandscape = geometry.size.width > geometry.size.height
            return isLandscape ? 2 : 1
        } else {
            // For screens larger than iPad (laptops): Show all 7 days
            // iPad Pro 12.9" landscape is ~1024 points, laptops typically 1280+
            if geometry.size.width > 1200 {
                return 7
            }
            // iPad: Show 3 days in portrait, 5 in landscape
            // Detect landscape by checking if width > height
            let isLandscape = geometry.size.width > geometry.size.height
            return isLandscape ? 5 : 3
        }
    }
    
    private func dayColumnWidth(availableWidth: CGFloat, visibleDays: Int) -> CGFloat {
        // Account for padding (12 * 2 = 24)
        let availableContentWidth = availableWidth - 24
        return availableContentWidth / CGFloat(visibleDays)
    }
    
    private func totalContentWidth(availableWidth: CGFloat, visibleDays: Int) -> CGFloat {
        // Total width for all 7 days
        return dayColumnWidth(availableWidth: availableWidth, visibleDays: visibleDays) * 7
    }
    
    private func getAllEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        calendarVM.events(for: date)
    }
    
    private func getTasksForDate(_ date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.mondayFirst
        var filteredTasks: [String: [GoogleTask]] = [:]
        
        // Combine personal and professional tasks
        let allTasks = tasksVM.personalTasks.merging(tasksVM.professionalTasks) { (personal, _) in personal }
        
        for (listId, tasks) in allTasks {
            // Filter out completed tasks if hideCompletedTasks is enabled
            var tasksToFilter = tasks
            if appPrefs.hideCompletedTasks {
                tasksToFilter = tasks.filter { !$0.isCompleted }
            }
            
            let dateFilteredTasks = tasksToFilter.filter { task in
                // For completed tasks, show on completion date
                if task.isCompleted {
                    guard let completionDate = task.completionDate else { return false }
                    return calendar.isDate(completionDate, inSameDayAs: date)
                }
                
                // For incomplete tasks, show on due date
                guard let dueDate = task.dueDate else { return false }
                return calendar.isDate(dueDate, inSameDayAs: date)
            }
            
            if !dateFilteredTasks.isEmpty {
                filteredTasks[listId] = dateFilteredTasks
            }
        }
        
        return filteredTasks
    }
    
    private func weekDayColumnHeader(date: Date, isToday: Bool) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(dayOfWeekAbbrev(from: date))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isToday ? .white : .secondary)
            
            Text(formatDateShort(from: date))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(isToday ? .white : .primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(isToday ? Color.blue : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            // Navigate to the selected day's day view
            navigationManager.switchToCalendar()
            navigationManager.updateInterval(.day, date: date)
        }
    }
    
    private func dayOfWeekAbbrev(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
    
    private func formatDateShort(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Global Navigation Bar
            GlobalNavBar()
                .background(.ultraThinMaterial)
            
            GeometryReader { geometry in
                let availableWidth = geometry.size.width
                let visibleDays = visibleDaysCount(for: geometry)
                let columnWidth = dayColumnWidth(availableWidth: availableWidth, visibleDays: visibleDays)
                let contentWidth = totalContentWidth(availableWidth: availableWidth, visibleDays: visibleDays)
                
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            if weekDates.count == 7 {
                                // Fixed header row with day dates (7 columns)
                                HStack(spacing: 0) {
                                    ForEach(0..<weekDates.count, id: \.self) { index in
                                        let date = weekDates[index]
                                        let calendar = Calendar.mondayFirst
                                        let isToday = calendar.isDate(date, inSameDayAs: Date())
                                        weekDayColumnHeader(date: date, isToday: isToday)
                                            .frame(width: columnWidth)
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
                                .frame(width: contentWidth, height: 60)
                                .background(Color(.systemBackground))
                                
                                // Unified scrollable timeline for all 7 days with TimeboxComponent
                                ScrollView(.vertical, showsIndicators: true) {
                                    HStack(alignment: .top, spacing: 0) {
                                        ForEach(0..<weekDates.count, id: \.self) { index in
                                            if index < weekDates.count {
                                                timeboxColumn(for: weekDates[index], index: index, availableWidth: availableWidth, columnWidth: columnWidth)
                                            }
                                        }
                                    }
                                    .frame(width: contentWidth)
                                    .padding(.horizontal, 12)
                                }
                            } else {
                                // Fallback if week dates couldn't be calculated
                                Text("Unable to load week dates")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(width: contentWidth)
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
            await calendarVM.loadCalendarDataForWeek(containing: navigationManager.currentDate)
            refreshWeekCaches(force: true)
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            Task {
                // Load calendar data when the date changes
                await calendarVM.loadCalendarDataForWeek(containing: newValue)
            }
            refreshWeekCaches(force: true)
        }
        .onAppear {
            refreshWeekCaches(force: true)
        }
        .onReceive(calendarVM.$personalEvents) { _ in
            refreshWeekCaches(force: true)
        }
        .onReceive(calendarVM.$professionalEvents) { _ in
            refreshWeekCaches(force: true)
        }
        .onReceive(tasksVM.$personalTasks) { _ in
            refreshWeekCaches(force: true)
        }
        .onReceive(tasksVM.$professionalTasks) { _ in
            refreshWeekCaches(force: true)
        }
        .onReceive(appPrefs.$hideCompletedTasks) { _ in
            refreshWeekCaches(force: true)
        }
        .sheet(item: Binding<GoogleCalendarEvent?>(
            get: { selectedEvent },
            set: { selectedEvent = $0 }
        )) { ev in
            let accountKind: GoogleAuthManager.AccountKind = calendarVM.personalEvents.contains(where: { $0.id == ev.id }) ? .personal : .professional
            AddItemView(
                currentDate: ev.startTime ?? Date(),
                tasksViewModel: tasksVM,
                calendarViewModel: calendarVM,
                appPrefs: appPrefs,
                existingEvent: ev,
                accountKind: accountKind,
                showEventOnly: true
            )
        }
        .sheet(item: $taskSheetSelection) { sel in
            TaskDetailsView(
                task: sel.task,
                taskListId: sel.listId,
                accountKind: sel.accountKind,
                accentColor: sel.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksVM.personalTaskLists,
                professionalTaskLists: tasksVM.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksVM,
                onSave: { updatedTask in
                    Task {
                        await tasksVM.updateTask(updatedTask, in: sel.listId, for: sel.accountKind)
                    }
                },
                onDelete: {
                    Task {
                        // Delete the task
                        await tasksVM.deleteTask(sel.task, from: sel.listId, for: sel.accountKind)
                        // Also delete the time window for this task
                        TaskTimeWindowManager.shared.deleteTimeWindow(for: sel.task.id)
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksVM.moveTask(updatedTask, from: sel.listId, to: targetListId, for: sel.accountKind)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksVM.crossAccountMoveTask(updatedTask, from: (sel.accountKind, sel.listId), to: (targetAccountKind, targetListId))
                    }
                }
            )
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // MARK: - Helper Functions
    private func splitTasksByAccount(_ tasksForDate: [String: [GoogleTask]]) -> (personal: [String: [GoogleTask]], professional: [String: [GoogleTask]]) {
        var personalTasks: [String: [GoogleTask]] = [:]
        var professionalTasks: [String: [GoogleTask]] = [:]
        
        for (listId, tasks) in tasksForDate {
            // Determine if this list is personal or professional
            if tasksVM.personalTasks[listId] != nil {
                personalTasks[listId] = tasks
            } else if tasksVM.professionalTasks[listId] != nil {
                professionalTasks[listId] = tasks
            }
        }
        
        return (personalTasks, professionalTasks)
    }
    
    // Calculate max all-day height across all days in the week
    private func calculateMaxAllDayHeight(eventsCache: [Date: [GoogleCalendarEvent]], tasksCache: [Date: [String: [GoogleTask]]]) -> CGFloat {
        guard !weekDates.isEmpty else { return 20 }
        let lineHeight: CGFloat = 20 + 12 + 4 // approximate per-line height
        let timeWindowManager = TaskTimeWindowManager.shared
        
        let maxHeight = weekDates.map { date -> CGFloat in
            let eventsForDate = eventsCache[date] ?? []
            let tasksForDate = tasksCache[date] ?? [:]
            
            let allDayEvents = eventsForDate.filter { $0.isAllDay }
            var allDayTasks = tasksForDate.values.flatMap { $0 }.filter { task in
                if let timeWindow = timeWindowManager.getTimeWindow(for: task.id) {
                    return timeWindow.isAllDay
                }
                return true // If no time window, treat as all-day
            }
            
            if appPrefs.hideCompletedTasks {
                allDayTasks = allDayTasks.filter { !$0.isCompleted }
            }
            
            let eventsRowHeight: CGFloat = allDayEvents.isEmpty ? 0 : CGFloat(allDayEvents.count) * lineHeight
            let tasksRowHeight: CGFloat = allDayTasks.isEmpty ? 0 : CGFloat(allDayTasks.count) * lineHeight
            let spacing: CGFloat = (allDayEvents.isEmpty || allDayTasks.isEmpty) ? 0 : 4
            
            let totalHeight = eventsRowHeight + tasksRowHeight + spacing
            return max(totalHeight, 20)
        }.max() ?? 20
        
        return maxHeight
    }
    
    // MARK: - Helper Views
    @ViewBuilder
    private func timeboxColumn(for date: Date, index: Int, availableWidth: CGFloat, columnWidth: CGFloat) -> some View {
        let eventsForDate = weeklyEventsCache[date] ?? getAllEventsForDate(date)
        let tasksForDate = weeklyTasksCache[date] ?? getTasksForDate(date)
        let (personalTasksForDate, professionalTasksForDate) = splitTasksByAccount(tasksForDate)
        let maxAllDayHeight = cachedMaxAllDayHeight > 0 ? cachedMaxAllDayHeight : calculateMaxAllDayHeight(eventsCache: weeklyEventsCache, tasksCache: weeklyTasksCache)
        
        VStack(spacing: 0) {
            // All-day section with fixed height
            allDaySection(
                date: date,
                events: eventsForDate,
                personalTasks: personalTasksForDate,
                professionalTasks: professionalTasksForDate,
                maxHeight: maxAllDayHeight
            )
            .frame(height: maxAllDayHeight)
            
            // Timeline section (without all-day section since we show it separately)
            TimeboxComponent(
                date: date,
                events: eventsForDate,
                personalEvents: calendarVM.personalEvents,
                professionalEvents: calendarVM.professionalEvents,
                personalTasks: personalTasksForDate,
                professionalTasks: professionalTasksForDate,
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                onEventTap: { event in
                    selectedEvent = event
                },
                onTaskTap: { task, listId in
                    // Determine account kind
                    let accountKind: GoogleAuthManager.AccountKind = tasksVM.personalTasks[listId] != nil ? .personal : .professional
                    taskSheetSelection = TimeboxTaskSelection(
                        id: task.id,
                        task: task,
                        listId: listId,
                        accountKind: accountKind
                    )
                },
                onTaskToggle: { task, listId in
                    // Determine account kind
                    let accountKind: GoogleAuthManager.AccountKind = tasksVM.personalTasks[listId] != nil ? .personal : .professional
                    Task {
                        await tasksVM.toggleTaskCompletion(task, in: listId, for: accountKind)
                    }
                },
                showAllDaySection: false
            )
            .frame(width: columnWidth)
        }
        
        // Divider between days (except for the last one)
        if index < weekDates.count - 1 {
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 1)
        }
    }
    
    @ViewBuilder
    private func allDaySection(date: Date, events: [GoogleCalendarEvent], personalTasks: [String: [GoogleTask]], professionalTasks: [String: [GoogleTask]], maxHeight: CGFloat) -> some View {
        let allDayEvents = events.filter { $0.isAllDay }
        let allDayTasksRaw = (personalTasks.values.flatMap { $0 } + professionalTasks.values.flatMap { $0 }).filter { task in
            if let timeWindow = TaskTimeWindowManager.shared.getTimeWindow(for: task.id) {
                return timeWindow.isAllDay
            }
            return true
        }
        
        // Filter out completed tasks if hideCompletedTasks is enabled
        let allDayTasks = appPrefs.hideCompletedTasks ? allDayTasksRaw.filter { !$0.isCompleted } : allDayTasksRaw
        
        VStack(alignment: .leading, spacing: 6) {
            // All-day events row (one event per line)
            if !allDayEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allDayEvents, id: \.id) { event in
                        let isPersonal = calendarVM.personalEvents.contains { $0.id == event.id }
                        let color = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
                        
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEvent = event
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            
            // All-day tasks row (one task per line, vertical stacking)
            if !allDayTasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allDayTasks, id: \.id) { task in
                        let isPersonal = personalTasks.values.flatMap { $0 }.contains { $0.id == task.id }
                        let color = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
                        
                        HStack(spacing: 8) {
                            // Checkmark circle button - tappable to toggle completion
                            Button(action: {
                                // Determine account kind
                                let accountKind: GoogleAuthManager.AccountKind = isPersonal ? .personal : .professional
                                let listId = findTaskListId(for: task, in: personalTasks, professionalTasks: professionalTasks)
                                Task {
                                    await tasksVM.toggleTaskCompletion(task, in: listId, for: accountKind)
                                }
                            }) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.body)
                                    .foregroundColor(task.isCompleted ? color : .secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Text(task.title)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(task.isCompleted ? .secondary : .primary)
                                .strikethrough(task.isCompleted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(color.opacity(0.1))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Determine account kind
                            let accountKind: GoogleAuthManager.AccountKind = isPersonal ? .personal : .professional
                            taskSheetSelection = TimeboxTaskSelection(
                                id: task.id,
                                task: task,
                                listId: findTaskListId(for: task, in: personalTasks, professionalTasks: professionalTasks),
                                accountKind: accountKind
                            )
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(maxHeight: maxHeight, alignment: .top)
    }
    
    private func findTaskListId(for task: GoogleTask, in personalTasks: [String: [GoogleTask]], professionalTasks: [String: [GoogleTask]]) -> String {
        // Find which list contains this task
        for (listId, tasks) in personalTasks {
            if tasks.contains(where: { $0.id == task.id }) {
                return listId
            }
        }
        for (listId, tasks) in professionalTasks {
            if tasks.contains(where: { $0.id == task.id }) {
                return listId
            }
        }
        return "" // Fallback
    }
    
    private func dueDateTag(for task: GoogleTask, accentColor: Color) -> (text: String, textColor: Color, backgroundColor: Color)? {
        if task.isCompleted {
            return nil
        }
        
        guard let dueDate = task.dueDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: dueDate)
        
        if calendar.isDate(dueDay, inSameDayAs: today) {
            return ("Today", .white, accentColor)
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                  calendar.isDate(dueDay, inSameDayAs: tomorrow) {
            return ("Tomorrow", .white, .cyan)
        } else if dueDay < today {
            return ("Overdue", .white, .red)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return (formatter.string(from: dueDate), .primary, Color(.systemGray5))
        }
    }
    
}
