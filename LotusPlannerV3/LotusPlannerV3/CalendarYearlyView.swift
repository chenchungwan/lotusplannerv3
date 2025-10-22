import SwiftUI

struct CalendarYearlyView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @State private var currentYear: Int
    @State private var selectedDate: Date
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    init() {
        let today = Date()
        self._currentYear = State(initialValue: Calendar.current.component(.year, from: today))
        self._selectedDate = State(initialValue: today)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Global navigation bar
            GlobalNavBar()
            
            GeometryReader { geometry in
                // 12-month grid
                monthsGrid(geometry: geometry)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            // Sync currentYear with navigationManager's currentDate
            currentYear = Calendar.current.component(.year, from: navigationManager.currentDate)
            // Listen for calendar data refresh requests
            NotificationCenter.default.addObserver(forName: Notification.Name("RefreshCalendarData"), object: nil, queue: .main) { _ in
                // Update currentYear when switching to calendar view
                currentYear = Calendar.current.component(.year, from: navigationManager.currentDate)
                selectedDate = navigationManager.currentDate
            }
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            // Update currentYear when navigationManager's date changes
            currentYear = Calendar.current.component(.year, from: newValue)
        }
        .onChange(of: navigationManager.currentView) { oldValue, newValue in
            // If we're no longer in yearly calendar view, the parent will handle the view switch
            // This is just to ensure the view updates properly
        }
    }
    
    // MARK: - Adaptive Layout Configuration
    private var adaptiveColumns: Int {
        switch (horizontalSizeClass, verticalSizeClass) {
        case (.compact, .regular):  // iPhone portrait
            return 1
        case (.compact, .compact):  // iPhone landscape
            return 2
        default:  // iPad
            return 3
        }
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 16
    }
    
    private var adaptiveGridSpacing: CGFloat {
        horizontalSizeClass == .compact ? 8 : 16
    }
    
    private var adaptiveColumnSpacing: CGFloat {
        horizontalSizeClass == .compact ? 6 : 12
    }
    
    private func adaptiveMinCardHeight(availableHeight: CGFloat, rows: Int) -> CGFloat {
        // Calculate minimum height needed for all content:
        // Single column (iPhone portrait):
        //   - Month title: ~35pt (title font)
        //   - Week headers: ~28pt (body font)
        //   - 6 week rows: 192pt (6 × 32pt cells)
        //   - Spacing: ~20pt (5 × 4pt)
        //   - Padding: ~16pt (2 × 8pt)
        //   - Total: ~291pt minimum
        // Multi-column:
        //   - Month title: ~25-35pt
        //   - Week headers: ~20-28pt
        //   - 6 week rows: 144-168pt (6 × 24-28pt)
        //   - Spacing: ~10-20pt
        //   - Padding: ~8-16pt
        //   - Total: ~207-267pt minimum
        
        switch (horizontalSizeClass, verticalSizeClass) {
        case (.compact, .regular):  // iPhone portrait - 1 column, 12 rows (larger fonts)
            return max((availableHeight - (adaptiveGridSpacing * CGFloat(rows - 1))) / CGFloat(rows), 290)
        case (.compact, .compact):  // iPhone landscape - 2 columns, 6 rows
            return max((availableHeight - (adaptiveGridSpacing * CGFloat(rows - 1))) / CGFloat(rows), 200)
        default:  // iPad - 3 columns, 4 rows
            return max((availableHeight - (adaptiveGridSpacing * CGFloat(rows - 1))) / CGFloat(rows), 260)
        }
    }
    
    private func monthsGrid(geometry: GeometryProxy) -> some View {
        let columns = adaptiveColumns
        let availableHeight = max(geometry.size.height, 400)
        let rows = 12 / columns  // Calculate rows based on columns
        let monthCardHeight = adaptiveMinCardHeight(availableHeight: availableHeight, rows: rows)
        
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: adaptiveColumnSpacing), count: columns), spacing: adaptiveGridSpacing) {
                    ForEach(1...12, id: \.self) { month in
                        YearlyMonthCardView(
                            month: month,
                            year: currentYear,
                            currentDate: selectedDate,
                            horizontalSizeClass: horizontalSizeClass,
                            verticalSizeClass: verticalSizeClass,
                            onDayTap: { date in
                                selectedDate = date
                                navigationManager.switchToCalendar()
                                navigationManager.updateInterval(.day, date: date)
                            },
                            onMonthTap: {
                                let monthDate = Calendar.mondayFirst.date(from: DateComponents(year: currentYear, month: month, day: 1))!
                                selectedDate = monthDate
                                navigationManager.switchToCalendar()
                                navigationManager.updateInterval(.month, date: monthDate)
                            },
                            onWeekTap: { date in
                                selectedDate = date
                                navigationManager.switchToCalendar()
                                navigationManager.updateInterval(.week, date: date)
                            }
                        )
                        .frame(height: monthCardHeight)
                        .id(month)  // Add identifier for scrolling
                    }
                }
                .padding(adaptivePadding)
            }
            .onAppear {
                // Scroll to current month on appear
                scrollToCurrentMonth(proxy: proxy)
            }
            .onChange(of: currentYear) { oldValue, newValue in
                // Scroll to current month when year changes
                scrollToCurrentMonth(proxy: proxy)
            }
        }
    }
    
    private func scrollToCurrentMonth(proxy: ScrollViewProxy) {
        let currentMonth = Calendar.current.component(.month, from: navigationManager.currentDate)
        let currentYearFromDate = Calendar.current.component(.year, from: navigationManager.currentDate)
        
        // Only scroll if we're viewing the current year
        if currentYearFromDate == currentYear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(currentMonth, anchor: .center)
                }
            }
        }
    }
    
    private func previousYear() {
        if let newDate = Calendar.mondayFirst.date(byAdding: .year, value: -1, to: navigationManager.currentDate) {
            navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
        }
    }
    
    private func nextYear() {
        if let newDate = Calendar.mondayFirst.date(byAdding: .year, value: 1, to: navigationManager.currentDate) {
            navigationManager.updateInterval(navigationManager.currentInterval, date: newDate)
        }
    }
}

