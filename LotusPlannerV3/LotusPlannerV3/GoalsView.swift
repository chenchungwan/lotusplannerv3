import SwiftUI

struct GoalsView: View {
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @State private var showingCreateCategory = false
    @State private var goalToEdit: GoalData?
    @State private var selectedGoal: GoalData?
    
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
            } else {
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
            }
        }
        // Use `.sheet(item:)` here instead of the (isPresented:, state:) pair:
        // on Mac Catalyst the two separate state flips race and the sheet
        // builder was running with `selectedGoal == nil`, crashing the app.
        .sheet(item: $selectedGoal) { goal in
            GoalDetailSheet(goal: goal)
        }
        .sheet(item: $goalToEdit) { goal in
            CreateGoalView(editingGoal: goal, onDismiss: {
                goalToEdit = nil
            })
        }
        // Goal creation lives in the shared `CreateItemSheet`, presented at
        // ContentView scope via `NavigationManager.activeSheet`.
        .sheet(isPresented: $showingCreateCategory) {
            CreateCategoryView()
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
        .onChange(of: navigationManager.currentDate) {
            // Refresh goals when date changes
            goalsManager.refreshData()
        }
        .onChange(of: navigationManager.currentInterval) {
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
