import Foundation
import CoreData
import CloudKit

// MARK: - Goal Target Timeframe
enum GoalTimeframe: String, CaseIterable, Codable {
    case week = "week"
    case month = "month"
    case year = "year"
    
    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
    
    var calendarComponent: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

// MARK: - Linked Task Data
struct LinkedTaskData: Codable, Hashable {
    let taskId: String
    let listId: String
    let accountKind: String // "personal" or "professional"

    init(taskId: String, listId: String, accountKind: GoogleAuthManager.AccountKind) {
        self.taskId = taskId
        self.listId = listId
        self.accountKind = accountKind == .personal ? "personal" : "professional"
    }

    var accountKindEnum: GoogleAuthManager.AccountKind {
        return accountKind == "personal" ? .personal : .professional
    }
}

// MARK: - Goal Data Model
struct GoalData: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var successMetric: String
    var categoryId: UUID
    var targetTimeframe: GoalTimeframe
    var dueDate: Date
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date
    var linkedTasks: [LinkedTaskData] // Tasks linked to this goal

    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        successMetric: String = "",
        categoryId: UUID,
        targetTimeframe: GoalTimeframe,
        dueDate: Date,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        linkedTasks: [LinkedTaskData] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.successMetric = successMetric
        self.categoryId = categoryId
        self.targetTimeframe = targetTimeframe
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.linkedTasks = linkedTasks
    }
}

// MARK: - Goal Category Data Model
struct GoalCategoryData: Identifiable, Codable {
    let id: UUID
    var title: String
    var displayPosition: Int // 0-5 for 2x3 grid (0=top-left, 1=top-right, 2=middle-left, etc.)
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        displayPosition: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.displayPosition = displayPosition
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Goals Container for iCloud Sync
struct GoalsContainer: Codable {
    var categories: [GoalCategoryData]
    var goals: [GoalData]
    var lastSyncDate: Date
    
    init(categories: [GoalCategoryData] = [], goals: [GoalData] = [], lastSyncDate: Date = Date()) {
        self.categories = categories
        self.goals = goals
        self.lastSyncDate = lastSyncDate
    }
}

// MARK: - Goal Helper Functions
extension GoalData {
    /// Calculate the due date based on target timeframe from a given start date
    static func calculateDueDate(for timeframe: GoalTimeframe, from startDate: Date = Date()) -> Date {
        let calendar = Calendar.current
        
        switch timeframe {
        case .week:
            // End of current week (Sunday)
            let weekday = calendar.component(.weekday, from: startDate)
            let daysUntilSunday = (7 - weekday + 1) % 7
            return calendar.date(byAdding: .day, value: daysUntilSunday, to: startDate) ?? startDate
            
        case .month:
            // End of current month
            if let endOfMonth = calendar.dateInterval(of: .month, for: startDate)?.end {
                return calendar.date(byAdding: .day, value: -1, to: endOfMonth) ?? startDate
            }
            return startDate
            
        case .year:
            // End of current year
            if let endOfYear = calendar.dateInterval(of: .year, for: startDate)?.end {
                return calendar.date(byAdding: .day, value: -1, to: endOfYear) ?? startDate
            }
            return startDate
        }
    }
    
    /// Check if goal is overdue
    var isOverdue: Bool {
        return !isCompleted && dueDate < Date()
    }
    
    /// Get days remaining until due date
    var daysRemaining: Int {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day], from: now, to: dueDate)
        return max(0, components.day ?? 0)
    }
}

extension GoalCategoryData {
    /// Get grid position (row, column) from display position
    var gridPosition: (row: Int, column: Int) {
        let row = displayPosition / 2
        let column = displayPosition % 2
        return (row: row, column: column)
    }
    
    /// Set display position from grid coordinates
    mutating func setGridPosition(row: Int, column: Int) {
        displayPosition = row * 2 + column
    }
    
    /// Check if position is valid for 2x3 grid
    var isValidPosition: Bool {
        return displayPosition >= 0 && displayPosition < 6
    }
}
