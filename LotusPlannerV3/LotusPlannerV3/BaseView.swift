import SwiftUI

enum ViewMode: String, CaseIterable, Hashable {
    case day
    case week
    case month
    case year
}

struct BaseView: View {
    @EnvironmentObject var appPrefs: AppPreferences
    @State private var selectedDate = Date()
    @State private var viewMode: ViewMode = .day
    
    var body: some View {
        VStack(spacing: 0) {
            // Global Navigation Bar
            HStack(spacing: 8) {
                // Shared toolbar icons (settings, goals, calendar, tasks)
                SharedNavigationToolbar()
                
                // Date navigation arrows and title
                Button(action: { step(-1) }) {
                    Image(systemName: "chevron.left")
                }
                // Changed from Button to just Text
                Text(titleText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Button(action: { step(1) }) {
                    Image(systemName: "chevron.right")
                }
                
                Spacer()
                
                Picker("", selection: $viewMode) {
                    Text("Day").tag(ViewMode.day)
                    Text("Week").tag(ViewMode.week)
                    Text("Month").tag(ViewMode.month)
                    Text("Year").tag(ViewMode.year)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 300)
            }
            .padding(.horizontal)
            .frame(height: 44)
            .background(Color(UIColor.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.2)),
                alignment: .bottom
            )
            
            // Content area
            ScrollView {
                Text("Base View Content")
                    .padding()
            }
        }
    }
}

// MARK: - Helpers

extension BaseView {
    private var titleText: String {
        switch viewMode {
        case .year:
            return yearTitle
        case .month:
            return monthTitle
        case .week:
            return weekTitle
        case .day:
            return dayTitle
        }
    }
    
    private var yearTitle: String {
        let year = Calendar.current.component(.year, from: selectedDate)
        return String(year)
    }
    
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }
    
    private var weekTitle: String {
        let calendar = Calendar.mondayFirst
        guard
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start,
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)
        else { return "Week" }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startString = formatter.string(from: weekStart)
        let endString = formatter.string(from: weekEnd)
        
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: selectedDate)
        
        return "\(startString) - \(endString), \(year)"
    }
    
    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: selectedDate)
    }
    
    private func step(_ offset: Int) {
        let calendar = Calendar.current
        let component: Calendar.Component
        switch viewMode {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        if let newDate = calendar.date(byAdding: component, value: offset, to: selectedDate) {
            selectedDate = newDate
        }
    }
}

extension ViewMode {
    var displayName: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}