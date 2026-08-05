import SwiftUI

extension WeeklyView {
    private struct WeeklyVisiblePosition: Identifiable {
        let row: Int
        let col: Int
        var id: String { "\(row)_\(col)" }
    }

    private struct WeeklyResolvedPlacement: Identifiable {
        let row: Int
        let col: Int
        let rowSpan: Int
        let colSpan: Int
        let component: WeeklyCustomComponent

        var id: String { "\(row)_\(col)_\(component.rawValue)" }
    }

    var activeCustomWeeklyConfig: CustomWeeklyViewConfig? {
        _ = weeklyCustomConfigVersion
        return CustomWeeklyViewLibrary.load().activeConfig
    }

    @ViewBuilder
    var customWeeklyView: some View {
        if let config = activeCustomWeeklyConfig {
            customWeeklyGrid(config)
        } else {
            customWeeklyEmptyState
        }
    }

    private func customWeeklyGrid(_ config: CustomWeeklyViewConfig) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 6
            let padding: CGFloat = 8
            let rows = max(1, config.orientation.fixedRows ?? config.rows)
            let cols = max(1, config.orientation.fixedCols ?? config.cols)
            let headerHeight: CGFloat = 60
            let rowHeaderWidth: CGFloat = 96

            switch config.orientation {
            case .daysInColumns:
                let innerW = max(0, proxy.size.width - padding * 2)
                let innerH = max(0, proxy.size.height - padding * 2 - headerHeight)
                let cellW = max(0, (innerW - spacing * CGFloat(cols - 1)) / CGFloat(cols))
                let cellH = max(0, (innerH - spacing * CGFloat(rows - 1)) / CGFloat(rows))

                VStack(spacing: 0) {
                    customWeeklyDateColumnHeader(dayColumnWidth: cellW, spacing: spacing)
                        .frame(width: innerW, height: headerHeight)
                        .padding(.horizontal, padding)

                    customWeeklyPlacementGrid(config: config, rows: rows, cols: cols, cellW: cellW, cellH: cellH, spacing: spacing, padding: padding)
                        .frame(width: innerW + padding * 2, height: innerH + padding * 2)
                }

            case .daysInRows:
                let innerW = max(0, proxy.size.width - padding * 2 - rowHeaderWidth)
                let innerH = max(0, proxy.size.height - padding * 2)
                let cellW = max(0, (innerW - spacing * CGFloat(cols - 1)) / CGFloat(cols))
                let cellH = max(0, (innerH - spacing * CGFloat(rows - 1)) / CGFloat(rows))

                HStack(spacing: 0) {
                    customWeeklyDateRowHeader(rowHeight: cellH, spacing: spacing)
                        .frame(width: rowHeaderWidth, height: innerH)

                    customWeeklyPlacementGrid(config: config, rows: rows, cols: cols, cellW: cellW, cellH: cellH, spacing: spacing, padding: padding)
                        .frame(width: innerW + padding * 2, height: innerH + padding * 2)
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private func customWeeklyPlacementGrid(
        config: CustomWeeklyViewConfig,
        rows: Int,
        cols: Int,
        cellW: CGFloat,
        cellH: CGFloat,
        spacing: CGFloat,
        padding: CGFloat
    ) -> some View {
        let placements = resolvedPlacements(config: config, rows: rows, cols: cols)

        return ZStack(alignment: .topLeading) {
            ForEach(weeklyVisiblePositions(rows: rows, cols: cols)) { cell in
                let x = CGFloat(cell.col) * (cellW + spacing) + padding
                let y = CGFloat(cell.row) * (cellH + spacing) + padding

                customWeeklyCell(nil)
                    .frame(width: cellW, height: cellH)
                    .position(x: x + cellW / 2, y: y + cellH / 2)
            }

            ForEach(placements) { placement in
                let width = cellW * CGFloat(placement.colSpan) + spacing * CGFloat(max(0, placement.colSpan - 1))
                let height = cellH * CGFloat(placement.rowSpan) + spacing * CGFloat(max(0, placement.rowSpan - 1))
                let x = CGFloat(placement.col) * (cellW + spacing) + padding
                let y = CGFloat(placement.row) * (cellH + spacing) + padding

                customWeeklyCell(placement.component)
                    .frame(width: width, height: height)
                    .position(x: x + width / 2, y: y + height / 2)
            }
        }
    }

    private func customWeeklyDateColumnHeader(dayColumnWidth: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
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
                    .id("custom_week_day_header_\(index)")
            }
        }
        .background(Color(.systemBackground))
    }

