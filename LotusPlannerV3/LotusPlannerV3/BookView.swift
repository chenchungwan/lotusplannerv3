import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Notification Names for BookView Navigation
extension Notification.Name {
    static let bookViewNavigateToDay = Notification.Name("BookViewNavigateToDay")
    static let bookViewNavigateToWeek = Notification.Name("BookViewNavigateToWeek")
    static let bookViewNavigateToMonth = Notification.Name("BookViewNavigateToMonth")
    static let bookViewNavigateToYear = Notification.Name("BookViewNavigateToYear")
    static let bookViewNavigateToTimebox = Notification.Name("BookViewNavigateToTimebox")
    static let toggleBookViewBulkEdit = Notification.Name("ToggleBookViewBulkEdit")
}

// MARK: - Book Page Content Enum
enum BookPageContent: Hashable {
    case year(Int)
    case month(Int, Int)        // month number (1-12), year
    case weekTimebox(Date)      // Monday — TimeboxView for the week
    case weekCalendar(Date)     // Monday — WeeklyView for the week
    case day(Date)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .year(let y):
            hasher.combine(0)
            hasher.combine(y)
        case .month(let m, let y):
            hasher.combine(1)
            hasher.combine(m)
            hasher.combine(y)
        case .weekTimebox(let d):
            hasher.combine(2)
            hasher.combine(d)
        case .weekCalendar(let d):
            hasher.combine(3)
            hasher.combine(d)
        case .day(let d):
            hasher.combine(4)
            hasher.combine(d)
        }
    }

    static func == (lhs: BookPageContent, rhs: BookPageContent) -> Bool {
        switch (lhs, rhs) {
        case (.year(let a), .year(let b)):
            return a == b
        case (.month(let m1, let y1), .month(let m2, let y2)):
            return m1 == m2 && y1 == y2
        case (.weekTimebox(let d1), .weekTimebox(let d2)):
            return d1 == d2
        case (.weekCalendar(let d1), .weekCalendar(let d2)):
            return d1 == d2
        case (.day(let d1), .day(let d2)):
            return d1 == d2
        default:
            return false
        }
    }
}

// MARK: - Page Generator
struct BookPageGenerator {
    /// Generates pages in chronological order per year:
    ///   Year overview → then day-by-day with month/week views interleaved:
    ///     - Month view inserted before the 1st of each month
    ///     - Week timebox + weekly views inserted before each Monday
    ///     - Day view for every day
    static func generatePages(startYear: Int, numberOfYears: Int = 2) -> [BookPageContent] {
        let calendar = Calendar.mondayFirst
        var pages: [BookPageContent] = []

        for yearOffset in 0..<numberOfYears {
            let year = startYear + yearOffset

            // Year overview page
            pages.append(.year(year))

            guard let jan1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let dec31 = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { continue }

            // Walk day-by-day, inserting month and week pages at the right spots
            var currentDay = jan1
            while currentDay <= dec31 {
                let dayOfMonth = calendar.component(.day, from: currentDay)
                let weekday = calendar.component(.weekday, from: currentDay)
                let isMonday = weekday == 2 // Calendar.mondayFirst: Sunday=1, Monday=2

                // Insert month view before the 1st of each month
                if dayOfMonth == 1 {
                    let month = calendar.component(.month, from: currentDay)
                    pages.append(.month(month, year))
                }

                // Insert week timebox + weekly views before each Monday
                if isMonday {
                    pages.append(.weekTimebox(currentDay))
                    pages.append(.weekCalendar(currentDay))
                }

                // Day view
                pages.append(.day(currentDay))

                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
                currentDay = nextDay
            }
        }

        return pages
    }

    static func findTodayIndex(in pages: [BookPageContent]) -> Int {
        let calendar = Calendar.current
        let today = Date()
        return pages.firstIndex(where: { page in
            if case .day(let date) = page {
                return calendar.isDate(date, inSameDayAs: today)
            }
            return false
        }) ?? 0
    }
}

// MARK: - UIPageViewController Wrapper (Lazy, Performant)
#if os(iOS)
struct BookPageViewController: UIViewControllerRepresentable {
    let pages: [BookPageContent]
    @Binding var currentPage: Int
    let pageViewBuilder: (BookPageContent) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator

