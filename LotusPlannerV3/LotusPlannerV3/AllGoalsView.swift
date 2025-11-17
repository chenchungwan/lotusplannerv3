import SwiftUI

struct AllGoalsTableContent: View {
    @ObservedObject private var goalsManager = GoalsManager.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // State for sheet presentations
    @State private var showingEditGoal = false
    @State private var goalToEdit: GoalData?
    @State private var categoryToEdit: GoalCategoryData?
    @State private var showingEditCategory = false
    @State private var refreshTrigger = UUID()
    
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
    
    // Find the current period's timeframe
    private var currentTimeframe: TimeframeGroup? {
        let now = Date()
        let calendar = Calendar.mondayFirst
        
        // Find the timeframe that contains the current date
        // Priority: current week > current month > current year > first non-past
        
        // First, try to find the current week
        if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) {
            let currentWeekStart = weekInterval.start
            let currentYear = calendar.component(.year, from: now)
            let currentWeekOfYear = calendar.component(.weekOfYear, from: now)
            
            if let found = timeframes.first(where: { timeframe in
                timeframe.type == .week &&
                timeframe.year == currentYear &&
                timeframe.weekOfYear == currentWeekOfYear &&
                timeframe.weekStartDate == currentWeekStart
            }) {
                return found
            }
        }
        
        // Then try to find the current month
        if let monthInterval = calendar.dateInterval(of: .month, for: now) {
            let currentYear = calendar.component(.year, from: now)
            let currentMonth = calendar.component(.month, from: now)
            
            if let found = timeframes.first(where: { timeframe in
                timeframe.type == .month &&
                timeframe.year == currentYear &&
                timeframe.month == currentMonth
            }) {
                return found
            }
        }
        
        // Then try to find the current year
        let currentYear = calendar.component(.year, from: now)
        if let found = timeframes.first(where: { timeframe in
            timeframe.type == .year &&
            timeframe.year == currentYear
        }) {
            return found
        }
        
