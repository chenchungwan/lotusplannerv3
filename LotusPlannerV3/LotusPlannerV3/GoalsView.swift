import SwiftUI

struct GoalsView: View {
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @State private var showingCreateGoal = false
    @State private var showingCreateCategory = false
    @State private var goalToEdit: GoalData?
    @State private var selectedGoal: GoalData?
    
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
            
            // Main Content
            if navigationManager.currentInterval == .day {
                AllGoalsTableContent()
            } else if appPrefs.useGoalCardView {
                // Individual Goal Card Grid View
                GoalCardGridView(
                    sortedCategories: sortedCategories,
                    getFilteredGoals: getFilteredGoalsForCategory,
                    onGoalTap: { goal in
                        selectedGoal = goal
                    },
                    onGoalEdit: { goal in
                        goalToEdit = goal
                    },
                    currentInterval: navigationManager.currentInterval,
                    currentDate: navigationManager.currentDate
                )
            } else {
                // Category Cards Grid View
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
        // Use `.sheet(item:)` here instead of the (isPresented:, state:) pair:
        // on Mac Catalyst the two separate state flips race and the sheet
        // builder was running with `selectedGoal == nil`, crashing the app.
        .sheet(item: $selectedGoal) { goal in
            GoalDetailSheet(goal: goal)
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
        .onReceive(NotificationCenter.default.publisher(for: .showAddGoal)) { _ in
            showingCreateGoal = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddCategory)) { _ in
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

// MARK: - Preview
#Preview {
    GoalsView()
}