        let initialVC = context.coordinator.viewController(for: currentPage)
        pvc.setViewControllers([initialVC], direction: .forward, animated: false)

        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        // Only update if programmatic jump (not from swipe)
        guard context.coordinator.lastReportedIndex != currentPage else { return }
        let direction: UIPageViewController.NavigationDirection =
            currentPage > context.coordinator.lastReportedIndex ? .forward : .reverse
        let vc = context.coordinator.viewController(for: currentPage)
        context.coordinator.lastReportedIndex = currentPage
        pvc.setViewControllers([vc], direction: direction, animated: true)
    }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: BookPageViewController
        var lastReportedIndex: Int
        private var cachedControllers: [Int: UIHostingController<AnyView>] = [:]
        private let cacheRadius = 3

        init(_ parent: BookPageViewController) {
            self.parent = parent
            self.lastReportedIndex = parent.currentPage
        }

        func viewController(for index: Int) -> UIViewController {
            if let cached = cachedControllers[index] {
                return cached
            }
            let content = parent.pageViewBuilder(parent.pages[index])
            let hc = UIHostingController(rootView: content)
            hc.view.tag = index
            hc.view.backgroundColor = .systemBackground
            cachedControllers[index] = hc
            pruneCache(around: index)
            return hc
        }

        private func pruneCache(around index: Int) {
            let keep = (index - cacheRadius)...(index + cacheRadius)
            cachedControllers = cachedControllers.filter { keep.contains($0.key) }
        }

        // MARK: DataSource
        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            let index = viewController.view.tag
            guard index > 0 else { return nil }
            return self.viewController(for: index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            let index = viewController.view.tag
            guard index < parent.pages.count - 1 else { return nil }
            return self.viewController(for: index + 1)
        }

        // MARK: Delegate
        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed, let visibleVC = pageViewController.viewControllers?.first else { return }
            let index = visibleVC.view.tag
            lastReportedIndex = index
            parent.currentPage = index
        }
    }
}
#endif

// MARK: - Book View
struct BookView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var calendarVM = DataManager.shared.calendarViewModel
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @StateObject private var bulkEditManager = BulkEditManager()

    let pages: [BookPageContent]
    @State private var currentPage: Int
    private let todayIndex: Int
    private let startYear: Int
    private let numberOfYears: Int

    init() {
        let year = Calendar.current.component(.year, from: Date())
        let numYears = 2
        let generatedPages = BookPageGenerator.generatePages(startYear: year, numberOfYears: numYears)
        let today = BookPageGenerator.findTodayIndex(in: generatedPages)

        self.pages = generatedPages
        self._currentPage = State(initialValue: today)
        self.todayIndex = today
        self.startYear = year
        self.numberOfYears = numYears
    }

    var body: some View {
        ZStack {
            #if os(iOS)
            BookPageViewController(
                pages: pages,
                currentPage: $currentPage,
                pageViewBuilder: { page in
                    AnyView(pageView(for: page))
                }
            )
            .ignoresSafeArea(edges: .bottom)
            #endif

            // Navigation bar + tab bar overlay
            VStack(spacing: 0) {
                GlobalNavBar()
                    .background(.ultraThinMaterial)
                BookTabBar(
                    activePage: pages.indices.contains(currentPage) ? pages[currentPage] : .year(startYear),
                    onTabTap: { target in navigateToPage(target) }
                )
                Spacer()
            }
        }
        .onChange(of: currentPage) { oldValue, newValue in
            guard newValue >= 0 && newValue < pages.count else { return }
            syncNavigationManager(for: pages[newValue])
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookViewNavigateToDay)) { notification in
            if let date = notification.object as? Date {
                navigateToPage(.day(date))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookViewNavigateToWeek)) { notification in
            if let date = notification.object as? Date {
                navigateToPage(.weekTimebox(date))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookViewNavigateToMonth)) { notification in
            if let values = notification.object as? [Int], values.count == 2 {
                navigateToPage(.month(values[0], values[1]))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookViewNavigateToYear)) { notification in
            if let year = notification.object as? Int {
                navigateToPage(.year(year))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookViewNavigateToTimebox)) { notification in
            if let date = notification.object as? Date {
                navigateToPage(.weekTimebox(date))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleBookViewBulkEdit)) { _ in
            bulkEditManager.state.isActive.toggle()
            if !bulkEditManager.state.isActive {
                bulkEditManager.state.selectedTaskIds.removeAll()
            }
        }
    }
}

