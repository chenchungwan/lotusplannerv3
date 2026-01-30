import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Notification Names for BookView Navigation
extension Notification.Name {
    static let bookViewNavigateToDay = Notification.Name("BookViewNavigateToDay")
    static let bookViewNavigateToWeek = Notification.Name("BookViewNavigateToWeek")
    static let bookViewNavigateToMonth = Notification.Name("BookViewNavigateToMonth")
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

    @State private var showingSettings = false

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
        HStack(spacing: 0) {
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

                // Floating navigation overlay
                VStack {
                    bookNavOverlay
                    Spacer()
                }
            }

            // Right sidebar
            BookSidebar(
                startYear: startYear,
                numberOfYears: numberOfYears,
                activePage: pages.indices.contains(currentPage) ? pages[currentPage] : .year(startYear),
                onYearTap: { year in navigateToPage(.year(year)) },
                onMonthTap: { month, year in navigateToPage(.month(month, year)) }
            )
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
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

// MARK: - Floating Navigation Overlay
extension BookView {
    var bookNavOverlay: some View {
        HStack(spacing: 12) {
            // Hamburger menu
            Menu {
                Button(action: { navigationManager.switchToCalendar() }) {
                    Label("Calendar", systemImage: "calendar")
                }
                Button(action: { navigationManager.switchToTasks() }) {
                    Label("Tasks", systemImage: "checklist")
                }
                Button(action: { navigationManager.switchToLists() }) {
                    Label("Lists", systemImage: "list.bullet")
                }
                Button(action: { navigationManager.switchToJournalDayViews() }) {
                    Label("Journals", systemImage: "book")
                }
                if !appPrefs.hideGoals {
                    Button(action: { navigationManager.switchToGoals() }) {
                        Label("Goals (Beta)", systemImage: "target")
                    }
                }
                Divider()
                Button("Settings") { showingSettings = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .frame(minWidth: 36, minHeight: 36)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)

            // Current page label
            Text(pageLabel(for: pages[currentPage]))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer()

            // Today button
            Button("Today") {
                currentPage = todayIndex
            }
            .font(.subheadline)
            .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func pageLabel(for page: BookPageContent) -> String {
        switch page {
        case .year(let year):
            return "\(year)"
        case .month(let month, let year):
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            let date = Calendar.current.date(from: DateComponents(year: year, month: month)) ?? Date()
            return formatter.string(from: date)
        case .weekTimebox(let monday):
            let calendar = Calendar.mondayFirst
            let weekNum = calendar.component(.weekOfYear, from: monday)
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            let startStr = formatter.string(from: monday)
            let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
            let endStr = formatter.string(from: sunday)
            return "W\(weekNum) Timebox: \(startStr) - \(endStr)"
        case .weekCalendar(let monday):
            let calendar = Calendar.mondayFirst
            let weekNum = calendar.component(.weekOfYear, from: monday)
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            let startStr = formatter.string(from: monday)
            let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
            let endStr = formatter.string(from: sunday)
            return "W\(weekNum) Weekly: \(startStr) - \(endStr)"
        case .day(let date):
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            let dayOfWeek = dayFormatter.string(from: date).uppercased()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/d/yy"
            return "\(dayOfWeek) \(dateFormatter.string(from: date))"
        }
    }
}

// MARK: - Book Sidebar
struct BookSidebar: View {
    let startYear: Int
    let numberOfYears: Int
    let activePage: BookPageContent
    let onYearTap: (Int) -> Void
    let onMonthTap: (Int, Int) -> Void

    // Pastel colors for each month (matching the reference image)
    private static let monthColors: [Color] = [
        Color(red: 0.85, green: 0.85, blue: 0.95),  // Jan - light lavender
        Color(red: 0.90, green: 0.90, blue: 0.90),  // Feb - light gray
        Color(red: 0.85, green: 0.93, blue: 0.85),  // Mar - light green
        Color(red: 0.95, green: 0.90, blue: 0.80),  // Apr - light peach
        Color(red: 0.90, green: 0.95, blue: 0.80),  // May - light lime
        Color(red: 0.80, green: 0.90, blue: 0.85),  // Jun - light teal
        Color(red: 0.85, green: 0.90, blue: 0.80),  // Jul - light sage
        Color(red: 0.95, green: 0.88, blue: 0.78),  // Aug - light tan
        Color(red: 0.90, green: 0.85, blue: 0.80),  // Sep - light brown
        Color(red: 0.80, green: 0.88, blue: 0.95),  // Oct - light blue
        Color(red: 0.88, green: 0.82, blue: 0.90),  // Nov - light purple
        Color(red: 0.90, green: 0.82, blue: 0.85),  // Dec - light rose
    ]

    private static let monthAbbreviations = [
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
    ]

    /// Determine which year and month (0=year tab, 1-12=month) is active
    private var activeYearMonth: (year: Int, month: Int) {
        let calendar = Calendar.current
        switch activePage {
        case .year(let y):
            return (y, 0)
        case .month(let m, let y):
            return (y, m)
        case .weekTimebox(let date), .weekCalendar(let date):
            let y = calendar.component(.year, from: date)
            let m = calendar.component(.month, from: date)
            return (y, m)
        case .day(let date):
            let y = calendar.component(.year, from: date)
            let m = calendar.component(.month, from: date)
            return (y, m)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            // 13 tabs per year (1 year + 12 months), filling the full height
            let tabHeight = totalHeight / 13

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(0..<numberOfYears, id: \.self) { yearOffset in
                            let year = startYear + yearOffset
                            yearSection(year: year, tabHeight: tabHeight)
                                .id(year)
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo(activeYearMonth.year, anchor: .top)
                }
                .onChange(of: activeYearMonth.year) { _, newYear in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newYear, anchor: .top)
                    }
                }
            }
        }
        .frame(width: 40)
        .background(Color(.systemBackground))
    }

    private func yearSection(year: Int, tabHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Year tab
            let isActiveYear = activeYearMonth.year == year && activeYearMonth.month == 0
            Button {
                onYearTap(year)
            } label: {
                Text(String(format: "%d", year))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isActiveYear ? .white : .primary)
                    .rotationEffect(.degrees(90))
                    .fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isActiveYear ? Color.accentColor : Color(.systemGray5))
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 6, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 6
                    ))
            }
            .frame(height: tabHeight)
            .buttonStyle(.plain)

            // 12 month tabs
            ForEach(0..<12, id: \.self) { monthIndex in
                let month = monthIndex + 1
                let isActive = activeYearMonth.year == year && activeYearMonth.month == month
                let bgColor = Self.monthColors[monthIndex]

                Button {
                    onMonthTap(month, year)
                } label: {
                    Text(Self.monthAbbreviations[monthIndex])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isActive ? .white : .primary.opacity(0.8))
                        .rotationEffect(.degrees(90))
                        .fixedSize()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isActive ? Color.accentColor : bgColor)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: monthIndex == 0 ? 0 : 4,
                            bottomLeadingRadius: monthIndex == 11 ? 6 : 4,
                            bottomTrailingRadius: monthIndex == 11 ? 6 : 4,
                            topTrailingRadius: monthIndex == 0 ? 0 : 4
                        ))
                }
                .frame(height: tabHeight)
                .buttonStyle(.plain)
            }
        }
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
    @State private var selectedEvent: GoogleCalendarEvent?

    var body: some View {
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
}
