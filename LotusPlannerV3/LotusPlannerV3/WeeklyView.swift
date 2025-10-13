import SwiftUI

enum WeeklyViewMode: String, CaseIterable, Hashable {
    case week
}

struct WeeklyView: View {
    @EnvironmentObject var appPrefs: AppPreferences
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var logsViewModel = LogsViewModel.shared
    
    @State private var selectedDate = Date()
    @State private var viewMode: WeeklyViewMode = .week
    @State private var selectedCalendarEvent: GoogleCalendarEvent?
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    struct WeeklyTaskSelection: Identifiable {
        let id = UUID()
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    @State private var taskSheetSelection: WeeklyTaskSelection?
    @State private var showingAddEvent = false
    @State private var showingNewTask = false
    @State private var scrollToCurrentDayTrigger = false
    
    var body: some View {
        VStack(spacing: 0) {
            GlobalNavBar()
                .background(.ultraThinMaterial)
            
            mainContent
        }
        .sidebarToggleHidden()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showingAddEvent) {
            AddItemView(
                currentDate: selectedDate,
                tasksViewModel: tasksViewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        .sheet(item: $taskSheetSelection) { sel in
            TaskDetailsView(
                task: sel.task,
                taskListId: sel.listId,
                accountKind: sel.accountKind,
                accentColor: sel.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { updatedTask in
                    Task {
                        await tasksViewModel.updateTask(updatedTask, in: sel.listId, for: sel.accountKind)
                    }
                },
                onDelete: {
                    Task {
                        await tasksViewModel.deleteTask(sel.task, from: sel.listId, for: sel.accountKind)
                    }
                },
                onMove: { updatedTask, targetListId in
                    Task {
                        await tasksViewModel.moveTask(updatedTask, from: sel.listId, to: targetListId, for: sel.accountKind)
                    }
                },
                onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                    Task {
                        await tasksViewModel.crossAccountMoveTask(updatedTask, from: (sel.accountKind, sel.listId), to: (targetAccountKind, targetListId))
                    }
                }
            )
        }
        .sheet(isPresented: $showingNewTask) {
            // Create-task UI matching TasksView create flow
            let personalLinked = authManager.isLinked(kind: .personal)
            let professionalLinked = authManager.isLinked(kind: .professional)
            let defaultAccount: GoogleAuthManager.AccountKind = selectedAccountKind ?? (personalLinked ? .personal : .professional)
            let defaultLists = defaultAccount == .personal ? tasksViewModel.personalTaskLists : tasksViewModel.professionalTaskLists
            let defaultListId = defaultLists.first?.id ?? ""
            let newTask = GoogleTask(
                id: UUID().uuidString,
                title: "",
                notes: nil,
                status: "needsAction",
                due: nil,
                completed: nil,
                updated: nil
            )
            TaskDetailsView(
                task: newTask,
                taskListId: defaultListId,
                accountKind: defaultAccount,
                accentColor: defaultAccount == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: tasksViewModel.personalTaskLists,
                professionalTaskLists: tasksViewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: tasksViewModel,
                onSave: { _ in },
                onDelete: {},
                onMove: { _, _ in },
                onCrossAccountMove: { _, _, _ in },
                isNew: true
            )
        }
        .task {
            // Initialize selectedDate from navigation manager if available
            selectedDate = navigationManager.currentDate
            
            // Clear caches and load fresh data
            calendarViewModel.clearAllData()
            await tasksViewModel.loadTasks(forceClear: true)
            await calendarViewModel.loadCalendarDataForWeek(containing: selectedDate)
            
            await MainActor.run {
                // Force view updates
                calendarViewModel.objectWillChange.send()
                tasksViewModel.objectWillChange.send()
            }
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            selectedDate = newValue
            // Scroll to current day when date changes
            scrollToCurrentDayTrigger.toggle()
            
            Task {
                // Clear caches and load fresh data
                calendarViewModel.clearAllData()
                await tasksViewModel.loadTasks(forceClear: true)
                await calendarViewModel.loadCalendarDataForWeek(containing: newValue)
                
                await MainActor.run {
                    // Force view updates
                    calendarViewModel.objectWillChange.send()
                    tasksViewModel.objectWillChange.send()
                }
            }
        }
        .onChange(of: navigationManager.currentInterval) { oldValue, newValue in
            Task {
                // Clear caches and load fresh data
                calendarViewModel.clearAllData()
                await tasksViewModel.loadTasks(forceClear: true)
                
                // Load data based on interval
                switch newValue {
                case .day:
                    await calendarViewModel.loadCalendarData(for: selectedDate)
                case .week:
                    await calendarViewModel.loadCalendarDataForWeek(containing: selectedDate)
                case .month:
                    await calendarViewModel.loadCalendarDataForMonth(containing: selectedDate)
                case .year:
                    await calendarViewModel.loadCalendarDataForMonth(containing: selectedDate)
                }
                
                await MainActor.run {
                    // Force view updates
                    calendarViewModel.objectWillChange.send()
                    tasksViewModel.objectWillChange.send()
                }
            }
        }
    }
    
    
    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        if appPrefs.useRowBasedWeeklyView {
            // Row-based layout: each day is a row
            weekRowBasedViewWithStickyColumn
        } else {
            // Column-based layout: 7 columns for days
            weekColumnBasedViewWithStickyHeader
        }
    }
    
