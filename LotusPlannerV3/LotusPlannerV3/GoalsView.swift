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
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var appPrefs = AppPreferences.shared

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

    // Helper to get task from linked task data
    private func getTask(from linkedTask: LinkedTaskData) -> GoogleTask? {
        let tasksDict = linkedTask.accountKindEnum == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
        return tasksDict[linkedTask.listId]?.first(where: { $0.id == linkedTask.taskId })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Checkbox (larger tap target) - aligned to top
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

                // Linked tasks section
                if !goal.linkedTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(goal.linkedTasks, id: \.taskId) { linkedTask in
                            if let task = getTask(from: linkedTask) {
                                HStack(spacing: 6) {
                                    Image(systemName: task.status == "completed" ? "checkmark.circle.fill" : "circle")
                                        .font(.caption2)
                                        .foregroundColor(task.status == "completed" ? .green : .secondary)
                                    Text(task.title)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .strikethrough(task.status == "completed")
                                        .lineLimit(1)
                                }
                                .padding(.leading, 4)
                            }
                        }
                    }
                    .padding(.top, 4)
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

// MARK: - Create Goal View (3-Step Flow)
struct CreateGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared

    let editingGoal: GoalData?
    let onDismiss: () -> Void
    let defaultTimeframe: TimelineInterval?
    let defaultDate: Date?

    // Step tracking
    @State private var currentStep = 1
    private let totalSteps = 3

    // Step 1: Define the Goal
    @State private var title = ""
    @State private var selectedCategoryId: UUID?
    @State private var selectedTimeframe: GoalTimeframe = .year
    @State private var selectedDate = Date()
    @State private var notes = ""

    // Step 2: Break Down into Tasks
    @State private var taskItems: [PendingTask] = []

    // Editing
    @State private var showingDeleteAlert = false

    struct PendingTask: Identifiable {
        let id = UUID()
        var title: String
        var dueDate: Date
        var accountKind: GoogleAuthManager.AccountKind = .personal
        var listId: String = ""
        var existingTaskId: String? = nil // Non-nil if this is an already-created task
    }

    init(editingGoal: GoalData? = nil, defaultTimeframe: TimelineInterval? = nil, defaultDate: Date? = nil, onDismiss: @escaping () -> Void = {}) {
        self.editingGoal = editingGoal
        self.onDismiss = onDismiss
        self.defaultTimeframe = defaultTimeframe
        self.defaultDate = defaultDate
    }

    private var canProceedFromStep1: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCategoryId != nil
    }

    private var canSave: Bool {
        canProceedFromStep1
    }

    private var availableTaskLists: [(list: GoogleTaskList, kind: GoogleAuthManager.AccountKind)] {
        var result: [(GoogleTaskList, GoogleAuthManager.AccountKind)] = []
        for list in tasksVM.personalTaskLists {
            result.append((list, .personal))
        }
        for list in tasksVM.professionalTaskLists {
            result.append((list, .professional))
        }
        return result
    }

    private var defaultListId: String {
        tasksVM.personalTaskLists.first?.id ?? tasksVM.professionalTaskLists.first?.id ?? ""
    }

    private var defaultAccountKind: GoogleAuthManager.AccountKind {
        if !tasksVM.personalTaskLists.isEmpty { return .personal }
        return .professional
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step indicator
                HStack(spacing: 4) {
                    ForEach(1...totalSteps, id: \.self) { step in
                        Capsule()
                            .fill(step <= currentStep ? Color.accentColor : Color(.systemGray4))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Step content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch currentStep {
                        case 1: step1DefineGoal
                        case 2: step2BreakDown
                        case 3: step3Review
                        default: EmptyView()
                        }
                    }
                    .padding()
                }

                // Navigation
                stepNavigation
                    .padding()
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
            }
            .alert("Delete Goal", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Goal & Tasks", role: .destructive) { deleteGoal() }
            } message: {
                let taskCount = editingGoal?.linkedTasks.count ?? 0
                if taskCount > 0 {
                    Text("This will delete '\(title)' and its \(taskCount) linked task\(taskCount == 1 ? "" : "s") from Google Tasks. This action cannot be undone.")
                } else {
                    Text("Are you sure you want to delete '\(title)'? This action cannot be undone.")
                }
            }
        }
        .onAppear { populateForm() }
    }

    // MARK: - Step 1: Define the Goal

    private var step1DefineGoal: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Define Your Goal")
                .font(.title2)
                .fontWeight(.bold)

            Text("Be specific — a clear goal is actionable, measurable, and timebound.")
                .font(.callout)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Goal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("e.g. Run a 5K race by September", text: $title, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Picker("Category", selection: Binding(
                    get: { selectedCategoryId },
                    set: { selectedCategoryId = $0 }
                )) {
                    Text("Select a category").tag(nil as UUID?)
                    ForEach(goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition }), id: \.id) { category in
                        Text(category.title).tag(category.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Due Date")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach([GoalTimeframe.year, GoalTimeframe.month, GoalTimeframe.week], id: \.self) { timeframe in
                            Button {
                                selectedTimeframe = timeframe
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedTimeframe == timeframe ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(selectedTimeframe == timeframe ? .accentColor : .secondary)
                                    Text(timeframe.displayName)
                                        .fontWeight(selectedTimeframe == timeframe ? .semibold : .regular)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        switch selectedTimeframe {
                        case .year: YearPickerView(selectedDate: $selectedDate)
                        case .month: MonthPickerView(selectedDate: $selectedDate)
                        case .week: WeekPickerView(selectedDate: $selectedDate)
                        }
                        Text("Due: \(calculateDueDate().formatted(date: .abbreviated, time: .omitted))")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Motivation, context, or anything you want to remember")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Optional notes...", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            if editingGoal != nil {
                Button(action: { showingDeleteAlert = true }) {
                    HStack {
                        Spacer()
                        Text("Delete Goal")
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Step 2: Break Down into Tasks

    private var step2BreakDown: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Break It Down")
                .font(.title2)
                .fontWeight(.bold)

            Text("What tasks do you need to complete to achieve this goal? These will be created as Google Tasks you can schedule in your day views.")
                .font(.callout)
                .foregroundColor(.secondary)

            ForEach($taskItems) { $item in
                let isExisting = item.existingTaskId != nil
                if isExisting {
                    existingTaskRow(item)
                } else {
                    newTaskRow($item)
                }
            }

            Button {
                addTaskItem()
            } label: {
                Label("Add Task", systemImage: "plus.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            if taskItems.isEmpty {
                Text("You can skip this step and add tasks later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Task Row Helpers

    private func existingTaskRow(_ item: PendingTask) -> some View {
        let task = lookupTask(item)
        let isCompleted = task?.isCompleted ?? false
        let listName = listNameForTask(item)

        return HStack(spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? .green : .secondary)
                .font(.body)

            Text(item.title)
                .font(.body)
                .strikethrough(isCompleted)
                .foregroundColor(isCompleted ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            if !listName.isEmpty {
                Text(listName)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }

            Text(item.dueDate.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(item.dueDate < Date() && !isCompleted ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                .foregroundColor(item.dueDate < Date() && !isCompleted ? .red : .green)
                .cornerRadius(4)

            Button {
                taskItems.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func newTaskRow(_ item: Binding<PendingTask>) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                    .font(.body)
                TextField("Task name", text: item.title)
                    .textFieldStyle(.roundedBorder)
                Button {
                    taskItems.removeAll { $0.id == item.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                DatePicker("Due", selection: item.dueDate, in: ...calculateDueDate(), displayedComponents: .date)
                    .environment(\.calendar, Calendar.mondayFirst)
                    .font(.caption)

                if availableTaskLists.count > 1 {
                    Picker("List", selection: Binding(
                        get: { "\(item.wrappedValue.accountKind == .personal ? "p" : "w"):\(item.wrappedValue.listId)" },
                        set: { newValue in
                            let parts = newValue.split(separator: ":")
                            if parts.count == 2 {
                                item.wrappedValue.accountKind = parts[0] == "p" ? .personal : .professional
                                item.wrappedValue.listId = String(parts[1])
                            }
                        }
                    )) {
                        ForEach(availableTaskLists, id: \.list.id) { entry in
                            let prefix = entry.kind == .personal ? "Personal" : "Work"
                            Text("\(prefix): \(entry.list.title)")
                                .tag("\(entry.kind == .personal ? "p" : "w"):\(entry.list.id)")
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func lookupTask(_ item: PendingTask) -> GoogleTask? {
        guard let taskId = item.existingTaskId else { return nil }
        let tasksDict = item.accountKind == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
        return tasksDict[item.listId]?.first(where: { $0.id == taskId })
    }

    private func listNameForTask(_ item: PendingTask) -> String {
        let lists = item.accountKind == .personal ? tasksVM.personalTaskLists : tasksVM.professionalTaskLists
        return lists.first(where: { $0.id == item.listId })?.title ?? ""
    }

    // MARK: - Step 3: Review & Commit

    private var step3Review: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review & Commit")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                summaryRow(label: "Goal", value: title)

                if let catId = selectedCategoryId,
                   let cat = goalsManager.categories.first(where: { $0.id == catId }) {
                    summaryRow(label: "Category", value: cat.title)
                }

                summaryRow(label: "Due", value: calculateDueDate().formatted(date: .abbreviated, time: .omitted))

                if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summaryRow(label: "Notes", value: notes)
                }

                let filledTasks = taskItems.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if !filledTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tasks (\(filledTasks.count))")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        ForEach(filledTasks) { task in
                            HStack(spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(task.title)
                                    .font(.body)
                                Spacer()
                                Text(task.dueDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Step Navigation

    private var stepNavigation: some View {
        HStack {
            if currentStep > 1 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }

            Spacer()

            if currentStep < totalSteps {
                if currentStep == 2 {
                    Button("Skip") {
                        withAnimation { currentStep += 1 }
                    }
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)
                }

                Button {
                    withAnimation { currentStep += 1 }
                } label: {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .fontWeight(.semibold)
                }
                .disabled(currentStep == 1 && !canProceedFromStep1)
            } else {
                Button {
                    saveGoal()
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text(isSaving ? "Saving..." : (editingGoal != nil ? "Save Goal" : "Create Goal"))
                    }
                    .fontWeight(.bold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background((canSave && !isSaving) ? Color.accentColor : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(!canSave || isSaving)
            }
        }
    }

    // MARK: - Helpers

    private func addTaskItem() {
        let dueDate = calculateDueDate()
        taskItems.append(PendingTask(
            title: "",
            dueDate: dueDate,
            accountKind: defaultAccountKind,
            listId: defaultListId
        ))
    }

    private func calculateDueDate() -> Date {
        let calendar = Calendar.mondayFirst
        switch selectedTimeframe {
        case .week:
            // End of Monday-first week = Sunday
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) {
                return calendar.date(byAdding: .day, value: -1, to: weekInterval.end) ?? selectedDate
            }
            return selectedDate
        case .month:
            if let end = calendar.dateInterval(of: .month, for: selectedDate)?.end {
                return calendar.date(byAdding: .day, value: -1, to: end) ?? selectedDate
            }
            return selectedDate
        case .year:
            if let end = calendar.dateInterval(of: .year, for: selectedDate)?.end {
                return calendar.date(byAdding: .day, value: -1, to: end) ?? selectedDate
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
            notes = goal.extendedData?.notes ?? ""
            // Populate linked tasks as PendingTask items for editing
            for linked in goal.linkedTasks {
                let tasksDict = linked.accountKindEnum == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
                if let task = tasksDict[linked.listId]?.first(where: { $0.id == linked.taskId }) {
                    var dueDate = Date()
                    if let dueDateStr = task.due {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        if let parsed = formatter.date(from: dueDateStr) { dueDate = parsed }
                    }
                    taskItems.append(PendingTask(
                        title: task.title,
                        dueDate: dueDate,
                        accountKind: linked.accountKindEnum,
                        listId: linked.listId,
                        existingTaskId: linked.taskId
                    ))
                }
            }
        } else {
            selectedCategoryId = goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition }).first?.id

            if let defaultInterval = defaultTimeframe, let date = defaultDate {
                let calendar = Calendar.mondayFirst
                switch defaultInterval {
                case .day, .week:
                    selectedTimeframe = .week
                    if let i = calendar.dateInterval(of: .weekOfYear, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: i.end) ?? date
                    } else { selectedDate = date }
                case .month:
                    selectedTimeframe = .month
                    if let i = calendar.dateInterval(of: .month, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: i.end) ?? date
                    } else { selectedDate = date }
                case .year:
                    selectedTimeframe = .year
                    if let i = calendar.dateInterval(of: .year, for: date) {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: i.end) ?? date
                    } else { selectedDate = date }
                }
            } else {
                selectedTimeframe = .year
                selectedDate = Date()
            }
        }
    }

    @State private var isSaving = false

    private func saveGoal() {
        guard let categoryId = selectedCategoryId, !isSaving else { return }
        isSaving = true

        let extData = GoalExtendedData(
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let dueDate = calculateDueDate()
        let goalTitle = title
        // Separate existing tasks (already created) from new ones
        let filledTasks = taskItems.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let newTasks = filledTasks.filter { $0.existingTaskId == nil }
        let existingTasks = filledTasks.filter { $0.existingTaskId != nil }
        let defListId = defaultListId

        Task {
            // Keep existing linked tasks
            var linkedTasks: [LinkedTaskData] = existingTasks.map { item in
                LinkedTaskData(
                    taskId: item.existingTaskId!,
                    listId: item.listId,
                    accountKind: item.accountKind
                )
            }

            // Create only new tasks
            for item in newTasks {
                let listId = item.listId.isEmpty ? defListId : item.listId
                let kind = item.accountKind

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let dueDateStr = formatter.string(from: item.dueDate)

                let tempTask = GoogleTask(
                    id: UUID().uuidString,
                    title: item.title,
                    notes: "Goal: \(goalTitle)",
                    status: "needsAction",
                    due: dueDateStr
                )

                do {
                    let createdTask = try await tasksVM.createTaskOnServer(tempTask, in: listId, for: kind)
                    await MainActor.run {
                        switch kind {
                        case .personal:
                            if tasksVM.personalTasks[listId] != nil {
                                tasksVM.personalTasks[listId]?.append(createdTask)
                            } else {
                                tasksVM.personalTasks[listId] = [createdTask]
                            }
                        case .professional:
                            if tasksVM.professionalTasks[listId] != nil {
                                tasksVM.professionalTasks[listId]?.append(createdTask)
                            } else {
                                tasksVM.professionalTasks[listId] = [createdTask]
                            }
                        }
                    }
                    linkedTasks.append(LinkedTaskData(
                        taskId: createdTask.id,
                        listId: listId,
                        accountKind: kind
                    ))
                } catch {
                    devLog("Failed to create task '\(item.title)': \(error)", level: .error, category: .tasks)
                }
            }

            await MainActor.run {
                if let existingGoal = editingGoal {
                    var updatedGoal = existingGoal
                    updatedGoal.title = title
                    updatedGoal.categoryId = categoryId
                    updatedGoal.targetTimeframe = selectedTimeframe
                    updatedGoal.dueDate = dueDate
                    updatedGoal.updatedAt = Date()
                    updatedGoal.extendedData = extData
                    updatedGoal.linkedTasks = linkedTasks
                    goalsManager.updateGoal(updatedGoal)
                } else {
                    devLog("Creating goal '\(title)' with \(linkedTasks.count) linked tasks: \(linkedTasks.map { $0.taskId })", level: .info, category: .goals)
                    let newGoal = GoalData(
                        title: title,
                        categoryId: categoryId,
                        targetTimeframe: selectedTimeframe,
                        dueDate: dueDate,
                        linkedTasks: linkedTasks,
                        extendedData: extData
                    )
                    goalsManager.addGoal(newGoal)
                }

                onDismiss()
                dismiss()
            }
        }
    }

    private func deleteGoal() {
        if let goal = editingGoal {
            // Delete linked Google Tasks
            for linked in goal.linkedTasks {
                let tasksDict = linked.accountKindEnum == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
                if let task = tasksDict[linked.listId]?.first(where: { $0.id == linked.taskId }) {
                    Task {
                        await tasksVM.deleteTask(task, from: linked.listId, for: linked.accountKindEnum)
                    }
                }
            }
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

// MARK: - Goal Detail Sheet
struct GoalDetailSheet: View {
    let goal: GoalData
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var tasksVM = DataManager.shared.tasksViewModel

    private var category: GoalCategoryData? {
        goalsManager.getCategoryById(goal.categoryId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Goal")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(goal.title)
                            .font(.title3)
                            .fontWeight(.bold)
                    }

                    // Category, Due, Status
                    HStack(spacing: 12) {
                        if let cat = category {
                            tagChip(cat.title, color: .blue)
                        }
                        tagChip(goal.dueDate.formatted(date: .abbreviated, time: .omitted),
                                color: goal.isOverdue ? .red : .green)
                        tagChip(goal.isCompleted ? "Done" : "In Progress",
                                color: goal.isCompleted ? .green : .orange)
                    }

                    // Notes
                    if let ext = goal.extendedData, !ext.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(ext.notes)
                                .font(.body)
                        }
                    }

                    // Linked Tasks
                    if !goal.linkedTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tasks")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            ForEach(goal.linkedTasks, id: \.taskId) { linked in
                                let tasksDict = linked.accountKindEnum == .personal ? tasksVM.personalTasks : tasksVM.professionalTasks
                                if let task = tasksDict[linked.listId]?.first(where: { $0.id == linked.taskId }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(task.isCompleted ? .green : .secondary)
                                            .font(.body)
                                        Text(task.title)
                                            .font(.body)
                                            .strikethrough(task.isCompleted)
                                        Spacer()
                                        if let due = task.due {
                                            Text(due.prefix(10))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Goal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func tagChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
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
