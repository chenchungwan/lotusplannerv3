import SwiftUI
import UniformTypeIdentifiers

/// Week-level task columns + drop handlers + scroll-to-today helpers + sleep log views. These sit at the trailing end of the W view's helpers; the sleep log is here rather than in WeeklyView+LogViews because it shares scroll/positioning concerns with the tasks columns in the row-based layout.
extension WeeklyView {

    // MARK: - Week Task Functions
    func weekTasksDateHeader(dayColumnWidth: CGFloat, summaryColumnWidth: CGFloat = 0, timeColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            if appPrefs.showWeeklySummarySection {
                weeklySummaryHeader()
                    .frame(width: summaryColumnWidth, height: 60)
                    .background(Color(.systemGray6))
                    .overlay(
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
            }

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
    
    func weekTaskDateHeaderView(date: Date) -> some View {
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())

        return VStack(spacing: 4) {
            // Standardized day of week format: MON, TUE, etc.
            Text(DateFormatter.standardDayOfWeek.string(from: date).uppercased())
                .font(.system(size: 16, weight: .semibold))
                .fontWeight(.semibold)
                .foregroundColor(isToday ? DateDisplayStyle.todayColor : DateDisplayStyle.secondaryColor)

            // Standardized date format: m/d/yy
            Text(DateFormatter.standardDate.string(from: date))
                .font(.system(size: 20, weight: .bold))
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
            if hideNavBar {
                // Inside BookView: use notification so currentView stays .bookView
                NotificationCenter.default.post(name: .bookViewNavigateToDay, object: date)
            } else {
                navigationManager.updateInterval(.day, date: date)
            }
        }
    }

    var weeklySummaryConfig: WeeklySummaryConfig {
        _ = weeklySummaryConfigVersion
        return WeeklySummaryConfig.load()
    }

    func weeklySummaryRowHeight(minimum: CGFloat = 220) -> CGFloat {
        let config = weeklySummaryConfig
        let components = config.horizontalPlacements.compactMap { CustomComponent(rawValue: $0.component) }
        let tallest = components.map(weeklySummaryPreferredHeight(for:)).max() ?? minimum
        return max(minimum, tallest)
    }

    func weeklySummaryPreferredWidth(minimum: CGFloat) -> CGFloat {
        let config = weeklySummaryConfig
        let placements = appPrefs.useRowBasedWeeklyView ? config.horizontalPlacements : config.verticalPlacements
        let widest = placements
            .compactMap { CustomComponent(rawValue: $0.component) }
            .map(weeklySummaryPreferredWidth(for:))
            .max() ?? minimum
        return max(minimum, widest)
    }

    func weeklySummaryPreferredWidth(for component: CustomComponent) -> CGFloat {
        switch component {
        case .logCustomWeek, .logCustomWeek2:
            return 340
        case .goalsWeek, .goalsMonth, .goalsYear, .goalsPicker:
            return 360
        case .weeklyGoalsBar:
            return 420
        case .weightGraph,
             .weightGraphWeek,
             .weightGraphMonth,
             .weightGraphYear,
             .workoutStreakGraph,
             .workoutStreakGraphWeek,
             .workoutStreakGraphMonth,
             .workoutStreakGraphYear:
            return 380
        default:
            return 280
        }
    }

    func weeklySummaryPreferredHeight(for component: CustomComponent) -> CGFloat {
        switch component {
        case .logCustomWeek:
            return weeklyRoutinePreferredHeight(collectionIndex: 0)
        case .logCustomWeek2:
            return weeklyRoutinePreferredHeight(collectionIndex: 1)
        case .goalsWeek, .goalsMonth, .goalsYear, .goalsPicker:
            return 260
        case .weightGraph,
             .weightGraphWeek,
             .weightGraphMonth,
             .weightGraphYear,
             .workoutStreakGraph,
             .workoutStreakGraphWeek,
             .workoutStreakGraphMonth,
             .workoutStreakGraphYear:
            return 260
        case .weeklyGoalsBar:
            return 72
        default:
            return 220
        }
    }

    func weeklyRoutinePreferredHeight(collectionIndex: Int) -> CGFloat {
        let itemCount = customLogManager.items(in: collectionIndex).filter { $0.isEnabled }.count
        let headerHeight: CGFloat = 18
        let dividerHeight: CGFloat = 1
        let rowHeight: CGFloat = 24
        let rowSpacing: CGFloat = 6
        let verticalPadding: CGFloat = 20
        let contentSpacing = rowSpacing * CGFloat(max(0, itemCount + 1))
        let rowsHeight = rowHeight * CGFloat(max(1, itemCount))
        return headerHeight + dividerHeight + rowsHeight + contentSpacing + verticalPadding
    }

    func weeklySummaryHeader() -> some View {
        VStack(spacing: 4) {
            Image(systemName: "rectangle.leadinghalf.inset.filled")
                .font(.system(size: 16, weight: .semibold))
            Text("SUMMARY")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    func weeklySummaryColumn(width: CGFloat) -> some View {
        let config = weeklySummaryConfig
        let rows = max(1, config.verticalRows)
        let placements = config.verticalPlacements

        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                let component = placements.first(where: { $0.row == row }).flatMap { CustomComponent(rawValue: $0.component) }
                weeklySummaryCell(
                    component: component
                )
                .frame(width: width, height: component.map(weeklySummaryPreferredHeight(for:)) ?? 220, alignment: .topLeading)

                if row < rows - 1 {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 1)
                }
            }
        }
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 0.5),
            alignment: .trailing
        )
    }

    func weeklySummaryRowContent(cellWidth: CGFloat, cellHeight: CGFloat? = nil) -> some View {
        let config = weeklySummaryConfig
        let columns = max(1, config.horizontalCols)
        let placements = config.horizontalPlacements
        let preferredWidth = weeklySummaryPreferredWidth(minimum: cellWidth)
        let preferredHeight = cellHeight ?? weeklySummaryRowHeight()

        return HStack(alignment: .top, spacing: 0) {
            ForEach(0..<columns, id: \.self) { col in
                weeklySummaryCell(
                    component: placements.first(where: { $0.col == col }).flatMap { CustomComponent(rawValue: $0.component) }
                )
                .frame(width: preferredWidth, height: preferredHeight, alignment: .topLeading)

                if col < columns - 1 {
                    Divider()
                }
            }
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    func weeklySummaryCell(component: CustomComponent?) -> some View {
        if let component {
            weeklySummaryComponentView(component)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(6)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "square.dashed")
                    .font(.title3)
                Text("Summary")
                    .font(.caption)
            }
            .foregroundColor(.secondary.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        }
    }

    @ViewBuilder
    func weeklySummaryComponentView(_ component: CustomComponent) -> some View {
        switch component {
        case .logCustomWeek:
            CustomLogWeekComponent(currentDate: selectedDate)
        case .logCustomWeek2:
            CustomLogWeekComponent(currentDate: selectedDate, collectionIndex: 1)
        case .goalsWeek:
            GoalsTimeframeComponent(timeframe: .week, date: selectedDate)
        case .goalsMonth:
            GoalsTimeframeComponent(timeframe: .month, date: selectedDate)
        case .goalsYear:
            GoalsTimeframeComponent(timeframe: .year, date: selectedDate)
        case .goalsPicker:
            GoalsTimeframePickerComponent(date: selectedDate)
        case .weeklyGoalsBar:
            WeeklyGoalsBarComponent(currentDate: selectedDate)
        case .weightGraph:
            WeightGraphComponent(currentDate: selectedDate)
        case .weightGraphWeek:
            WeightGraphComponent(currentDate: selectedDate, fixedTimeframe: .week)
        case .weightGraphMonth:
            WeightGraphComponent(currentDate: selectedDate, fixedTimeframe: .month)
        case .weightGraphYear:
            WeightGraphComponent(currentDate: selectedDate, fixedTimeframe: .year)
        case .workoutStreakGraph:
            WorkoutStreakGraphComponent(currentDate: selectedDate)
        case .workoutStreakGraphWeek:
            WorkoutStreakGraphComponent(currentDate: selectedDate, fixedTimeframe: .week)
        case .workoutStreakGraphMonth:
            WorkoutStreakGraphComponent(currentDate: selectedDate, fixedTimeframe: .month)
        case .workoutStreakGraphYear:
            WorkoutStreakGraphComponent(currentDate: selectedDate, fixedTimeframe: .year)
        default:
            VStack(spacing: 6) {
                Image(systemName: component.systemImage)
                    .foregroundColor(.accentColor)
                Text(component.displayName(account1: appPrefs.account1Name, account2: appPrefs.account2Name))
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    func weekTaskColumnAccount1(date: Date) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            // Account 1 Tasks using day view component
            let account1TasksForDate = getFilteredTasksForSpecificDate(date: date, accountKind: .account1)
            if !account1TasksForDate.allSatisfy({ $0.value.isEmpty }) {
                TasksComponent(
                    taskLists: tasksViewModel.account1TaskLists,
                    tasksDict: account1TasksForDate,
                    accentColor: appPrefs.account1Color,
                    accountType: .account1,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .account1)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: .account1)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .account1)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .account1)
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
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 4)
    }

    func weekTaskColumnAccount2(date: Date) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            // Account 2 Tasks using day view component
            let account2TasksForDate = getFilteredTasksForSpecificDate(date: date, accountKind: .account2)
            if !account2TasksForDate.allSatisfy({ $0.value.isEmpty }) {
                TasksComponent(
                    taskLists: tasksViewModel.account2TaskLists,
                    tasksDict: account2TasksForDate,
                    accentColor: appPrefs.account2Color,
                    accountType: .account2,
                    onTaskToggle: { task, listId in
                        Task {
                            await tasksViewModel.toggleTaskCompletion(task, in: listId, for: .account2)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: .account2)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: .account2)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await tasksViewModel.updateTaskListOrder(newOrder, for: .account2)
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
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 4)
    }

    // Helper function to get filtered tasks for a specific date (for weekly view)
    func getFilteredTasksForSpecificDate(date: Date, accountKind: GoogleAuthManager.AccountKind) -> [String: [GoogleTask]] {
        tasksViewModel.tasksForDay(date, kind: accountKind)
    }

    func handleTaskDrop(_ info: DraggableTaskInfo, to targetDate: Date) {
        // Drop on a day cell — schedule as all-day on the target date.
        // TaskScheduler centralizes formatting (local `yyyy-MM-dd`, NOT
        // the previous UTC format which rolled the date forward by one
        // day in negative-offset timezones) and time-window cleanup.
        guard let resolved = TaskScheduler.resolveTask(info) else { return }
        TaskScheduler.scheduleAllDay(
            task: resolved.task,
            listId: info.listId,
            kind: resolved.kind,
            on: targetDate
        )
    }


    func handleEventDrop(providers: [NSItemProvider], targetDate: Date) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            let json: String?
            if let str = item as? String { json = str }
            else if let data = item as? Data { json = String(data: data, encoding: .utf8) }
            else { return }

            guard let json,
                  let jsonData = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
                  dict["type"] == "event",
                  let eventId = dict["id"],
                  let accountKind = dict["accountKind"] else { return }

            DispatchQueue.main.async {
                let isAccount1 = accountKind == "personal"
                let events = isAccount1 ? calendarViewModel.account1Events : calendarViewModel.account2Events
                guard let event = events.first(where: { $0.id == eventId }) else { return }

                Task {
                    await calendarViewModel.moveEventToDate(event, to: targetDate)
                }
            }
        }
        return true
    }

    func findTaskListId(for task: GoogleTask, in accountKind: GoogleAuthManager.AccountKind) -> String? {
        let tasksDict = accountKind == .account1 ? tasksViewModel.account1Tasks : tasksViewModel.account2Tasks
        
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
    
    var isCurrentWeek: Bool {
        let calendar = Calendar.mondayFirst
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return false }
        let weekStart = weekInterval.start
        let weekEnd = weekInterval.end
        let result = selectedDate >= weekStart && selectedDate < weekEnd
        return result
    }
    
    func scrollToCurrentDay() {
        // Trigger scroll by toggling the state
        scrollToCurrentDayTrigger.toggle()
        scrollToCurrentDayHorizontalTrigger.toggle()
        scrollToCurrentDayRowTrigger.toggle()
    }
    
    func scrollToCurrentDayWithProxy(_ proxy: ScrollViewProxy) {
        // If it's the current week, scroll to today's position
        // If it's not the current week, scroll to Monday (index 0)
        let calendar = Calendar.mondayFirst
        let dayIndex: Int
        
        if isCurrentWeek {
            // Find which day of the week today is (0 = Monday, 6 = Sunday)
            let today = Date()
            let todayWeekday = calendar.component(.weekday, from: today)
            let mondayWeekday = 2 // Monday is weekday 2 in Calendar.current
            dayIndex = (todayWeekday - mondayWeekday + 7) % 7
        } else {
            // Default to Monday (index 0) for non-current weeks
            dayIndex = 0
        }
        
        // Scroll to the current day column
        withAnimation(.easeInOut(duration: 0.5)) {
            proxy.scrollTo("day_\(dayIndex)", anchor: .center)
        }
    }
    
    func scrollToCurrentDayHorizontalWithProxy(_ proxy: ScrollViewProxy) {
        // If it's the current week, scroll to today's position
        // If it's not the current week, scroll to Monday (index 0)
        let calendar = Calendar.mondayFirst
        let dayIndex: Int
        
        if isCurrentWeek {
            // Find which day of the week today is by matching against weekDates
            // weekDates[0] = Monday, weekDates[1] = Tuesday, ..., weekDates[6] = Sunday
            let today = Date()
            if let index = weekDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: today) }) {
                dayIndex = index
            } else {
                // Fallback to Monday if today not found
                dayIndex = 0
            }
        } else {
            // Default to Monday (index 0) for non-current weeks
            dayIndex = 0
        }

        // Scroll to the current day column horizontally
        proxy.scrollTo("day_\(dayIndex)", anchor: .leading)
    }
    
    func scrollToCurrentDayRowWithProxy(_ proxy: ScrollViewProxy) {
        // If it's the current week, scroll to today's position
        // If it's not the current week, scroll to Monday (index 0)
        let calendar = Calendar.mondayFirst
        let dayIndex: Int
        
        if isCurrentWeek {
            // Find which day of the week today is by matching against weekDates
            // weekDates[0] = Monday, weekDates[1] = Tuesday, ..., weekDates[6] = Sunday
            let today = Date()
            if let index = weekDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: today) }) {
                dayIndex = index
            } else {
                // Fallback to Monday if today not found
                dayIndex = 0
            }
        } else {
            // Default to Monday (index 0) for non-current weeks
            dayIndex = 0
        }

        // Scroll to the current day row vertically
        proxy.scrollTo("day_row_\(dayIndex)", anchor: .top)
    }

    // MARK: - Sleep Log Helpers

    func getSleepLogsForDate(_ date: Date) -> [SleepLogEntry] {
        logsViewModel.sleepLogs(on: date)
    }

    func sleepLogCard(entry: SleepLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Bed time, wake time, and duration
            HStack(spacing: 4) {
                if let bedTime = entry.bedTime, let wakeTime = entry.wakeUpTime {
                    Text(formatLogTime(bedTime))
                        .font(.body)
                        .fontWeight(.medium)
                    Text("→")
                        .font(.body)
                        .fontWeight(.medium)
                    Text(formatLogTime(wakeTime))
                        .font(.body)
                        .fontWeight(.medium)
                    if let duration = entry.sleepDurationFormatted {
                        Text("(\(duration))")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                } else if let bedTime = entry.bedTime {
                    Text("Bed: \(formatLogTime(bedTime))")
                        .font(.body)
                        .fontWeight(.medium)
                } else if let wakeTime = entry.wakeUpTime {
                    Text("Wake: \(formatLogTime(wakeTime))")
                        .font(.body)
                        .fontWeight(.medium)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    func weekSleepLogColumn(date: Date) -> some View {
        let sleepLogsForDate = getSleepLogsForDate(date)

        return VStack(alignment: .leading, spacing: 4) {
            ForEach(sleepLogsForDate, id: \.id) { entry in
                weekSleepLogCard(entry: entry)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func weekSleepLogCard(entry: SleepLogEntry) -> some View {
        HStack(alignment: .top, spacing: 2) {
            // Bed time, wake time, and duration all on one line
            if let bedTime = entry.bedTime, let wakeTime = entry.wakeUpTime {
                Text(formatLogTime(bedTime))
                    .font(.body)
                    .foregroundColor(.primary)
                Text("→")
                    .font(.body)
                    .foregroundColor(.primary)
                Text(formatLogTime(wakeTime))
                    .font(.body)
                    .foregroundColor(.primary)
                if let duration = entry.sleepDurationFormatted {
                    Text("(\(duration))")
                        .font(.body)
                        .foregroundColor(.primary)
                }
            } else if let bedTime = entry.bedTime {
                Text("Bed: \(formatLogTime(bedTime))")
                    .font(.body)
                    .foregroundColor(.primary)
            } else if let wakeTime = entry.wakeUpTime {
                Text("Wake: \(formatLogTime(wakeTime))")
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}
