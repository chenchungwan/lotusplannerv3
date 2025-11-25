import SwiftUI

struct GoalsView: View {
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @State private var showingCreateGoal = false
    @State private var showingCreateCategory = false
    @State private var goalToEdit: GoalData?
    @State private var selectedGoal: GoalData?
    @State private var showingGoalDetail = false
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // Computed properties for better performance
    private var sortedCategories: [GoalCategoryData] {
        goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition })
    }
    
    // Completion statistics for current timeframe
    private var completionStats: (completed: Int, total: Int) {
        let allGoals = goalsManager.goals.filter { goal in
            isGoalInCurrentTimeframe(goal)
        }
        let completed = allGoals.filter { $0.isCompleted }.count
        return (completed, allGoals.count)
    }
    
    // Adaptive column count based on device
    private var adaptiveColumns: [GridItem] {
        let columnCount: Int
        let spacing: CGFloat = adaptiveGridSpacing
        
        if horizontalSizeClass == .compact && verticalSizeClass == .regular {
            // iPhone portrait: 1 column
            columnCount = 1
        } else if horizontalSizeClass == .compact && verticalSizeClass == .compact {
            // iPhone landscape: 2 columns
            columnCount = 2
        } else {
            // iPad: 2-3 columns depending on width
            columnCount = 2
        }
        
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }
    
    private var adaptiveGridSpacing: CGFloat {
        if horizontalSizeClass == .compact && verticalSizeClass == .regular {
            return 12 // iPhone portrait: tighter spacing
        } else if horizontalSizeClass == .compact {
            return 12 // iPhone landscape: tighter spacing
        } else {
            return 16 // iPad: standard spacing
        }
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 12 : 16
    }
    
    private var adaptiveMinCardHeight: CGFloat {
        if horizontalSizeClass == .compact && verticalSizeClass == .regular {
            return 200 // iPhone portrait: taller cards for readability
        } else if horizontalSizeClass == .compact {
            return 150 // iPhone landscape: shorter cards
        } else {
            return 180 // iPad: medium height
        }
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
            
            // Summary Section (only for w, m, y views, not day view)
            if navigationManager.currentInterval != .day {
                GoalsSummaryView(
                    completed: completionStats.completed,
                    total: completionStats.total,
                    currentInterval: navigationManager.currentInterval,
                    currentDate: navigationManager.currentDate
                )
            }
            
            // Main Content - Show all goals table when in day interval, grid view otherwise
            if navigationManager.currentInterval == .day {
                // All Goals Table View
                AllGoalsTableContent()
            } else {
                // Normal Grid View with adaptive columns
                ScrollView {
                    LazyVGrid(
                        columns: adaptiveColumns,
                        spacing: adaptiveGridSpacing
                    ) {
                        ForEach(sortedCategories) { category in
                            GoalCategoryCard(
                                category: category,
                                goals: getFilteredGoalsForCategory(category.id),
                                onGoalTap: { goal in
                                    selectedGoal = goal
                                    showingGoalDetail = true
                                },
                                onGoalEdit: { goal in
                                    goalToEdit = goal
                                },
                                onGoalDelete: { goal in
                                    goalsManager.deleteGoal(goal.id)
                                },
                                onCategoryEdit: { category in
                                    // Handle category edit
                                },
                                onCategoryDelete: { category in
                                    goalsManager.deleteCategory(category.id)
                                },
                                showTags: navigationManager.currentInterval == .day,
                                currentInterval: navigationManager.currentInterval,
                                currentDate: navigationManager.currentDate,
                                showQuickAdd: navigationManager.currentInterval != .day
                            )
                            .frame(minHeight: adaptiveMinCardHeight)
                        }
                        
                        // Add Category Card (only show if under max limit)
                        if goalsManager.canAddCategory {
                            AddCategoryCard(
                                onAddCategory: { categoryName in
                                    goalsManager.addCategory(title: categoryName)
                                }
                            )
                            .frame(minHeight: adaptiveMinCardHeight)
                        }
                    }
                    .padding(adaptivePadding)
                }
            }
        }
        .sheet(isPresented: $showingGoalDetail) {
            if let goal = selectedGoal {
                GoalDetailSheet(goal: goal)
            }
        }
        .sheet(item: $goalToEdit) { goal in
            CreateGoalView(editingGoal: goal) {
                goalToEdit = nil
            }
        }
        .sheet(isPresented: $showingCreateGoal) {
            CreateGoalView(
                editingGoal: nil,
                defaultTimeframe: navigationManager.currentInterval,
                defaultDate: navigationManager.currentDate
            ) {
                showingCreateGoal = false
            }
        }
        .sheet(isPresented: $showingCreateCategory) {
            CreateCategoryView()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAddGoal"))) { _ in
            showingCreateGoal = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAddCategory"))) { _ in
            showingCreateCategory = true
        }
        .onAppear {
            // Set default interval to week for goals view
            if navigationManager.currentInterval == .day {
                navigationManager.currentInterval = .week
            }
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
    private func isGoalInCurrentTimeframe(_ goal: GoalData) -> Bool {
        switch navigationManager.currentInterval {
        case .day:
            // For day view, show all goals (yearly view)
            return true
        case .week:
            return isGoalInWeek(goal, date: navigationManager.currentDate)
        case .month:
            return isGoalInMonth(goal, date: navigationManager.currentDate)
        case .year:
            return isGoalInYear(goal, date: navigationManager.currentDate)
        }
    }
    
    private func isGoalInWeek(_ goal: GoalData, date: Date) -> Bool {
        guard let weekInterval = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: date) else {
            return false
        }
        
        return goal.targetTimeframe == .week && 
               goal.dueDate >= weekInterval.start && 
               goal.dueDate < weekInterval.end
    }
    
    private func isGoalInMonth(_ goal: GoalData, date: Date) -> Bool {
        guard let monthInterval = Calendar.mondayFirst.dateInterval(of: .month, for: date) else {
            return false
        }
        
        return goal.targetTimeframe == .month && 
               goal.dueDate >= monthInterval.start && 
               goal.dueDate < monthInterval.end
    }
    
    private func isGoalInYear(_ goal: GoalData, date: Date) -> Bool {
        guard let yearInterval = Calendar.mondayFirst.dateInterval(of: .year, for: date) else {
            return false
        }
        
        return goal.targetTimeframe == .year && 
               goal.dueDate >= yearInterval.start && 
               goal.dueDate < yearInterval.end
    }
    
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
    let showTags: Bool
    let currentInterval: TimelineInterval
    let currentDate: Date
    let showQuickAdd: Bool
    
    @ObservedObject private var goalsManager = GoalsManager.shared
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var showingCopyAlert = false
    @State private var showingNoGoalsAlert = false
    @State private var isAddingQuickGoal = false
    @State private var newGoalTitle = ""
    @FocusState private var isQuickGoalFieldFocused: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 10 : 12
    }
    
    private var adaptiveSpacing: CGFloat {
        horizontalSizeClass == .compact ? 6 : 8
    }
    
    // Computed properties for better performance
    private var completedGoalsCount: Int {
        goals.filter { $0.isCompleted }.count
    }
    
    private var totalGoalsCount: Int {
        goals.count
    }
    
    // Check if we should show the repeat icon
    private var shouldShowRepeatIcon: Bool {
        // Only show in week, month, year views (not day view which is "All Goals")
        // Always show the icon to allow repeated copying from previous period
        return currentInterval != .day
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: adaptiveSpacing) {
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
                    Text("\(category.title) (\(totalGoalsCount))")
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
                
                // Repeat icon to copy goals from previous period
                if shouldShowRepeatIcon {
                    Button(action: {
                        showingCopyAlert = true
                    }) {
                        Image(systemName: "repeat")
                            .font(.body) // Larger for better tap target
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, adaptivePadding)
            .padding(.top, adaptivePadding)
            
            Divider()
            
            // Goals list
            ScrollView {
                LazyVStack(spacing: adaptiveSpacing) {
                    ForEach(goals) { goal in
                        GoalRow(
                            goal: goal,
                            onTap: { 
                                goalsManager.toggleGoalCompletion(goal.id)
                            },
                            onEdit: { onGoalEdit(goal) },
                            onDelete: { onGoalDelete(goal) },
                            showTags: showTags
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
                    
                    if showQuickAdd {
                        quickAddGoalRow
                    }
                }
                .padding(.horizontal, adaptivePadding / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .onChange(of: showQuickAdd) { value in
            if !value {
                cancelQuickGoalInline()
            }
        }
        .alert("Copy Goals from Previous Period?", isPresented: $showingCopyAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Copy", role: .none) {
                copyGoalsFromPreviousPeriod()
            }
        } message: {
            Text("This will copy all \(currentInterval.rawValue.lowercased()) goals from the previous \(currentInterval.rawValue.lowercased()) to this period. Your existing goals will be kept. Are you sure?")
        }
        .alert("No Goals to Copy", isPresented: $showingNoGoalsAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("There are no \(currentInterval.rawValue.lowercased()) goals in the previous period to copy.")
        }
    }
    
    @ViewBuilder
    private var quickAddGoalRow: some View {
        if isAddingQuickGoal {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                TextField("New goal", text: $newGoalTitle)
                    .font(.body)
                    .focused($isQuickGoalFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        createQuickGoalInline()
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            isQuickGoalFieldFocused = true
                        }
                    }
                
                Button {
                    cancelQuickGoalInline()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel quick goal")
            }
            .padding(adaptivePadding)
        } else {
            Button {
                isAddingQuickGoal = true
                newGoalTitle = ""
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    
                    Text("New goal")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(adaptivePadding)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add quick goal")
        }
    }
    
    private func cancelQuickGoalInline() {
        isAddingQuickGoal = false
        newGoalTitle = ""
        isQuickGoalFieldFocused = false
    }
    
    private func createQuickGoalInline() {
        let trimmed = newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelQuickGoalInline()
            return
        }
        
        let timeframe = convertToGoalTimeframe(currentInterval)
        let dueDate = quickGoalDueDate(for: timeframe)
        
        let newGoal = GoalData(
            title: trimmed,
            description: "",
            successMetric: "",
            categoryId: category.id,
            targetTimeframe: timeframe,
            dueDate: dueDate,
            isCompleted: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        goalsManager.addGoal(newGoal)
        cancelQuickGoalInline()
    }
    
    private func quickGoalDueDate(for timeframe: GoalTimeframe) -> Date {
        switch timeframe {
        case .week:
            return GoalData.calculateDueDate(for: .week, from: currentDate)
        case .month:
            return GoalData.calculateDueDate(for: .month, from: currentDate)
        case .year:
            return GoalData.calculateDueDate(for: .year, from: currentDate)
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
    
    private func copyGoalsFromPreviousPeriod() {
        let calendar = Calendar.mondayFirst
        
        // Calculate previous period based on current interval
        let previousPeriodStart: Date
        let previousPeriodEnd: Date
        
        switch currentInterval {
        case .week:
            // Get previous week
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: currentDate),
                  let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start),
                  let prevWeekInterval = calendar.dateInterval(of: .weekOfYear, for: prevWeekStart) else {
                return
            }
            previousPeriodStart = prevWeekInterval.start
            previousPeriodEnd = prevWeekInterval.end
            
        case .month:
            // Get previous month
            guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
                  let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: monthInterval.start),
                  let prevMonthInterval = calendar.dateInterval(of: .month, for: prevMonthStart) else {
                return
            }
            previousPeriodStart = prevMonthInterval.start
            previousPeriodEnd = prevMonthInterval.end
            
        case .year:
            // Get previous year
            guard let yearInterval = calendar.dateInterval(of: .year, for: currentDate),
                  let prevYearStart = calendar.date(byAdding: .year, value: -1, to: yearInterval.start),
                  let prevYearInterval = calendar.dateInterval(of: .year, for: prevYearStart) else {
                return
            }
            previousPeriodStart = prevYearInterval.start
            previousPeriodEnd = prevYearInterval.end
            
        case .day:
            return // Should not happen due to shouldShowRepeatIcon check
        }
        
        // Get all goals from previous period for this category with matching timeframe type
        let previousPeriodGoals = goalsManager.goals.filter { goal in
            goal.categoryId == category.id &&
            goal.targetTimeframe == convertToGoalTimeframe(currentInterval) &&
            goal.dueDate >= previousPeriodStart &&
            goal.dueDate < previousPeriodEnd
        }
        
        // Check if there are any goals to copy
        if previousPeriodGoals.isEmpty {
            // Show alert that no goals were found
            showingNoGoalsAlert = true
            return
        }
        
        // Calculate the new due date (shift by one period forward)
        let periodShift: DateComponents
        switch currentInterval {
        case .week:
            periodShift = DateComponents(weekOfYear: 1)
        case .month:
            periodShift = DateComponents(month: 1)
        case .year:
            periodShift = DateComponents(year: 1)
        case .day:
            return
        }
        
        // Copy each goal to the current period
        for oldGoal in previousPeriodGoals {
            guard let newDueDate = calendar.date(byAdding: periodShift, to: oldGoal.dueDate) else {
                continue
            }
            
            // Create new goal with same properties but new due date and not completed
            let newGoal = GoalData(
                id: UUID(),
                title: oldGoal.title,
                description: oldGoal.description,
                successMetric: oldGoal.successMetric,
                categoryId: oldGoal.categoryId,
                targetTimeframe: oldGoal.targetTimeframe,
                dueDate: newDueDate,
                isCompleted: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            goalsManager.addGoal(newGoal)
        }
        
        // Post notification to refresh All Goals view
        NotificationCenter.default.post(name: Notification.Name("RefreshAllGoalsView"), object: nil)
    }
    
    private func convertToGoalTimeframe(_ interval: TimelineInterval) -> GoalTimeframe {
        switch interval {
        case .week:
            return .week
        case .month:
            return .month
        case .year:
            return .year
        case .day:
            return .week // Fallback, shouldn't happen
        }
    }
}

// MARK: - Goal Row
struct GoalRow: View {
    let goal: GoalData
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let showTags: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 10 : 8
    }
    
    private var adaptiveVerticalPadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 4
    }
    
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
        HStack(spacing: 10) {
            // Checkbox (larger tap target)
            Button(action: onTap) {
                Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3) // Slightly larger for better tap target
                    .foregroundColor(goal.isCompleted ? .green : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            
            // Goal content
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(.body)
                    .strikethrough(goal.isCompleted)
                    .foregroundColor(goal.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                
                if showTags {
                    HStack(spacing: 4) {
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
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onEdit()
            }
            
            Spacer()
        }
        .padding(.horizontal, adaptivePadding)
        .padding(.vertical, adaptiveVerticalPadding)
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
    @ObservedObject private var goalsManager = GoalsManager.shared
    
    let editingGoal: GoalData?
    let onDismiss: () -> Void
    let defaultTimeframe: TimelineInterval?
    let defaultDate: Date?
    
    @State private var title = ""
    @State private var selectedCategoryId: UUID?
    @State private var selectedTimeframe: GoalTimeframe = .year
    @State private var selectedDate = Date()
    @State private var showingDeleteAlert = false
    
    // Track original values for change detection
    private let originalTitle: String
    private let originalCategoryId: UUID?
    private let originalTimeframe: GoalTimeframe
    private let originalDueDate: Date
    
    init(editingGoal: GoalData? = nil, defaultTimeframe: TimelineInterval? = nil, defaultDate: Date? = nil, onDismiss: @escaping () -> Void = {}) {
        self.editingGoal = editingGoal
        self.onDismiss = onDismiss
        self.defaultTimeframe = defaultTimeframe
        self.defaultDate = defaultDate
        
        // Store original values
        self.originalTitle = editingGoal?.title ?? ""
        self.originalCategoryId = editingGoal?.categoryId
        self.originalTimeframe = editingGoal?.targetTimeframe ?? .year
        self.originalDueDate = editingGoal?.dueDate ?? Date()
    }
    
    // Check if any changes have been made
    private var hasChanges: Bool {
        guard editingGoal != nil else { return false }
        
        return title != originalTitle ||
               selectedCategoryId != originalCategoryId ||
               selectedTimeframe != originalTimeframe ||
               !Calendar.current.isDate(calculateDueDate(), inSameDayAs: originalDueDate)
    }
    
    // Validate that required fields are filled
    private var canSave: Bool {
        return !title.isEmpty && selectedCategoryId != nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Add goal description", text: $title)
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
                    HStack(alignment: .top, spacing: 8) {
                        // First Column: Timeframe Selection with Radio Buttons
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Timeframe")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach([GoalTimeframe.year, GoalTimeframe.month, GoalTimeframe.week], id: \.self) { timeframe in
                                    Button(action: {
                                        selectedTimeframe = timeframe
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: selectedTimeframe == timeframe ? "largecircle.fill.circle" : "circle")
                                                .foregroundColor(selectedTimeframe == timeframe ? .accentColor : .secondary)
                                                .font(.title2)
                                            
                                            Text(timeframe.displayName)
                                                .font(.body)
                                                .fontWeight(selectedTimeframe == timeframe ? .semibold : .regular)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Second Column: Date Picker based on selected timeframe
                        VStack(alignment: .leading, spacing: 8) {
                            switch selectedTimeframe {
                            case .year:
                                YearPickerView(selectedDate: $selectedDate)
                            case .month:
                                MonthPickerView(selectedDate: $selectedDate)
                            case .week:
                                WeekPickerView(selectedDate: $selectedDate)
                            }
                            
                            Text("Due: \(calculateDueDate().formatted(date: .abbreviated, time: .omitted))")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
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
                    Button(editingGoal != nil ? "Save" : "Create") {
                        saveGoal()
                    }
                    .disabled(!canSave || (editingGoal != nil ? !hasChanges : false))
                    .fontWeight(.semibold)
                    .foregroundColor((canSave && (editingGoal == nil || hasChanges)) ? .accentColor : .secondary)
                    .opacity((canSave && (editingGoal == nil || hasChanges)) ? 1.0 : 0.5)
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
            
            // Use defaultTimeframe and defaultDate if provided
            if let defaultInterval = defaultTimeframe, let date = defaultDate {
                let calendar = Calendar.mondayFirst
                
                // Map TimelineInterval to GoalTimeframe and calculate end date
                switch defaultInterval {
                case .day:
                    // If "All Goals" view, default to weekly with current week
                    selectedTimeframe = .week
                    if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: weekInterval.end) ?? date
                    } else {
                        selectedDate = date
                    }
                case .week:
                    selectedTimeframe = .week
                    if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: weekInterval.end) ?? date
                    } else {
                        selectedDate = date
                    }
                case .month:
                    selectedTimeframe = .month
                    if let monthInterval = calendar.dateInterval(of: .month, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? date
                    } else {
                        selectedDate = date
                    }
                case .year:
                    selectedTimeframe = .year
                    if let yearInterval = calendar.dateInterval(of: .year, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: yearInterval.end) ?? date
                    } else {
                        selectedDate = date
                    }
                }
            } else {
                // Fallback to old defaults
                selectedTimeframe = .year
                selectedDate = Date()
            }
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
    @ObservedObject private var goalsManager = GoalsManager.shared
    
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
                .pickerStyle(.wheel)
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
                .pickerStyle(.wheel)
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
                .pickerStyle(.wheel)
                .onChange(of: selectedYear) { _ in
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
                .pickerStyle(.wheel)
                .onChange(of: selectedWeek) { _ in
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

// MARK: - Goal Detail Sheet
struct GoalDetailSheet: View {
    let goal: GoalData
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    
    private var category: GoalCategoryData? {
        goalsManager.getCategoryById(goal.categoryId)
    }
    
    private var dueDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(goal.title)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    // Description
                    if !goal.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(goal.description)
                                .font(.body)
                        }
                    }
                    
                    // Success Metric
                    if !goal.successMetric.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Success Metric")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(goal.successMetric)
                                .font(.body)
                        }
                    }
                    
                    // Category
                    if let category = category {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Category")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(category.title)
                                .font(.body)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Timeframe
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timeframe")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(goal.targetTimeframe.displayName)
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                    
                    // Due Date
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Due Date")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(dueDateFormatter.string(from: goal.dueDate))
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(goal.isCompleted ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    }
                    
                    // Status
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        HStack {
                            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(goal.isCompleted ? .green : .secondary)
                            Text(goal.isCompleted ? "Completed" : "In Progress")
                                .font(.body)
                                .fontWeight(goal.isCompleted ? .semibold : .regular)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(goal.isCompleted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Goal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Goals Summary View
struct GoalsSummaryView: View {
    let completed: Int
    let total: Int
    let currentInterval: TimelineInterval
    let currentDate: Date
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private var completionPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
    
    private var timeframeTitle: String {
        let formatter = DateFormatter()
        
        switch currentInterval {
        case .week:
            formatter.dateFormat = "MMM d"
            let startOfWeek = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: currentDate)?.start ?? currentDate
            let endOfWeek = Calendar.mondayFirst.date(byAdding: .day, value: 6, to: startOfWeek) ?? currentDate
            return "Week of \(formatter.string(from: startOfWeek)) - \(formatter.string(from: endOfWeek))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: currentDate)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: currentDate)
        case .day:
            return "All Goals"
        }
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 16 : 20
    }
    
    private var adaptiveSpacing: CGFloat {
        horizontalSizeClass == .compact ? 8 : 12
    }
    
    var body: some View {
        VStack(spacing: adaptiveSpacing) {
            // Timeframe title
            Text(timeframeTitle)
                .font(horizontalSizeClass == .compact ? .subheadline : .headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Progress bar and stats
            HStack(spacing: 12) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(height: horizontalSizeClass == .compact ? 12 : 16)
                        
                        // Progress fill
                        RoundedRectangle(cornerRadius: 8)
                            .fill(completionPercentage == 1.0 ? Color.green : Color.blue)
                            .frame(width: geometry.size.width * completionPercentage, height: horizontalSizeClass == .compact ? 12 : 16)
                            .animation(.easeInOut(duration: 0.3), value: completionPercentage)
                    }
                }
                .frame(height: horizontalSizeClass == .compact ? 12 : 16)
                
                // Stats text
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                    
                    Text("\(completed)")
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("/")
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("\(total)")
                        .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .frame(minWidth: horizontalSizeClass == .compact ? 60 : 80)
            }
            
            // Completion percentage
            if total > 0 {
                Text("\(Int(completionPercentage * 100))% Complete")
                    .font(horizontalSizeClass == .compact ? .caption : .subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, adaptivePadding)
        .padding(.vertical, horizontalSizeClass == .compact ? 12 : 16)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
}

// MARK: - Preview
#Preview {
    GoalsView()
}