    // MARK: - Column-Based View with Sticky Header
    private var weekColumnBasedViewWithStickyHeader: some View {
        let fixedWidth: CGFloat = 1600
        let dayColumnWidth = fixedWidth / 7
        
        return VStack(spacing: 0) {
            // Fixed date header
            ScrollView(.horizontal, showsIndicators: false) {
                weekTasksDateHeader(dayColumnWidth: dayColumnWidth, timeColumnWidth: 50)
                    .frame(width: fixedWidth)
            }
            .background(Color(.systemGray6))
            
            // Divider below date header
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 1)
            
            // Scrollable content (both vertical and horizontal)
            GeometryReader { geometry in
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    ScrollViewReader { proxy in
                        weekTasksContent(dayColumnWidth: dayColumnWidth, fixedWidth: fixedWidth)
                            .onAppear {
                                scrollToCurrentDayWithProxy(proxy)
                            }
                            .onChange(of: scrollToCurrentDayTrigger) { _ in
                                scrollToCurrentDayWithProxy(proxy)
                            }
                    }
                    .padding([.horizontal, .bottom], 8)
                }
                .background(Color(.systemBackground))
            }
        }
    }
    }


// MARK: - Helpers

extension WeeklyView {
    // MARK: - Task Views

    
    // MARK: - Week Tasks Content (without header)
    private func weekTasksContent(dayColumnWidth: CGFloat, fixedWidth: CGFloat) -> some View {
        // Determine whether there are any tasks to show this week for each account
        let personalHasAny = weekDates.contains { date in
            let dict = getFilteredTasksForSpecificDate(tasksViewModel.personalTasks, date: date)
            return !dict.allSatisfy { $0.value.isEmpty }
        }
        let professionalHasAny = weekDates.contains { date in
            let dict = getFilteredTasksForSpecificDate(tasksViewModel.professionalTasks, date: date)
            return !dict.allSatisfy { $0.value.isEmpty }
        }

        return VStack(spacing: 0) {
            // Events Row (always shown)
            VStack(alignment: .leading, spacing: 4) {
                // Fixed-width 7-day event columns
                HStack(alignment: .top, spacing: 0) {
                    // 7-day event columns with fixed width
                    ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                        weekEventColumn(date: date)
                            .frame(width: dayColumnWidth, alignment: .top) // Fixed width matching timeline
                            .background(Color(.systemBackground))
                            .overlay(
                                Rectangle()
                                    .fill(Color(.systemGray4))
                                    .frame(width: 0.5),
                                alignment: .trailing
                            )
                            .id("event_day_\(index)")
                    }
                }
                .frame(width: fixedWidth) // Total fixed width
            }
            .padding(.all, 8)
            .background(Color(.systemGray6).opacity(0.15))
            
            // Divider after events row (before personal tasks)
            Rectangle()
                .fill(Color(.systemGray3))
                .frame(height: 2)

            // Personal Tasks Row
            if authManager.isLinked(kind: .personal) && personalHasAny {
                VStack(alignment: .leading, spacing: 4) {
                    
                    // Fixed-width 7-day task columns
                    HStack(spacing: 0) {
                        // 7-day task columns with fixed width
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            weekTaskColumnPersonal(date: date)
                                .frame(width: dayColumnWidth) // Fixed width matching timeline
                                .background(Color(.systemBackground))
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                                .id("day_\(index)")
                        }
                    }
                    .frame(width: fixedWidth) // Total fixed width
                }
                .padding(.all, 8)
                .background(Color(.systemGray6).opacity(0.3))
            }
            
