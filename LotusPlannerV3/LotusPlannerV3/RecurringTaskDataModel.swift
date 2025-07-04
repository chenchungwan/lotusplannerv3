import Foundation
import FirebaseFirestore

// MARK: - Recurring Task Frequency
enum RecurringFrequency: String, CaseIterable, Codable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .custom: return "Custom"
        }
    }
    
    var icon: String {
        switch self {
        case .daily: return "calendar.day.timeline.left"
        case .weekly: return "calendar.week.timeline.left"
        case .monthly: return "calendar.month.timeline.left"
        case .yearly: return "calendar.year.timeline.left"
        case .custom: return "calendar.custom"
        }
    }
}

// MARK: - Recurring Task Data Model
struct RecurringTask: Identifiable, Codable, Equatable {
    let id: String
    let originalTaskId: String // ID of the original Google Task
    let taskListId: String // Google Task List ID
    let accountKind: String // "personal" or "professional"
    let userId: String
    let frequency: RecurringFrequency
    let interval: Int // e.g., every 2 weeks, every 3 days
    let startDate: Date // When the recurring pattern starts
    let endDate: Date? // When the recurring pattern ends (optional)
    let isActive: Bool // Whether the recurring task is active
    let createdAt: Date
    let updatedAt: Date
    
    // Task template data (to create new instances)
    let taskTitle: String
    let taskNotes: String?
    
    // Custom frequency options
    let customDays: [Int]? // For custom weekly (0=Sunday, 1=Monday, etc.)
    let customDayOfMonth: Int? // For custom monthly (1-31)
    let customMonthOfYear: Int? // For custom yearly (1-12)
    
    init(
        originalTaskId: String,
        taskListId: String,
        accountKind: GoogleAuthManager.AccountKind,
        userId: String,
        frequency: RecurringFrequency,
        interval: Int = 1,
        startDate: Date,
        endDate: Date? = nil,
        taskTitle: String,
        taskNotes: String? = nil,
        customDays: [Int]? = nil,
        customDayOfMonth: Int? = nil,
        customMonthOfYear: Int? = nil
    ) {
        self.id = UUID().uuidString
        self.originalTaskId = originalTaskId
        self.taskListId = taskListId
        self.accountKind = accountKind.rawValue
        self.userId = userId
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = true
        self.createdAt = Date()
        self.updatedAt = Date()
        self.taskTitle = taskTitle
        self.taskNotes = taskNotes
        self.customDays = customDays
        self.customDayOfMonth = customDayOfMonth
        self.customMonthOfYear = customMonthOfYear
    }
    
    // For Firestore
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let originalTaskId = data["originalTaskId"] as? String,
              let taskListId = data["taskListId"] as? String,
              let accountKind = data["accountKind"] as? String,
              let userId = data["userId"] as? String,
              let frequencyString = data["frequency"] as? String,
              let frequency = RecurringFrequency(rawValue: frequencyString),
              let interval = data["interval"] as? Int,
              let startDate = (data["startDate"] as? Timestamp)?.dateValue(),
              let isActive = data["isActive"] as? Bool,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
              let taskTitle = data["taskTitle"] as? String else {
            return nil
        }
        
