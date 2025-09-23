import SwiftUI

struct CalendarYearlyView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @State private var currentYear: Int
    @State private var selectedDate: Date
    
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
        }
        .onChange(of: navigationManager.currentDate) { oldValue, newValue in
            // Update currentYear when navigationManager's date changes
            currentYear = Calendar.current.component(.year, from: newValue)
        }
    }
    
    
    private func monthsGrid(geometry: GeometryProxy) -> some View {
        let padding: CGFloat = 16
        let gridSpacing: CGFloat = 16
        let columnSpacing: CGFloat = 12
        let availableHeight = max(geometry.size.height, 400) // Ensure minimum height
        let rows = 4 // 12 months ÷ 3 columns = 4 rows
        let monthCardHeight = max((availableHeight - (gridSpacing * CGFloat(rows - 1))) / CGFloat(rows), 80) // Minimum card height
        
        return ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: 3), spacing: gridSpacing) {
                ForEach(1...12, id: \.self) { month in
                    YearlyMonthCardView(
                        month: month,
                        year: currentYear,
                        currentDate: selectedDate,
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
                }
            }
            .padding(padding)
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
    let onDayTap: (Date) -> Void
    let onMonthTap: () -> Void
    let onWeekTap: (Date) -> Void
    
    private var monthName: String {
        Calendar.mondayFirst.monthSymbols[month - 1]
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
        VStack(spacing: 4) {
            // Month title
            Text(monthName)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(isCurrentMonth ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isCurrentMonth ? Color.blue : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onTapGesture { onMonthTap() }
            
            // Week headers
            HStack(spacing: 2) {
                // Week number column header
                Text("W")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { week in
                    weekRow(week: week)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private func weekRow(week: Int) -> some View {
        HStack(spacing: 2) {
            // Week number
            Text(getWeekNumber(for: week))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let weekStart = getWeekStartDate(for: week) {
                        onWeekTap(weekStart)
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
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
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
                    .frame(height: 20)
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