struct YearlyMonthCardView: View {
    let month: Int
    let year: Int
    let currentDate: Date
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?
    let onDayTap: (Date) -> Void
    let onMonthTap: () -> Void
    let onWeekTap: (Date) -> Void
    
    // MARK: - Adaptive Configuration
    private var isCompactDevice: Bool {
        horizontalSizeClass == .compact
    }
    
    private var isSingleColumn: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    private var monthNameFont: Font {
        if isSingleColumn {
            return .title  // Larger for single column
        } else if isCompactDevice {
            return .headline
        } else {
            return .title2
        }
    }
    
    private var dayFont: Font {
        if isSingleColumn {
            return .body  // Larger for single column
        } else if isCompactDevice {
            return .caption2
        } else {
            return .caption
        }
    }
    
    private var shouldShowWeekNumbers: Bool {
        // Hide week numbers on very small screens to save space
        !isCompactDevice || verticalSizeClass == .compact
    }
    
    private var adaptiveSpacing: CGFloat {
        if isSingleColumn {
            return 4  // More spacing for single column
        } else if isCompactDevice {
            return 2
        } else {
            return 4
        }
    }
    
    private var adaptivePadding: CGFloat {
        if isSingleColumn {
            return 8  // More padding for single column
        } else if isCompactDevice {
            return 4
        } else {
            return 8
        }
    }
    
    private var dayCellHeight: CGFloat {
        if isSingleColumn {
            return 32  // Taller cells for larger text
        } else if isCompactDevice {
            return 24
        } else {
            return 28
        }
    }
    
    private var weekNumberWidth: CGFloat {
        if isSingleColumn {
            return 24  // Wider for larger text
        } else if isCompactDevice {
            return 16
        } else {
            return 20
        }
    }
    
    private var monthName: String {
        // Use full month names in single column, short names in multi-column compact
        if isSingleColumn {
            return Calendar.mondayFirst.monthSymbols[month - 1]  // Full name
        } else if isCompactDevice {
            return Calendar.mondayFirst.shortMonthSymbols[month - 1]  // Short name
        } else {
            return Calendar.mondayFirst.monthSymbols[month - 1]  // Full name
        }
    }
    