        self.id = document.documentID
        self.originalTaskId = originalTaskId
        self.taskListId = taskListId
        self.accountKind = accountKind
        self.userId = userId
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.endDate = (data["endDate"] as? Timestamp)?.dateValue()
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.taskTitle = taskTitle
        self.taskNotes = data["taskNotes"] as? String
        self.customDays = data["customDays"] as? [Int]
        self.customDayOfMonth = data["customDayOfMonth"] as? Int
        self.customMonthOfYear = data["customMonthOfYear"] as? Int
    }
    
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "originalTaskId": originalTaskId,
            "taskListId": taskListId,
            "accountKind": accountKind,
            "userId": userId,
            "frequency": frequency.rawValue,
            "interval": interval,
            "startDate": Timestamp(date: startDate),
            "isActive": isActive,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "taskTitle": taskTitle
        ]
        
        if let endDate = endDate {
            data["endDate"] = Timestamp(date: endDate)
        }
        
        if let taskNotes = taskNotes {
            data["taskNotes"] = taskNotes
        }
        
        if let customDays = customDays {
            data["customDays"] = customDays
        }
        
        if let customDayOfMonth = customDayOfMonth {
            data["customDayOfMonth"] = customDayOfMonth
        }
        
        if let customMonthOfYear = customMonthOfYear {
            data["customMonthOfYear"] = customMonthOfYear
        }
        
        return data
    }
    
    // MARK: - Helper Methods
    
    /// Calculate the next due date based on the recurring pattern
    func nextDueDate(after date: Date) -> Date? {
        let calendar = Calendar.current
        
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date)
            
        case .weekly:
            if let customDays = customDays, !customDays.isEmpty {
                // Custom weekly pattern
                return nextCustomWeeklyDate(after: date, customDays: customDays)
            } else {
                // Simple weekly pattern
                return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
            }
            
        case .monthly:
            if let customDayOfMonth = customDayOfMonth {
                // Custom monthly pattern
                return nextCustomMonthlyDate(after: date, dayOfMonth: customDayOfMonth)
            } else {
                // Simple monthly pattern
                return calendar.date(byAdding: .month, value: interval, to: date)
            }
            
        case .yearly:
            if let customMonthOfYear = customMonthOfYear, let customDayOfMonth = customDayOfMonth {
                // Custom yearly pattern
                return nextCustomYearlyDate(after: date, month: customMonthOfYear, day: customDayOfMonth)
            } else {
                // Simple yearly pattern
                return calendar.date(byAdding: .year, value: interval, to: date)
            }
            
        case .custom:
            // For custom patterns, use the most appropriate calculation
            if let customDays = customDays, !customDays.isEmpty {
                return nextCustomWeeklyDate(after: date, customDays: customDays)
            } else if let customDayOfMonth = customDayOfMonth {
                return nextCustomMonthlyDate(after: date, dayOfMonth: customDayOfMonth)
            } else {
                return calendar.date(byAdding: .day, value: interval, to: date)
            }
        }
    }
    
    private func nextCustomWeeklyDate(after date: Date, customDays: [Int]) -> Date? {
        let calendar = Calendar.current
        let sortedDays = customDays.sorted()
        
        // Find the next occurrence within the current week
        let currentWeekday = calendar.component(.weekday, from: date) - 1 // 0=Sunday, 1=Monday, etc.
        
        for day in sortedDays {
            if day > currentWeekday {
                let daysToAdd = day - currentWeekday
                return calendar.date(byAdding: .day, value: daysToAdd, to: date)
            }
        }
        
        // If no occurrence in current week, find the first occurrence in next week
        let daysToNextWeek = 7 - currentWeekday
        let nextWeekStartDay = sortedDays.first ?? 0
        let totalDaysToAdd = daysToNextWeek + nextWeekStartDay
        
        return calendar.date(byAdding: .day, value: totalDaysToAdd, to: date)
    }
    
    private func nextCustomMonthlyDate(after date: Date, dayOfMonth: Int) -> Date? {
        let calendar = Calendar.current
        
        // Try current month first
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = dayOfMonth
        
        if let candidateDate = calendar.date(from: components), candidateDate > date {
            return candidateDate
        }
        
        // Try next month
        components.month = (components.month ?? 1) + interval
        if let nextDate = calendar.date(from: components) {
            return nextDate
        }
        
        return nil
    }
    
    private func nextCustomYearlyDate(after date: Date, month: Int, day: Int) -> Date? {
        let calendar = Calendar.current
        
        // Try current year first
        var components = calendar.dateComponents([.year], from: date)
        components.month = month
        components.day = day
        
        if let candidateDate = calendar.date(from: components), candidateDate > date {
            return candidateDate
        }
        
        // Try next year
        components.year = (components.year ?? 2024) + interval
        return calendar.date(from: components)
    }
    
    /// Check if the recurring task should generate a new instance
    func shouldGenerateNewTask(completedDate: Date) -> Bool {
        guard isActive else { return false }
        
        // Check if the completion date is after the start date
        if completedDate < startDate {
            return false
        }
        
        // Check if the completion date is before the end date (if set)
        if let endDate = endDate, completedDate >= endDate {
            return false
        }
        
        return true
    }
    
    /// Generate a new task instance
    func generateNewTaskInstance(dueDate: Date) -> GoogleTask {
        let dueDateString: String
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        dueDateString = formatter.string(from: dueDate)
        
        return GoogleTask(
            id: UUID().uuidString, // Will be overwritten by server
            title: taskTitle,
            notes: taskNotes,
            status: "needsAction",
            due: dueDateString,
            updated: nil,
            recurringTaskId: id,
            isRecurringInstance: true
        )
    }
}

// MARK: - Recurring Task Instance Tracking
struct RecurringTaskInstance: Identifiable, Codable, Equatable {
    let id: String
    let recurringTaskId: String
    let googleTaskId: String
    let dueDate: Date
    let isCompleted: Bool
    let completedDate: Date?
    let createdAt: Date
    
    init(recurringTaskId: String, googleTaskId: String, dueDate: Date) {
        self.id = UUID().uuidString
        self.recurringTaskId = recurringTaskId
        self.googleTaskId = googleTaskId
        self.dueDate = dueDate
        self.isCompleted = false
        self.completedDate = nil
        self.createdAt = Date()
    }
    
    // For Firestore
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let recurringTaskId = data["recurringTaskId"] as? String,
              let googleTaskId = data["googleTaskId"] as? String,
              let dueDate = (data["dueDate"] as? Timestamp)?.dateValue(),
              let isCompleted = data["isCompleted"] as? Bool,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.id = document.documentID
        self.recurringTaskId = recurringTaskId
        self.googleTaskId = googleTaskId
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedDate = (data["completedDate"] as? Timestamp)?.dateValue()
        self.createdAt = createdAt
    }
    
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "recurringTaskId": recurringTaskId,
            "googleTaskId": googleTaskId,
            "dueDate": Timestamp(date: dueDate),
            "isCompleted": isCompleted,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let completedDate = completedDate {
            data["completedDate"] = Timestamp(date: completedDate)
        }
        
        return data
    }
} 