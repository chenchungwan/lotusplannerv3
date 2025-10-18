import SwiftUI

struct DayViewA5: View {
    @ObservedObject var navigationManager: NavigationManager
    @ObservedObject var appPreferences: AppPreferences
    @ObservedObject var calendarViewModel: CalendarViewModel
    @ObservedObject var tasksViewModel: TasksViewModel
    @ObservedObject var googleAuthManager: GoogleAuthManager
    @ObservedObject var logsViewModel: LogsViewModel
    
    // Fixed page dimensions
    private let pageWidth: CGFloat = 1668
    private let pageHeight: CGFloat = 1210
    
    // Column widths based on page width (not screen width)
    private var tasksLogsColumnWidth: CGFloat { pageWidth / 3 } // 1/3 of page width  
    private var journalColumnWidth: CGFloat { pageWidth / 2 } // 1/2 of page width
    
    // Draggable divider state
    @State private var tasksHeight: CGFloat = 400
    @State private var isDragging = false
    
    // Column divider state
    @State private var eventsColumnWidth: CGFloat = 278 // 1/6 of page width
    @State private var isColumnDragging = false
    
    // Task selection state
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                // Main content with fixed page dimensions
                HStack(alignment: .top, spacing: 0) {
                    // Column 1: Events (1/6 of page width)
                    VStack {
                        Group {
                            if appPreferences.showEventsAsListInDay {
                                EventsListComponent(
                                    events: filteredEventsForDay(navigationManager.currentDate),
                                    personalEvents: calendarViewModel.personalEvents,
                                    professionalEvents: calendarViewModel.professionalEvents,
                                    personalColor: appPreferences.personalColor,
                                    professionalColor: appPreferences.professionalColor,
                                    onEventTap: { _ in },
                                    date: navigationManager.currentDate
                                )
                            } else {
                                TimelineComponent(
                                    date: navigationManager.currentDate,
                                    events: filteredEventsForDay(navigationManager.currentDate),
                                    personalEvents: filteredPersonalEventsForDay(navigationManager.currentDate),
                                    professionalEvents: filteredProfessionalEventsForDay(navigationManager.currentDate),
                                    personalColor: appPreferences.personalColor,
                                    professionalColor: appPreferences.professionalColor,
                                    onEventTap: { _ in }
                                )
                            }
                        }
                    }
                    .frame(width: eventsColumnWidth, height: pageHeight)
                    .background(Color(.systemBackground))
                    
                    // Draggable divider between columns 1 and 2
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 8)
                        .overlay(
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 40)
                                .cornerRadius(4)
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isColumnDragging = true
                                    let newWidth = eventsColumnWidth + value.translation.width
                                    let maxWidth = pageWidth * 0.4 // Max 40% of page width
                                    let minWidth: CGFloat = 150
                                    eventsColumnWidth = max(minWidth, min(newWidth, maxWidth))
                                }
                                .onEnded { _ in
                                    isColumnDragging = false
                                }
                        )
                        
                    // Column 2: Tasks and Logs (remaining width)
                    VStack(spacing: 0) {
                        // Tasks Component - Side by Side
                        HStack(alignment: .top, spacing: 8) {
                            let personalTasks = filteredTasksDictForDay(tasksViewModel.personalTasks, on: navigationManager.currentDate)
                            let professionalTasks = filteredTasksDictForDay(tasksViewModel.professionalTasks, on: navigationManager.currentDate)
                            
                            // Personal Tasks
                            VStack {
                                TasksComponent(
                                    taskLists: tasksViewModel.personalTaskLists,
                                    tasksDict: personalTasks,
                                    accentColor: appPreferences.personalColor,
                                    accountType: .personal,
                                    onTaskToggle: { task, listId in
                                        Task { await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal) }
                                    },
                                    onTaskDetails: { task, listId in
                                        selectedTask = task
                                        selectedTaskListId = listId
                                    },
                                    onListRename: nil
                                )
                            }
                            .frame(maxWidth: .infinity)
                            
                            // Professional Tasks
                            VStack {
                                TasksComponent(
                                    taskLists: tasksViewModel.professionalTaskLists,
                                    tasksDict: professionalTasks,
                                    accentColor: appPreferences.professionalColor,
                                    accountType: .professional,
                                    onTaskToggle: { task, listId in
                                        Task { await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional) }
                                    },
                                    onTaskDetails: { task, listId in
                                        selectedTask = task
                                        selectedTaskListId = listId
                                    },
                                    onListRename: nil
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: tasksHeight)
                        
                        // Draggable Divider
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 8)
                            .overlay(
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: 40, height: 8)
                                    .cornerRadius(4)
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        isDragging = true
                                        let newHeight = tasksHeight + value.translation.height
                                        let maxHeight = pageHeight - 200 // Leave space for logs
                                        let minHeight: CGFloat = 100
                                        tasksHeight = max(minHeight, min(newHeight, maxHeight))
                                    }
                                    .onEnded { _ in
                                        isDragging = false
                                    }
                            )
                        
                        // Logs Component
                        VStack {
                            LogsComponent(
                                currentDate: navigationManager.currentDate,
                                horizontal: false
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: pageWidth - eventsColumnWidth - journalColumnWidth - 8, height: pageHeight)
                    .background(Color(.systemBackground))
                    
                    // Column 3: Journal (1/2 of page width)
                    VStack {
                        JournalView(
                            currentDate: navigationManager.currentDate,
                            embedded: true,
                            layoutType: .compact
                        )
                    }
                    .frame(width: journalColumnWidth, height: pageHeight)
                    .background(Color(.systemBackground))
                }
                .frame(width: pageWidth, height: pageHeight)
                .background(Color(.systemBackground))
            }
            .background(Color(.systemBackground))
        }
    }
    
    private func filteredEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        let all = calendarViewModel.personalEvents + calendarViewModel.professionalEvents
        return all.filter { ev in
            if let start = ev.startTime { return isSameDay(start, date) }
            return false
        }
    }
    
    private func filteredPersonalEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        return calendarViewModel.personalEvents.filter { ev in
            if let start = ev.startTime { return isSameDay(start, date) }
            return false
        }
    }
    
    private func filteredProfessionalEventsForDay(_ date: Date) -> [GoogleCalendarEvent] {
        return calendarViewModel.professionalEvents.filter { ev in
            if let start = ev.startTime { return isSameDay(start, date) }
            return false
        }
    }
    
    private func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    
    private func filteredTasksDictForDay(_ dict: [String: [GoogleTask]], on date: Date) -> [String: [GoogleTask]] {
        let calendar = Calendar.mondayFirst
        let startOfViewedDate = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: Date())
        let isViewingToday = startOfViewedDate == startOfToday
        
        var result: [String: [GoogleTask]] = [:]
        for (listId, tasks) in dict {
            let filtered = tasks.filter { task in
                // For completed tasks, show only on completion date
                if task.isCompleted {
                    if let completionDate = task.completionDate {
                        return calendar.isDate(completionDate, inSameDayAs: date)
                    }
                    return false
                }
                
                // For incomplete tasks, show if due on the viewed date or overdue
                if let dueDate = task.dueDate {
                    let isDueOnViewedDate = calendar.isDate(dueDate, inSameDayAs: date)
                    let isOverdue = dueDate < startOfViewedDate
                    return isDueOnViewedDate || (isOverdue && !isViewingToday)
                }
                
                // Tasks without due dates show only on today
                return isViewingToday
            }
            if !filtered.isEmpty {
                result[listId] = filtered
            }
        }
        return result
    }
}

#Preview {
    DayViewA5(
        navigationManager: NavigationManager.shared,
        appPreferences: AppPreferences.shared,
        calendarViewModel: CalendarViewModel(),
        tasksViewModel: TasksViewModel(),
        googleAuthManager: GoogleAuthManager.shared,
        logsViewModel: LogsViewModel.shared
    )
}