// MARK: - Navigation Manager Sync
extension BookView {
    private func syncNavigationManager(for page: BookPageContent) {
        switch page {
        case .year(let year):
            let date = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
            navigationManager.updateInterval(.year, date: date)
        case .month(let month, let year):
            let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
            navigationManager.updateInterval(.month, date: date)
        case .weekTimebox(let monday), .weekCalendar(let monday):
            navigationManager.updateInterval(.week, date: monday)
        case .day(let date):
            navigationManager.updateInterval(.day, date: date)
        }
    }
}

// MARK: - Page Rendering
extension BookView {
    @ViewBuilder
    func pageView(for page: BookPageContent) -> some View {
        switch page {
        case .year(let year):
            CalendarYearlyView(hideNavBar: true, overrideYear: year)
                .padding(.top, 50)
        case .month(let month, let year):
            BookMonthPage(month: month, year: year)
        case .weekTimebox:
            TimeboxView(bulkEditManager: bulkEditManager, hideNavBar: true)
                .padding(.top, 50)
        case .weekCalendar:
            WeeklyView(bulkEditManager: bulkEditManager, hideNavBar: true)
                .padding(.top, 50)
        case .day:
            BookDayPage(bulkEditManager: bulkEditManager)
                .padding(.top, 50)
        }
    }
}

// MARK: - Programmatic Navigation
extension BookView {
    func navigateToPage(_ target: BookPageContent) {
        guard let index = findPageIndex(for: target) else { return }
        currentPage = index
    }

    func findPageIndex(for target: BookPageContent) -> Int? {
        let calendar = Calendar.current
        switch target {
        case .day(let targetDate):
            return pages.firstIndex(where: {
                if case .day(let d) = $0 { return calendar.isDate(d, inSameDayAs: targetDate) }
                return false
            })
        case .weekTimebox(let targetDate):
            return pages.firstIndex(where: {
                if case .weekTimebox(let monday) = $0 {
                    let weekEnd = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
                    return targetDate >= monday && targetDate <= weekEnd
                }
                return false
            })
        case .weekCalendar(let targetDate):
            return pages.firstIndex(where: {
                if case .weekCalendar(let monday) = $0 {
                    let weekEnd = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
                    return targetDate >= monday && targetDate <= weekEnd
                }
                return false
            })
        case .month(let m, let y):
            return pages.firstIndex(where: {
                if case .month(let pm, let py) = $0 { return pm == m && py == y }
                return false
            })
        case .year(let year):
            return pages.firstIndex(where: {
                if case .year(let y) = $0 { return y == year }
                return false
            })
        }
    }
}


// MARK: - Book Tab Bar
struct BookTabBar: View {
    let activePage: BookPageContent
    let onTabTap: (BookPageContent) -> Void

    private static let tabCount = 10

    private enum TabKind {
        case today
        case week
        case month
        case year
        case blank(Int)
    }

    private var tabs: [TabKind] {
        [.today, .week, .month, .year,
         .blank(5), .blank(6), .blank(7), .blank(8), .blank(9), .blank(10)]
    }

    private func tabLabel(for tab: TabKind) -> String {
        switch tab {
        case .today: return "TODAY"
        case .week: return "WEEK"
        case .month: return "MONTH"
        case .year: return "YEAR"
        case .blank: return ""
        }
    }

    private func tabTarget(for tab: TabKind) -> BookPageContent? {
        let calendar = Calendar.current
        let now = Date()
        switch tab {
        case .today:
            return .day(now)
        case .week:
            return .weekTimebox(now)
        case .month:
            let m = calendar.component(.month, from: now)
            let y = calendar.component(.year, from: now)
            return .month(m, y)
        case .year:
            let y = calendar.component(.year, from: now)
            return .year(y)
        case .blank:
            return nil
        }
    }

