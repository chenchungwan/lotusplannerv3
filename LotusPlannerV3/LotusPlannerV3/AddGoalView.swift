import SwiftUI

struct AddGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var goalsViewModel = DataManager.shared.goalsViewModel
    @State private var goalTitle = ""
    @State private var selectedCategory = ""
    @State private var selectedTimeframe: Timeframe = .year
    @State private var customDueDate: Date = Date()
    @State private var useCustomDueDate = false
    @State private var isCreating = false
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedWeek: Int = Calendar.current.component(.weekOfYear, from: Date())
    
    private var categories: [String] {
        goalsViewModel.categories.map { $0.title }
    }
    
    private var calculatedDueDate: Date {
        if useCustomDueDate {
            return customDueDate
        } else {
            return calculateDueDateFromSelections()
        }
    }
    
    private var canCreateGoal: Bool {
        !goalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedCategory.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Goal title", text: $goalTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Section("Category") {
                    if categories.isEmpty {
                        Text("No categories available. Please create a category first.")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
                
                Section("Timeframe") {
                    Picker("Timeframe", selection: $selectedTimeframe) {
                        ForEach(Timeframe.allCases, id: \.self) { timeframe in
                            Text(timeframe.displayName).tag(timeframe)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: selectedTimeframe) { _, newTimeframe in
                        // Reset selections when timeframe changes
                        let currentDate = Date()
                        let calendar = Calendar.current
                        selectedYear = calendar.component(.year, from: currentDate)
                        selectedMonth = calendar.component(.month, from: currentDate)
                        selectedWeek = calendar.component(.weekOfYear, from: currentDate)
                    }
                    
                    if selectedTimeframe == .year {
                        Picker("Year", selection: $selectedYear) {
                            ForEach(Calendar.current.component(.year, from: Date())...Calendar.current.component(.year, from: Date()) + 10, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    } else if selectedTimeframe == .month {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Year", selection: $selectedYear) {
                                ForEach(Calendar.current.component(.year, from: Date())...Calendar.current.component(.year, from: Date()) + 5, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            
                            Picker("Month", selection: $selectedMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(monthName(for: month)).tag(month)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    } else if selectedTimeframe == .week {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Year", selection: $selectedYear) {
                                ForEach(Calendar.current.component(.year, from: Date())...Calendar.current.component(.year, from: Date()) + 2, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            
                            Picker("Week", selection: $selectedWeek) {
                                ForEach(1...52, id: \.self) { week in
                                    Text(weekDateRange(for: week, year: selectedYear)).tag(week)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }
                }
                
                Section("Due Date") {
                    Toggle("Custom due date", isOn: $useCustomDueDate)
                    
                    if useCustomDueDate {
                        DatePicker("Due date", selection: $customDueDate, displayedComponents: .date)
                    } else {
                        HStack {
                            Text("Due date")
                            Spacer()
                            Text(calculatedDueDate, formatter: DateFormatter.shortDate)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Goal")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if selectedCategory.isEmpty && !categories.isEmpty {
                    selectedCategory = categories.first ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        createGoal()
                    }
                    .disabled(!canCreateGoal || isCreating)
                    .foregroundColor(.blue)
                }
            }
        }
    }
    
    private func createGoal() {
        guard canCreateGoal else { return }
        
        isCreating = true
        
        // Find the category ID
        guard let category = goalsViewModel.categories.first(where: { $0.title == selectedCategory }) else {
            isCreating = false
            return
        }
        
        // Create the goal
        let newGoal = Goal(
            title: goalTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            category: selectedCategory,
            timeframe: selectedTimeframe,
            dueDate: calculatedDueDate
        )
        
        // Add goal to the category
        if let categoryIndex = goalsViewModel.categories.firstIndex(where: { $0.id == category.id }) {
            goalsViewModel.categories[categoryIndex].goals.append(newGoal)
            goalsViewModel.saveCategories()
        }
        
        isCreating = false
        dismiss()
    }
    
    private func calculateDueDateFromSelections() -> Date {
        let calendar = Calendar.current
        
        switch selectedTimeframe {
        case .year:
            // Due at end of selected year
            let yearStart = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1)) ?? Date()
            let nextYear = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? yearStart
            let yearEnd = calendar.date(byAdding: .day, value: -1, to: nextYear) ?? yearStart
            return yearEnd
            
        case .month:
            // Due at end of selected month
            let monthStart = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)) ?? Date()
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? monthStart
            return monthEnd
            
        case .week:
            // Due at end of selected week (Sunday)
            let yearStart = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1)) ?? Date()
            
            // Get the first Monday of the year
            let firstWeekday = calendar.component(.weekday, from: yearStart)
            let daysUntilMonday = (2 - firstWeekday + 7) % 7 // Monday is weekday 2
            let firstMonday = calendar.date(byAdding: .day, value: daysUntilMonday, to: yearStart) ?? yearStart
            
            // Get the Monday of the selected week
            let weekMonday = calendar.date(byAdding: .weekOfYear, value: selectedWeek - 1, to: firstMonday) ?? firstMonday
            
            // Get the Sunday of that week (6 days after Monday)
            let weekSunday = calendar.date(byAdding: .day, value: 6, to: weekMonday) ?? weekMonday
            return weekSunday
        }
    }
    
    private func monthName(for month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let date = Calendar.current.date(from: DateComponents(month: month)) ?? Date()
        return formatter.string(from: date)
    }
    
    private func weekDateRange(for week: Int, year: Int) -> String {
        let calendar = Calendar.current
        
        // Get the first day of the year
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return "Invalid week"
        }
        
        // Get the first Monday of the year (week 1 starts on Monday)
        let firstWeekday = calendar.component(.weekday, from: yearStart)
        let daysUntilMonday = (2 - firstWeekday + 7) % 7 // Monday is weekday 2
        guard let firstMonday = calendar.date(byAdding: .day, value: daysUntilMonday, to: yearStart) else {
            return "Invalid week"
        }
        
        // Get the Monday of the specified week
        guard let weekMonday = calendar.date(byAdding: .weekOfYear, value: week - 1, to: firstMonday) else {
            return "Invalid week"
        }
        
        // Get the Sunday of that week (6 days after Monday)
        guard let weekSunday = calendar.date(byAdding: .day, value: 6, to: weekMonday) else {
            return "Invalid week"
        }
        
        // Format the date range as "WK46: 11/24 - 11/30"
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        
        let startString = formatter.string(from: weekMonday)
        let endString = formatter.string(from: weekSunday)
        
        return "WK\(week): \(startString) - \(endString)"
    }
}


#Preview {
    AddGoalView()
}
