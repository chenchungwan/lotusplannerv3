import Foundation

struct Goal: Identifiable, Codable, Equatable {
    let id: UUID
    var description: String
    var dueDate: Date?
    var categoryId: UUID // reference to GoalCategory.id
    var isCompleted: Bool
    var taskLinks: [TaskLink]
    var userId: String
    var createdAt: Date
    
    init(id: UUID = UUID(), description: String, dueDate: Date? = nil, categoryId: UUID, isCompleted: Bool = false, taskLinks: [TaskLink] = [], userId: String, createdAt: Date = Date()) {
        self.id = id
        self.description = description
        self.dueDate = dueDate
        self.categoryId = categoryId
        self.isCompleted = isCompleted
        self.taskLinks = taskLinks
        self.userId = userId
        self.createdAt = createdAt
    }
    
    struct TaskLink: Codable, Equatable {
        let taskId: String
        let listId: String
        let accountKindRaw: String // "personal" or "professional"
    }
} 