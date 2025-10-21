import SwiftUI

struct AllGoalsTableContent: View {
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // State for sheet presentations
    @State private var selectedGoal: GoalData?
    @State private var showingGoalDetail = false
    @State private var showingEditGoal = false
    @State private var goalToEdit: GoalData?
    @State private var categoryToEdit: GoalCategoryData?
    @State private var showingEditCategory = false
    
    // Computed property to get all timeframes with oldest first (leftmost)
    private var timeframes: [TimeframeGroup] {
        let allGoals = goalsManager.goals
        var timeframeSet = Set<TimeframeGroup>()
        
        for goal in allGoals {
            let group = TimeframeGroup(from: goal)
            timeframeSet.insert(group)
        }
        
        // Sort in ascending order (oldest first/leftmost, newest last/rightmost)
        return timeframeSet.sorted(by: { $0 < $1 })
    }
    
    // Computed property to get all categories
    private var categories: [GoalCategoryData] {
        goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition })
    }
    
    // MARK: - Adaptive Layout Properties
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    private var isLandscape: Bool {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return false
        }
        return window.bounds.width > window.bounds.height
    }
    
    // Number of visible columns based on device
    private var visibleColumns: Int {
        if isCompact {
            // iPhone or smaller
            return 2
        } else {
            // iPad
            return isLandscape ? 5 : 3
        }
    }
    
    // Column width based on visible columns
    private func columnWidth(for availableWidth: CGFloat) -> CGFloat {
        let spacing: CGFloat = 16
        let totalSpacing = spacing * CGFloat(visibleColumns + 1)
        return (availableWidth - totalSpacing) / CGFloat(visibleColumns)
    }
    
    // Adaptive padding
    private var adaptivePadding: CGFloat {
        isCompact ? 12 : 16
    }
    
    // Adaptive spacing
    private var adaptiveSpacing: CGFloat {
        isCompact ? 8 : 12
    }
    
    var body: some View {
        GeometryReader { geometry in
            let colWidth = columnWidth(for: geometry.size.width)
            
            if timeframes.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "target")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No Goals Yet")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Create your first goal to get started")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(timeframes) { timeframe in
                            TimeframeColumnView(
                                timeframe: timeframe,
                                categories: categories,
                                columnWidth: colWidth,
                                adaptivePadding: adaptivePadding,
                                adaptiveSpacing: adaptiveSpacing,
                                isCompact: isCompact,
                                onGoalTap: { goal in
                                    selectedGoal = goal
                                    showingGoalDetail = true
                                },
                                onGoalEdit: { goal in
                                    goalToEdit = goal
                                    showingEditGoal = true
                                },
                                onGoalDelete: { goal in
                                    goalsManager.deleteGoal(goal.id)
                                },
                                onCategoryEdit: { category in
                                    categoryToEdit = category
                                    showingEditCategory = true
                                },
                                onCategoryDelete: { category in
                                    goalsManager.deleteCategory(category.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .sheet(isPresented: $showingGoalDetail) {
            if let goal = selectedGoal {
                GoalDetailSheet(goal: goal)
            }
        }
        .sheet(isPresented: $showingEditGoal) {
            if let goal = goalToEdit {
                EditGoalView(goal: goal)
            }
        }
        .sheet(isPresented: $showingEditCategory) {
            if let category = categoryToEdit {
                EditCategoryView(category: category)
            }
        }
    }
    
    private func getGoals(for categoryId: UUID, in timeframe: TimeframeGroup) -> [GoalData] {
        let categoryGoals = goalsManager.getGoalsForCategory(categoryId)
        return categoryGoals.filter { goal in
            TimeframeGroup(from: goal) == timeframe
        }
    }
}

// MARK: - Timeframe Column View
struct TimeframeColumnView: View {
    let timeframe: TimeframeGroup
    let categories: [GoalCategoryData]
    let columnWidth: CGFloat
    let adaptivePadding: CGFloat
    let adaptiveSpacing: CGFloat
    let isCompact: Bool
    let onGoalTap: (GoalData) -> Void
    let onGoalEdit: (GoalData) -> Void
    let onGoalDelete: (GoalData) -> Void
    let onCategoryEdit: (GoalCategoryData) -> Void
    let onCategoryDelete: (GoalCategoryData) -> Void
    
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @State private var isExpanded: Bool = true
    
    private var isCurrent: Bool {
        timeframe.type == .week && isCurrentWeek(timeframe)
    }
    
    private var isPast: Bool {
        let now = Date()
        return timeframe.endDate < now
    }
    
    private var allGoalsInTimeframe: [GoalData] {
        goalsManager.goals.filter { goal in
            TimeframeGroup(from: goal) == timeframe
        }
    }
    
    private var completionStats: (completed: Int, total: Int) {
        let completed = allGoalsInTimeframe.filter { $0.isCompleted }.count
        return (completed, allGoalsInTimeframe.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: adaptiveSpacing) {
            if isExpanded {
                // Expanded view - full width with all content
                // Date range header with collapse button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text(timeframe.displayName)
                            .font(isCompact ? .headline : .title3)
                            .fontWeight(.bold)
                            .foregroundColor(isCurrent ? .white : .primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.left")
                            .font(isCompact ? .body : .title3)
                            .foregroundColor(isCurrent ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(adaptivePadding)
                    .background(isCurrent ? Color.blue : Color(.systemGray6))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                // Summary card - show for all timeframes
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(isCompact ? .body : .title3)
                    
                    Text("\(completionStats.completed)")
                        .font(isCompact ? .body : .title3)
                        .fontWeight(.medium)
                    
                    Text("/")
                        .font(isCompact ? .body : .title3)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                        .font(isCompact ? .body : .title3)
                    
                    Text("\(completionStats.total)")
                        .font(isCompact ? .body : .title3)
                        .fontWeight(.medium)
                }
                .padding(adaptivePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                
                // Category cards - fixed height for uniformity
                ForEach(categories) { category in
                    let goalsForCategory = getGoals(for: category.id, in: timeframe)
                    
                    GoalCategoryCard(
                        category: category,
                        goals: goalsForCategory,
                        onGoalTap: onGoalTap,
                        onGoalEdit: onGoalEdit,
                        onGoalDelete: onGoalDelete,
                        onCategoryEdit: onCategoryEdit,
                        onCategoryDelete: onCategoryDelete,
                        showTags: false,
                        currentInterval: navigationManager.currentInterval,
                        currentDate: navigationManager.currentDate
                    )
                    .frame(height: calculateCardHeight())
                }
            } else {
                // Collapsed view - narrow column with vertical text
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.body)
                            .foregroundColor(isCurrent ? .white : .primary)
                        
                        Text(timeframe.displayName)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(isCurrent ? .white : .primary)
                            .rotationEffect(.degrees(-90))
                            .fixedSize()
                            .frame(width: 20)
                    }
                    .padding(.vertical, adaptivePadding)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .background(isCurrent ? Color.blue : Color(.systemGray6))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: isExpanded ? columnWidth : 50)
    }
    
    // Calculate fixed card height based on 3 goal lines - optimized to fit 6 cards on screen
    private func calculateCardHeight() -> CGFloat {
        // Compact header height (category title, progress, etc)
        let headerHeight: CGFloat = isCompact ? 45 : 50
        
        // Space for 3 goal lines (checkbox + text) - very compact
        // Each goal row is ~26-28pt (icon + text + minimal padding)
        let goalRowHeight: CGFloat = isCompact ? 24 : 26
        let numberOfRows: CGFloat = 3
        let goalsAreaHeight = goalRowHeight * numberOfRows
        
        // Minimal bottom padding
        let bottomPadding: CGFloat = 8
        
        return headerHeight + goalsAreaHeight + bottomPadding
    }
    
    private func getGoals(for categoryId: UUID, in timeframe: TimeframeGroup) -> [GoalData] {
        let categoryGoals = goalsManager.getGoalsForCategory(categoryId)
        return categoryGoals.filter { goal in
            TimeframeGroup(from: goal) == timeframe
        }
    }
    
    private func isCurrentWeek(_ timeframe: TimeframeGroup) -> Bool {
        guard timeframe.type == .week else { return false }
        let calendar = Calendar.mondayFirst
        let now = Date()
        
        guard let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: now),
              let timeframeWeekStart = timeframe.weekStartDate else {
            return false
        }
        
        return currentWeekInterval.start == timeframeWeekStart
    }
}

// MARK: - Goal Detail Sheet
struct GoalDetailSheet: View {
    let goal: GoalData
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(goal.title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if !goal.description.isEmpty {
                    Text(goal.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
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

// MARK: - Edit Goal View
struct EditGoalView: View {
    let goal: GoalData
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    
    @State private var title: String
    @State private var description: String
    
    init(goal: GoalData) {
        self.goal = goal
        _title = State(initialValue: goal.title)
        _description = State(initialValue: goal.description)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Title") {
                    TextField("Title", text: $title)
                }
                
                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updatedGoal = goal
                        updatedGoal.title = title
                        updatedGoal.description = description
                        goalsManager.updateGoal(updatedGoal)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Category View
struct EditCategoryView: View {
    let category: GoalCategoryData
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var goalsManager = GoalsManager.shared
    
    @State private var title: String
    
    init(category: GoalCategoryData) {
        self.category = category
        _title = State(initialValue: category.title)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category Name") {
                    TextField("Name", text: $title)
                }
            }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updatedCategory = category
                        updatedCategory.title = title
                        goalsManager.updateCategory(updatedCategory)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: - Timeframe Group
struct TimeframeGroup: Identifiable, Hashable, Comparable {
    let id = UUID()
    let type: GoalTimeframe
    let year: Int
    let month: Int? // For month timeframe
    let weekOfYear: Int? // For week timeframe
    let weekStartDate: Date? // For week timeframe display
    let endDate: Date // End date of the timeframe for sorting
    
    var displayName: String {
        switch type {
        case .year:
            return "Year \(year)"
        case .month:
            if let month = month {
                let monthName = DateFormatter().monthSymbols[month - 1]
                return "\(monthName) \(year)"
            }
            return "Year \(year)"
        case .week:
            if let weekOfYear = weekOfYear, let startDate = weekStartDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "M/d"
                let endDate = Calendar.mondayFirst.date(byAdding: .day, value: 6, to: startDate) ?? startDate
                let startString = formatter.string(from: startDate)
                let endString = formatter.string(from: endDate)
                return "Week \(weekOfYear): \(startString) - \(endString)"
            }
            return "Week"
        }
    }
    
    init(from goal: GoalData) {
        self.type = goal.targetTimeframe
        let calendar = Calendar.mondayFirst
        self.year = calendar.component(.year, from: goal.dueDate)
        
        // Calculate the end date based on timeframe type
        switch goal.targetTimeframe {
        case .year:
            self.month = nil
            self.weekOfYear = nil
            self.weekStartDate = nil
            // End of year: December 31
            if let yearInterval = calendar.dateInterval(of: .year, for: goal.dueDate) {
                self.endDate = calendar.date(byAdding: .second, value: -1, to: yearInterval.end) ?? goal.dueDate
            } else {
                self.endDate = goal.dueDate
            }
        case .month:
            self.month = calendar.component(.month, from: goal.dueDate)
            self.weekOfYear = nil
            self.weekStartDate = nil
            // End of month: last day of the month
            if let monthInterval = calendar.dateInterval(of: .month, for: goal.dueDate) {
                self.endDate = calendar.date(byAdding: .second, value: -1, to: monthInterval.end) ?? goal.dueDate
            } else {
                self.endDate = goal.dueDate
            }
        case .week:
            self.month = nil
            self.weekOfYear = calendar.component(.weekOfYear, from: goal.dueDate)
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: goal.dueDate) {
                self.weekStartDate = weekInterval.start
                // End of week: last day of the week (Sunday)
                self.endDate = calendar.date(byAdding: .second, value: -1, to: weekInterval.end) ?? goal.dueDate
            } else {
                self.weekStartDate = nil
                self.endDate = goal.dueDate
            }
        }
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(year)
        hasher.combine(month)
        hasher.combine(weekOfYear)
    }
    
    static func == (lhs: TimeframeGroup, rhs: TimeframeGroup) -> Bool {
        lhs.type == rhs.type &&
        lhs.year == rhs.year &&
        lhs.month == rhs.month &&
        lhs.weekOfYear == rhs.weekOfYear
    }
    
    // Comparable conformance (sort by end date)
    static func < (lhs: TimeframeGroup, rhs: TimeframeGroup) -> Bool {
        // Sort by end date: earlier end dates come first
        return lhs.endDate < rhs.endDate
    }
}

extension GoalTimeframe {
    var sortOrder: Int {
        switch self {
        case .year: return 0
        case .month: return 1
        case .week: return 2
        }
    }
}

#Preview {
    AllGoalsTableContent()
}
