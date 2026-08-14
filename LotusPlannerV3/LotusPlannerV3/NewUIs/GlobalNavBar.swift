import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct GlobalNavBar: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksVM = TasksViewModel.shared
    @ObservedObject private var calendarVM = CalendarViewModel.shared
    @ObservedObject private var auth = GoogleAuthManager.shared

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var isSyncing = false

    private var isCompact: Bool { horizontalSizeClass == .compact }

    private var buttonSize: CGFloat {
        #if targetEnvironment(macCatalyst)
        34
        #else
        isCompact ? 40 : 46
        #endif
    }

    private var iconFont: Font {
        #if targetEnvironment(macCatalyst)
        .title3
        #else
        isCompact ? .title3 : .title2
        #endif
    }

    private var titleFont: Font {
        #if targetEnvironment(macCatalyst)
        .title3
        #else
        isCompact ? .title3 : .title
        #endif
    }

    private var barHeight: CGFloat {
        #if targetEnvironment(macCatalyst)
        74
        #else
        96
        #endif
    }

    private var isCalendarLikeView: Bool {
        navigationManager.currentView == .calendar || navigationManager.currentView == .bookView
    }

    private var usesCalendarIntervalSymbols: Bool {
        isCalendarLikeView ||
        navigationManager.currentView == .yearlyCalendar ||
        navigationManager.currentView == .timebox
    }

    private var canNavigateDate: Bool {
        navigationManager.currentView != .lists &&
        !(navigationManager.currentView == .goals && navigationManager.currentInterval == .day)
    }

    private var showsIntervals: Bool {
        navigationManager.currentView != .lists && navigationManager.currentView != .journalDayViews
    }

    private var showsHideCompleted: Bool {
        navigationManager.currentView == .tasks ||
        navigationManager.currentView == .lists ||
        isCalendarLikeView ||
        navigationManager.currentView == .yearlyCalendar ||
        navigationManager.currentView == .timebox ||
        navigationManager.currentView == .journalDayViews
    }

    private var hideCompletedInactive: Bool {
        navigationManager.currentView == .journalDayViews ||
        ((isCalendarLikeView || navigationManager.currentView == .yearlyCalendar) &&
         (navigationManager.currentInterval == .month || navigationManager.currentInterval == .year))
    }

    private var showsTaskFilter: Bool {
        !isCalendarLikeView &&
        navigationManager.currentView != .yearlyCalendar &&
        navigationManager.currentView != .lists &&
        navigationManager.currentView != .journalDayViews &&
        navigationManager.currentView != .timebox
    }

    private var showsCalendarBulkEdit: Bool {
        isCalendarLikeView || navigationManager.currentView == .yearlyCalendar || navigationManager.currentView == .journalDayViews
    }

    private var showsPhotoExport: Bool {
        navigationManager.currentView == .calendar &&
        (navigationManager.currentInterval == .day || navigationManager.currentInterval == .week)
    }

    private var dateLabel: String {
        if navigationManager.currentView == .lists { return "Task Lists" }

        if navigationManager.currentView == .goals {
            switch navigationManager.currentInterval {
            case .day:
                return "All Goals"
            case .week:
                return weekLabel(prefix: "W")
            case .month:
                return monthLabel()
            case .year:
                return yearLabel()
            }
        }

        if navigationManager.showTasksView && navigationManager.showingAllTasks {
            return "All Tasks"
        }

        if navigationManager.currentView == .yearlyCalendar || navigationManager.currentInterval == .year {
            return yearLabel()
        }

        switch navigationManager.currentInterval {
        case .day:
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = isCompact ? "EEE" : "EEEE"
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = isCompact ? "M/d/yy" : "MMM d, yyyy"
            return "\(dayFormatter.string(from: navigationManager.currentDate)) \(dateFormatter.string(from: navigationManager.currentDate))"
        case .week:
            return weekLabel(prefix: "Week")
        case .month:
            return monthLabel()
        case .year:
            return yearLabel()
        }
    }

    private var titleColor: Color {
        guard canNavigateDate else { return .primary }
        return isCurrentPeriod ? DateDisplayStyle.currentPeriodColor : .primary
    }

    /// Compact width (iPhone portrait / split view) or compact height
    /// (iPhone landscape) should always use the scrollable two-line bar.
    private var prefersTwoLineBar: Bool {
        isCompact || verticalSizeClass == .compact || isPadWidthConstrainedNavigation
    }

    private var isPadWidthConstrainedNavigation: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad &&
            (isCalendarLikeView || navigationManager.currentView == .timebox || navigationManager.currentView == .tasks)
        #else
        return false
        #endif
    }

    /// Ideal width of the one-line bar (nav + gap + actions). `0` means not measured yet.
    @State private var oneLineIdealWidth: CGFloat = 0
    @State private var barContainerWidth: CGFloat = 0

    private var usesTwoLineBar: Bool {
        if prefersTwoLineBar { return true }
        guard oneLineIdealWidth > 0, barContainerWidth > 0 else { return false }
        let effectiveContainerWidth = min(barContainerWidth, ScreenMetrics.width)
        return oneLineIdealWidth > effectiveContainerWidth
    }

    var body: some View {
        Group {
            if usesTwoLineBar {
                twoLineBar
            } else {
                oneLineBar
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: NavBarContainerWidthKey.self, value: geo.size.width)
            }
        }
        .background(alignment: .leading) {
            oneLineWidthProbe
        }
        .onPreferenceChange(NavBarContainerWidthKey.self) { barContainerWidth = $0 }
        .onPreferenceChange(NavBarOneLineIdealWidthKey.self) { oneLineIdealWidth = $0 }
        .background(Color(.systemBackground))
        .buttonStyle(.borderless)
    }

    /// Full-width one-line bar: hamburger/date/intervals leading, actions trailing.
    private var oneLineBar: some View {
        HStack(spacing: 12) {
            navigationControls
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 12)
            actionControls
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: barHeight / 2)
    }

    /// Invisible ideal-width probe so we can fall back to two-line when content
    /// would clip — without breaking the real one-line bar's leading/trailing layout.
    private var oneLineWidthProbe: some View {
        HStack(spacing: 12) {
            navigationControls
            Color.clear.frame(width: 12)
            actionControls
        }
        .padding(.horizontal, 12)
        .fixedSize(horizontal: true, vertical: false)
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: NavBarOneLineIdealWidthKey.self, value: geo.size.width)
            }
        )
    }

    private var navigationControls: some View {
        HStack(spacing: isCompact ? 4 : 8) {
            mainMenu

            HStack(spacing: isCompact ? 3 : 4) {
                if canNavigateDate {
                    iconButton("chevron.left") { step(-1) }
                        .keyboardShortcut("[", modifiers: [])
                }
                titleButton
                if canNavigateDate {
                    iconButton("chevron.right") { step(1) }
                        .keyboardShortcut("]", modifiers: [])
                }
            }
            // Keep date swipe on the title cluster only so horizontal
            // ScrollViews in the two-line bar can still receive drags.
            .simultaneousGesture(timeSwipeGesture)

            intervalControls
        }
    }

    private var twoLineBar: some View {
        VStack(spacing: 0) {
            // Top line: navigation — menu, date, interval selectors (left-aligned)
            ScrollView(.horizontal, showsIndicators: false) {
                navigationControls
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, isCompact ? 8 : 12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: barHeight / 2)

            // Bottom line: editing/actions (right-aligned)
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: isCompact ? 4 : 8) {
                        Spacer(minLength: 0)
                        actionControls
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, isCompact ? 8 : 12)
                    .frame(minWidth: geometry.size.width)
                }
            }
            .frame(height: barHeight / 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
    }

    private var titleButton: some View {
        Button {
            guard canNavigateDate else { return }
            navigationManager.datePickerSelection = navigationManager.currentDate
            navigationManager.present(.datePicker)
        } label: {
            Text(dateLabel)
                .font(titleFont.weight(.semibold))
                .foregroundColor(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: isCompact ? 180 : 300, alignment: .leading)
        }
        .disabled(!canNavigateDate)
    }

    private var mainMenu: some View {
        Menu {
            Button { navigationManager.switchToCalendar() } label: {
                Label("Calendar", systemImage: "calendar")
            }
            Button { navigationManager.switchToTasks() } label: {
                Label("Tasks", systemImage: "checklist")
            }
            Button { navigationManager.switchToLists() } label: {
                Label("Lists", systemImage: "list.bullet")
            }
            Button { navigationManager.switchToJournalDayViews() } label: {
                Label("Journals", systemImage: "book")
            }
            if !appPrefs.hideBookView {
                Button { navigationManager.switchToBookView() } label: {
                    Label("Book View (Beta)", systemImage: "book.pages")
                }
            }
            if !appPrefs.hideGoals {
                Button { navigationManager.switchToGoals() } label: {
                    Label("Goals", systemImage: "target")
                }
            }

            Divider()

            Button { navigationManager.present(.settings) } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button { navigationManager.present(.integrations) } label: {
                Label("Integrations", systemImage: "puzzlepiece.extension")
            }
            Button { navigationManager.present(.about) } label: {
                Label("About", systemImage: "info.circle")
            }
            Button { navigationManager.present(.diagnostics) } label: {
                Label("Diagnostics", systemImage: "stethoscope")
            }
            Button { navigationManager.present(.reportIssues) } label: {
                Label("Report Issue / Request Features", systemImage: "exclamationmark.bubble")
            }
            if let url = URL(string: "https://apps.apple.com/us/app/lotus-planner/id6749281062?action=write-review") {
                Link(destination: url) {
                    Label("Rate the App", systemImage: "star")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(iconFont)
                .frame(width: buttonSize, height: buttonSize)
                .foregroundColor(.secondary)
        }
        .help("Menu")
    }

    @ViewBuilder
    private var intervalControls: some View {
        if showsIntervals {
            HStack(spacing: isCompact ? 2 : 4) {
                if navigationManager.currentView != .goals {
                    intervalButton(.day, symbol: "d.circle")
                }
                if navigationManager.currentView != .tasks {
                    intervalButton(.week, symbol: usesCalendarIntervalSymbols || navigationManager.currentView == .goals ? "w.circle" : "s.circle")
                }
                if navigationManager.currentView != .goals {
                    timeboxOrWeekButton
                }
                intervalButton(.month, symbol: "m.circle")
                intervalButton(.year, symbol: "y.circle")
            }
        }
    }

    @ViewBuilder
    private var actionControls: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            if showsTaskFilter {
                taskFilterControl
            }

            syncButton

            if showsHideCompleted {
                iconButton(appPrefs.hideCompletedTasks ? "eye.slash" : "eye", color: hideCompletedInactive ? .secondary.opacity(0.4) : .accentColor) {
                    appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks)
                }
                .disabled(hideCompletedInactive)
                .help("Hide completed tasks")
            }

            if showsPhotoExport {
                iconButton("square.and.arrow.down", color: .accentColor) {
                    saveCurrentPageToPhotos()
                }
                .help("Save page to Photos")
            }

            bulkEditControl

            iconButton("sparkles", color: .accentColor) {
                navigationManager.present(.aiTaskEntry)
            }
            .disabled(!(auth.isLinked(kind: .account1) || auth.isLinked(kind: .account2)))
            .help("AI Task Entry")

            addMenu
        }
    }

    private var timeboxOrWeekButton: some View {
        Button {
            if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                NotificationCenter.default.post(name: .filterTasksToCurrentWeek, object: nil)
            } else if navigationManager.currentView == .bookView {
                navigationManager.updateInterval(.week, date: Date())
                NotificationCenter.default.post(name: .bookViewNavigateToTimebox, object: Date())
            } else if navigationManager.currentView == .timebox {
                return
            } else if usesCalendarIntervalSymbols {
                navigationManager.switchToTimebox()
            } else {
                handleTimeIntervalChange(.week)
            }
        } label: {
            Image(systemName: usesCalendarIntervalSymbols ? "t.circle" : "w.circle")
                .font(iconFont)
                .frame(width: buttonSize, height: buttonSize)
                .foregroundColor(timeboxOrWeekButtonColor)
        }
        .help("Timebox")
    }

    private var timeboxOrWeekButtonColor: Color {
        if navigationManager.currentView == .tasks {
            return intervalColor(.week)
        }
        return navigationManager.currentView == .timebox || navigationManager.isShowingTimebox ? .accentColor : .secondary
    }

    private var taskFilterControl: some View {
        Group {
            if navigationManager.currentView == .goals {
                iconButton("ellipsis.circle", color: navigationManager.currentInterval == .day ? .accentColor : .secondary) {
                    navigationManager.updateInterval(.day, date: Date())
                }
            } else {
                Menu {
                    Button("All") {
                        NotificationCenter.default.post(name: .showAllTasksRequested, object: nil)
                    }
                    Divider()
                    taskSubfilterButton("Has Due Date", .hasDueDate)
                    taskSubfilterButton("No Due Date", .noDueDate)
                    taskSubfilterButton("Overdue", .pastDue)
                    Button("Complete") {
                        NotificationCenter.default.post(name: .showAllTasksRequested, object: nil)
                        NotificationCenter.default.post(name: .setAllTasksSubfilter, object: AllTaskSubfilter.completed)
                        appPrefs.updateHideCompletedTasks(false)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(iconFont)
                        .frame(width: buttonSize, height: buttonSize)
                        .foregroundColor(navigationManager.showingAllTasks ? .accentColor : .secondary)
                }
                .help("Task filters")
            }
        }
    }

    private var syncButton: some View {
        Button {
            Task { await reloadAllData() }
        } label: {
            if isSyncing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: buttonSize, height: buttonSize)
            } else {
                Image(systemName: "arrow.trianglehead.clockwise.icloud")
                    .font(iconFont)
                    .frame(width: buttonSize, height: buttonSize)
            }
        }
        .disabled(isSyncing)
        .help("Sync")
    }

    private func saveCurrentPageToPhotos() {
        let formatter = DateFormatter()
        if navigationManager.currentInterval == .week,
           let weekInterval = Calendar.mondayFirst.dateInterval(
               of: .weekOfYear,
               for: navigationManager.currentDate
           ) {
            formatter.dateFormat = "M/d"
            let start = formatter.string(from: weekInterval.start)
            let weekEnd = Calendar.mondayFirst.date(
                byAdding: .day,
                value: 6,
                to: weekInterval.start
            ) ?? weekInterval.start
            let end = formatter.string(from: weekEnd)
            PrintDayHelper.saveExpandedWindowToPhotos(jobName: "Week \(start) – \(end)")
        } else {
            formatter.dateStyle = .medium
            let date = formatter.string(from: navigationManager.currentDate)
            PrintDayHelper.saveExpandedDayToPhotos(jobName: "Day — \(date)")
        }
    }

    @ViewBuilder
    private var bulkEditControl: some View {
        if showsCalendarBulkEdit {
            let inactive = navigationManager.currentView == .journalDayViews ||
            navigationManager.currentInterval == .month ||
            navigationManager.currentInterval == .year ||
            navigationManager.currentView == .yearlyCalendar

            iconButton("checkmark.rectangle.stack", color: inactive ? .secondary.opacity(0.4) : .accentColor) {
                if navigationManager.currentView == .bookView {
                    NotificationCenter.default.post(name: .toggleBookViewBulkEdit, object: nil)
                } else if navigationManager.currentInterval == .day {
                    NotificationCenter.default.post(name: .toggleCalendarBulkEdit, object: nil)
                } else if navigationManager.currentInterval == .week {
                    NotificationCenter.default.post(name: .toggleWeeklyCalendarBulkEdit, object: nil)
                }
            }
            .disabled(inactive)
            .help("Bulk edit")
        } else if navigationManager.currentView == .tasks {
            iconButton("checkmark.rectangle.stack", color: .accentColor) {
                NotificationCenter.default.post(name: .toggleTasksBulkEdit, object: nil)
            }
            .help("Bulk edit")
        } else if navigationManager.currentView == .lists {
            iconButton("checkmark.rectangle.stack", color: .accentColor) {
                NotificationCenter.default.post(name: .toggleListsBulkEdit, object: nil)
            }
            .help("Bulk edit")
        } else if navigationManager.currentView == .timebox {
            iconButton("checkmark.rectangle.stack", color: .accentColor) {
                NotificationCenter.default.post(name: .toggleTimeboxBulkEdit, object: nil)
            }
            .help("Bulk edit")
        }
    }

    /// Every item here opens the same create window; the choice only picks
    /// which tab it lands on, and the user can switch tabs from there. All
    /// types are always offered — the window supports them regardless of
    /// which screen the user is on.
    private var addMenu: some View {
        Menu {
            Button("Event") { navigationManager.present(.addEvent) }
            Button("Task") { navigationManager.present(.addTask) }
            Button("List") { navigationManager.present(.addList) }
            Button("Goal") { navigationManager.present(.addGoal) }
            Button("Log") { navigationManager.present(.addLog) }
        } label: {
            Image(systemName: "plus")
                .font(iconFont)
                .frame(width: buttonSize, height: buttonSize)
        }
        .help("Add")
    }

    private func iconButton(_ systemName: String, color: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(iconFont)
                .frame(width: buttonSize, height: buttonSize)
                .foregroundColor(color)
        }
    }

    private func intervalButton(_ interval: TimelineInterval, symbol: String) -> some View {
        Button {
            if navigationManager.currentView == .tasks && navigationManager.showingAllTasks {
                let notification: Notification.Name
                switch interval {
                case .day: notification = .filterTasksToCurrentDay
                case .week: notification = .filterTasksToCurrentWeek
                case .month: notification = .filterTasksToCurrentMonth
                case .year: notification = .filterTasksToCurrentYear
                }
                NotificationCenter.default.post(name: notification, object: nil)
            } else {
                handleTimeIntervalChange(interval)
            }
        } label: {
            Image(systemName: symbol)
                .font(iconFont)
                .frame(width: buttonSize, height: buttonSize)
                .foregroundColor(intervalColor(interval))
        }
        .help(interval.rawValue.capitalized)
    }

    private func taskSubfilterButton(_ title: String, _ filter: AllTaskSubfilter) -> some View {
        Button(title) {
            NotificationCenter.default.post(name: .showAllTasksRequested, object: nil)
            NotificationCenter.default.post(name: .setAllTasksSubfilter, object: filter)
        }
    }

    private func intervalColor(_ interval: TimelineInterval) -> Color {
        if navigationManager.showingAllTasks || navigationManager.currentView == .yearlyCalendar && interval != .year {
            return .secondary
        }
        if navigationManager.currentView == .timebox {
            return .secondary
        }
        return navigationManager.currentInterval == interval ? .accentColor : .secondary
    }

    private func monthLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: navigationManager.currentDate)
    }

    private func yearLabel() -> String {
        String(Calendar.current.component(.year, from: navigationManager.currentDate))
    }

    private func weekLabel(prefix: String) -> String {
        guard let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: navigationManager.currentDate) else {
            return "Week"
        }
        let start = weekInterval.start
        let end = Calendar.mondayFirst.date(byAdding: .day, value: 6, to: start) ?? start
        let weekNumber = Calendar.mondayFirst.component(.weekOfYear, from: start)
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return "\(prefix) \(weekNumber): \(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private var isCurrentPeriod: Bool {
        let now = Date()
        switch navigationManager.currentInterval {
        case .year:
            return Calendar.current.isDate(navigationManager.currentDate, equalTo: now, toGranularity: .year)
        case .month:
            return Calendar.current.isDate(navigationManager.currentDate, equalTo: now, toGranularity: .month)
        case .week:
            guard let current = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: navigationManager.currentDate),
                  let thisWeek = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: now) else {
                return false
            }
            return current.start == thisWeek.start
        case .day:
            return Calendar.current.isDate(navigationManager.currentDate, inSameDayAs: now)
        }
    }

    private var timeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 35)
            .onEnded { value in
                guard canNavigateDate else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.4 else { return }

                if horizontal < -45 {
                    step(1)
                } else if horizontal > 45 {
                    step(-1)
                }
            }
    }

    private func handleTimeIntervalChange(_ interval: TimelineInterval) {
        if navigationManager.currentView == .goals {
            navigationManager.setTimelineInterval(interval, date: Date())
        } else if navigationManager.currentView == .bookView {
            let now = Date()
            navigationManager.setTimelineInterval(interval, date: now)
            switch interval {
            case .day:
                NotificationCenter.default.post(name: .bookViewNavigateToDay, object: now)
            case .week:
                NotificationCenter.default.post(name: .bookViewNavigateToWeek, object: now)
            case .month:
                let month = Calendar.current.component(.month, from: now)
                let year = Calendar.current.component(.year, from: now)
                NotificationCenter.default.post(name: .bookViewNavigateToMonth, object: [month, year])
            case .year:
                NotificationCenter.default.post(name: .bookViewNavigateToYear, object: Calendar.current.component(.year, from: now))
            }
        } else if navigationManager.showTasksView {
            navigationManager.showingAllTasks = false
            navigationManager.setTimelineInterval(interval, date: Date())
        } else if navigationManager.currentView == .yearlyCalendar {
            navigationManager.showingAllTasks = false
            navigationManager.setTimelineInterval(interval, date: Date())
            if interval != .year {
                navigationManager.switchToCalendar()
            }
        } else {
            navigationManager.showingAllTasks = false
            navigationManager.setTimelineInterval(interval, date: Date())
            if interval == .year {
                navigationManager.switchToYearlyCalendar()
            } else {
                navigationManager.switchToCalendar()
            }
        }
    }

    private func step(_ direction: Int) {
        if navigationManager.currentView == .bookView {
            stepBookView(direction)
            return
        }

        if navigationManager.currentView == .yearlyCalendar {
            if let newDate = Calendar.mondayFirst.date(byAdding: .year, value: direction, to: navigationManager.currentDate) {
                navigationManager.setTimelineInterval(navigationManager.currentInterval, date: newDate)
            }
            return
        }

        if navigationManager.currentView == .journalDayViews {
            if let newDate = Calendar.mondayFirst.date(byAdding: navigationManager.currentInterval.calendarComponent, value: direction, to: navigationManager.currentDate) {
                navigationManager.setTimelineInterval(navigationManager.currentInterval, date: newDate)
                NotificationCenter.default.post(name: .refreshJournalContent, object: nil)
            }
            return
        }

        let timeDirection: NavigationManager.TimeDirection = direction < 0 ? .previous : .next
        guard let newDate = navigationManager.moveFocusedDate(timeDirection) else {
            return
        }

        Task {
            calendarVM.clearAllData()
            await tasksVM.loadTasks(forceClear: true)

            switch navigationManager.currentInterval {
            case .day:
                await calendarVM.loadCalendarData(for: newDate)
            case .week:
                await calendarVM.loadCalendarDataForWeek(containing: newDate)
            case .month, .year:
                await calendarVM.loadCalendarDataForMonth(containing: newDate)
            }

            await MainActor.run {
                LogsViewModel.shared.reloadData()
                NotificationCenter.default.post(name: .iCloudDataChanged, object: nil)
                NotificationCenter.default.post(name: .refreshJournalContent, object: nil)
                calendarVM.objectWillChange.send()
                tasksVM.objectWillChange.send()
            }
        }
    }

    private func stepBookView(_ direction: Int) {
        guard let newDate = Calendar.mondayFirst.date(byAdding: navigationManager.currentInterval.calendarComponent, value: direction, to: navigationManager.currentDate) else {
            return
        }
        navigationManager.setTimelineInterval(navigationManager.currentInterval, date: newDate)
        switch navigationManager.currentInterval {
        case .day:
            NotificationCenter.default.post(name: .bookViewNavigateToDay, object: newDate)
        case .week:
            NotificationCenter.default.post(name: .bookViewNavigateToWeek, object: newDate)
        case .month:
            let month = Calendar.current.component(.month, from: newDate)
            let year = Calendar.current.component(.year, from: newDate)
            NotificationCenter.default.post(name: .bookViewNavigateToMonth, object: [month, year])
        case .year:
            NotificationCenter.default.post(name: .bookViewNavigateToYear, object: Calendar.current.component(.year, from: newDate))
        }
    }

    private func reloadAllData() async {
        await MainActor.run { isSyncing = true }

        iCloudManager.shared.forceCompleteSync()
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        let currentDate = navigationManager.currentDate
        GoalsManager.shared.refreshData()
        CustomLogManager.shared.refreshData()

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        await MainActor.run {
            TaskTimeWindowManager.shared.loadTimeWindows()
        }

        switch navigationManager.currentInterval {
        case .day:
            await calendarVM.loadCalendarData(for: currentDate)
        case .week:
            await calendarVM.loadCalendarDataForWeek(containing: currentDate)
        case .month, .year:
            await calendarVM.loadCalendarDataForMonth(containing: currentDate)
        }

        await tasksVM.loadTasks(forceClear: true)
        LogsViewModel.shared.reloadData()

        await MainActor.run {
            PersistenceController.shared.container.viewContext.refreshAllObjects()
        }

        NotificationCenter.default.post(name: .refreshJournalContent, object: nil)
        iCloudManager.shared.lastSyncDate = Date()

        await MainActor.run { isSyncing = false }
    }

}

private struct NavBarContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct NavBarOneLineIdealWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    GlobalNavBar()
}
