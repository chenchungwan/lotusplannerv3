import SwiftUI

struct GoalsView: View {
    @StateObject private var goalsManager = GoalsManager.shared
    @StateObject private var appPrefs = AppPreferences.shared
    @StateObject private var navigationManager = NavigationManager.shared
    @State private var showingCreateGoal = false
    @State private var showingCreateCategory = false
    @State private var editingGoal: GoalData?
    
    // Computed properties for better performance
    private var sortedCategories: [GoalCategoryData] {
        goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition })
    }
    
    private var filteredGoals: [GoalData] {
        let allGoals = goalsManager.goals
        
        switch navigationManager.currentInterval {
        case .day:
            // For day view, show all goals (yearly view)
            return allGoals
        case .week:
            return filterGoalsForWeek(allGoals, date: navigationManager.currentDate)
        case .month:
            return filterGoalsForMonth(allGoals, date: navigationManager.currentDate)
        case .year:
            return filterGoalsForYear(allGoals, date: navigationManager.currentDate)
        }
    }
    
    private var goalsTitle: String {
        switch navigationManager.currentInterval {
        case .day:
            return "All Goals"
        case .week:
            let weekNumber = Calendar.mondayFirst.component(.weekOfYear, from: navigationManager.currentDate)
            return "Week \(weekNumber) Weekly Goals"
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return "\(formatter.string(from: navigationManager.currentDate)) Monthly Goals"
        case .year:
            let year = Calendar.current.component(.year, from: navigationManager.currentDate)
            return "\(year) Yearly Goals"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            GlobalNavBar()
            
            // Main Content
            GeometryReader { geometry in
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ],
                        spacing: 16
                    ) {
                        ForEach(sortedCategories) { category in
                            GoalCategoryCard(
                                category: category,
                                goals: getFilteredGoalsForCategory(category.id),
                                onGoalTap: { goal in
                                    // Handle goal tap - could show details or toggle completion
                                    goalsManager.toggleGoalCompletion(goal.id)
                                },
                                onGoalEdit: { goal in
                                    editingGoal = goal
                                    showingCreateGoal = true
                                },
                                onGoalDelete: { goal in
                                    goalsManager.deleteGoal(goal.id)
                                },
                                onCategoryEdit: { category in
                                    // Handle category edit
                                },
                                onCategoryDelete: { category in
                                    goalsManager.deleteCategory(category.id)
                                }
                            )
                            .frame(height: geometry.size.height / 3 - 16)
                        }
                        
                        // Add Category Card
                        AddCategoryCard(
                            onAddCategory: { categoryName in
                                goalsManager.addCategory(title: categoryName)
                            }
                        )
                        .frame(height: geometry.size.height / 3 - 16)
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showingCreateGoal) {
            CreateGoalView(editingGoal: editingGoal) {
                editingGoal = nil
            }
        }
        .sheet(isPresented: $showingCreateCategory) {
            CreateCategoryView()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAddGoal"))) { _ in
            editingGoal = nil
            showingCreateGoal = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAddCategory"))) { _ in
            showingCreateCategory = true
        }
        .onAppear {
            // Only refresh if data is stale
            if goalsManager.categories.isEmpty {
                goalsManager.refreshData()
            }
        }
        .onChange(of: navigationManager.currentDate) { _ in
            // Refresh goals when date changes
            goalsManager.refreshData()
        }
        .onChange(of: navigationManager.currentInterval) { _ in
            // Refresh goals when interval changes
            goalsManager.refreshData()
        }
    }
    
    // MARK: - Filtering Functions
    private func getFilteredGoalsForCategory(_ categoryId: UUID) -> [GoalData] {
        let categoryGoals = goalsManager.getGoalsForCategory(categoryId)
        
        switch navigationManager.currentInterval {
        case .day:
            // For day view, show all goals (yearly view)
            return categoryGoals
        case .week:
            return filterGoalsForWeek(categoryGoals, date: navigationManager.currentDate)
        case .month:
            return filterGoalsForMonth(categoryGoals, date: navigationManager.currentDate)
        case .year:
            return filterGoalsForYear(categoryGoals, date: navigationManager.currentDate)
        }
    }
    
    private func filterGoalsForWeek(_ goals: [GoalData], date: Date) -> [GoalData] {
        guard let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: date) else {
            return goals
        }
        
        return goals.filter { goal in
            // Filter by goal type (weekly goals only) AND due date within the week
            goal.targetTimeframe == .week && 
            goal.dueDate >= weekInterval.start && 
            goal.dueDate < weekInterval.end
        }
    }
    
    private func filterGoalsForMonth(_ goals: [GoalData], date: Date) -> [GoalData] {
        guard let monthInterval = Calendar.current.dateInterval(of: .month, for: date) else {
            return goals
        }
        
        return goals.filter { goal in
            // Filter by goal type (monthly goals only) AND due date within the month
            goal.targetTimeframe == .month && 
            goal.dueDate >= monthInterval.start && 
            goal.dueDate < monthInterval.end
        }
    }
    
    private func filterGoalsForYear(_ goals: [GoalData], date: Date) -> [GoalData] {
        guard let yearInterval = Calendar.current.dateInterval(of: .year, for: date) else {
            return goals
        }
        
        return goals.filter { goal in
            // Filter by goal type (yearly goals only) AND due date within the year
            goal.targetTimeframe == .year && 
            goal.dueDate >= yearInterval.start && 
            goal.dueDate < yearInterval.end
        }
    }
}

