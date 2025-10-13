import SwiftUI

struct LogsTableView: View {
    @ObservedObject private var logsVM = LogsViewModel.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @State private var currentWeekStart: Date = Calendar.current.startOfWeek(for: Date())
    
    private let calendar = Calendar.current
    
    // Get all days in the current week
    private var daysInWeek: [Date] {
        (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: currentWeekStart)
        }
    }
    
    // Get week range string
    private var weekRangeString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) else {
            return ""
        }
        
        let startString = dateFormatter.string(from: currentWeekStart)
        let endString = dateFormatter.string(from: weekEnd)
        
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        
        return "\(startString) - \(endString), \(yearFormatter.string(from: currentWeekStart))"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            GlobalNavBar()
            
            // Week Navigation Header
            HStack {
                Button(action: previousWeek) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(weekRangeString)
                    .font(.headline)
                
                Spacer()
                
                Button(action: nextWeek) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                
                Button("Today") {
                    currentWeekStart = calendar.startOfWeek(for: Date())
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.leading, 8)
            }
            .padding()
            .background(Color(.systemGray6))
            
            Divider()
            
            // Table Content
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    // Header Row (Days of the week)
                    HStack(spacing: 0) {
                        // Log Type column header
                        Text("Log Type")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 100, alignment: .leading)
                            .padding(.leading, 12)
                        
                        Divider()
                        
                        // Day column headers
                        ForEach(daysInWeek, id: \.self) { date in
                            VStack(spacing: 4) {
                                Text(dayString(for: date))
                                    .font(.caption)
                                    .fontWeight(calendar.isDateInToday(date) ? .bold : .semibold)
                                    .foregroundColor(calendar.isDateInToday(date) ? .blue : .primary)
                                Text(dateString(for: date))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 100)
                            
                            if date != daysInWeek.last {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    
                    Divider()
                    
                    // Data Rows (one row per log type)
                    if appPrefs.showWeightLogs {
                        LogTypeRow(
                            logType: .weight,
                            daysInWeek: daysInWeek,
                            getEntries: { date in getWeightEntries(for: date) }
                        )
                        Divider()
                    }
                    
                    if appPrefs.showWorkoutLogs {
                        LogTypeRow(
                            logType: .workout,
                            daysInWeek: daysInWeek,
                            getEntries: { date in getWorkoutEntries(for: date) }
                        )
                        Divider()
                    }
                    
                    if appPrefs.showFoodLogs {
                        LogTypeRow(
                            logType: .food,
                            daysInWeek: daysInWeek,
                            getEntries: { date in getFoodEntries(for: date) }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func previousWeek() {
        if let newDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) {
            currentWeekStart = newDate
        }
    }
    
    private func nextWeek() {
        if let newDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) {
            currentWeekStart = newDate
        }
    }
    
    private func dayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
    
    private func getWeightEntries(for date: Date) -> [WeightLogEntry] {
        logsVM.weightEntries.filter { entry in
            calendar.isDate(entry.timestamp, inSameDayAs: date)
        }
    }
    
    private func getWorkoutEntries(for date: Date) -> [WorkoutLogEntry] {
        logsVM.workoutEntries.filter { entry in
            calendar.isDate(entry.date, inSameDayAs: date)
        }
    }
    
    private func getFoodEntries(for date: Date) -> [FoodLogEntry] {
        logsVM.foodEntries.filter { entry in
            calendar.isDate(entry.date, inSameDayAs: date)
        }
    }
}

// MARK: - Log Type Row
struct LogTypeRow: View {
    let logType: LogType
    let daysInWeek: [Date]
    let getEntries: (Date) -> Any
    
    @ObservedObject private var logsVM = LogsViewModel.shared
    
    private let calendar = Calendar.current
    
    var body: some View {
        HStack(spacing: 0) {
            // Log Type label column
            HStack(spacing: 6) {
                Image(systemName: logType.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(logType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(width: 100, alignment: .leading)
            .padding(.leading, 12)
            .padding(.vertical, 12)
            
            Divider()
            
            // Data cells for each day
            ForEach(daysInWeek, id: \.self) { date in
                let isToday = calendar.isDateInToday(date)
                
                LogCellContent(
                    content: formatEntries(for: date),
                    isEmpty: hasNoEntries(for: date),
                    isToday: isToday
                )
                .frame(width: 100)
                
                if date != daysInWeek.last {
                    Divider()
                }
            }
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Helper Methods
    private func formatEntries(for date: Date) -> String {
        switch logType {
        case .weight:
            let entries = logsVM.weightEntries.filter { entry in
                calendar.isDate(entry.timestamp, inSameDayAs: date)
            }
            guard !entries.isEmpty else { return "-" }
            return entries.map { entry in
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "h:mm a"
                let time = timeFormatter.string(from: entry.timestamp)
                return "\(String(format: "%.1f", entry.weight)) \(entry.unit.displayName)\n@ \(time)"
            }.joined(separator: "\n")
            
        case .workout:
            let entries = logsVM.workoutEntries.filter { entry in
                calendar.isDate(entry.date, inSameDayAs: date)
            }
            guard !entries.isEmpty else { return "-" }
            return entries.map { $0.name }.joined(separator: "\n")
            
        case .food:
            let entries = logsVM.foodEntries.filter { entry in
                calendar.isDate(entry.date, inSameDayAs: date)
            }
            guard !entries.isEmpty else { return "-" }
            return entries.map { $0.name }.joined(separator: "\n")
            
        case .water:
            let entries = logsVM.waterEntries.filter { entry in
                calendar.isDate(entry.date, inSameDayAs: date)
            }
            guard !entries.isEmpty else { return "-" }
            return entries.map { entry in
                "\(entry.filledCount) cups"
            }.joined(separator: "\n")
        }
    }
    
    private func hasNoEntries(for date: Date) -> Bool {
        switch logType {
        case .weight:
            return logsVM.weightEntries.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }.isEmpty
        case .workout:
            return logsVM.workoutEntries.filter { calendar.isDate($0.date, inSameDayAs: date) }.isEmpty
        case .food:
            return logsVM.foodEntries.filter { calendar.isDate($0.date, inSameDayAs: date) }.isEmpty
        case .water:
            return logsVM.waterEntries.filter { calendar.isDate($0.date, inSameDayAs: date) }.isEmpty
        }
    }
}

// MARK: - Log Cell Content
struct LogCellContent: View {
    let content: String
    let isEmpty: Bool
    var isToday: Bool = false
    
    var body: some View {
        Text(content)
            .font(.caption)
            .foregroundColor(isEmpty ? .secondary : (isToday ? .blue : .primary))
            .fontWeight(isToday ? .semibold : .regular)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .lineLimit(nil)
            .multilineTextAlignment(.center)
            .background(isToday ? Color.blue.opacity(0.08) : Color.clear)
    }
}

// MARK: - Calendar Extension
extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = self.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}

// MARK: - Preview
#Preview {
    LogsTableView()
}