    private func isTabActive(_ tab: TabKind) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        switch tab {
        case .today:
            if case .day(let date) = activePage {
                return calendar.isDate(date, inSameDayAs: now)
            }
            return false
        case .week:
            switch activePage {
            case .weekTimebox(let date), .weekCalendar(let date):
                let weekEnd = calendar.date(byAdding: .day, value: 6, to: date) ?? date
                return now >= date && now <= weekEnd
            default:
                return false
            }
        case .month:
            if case .month(let m, let y) = activePage {
                return m == calendar.component(.month, from: now)
                    && y == calendar.component(.year, from: now)
            }
            return false
        case .year:
            if case .year(let y) = activePage {
                return y == calendar.component(.year, from: now)
            }
            return false
        case .blank:
            return false
        }
    }

    private static let tabColors: [Color] = [
        Color(red: 0.85, green: 0.85, blue: 0.95),  // Today - light lavender
        Color(red: 0.85, green: 0.93, blue: 0.85),  // Week - light green
        Color(red: 0.95, green: 0.90, blue: 0.80),  // Month - light peach
        Color(red: 0.80, green: 0.88, blue: 0.95),  // Year - light blue
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                let tab = tabs[index]
                let isActive = isTabActive(tab)
                let label = tabLabel(for: tab)
                let target = tabTarget(for: tab)
                let bgColor: Color = index < Self.tabColors.count
                    ? Self.tabColors[index]
                    : Color(.systemGray6)

                Button {
                    if let target = target {
                        onTabTap(target)
                    }
                } label: {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isActive ? .white : (label.isEmpty ? .clear : .primary.opacity(0.8)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isActive ? Color.accentColor : bgColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 28)
                .buttonStyle(.plain)
                .disabled(target == nil)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Book Month Page
struct BookMonthPage: View {
    let month: Int
    let year: Int

    @ObservedObject private var calendarVM = DataManager.shared.calendarViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var authManager = GoogleAuthManager.shared

    @State private var selectedEvent: GoogleCalendarEvent?

    private var monthDate: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(monthTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 58)
                .padding(.bottom, 8)

            MonthTimelineComponent(
                currentDate: monthDate,
                monthEvents: getMonthEventsGroupedByDate(),
                personalEvents: calendarVM.personalEvents,
                professionalEvents: calendarVM.professionalEvents,
                personalColor: appPrefs.personalColor,
                professionalColor: appPrefs.professionalColor,
                onEventTap: { event in
                    selectedEvent = event
                },
                onDayTap: { date in
                    NotificationCenter.default.post(name: .bookViewNavigateToDay, object: date)
                }
            )
        }
        .background(Color(.systemBackground))
        .task {
            await calendarVM.forceLoadCalendarDataForMonth(containing: monthDate)
        }
        .sheet(item: $selectedEvent) { event in
            let accountKind: GoogleAuthManager.AccountKind =
                calendarVM.personalEvents.contains(where: { $0.id == event.id }) ? .personal : .professional
            AddItemView(
                currentDate: event.startTime ?? Date(),
                tasksViewModel: DataManager.shared.tasksViewModel,
                calendarViewModel: calendarVM,
                appPrefs: appPrefs,
                existingEvent: event,
                accountKind: accountKind,
                showEventOnly: true
            )
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: monthDate)
    }

    private func getMonthEventsGroupedByDate() -> [Date: [GoogleCalendarEvent]] {
        var allEvents: [GoogleCalendarEvent] = []
        if authManager.isLinked(kind: .personal) {
            allEvents += calendarVM.personalEvents
        }
        if authManager.isLinked(kind: .professional) {
            allEvents += calendarVM.professionalEvents
        }

        let calendar = Calendar.current
        var grouped: [Date: [GoogleCalendarEvent]] = [:]
        for event in allEvents {
            guard let startTime = event.startTime else { continue }
            let day = calendar.startOfDay(for: startTime)
            grouped[day, default: []].append(event)
        }
        return grouped
    }
}

