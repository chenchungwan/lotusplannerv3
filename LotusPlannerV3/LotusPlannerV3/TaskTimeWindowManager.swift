import Foundation
import SwiftUI

/// Manager for task time windows stored in iCloud via Core Data.
/// Maps Google Task IDs to time windows (start/end times on the same day as due date).
@MainActor
class TaskTimeWindowManager: ObservableObject {
    static let shared = TaskTimeWindowManager()
    
    @Published private(set) var timeWindows: [TaskTimeWindowData] = []
    
    private let coreDataManager = CoreDataManager.shared
    private let authManager = GoogleAuthManager.shared
    
    private init() {
        loadTimeWindows()
    }
    
    // MARK: - Load Time Windows
    func loadTimeWindows() {
        devLog("📖 TaskTimeWindowManager: loadTimeWindows() called")
        // Don't filter by userId - CloudKit already scopes data to the iCloud account
        // This ensures task times sync across all devices using the same iCloud account
        devLog("📖 TaskTimeWindowManager: Loading ALL time windows (no userId filter)")
        timeWindows = coreDataManager.loadAllTaskTimeWindows(for: nil)
        devLog("📖 TaskTimeWindowManager: Loaded \(timeWindows.count) time windows")
    }
    
    // MARK: - Get Time Window
    /// Get the time window for a specific task ID
    func getTimeWindow(for taskId: String) -> TaskTimeWindowData? {
        return timeWindows.first { $0.taskId == taskId }
    }
    
    /// Get time window for a task, or create a default one if it doesn't exist
    func getOrCreateTimeWindow(for taskId: String, dueDate: Date) -> TaskTimeWindowData {
        if let existing = getTimeWindow(for: taskId) {
            return existing
        }
        
        // Create a default time window (all-day)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: dueDate)
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
        
        return TaskTimeWindowData(
            taskId: taskId,
            startTime: startOfDay,
            endTime: endOfDay,
            isAllDay: true,
            userId: getUserId()
        )
    }
    
    // MARK: - Save Time Window
    /// Save or update a time window for a task
    func saveTimeWindow(_ timeWindow: TaskTimeWindowData) {
        devLog("📝 TaskTimeWindowManager: saveTimeWindow(TaskTimeWindowData) called")
        
        // Create updated version with current timestamp
        let updatedWindow = TaskTimeWindowData(
            id: timeWindow.id,
            taskId: timeWindow.taskId,
            startTime: timeWindow.startTime,
            endTime: timeWindow.endTime,
            isAllDay: timeWindow.isAllDay,
            userId: timeWindow.userId,
            createdAt: timeWindow.createdAt,
            updatedAt: Date()
        )
        
        devLog("📝 TaskTimeWindowManager: Calling coreDataManager.saveTaskTimeWindow...")
        coreDataManager.saveTaskTimeWindow(updatedWindow)
        
        // Update local cache
        if let index = timeWindows.firstIndex(where: { $0.taskId == updatedWindow.taskId }) {
            devLog("📝 TaskTimeWindowManager: Updating existing time window in cache")
            timeWindows[index] = updatedWindow
        } else {
            devLog("📝 TaskTimeWindowManager: Adding new time window to cache")
            timeWindows.append(updatedWindow)
        }
        
        devLog("✅ TaskTimeWindowManager: Time window saved successfully")
    }
    
    /// Save time window from components
    func saveTimeWindow(
        taskId: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false
    ) {
        devLog("📝 TaskTimeWindowManager: saveTimeWindow called")
        devLog("📝   taskId: \(taskId)")
        devLog("📝   startTime: \(startTime)")
        devLog("📝   endTime: \(endTime)")
        devLog("📝   isAllDay: \(isAllDay)")
        
        // Validate that start and end are on the same day
        let calendar = Calendar.current
        guard calendar.isDate(startTime, inSameDayAs: endTime) else {
            devLog("⚠️ TaskTimeWindowManager: Start and end times must be on the same day")
            return
        }
        
        let existing = getTimeWindow(for: taskId)
        let timeWindow = TaskTimeWindowData(
            taskId: taskId,
            startTime: startTime,
            endTime: endTime,
            isAllDay: isAllDay,
            userId: getUserId(),
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date()
        )
        
        devLog("📝 TaskTimeWindowManager: Calling saveTimeWindow(timeWindow)...")
        saveTimeWindow(timeWindow)
    }
    
    // MARK: - Delete Time Window
    /// Delete the time window for a task
    func deleteTimeWindow(for taskId: String) {
        coreDataManager.deleteTaskTimeWindow(for: taskId)
        timeWindows.removeAll { $0.taskId == taskId }
    }
    
    // MARK: - Helper Methods
    private func getUserId() -> String {
        // Use a fixed userId for TaskTimeWindows since CloudKit already scopes data to iCloud account
        // This ensures all devices using the same iCloud account share the same task times
        // regardless of which Google account they're logged into
        return "icloud-user"
    }
    
    // MARK: - Query Methods
    /// Get all time windows for a specific date
    func getTimeWindows(for date: Date) -> [TaskTimeWindowData] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        
        return timeWindows.filter { window in
            let windowDay = calendar.startOfDay(for: window.startTime)
            return windowDay == targetDay
        }
    }
    
    /// Get all time windows for tasks that are all-day
    func getAllDayTimeWindows() -> [TaskTimeWindowData] {
        return timeWindows.filter { $0.isAllDay }
    }
    
    /// Get all time windows for tasks that have specific times
    func getTimedTimeWindows() -> [TaskTimeWindowData] {
        return timeWindows.filter { !$0.isAllDay }
    }
}

