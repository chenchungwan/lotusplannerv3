import SwiftUI

struct AllGoalsTableContent: View {
    @ObservedObject private var goalsManager = GoalsManager.shared
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // Computed property to get all timeframes with oldest first (leftmost)
    private var timeframes: [TimeframeGroup] {
        let allGoals = goalsManager.goals
        var timeframeSet = Set<TimeframeGroup>()
        
        for goal in allGoals {
            let group = TimeframeGroup(from: goal)
            timeframeSet.insert(group)
        }
        
        // Sort in ascending order (oldest first/leftmost, newest last/rightmost)
        // Example: 2025 → 2026, Week 1 → Week 2
        return timeframeSet.sorted(by: { $0 < $1 })
    }
    
    // Helper to check if timeframe is current week
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
    
    // Helper to check if timeframe is in the past
    private func isInPast(_ timeframe: TimeframeGroup) -> Bool {
        let now = Date()
        return timeframe.endDate < now
    }
    
    // Get all goals for a timeframe (across all categories)
    private func getAllGoals(in timeframe: TimeframeGroup) -> [GoalData] {
        return goalsManager.goals.filter { goal in
            TimeframeGroup(from: goal) == timeframe
        }
    }
    
    // Get completion stats for a timeframe
    private func getCompletionStats(for timeframe: TimeframeGroup) -> (completed: Int, total: Int) {
        let goals = getAllGoals(in: timeframe)
        let completed = goals.filter { $0.isCompleted }.count
        return (completed, goals.count)
    }
    
