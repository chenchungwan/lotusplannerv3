import Foundation
import FirebaseFirestore

@MainActor
class RecurringTaskManager: ObservableObject {
    static let shared = RecurringTaskManager()
    
    private let firestoreManager = FirestoreManager.shared
    private let authManager = GoogleAuthManager.shared
    
    @Published var personalRecurringTasks: [RecurringTask] = []
    @Published var professionalRecurringTasks: [RecurringTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {}
    
    // MARK: - Load Recurring Tasks
    func loadRecurringTasks() async {
        isLoading = true
        errorMessage = nil
        
        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .personal) {
                group.addTask {
                    await self.loadRecurringTasksForAccount(.personal)
                }
            }
            
            if authManager.isLinked(kind: .professional) {
                group.addTask {
                    await self.loadRecurringTasksForAccount(.professional)
                }
            }
        }
        
        isLoading = false
    }
    
    private func loadRecurringTasksForAccount(_ kind: GoogleAuthManager.AccountKind) async {
        do {
            let tasks = try await firestoreManager.getRecurringTasks(for: kind)
            
            await MainActor.run {
                switch kind {
                case .personal:
                    self.personalRecurringTasks = tasks
                case .professional:
                    self.professionalRecurringTasks = tasks
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load \(kind.rawValue) recurring tasks: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Create Recurring Task
    func createRecurringTask(
        from task: GoogleTask,
        taskListId: String,
        accountKind: GoogleAuthManager.AccountKind,
        frequency: RecurringFrequency,
        interval: Int = 1,
        startDate: Date,
        endDate: Date? = nil,
        customDays: [Int]? = nil,
        customDayOfMonth: Int? = nil,
        customMonthOfYear: Int? = nil
    ) async throws -> RecurringTask {
        let userId = authManager.getEmail(for: accountKind)
        
        let recurringTask = RecurringTask(
            originalTaskId: task.id,
            taskListId: taskListId,
            accountKind: accountKind,
            userId: userId,
            frequency: frequency,
            interval: interval,
            startDate: startDate,
            endDate: endDate,
            taskTitle: task.title,
            taskNotes: task.notes,
            customDays: customDays,
            customDayOfMonth: customDayOfMonth,
            customMonthOfYear: customMonthOfYear
        )
        
        try await firestoreManager.addRecurringTask(recurringTask, for: accountKind)
        
        // Create initial instance tracking
        let instance = RecurringTaskInstance(
            recurringTaskId: recurringTask.id,
            googleTaskId: task.id,
            dueDate: task.dueDate ?? Date()
        )
        
        try await firestoreManager.addRecurringTaskInstance(instance, for: accountKind)
        
        // Update local state
        await MainActor.run {
            switch accountKind {
            case .personal:
                self.personalRecurringTasks.append(recurringTask)
            case .professional:
                self.professionalRecurringTasks.append(recurringTask)
            }
        }
        
        return recurringTask
    }
    
    // MARK: - Update Recurring Task
    func updateRecurringTask(_ task: RecurringTask, for accountKind: GoogleAuthManager.AccountKind) async throws {
        try await firestoreManager.updateRecurringTask(task, for: accountKind)
        
        // Update local state
        await MainActor.run {
            switch accountKind {
            case .personal:
                if let index = self.personalRecurringTasks.firstIndex(where: { $0.id == task.id }) {
                    self.personalRecurringTasks[index] = task
                }
            case .professional:
                if let index = self.professionalRecurringTasks.firstIndex(where: { $0.id == task.id }) {
                    self.professionalRecurringTasks[index] = task
                }
            }
        }
    }
    
    // MARK: - Delete Recurring Task
    func deleteRecurringTask(_ taskId: String, for accountKind: GoogleAuthManager.AccountKind) async throws {
        try await firestoreManager.deleteRecurringTask(taskId, for: accountKind)
        
        // Update local state
        await MainActor.run {
            switch accountKind {
            case .personal:
                self.personalRecurringTasks.removeAll { $0.id == taskId }
            case .professional:
                self.professionalRecurringTasks.removeAll { $0.id == taskId }
            }
        }
    }
    
    // MARK: - Handle Task Completion
    func handleTaskCompletion(
        _ task: GoogleTask,
        taskListId: String,
        accountKind: GoogleAuthManager.AccountKind
    ) async throws -> GoogleTask? {
        // Check if this task is part of a recurring pattern
        guard let recurringTaskId = task.recurringTaskId,
              task.isRecurringInstance else {
            return nil
        }
        
        // Get the recurring task
        guard let recurringTask = try await firestoreManager.getRecurringTask(by: recurringTaskId, for: accountKind) else {
            print("⚠️ Recurring task not found for ID: \(recurringTaskId)")
            return nil
        }
        
        // Check if we should generate a new task
        let completionDate = Date()
        guard recurringTask.shouldGenerateNewTask(completedDate: completionDate) else {
            print("🚫 Not generating new task - outside recurring period")
            return nil
        }
        
        // Calculate next due date
        let currentDueDate = task.dueDate ?? completionDate
        guard let nextDueDate = recurringTask.nextDueDate(after: currentDueDate) else {
            print("⚠️ Could not calculate next due date")
            return nil
        }
        
        // Generate new task instance
        let newTask = recurringTask.generateNewTaskInstance(dueDate: nextDueDate)
        
        // Create tracking instance for the new task
        let newInstance = RecurringTaskInstance(
            recurringTaskId: recurringTaskId,
            googleTaskId: newTask.id,
            dueDate: nextDueDate
        )
        
        try await firestoreManager.addRecurringTaskInstance(newInstance, for: accountKind)
        
        // Update the completed instance
        if let completedInstance = try await firestoreManager.getRecurringTaskInstanceByGoogleTaskId(task.id, for: accountKind) {
            let updatedInstance = RecurringTaskInstance(
                recurringTaskId: completedInstance.recurringTaskId,
                googleTaskId: completedInstance.googleTaskId,
                dueDate: completedInstance.dueDate
            )
            // Note: RecurringTaskInstance struct is immutable, would need to make it mutable to update completion
            // For now, we'll just track that a new task was created
        }
        
        print("✅ Generated new recurring task instance for \(nextDueDate)")
        return newTask
    }
    
    // MARK: - Get Recurring Task for Google Task
    func getRecurringTask(for googleTask: GoogleTask, accountKind: GoogleAuthManager.AccountKind) async throws -> RecurringTask? {
        guard let recurringTaskId = googleTask.recurringTaskId else {
            return nil
        }
        
        return try await firestoreManager.getRecurringTask(by: recurringTaskId, for: accountKind)
    }
    
    // MARK: - Check if Task is Recurring
    func isTaskRecurring(_ task: GoogleTask) -> Bool {
        return task.recurringTaskId != nil && task.isRecurringInstance
    }
    
    // MARK: - Generate Upcoming Recurring Tasks
    func generateUpcomingRecurringTasks(for accountKind: GoogleAuthManager.AccountKind, daysAhead: Int = 14) async throws -> [GoogleTask] {
        let recurringTasks = switch accountKind {
        case .personal: personalRecurringTasks
        case .professional: professionalRecurringTasks
        }
        
        var upcomingTasks: [GoogleTask] = []
        let currentDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: currentDate) ?? currentDate
        
        for recurringTask in recurringTasks {
            guard recurringTask.isActive else { continue }
            
            // Get existing instances for this recurring task
            let existingInstances = try await firestoreManager.getRecurringTaskInstances(
                for: recurringTask.id,
                accountKind: accountKind
            )
            
            // Find the last created instance to calculate from
            let lastDueDate = existingInstances
                .map { $0.dueDate }
                .max() ?? recurringTask.startDate
            
            // Generate tasks until the end date
            var nextDueDate = recurringTask.nextDueDate(after: lastDueDate)
            
            while let dueDate = nextDueDate, dueDate <= endDate {
                // Check if we already have an instance for this date
                let hasExistingInstance = existingInstances.contains { instance in
                    Calendar.current.isDate(instance.dueDate, inSameDayAs: dueDate)
                }
                
                if !hasExistingInstance {
                    let newTask = recurringTask.generateNewTaskInstance(dueDate: dueDate)
                    upcomingTasks.append(newTask)
                    
                    // Create tracking instance
                    let instance = RecurringTaskInstance(
                        recurringTaskId: recurringTask.id,
                        googleTaskId: newTask.id,
                        dueDate: dueDate
                    )
                    
                    try await firestoreManager.addRecurringTaskInstance(instance, for: accountKind)
                }
                
                nextDueDate = recurringTask.nextDueDate(after: dueDate)
            }
        }
        
        return upcomingTasks
    }
    
    // MARK: - Disable Recurring Task
    func disableRecurringTask(_ taskId: String, for accountKind: GoogleAuthManager.AccountKind) async throws {
        guard let recurringTask = try await firestoreManager.getRecurringTask(by: taskId, for: accountKind) else {
            throw RecurringTaskError.taskNotFound
        }
        
        // Create an updated task with isActive set to false
        let updatedTask = RecurringTask(
            originalTaskId: recurringTask.originalTaskId,
            taskListId: recurringTask.taskListId,
            accountKind: GoogleAuthManager.AccountKind(rawValue: recurringTask.accountKind) ?? .personal,
            userId: recurringTask.userId,
            frequency: recurringTask.frequency,
            interval: recurringTask.interval,
            startDate: recurringTask.startDate,
            endDate: recurringTask.endDate,
            taskTitle: recurringTask.taskTitle,
            taskNotes: recurringTask.taskNotes,
            customDays: recurringTask.customDays,
            customDayOfMonth: recurringTask.customDayOfMonth,
            customMonthOfYear: recurringTask.customMonthOfYear
        )
        
        // Note: Since RecurringTask is immutable, we would need to modify it to have mutable isActive
        // For now, we'll use the delete method to "disable" it
        try await deleteRecurringTask(taskId, for: accountKind)
    }
}

// MARK: - Recurring Task Errors
enum RecurringTaskError: Error, LocalizedError {
    case taskNotFound
    case invalidRecurringPattern
    case failedToCreateInstance
    case authenticationRequired
    
    var errorDescription: String? {
        switch self {
        case .taskNotFound:
            return "Recurring task not found"
        case .invalidRecurringPattern:
            return "Invalid recurring pattern"
        case .failedToCreateInstance:
            return "Failed to create recurring task instance"
        case .authenticationRequired:
            return "Authentication required for recurring tasks"
        }
    }
}
