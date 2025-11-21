import SwiftUI

struct DayViewTimebox: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    private let onEventTap: ((GoogleCalendarEvent) -> Void)?
    
    // MARK: - State Variables
    @State private var dayLeftSectionWidth: CGFloat
    @State private var isDayVerticalDividerDragging = false
    @State private var dayMiddleSectionWidth: CGFloat
    @State private var isMiddleVerticalDividerDragging = false
    @State private var isLogsSectionCollapsed: Bool = false
    
    // MARK: - Selection State
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedTaskAccount: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails: Bool = false
    @State private var selectedEvent: GoogleCalendarEvent?
    
    init(onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self._navigationManager = ObservedObject(wrappedValue: NavigationManager.shared)
        self._appPrefs = ObservedObject(wrappedValue: AppPreferences.shared)
        self.calendarVM = DataManager.shared.calendarViewModel
        self._tasksVM = ObservedObject(wrappedValue: DataManager.shared.tasksViewModel)
        self._auth = ObservedObject(wrappedValue: GoogleAuthManager.shared)
        self.onEventTap = onEventTap
        
        // Initialize state variables with stored values from AppPreferences
        self._dayLeftSectionWidth = State(initialValue: AppPreferences.shared.dayViewTimeboxLeftSectionWidth)
        self._dayMiddleSectionWidth = State(initialValue: AppPreferences.shared.dayViewCompactLeftColumnWidth) // Reuse existing preference
        self._isLogsSectionCollapsed = State(initialValue: AppPreferences.shared.dayViewTimeboxLogsSectionCollapsed)
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                // Left section - TimeboxComponent only
                leftSection(geometry: geometry)
                    .frame(width: dayLeftSectionWidth)
                
                // First vertical divider
                leftVerticalDivider
                
                // Middle section - Logs (collapsible horizontally)
                if appPrefs.showAnyLogs {
                    middleSection(geometry: geometry)
                        .frame(width: isLogsSectionCollapsed ? 44 : dayMiddleSectionWidth)
                    
                    // Second vertical divider (only show when logs are expanded)
                    if !isLogsSectionCollapsed {
                        middleVerticalDivider
                    }
                }
                
                // Right section - Journal only (expands to fill remaining space)
                rightSection(geometry: geometry)
                    .frame(maxWidth: .infinity)
            }
        }
        // Task details sheet
        .sheet(isPresented: Binding(
            get: { showingTaskDetails && selectedTask != nil && selectedTaskListId != nil && selectedTaskAccount != nil },
            set: { showingTaskDetails = $0 }
        )) {
            if let t = selectedTask, let listId = selectedTaskListId, let account = selectedTaskAccount {
                TaskDetailsView(
                    task: t,
                    taskListId: listId,
                    accountKind: account,
                    accentColor: account == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    personalTaskLists: tasksVM.personalTaskLists,
                    professionalTaskLists: tasksVM.professionalTaskLists,
                    appPrefs: appPrefs,
                    viewModel: tasksVM,
                    onSave: { updatedTask in
                        Task {
                            await tasksVM.updateTask(updatedTask, in: listId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onDelete: {
                        Task {
                            await tasksVM.deleteTask(t, from: listId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onMove: { updatedTask, targetListId in
                        Task {
                            await tasksVM.moveTask(updatedTask, from: listId, to: targetListId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                        Task {
                            await tasksVM.crossAccountMoveTask(updatedTask, from: (account, listId), to: (targetAccount, targetListId))
                        }
                        showingTaskDetails = false
                    },
                    isNew: false
                )
            }
        }
        // Event details sheet
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
    }
    
    // MARK: - Left Section (TimeboxComponent only)
    private func leftSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Fixed all-day section at top (always visible)
            if !allDayItems.isEmpty {
                allDayItemsSection
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(Color(.systemBackground))
                
                Divider()
            }
            
            // Scrollable timeline below
            TimeboxComponent(
                date: navigationManager.currentDate,
                events: getAllEventsForDate(navigationManager.currentDate),
                personalEvents: calendarVM.personalEvents,
                professionalEvents: calendarVM.professionalEvents,
                personalTasks: filteredTasksForDate(tasksVM.personalTasks, date: navigationManager.currentDate),
                professionalTasks: filteredTasksForDate(tasksVM.professionalTasks, date: navigationManager.currentDate),
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                onEventTap: { ev in
                    if let onEventTap = onEventTap {
                        onEventTap(ev)
                    } else {
                        selectedEvent = ev
                    }
                },
                onTaskTap: { task, listId in
                    // Determine account kind
                    let accountKind: GoogleAuthManager.AccountKind = tasksVM.personalTasks[listId] != nil ? .personal : .professional
                    selectedTask = task
                    selectedTaskListId = listId
                    selectedTaskAccount = accountKind
                    showingTaskDetails = true
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
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Middle Section (Logs only)
    private func middleSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            if !isLogsSectionCollapsed {
                // Expanded state - show full logs with collapse button
                VStack(spacing: 0) {
                    // Header with collapse button
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLogsSectionCollapsed = true
                                appPrefs.updateDayViewTimeboxLogsSectionCollapsed(true)
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6).opacity(0.5))
                    
                    Divider()
                    
                    // Logs content
                    ScrollView(.vertical, showsIndicators: true) {
                        LogsComponent(currentDate: navigationManager.currentDate, horizontal: false)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    .frame(maxHeight: .infinity)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                // Collapsed state - show vertical expand button
                VStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogsSectionCollapsed = false
                            appPrefs.updateDayViewTimeboxLogsSectionCollapsed(false)
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    
                    Spacer()
                }
                .frame(width: 44)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Right Section (Journal only)
    private func rightSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Journal section (expands to fill full height)
            VStack(alignment: .leading, spacing: 6) {
                JournalView(currentDate: $navigationManager.currentDate, embedded: true, layoutType: .compact)
            }
            .id(navigationManager.currentDate)
            .frame(maxHeight: .infinity)
            .padding(.all, 8)
            .background(Color(.systemBackground))
            .clipped()
        }
    }
    
    // MARK: - Dividers
    private var leftVerticalDivider: some View {
        Rectangle()
            .fill(isDayVerticalDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isDayVerticalDividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDayVerticalDividerDragging = true
                        let newWidth = dayLeftSectionWidth + value.translation.width
                        let minWidth: CGFloat = 200
                        let maxWidth: CGFloat = 500
                        dayLeftSectionWidth = max(minWidth, min(maxWidth, newWidth))
                    }
                    .onEnded { _ in
                        isDayVerticalDividerDragging = false
                        appPrefs.updateDayViewTimeboxLeftSectionWidth(dayLeftSectionWidth)
                    }
            )
    }
    
    private var middleVerticalDivider: some View {
        Rectangle()
            .fill(isMiddleVerticalDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isMiddleVerticalDividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isMiddleVerticalDividerDragging = true
                        let newWidth = dayMiddleSectionWidth + value.translation.width
                        let minWidth: CGFloat = 200
                        let maxWidth: CGFloat = 500
                        dayMiddleSectionWidth = max(minWidth, min(maxWidth, newWidth))
                    }
                    .onEnded { _ in
                        isMiddleVerticalDividerDragging = false
                        appPrefs.updateDayViewCompactLeftColumnWidth(dayMiddleSectionWidth)
                    }
            )
    }
    
    // MARK: - All-Day Items Section
    private var allDayItems: [(isEvent: Bool, isTask: Bool, id: String, title: String, isPersonal: Bool)] {
        var items: [(isEvent: Bool, isTask: Bool, id: String, title: String, isPersonal: Bool)] = []
        
        // Add all-day events
        let allEvents = getAllEventsForDate(navigationManager.currentDate)
        let allDayEvents = allEvents.filter { $0.isAllDay }
        for event in allDayEvents {
            let isPersonal = calendarVM.personalEvents.contains { $0.id == event.id }
            items.append((isEvent: true, isTask: false, id: event.id, title: event.summary, isPersonal: isPersonal))
        }
        
        // Add all-day tasks (tasks without specific times)
        let personalFiltered = filteredTasksForDate(tasksVM.personalTasks, date: navigationManager.currentDate)
        let professionalFiltered = filteredTasksForDate(tasksVM.professionalTasks, date: navigationManager.currentDate)
        
        for (listId, tasks) in personalFiltered {
            for task in tasks {
                items.append((isEvent: false, isTask: true, id: task.id, title: task.title, isPersonal: true))
            }
        }
        
        for (listId, tasks) in professionalFiltered {
            for task in tasks {
                items.append((isEvent: false, isTask: true, id: task.id, title: task.title, isPersonal: false))
            }
        }
        
        return items
    }
    
    private var allDayItemsSection: some View {
        VStack(spacing: 4) {
            ForEach(allDayItems, id: \.id) { item in
                allDayItemBlock(item: item)
            }
        }
    }
    
    private func allDayItemBlock(item: (isEvent: Bool, isTask: Bool, id: String, title: String, isPersonal: Bool)) -> some View {
        let itemColor = item.isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return Group {
            if item.isTask {
                // Find the task to get its completion status
                let allTasks = (item.isPersonal ? tasksVM.personalTasks : tasksVM.professionalTasks)
                    .values.flatMap { $0 }
                if let task = allTasks.first(where: { $0.id == item.id }) {
                    let listId = findTaskListId(for: task, isPersonal: item.isPersonal)
                    HStack(spacing: 8) {
                        Button(action: {
                            if let listId = listId {
                                let accountKind: GoogleAuthManager.AccountKind = item.isPersonal ? .personal : .professional
                                Task {
                                    await tasksVM.toggleTaskCompletion(task, in: listId, for: accountKind)
                                }
                            }
                        }) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .foregroundColor(task.isCompleted ? itemColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Text(task.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(task.isCompleted ? .secondary : .primary)
                            .strikethrough(task.isCompleted)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(itemColor.opacity(0.1))
                    .cornerRadius(8)
                    .onTapGesture {
                        if let listId = listId {
                            selectedTask = task
                            selectedTaskListId = listId
                            selectedTaskAccount = item.isPersonal ? .personal : .professional
                            showingTaskDetails = true
                        }
                    }
                }
            } else {
                // Event
                if let event = calendarVM.personalEvents.first(where: { $0.id == item.id }) ?? 
                              calendarVM.professionalEvents.first(where: { $0.id == item.id }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(itemColor)
                            .frame(width: 8, height: 8)
                        
                        Text(item.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(itemColor.opacity(0.1))
                    .cornerRadius(8)
                    .onTapGesture {
                        if let onEventTap = onEventTap {
                            onEventTap(event)
                        } else {
                            selectedEvent = event
                        }
                    }
                }
            }
        }
    }
    
    private func findTaskListId(for task: GoogleTask, isPersonal: Bool) -> String? {
        let tasksDict = isPersonal ? tasksVM.personalTasks : tasksVM.professionalTasks
        for (listId, tasks) in tasksDict {
            if tasks.contains(where: { $0.id == task.id }) {
                return listId
            }
        }
        return nil
    }
    
    // MARK: - Helper Functions
    private func getAllEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.mondayFirst
        let all = calendarVM.personalEvents + calendarVM.professionalEvents
        return all.filter { ev in
            guard let startTime = ev.startTime else { return ev.isAllDay }
            
            if ev.isAllDay {
                // For all-day events, check if the date falls within the event's date range
                guard let endTime = ev.endTime else { return false }
                
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
                guard let endTime = ev.endTime else {
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
    }
    
    private func filteredTasksForDate(_ dict: [String: [GoogleTask]], date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.mondayFirst
        let startOfViewedDate = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: Date())
        let isViewingToday = startOfViewedDate == startOfToday
        
        var result: [String: [GoogleTask]] = [:]
        for (listId, tasks) in dict {
            let filtered = tasks.filter { task in
                // For completed tasks, show only on completion date
                if task.isCompleted {
                    if let comp = task.completionDate {
                        return Calendar.mondayFirst.isDate(comp, inSameDayAs: date)
                    }
                    return false
                }
                
                // For incomplete tasks
                if let dueDate = task.dueDate {
                    let startOfDueDate = calendar.startOfDay(for: dueDate)
                    let isViewingDueDate = startOfViewedDate == startOfDueDate
                    let isOverdue = startOfDueDate < startOfToday
                    
                    // Show if:
                    // 1. We're viewing its due date (past or future), OR
                    // 2. We're viewing today AND it's overdue
                    return isViewingDueDate || (isViewingToday && isOverdue)
                }
                return false
            }
            if !filtered.isEmpty { result[listId] = filtered }
        }
        return result
    }
}

#Preview {
    DayViewTimebox()
}