// MARK: - Goal Category Card
struct GoalCategoryCard: View {
    let category: GoalCategoryData
    let goals: [GoalData]
    let onGoalTap: (GoalData) -> Void
    let onGoalEdit: (GoalData) -> Void
    let onGoalDelete: (GoalData) -> Void
    let onCategoryEdit: (GoalCategoryData) -> Void
    let onCategoryDelete: (GoalCategoryData) -> Void
    
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var showingDeleteAlert = false
    
    // Computed properties for better performance
    private var completedGoalsCount: Int {
        goals.filter { $0.isCompleted }.count
    }
    
    private var totalGoalsCount: Int {
        goals.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title
            HStack {
                if isEditingTitle {
                    TextField("Category name", text: $editedTitle)
                        .font(.headline)
                        .fontWeight(.bold)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            saveCategoryTitle()
                        }
                } else {
                    Text(category.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .onTapGesture {
                            startEditingTitle()
                        }
                }
                
                Spacer()
                
                if isEditingTitle {
                    Button("Save") {
                        saveCategoryTitle()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                
                // Delete category button
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Divider()
            
            // Goals list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(goals) { goal in
                        GoalRow(
                            goal: goal,
                            onTap: { onGoalTap(goal) },
                            onEdit: { onGoalEdit(goal) },
                            onDelete: { onGoalDelete(goal) }
                        )
                    }
                    
                    if goals.isEmpty {
                        Text("No goals yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .alert("Delete Category", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onCategoryDelete(category)
            }
        } message: {
            Text("Are you sure you want to delete '\(category.title)'? All goals in this category will be deleted.")
        }
    }
    
    private func startEditingTitle() {
        editedTitle = category.title
        isEditingTitle = true
    }
    
    private func saveCategoryTitle() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            var updatedCategory = category
            updatedCategory.title = trimmed
            updatedCategory.updatedAt = Date()
            onCategoryEdit(updatedCategory)
        }
        isEditingTitle = false
    }
}

// MARK: - Goal Row
struct GoalRow: View {
    let goal: GoalData
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    // Computed properties for better performance
    private var isOverdue: Bool {
        goal.dueDate < Date() && !goal.isCompleted
    }
    