    private var isCurrentMonth: Bool {
        let today = Date()
        return Calendar.mondayFirst.component(.year, from: today) == year &&
               Calendar.mondayFirst.component(.month, from: today) == month
    }
    
    private var currentDay: Int {
        Calendar.mondayFirst.component(.day, from: currentDate)
    }
    
    private var todayDay: Int {
        Calendar.mondayFirst.component(.day, from: Date())
    }
    
    private var monthData: (daysInMonth: Int, offsetDays: Int) {
        let calendar = Calendar.mondayFirst
        let monthDate = calendar.date(from: DateComponents(year: year, month: month))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: monthDate)
        let offsetDays = (firstWeekday + 5) % 7
        return (daysInMonth, offsetDays)
    }
    
    var body: some View {
        VStack(spacing: adaptiveSpacing) {
            // Month title
            Text(monthName)
                .font(monthNameFont)
                .fontWeight(.semibold)
                .foregroundColor(isCurrentMonth ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isSingleColumn ? 8 : (isCompactDevice ? 4 : 6))
                .background(isCurrentMonth ? Color.blue : Color.clear)
                .cornerRadius(isSingleColumn ? 8 : (isCompactDevice ? 4 : 6))
                .contentShape(Rectangle())
                .onTapGesture { onMonthTap() }
            
            // Week headers
            HStack(spacing: adaptiveSpacing) {
                // Week number column header (conditional)
                if shouldShowWeekNumbers {
                    Text("W")
                        .font(dayFont)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: weekNumberWidth)
                }
                
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(dayFont)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            VStack(spacing: adaptiveSpacing) {
                ForEach(0..<6, id: \.self) { week in
                    weekRow(week: week)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(adaptivePadding)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(isCompactDevice ? 8 : 12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private func weekRow(week: Int) -> some View {
        HStack(spacing: adaptiveSpacing) {
            // Week number (conditional)
            if shouldShowWeekNumbers {
                Text(getWeekNumber(for: week))
                    .font(dayFont)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: weekNumberWidth, height: dayCellHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let weekStart = getWeekStartDate(for: week) {
                            onWeekTap(weekStart)
                        }
                    }
            }
            
            // Days
            ForEach(0..<7, id: \.self) { dayOfWeek in
                dayCell(week: week, dayOfWeek: dayOfWeek)
            }
        }
    }
    
    private func dayCell(week: Int, dayOfWeek: Int) -> some View {
        let dayNumber = week * 7 + dayOfWeek - monthData.offsetDays + 1
        let isValidDay = dayNumber > 0 && dayNumber <= monthData.daysInMonth
        let isToday = isCurrentMonth && dayNumber == todayDay
        
        return Group {
            if isValidDay {
                Text("\(dayNumber)")
                    .font(dayFont)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .frame(height: dayCellHeight)
                    .background(isToday ? Color.red : Color.clear)
                    .foregroundColor(isToday ? .white : .primary)
                    .clipShape(Circle())
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let calendar = Calendar.mondayFirst
                        if let date = calendar.date(from: DateComponents(year: year, month: month, day: dayNumber)) {
                            onDayTap(date)
                        }
                    }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: dayCellHeight)
            }
        }
    }
    
    private func getWeekNumber(for week: Int) -> String {
        let calendar = Calendar.mondayFirst
        let firstDayOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let daysToSubtract = (firstWeekday + 5) % 7
        
        guard let firstDayOfFirstWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: firstDayOfMonth),
              let currentWeekDate = calendar.date(byAdding: .day, value: week * 7, to: firstDayOfFirstWeek) else {
            return ""
        }
        
        let weekNumber = calendar.component(.weekOfYear, from: currentWeekDate)
        return weekNumber > 0 ? "\(weekNumber)" : ""
    }
    
    private func getWeekStartDate(for week: Int) -> Date? {
        let calendar = Calendar.mondayFirst
        let firstDayOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let offsetDays = (firstWeekday + 5) % 7
        guard let firstDayOfFirstWeek = calendar.date(byAdding: .day, value: -offsetDays, to: firstDayOfMonth) else { return nil }
        return calendar.date(byAdding: .day, value: week * 7, to: firstDayOfFirstWeek)
    }
}

#Preview {
    CalendarYearlyView()
}
