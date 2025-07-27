import SwiftUI

struct Week2TimelineComponent: View {
    let currentDate: Date
    let weekEvents: [Date: [GoogleCalendarEvent]]
    let personalEvents: [GoogleCalendarEvent]
    let professionalEvents: [GoogleCalendarEvent]
    let personalColor: Color
    let professionalColor: Color
    let onEventTap: ((GoogleCalendarEvent) -> Void)?
    let onDayTap: ((Date) -> Void)?
    
    // Week dates (Monday to Sunday)
    private var weekDates: [Date] {
        let calendar = Calendar.mondayFirst
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start else {
            return []
        }
        
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 1) {
                ForEach(weekDates, id: \.self) { date in
                    dayColumn(for: date)
                        .frame(width: dayColumnWidth)
                }
            }
            .padding(.horizontal, 8)
        }
    }
    
    // Calculate day column width based on screen width
    private var dayColumnWidth: CGFloat {
        // Assume we want 7 days visible with some padding
        let screenWidth = UIScreen.main.bounds.width
        let totalPadding: CGFloat = 20 // horizontal padding
        let spacing: CGFloat = 6 // spacing between columns
        return (screenWidth - totalPadding - spacing) / 7
    }
    
    private func dayColumn(for date: Date) -> some View {
        VStack(spacing: 0) {
            // Day header
            dayHeader(for: date)
            
            // Day timeline using the same component as Day view
            TimelineComponent(
                date: date,
                events: weekEvents[date] ?? [],
                personalEvents: personalEvents,
                professionalEvents: professionalEvents,
                personalColor: personalColor,
                professionalColor: professionalColor,
                onEventTap: onEventTap
            )
        }
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .onTapGesture {
            onDayTap?(date)
        }
    }
    
    private func dayHeader(for date: Date) -> some View {
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d"
        
        return VStack(spacing: 2) {
            Text(dayFormatter.string(from: date))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(isToday ? .white : .primary)
            
            Text(dateFormatter.string(from: date))
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(isToday ? .white : .primary)
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(isToday ? Color.blue : Color(.systemGray5))
    }
}

// MARK: - Preview
struct Week2TimelineComponent_Previews: PreviewProvider {
    static var previews: some View {
        Week2TimelineComponent(
            currentDate: Date(),
            weekEvents: [:],
            personalEvents: [],
            professionalEvents: [],
            personalColor: .purple,
            professionalColor: .green,
            onEventTap: nil,
            onDayTap: nil
        )
        .previewLayout(.sizeThatFits)
    }
} 