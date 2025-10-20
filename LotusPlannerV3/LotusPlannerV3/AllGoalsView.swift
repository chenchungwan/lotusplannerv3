import SwiftUI

struct AllGoalsTableContent: View {
    @StateObject private var goalsManager = GoalsManager.shared
    
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
    
    // Computed property to get all categories
    private var categories: [GoalCategoryData] {
        goalsManager.categories.sorted(by: { $0.displayPosition < $1.displayPosition })
    }
    
    var body: some View {
        GeometryReader { geometry in
            let columnWidth: CGFloat = max(200, geometry.size.width / 5)
            let rowHeight: CGFloat = max(200, geometry.size.height / 6)
            let categoryColumnWidth: CGFloat = 150
            
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row with timeframes
                    HStack(spacing: 0) {
                        // Category header cell
                        VStack(spacing: 0) {
                            Text("Category")
                                .font(.body)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                        }
                        .frame(width: categoryColumnWidth, height: 60, alignment: .leading)
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
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(isCurrent ? .white : .primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity)
                            }
                            .frame(width: columnWidth, height: 60, alignment: .center)
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
                    
                    // Category rows
                    ForEach(categories) { category in
                        HStack(alignment: .top, spacing: 0) {
                            // Category name cell
                            VStack(spacing: 0) {
                                Text(category.title)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(.all, 8)
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
                                    GoalsCellView(goals: goalsForCell)
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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if goals.isEmpty {
                    Text("—")
                        .foregroundColor(.secondary)
                        .font(.body)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(goals) { goal in
                        HStack(spacing: 8) {
                            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .foregroundColor(goal.isCompleted ? .green : .secondary)
                            
                            Text(goal.title)
                                .font(.body)
                                .fontWeight(.medium)
                                .strikethrough(goal.isCompleted)
                                .foregroundColor(goal.isCompleted ? .secondary : .primary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(8)
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

