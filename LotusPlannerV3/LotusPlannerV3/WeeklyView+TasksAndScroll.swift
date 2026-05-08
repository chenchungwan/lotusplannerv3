import SwiftUI
import UniformTypeIdentifiers

/// Week-level task columns + drop handlers + scroll-to-today helpers + sleep log views. These sit at the trailing end of the W view's helpers; the sleep log is here rather than in WeeklyView+LogViews because it shares scroll/positioning concerns with the tasks columns in the row-based layout.
extension WeeklyView {

    // MARK: - Week Task Functions
    func weekTasksDateHeader(dayColumnWidth: CGFloat, timeColumnWidth: CGFloat) -> some View {
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
    
    func weekTaskColumnPersonal(date: Date) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            // Personal Tasks using day view component
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
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 4)
    }

    func weekTaskColumnProfessional(date: Date) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            // Professional Tasks using day view component
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
                let isPersonal = accountKind == "personal"
                let events = isPersonal ? calendarViewModel.personalEvents : calendarViewModel.professionalEvents
                guard let event = events.first(where: { $0.id == eventId }) else { return }

                Task {
                    await calendarViewModel.moveEventToDate(event, to: targetDate)
                }
            }
        }
        return true
    }

    func findTaskListId(for task: GoogleTask, in accountKind: GoogleAuthManager.AccountKind) -> String? {
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