    private var daysRemaining: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDate = calendar.startOfDay(for: goal.dueDate)
        let components = calendar.dateComponents([.day], from: today, to: dueDate)
        return components.day ?? 0
    }
    
    private func formatDueDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button(action: onTap) {
                Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(goal.isCompleted ? .green : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            
            // Goal content
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.body)
                    .strikethrough(goal.isCompleted)
                    .foregroundColor(goal.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                
                HStack {
                    Text(goal.targetTimeframe.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    
                    Text(formatDueDate(goal.dueDate))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isOverdue ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                        .foregroundColor(isOverdue ? .red : .green)
                        .cornerRadius(4)
                    
                    Spacer()
                }
            }
            .onTapGesture {
                onEdit()
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Add Category Card
struct AddCategoryCard: View {
    let onAddCategory: (String) -> Void
    
    @State private var isAdding = false
    @State private var newCategoryTitle = ""
    
    var body: some View {
        VStack(spacing: 12) {
            if isAdding {
                VStack(spacing: 16) {
                    Text("New Category")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    TextField("Category name", text: $newCategoryTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            addCategory()
                        }
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            cancelAdding()
                        }
                        .foregroundColor(.secondary)
                        
                        Button("Add") {
                            addCategory()
                        }
                        .foregroundColor(.blue)
                        .disabled(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
            } else {
                Button(action: {
                    isAdding = true
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        Text("Add Category")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5]))
        )
    }
    
    private func addCategory() {
        let trimmed = newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onAddCategory(trimmed)
            cancelAdding()
        }
    }
    
    private func cancelAdding() {
        isAdding = false
        newCategoryTitle = ""
    }
}

// MARK: - Create Goal View
struct CreateGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var goalsManager = GoalsManager.shared
    
    let editingGoal: GoalData?
    let onDismiss: () -> Void
    
    @State private var title = ""
    @State private var selectedCategoryId: UUID?
    @State private var selectedTimeframe: GoalTimeframe = .year
    @State private var selectedDate = Date()
    @State private var showingDeleteAlert = false
    
    init(editingGoal: GoalData? = nil, onDismiss: @escaping () -> Void = {}) {
        self.editingGoal = editingGoal
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Goal title", text: $title)
                }
                
                Section("Category") {
                    Picker("Category", selection: Binding(
                        get: { selectedCategoryId },
                        set: { selectedCategoryId = $0 }
                    )) {
                        Text("Select a category").tag(nil as UUID?)
                        ForEach(goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition }), id: \.id) { category in
                            Text(category.title).tag(category.id as UUID?)
                        }
                    }
                }
                
                Section("Due Date") {
                    // Timeframe Selection with Radio Buttons
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Timeframe")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach([GoalTimeframe.year, GoalTimeframe.month, GoalTimeframe.week], id: \.self) { timeframe in
                                HStack {
                                    Button(action: {
                                        selectedTimeframe = timeframe
                                    }) {
                                        HStack {
                                            Image(systemName: selectedTimeframe == timeframe ? "largecircle.fill.circle" : "circle")
                                                .foregroundColor(selectedTimeframe == timeframe ? .accentColor : .secondary)
                                                .font(.title2)
                                            
                                            Text(timeframe.displayName)
                                                .font(.body)
                                                .fontWeight(selectedTimeframe == timeframe ? .semibold : .regular)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                    // Date Picker based on selected timeframe
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target \(selectedTimeframe.displayName.lowercased())")
                            .font(.headline)
                        
                        switch selectedTimeframe {
                        case .year:
                            YearPickerView(selectedDate: $selectedDate)
                        case .month:
                            MonthPickerView(selectedDate: $selectedDate)
                        case .week:
                            WeekPickerView(selectedDate: $selectedDate)
                        }
                    }
                    
                    Text("Due: \(calculateDueDate().formatted(date: .abbreviated, time: .omitted))")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                
                if editingGoal != nil {
                    Section {
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            HStack {
                                Spacer()
                                Text("Delete Goal")
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(editingGoal != nil ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveGoal()
                    }
                    .disabled(title.isEmpty || selectedCategoryId == nil)
                }
            }
            .alert("Delete Goal", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteGoal()
                }
            } message: {
                Text("Are you sure you want to delete '\(title)'? This action cannot be undone.")
            }
        }
        .onAppear {
            populateForm()
        }
    }
    
    
    private func formatSelectedDate() -> String {
        let formatter = DateFormatter()
        switch selectedTimeframe {
        case .week:
            formatter.dateFormat = "MMM d yyyy"
            return "Week of \(formatter.string(from: selectedDate))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: selectedDate)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: selectedDate)
        }
    }
    
    private func calculateDueDate() -> Date {
        let calendar = Calendar.current
        
        switch selectedTimeframe {
        case .week:
            // End of the selected week (Sunday)
            let weekday = calendar.component(.weekday, from: selectedDate)
            let daysUntilSunday = (7 - weekday + 1) % 7
            return calendar.date(byAdding: .day, value: daysUntilSunday, to: selectedDate) ?? selectedDate
            
        case .month:
            // End of the selected month
            if let endOfMonth = calendar.dateInterval(of: .month, for: selectedDate)?.end {
                return calendar.date(byAdding: .day, value: -1, to: endOfMonth) ?? selectedDate
            }
            return selectedDate
            
        case .year:
            // End of the selected year
            if let endOfYear = calendar.dateInterval(of: .year, for: selectedDate)?.end {
                return calendar.date(byAdding: .day, value: -1, to: endOfYear) ?? selectedDate
            }
            return selectedDate
        }
    }
    
    private func populateForm() {
        if let goal = editingGoal {
            title = goal.title
            selectedCategoryId = goal.categoryId
            selectedTimeframe = goal.targetTimeframe
            selectedDate = goal.dueDate
        } else {
            // Set defaults for new goals
            selectedCategoryId = goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition }).first?.id
            selectedTimeframe = .year
            selectedDate = Date()
        }
    }
    
    private func saveGoal() {
        guard let categoryId = selectedCategoryId else { return }
        
        if let existingGoal = editingGoal {
            // Update existing goal
            var updatedGoal = existingGoal
            updatedGoal.title = title
            updatedGoal.categoryId = categoryId
            updatedGoal.targetTimeframe = selectedTimeframe
            updatedGoal.dueDate = calculateDueDate()
            updatedGoal.updatedAt = Date()
            
            goalsManager.updateGoal(updatedGoal)
        } else {
            // Create new goal
            let newGoal = GoalData(
                title: title,
                description: "",
                successMetric: "",
                categoryId: categoryId,
                targetTimeframe: selectedTimeframe,
                dueDate: calculateDueDate()
            )
            
            goalsManager.addGoal(newGoal)
        }
        
        onDismiss()
        dismiss()
    }
    
    private func deleteGoal() {
        if let goal = editingGoal {
            goalsManager.deleteGoal(goal.id)
        }
        onDismiss()
        dismiss()
    }
}

