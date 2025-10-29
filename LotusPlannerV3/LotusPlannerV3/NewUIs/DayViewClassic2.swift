import SwiftUI

struct DayViewClassic2: View {
    @ObservedObject private var navigationManager: NavigationManager
    @ObservedObject private var appPrefs: AppPreferences
    private let calendarVM: CalendarViewModel
    @ObservedObject private var tasksVM: TasksViewModel
    @ObservedObject private var auth: GoogleAuthManager
    private let onEventTap: ((GoogleCalendarEvent) -> Void)?
    
    // MARK: - State Variables
    @State private var dayLeftSectionWidth: CGFloat
    @State private var leftTimelineHeight: CGFloat
    @State private var isLeftTimelineDividerDragging = false
    @State private var eventsHeight: CGFloat
    @State private var isEventsTasksDividerDragging = false
    @State private var logsHeight: CGFloat
    @State private var isLogsDividerDragging = false
    @State private var isDayVerticalDividerDragging = false
    
    // MARK: - Selection State
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedTaskAccount: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails: Bool = false
    
    init(onEventTap: ((GoogleCalendarEvent) -> Void)? = nil) {
        self._navigationManager = ObservedObject(wrappedValue: NavigationManager.shared)
        self._appPrefs = ObservedObject(wrappedValue: AppPreferences.shared)
        self.calendarVM = DataManager.shared.calendarViewModel
        self._tasksVM = ObservedObject(wrappedValue: DataManager.shared.tasksViewModel)
        self._auth = ObservedObject(wrappedValue: GoogleAuthManager.shared)
        self.onEventTap = onEventTap
        
        // Initialize state variables with stored values from AppPreferences
        self._dayLeftSectionWidth = State(initialValue: 300)
        self._leftTimelineHeight = State(initialValue: 300)
        self._eventsHeight = State(initialValue: AppPreferences.shared.dayViewClassic2EventsHeight)
        self._logsHeight = State(initialValue: AppPreferences.shared.dayViewClassic2LogsHeight)
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                // Left section (dynamic width)
                leftDaySectionWithDivider(geometry: geometry)
                    .frame(width: dayLeftSectionWidth)
                
                // Vertical divider
                dayVerticalDivider
                
                // Right section expands to fill remaining space
                rightDaySection(geometry: geometry)
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
                        let viewModel = tasksVM // Capture the view model
                        Task {
                            await viewModel.updateTask(updatedTask, in: listId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onDelete: {
                        let viewModel = tasksVM // Capture the view model
                        Task {
                            await viewModel.deleteTask(t, from: listId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onMove: { updatedTask, targetListId in
                        let viewModel = tasksVM // Capture the view model
                        Task {
                            await viewModel.moveTask(updatedTask, from: listId, to: targetListId, for: account)
                        }
                        showingTaskDetails = false
                    },
                    onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                        let viewModel = tasksVM // Capture the view model
                        Task {
                            await viewModel.crossAccountMoveTask(updatedTask, from: (account, listId), to: (targetAccount, targetListId))
                        }
                        showingTaskDetails = false
                    },
                    isNew: false
                )
            }
        }
    }
    
    // MARK: - Left Section
    private func leftDaySectionWithDivider(geometry: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Events section
                eventsTimelineCard()
                    .padding(.leading, 16 + geometry.safeAreaInsets.leading)
                    .padding(.trailing, 8)
                
                // Divider between Events and Tasks
                eventsTasksDivider
                
                // Personal Tasks section
                personalTasksSection
                    .padding(.leading, 16 + geometry.safeAreaInsets.leading)
                    .padding(.trailing, 8)
                
                // Professional Tasks section
                professionalTasksSection
                    .padding(.leading, 16 + geometry.safeAreaInsets.leading)
                    .padding(.trailing, 8)
                
                // Logs section (only if any logs are enabled)
                if appPrefs.showAnyLogs {
                    // Divider between Tasks and Logs
                    logsDivider
                    
                    LogsComponent(currentDate: navigationManager.currentDate, horizontal: false)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Right Section
    private func rightDaySection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Journal section (full height since tasks moved to left column)
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
    
    // MARK: - Components
    
    private var leftTimelineSection: some View {
        Group {
            if appPrefs.showEventsAsListInDay {
                dayEventsList
            } else {
                TimelineComponent(
                    date: navigationManager.currentDate,
                    events: getAllEventsForDate(navigationManager.currentDate),
                    personalEvents: calendarVM.personalEvents,
                    professionalEvents: calendarVM.professionalEvents,
                    personalColor: appPrefs.personalColor,
                    professionalColor: appPrefs.professionalColor,
                    onEventTap: { ev in
                        onEventTap?(ev)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    // Shared Events timeline card used by all layouts
    private func eventsTimelineCard() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Events")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 8)
            leftTimelineSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .padding(.bottom, 0)
        .padding(.leading, 8)
    }
    
    // MARK: - Task Sections
    private var personalTasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Personal Tasks")
                    .font(.headline)
                    .foregroundColor(appPrefs.personalColor)
                Spacer()
            }
            .padding(.horizontal, 8)
            
            let personalFiltered = filteredTasksForDate(tasksVM.personalTasks, date: navigationManager.currentDate)
            if auth.isLinked(kind: .personal) && !personalFiltered.values.flatMap({ $0 }).isEmpty {
                TasksComponent(
                    taskLists: tasksVM.personalTaskLists,
                    tasksDict: personalFiltered,
                    accentColor: appPrefs.personalColor,
                    accountType: .personal,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksVM.toggleTaskCompletion(task, in: listId, for: .personal)
                        }
                    },
                    onTaskDetails: { task, listId in
                        selectedTask = task
                        selectedTaskListId = listId
                        selectedTaskAccount = .personal
                        showingTaskDetails = true
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksVM.updateTaskListOrder(newOrder, for: .personal)
                        }
                    },
                    isSingleDayView: true
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if !auth.isLinked(kind: .personal) && !auth.isLinked(kind: .professional) {
                // Empty state - show link account UI
                Button(action: { NavigationManager.shared.showSettings() }) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("Link Your Google Account")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("Connect your Google account to view and manage your tasks")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // Account linked but no tasks
                Text("No tasks")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 8)
        .padding(.bottom, 0)
    }
    
    private var professionalTasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Professional Tasks")
                    .font(.headline)
                    .foregroundColor(appPrefs.professionalColor)
                Spacer()
            }
            .padding(.horizontal, 8)
            
            let professionalFiltered = filteredTasksForDate(tasksVM.professionalTasks, date: navigationManager.currentDate)
            if auth.isLinked(kind: .professional) && !professionalFiltered.values.flatMap({ $0 }).isEmpty {
                TasksComponent(
                    taskLists: tasksVM.professionalTaskLists,
                    tasksDict: professionalFiltered,
                    accentColor: appPrefs.professionalColor,
                    accountType: .professional,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksVM.toggleTaskCompletion(task, in: listId, for: .professional)
                        }
                    },
                    onTaskDetails: { task, listId in
                        selectedTask = task
                        selectedTaskListId = listId
                        selectedTaskAccount = .professional
                        showingTaskDetails = true
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksVM.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksVM.updateTaskListOrder(newOrder, for: .professional)
                        }
                    },
                    isSingleDayView: true
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if !auth.isLinked(kind: .personal) && !auth.isLinked(kind: .professional) {
                // Empty state - already handled by personal tasks section
                EmptyView()
            } else {
                // Account linked but no tasks
                Text("No tasks")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 8)
        .padding(.bottom, 0)
    }
    
    private var dayEventsList: some View {
        let events = getAllEventsForDate(navigationManager.currentDate)
            .sorted { (a, b) in
                let aDate = a.startTime ?? Date.distantPast
                let bDate = b.startTime ?? Date.distantPast
                return aDate < bDate
            }
        return EventsListComponent(
            events: events,
            personalEvents: calendarVM.personalEvents,
            professionalEvents: calendarVM.professionalEvents,
            personalColor: appPrefs.personalColor,
            professionalColor: appPrefs.professionalColor,
            onEventTap: { ev in
                onEventTap?(ev)
            },
            date: navigationManager.currentDate
        )
    }
    
    
    private var eventsTasksDivider: some View {
        Rectangle()
            .fill(isEventsTasksDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isEventsTasksDividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isEventsTasksDividerDragging = true
                        let newHeight = eventsHeight + value.translation.height
                        let minHeight: CGFloat = 150
                        let maxHeight: CGFloat = 400
                        eventsHeight = max(minHeight, min(maxHeight, newHeight))
                    }
                    .onEnded { _ in
                        isEventsTasksDividerDragging = false
                        appPrefs.updateDayViewClassic2EventsHeight(eventsHeight)
                    }
            )
    }
    
