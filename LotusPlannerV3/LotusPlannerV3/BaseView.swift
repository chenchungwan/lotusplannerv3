import SwiftUI

enum ViewMode: String, CaseIterable, Hashable {
    case day
    case week
    case month
    case year
}

struct BaseView: View {
    @EnvironmentObject var appPrefs: AppPreferences
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @State private var selectedDate = Date()
    @State private var viewMode: ViewMode = .day
    @State private var selectedCalendarEvent: GoogleCalendarEvent?
    @State private var showingEventDetails = false
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails = false
    
    // Section width management
    @State private var leftSectionWidth: CGFloat = 300
    @State private var middleSectionWidth: CGFloat = max(600, UIScreen.main.bounds.width * 0.25) // Both task sections combined, minimum 25% device width
    @State private var rightSectionWidth: CGFloat = UIScreen.main.bounds.width // Journal section width
    @State private var isDraggingLeftSlider = false
    @State private var isDraggingRightSlider = false
    
    // Computed property for minimum middle section width (25% of device width)
    private var minimumMiddleSectionWidth: CGFloat {
        UIScreen.main.bounds.width * 0.25
    }
    
    var body: some View {
            VStack(spacing: 0) {
                // Global Navigation Bar
            HStack(spacing: 8) {
                // Shared toolbar icons (settings, goals, calendar, tasks)
                SharedNavigationToolbar()
                
                // Date navigation arrows and title
                Button(action: { step(-1) }) {
                    Image(systemName: "chevron.left")
                }
                // Date title - clickable to go to today
                Button(action: { 
                    selectedDate = Date() // Go to today
                }) {
                    Text(titleText)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                Button(action: { step(1) }) {
                    Image(systemName: "chevron.right")
                }
                    
                    Spacer()
                    
                Picker("", selection: $viewMode) {
                    Text("Day").tag(ViewMode.day)
                    Text("Week").tag(ViewMode.week)
                    Text("Month").tag(ViewMode.month)
                    Text("Year").tag(ViewMode.year)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 300)
                }
                .padding(.horizontal)
                .frame(height: 44)
                .background(Color(UIColor.systemBackground))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.gray.opacity(0.2)),
                    alignment: .bottom
                )
                
            // Main content area divided into 3 horizontal sections with sliders
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Left section - Timeline (resizable width)
                    VStack(alignment: .leading, spacing: 0) {
                        TimelineComponent(
                            date: selectedDate,
                            events: getAllEventsForDate(selectedDate),
                            personalEvents: calendarViewModel.personalEvents,
                            professionalEvents: calendarViewModel.professionalEvents,
                            personalColor: appPrefs.personalColor,
                            professionalColor: appPrefs.professionalColor,
                            onEventTap: { ev in
                                selectedCalendarEvent = ev
                                showingEventDetails = true
                            }
                        )
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        
                        Spacer(minLength: 0)
                    }
                    .frame(width: leftSectionWidth)
                    .padding(.all, 8)
                    .background(Color(.systemGray6))
                    
                    // Left slider
                    leftSlider
                    
                    // Middle section - Tasks (resizable width, vertical layout)
                    VStack(spacing: 0) {
                        // Personal Tasks (top 50%)
                        if authManager.isLinked(kind: .personal) {
                            VStack(alignment: .leading, spacing: 0) {
                                PersonalTasksComponent(
                                    taskLists: tasksViewModel.personalTaskLists,
                                    tasksDict: getFilteredTasksForDate(tasksViewModel.personalTasks),
                                    accentColor: appPrefs.personalColor,
                                    onTaskToggle: { task, listId in
                                        Task {
                                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                        }
                                    },
                                    onTaskDetails: { task, listId in
                                        selectedTask = task
                                        selectedTaskListId = listId
                                        selectedAccountKind = .personal
                                        showingTaskDetails = true
                                    }
                                )
                                
                                Spacer(minLength: 0)
                            }
                            .frame(maxHeight: personalTasksSectionHeight ?? .infinity)
                            .padding(.all, 8)
                        }
                        
                        // Divider between tasks (if both accounts are linked)
                        if authManager.isLinked(kind: .personal) && authManager.isLinked(kind: .professional) {
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(height: 1)
                        }
                        
                        // Professional Tasks (bottom 50%)
                        if authManager.isLinked(kind: .professional) {
                            VStack(alignment: .leading, spacing: 0) {
                                ProfessionalTasksComponent(
                                    taskLists: tasksViewModel.professionalTaskLists,
                                    tasksDict: getFilteredTasksForDate(tasksViewModel.professionalTasks),
                                    accentColor: appPrefs.professionalColor,
                                    onTaskToggle: { task, listId in
                                        Task {
                                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                                        }
                                    },
                                    onTaskDetails: { task, listId in
                                        selectedTask = task
                                        selectedTaskListId = listId
                                        selectedAccountKind = .professional
                                        showingTaskDetails = true
                                    }
                                )
                                
                                Spacer(minLength: 0)
                            }
                            .frame(maxHeight: professionalTasksSectionHeight ?? .infinity)
                            .padding(.all, 8)
                        }
                        
                        // If neither account is linked, show placeholder
                        if !authManager.isLinked(kind: .personal) && !authManager.isLinked(kind: .professional) {
                            VStack {
                                Text("No Task Accounts Linked")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Link your Google accounts in Settings to view tasks")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.all, 8)
                        }
                    }
                    .frame(width: middleSectionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    
                    // Right slider
                    rightSlider
                    
                    // Right section - Journal (Scrapbook) - Resizable width
                    VStack(alignment: .leading, spacing: 0) {
                        JournalView(
                            currentDate: selectedDate,
                            embedded: true,
                            layoutType: .compact
                        )
                        .id(Calendar.current.startOfDay(for: selectedDate)) // Force refresh when date changes
                        
                        Spacer(minLength: 0)
                    }
                    .frame(width: rightSectionWidth)
                    .padding(.all, 8)
                    .background(Color(.systemGray5))
                }
                .frame(minHeight: 0, maxHeight: .infinity)
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
        .sheet(isPresented: $showingTaskDetails) {
            if let task = selectedTask,
               let listId = selectedTaskListId,
               let accountKind = selectedAccountKind {
                TaskDetailsView(
                    task: task,
                    taskListId: listId,
                    accountKind: accountKind,
                    accentColor: accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    personalTaskLists: tasksViewModel.personalTaskLists,
                    professionalTaskLists: tasksViewModel.professionalTaskLists,
                    appPrefs: appPrefs,
                    viewModel: tasksViewModel,
                    onSave: { updatedTask in
                        Task {
                            await tasksViewModel.updateTask(updatedTask, in: listId, for: accountKind)
                        }
                        showingTaskDetails = false
                    },
                    onDelete: {
                        Task {
                            await tasksViewModel.deleteTask(task, from: listId, for: accountKind)
                        }
                        showingTaskDetails = false
                    },
                    onMove: { task, newListId in
                        Task {
                            await tasksViewModel.moveTask(task, from: listId, to: newListId, for: accountKind)
                        }
                        showingTaskDetails = false
                    },
                    onCrossAccountMove: { task, newAccountKind, newListId in
                        Task {
                            await tasksViewModel.crossAccountMoveTask(task, from: (accountKind, listId), to: (newAccountKind, newListId))
                        }
                        showingTaskDetails = false
                    }
                )
            }
        }
        .task {
            await calendarViewModel.loadCalendarData(for: selectedDate)
            await tasksViewModel.loadTasks()
        }
        .onChange(of: selectedDate) { oldValue, newValue in
            Task {
                await calendarViewModel.loadCalendarData(for: newValue)
            }
        }
    }
}

// MARK: - Helpers

extension BaseView {
    // MARK: - Computed Properties for Section Heights (Vertical Layout)
    private var personalTasksSectionHeight: CGFloat? {
        if authManager.isLinked(kind: .personal) && authManager.isLinked(kind: .professional) {
            return nil // Use .infinity to split equally with professional tasks
        } else if authManager.isLinked(kind: .personal) {
            return nil // Use .infinity for full height
        } else {
            return 0
        }
    }
    