    // Computed property to get all categories
    private var categories: [GoalCategoryData] {
        goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition })
    }
    
    // MARK: - Adaptive Layout Properties
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    // Adaptive column width based on device
    private func adaptiveColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        if isCompact {
            // iPhone: narrower columns (120-150pt)
            return max(120, min(150, availableWidth / 2.5))
        } else {
            // iPad: wider columns (180-250pt)
            return max(180, min(250, availableWidth / 5))
        }
    }
    
    // Adaptive category column width
    private var adaptiveCategoryColumnWidth: CGFloat {
        isCompact ? 100 : 150
    }
    
    // Adaptive row height
    private func adaptiveRowHeight(for availableHeight: CGFloat) -> CGFloat {
        if isCompact {
            // iPhone: shorter rows (140-180pt)
            return max(140, min(180, availableHeight / 4))
        } else {
            // iPad: taller rows (180-220pt)
            return max(180, min(220, availableHeight / 6))
        }
    }
    
    // Adaptive header height
    private var adaptiveHeaderHeight: CGFloat {
        isCompact ? 50 : 60
    }
    
    // Adaptive font size
    private var adaptiveFont: Font {
        isCompact ? .caption : .body
    }
    
    private var adaptiveTitleFont: Font {
        isCompact ? .caption : .body
    }
    
    // Adaptive padding
    private var adaptivePadding: CGFloat {
        isCompact ? 6 : 8
    }
    
    // Adaptive spacing
    private var adaptiveSpacing: CGFloat {
        isCompact ? 3 : 4
    }
    
    var body: some View {
        GeometryReader { geometry in
            let columnWidth: CGFloat = adaptiveColumnWidth(for: geometry.size.width)
            let rowHeight: CGFloat = adaptiveRowHeight(for: geometry.size.height)
            let categoryColumnWidth: CGFloat = adaptiveCategoryColumnWidth
            
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row with timeframes
                    HStack(spacing: 0) {
                        // Category header cell
                        VStack(spacing: 0) {
                            Text("Category")
                                .font(adaptiveTitleFont)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, adaptivePadding)
                        }
                        .frame(width: categoryColumnWidth, height: adaptiveHeaderHeight, alignment: .leading)
                        .background(Color(.systemGray6))
                        .overlay(
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                        
                        // Timeframe headers
                        ForEach(timeframes) { timeframe in
                            let isCurrent = isCurrentWeek(timeframe)
                            VStack(spacing: 0) {
                                Text(timeframe.displayName)
                                    .font(adaptiveTitleFont)
                                    .fontWeight(.semibold)
                                    .foregroundColor(isCurrent ? .white : .primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, adaptivePadding)
                                    .frame(maxWidth: .infinity)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(width: columnWidth, height: adaptiveHeaderHeight, alignment: .center)
                            .background(isCurrent ? Color.blue : Color(.systemGray6))
                            .overlay(
                                Rectangle()
                                    .fill(Color(.systemGray4))
                                    .frame(width: 0.5),
                                alignment: .trailing
                            )
                        }
                    }
                    
                    Rectangle()
                        .fill(Color(.systemGray3))
                        .frame(height: 1)
                    
                    // Summary row (completion stats for past timeframes)
                    HStack(alignment: .top, spacing: 0) {
                        // Label cell
                        VStack(spacing: 0) {
                            Text("Summary")
                                .font(adaptiveTitleFont)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(.all, adaptivePadding)
                        }
                        .frame(width: categoryColumnWidth, alignment: .topLeading)
                        .background(Color(.systemGray6))
                        .overlay(
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                        
                        // Stats for each timeframe
                        ForEach(timeframes) { timeframe in
                            let isPast = isInPast(timeframe)
                            let isCurrent = isCurrentWeek(timeframe)
                            let stats = isPast ? getCompletionStats(for: timeframe) : nil
                            
                            VStack(spacing: adaptiveSpacing) {
                                if isPast, let stats = stats, stats.total > 0 {
                                    Text("\(stats.completed) / \(stats.total)")
                                        .font(adaptiveFont)
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                    
                                    Text("Goals Accomplished")
                                        .font(adaptiveFont)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                } else {
                                    Text("—")
                                        .font(adaptiveFont)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                            }
                            .padding(.all, adaptivePadding)
                            .frame(width: columnWidth, alignment: .topLeading)
                            .background(isCurrent ? Color.blue.opacity(0.05) : Color(.systemBackground))
                            .overlay(
                                Rectangle()
                                    .fill(Color(.systemGray4))
                                    .frame(width: 0.5),
                                alignment: .trailing
                            )
                        }
                    }
                    
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 0.5)
                    
                    // Category rows
                    ForEach(categories) { category in
                        HStack(alignment: .top, spacing: 0) {
                            // Category name cell
                            VStack(spacing: 0) {
                                Text(category.title)
                                    .font(adaptiveTitleFont)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(.all, adaptivePadding)
                            }
                            .frame(width: categoryColumnWidth, height: rowHeight, alignment: .topLeading)
                            .background(Color(.systemGray6))
                            .overlay(
                                Rectangle()
                                    .fill(Color(.systemGray4))
                                    .frame(width: 0.5),
                                alignment: .trailing
                            )
                            
                            // Goals for each timeframe
                            ForEach(timeframes) { timeframe in
                                let goalsForCell = getGoals(for: category.id, in: timeframe)
                                let isCurrent = isCurrentWeek(timeframe)
                                VStack(spacing: 0) {
                                    GoalsCellView(
                                        goals: goalsForCell,
                                        adaptiveFont: adaptiveFont,
                                        adaptivePadding: adaptivePadding,
                                        adaptiveSpacing: adaptiveSpacing
                                    )
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                .frame(width: columnWidth, height: rowHeight, alignment: .topLeading)
                                .background(isCurrent ? Color.blue.opacity(0.05) : Color(.systemBackground))
                                .overlay(
                                    Rectangle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 0.5),
                                    alignment: .trailing
                                )
                            }
                        }
                        .frame(minHeight: rowHeight)
                        
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(height: 0.5)
                    }
                }
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

// MARK: - Goals Cell View
struct GoalsCellView: View {
    let goals: [GoalData]
    let adaptiveFont: Font
    let adaptivePadding: CGFloat
    let adaptiveSpacing: CGFloat
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: adaptiveSpacing) {
                if goals.isEmpty {
                    Text("—")
                        .foregroundColor(.secondary)
                        .font(adaptiveFont)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(goals) { goal in
                        HStack(spacing: adaptiveSpacing + 2) {
                            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(adaptiveFont)
                                .foregroundColor(goal.isCompleted ? .green : .secondary)
                                .frame(minWidth: 20, minHeight: 20)
                            
                            Text(goal.title)
                                .font(adaptiveFont)
                                .fontWeight(.medium)
                                .strikethrough(goal.isCompleted)
                                .foregroundColor(goal.isCompleted ? .secondary : .primary)
                                .lineLimit(3)
                                .minimumScaleFactor(0.9)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(adaptivePadding)
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
        // This means Week 1 comes before Week 2, January before February, 2025 before 2026
        // And within the same period, Year 2025 comes last (after all months and weeks in 2025)
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

