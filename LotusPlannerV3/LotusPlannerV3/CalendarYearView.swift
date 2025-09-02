import SwiftUI



struct CalendarYearView: View {
    let currentDate: Date
    let onDateSelected: (Date) -> Void
    
    private let calendar = Calendar.mondayFirst
    private let monthsPerRow = 3
    private let monthNames = ["January", "February", "March", "April", "May", "June",
                            "July", "August", "September", "October", "November", "December"]
    private let weekDaySymbols = ["M", "T", "W", "T", "F", "S", "S"]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: monthsPerRow), spacing: 16) {
                ForEach(0..<12) { monthIndex in
                    monthView(for: monthIndex)
                }
            }
            .padding()
        }
    }
    
    private func monthView(for monthIndex: Int) -> some View {
        let monthDate = calendar.date(byAdding: .month, value: monthIndex, to: yearStart)!
        let isCurrentMonth = calendar.isDate(monthDate, equalTo: Date(), toGranularity: .month)
        let isCurrentYear = calendar.isDate(currentDate, equalTo: Date(), toGranularity: .year)
        
        return VStack(spacing: 4) {
            // Month header - Standardized styling
            Text(monthNames[monthIndex])
                .font(DateDisplayStyle.titleFont)
                .foregroundColor(DateDisplayStyle.dateColor(isToday: false, isCurrentPeriod: isCurrentMonth && isCurrentYear))
            
            // Week day headers
            HStack(spacing: 4) {
                ForEach(weekDaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(DateDisplayStyle.subtitleFont)
                        .foregroundColor(DateDisplayStyle.secondaryColor)
                        .frame(width: 20)
                }
            }
            
            // Day grid
            VStack(spacing: 4) {
                ForEach(monthWeeks(for: monthDate), id: \.self) { week in
                    HStack(spacing: 4) {
                        ForEach(0..<7) { weekday in
                            if let date = week[weekday] {
                                dayCell(date)
                            } else {
                                Color.clear
                                    .frame(width: 20, height: 20)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    private func dayCell(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: currentDate)
        
        return Text("\(calendar.component(.day, from: date))")
            .font(DateDisplayStyle.subtitleFont)
            .foregroundColor(cellTextColor(for: date))
            .frame(width: 20, height: 20)
            .background(cellBackground(isToday: isToday, isSelected: isSelected))
            .clipShape(Circle())
            .contentShape(Circle())
            .onTapGesture {
                onDateSelected(date)
            }
    }
    
    private func cellTextColor(for date: Date) -> Color {
        if calendar.isDateInToday(date) {
            return .white
        } else if calendar.isDate(date, inSameDayAs: currentDate) {
            return .blue
        } else if calendar.isDate(date, equalTo: currentDate, toGranularity: .month) {
            return .primary
        } else {
            return .secondary
        }
    }
    
    private func cellBackground(isToday: Bool, isSelected: Bool) -> Color {
        if isToday {
            return .blue
        } else if isSelected {
            return .blue.opacity(0.2)
        } else {
            return .clear
        }
    }
    
    private var yearStart: Date {
        let components = calendar.dateComponents([.year], from: currentDate)
        return calendar.date(from: components)!
    }
    
    private func monthWeeks(for date: Date) -> [[Date?]] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return []
        }
        
        let weekday = calendar.component(.weekday, from: monthStart)
        let weekdayOffset = (weekday + 5) % 7 // Convert to Monday-based (0-6)
        
        var weeks: [[Date?]] = []
        var currentWeek: [Date?] = Array(repeating: nil, count: weekdayOffset)
        
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 0
        
        for day in 1...daysInMonth {
            if let dayDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                currentWeek.append(dayDate)
                
                if currentWeek.count == 7 {
                    weeks.append(currentWeek)
                    currentWeek = []
                }
            }
        }
        
        // Fill the last week with nil if needed
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                currentWeek.append(nil)
            }
            weeks.append(currentWeek)
        }
        
        return weeks
    }
}

#Preview {
    CalendarYearView(currentDate: Date()) { _ in }
}

