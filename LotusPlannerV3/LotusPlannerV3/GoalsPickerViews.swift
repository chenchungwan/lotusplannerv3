import SwiftUI

// MARK: - Custom Picker Views

// UIPickerView is unsupported under the Mac idiom of Mac Catalyst — adding
// one to a window throws _throwForUnsupportedNonMacIdiomBehavior and crashes
// the app. Substitute the menu style when running on Catalyst.
private extension View {
    @ViewBuilder
    func wheelOrMenuPickerStyle() -> some View {
        #if targetEnvironment(macCatalyst)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.wheel)
        #endif
    }
}

struct YearPickerView: View {
    @Binding var selectedDate: Date
    
    private var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 10))
    }
    
    var body: some View {
        VStack {
            Text("Year")
                .font(.headline)
                .padding(.bottom, 4)
            
                Picker("Year", selection: Binding(
                    get: { Calendar.current.component(.year, from: selectedDate) },
                    set: { year in
                        let calendar = Calendar.current
                        let components = calendar.dateComponents([.month, .day], from: selectedDate)
                        var newComponents = components
                        newComponents.year = year
                        selectedDate = calendar.date(from: newComponents) ?? selectedDate
                    }
                )) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year))
                            .font(.title3)
                            .tag(year)
                    }
                }
            .wheelOrMenuPickerStyle()
        }
    }
}

struct MonthPickerView: View {
    @Binding var selectedDate: Date
    
    private let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    
    private var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 5))
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text("Year")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Picker("Year", selection: Binding(
                    get: { Calendar.current.component(.year, from: selectedDate) },
                    set: { year in
                        let calendar = Calendar.current
                        let month = calendar.component(.month, from: selectedDate)
                        let components = calendar.dateComponents([.day], from: selectedDate)
                        var newComponents = components
                        newComponents.year = year
                        newComponents.month = month
                        selectedDate = calendar.date(from: newComponents) ?? selectedDate
                    }
                )) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year))
                            .font(.title3)
                            .tag(year)
                    }
                }
                .wheelOrMenuPickerStyle()
            }
            
            VStack {
                Text("Month")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Picker("Month", selection: Binding(
                    get: { Calendar.current.component(.month, from: selectedDate) },
                    set: { month in
                        let calendar = Calendar.current
                        let year = calendar.component(.year, from: selectedDate)
                        let components = calendar.dateComponents([.day], from: selectedDate)
                        var newComponents = components
                        newComponents.year = year
                        newComponents.month = month
                        selectedDate = calendar.date(from: newComponents) ?? selectedDate
                    }
                )) {
                    ForEach(1...12, id: \.self) { month in
                        Text(months[month - 1])
                            .font(.title3)
                            .tag(month)
                    }
                }
                .wheelOrMenuPickerStyle()
            }
        }
        .padding(.vertical, 4)
    }
}

struct WeekPickerView: View {
    @Binding var selectedDate: Date
    
    private let calendar = Calendar.mondayFirst
    @State private var selectedYear: Int
    @State private var selectedWeek: Int
    
    init(selectedDate: Binding<Date>) {
        self._selectedDate = selectedDate
        let currentDate = selectedDate.wrappedValue
        let calendar = Calendar.mondayFirst
        self._selectedYear = State(initialValue: calendar.component(.year, from: currentDate))
        self._selectedWeek = State(initialValue: calendar.component(.weekOfYear, from: currentDate))
    }
    
    private var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 2))
    }
    
    private var weeks: [(weekNumber: Int, startDate: Date, endDate: Date)] {
        var weeks: [(Int, Date, Date)] = []
        
        let startOfYear = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1))!
        let endOfYear = calendar.date(from: DateComponents(year: selectedYear, month: 12, day: 31))!
        
        var currentWeek = startOfYear
        while currentWeek <= endOfYear {
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: currentWeek) {
                let weekNumber = calendar.component(.weekOfYear, from: currentWeek)
                let endDate = calendar.date(byAdding: .day, value: 6, to: weekInterval.start) ?? weekInterval.end
                weeks.append((weekNumber, weekInterval.start, endDate))
            }
            currentWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeek) ?? endOfYear
        }
        
        return weeks
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text("Year")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Picker("Year", selection: $selectedYear) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year))
                            .font(.title3)
                            .tag(year)
                    }
                }
                .wheelOrMenuPickerStyle()
                .onChange(of: selectedYear) {
                    updateSelectedDate()
                }
            }
            
            VStack {
                Text("Week")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Picker("Week", selection: $selectedWeek) {
                    ForEach(weeks, id: \.weekNumber) { week in
                        let weekText = "WK\(week.weekNumber): \(formatWeekRange(week.startDate, week.endDate))"
                        Text(weekText)
                            .font(.body)
                            .tag(week.weekNumber)
                    }
                }
                .wheelOrMenuPickerStyle()
                .onChange(of: selectedWeek) {
                    updateSelectedDate()
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func updateSelectedDate() {
        if let week = weeks.first(where: { $0.weekNumber == selectedWeek }) {
            selectedDate = week.startDate
        }
    }
    
    private func formatWeekRange(_ startDate: Date, _ endDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)
        return "\(startString) - \(endString)"
    }
}