    private var logsDivider: some View {
        Rectangle()
            .fill(isLogsDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isLogsDividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isLogsDividerDragging = true
                        let newHeight = logsHeight - value.translation.height
                        let minHeight: CGFloat = 100
                        let maxHeight: CGFloat = 1200
                        logsHeight = max(minHeight, min(maxHeight, newHeight))
                    }
                    .onEnded { _ in
                        isLogsDividerDragging = false
                        appPrefs.updateDayViewClassic2LogsHeight(logsHeight)
                    }
            )
    }
    
    private var leftTimelineDivider: some View {
        Rectangle()
            .fill(isLeftTimelineDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(height: 8)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isLeftTimelineDividerDragging ? .white : .gray)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isLeftTimelineDividerDragging = true
                        let newHeight = leftTimelineHeight + value.translation.height
                        let minHeight: CGFloat = 200
                        let maxHeight: CGFloat = 500
                        leftTimelineHeight = max(minHeight, min(maxHeight, newHeight))
                    }
                    .onEnded { _ in
                        isLeftTimelineDividerDragging = false
                    }
            )
    }
    
    private var dayVerticalDivider: some View {
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
                        // Could save to preferences here if needed
                    }
            )
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
                // For timed events, check if the event starts on this date
                return calendar.isDate(startTime, inSameDayAs: date)
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
    DayViewClassic2()
}
