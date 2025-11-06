import Foundation

// MARK: - Task Time Window Data Model
/// Maps a Google Task ID to a time window for scheduling on its due date.
/// Unlike events, both start and end times are on the same day (the due date).
struct TaskTimeWindowData: Identifiable, Codable, Hashable {
    let id: String // Google Task ID
    let taskId: String // Same as id, kept for clarity
    let startTime: Date // Start time on the due date
    let endTime: Date // End time on the due date (must be same day as startTime)
    let isAllDay: Bool // Whether this is an all-day task
    let userId: String // User ID for multi-user support
    let createdAt: Date
    let updatedAt: Date
    
    init(
        taskId: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false,
        userId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = taskId // Use task ID as the primary identifier
        self.taskId = taskId
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    init(
        id: String,
        taskId: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool,
        userId: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.taskId = taskId
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Validates that start and end times are on the same day
    var isValid: Bool {
        let calendar = Calendar.current
        return calendar.isDate(startTime, inSameDayAs: endTime)
    }
    
    /// Returns the date component (same for both start and end since they're on the same day)
    var date: Date {
        let calendar = Calendar.current
        return calendar.startOfDay(for: startTime)
    }
}