        // If no exact match, find the first non-past timeframe (current or future)
        return timeframes.first(where: { $0.endDate >= now })
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
                ScrollViewReader { proxy in
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
                                        goalToEdit = goal
                                        showingEditGoal = true
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
                                .id(timeframe.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    }
                    .id(refreshTrigger) // Force refresh when trigger changes
                    .onAppear {
                        // Auto-scroll to current period's column on launch
                        // Use multiple attempts to ensure scroll happens after layout
                        scrollToCurrentTimeframe(proxy: proxy, delay: 0.1)
                        scrollToCurrentTimeframe(proxy: proxy, delay: 0.3)
                        scrollToCurrentTimeframe(proxy: proxy, delay: 0.5)
                    }
                    .onChange(of: refreshTrigger) { _ in
                        // Also scroll to current timeframe when view refreshes
                        scrollToCurrentTimeframe(proxy: proxy, delay: 0.1)
                        scrollToCurrentTimeframe(proxy: proxy, delay: 0.3)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditGoal) {
            if let goal = goalToEdit {
                CreateGoalView(editingGoal: goal) {
                    goalToEdit = nil
                    showingEditGoal = false
                }
            }
        }
        .sheet(isPresented: $showingEditCategory) {
            if let category = categoryToEdit {
                EditCategoryView(category: category)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshAllGoalsView"))) { _ in
            // Force refresh by updating the refresh trigger
            refreshTrigger = UUID()
        }
    }
    
    private func getGoals(for categoryId: UUID, in timeframe: TimeframeGroup) -> [GoalData] {
        let categoryGoals = goalsManager.getGoalsForCategory(categoryId)
        return categoryGoals.filter { goal in
            TimeframeGroup(from: goal) == timeframe
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    private func scrollToCurrentTimeframe(proxy: ScrollViewProxy, delay: Double = 0.2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let now = Date()
            // Find the first non-past timeframe (current or future)
            // This ensures we scroll past all collapsed past columns
            if let targetTimeframe = timeframes.first(where: { $0.endDate >= now }) {
                // Use stable ID that matches the view
                let targetId = targetTimeframe.id
                withAnimation(.easeInOut(duration: 0.6)) {
                    // Use .leading anchor to position target column at left edge,
                    // pushing all past collapsed columns off-screen to the left
                    proxy.scrollTo(targetId, anchor: .leading)
                }
            } else if let lastTimeframe = timeframes.last {
                // Fallback: if all are past, scroll to the most recent one
                let targetId = lastTimeframe.id
                withAnimation(.easeInOut(duration: 0.6)) {
                    proxy.scrollTo(targetId, anchor: .leading)
                }
            }
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
    
    init(timeframe: TimeframeGroup, categories: [GoalCategoryData], columnWidth: CGFloat, adaptivePadding: CGFloat, adaptiveSpacing: CGFloat, isCompact: Bool, onGoalTap: @escaping (GoalData) -> Void, onGoalEdit: @escaping (GoalData) -> Void, onGoalDelete: @escaping (GoalData) -> Void, onCategoryEdit: @escaping (GoalCategoryData) -> Void, onCategoryDelete: @escaping (GoalCategoryData) -> Void) {
        self.timeframe = timeframe
        self.categories = categories
        self.columnWidth = columnWidth
        self.adaptivePadding = adaptivePadding
        self.adaptiveSpacing = adaptiveSpacing
        self.isCompact = isCompact
        self.onGoalTap = onGoalTap
        self.onGoalEdit = onGoalEdit
        self.onGoalDelete = onGoalDelete
        self.onCategoryEdit = onCategoryEdit
        self.onCategoryDelete = onCategoryDelete
        
        // Auto-collapse past columns
        let now = Date()
        self._isExpanded = State(initialValue: timeframe.endDate >= now)
    }
    
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
                // Date range header with collapse button and summary
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        // First line: Date range name and chevron
                        HStack {
                            Text(timeframe.displayName)
                                .font(isCompact ? .subheadline : .body)
                                .fontWeight(.bold)
                                .foregroundColor(isCurrent ? .white : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.left")
                                .font(isCompact ? .caption : .body)
                                .foregroundColor(isCurrent ? .white : .primary)
                        }
                        
                        // Second line: Summary
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(isCurrent ? .white.opacity(0.9) : .green)
                                .font(isCompact ? .caption : .subheadline)
                            
                            Text("\(completionStats.completed)")
                                .font(isCompact ? .caption : .subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(isCurrent ? .white : .primary)
                            
                            Text("/")
                                .font(isCompact ? .caption : .subheadline)
                                .foregroundColor(isCurrent ? .white.opacity(0.7) : .secondary)
                            
                            Image(systemName: "circle")
                                .foregroundColor(isCurrent ? .white.opacity(0.7) : .secondary)
                                .font(isCompact ? .caption : .subheadline)
                            
                            Text("\(completionStats.total)")
                                .font(isCompact ? .caption : .subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(isCurrent ? .white : .primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(adaptivePadding)
                    .background(isCurrent ? Color.blue : Color(.systemGray6))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                // Category cards - scrollable area that takes remaining height
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: adaptiveSpacing) {
                        ForEach(categories) { category in
                            GoalCategoryCard(
                                category: category,
                                goals: getGoals(for: category.id, in: timeframe),
                                onGoalTap: onGoalTap,
                                onGoalEdit: onGoalEdit,
                                onGoalDelete: onGoalDelete,
                                onCategoryEdit: onCategoryEdit,
                                onCategoryDelete: onCategoryDelete,
                                showTags: false,
                                currentInterval: convertToTimelineInterval(timeframe.type),
                                currentDate: timeframe.startDate
                            )
                            .frame(height: calculateCardHeight())
                        }
                    }
                }
                .frame(maxHeight: .infinity)
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
                            .foregroundColor(isCurrent ? .white : (isPast ? .secondary : .primary))
                        
                        Text(timeframe.displayName)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(isCurrent ? .white : (isPast ? .secondary : .primary))
                            .rotationEffect(.degrees(-90))
                            .fixedSize()
                            .frame(width: 20)
                        
                        // Show past indicator
                        if isPast {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, adaptivePadding)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .background(isCurrent ? Color.blue : (isPast ? Color(.systemGray5) : Color(.systemGray6)))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: isExpanded ? columnWidth : 50)
    }
    
    // Calculate fixed card height based on 3 goal lines - expanded by 50%
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
        
        let baseHeight = headerHeight + goalsAreaHeight + bottomPadding
        return baseHeight * 1.8  // Expanded by 80% total (50% + 20%)
    }
    
    private func getGoals(for categoryId: UUID, in timeframe: TimeframeGroup) -> [GoalData] {
        let categoryGoals = goalsManager.getGoalsForCategory(categoryId)
        return categoryGoals.filter { goal in
            TimeframeGroup(from: goal) == timeframe
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
    
    private func convertToTimelineInterval(_ goalTimeframe: GoalTimeframe) -> TimelineInterval {
        switch goalTimeframe {
        case .week:
            return .week
        case .month:
            return .month
        case .year:
            return .year
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
    // Use a stable identifier based on timeframe properties
    var id: String {
        switch type {
        case .year:
            return "year_\(year)"
        case .month:
            return "month_\(year)_\(month ?? 0)"
        case .week:
            if let weekStart = weekStartDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return "week_\(formatter.string(from: weekStart))"
            }
            return "week_\(year)_\(weekOfYear ?? 0)"
        }
    }
    
    let type: GoalTimeframe
    let year: Int
    let month: Int? // For month timeframe
    let weekOfYear: Int? // For week timeframe
    let weekStartDate: Date? // For week timeframe display
    let endDate: Date // End date of the timeframe for sorting
    
    var startDate: Date {
        switch type {
        case .year:
            return Calendar.mondayFirst.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        case .month:
            if let month = month {
                return Calendar.mondayFirst.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
            }
            return Date()
        case .week:
            return weekStartDate ?? Date()
        }
    }
    
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