    private func customWeeklyDateRowHeader(rowHeight: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                weekTaskDateHeaderView(date: date)
                    .frame(width: 96, height: rowHeight)
                    .background(Color(.systemGray6))
                    .overlay(
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(height: 0.5),
                        alignment: .bottom
                    )
                    .id("custom_week_day_row_header_\(index)")
            }
        }
        .background(Color(.systemBackground))
    }

    private func resolvedPlacements(config: CustomWeeklyViewConfig, rows: Int, cols: Int) -> [WeeklyResolvedPlacement] {
        var occupied = Set<WeeklyVisiblePosition.ID>()
        var resolved: [WeeklyResolvedPlacement] = []

        for dto in config.placements {
            guard let component = WeeklyCustomComponent(rawValue: dto.component) else { continue }
            let normalized = normalizedWeeklyPlacement(dto: dto, component: component, orientation: config.orientation, rows: rows, cols: cols)
            guard normalized.row >= 0,
                  normalized.col >= 0,
                  normalized.row + normalized.rowSpan <= rows,
                  normalized.col + normalized.colSpan <= cols else {
                continue
            }

            let claimed = (normalized.row..<(normalized.row + normalized.rowSpan)).flatMap { row in
                (normalized.col..<(normalized.col + normalized.colSpan)).map { col in "\(row)_\(col)" }
            }
            guard occupied.isDisjoint(with: claimed) else { continue }
            occupied.formUnion(claimed)
            resolved.append(normalized)
        }

        return resolved
    }

    private func normalizedWeeklyPlacement(
        dto: CustomWeeklyViewConfig.PlacementDTO,
        component: WeeklyCustomComponent,
        orientation: CustomWeeklyLayoutOrientation,
        rows: Int,
        cols: Int
    ) -> WeeklyResolvedPlacement {
        if component.isDayByDay {
            switch orientation {
            case .daysInColumns:
                let row = min(max(0, dto.row), max(0, rows - 1))
                return WeeklyResolvedPlacement(
                    row: row,
                    col: 0,
                    rowSpan: max(1, min(dto.rowSpan, rows - row)),
                    colSpan: min(7, cols),
                    component: component
                )
            case .daysInRows:
                let col = min(max(0, dto.col), max(0, cols - 1))
                return WeeklyResolvedPlacement(
                    row: 0,
                    col: col,
                    rowSpan: min(7, rows),
                    colSpan: max(1, min(dto.colSpan, cols - col)),
                    component: component
                )
            }
        }

        let row = min(max(0, dto.row), max(0, rows - 1))
        let col = min(max(0, dto.col), max(0, cols - 1))
        return WeeklyResolvedPlacement(
            row: row,
            col: col,
            rowSpan: max(1, min(dto.rowSpan, rows - row)),
            colSpan: max(1, min(dto.colSpan, cols - col)),
            component: component
        )
    }

    private func weeklyVisiblePositions(rows: Int, cols: Int) -> [WeeklyVisiblePosition] {
        (0..<rows).flatMap { row in
            (0..<cols).map { col in WeeklyVisiblePosition(row: row, col: col) }
        }
    }

    @ViewBuilder
    private func customWeeklyCell(_ component: WeeklyCustomComponent?) -> some View {
        if let component {
            customWeeklyComponentView(component)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        }
    }

    @ViewBuilder
    private func customWeeklyComponentView(_ component: WeeklyCustomComponent) -> some View {
        switch component {
        case .verticalWeek:
            weekColumnBasedViewWithStickyHeader
        case .horizontalWeek:
            weekRowBasedViewWithStickyColumn
        case .weeklyGoalsBar:
            WeeklyGoalsBarComponent(currentDate: navigationManager.currentDate)
                .padding(6)
        case .pastWeekSummary:
            if isPastWeek {
                pastWeekSummaryStrip
            } else {
                customWeeklyPlaceholder(
                    title: "Past Week Summary",
                    systemImage: "chart.bar",
                    message: "Appears after the displayed week has ended."
                )
            }
        case .eventsWeek:
            customWeekByDayStrip(title: "Events", systemImage: "calendar") { date in
                weekEventColumn(date: date)
            }
        case .eventsWeeklyList:
            customWeeklyEventsList()
        case .personalTasksWeek:
            customWeekByDayStrip(title: "\(appPrefs.personalAccountName) Tasks", systemImage: "person.circle") { date in
                weekTaskColumnPersonal(date: date)
            }
        case .personalTasksWeeklyList:
            customWeeklyTasksList(accountKind: .personal)
        case .professionalTasksWeek:
            customWeekByDayStrip(title: "\(appPrefs.professionalAccountName) Tasks", systemImage: "briefcase") { date in
                weekTaskColumnProfessional(date: date)
            }
        case .professionalTasksWeeklyList:
            customWeeklyTasksList(accountKind: .professional)
        case .weightLogWeek:
            customLogWeekStrip(title: "Weight", systemImage: "scalemass", logType: .weight)
        case .workoutLogWeek:
            customLogWeekStrip(title: "Workout", systemImage: "figure.run", logType: .workout)
        case .foodLogWeek:
            customLogWeekStrip(title: "Food", systemImage: "fork.knife", logType: .food)
        case .waterLogWeek:
            customLogWeekStrip(title: "Water", systemImage: "drop", logType: .water)
        case .sleepLogWeek:
            customLogWeekStrip(title: "Sleep", systemImage: "bed.double", logType: .sleep)
        case .customLogDailyWeek:
            customCustomLogDailyStrip(collectionIndex: 0)
        case .customLogDailyWeek2:
            customCustomLogDailyStrip(collectionIndex: 1)
        case .customLogWeek:
            CustomLogWeekComponent(currentDate: navigationManager.currentDate)
                .padding(6)
        case .customLogWeek2:
            CustomLogWeekComponent(currentDate: navigationManager.currentDate, collectionIndex: 1)
                .padding(6)
        case .weeklyGoals:
            ScrollView(.vertical, showsIndicators: true) {
                GoalsTimeframeComponent(timeframe: .week, date: navigationManager.currentDate)
                    .padding(6)
            }
        case .monthlyGoals:
            ScrollView(.vertical, showsIndicators: true) {
                GoalsTimeframeComponent(timeframe: .month, date: navigationManager.currentDate)
                    .padding(6)
            }
        case .yearlyGoals:
            ScrollView(.vertical, showsIndicators: true) {
                GoalsTimeframeComponent(timeframe: .year, date: navigationManager.currentDate)
                    .padding(6)
            }
        case .goalsPicker:
            ScrollView(.vertical, showsIndicators: true) {
                GoalsTimeframePickerComponent(date: navigationManager.currentDate)
                    .padding(6)
            }
        case .weightGraph:
            WeightGraphComponent(currentDate: navigationManager.currentDate)
                .padding(6)
        case .weightGraphWeek:
            WeightGraphComponent(currentDate: navigationManager.currentDate, fixedTimeframe: .week)
                .padding(6)
        case .weightGraphMonth:
            WeightGraphComponent(currentDate: navigationManager.currentDate, fixedTimeframe: .month)
                .padding(6)
        case .weightGraphYear:
            WeightGraphComponent(currentDate: navigationManager.currentDate, fixedTimeframe: .year)
                .padding(6)
        case .workoutStreakGraph:
            WorkoutStreakGraphComponent(currentDate: navigationManager.currentDate)
                .padding(6)
        case .workoutStreakGraphWeek:
            WorkoutStreakGraphComponent(currentDate: navigationManager.currentDate, fixedTimeframe: .week)
                .padding(6)
        case .workoutStreakGraphMonth:
            WorkoutStreakGraphComponent(currentDate: navigationManager.currentDate, fixedTimeframe: .month)
                .padding(6)
        case .workoutStreakGraphYear:
            WorkoutStreakGraphComponent(currentDate: navigationManager.currentDate, fixedTimeframe: .year)
                .padding(6)
        }
    }

    private func customWeekByDayStrip<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping (Date) -> Content
    ) -> some View {
        GeometryReader { proxy in
            let columnWidth = max(100, proxy.size.width / 7)
            VStack(alignment: .leading, spacing: 0) {
                customWeeklySectionHeader(title: title, systemImage: systemImage)

                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(weekDates, id: \.self) { date in
                            ScrollView(.vertical, showsIndicators: true) {
                                content(date)
                            }
                            .frame(width: columnWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(Color(.systemBackground))
                            .overlay(
                                Rectangle()
                                    .fill(Color(.systemGray4))
                                    .frame(width: 0.5),
                                alignment: .trailing
                            )
                        }
                    }
                }
            }
        }
    }

    private func customLogWeekStrip(title: String, systemImage: String, logType: BuiltInLogType) -> some View {
        customWeekByDayStrip(title: title, systemImage: systemImage) { date in
            weekLogColumn(for: logType, date: date)
                .padding(4)
        }
    }

    private func customCustomLogDailyStrip(collectionIndex: Int) -> some View {
        customWeekByDayStrip(
            title: AppPreferences.shared.customLogSectionName(for: collectionIndex),
            systemImage: "calendar.badge.checkmark"
        ) { date in
            customLogDailyColumn(date: date, collectionIndex: collectionIndex)
                .padding(6)
        }
    }

    private func customWeeklyTasksList(accountKind: GoogleAuthManager.AccountKind) -> some View {
        let isPersonal = accountKind == .personal
        let taskLists = isPersonal ? tasksViewModel.personalTaskLists : tasksViewModel.professionalTaskLists
        let tasks = filteredTasksForDisplayedWeek(accountKind: accountKind)
        let title = "\(appPrefs.accountName(for: accountKind)) Tasks"

        return VStack(alignment: .leading, spacing: 0) {
            customWeeklySectionHeader(title: title, systemImage: isPersonal ? "person.circle" : "briefcase")

            TasksComponent(
                taskLists: taskLists,
                tasksDict: tasks,
                accentColor: isPersonal ? appPrefs.personalColor : appPrefs.professionalColor,
                accountType: accountKind,
                onTaskToggle: { task, listId in
                    Task {
                        await tasksViewModel.toggleTaskCompletion(task, in: listId, for: accountKind)
                    }
                },
                onTaskDetails: { task, listId in
                    taskSheetSelection = WeeklyTaskSelection(task: task, listId: listId, accountKind: accountKind)
                },
                onListRename: { listId, newName in
                    Task {
                        await tasksViewModel.renameTaskList(listId: listId, newTitle: newName, for: accountKind)
                    }
                },
                onOrderChanged: { newOrder in
                    Task {
                        await tasksViewModel.updateTaskListOrder(newOrder, for: accountKind)
                    }
                },
                hideDueDateTag: false,
                showEmptyState: true,
                combineLists: true,
                isSingleDayView: false,
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

    private func filteredTasksForDisplayedWeek(accountKind: GoogleAuthManager.AccountKind) -> [String: [GoogleTask]] {
        guard let range = displayedWeekRange else { return [:] }
        let tasksDict = accountKind == .personal ? tasksViewModel.personalTasks : tasksViewModel.professionalTasks
        let calendar = Calendar.mondayFirst

        return tasksDict.mapValues { tasks in
            tasks.filter { task in
                if appPrefs.hideCompletedTasks && task.isCompleted {
                    return false
                }

                let relevantDate: Date?
                if task.isCompleted {
                    relevantDate = task.completionDate
                } else {
                    relevantDate = task.dueDate
                }

                guard let relevantDate else { return false }
                let day = calendar.startOfDay(for: relevantDate)
                return day >= range.start && day < range.end
            }
        }
    }

    private func customWeeklyEventsList() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            customWeeklySectionHeader(title: "Events", systemImage: "calendar")

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    let events = eventsForDisplayedWeek()

                    if events.isEmpty {
                        Text("No events")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(events, id: \.id) { event in
                            customWeeklyEventListRow(event)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func eventsForDisplayedWeek() -> [GoogleCalendarEvent] {
        weekDates
            .flatMap { getEventsForDate($0) }
            .reduce(into: [String: GoogleCalendarEvent]()) { partial, event in
                partial[event.id] = event
            }
            .values
            .sorted { lhs, rhs in
                let lhsStart = lhs.startTime ?? .distantPast
                let rhsStart = rhs.startTime ?? .distantPast
                let lhsDay = Calendar.mondayFirst.startOfDay(for: lhsStart)
                let rhsDay = Calendar.mondayFirst.startOfDay(for: rhsStart)
                if lhsDay != rhsDay {
                    return lhsDay < rhsDay
                }
                if lhs.isAllDay != rhs.isAllDay {
                    return lhs.isAllDay
                }
                return lhsStart < rhsStart
            }
    }

    private func customWeeklyEventListRow(_ event: GoogleCalendarEvent) -> some View {
        let isPersonal = event.ownerAccountKind == .personal
        let eventColor = isPersonal ? appPrefs.personalColor : appPrefs.professionalColor

        return Button {
            selectedCalendarEvent = event
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(customWeeklyEventDayText(event))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(eventColor)
                    Text(customWeeklyEventTimeText(event))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.summary)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .background(eventColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func customWeeklyEventDayText(_ event: GoogleCalendarEvent) -> String {
        guard let start = event.startTime else { return "" }
        return DateFormatter.standardDayOfWeek.string(from: start).uppercased()
    }

    private func customWeeklyEventTimeText(_ event: GoogleCalendarEvent) -> String {
        if event.isAllDay {
            return "All Day"
        }
        guard let start = event.startTime else { return "" }
        return DateFormatter.shortTime.string(from: start)
    }

    private func customLogDailyColumn(date: Date, collectionIndex: Int) -> some View {
        let items = customLogManager.items(in: collectionIndex).filter { $0.isEnabled }

        return VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty {
                Text("No custom log items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        customLogManager.toggleEntry(for: item.id, date: date)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: customLogManager.getCompletionStatus(for: item.id, date: date) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(customLogManager.getCompletionStatus(for: item.id, date: date) ? .accentColor : .secondary)
                            Text(item.title)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func customWeeklySectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }

    private func customWeeklyPlaceholder(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    private var customWeeklyEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Your custom weekly view is empty.")
                .font(.title3)
                .foregroundColor(.primary)

            Text("Open Settings, choose Weekly View Preferences, then add a Custom version.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