            // Divider between task types
            if authManager.isLinked(kind: .personal) && authManager.isLinked(kind: .professional) && personalHasAny && professionalHasAny {
                Rectangle()
                    .fill(Color(.systemGray3))
                    .frame(height: 2)
            }
            
            // Professional Tasks Row
            if authManager.isLinked(kind: .professional) && professionalHasAny {
                VStack(alignment: .leading, spacing: 4) {
                    
                    // Fixed-width 7-day task columns
                    HStack(spacing: 0) {
                        // 7-day task columns with fixed width
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            weekTaskColumnProfessional(date: date)
                                .frame(width: dayColumnWidth) // Fixed width matching timeline
                                .background(Color(.systemBackground))
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                                .id("day_\(index)")
                        }
                    }
                    .frame(width: fixedWidth) // Total fixed width
                }
                .padding(.all, 8)
                .background(Color(.systemGray6).opacity(0.3))
            }
            
            // Divider after tasks row (before weight logs)
            if appPrefs.showWeightLogs {
                Rectangle()
                    .fill(Color(.systemGray3))
                    .frame(height: 2)
            }
            
            // Weight Logs Row
            if appPrefs.showWeightLogs {
                VStack(alignment: .leading, spacing: 4) {
                    
                    // Fixed-width 7-day weight log columns
                    HStack(spacing: 0) {
                        // 7-day weight log columns with fixed width
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            weekWeightLogColumn(date: date)
                                .frame(width: dayColumnWidth) // Fixed width matching timeline
                                .background(Color(.systemBackground))
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                                .id("weight_day_\(index)")
                        }
                    }
                    .frame(width: fixedWidth) // Total fixed width
                }
                .padding(.all, 8)
                .background(Color(.systemGray6).opacity(0.15))
            }
            
            // Divider after weight logs (before workout logs)
            if appPrefs.showWorkoutLogs {
                Rectangle()
                    .fill(Color(.systemGray3))
                    .frame(height: 2)
            }
            
            // Workout Logs Row
            if appPrefs.showWorkoutLogs {
                VStack(alignment: .leading, spacing: 4) {
                    
                    // Fixed-width 7-day workout log columns
                    HStack(spacing: 0) {
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            weekWorkoutLogColumn(date: date)
                                .frame(width: dayColumnWidth)
                                .background(Color(.systemBackground))
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                                .id("workout_day_\(index)")
                        }
                    }
                    .frame(width: fixedWidth)
                }
                .padding(.all, 8)
                .background(Color(.systemGray6).opacity(0.15))
            }
            
            // Divider after workout logs (before food logs)
            if appPrefs.showFoodLogs {
                Rectangle()
                    .fill(Color(.systemGray3))
                    .frame(height: 2)
            }
            
            // Food Logs Row
            if appPrefs.showFoodLogs {
                VStack(alignment: .leading, spacing: 4) {
                    
                    // Fixed-width 7-day food log columns
                    HStack(spacing: 0) {
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            weekFoodLogColumn(date: date)
                                .frame(width: dayColumnWidth)
                                .background(Color(.systemBackground))
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                                .id("food_day_\(index)")
                        }
                    }
                    .frame(width: fixedWidth)
                }
                .padding(.all, 8)
                .background(Color(.systemGray6).opacity(0.15))
            }
            
            // Divider after food logs (before water logs)
            if appPrefs.showWaterLogs {
                Rectangle()
                    .fill(Color(.systemGray3))
                    .frame(height: 2)
            }
            
            // Water Logs Row
            if appPrefs.showWaterLogs {
                VStack(alignment: .leading, spacing: 4) {
                    
                    // Fixed-width 7-day water log columns
                    HStack(spacing: 0) {
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            weekWaterLogColumn(date: date)
                                .frame(width: dayColumnWidth)
                                .background(Color(.systemBackground))
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                                .id("water_day_\(index)")
                        }
                    }
                    .frame(width: fixedWidth)
                }
                .padding(.all, 8)
                .background(Color(.systemGray6).opacity(0.15))
            }
            
            // Empty state message when no accounts are linked
            if !authManager.isLinked(kind: .personal) && !authManager.isLinked(kind: .professional) {
                Button(action: { NavigationManager.shared.showSettings() }) {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Link Your Google Account")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Connect your Google account to view and manage your calendar events and tasks")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 60)
                }
                .buttonStyle(.plain)
            }
            // Show "No tasks" message when accounts are linked but no tasks exist
            else if !personalHasAny && !professionalHasAny {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No Tasks This Week")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("You're all caught up! No tasks are due this week.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 60)
            }
        }
    }
    
    // MARK: - Row-Based Week View with Sticky Column
    private var weekRowBasedViewWithStickyColumn: some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                // Fixed/Sticky date column
                VStack(spacing: 0) {
                    ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                        weekDayColumnSticky(date: date, isToday: Calendar.current.isDate(date, inSameDayAs: Date()))
                        
                        if index < weekDates.count - 1 {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 1)
                        }
                    }
                }
                .frame(width: 100)
                .background(Color(.systemGray6))
                
                Divider()
                
                // Scrollable content (without date column)
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            weekDayRowContent(date: date, isToday: Calendar.current.isDate(date, inSameDayAs: Date()))
                            
                            if index < weekDates.count - 1 {
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                    .padding(.all, 8)
                }
            }
        }
    }
    
    private func weekDayColumnSticky(date: Date, isToday: Bool) -> some View {
        Button(action: {
            // Navigate to day view for this date
            navigationManager.updateInterval(.day, date: date)
        }) {
            VStack(alignment: .center, spacing: 2) {
                Text(dayOfWeekAbbrev(from: date))
                    .font(DateDisplayStyle.bodyFont)
                    .fontWeight(.semibold)
                    .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.secondaryColor)
                
                Text(formatDateShort(from: date))
                    .font(DateDisplayStyle.titleFont)
                    .fontWeight(.bold)
                    .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.primaryColor)
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
    
    private func weekDayRowContent(date: Date, isToday: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Events column
            VStack(alignment: .leading, spacing: 4) {
                let eventsForDate = getEventsForDate(date)
                ForEach(eventsForDate, id: \.id) { event in
                    rowEventCard(event: event)
                }
                Spacer(minLength: 0)
            }
            .padding(.all, 8)
            .frame(width: 228.6, alignment: .topLeading)
            .frame(minHeight: 80)
            
            Divider()
            
            // Personal Tasks column
            if authManager.isLinked(kind: .personal) {
                VStack(alignment: .leading, spacing: 4) {
                    let personalTasksForDate = getFilteredTasksForSpecificDate(tasksViewModel.personalTasks, date: date)
                    if !personalTasksForDate.allSatisfy({ $0.value.isEmpty }) {
                        TasksComponent(
                            taskLists: tasksViewModel.personalTaskLists,
                            tasksDict: personalTasksForDate,
                            accentColor: appPrefs.personalColor,
                            accountType: .personal,
                            onTaskToggle: { task, listId in
                                Task {
                                    await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: .personal)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                                }
                            },
                            hideDueDateTag: true,
                            showEmptyState: false,
                            isSingleDayView: true
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(.all, 8)
                .frame(width: 228.6, alignment: .topLeading)
                .frame(minHeight: 80)
                
                Divider()
            }
            
            // Professional Tasks column
            if authManager.isLinked(kind: .professional) {
                VStack(alignment: .leading, spacing: 4) {
                    let professionalTasksForDate = getFilteredTasksForSpecificDate(tasksViewModel.professionalTasks, date: date)
                    if !professionalTasksForDate.allSatisfy({ $0.value.isEmpty }) {
                        TasksComponent(
                            taskLists: tasksViewModel.professionalTaskLists,
                            tasksDict: professionalTasksForDate,
                            accentColor: appPrefs.professionalColor,
                            accountType: .professional,
                            onTaskToggle: { task, listId in
                                Task {
                                    await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: .professional)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                                }
                            },
                            hideDueDateTag: true,
                            showEmptyState: false,
                            isSingleDayView: true
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(.all, 8)
                .frame(width: 228.6, alignment: .topLeading)
                .frame(minHeight: 80)
                
                Divider()
            }
            
            // Weight Logs column
            if appPrefs.showWeightLogs {
                VStack(alignment: .leading, spacing: 4) {
                    let weightLogsForDate = getWeightLogsForDate(date)
                    ForEach(weightLogsForDate, id: \.id) { entry in
                        weightLogCard(entry: entry)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.all, 8)
                .frame(width: 228.6, alignment: .topLeading)
                .frame(minHeight: 80)
                
                Divider()
            }
            
            // Workout Logs column
            if appPrefs.showWorkoutLogs {
                VStack(alignment: .leading, spacing: 4) {
                    let workoutLogsForDate = getWorkoutLogsForDate(date)
                    ForEach(workoutLogsForDate, id: \.id) { entry in
                        workoutLogCard(entry: entry)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.all, 8)
                .frame(width: 228.6, alignment: .topLeading)
                .frame(minHeight: 80)
                
                Divider()
            }
            
            // Food Logs column
            if appPrefs.showFoodLogs {
                VStack(alignment: .leading, spacing: 4) {
                    let foodLogsForDate = getFoodLogsForDate(date)
                    ForEach(foodLogsForDate, id: \.id) { entry in
                        foodLogCard(entry: entry)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.all, 8)
                .frame(width: 228.6, alignment: .topLeading)
                .frame(minHeight: 80)
                
                Divider()
            }
            
            // Water Logs column
            if appPrefs.showWaterLogs {
                VStack(alignment: .leading, spacing: 4) {
                    let waterLogsForDate = getWaterLogsForDate(date)
                    if !waterLogsForDate.isEmpty {
                        waterLogSummary(entries: waterLogsForDate)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.all, 8)
                .frame(width: 228.6, alignment: .topLeading)
                .frame(minHeight: 80)
            }
        }
    }
    
    private func weekDayRow(date: Date, isToday: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Day column - clickable
            Button(action: {
                // Navigate to day view for this date
                navigationManager.updateInterval(.day, date: date)
            }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DateFormatter.standardDayOfWeek.string(from: date).uppercased())
                        .font(DateDisplayStyle.bodyFont)
                        .fontWeight(.semibold)
                        .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.secondaryColor)
                    
                    Text(DateFormatter.standardDate.string(from: date))
                        .font(DateDisplayStyle.titleFont)
                        .fontWeight(.bold)
                        .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.primaryColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.all, 8)
            }
            .buttonStyle(.plain)
            .frame(width: 120)
            .frame(maxHeight: .infinity)
            .background(isToday ? Color.blue : Color(.systemGray6))
            
            Divider()
            
            // Events column
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    let eventsForDate = getEventsForDate(date)
                    ForEach(eventsForDate, id: \.id) { event in
                        rowEventCard(event: event)
                    }
                }
                .padding(.all, 8)
            }
            .frame(minWidth: 200, maxWidth: .infinity, alignment: .topLeading)
            
            Divider()
            
            // Personal Tasks column
            if authManager.isLinked(kind: .personal) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        let personalTasksForDate = getFilteredTasksForSpecificDate(tasksViewModel.personalTasks, date: date)
                        if !personalTasksForDate.allSatisfy({ $0.value.isEmpty }) {
                            TasksComponent(
                                taskLists: tasksViewModel.personalTaskLists,
                                tasksDict: personalTasksForDate,
                                accentColor: appPrefs.personalColor,
                                accountType: .personal,
                                onTaskToggle: { task, listId in
                                    Task {
                                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                    }
                                },
                                onTaskDetails: { task, listId in
                                    taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: .personal)
                                },
                                onListRename: { listId, newName in
                                    Task {
                                        await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                                    }
                                },
                                onOrderChanged: { newOrder in
                                    Task {
                                        await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                                    }
                                },
                                hideDueDateTag: true,
                                showEmptyState: false,
                                isSingleDayView: true
                            )
                        }
                    }
                    .padding(.all, 8)
                }
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .topLeading)
                
                Divider()
            }
            
            // Professional Tasks column
            if authManager.isLinked(kind: .professional) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        let professionalTasksForDate = getFilteredTasksForSpecificDate(tasksViewModel.professionalTasks, date: date)
                        if !professionalTasksForDate.allSatisfy({ $0.value.isEmpty }) {
                            TasksComponent(
                                taskLists: tasksViewModel.professionalTaskLists,
                                tasksDict: professionalTasksForDate,
                                accentColor: appPrefs.professionalColor,
                                accountType: .professional,
                                onTaskToggle: { task, listId in
                                    Task {
                                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                                    }
                                },
                                onTaskDetails: { task, listId in
                                    taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: .professional)
                                },
                                onListRename: { listId, newName in
                                    Task {
                                        await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                                    }
                                },
                                onOrderChanged: { newOrder in
                                    Task {
                                        await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                                    }
                                },
                                hideDueDateTag: true,
                                showEmptyState: false,
                                isSingleDayView: true
                            )
                        }
                    }
                    .padding(.all, 8)
                }
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .topLeading)
                
                Divider()
            }
            
            // Weight Logs column
            if appPrefs.showWeightLogs {
                VStack(alignment: .leading, spacing: 4) {
                    let weightLogsForDate = getWeightLogsForDate(date)
                    ForEach(weightLogsForDate, id: \.id) { entry in
                        weightLogCard(entry: entry)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.all, 8)
                .frame(minWidth: 200, maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            }
        }
        .frame(minHeight: 120)
    }
    
    private func rowEventCard(event: GoogleCalendarEvent) -> some View {
        let isPersonal = calendarViewModel.personalEvents.contains { $0.id == event.id }
        let eventColor = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return Button(action: {
            selectedCalendarEvent = event
        }) {
            HStack(alignment: .top, spacing: 8) {
                // Time
                if let startTime = event.startTime {
                    Text(formatEventTimeShort(startTime))
                        .font(.caption)
                        .foregroundColor(eventColor)
                        .fontWeight(.semibold)
                        .frame(width: 50, alignment: .leading)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    // Title
                    Text(event.summary)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Location
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Circle()
                    .fill(eventColor)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(eventColor.opacity(0.1))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(eventColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // Calendar-related views removed since we only show tasks now
    

    
    
    private func step(_ offset: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) {
            selectedDate = newDate
            navigationManager.updateInterval(.week, date: newDate)
        }
    }
    
    // Calendar event functions removed - only tasks are displayed now
    
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
    
    // Calendar event helper functions removed since we only show tasks now
    
    // MARK: - Week Event Functions
    private func weekEventColumn(date: Date) -> some View {
        let eventsForDate = getEventsForDate(date)
        
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(eventsForDate, id: \.id) { event in
                weekEventCard(event: event)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .top)
    }
    
    private func weekWeightLogColumn(date: Date) -> some View {
        let weightLogsForDate = getWeightLogsForDate(date)
        
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(weightLogsForDate, id: \.id) { entry in
                weekWeightLogCard(entry: entry)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func weekWeightLogCard(entry: WeightLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Time
            Text(formatLogTime(entry.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
                .fontWeight(.semibold)
            
            // Weight value
            Text("\(String(format: "%.1f", entry.weight)) \(entry.unit.displayName)")
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }
    
    private func weekWorkoutLogColumn(date: Date) -> some View {
        let workoutLogsForDate = getWorkoutLogsForDate(date)
        
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(workoutLogsForDate, id: \.id) { entry in
                weekWorkoutLogCard(entry: entry)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func weekWorkoutLogCard(entry: WorkoutLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Time
            Text(formatLogTime(entry.date))
                .font(.caption2)
                .foregroundColor(.secondary)
                .fontWeight(.semibold)
            
            // Workout name
            Text(entry.name)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }
    
    private func weekFoodLogColumn(date: Date) -> some View {
        let foodLogsForDate = getFoodLogsForDate(date)
        
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(foodLogsForDate, id: \.id) { entry in
                weekFoodLogCard(entry: entry)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func weekFoodLogCard(entry: FoodLogEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            // Bullet point
            Text("•")
                .font(.body)
                .foregroundColor(.secondary)
            
            // Food name
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    
    private func weekWaterLogColumn(date: Date) -> some View {
        let waterLogsForDate = getWaterLogsForDate(date)
        let totalCups = waterLogsForDate.reduce(0) { total, entry in
            total + entry.cupsFilled.filter { $0 }.count
        }
        
        return VStack(alignment: .leading, spacing: 4) {
            if totalCups > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.body)
                        .foregroundColor(.blue)
                    Text("\(totalCups) cups")
                        .font(.body)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func weekEventCard(event: GoogleCalendarEvent) -> some View {
        let isPersonal = calendarViewModel.personalEvents.contains { $0.id == event.id }
        let eventColor = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor
        
        return Button(action: {
            selectedCalendarEvent = event
        }) {
            VStack(alignment: .leading, spacing: 2) {
                // Event time
                if let startTime = event.startTime {
                    Text(formatEventTimeShort(startTime))
                        .font(.caption2)
                        .foregroundColor(eventColor)
                        .fontWeight(.semibold)
                }
                
                // Event title
                Text(event.summary)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Event location (if available)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(eventColor.opacity(0.15))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(eventColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func formatEventTimeShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func getEventsForDate(_ date: Date) -> [GoogleCalendarEvent] {
        let allEvents = calendarViewModel.personalEvents + calendarViewModel.professionalEvents
        
        return allEvents.filter { event in
            guard let startTime = event.startTime else { return false }
            return Calendar.current.isDate(startTime, inSameDayAs: date)
        }.sorted { (a, b) in
            let aDate = a.startTime ?? Date.distantPast
            let bDate = b.startTime ?? Date.distantPast
            return aDate < bDate
        }
    }
    
    private func getWeightLogsForDate(_ date: Date) -> [WeightLogEntry] {
        return logsViewModel.weightEntries.filter { entry in
            Calendar.current.isDate(entry.timestamp, inSameDayAs: date)
        }.sorted { $0.timestamp < $1.timestamp }
    }
    
    private func getWorkoutLogsForDate(_ date: Date) -> [WorkoutLogEntry] {
        return logsViewModel.workoutEntries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: date)
        }.sorted { $0.date < $1.date }
    }
    
    private func getFoodLogsForDate(_ date: Date) -> [FoodLogEntry] {
        return logsViewModel.foodEntries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: date)
        }.sorted { $0.date < $1.date }
    }
    
    private func getWaterLogsForDate(_ date: Date) -> [WaterLogEntry] {
        return logsViewModel.waterEntries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: date)
        }.sorted { $0.date < $1.date }
    }
    
    private func weightLogCard(entry: WeightLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Time
            Text(formatLogTime(entry.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            // Weight value
            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(format: "%.1f", entry.weight)) \(entry.unit.displayName)")
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }
    
    private func formatLogTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    private func workoutLogCard(entry: WorkoutLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Time
            Text(formatLogTime(entry.date))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            // Workout name
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }
    
    private func foodLogCard(entry: FoodLogEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            // Bullet point
            Text("•")
                .font(.body)
                .foregroundColor(.secondary)
            
            // Food name
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
    
    private func waterLogSummary(entries: [WaterLogEntry]) -> some View {
        let totalCups = entries.reduce(0) { total, entry in
            total + entry.cupsFilled.filter { $0 }.count
        }
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.body)
                    .foregroundColor(.blue)
                Text("\(totalCups) cups")
                    .font(.body)
                    .fontWeight(.medium)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }
    
    // MARK: - Week Task Functions
    private func weekTasksDateHeader(dayColumnWidth: CGFloat, timeColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Day headers
            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                weekTaskDateHeaderView(date: date)
                    .frame(width: dayColumnWidth, height: 60)
                    .background(Color(.systemGray6))
                    .overlay(
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
                    .id("day_\(index)")
            }
        }
        .background(Color(.systemBackground))
    }
    
    private func weekTaskDateHeaderView(date: Date) -> some View {
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        
        return VStack(spacing: 4) {
            // Standardized day of week format: MON, TUE, etc.
            Text(DateFormatter.standardDayOfWeek.string(from: date).uppercased())
                .font(DateDisplayStyle.bodyFont)
                .fontWeight(.semibold)
                .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.secondaryColor)
            
            // Standardized date format: m/d/yy
            Text(DateFormatter.standardDate.string(from: date))
                .font(DateDisplayStyle.titleFont)
                .fontWeight(.bold)
                .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.primaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isToday ? Color.blue : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            // Update the selected date
            selectedDate = date
            // Navigate to day view for the selected date
            navigationManager.updateInterval(.day, date: date)
        }
    }
    
    private func weekTaskColumnPersonal(date: Date) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            // Personal Tasks using day view component
            let personalTasksForDate = getFilteredTasksForSpecificDate(tasksViewModel.personalTasks, date: date)
            if !personalTasksForDate.allSatisfy({ $0.value.isEmpty }) {
                TasksComponent(
                    taskLists: tasksViewModel.personalTaskLists,
                    tasksDict: personalTasksForDate,
                    accentColor: appPrefs.personalColor,
                    accountType: .personal,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: .personal)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .personal)
                        }
                    },
                    hideDueDateTag: false,
                    showEmptyState: false,
                    isSingleDayView: true
                )
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
    
    private func weekTaskColumnProfessional(date: Date) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            // Professional Tasks using day view component
            let professionalTasksForDate = getFilteredTasksForSpecificDate(tasksViewModel.professionalTasks, date: date)
            if !professionalTasksForDate.allSatisfy({ $0.value.isEmpty }) {
                TasksComponent(
                    taskLists: tasksViewModel.professionalTaskLists,
                    tasksDict: professionalTasksForDate,
                    accentColor: appPrefs.professionalColor,
                    accountType: .professional,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: .professional)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .professional)
                        }
                    },
                    hideDueDateTag: false,
                    showEmptyState: false,
                    isSingleDayView: true
                )
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
    
    // Helper function to get filtered tasks for a specific date (for weekly view)
    private func getFilteredTasksForSpecificDate(_ tasks: [String: [GoogleTask]], date: Date) -> [String: [GoogleTask]] {
        var filteredTasks: [String: [GoogleTask]] = [:]
        
        for (listId, taskList) in tasks {
            let dateFilteredTasks = taskList.filter { task in
                // Only show tasks that have a due date AND it matches the specified date
                guard let dueDate = task.dueDate else { 
                    return false // Tasks without due dates are NOT shown
                }
                
                // Check if the due date is the same day as the specified date
                return Calendar.current.isDate(dueDate, inSameDayAs: date)
            }
            
            // Only include the list if it has tasks after filtering
            if !dateFilteredTasks.isEmpty {
                filteredTasks[listId] = dateFilteredTasks
            }
        }
        
        return filteredTasks
    }
    
    private func findTaskListId(for task: GoogleTask, in accountKind: GoogleAuthManager.AccountKind) -> String? {
        let tasksDict = accountKind == .personal ? tasksViewModel.personalTasks : tasksViewModel.professionalTasks
        
        for (listId, tasks) in tasksDict {
            if tasks.contains(where: { $0.id == task.id }) {
                return listId
            }
        }
        
        return nil
    }
    
    // Calendar header functions removed since we only show tasks now
    
    // All calendar-related timeline functions removed since we only show tasks now
    
    // MARK: - Scrolling Functions
    private func scrollToCurrentDay() {
        // Find the current day in the week using the same calendar as weekDates
        let today = Date()
        let calendar = Calendar.mondayFirst
        
        // Find which day of the week today is (0 = Monday, 6 = Sunday)
        let todayWeekday = calendar.component(.weekday, from: today)
        let mondayWeekday = 2 // Monday is weekday 2 in Calendar.current
        let dayIndex = (todayWeekday - mondayWeekday + 7) % 7
        
        // Trigger scroll by toggling the state
        scrollToCurrentDayTrigger.toggle()
    }
    
    private func scrollToCurrentDayWithProxy(_ proxy: ScrollViewProxy) {
        // Find the current day in the week using the same calendar as weekDates
        let today = Date()
        let calendar = Calendar.mondayFirst
        
        // Find which day of the week today is (0 = Monday, 6 = Sunday)
        let todayWeekday = calendar.component(.weekday, from: today)
        let mondayWeekday = 2 // Monday is weekday 2 in Calendar.current
        let dayIndex = (todayWeekday - mondayWeekday + 7) % 7
        
        // Scroll to the current day column
        withAnimation(.easeInOut(duration: 0.5)) {
            proxy.scrollTo("day_\(dayIndex)", anchor: .center)
        }
    }

}



extension WeeklyViewMode {
    var displayName: String {
        switch self {
        case .week: return "Week"
        }
    }
}

// MARK: - View Extension for Conditional Modifiers
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
