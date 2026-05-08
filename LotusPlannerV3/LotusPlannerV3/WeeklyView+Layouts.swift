import SwiftUI

/// Column-based and row-based week layout view trees plus the per-day row helpers (events column, tasks columns, log column, fixed/flex log cells, day row content). Together this is the bulk of the W view's rendering. Split out from the main WeeklyView.swift so the View body reads independently from the ~1,200 lines of layout-mode rendering.
extension WeeklyView {

    // MARK: - Task Views

    
    // MARK: - Week Tasks Content (without header)
    func weekTasksContent(dayColumnWidth: CGFloat, fixedWidth: CGFloat) -> some View {
        // Determine whether there are any tasks to show this week for each account
        let personalHasAny = weekDates.contains { date in
            let dict = getFilteredTasksForSpecificDate(date: date, accountKind: .personal)
            return !dict.allSatisfy { $0.value.isEmpty }
        }
        let professionalHasAny = weekDates.contains { date in
            let dict = getFilteredTasksForSpecificDate(date: date, accountKind: .professional)
            return !dict.allSatisfy { $0.value.isEmpty }
        }

        return VStack(spacing: 0) {
            // Events Row (with expand/collapse header)
            VStack(alignment: .leading, spacing: 0) {
                // Events Header with expand/collapse button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        eventsExpanded.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: eventsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Events")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6).opacity(0.5))
                }
                .buttonStyle(.plain)
                
                // Events content (collapsible)
                if eventsExpanded {
                    // Fixed-width 7-day event columns
                    HStack(alignment: .top, spacing: 0) {
                        // 7-day event columns with fixed width
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            weekEventColumn(date: date)
                                .frame(width: dayColumnWidth, alignment: .top)
                                .background(Color(.systemBackground))
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                                    handleEventDrop(providers: providers, targetDate: date)
                                }
                                .id("event_day_\(index)")
                        }
                    }
                    .frame(width: fixedWidth) // Total fixed width
                    .padding(.all, 8)
                }
            }
            .background(Color(.systemGray6).opacity(0.15))
            
            // Divider after events row (before personal tasks)
            Rectangle()
                .fill(Color(.systemGray3))
                .frame(height: 2)

            // Personal Tasks Row
            if authManager.isLinked(kind: .personal) && personalHasAny {
                VStack(alignment: .leading, spacing: 0) {
                    // Personal Tasks Header with expand/collapse button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            personalTasksExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: personalTasksExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(appPrefs.personalAccountName) Tasks")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6).opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                    // Personal Tasks content (collapsible)
                    if personalTasksExpanded {
                        // Fixed-width 7-day task columns
                        HStack(alignment: .top, spacing: 0) {
                            // 7-day task columns with fixed width
                            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                                weekTaskColumnPersonal(date: date)
                                    .frame(width: dayColumnWidth, alignment: .top)
                                    .background(Color(.systemBackground))
                                    .overlay(
                                        Rectangle()
                                            .fill(Color(.systemGray4))
                                            .frame(width: 0.5),
                                        alignment: .trailing
                                    )
                                    .dropDestination(for: DraggableTaskInfo.self) { items, _ in
                                        guard let item = items.first else { return false }
                                        handleTaskDrop(item, to: date)
                                        return true
                                    } isTargeted: { isTargeted in
                                        // Optional: highlight column when dragging over
                                    }
                                    .id("day_\(index)")
                            }
                        }
                        .frame(width: fixedWidth) // Total fixed width
                        .padding(.all, 8)
                    }
                }
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
                VStack(alignment: .leading, spacing: 0) {
                    // Professional Tasks Header with expand/collapse button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            professionalTasksExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: professionalTasksExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(appPrefs.professionalAccountName) Tasks")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6).opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                    // Professional Tasks content (collapsible)
                    if professionalTasksExpanded {
                        // Fixed-width 7-day task columns
                        HStack(alignment: .top, spacing: 0) {
                            // 7-day task columns with fixed width
                            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                                weekTaskColumnProfessional(date: date)
                                    .frame(width: dayColumnWidth, alignment: .top)
                                    .background(Color(.systemBackground))
                                    .overlay(
                                        Rectangle()
                                            .fill(Color(.systemGray4))
                                            .frame(width: 0.5),
                                        alignment: .trailing
                                    )
                                    .dropDestination(for: DraggableTaskInfo.self) { items, _ in
                                        guard let item = items.first else { return false }
                                        handleTaskDrop(item, to: date)
                                        return true
                                    } isTargeted: { _ in }
                                    .id("day_\(index)")
                            }
                        }
                        .frame(width: fixedWidth) // Total fixed width
                        .padding(.all, 8)
                    }
                }
                .background(Color(.systemGray6).opacity(0.3))
            }
            
            // Logs Section (all log types under one collapsible header)
            if appPrefs.showSleepLogs || appPrefs.showWeightLogs || appPrefs.showWorkoutLogs || appPrefs.showFoodLogs || appPrefs.showWaterLogs || (appPrefs.showCustomLogs && hasCustomLogsForWeek(in: 0)) || (appPrefs.showCustomLogs2 && hasCustomLogsForWeek(in: 1)) {
                // Divider before logs section
                Rectangle()
                    .fill(Color(.systemGray3))
                    .frame(height: 2)
                
                VStack(alignment: .leading, spacing: 0) {
                    // Logs Header with expand/collapse button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            logsExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: logsExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Logs")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6).opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                    // Logs content (collapsible)
                    if logsExpanded {
                        VStack(spacing: 0) {
                            // Logs in user-configured order (custom entry is
                            // interleaved with built-ins instead of always last).
                            let visibleEntries = appPrefs.logDisplayOrder.filter { entry in
                                switch entry {
                                case .builtIn(let t):
                                    return isBuiltInLogVisible(t)
                                case .custom:
                                    return appPrefs.showCustomLogs && hasCustomLogsForWeek(in: 0)
                                case .custom2:
                                    return appPrefs.showCustomLogs2 && hasCustomLogsForWeek(in: 1)
                                }
                            }
                            ForEach(Array(visibleEntries.enumerated()), id: \.element) { idx, entry in
                                switch entry {
                                case .builtIn(let t):
                                    weekLogRow(for: t, dayColumnWidth: dayColumnWidth, fixedWidth: fixedWidth)
                                case .custom:
                                    customLogRow(collectionIndex: 0, dayColumnWidth: dayColumnWidth, fixedWidth: fixedWidth)
                                case .custom2:
                                    customLogRow(collectionIndex: 1, dayColumnWidth: dayColumnWidth, fixedWidth: fixedWidth)
                                }

                                if idx < visibleEntries.count - 1 {
                                    Rectangle()
                                        .fill(Color(.systemGray3))
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                }
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
    var weekRowBasedViewWithStickyColumn: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Fixed/Sticky date column
                    VStack(spacing: 0) {
                        // Column headers row
                        VStack(alignment: .center, spacing: 4) {
                            Text("Date")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6).opacity(0.5))
                        
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(height: 1)
                        
                        ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                            weekDayColumnSticky(date: date, isToday: Calendar.current.isDate(date, inSameDayAs: Date()))
                                .id("day_row_\(index)")
                            
                            if index < weekDates.count - 1 {
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .frame(width: dateColumnWidth())
                    .background(Color(.systemGray6))
                    
                    Divider()
                    
                    // Scrollable content (without date column)
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 0) {
                            // Events Column
                            VStack(spacing: 0) {
                                // Events column header
                                VStack(alignment: .center, spacing: 4) {
                                    Text("Events")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                }
                                .frame(height: 44)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6).opacity(0.5))
                                
                                Rectangle()
                                    .fill(Color(.systemGray4))
                                    .frame(height: 1)
                                
                                // Events column content
                                ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                                    weekDayRowEventsColumn(date: date)
                                    
                                    if index < weekDates.count - 1 {
                                        Rectangle()
                                            .fill(Color(.systemGray5))
                                            .frame(height: 1)
                                    }
                                }
                            }
                            .frame(width: contentColumnWidth())
                            .background(Color(.systemBackground))
                            
                            Divider()
                            
                            // Personal Tasks Column
                            if authManager.isLinked(kind: .personal) {
                                VStack(spacing: 0) {
                                    // Personal Tasks column header
                                    VStack(alignment: .center, spacing: 4) {
                                        Text(appPrefs.personalAccountName)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                    }
                                    .frame(height: 44)
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.systemGray6).opacity(0.5))
                                    
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(height: 1)
                                    
                                    // Personal Tasks column content
                                    ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                                        weekDayRowPersonalTasksColumn(date: date)
                                        
                                        if index < weekDates.count - 1 {
                                            Rectangle()
                                                .fill(Color(.systemGray5))
                                                .frame(height: 1)
                                        }
                                    }
                                }
                                .frame(width: contentColumnWidth())
                                .background(Color(.systemBackground))
                                
                                Divider()
                            }
                            
                            // Professional Tasks Column
                            if authManager.isLinked(kind: .professional) {
                                VStack(spacing: 0) {
                                    // Professional Tasks column header
                                    VStack(alignment: .center, spacing: 4) {
                                        Text(appPrefs.professionalAccountName)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                    }
                                    .frame(height: 44)
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.systemGray6).opacity(0.5))
                                    
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(height: 1)
                                    
                                    // Professional Tasks column content
                                    ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                                        weekDayRowProfessionalTasksColumn(date: date)
                                        
                                        if index < weekDates.count - 1 {
                                            Rectangle()
                                                .fill(Color(.systemGray5))
                                                .frame(height: 1)
                                        }
                                    }
                                }
                                .frame(width: contentColumnWidth())
                                .background(Color(.systemBackground))
                                
                                Divider()
                            }
                            
                            // Logs Columns (no width restrictions - natural sizing)
                            if appPrefs.showSleepLogs || appPrefs.showWeightLogs || appPrefs.showWorkoutLogs || appPrefs.showFoodLogs || appPrefs.showWaterLogs || (appPrefs.showCustomLogs && hasCustomLogsForWeek(in: 0)) || (appPrefs.showCustomLogs2 && hasCustomLogsForWeek(in: 1)) {
                                VStack(spacing: 0) {
                                    // Logs column header
                                    VStack(alignment: .center, spacing: 4) {
                                        Text("Logs")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                    }
                                    .frame(height: 44)
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.systemGray6).opacity(0.5))
                                    
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(height: 1)
                                    
                                    // Logs column content
                                    ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                                        weekDayRowLogsColumn(date: date)
                                        
                                        if index < weekDates.count - 1 {
                                            Rectangle()
                                                .fill(Color(.systemGray5))
                                                .frame(height: 1)
                                        }
                                    }
                                }
                                .background(Color(.systemBackground))
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToCurrentDayRowWithProxy(proxy)
                    }
                }
                .onChange(of: scrollToCurrentDayRowTrigger) { _ in
                    scrollToCurrentDayRowWithProxy(proxy)
                }
            }
        }
    }
    
    func weekDayColumnSticky(date: Date, isToday: Bool) -> some View {
        Button(action: {
            // Navigate to day view for this date
            navigationManager.updateInterval(.day, date: date)
        }) {
            VStack(alignment: .center, spacing: 2) {
                Text(dayOfWeekAbbrev(from: date))
                    .font(.system(size: 14, weight: .semibold))
                    .fontWeight(.semibold)
                    .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.secondaryColor)

                Text(formatDateShort(from: date))
                    .font(.system(size: 16, weight: .bold))
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
    
    func dayOfWeekAbbrev(from date: Date) -> String {
        DateFormatter.standardDayOfWeek.string(from: date).uppercased()
    }
    
    func formatDateShort(from date: Date) -> String {
        DateFormatter.standardDate.string(from: date)
    }

    func streakColor(_ streak: Int) -> Color {
        if streak >= 5 { return .green }
        if streak == 4 { return .teal }
        if streak > 0 { return .red }
        return .secondary
    }

    @ViewBuilder
    func workoutStreakBadge(for date: Date) -> some View {
        let showStreak = appPrefs.showWorkoutStreak && appPrefs.showWorkoutLogs
        let showRings = appPrefs.showActivityRings
        if showStreak || showRings {
            HStack(spacing: 8) {
                if showStreak {
                    let streak = logsViewModel.workoutStreak(on: date)
                    let color = streakColor(streak)
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill")
                            .font(.body)
                            .foregroundColor(color)
                        Text("\(streak)/7")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(color)
                    }
                }

                if showRings {
                    let rings = healthKit.ringData(for: date)
                    HStack(spacing: 4) {
                        activityRingView(value: rings.moveValue, goal: rings.moveGoal, color: .red)
                        activityRingView(value: rings.exerciseValue, goal: rings.exerciseGoal, color: .green)
                        activityRingView(value: rings.standValue, goal: rings.standGoal, color: .cyan)
                    }
                }
            }
            .task(id: date) {
                guard showRings else { return }
                await healthKit.fetchActivityRings(for: date)
            }
        }
    }

    @ViewBuilder
    func activityRingView(value: Double, goal: Double, color: Color) -> some View {
        let progress = goal > 0 ? min(value / goal, 1.0) : 0
        let isComplete = goal > 0 && value >= goal
        let size: CGFloat = 16

        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
                .frame(width: size, height: size)

            if isComplete {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    // MARK: - Individual Column Views for Horizontal Layout
    func weekDayRowEventsColumn(date: Date) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) {
                let eventsForDate = getEventsForDate(date)
                ForEach(eventsForDate, id: \.id) { event in
                    rowEventCard(event: event)
                }
            }
            .padding(.all, 8)
        }
        .frame(minHeight: 80, alignment: .topLeading)
    }
    
    func weekDayRowPersonalTasksColumn(date: Date) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) {
                let personalTasksForDate = getFilteredTasksForSpecificDate(date: date, accountKind: .personal)
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
                        isSingleDayView: true,
                        showTitle: false,
                        isBulkEditMode: bulkEditManager.state.isActive,
                        selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                        onTaskSelectionToggle: { taskId in
                            if bulkEditManager.state.selectedTaskIds.contains(taskId) {
                                bulkEditManager.state.selectedTaskIds.remove(taskId)
                            } else {
                                bulkEditManager.state.selectedTaskIds.insert(taskId)
                            }
                        }
                    )
                }
            }
            .padding(.all, 8)
        }
        .frame(minHeight: 80, alignment: .topLeading)
    }
    
    func weekDayRowProfessionalTasksColumn(date: Date) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) {
                let professionalTasksForDate = getFilteredTasksForSpecificDate(date: date, accountKind: .professional)
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
                        isSingleDayView: true,
                        showTitle: false,
                        isBulkEditMode: bulkEditManager.state.isActive,
                        selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                        onTaskSelectionToggle: { taskId in
                            if bulkEditManager.state.selectedTaskIds.contains(taskId) {
                                bulkEditManager.state.selectedTaskIds.remove(taskId)
                            } else {
                                bulkEditManager.state.selectedTaskIds.insert(taskId)
                            }
                        }
                    )
                }
            }
            .padding(.all, 8)
        }
        .frame(minHeight: 80, alignment: .topLeading)
    }
    
    func weekDayRowLogsColumn(date: Date) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(appPrefs.logDisplayOrder) { entry in
                switch entry {
                case .builtIn(let t):
                    if isBuiltInLogVisible(t) {
                        weekDayRowLogCell(for: t, date: date)
                        Divider()
                    }
                case .custom:
                    if appPrefs.showCustomLogs && hasCustomLogsForDate(date, in: 0) {
                        weekDayRowCustomLogColumn(date: date, collectionIndex: 0)
                        Divider()
                    }
                case .custom2:
                    if appPrefs.showCustomLogs2 && hasCustomLogsForDate(date, in: 1) {
                        weekDayRowCustomLogColumn(date: date, collectionIndex: 1)
                        Divider()
                    }
                }
            }
        }
    }

    /// Vertical custom-log column for one date in the row-based layout.
    /// Factored out so both `.custom` and `.custom2` cases can share it.
    func weekDayRowCustomLogColumn(date: Date, collectionIndex: Int) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                let enabledItems = customLogManager.items(in: collectionIndex).filter { $0.isEnabled }
                customLogSummary(items: enabledItems, date: date)
            }
            .padding(.all, 8)
        }
        .frame(width: logColumnWidth(), alignment: .topLeading)
        .frame(minHeight: 80)
    }

    @ViewBuilder
    func weekDayRowLogCell(for logType: BuiltInLogType, date: Date) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                switch logType {
                case .food:
                    let entries = getFoodLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in foodLogCard(entry: entry) }
                case .sleep:
                    let entries = getSleepLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in sleepLogCard(entry: entry) }
                case .water:
                    let entries = getWaterLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in waterLogCard(entry: entry) }
                case .weight:
                    let entries = getWeightLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in weightLogCard(entry: entry) }
                case .workout:
                    workoutStreakBadge(for: date)
                    let entries = getWorkoutLogsForDate(date)
                    ForEach(entries, id: \.id) { entry in workoutLogCard(entry: entry) }
                }
            }
            .padding(.all, 8)
        }
        .frame(width: logColumnWidth(), alignment: .topLeading)
        .frame(minHeight: 80)
    }

    func weekDayRowContent(date: Date, isToday: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Events column
            LazyVStack(alignment: .leading, spacing: 4) {
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
                LazyVStack(alignment: .leading, spacing: 4) {
                    let personalTasksForDate = getFilteredTasksForSpecificDate(date: date, accountKind: .personal)
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
                            isSingleDayView: true,
                            isBulkEditMode: bulkEditManager.state.isActive,
                            selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                            onTaskSelectionToggle: { taskId in
                                if bulkEditManager.state.selectedTaskIds.contains(taskId) {
                                    bulkEditManager.state.selectedTaskIds.remove(taskId)
                                } else {
                                    bulkEditManager.state.selectedTaskIds.insert(taskId)
                                }
                            }
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
                LazyVStack(alignment: .leading, spacing: 4) {
                    let professionalTasksForDate = getFilteredTasksForSpecificDate(date: date, accountKind: .professional)
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
                            isSingleDayView: true,
                            isBulkEditMode: bulkEditManager.state.isActive,
                            selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                            onTaskSelectionToggle: { taskId in
                                if bulkEditManager.state.selectedTaskIds.contains(taskId) {
                                    bulkEditManager.state.selectedTaskIds.remove(taskId)
                                } else {
                                    bulkEditManager.state.selectedTaskIds.insert(taskId)
                                }
                            }
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(.all, 8)
                .frame(width: 228.6, alignment: .topLeading)
                .frame(minHeight: 80)
                
                Divider()
            }

            // Log columns in user-configured order
            ForEach(appPrefs.logDisplayOrder) { entry in
                switch entry {
                case .builtIn(let t):
                    if isBuiltInLogVisible(t) {
                        weekDayFixedLogCell(for: t, date: date, width: 228.6)
                        Divider()
                    }
                case .custom:
                    if appPrefs.showCustomLogs && hasCustomLogsForDate(date, in: 0) {
                        weekDayFixedCustomLogCell(date: date, collectionIndex: 0, width: 228.6)
                        Divider()
                    }
                case .custom2:
                    if appPrefs.showCustomLogs2 && hasCustomLogsForDate(date, in: 1) {
                        weekDayFixedCustomLogCell(date: date, collectionIndex: 1, width: 228.6)
                        Divider()
                    }
                }
            }
        }
    }

    /// Flex-width custom-log cell used by the variable-width row layout.
    /// Shared between `.custom` and `.custom2` cases.
    func weekDayRowFlexCustomLogCell(date: Date, collectionIndex: Int, isFirst: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                let enabledItems = customLogManager.items(in: collectionIndex).filter { $0.isEnabled }
                customLogSummary(items: enabledItems, date: date)
            }
            .padding(.all, 8)
        }
        .frame(
            minWidth: isFirst ? 228.6 : 200,
            maxWidth: isFirst ? 228.6 : .infinity,
            alignment: .topLeading
        )
        .frame(minHeight: 80)
    }

    /// Fixed-width custom-log cell for one date in the row-based table
    /// layout. Shared between `.custom` and `.custom2` cases.
    func weekDayFixedCustomLogCell(date: Date, collectionIndex: Int, width: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                let enabledItems = customLogManager.items(in: collectionIndex).filter { $0.isEnabled }
                customLogSummary(items: enabledItems, date: date)
            }
            .padding(.all, 8)
        }
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: 80)
    }

    func weekDayRow(date: Date, isToday: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Day column - clickable
            Button(action: {
                // Navigate to day view for this date
                navigationManager.updateInterval(.day, date: date)
            }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DateFormatter.standardDayOfWeek.string(from: date).uppercased())
                        .font(.system(size: 16, weight: .semibold))
                        .fontWeight(.semibold)
                        .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.secondaryColor)
                    
                    Text(DateFormatter.standardDate.string(from: date))
                        .font(.system(size: 20, weight: .bold))
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
                        let personalTasksForDate = getFilteredTasksForSpecificDate(date: date, accountKind: .personal)
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
                                isSingleDayView: true,
                                isBulkEditMode: bulkEditManager.state.isActive,
                                selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                                onTaskSelectionToggle: { taskId in
                                    if bulkEditManager.state.selectedTaskIds.contains(taskId) {
                                        bulkEditManager.state.selectedTaskIds.remove(taskId)
                                    } else {
                                        bulkEditManager.state.selectedTaskIds.insert(taskId)
                                    }
                                }
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
                        let professionalTasksForDate = getFilteredTasksForSpecificDate(date: date, accountKind: .professional)
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
                                isSingleDayView: true,
                                isBulkEditMode: bulkEditManager.state.isActive,
                                selectedTaskIds: bulkEditManager.state.selectedTaskIds,
                                onTaskSelectionToggle: { taskId in
                                    if bulkEditManager.state.selectedTaskIds.contains(taskId) {
                                        bulkEditManager.state.selectedTaskIds.remove(taskId)
                                    } else {
                                        bulkEditManager.state.selectedTaskIds.insert(taskId)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.all, 8)
                }
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .topLeading)
                
                Divider()
            }

            // Log columns in user-configured order (custom log interleaves with built-ins).
            let visibleEntries = appPrefs.logDisplayOrder.filter { entry in
                switch entry {
                case .builtIn(let t): return isBuiltInLogVisible(t)
                case .custom:         return appPrefs.showCustomLogs && hasCustomLogsForDate(date, in: 0)
                case .custom2:        return appPrefs.showCustomLogs2 && hasCustomLogsForDate(date, in: 1)
                }
            }
            ForEach(Array(visibleEntries.enumerated()), id: \.element) { idx, entry in
                let isFirst = idx == 0
                switch entry {
                case .builtIn(let t):
                    weekDayRowFlexLogCell(for: t, date: date, useFixedWidth: isFirst)
                case .custom:
                    weekDayRowFlexCustomLogCell(date: date, collectionIndex: 0, isFirst: isFirst)
                case .custom2:
                    weekDayRowFlexCustomLogCell(date: date, collectionIndex: 1, isFirst: isFirst)
                }
                if isFirst {
                    Divider()
                }
            }
        }
        .frame(minHeight: 120)
    }

    func rowEventCard(event: GoogleCalendarEvent) -> some View {
        let isPersonal = event.ownerAccountKind == .personal
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
    

    
    
    func step(_ offset: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) {
            selectedDate = newDate
            regenerateWeekDates(for: newDate)
            navigationManager.updateInterval(.week, date: newDate)
        }
    }
    
    // Calendar event functions removed - only tasks are displayed now
    
    func regenerateWeekDates(for referenceDate: Date) {
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
            weekDates = []
            return
        }
        
        var days: [Date] = []
        var date = weekInterval.start
        for _ in 0..<7 {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        weekDates = days
    }
    
    // Calendar event helper functions removed since we only show tasks now
    
    // MARK: - Week Event Functions
    func weekEventColumn(date: Date) -> some View {
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
    
}
