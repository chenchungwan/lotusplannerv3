import Foundation

// MARK: - Google Tasks Data Models
struct GoogleTaskList: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let updated: String?
}

struct GoogleTask: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var notes: String?
    var status: String
    var due: String?
    var completed: String?
    var updated: String?
    var position: String? = nil
    
    var isCompleted: Bool {
        return status == "completed"
    }
    
    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current  // Use local timezone for all-day dates
        return formatter
    }()
    
    private static let completionDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let dueDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dueDateTimeFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    
    var dueDate: Date? {
        guard let due = due else { return nil }
        
        // Extract just the date part from Google's response (ignore time completely)
        let dateOnly = String(due.prefix(10)) // Get "yyyy-MM-dd" part only
        
        return GoogleTask.dueDateFormatter.date(from: dateOnly)
    }
    
    var completionDate: Date? {
        guard let completed = completed else { return nil }
        
        // Google Tasks completion dates: RFC 3339 format with full timestamp
        return GoogleTask.completionDateFormatter.date(from: completed)
    }

    var dueDateTime: Date? {
        guard let due = due else { return nil }
        if let date = GoogleTask.dueDateTimeFormatter.date(from: due) {
            return date
        }
        return GoogleTask.dueDateTimeFormatterNoFraction.date(from: due)
    }

    /// Google stores `due` as RFC 3339 and echoes it back that way, but the
    /// app writes a bare local `yyyy-MM-dd` when scheduling. Keeping both
    /// forms alive meant the same task looked different depending on whether
    /// it came from the network or the local cache. Normalize before
    /// caching or sending so there is only one representation in play.
    ///
    /// Note that `due` carries no time-of-day meaning: Google discards it.
    /// A task's time lives in its `TaskTimeWindow`, never in this string.
    static func normalizedDue(_ due: String?) -> String? {
        guard let due else { return nil }
        guard due.count == 10, due.contains("-"), !due.contains("T") else { return due }
        return "\(due)T00:00:00.000Z"
    }

    /// Copy of this task with `due` in the same form the server would return.
    var normalizedForCache: GoogleTask {
        var copy = self
        copy.due = GoogleTask.normalizedDue(due)
        return copy
    }

    // MARK: - Priority Support

    /// Get priority from notes field
    var priority: TaskPriorityData? {
        return TaskPriorityData.parse(from: notes)
    }

    /// Get notes with priority tag removed (user-visible notes only)
    var userNotes: String? {
        return TaskPriorityData.removeTag(from: notes)
    }

    /// Create a copy of this task with updated priority
    func withPriority(_ priority: TaskPriorityData?) -> GoogleTask {
        let updatedNotes = TaskPriorityData.updateNotes(notes, with: priority)
        var copy = self
        copy.notes = updatedNotes
        return copy
    }
}

struct GoogleTasksResponse: Codable {
    let items: [GoogleTask]?
    let nextPageToken: String?
}

struct GoogleTaskListsResponse: Codable {
    let items: [GoogleTaskList]?
}