// MARK: - Book Day Page
struct BookDayPage: View {
    @ObservedObject var bulkEditManager: BulkEditManager
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var tasksViewModel = DataManager.shared.tasksViewModel
    @State private var selectedEvent: GoogleCalendarEvent?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                dayViewContent
            }
            .sheet(item: $selectedEvent) { event in
                let calendarVM = DataManager.shared.calendarViewModel
                let accountKind: GoogleAuthManager.AccountKind =
                    calendarVM.personalEvents.contains(where: { $0.id == event.id }) ? .personal : .professional
                AddItemView(
                    currentDate: event.startTime ?? Date(),
                    tasksViewModel: DataManager.shared.tasksViewModel,
                    calendarViewModel: calendarVM,
                    appPrefs: appPrefs,
                    existingEvent: event,
                    accountKind: accountKind,
                    showEventOnly: true
                )
            }
            .confirmationDialog("Complete Tasks", isPresented: $bulkEditManager.state.showingCompleteConfirmation) {
                Button("Complete \(bulkEditManager.state.selectedTaskIds.count) task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")") {
                    Task {
                        let allTasks = getAllTasksForBulkEdit()
                        await bulkEditManager.bulkComplete(tasks: allTasks, tasksVM: tasksViewModel) { undoData in
                            bulkEditManager.state.undoAction = .complete
                            bulkEditManager.state.undoData = undoData
                            bulkEditManager.state.showingUndoToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                if bulkEditManager.state.undoAction == .complete {
                                    bulkEditManager.state.showingUndoToast = false
                                    bulkEditManager.state.undoAction = nil
                                    bulkEditManager.state.undoData = nil
                                }
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete Tasks", isPresented: $bulkEditManager.state.showingDeleteConfirmation) {
                Button("Delete \(bulkEditManager.state.selectedTaskIds.count) task\(bulkEditManager.state.selectedTaskIds.count == 1 ? "" : "s")", role: .destructive) {
                    Task {
                        let allTasks = getAllTasksForBulkEdit()
                        await bulkEditManager.bulkDelete(tasks: allTasks, tasksVM: tasksViewModel) { undoData in
                            bulkEditManager.state.undoAction = .delete
                            bulkEditManager.state.undoData = undoData
                            bulkEditManager.state.showingUndoToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                if bulkEditManager.state.undoAction == .delete {
                                    bulkEditManager.state.showingUndoToast = false
                                    bulkEditManager.state.undoAction = nil
                                    bulkEditManager.state.undoData = nil
                                }
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $bulkEditManager.state.showingDueDatePicker) {
                BulkUpdateDueDatePicker(selectedTaskIds: bulkEditManager.state.selectedTaskIds) { date, isAllDay, startTime, endTime in
                    Task {
                        let allTasks = getAllTasksForBulkEdit()
                        await bulkEditManager.bulkUpdateDueDate(
                            tasks: allTasks,
                            dueDate: date,
                            isAllDay: isAllDay,
                            startTime: startTime,
                            endTime: endTime,
                            tasksVM: tasksViewModel
                        ) { undoData in
                            bulkEditManager.state.undoAction = .updateDueDate
                            bulkEditManager.state.undoData = undoData
                            bulkEditManager.state.showingUndoToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                if bulkEditManager.state.undoAction == .updateDueDate {
                                    bulkEditManager.state.showingUndoToast = false
                                    bulkEditManager.state.undoAction = nil
                                    bulkEditManager.state.undoData = nil
                                }
                            }
                        }
                        bulkEditManager.state.showingDueDatePicker = false
                    }
                }
            }
            .sheet(isPresented: $bulkEditManager.state.showingMoveDestinationPicker) {
                BulkMoveDestinationPicker(
                    personalTaskLists: tasksViewModel.personalTaskLists,
                    professionalTaskLists: tasksViewModel.professionalTaskLists,
                    onSelect: { accountKind, listId in
                        Task {
                            let allTasks = getAllTasksForBulkEdit()
                            await bulkEditManager.bulkMove(
                                tasks: allTasks,
                                to: listId,
                                destinationAccountKind: accountKind,
                                tasksVM: tasksViewModel
                            ) { undoData in
                                bulkEditManager.state.undoAction = .move
                                bulkEditManager.state.undoData = undoData
                                bulkEditManager.state.showingUndoToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                    if bulkEditManager.state.undoAction == .move {
                                        bulkEditManager.state.showingUndoToast = false
                                        bulkEditManager.state.undoAction = nil
                                        bulkEditManager.state.undoData = nil
                                    }
                                }
                            }
                            bulkEditManager.state.showingMoveDestinationPicker = false
                        }
                    }
                )
            }
            .sheet(isPresented: $bulkEditManager.state.showingPriorityPicker) {
                BulkUpdatePriorityPicker(selectedTaskIds: bulkEditManager.state.selectedTaskIds) { priority in
                    Task {
                        let allTasks = getAllTasksForBulkEdit()
                        await bulkEditManager.bulkUpdatePriority(
                            tasks: allTasks,
                            priority: priority,
                            tasksVM: tasksViewModel
                        ) { undoData in
                            bulkEditManager.state.undoAction = .updatePriority
                            bulkEditManager.state.undoData = undoData
                            bulkEditManager.state.showingUndoToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                if bulkEditManager.state.undoAction == .updatePriority {
                                    bulkEditManager.state.showingUndoToast = false
                                    bulkEditManager.state.undoAction = nil
                                    bulkEditManager.state.undoData = nil
                                }
                            }
                        }
                        bulkEditManager.state.showingPriorityPicker = false
                    }
                }
            }

            // Undo toast overlay
            if bulkEditManager.state.showingUndoToast, let action = bulkEditManager.state.undoAction {
                VStack {
                    Spacer()
                    HStack {
                        Text(undoMessage(for: action))
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Undo") {
                            Task {
                                await performUndo()
                            }
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.yellow)
                    }
                    .padding()
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: bulkEditManager.state.showingUndoToast)
            }
        }
    }

    @ViewBuilder
    private var dayViewContent: some View {
        switch appPrefs.dayViewLayout {
        case .compact:
            DayViewNewCompact(
                bulkEditManager: bulkEditManager,
                onEventTap: { ev in selectedEvent = ev }
            )
        case .mobile:
            DayViewMobile(
                bulkEditManager: bulkEditManager,
                onEventTap: { ev in selectedEvent = ev }
            )
        case .timebox:
            DayViewNewExpanded(
                bulkEditManager: bulkEditManager,
                onEventTap: { ev in selectedEvent = ev }
            )
        case .newClassic:
            DayViewNewClassic(
                bulkEditManager: bulkEditManager,
                onEventTap: { ev in selectedEvent = ev }
            )
        default:
            DayViewNewClassic(
                bulkEditManager: bulkEditManager,
                onEventTap: { ev in selectedEvent = ev }
            )
        }
    }

    // MARK: - Bulk Edit Helpers

    private func getAllTasksForBulkEdit() -> [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] {
        var allTasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)] = []
        for (listId, tasks) in tasksViewModel.personalTasks {
            for task in tasks {
                allTasks.append((task: task, listId: listId, accountKind: .personal))
            }
        }
        for (listId, tasks) in tasksViewModel.professionalTasks {
            for task in tasks {
                allTasks.append((task: task, listId: listId, accountKind: .professional))
            }
        }
        return allTasks
    }

    private func undoMessage(for action: BulkEditAction) -> String {
        switch action {
        case .complete:
            return "Tasks marked complete"
        case .delete:
            return "Tasks deleted"
        case .move:
            return "Tasks moved"
        case .updateDueDate:
            return "Due dates updated"
        case .updatePriority:
            return "Priorities updated"
        }
    }

    private func performUndo() async {
        guard let action = bulkEditManager.state.undoAction,
              let undoData = bulkEditManager.state.undoData else { return }

        switch action {
        case .complete:
            await bulkEditManager.undoComplete(data: undoData, tasksVM: tasksViewModel)
        case .delete:
            await bulkEditManager.undoDelete(data: undoData, tasksVM: tasksViewModel)
        case .move:
            await bulkEditManager.undoMove(data: undoData, tasksVM: tasksViewModel)
        case .updateDueDate:
            await bulkEditManager.undoUpdateDueDate(data: undoData, tasksVM: tasksViewModel)
        case .updatePriority:
            await bulkEditManager.undoUpdatePriority(data: undoData, tasksVM: tasksViewModel)
        }

        bulkEditManager.state.showingUndoToast = false
        bulkEditManager.state.undoAction = nil
        bulkEditManager.state.undoData = nil
    }
}