    private var professionalTasksSectionHeight: CGFloat? {
        if authManager.isLinked(kind: .personal) && authManager.isLinked(kind: .professional) {
            return nil // Use .infinity to split equally with personal tasks
        } else if authManager.isLinked(kind: .professional) {
            return nil // Use .infinity for full height
        } else {
            return 0
        }
    }
    
    // MARK: - Slider Views
    private var leftSlider: some View {
        Rectangle()
            .fill(isDraggingLeftSlider ? Color.blue.opacity(0.8) : Color(.systemGray3))
            .frame(width: 12) // Make wider for easier interaction
            .contentShape(Rectangle())
            .overlay(
                // Visual indicator for draggable area
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: 8)
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: 8)
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: 8)
                }
            )
            .gesture(
                DragGesture(minimumDistance: 0) // Allow immediate recognition
                    .onChanged { value in
                        isDraggingLeftSlider = true
                        // Adjust both left and middle sections inversely
                        let delta = value.translation.width
                        let newLeftWidth = leftSectionWidth + delta
                        let newMiddleWidth = middleSectionWidth - delta
                        
                        // Apply constraints - middle section must be at least 25% of device width
                        leftSectionWidth = max(200, min(800, newLeftWidth))
                        middleSectionWidth = max(minimumMiddleSectionWidth, min(1200, newMiddleWidth))
                        
                        print("Left slider: left=\(leftSectionWidth), middle=\(middleSectionWidth)")
                    }
                    .onEnded { _ in
                        isDraggingLeftSlider = false
                    }
            )
            .onTapGesture {
                // Debug tap to ensure slider is interactive
                print("Left slider tapped")
            }
    }
    
    private var rightSlider: some View {
        Rectangle()
            .fill(isDraggingRightSlider ? Color.blue.opacity(0.8) : Color(.systemGray3))
            .frame(width: 12) // Make wider for easier interaction
            .contentShape(Rectangle())
            .overlay(
                // Visual indicator for draggable area
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: 8)
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: 8)
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: 8)
                }
            )
            .gesture(
                DragGesture(minimumDistance: 0) // Allow immediate recognition
                    .onChanged { value in
                        isDraggingRightSlider = true
                        // Adjust both middle and right sections inversely
                        let delta = value.translation.width
                        let newMiddleWidth = middleSectionWidth + delta
                        let newRightWidth = rightSectionWidth - delta
                        
                        // Apply constraints
                        middleSectionWidth = max(minimumMiddleSectionWidth, min(1200, newMiddleWidth))
                        rightSectionWidth = max(200, min(UIScreen.main.bounds.width, newRightWidth))
                        
                        print("Right slider: middle=\(middleSectionWidth), right=\(rightSectionWidth)")
                    }
                    .onEnded { _ in
                        isDraggingRightSlider = false
                    }
            )
            .onTapGesture {
                // Debug tap to ensure slider is interactive
                print("Right slider tapped")
            }
    }
    
    private var titleText: String {
        switch viewMode {
        case .year:
            return yearTitle
        case .month:
            return monthTitle
        case .week:
            return weekTitle
        case .day:
            return dayTitle
        }
    }
    
    private var yearTitle: String {
        let year = Calendar.current.component(.year, from: selectedDate)
        return String(year)
    }
    
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }
    
    private var weekTitle: String {
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
    
    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: selectedDate)
    }
    
    private func step(_ offset: Int) {
        let calendar = Calendar.current
        let component: Calendar.Component
        switch viewMode {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        if let newDate = calendar.date(byAdding: component, value: offset, to: selectedDate) {
            selectedDate = newDate
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
    
    private func getFilteredTasksForDate(_ tasks: [String: [GoogleTask]]) -> [String: [GoogleTask]] {
        // Filter tasks to show ONLY those with due dates that match the selected date
        var filteredTasks: [String: [GoogleTask]] = [:]
        
        for (listId, taskList) in tasks {
            let dateFilteredTasks = taskList.filter { task in
                // Only show tasks that have a due date AND it matches the selected date
                guard let dueDate = task.dueDate else { 
                    return false // Tasks without due dates are NOT shown
                }
                
                // Check if the due date is the same day as selected date
                return Calendar.current.isDate(dueDate, inSameDayAs: selectedDate)
            }
            
            // Only include the list if it has tasks after filtering
            if !dateFilteredTasks.isEmpty {
                filteredTasks[listId] = dateFilteredTasks
            }
        }
        
        return filteredTasks
    }
}

extension ViewMode {
    var displayName: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}