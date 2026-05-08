import Foundation

// MARK: - Task Filter Enum
enum TaskFilter: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case all = "All"
    
    var icon: String {
        switch self {
        case .all: return "line.horizontal.3.decrease.circle"
        case .day: return "calendar"
        case .week: return "calendar"
        case .month: return "calendar"
        case .year: return "calendar"
        }
    }
    
    // SF Symbol for navigation buttons
    var sfSymbol: String {
        switch self {
        case .day: return "d.circle"
        case .week: return "w.circle"
        case .month: return "m.circle"
        case .year: return "y.circle"
        case .all: return "line.horizontal.3.decrease.circle"
        }
    }
}

// MARK: - "All" Subfilter
enum AllTaskSubfilter: String, CaseIterable {
    case all = "All"
    case hasDueDate = "Has Due Date"
    case noDueDate = "No Due Date"
    case pastDue = "Past Due"
    case completed = "Completed"
}

// MARK: - Tasks Error Enum
enum TasksError: Error {
    case notAuthenticated
    case invalidResponse
    case apiError(Int)
    case authError(String)
    case failedToCreateTaskList
    
    var localizedDescription: String {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidResponse:
            return "Invalid response"
        case .apiError(let code):
            return "API error: \(code)"
        case .authError(let message):
            return "Auth error: \(message)"
        case .failedToCreateTaskList:
            return "Failed to create task list"
        }
    }
}