// MARK: - Create Category View
struct CreateCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var goalsManager = GoalsManager.shared
    
    @State private var title = ""
    @State private var selectedPosition = 0
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category Details") {
                    TextField("Category name", text: $title)
                }
                
                Section("Position") {
                    Picker("Position in grid", selection: $selectedPosition) {
                        ForEach(0..<6, id: \.self) { position in
                            let row = position / 2
                            let col = position % 2
                            Text("Row \(row + 1), Column \(col + 1)").tag(position)
                        }
                    }
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCategory()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    private func saveCategory() {
        goalsManager.addCategory(title: title, displayPosition: selectedPosition)
        dismiss()
    }
}

// MARK: - Custom Picker Views

struct YearPickerView: View {
    @Binding var selectedDate: Date
    
    private var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 10))
    }
    
    var body: some View {
        VStack {
            Text("Select Year")
                .font(.headline)
                .padding()
            
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
                            .tag(year)
                    }
                }
            .pickerStyle(.wheel)
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
        HStack(spacing: 20) {
            VStack {
                Text("Year")
                    .font(.headline)
                    .padding(.bottom, 8)
                
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
                            .tag(year)
                    }
                }
                .pickerStyle(.wheel)
            }
            
            VStack {
                Text("Month")
                    .font(.headline)
                    .padding(.bottom, 8)
                
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
                            .tag(month)
                    }
                }
                .pickerStyle(.wheel)
            }
        }
        .padding()
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
        HStack(spacing: 20) {
            VStack {
                Text("Year")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                Picker("Year", selection: $selectedYear) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year))
                            .tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .onChange(of: selectedYear) { _ in
                    updateSelectedDate()
                }
            }
            
            VStack {
                Text("Week")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                Picker("Week", selection: $selectedWeek) {
                    ForEach(weeks, id: \.weekNumber) { week in
                        let weekText = "WK\(week.weekNumber): \(formatWeekRange(week.startDate, week.endDate))"
                        Text(weekText)
                            .tag(week.weekNumber)
                    }
                }
                .pickerStyle(.wheel)
                .onChange(of: selectedWeek) { _ in
                    updateSelectedDate()
                }
            }
        }
        .padding()
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

// MARK: - Preview
#Preview {
    GoalsView()
}
