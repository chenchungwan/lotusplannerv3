import SwiftUI
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
    
    var dueDate: Date? {
        guard let due = due else { return nil }
        
        // Extract just the date part from Google's response (ignore time completely)
        let dateOnly = String(due.prefix(10)) // Get "yyyy-MM-dd" part only
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current // Use local timezone for date-only parsing
        let parsedDate = formatter.date(from: dateOnly)
        return parsedDate
    }
    
    var completionDate: Date? {
        guard let completed = completed else { return nil }
        
        // Google Tasks completion dates: RFC 3339 format with full timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC") // Parse as UTC
        
        if let utcDate = formatter.date(from: completed) {
            // Convert to local timezone for day comparison
            let localFormatter = DateFormatter()
            localFormatter.dateStyle = .full
            localFormatter.timeZone = TimeZone.current
            return utcDate
        }
        return nil
    }
}

struct GoogleTasksResponse: Codable {
    let items: [GoogleTask]?
    let nextPageToken: String?
}

struct GoogleTaskListsResponse: Codable {
    let items: [GoogleTaskList]?
}

// MARK: - Tasks View Model
@MainActor
class TasksViewModel: ObservableObject {
    @Published var personalTaskLists: [GoogleTaskList] = []
    @Published var professionalTaskLists: [GoogleTaskList] = []
    @Published var personalTasks: [String: [GoogleTask]] = [:] // taskListId: [tasks]
    @Published var professionalTasks: [String: [GoogleTask]] = [:]
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    private let authManager = GoogleAuthManager.shared
    
    // MARK: - Task Caching
    private var cachedTasks: [String: [GoogleTask]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheTimeout: TimeInterval = 1800 // 30 minutes
    
    // MARK: - Task List Caching (Performance Optimization)
    private var cachedTaskLists: [GoogleAuthManager.AccountKind: [GoogleTaskList]] = [:]
    private var taskListCacheTimestamps: [GoogleAuthManager.AccountKind: Date] = [:]
    private let taskListCacheTimeout: TimeInterval = 3600 // 1 hour
    
    // MARK: - Filtered Task Caching
    private struct FilterCacheKey: Hashable {
        let accountKind: String  // "personal" or "professional"
        let filter: String       // String representation of filter
        let subfilter: String    // String representation of subfilter
        let referenceDate: String // Date string for filter context
        let hideCompleted: Bool   // hideCompletedTasks preference
    }
    private var filteredTasksCache: [FilterCacheKey: [String: [GoogleTask]]] = [:]
    
    func loadTasks(forceClear: Bool = false) async {
        isLoading = true
        errorMessage = ""
        
        // Clear all caches if forced
        if forceClear {
            clearCacheForAccount(.personal)
            clearCacheForAccount(.professional)
        }
        
        // Load tasks for both account types in parallel
        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .personal) {
                group.addTask {
                    await self.loadTasksForAccount(.personal)
                }
            }
            
            if authManager.isLinked(kind: .professional) {
                group.addTask {
                    await self.loadTasksForAccount(.professional)
                }
            }
        }
        
        await MainActor.run {
            self.isLoading = false
        }
    }
    
    /// Fast method to load only task lists (for popup initialization)
    func loadTaskListsOnly() async {
        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .personal) {
                group.addTask {
                    await self.loadTaskListsForAccount(.personal)
                }
            }
            
            if authManager.isLinked(kind: .professional) {
                group.addTask {
                    await self.loadTaskListsForAccount(.professional)
                }
            }
        }
    }
    
    /// Load tasks on-demand when popup is opened (performance optimization)
    func loadTasksOnDemand() async {
        // Only load if we don't already have tasks loaded
        let hasPersonalTasks = !personalTasks.isEmpty
        let hasProfessionalTasks = !professionalTasks.isEmpty
        
        if !hasPersonalTasks || !hasProfessionalTasks {
            await loadTasks()
        }
    }
    
    /// Check if tasks are already loaded to avoid unnecessary API calls
    var hasTasksLoaded: Bool {
        return !personalTasks.isEmpty || !professionalTasks.isEmpty
    }
    
    private func loadTaskListsForAccount(_ kind: GoogleAuthManager.AccountKind) async {
        // Check cache first
        if let cachedLists = getCachedTaskLists(for: kind) {
            await MainActor.run {
                switch kind {
                case .personal: self.personalTaskLists = cachedLists
                case .professional: self.professionalTaskLists = cachedLists
                }
            }
            return
        }
        
        do {
            let taskLists = try await fetchTaskLists(for: kind)
            
            await MainActor.run {
                switch kind {
                case .personal: self.personalTaskLists = taskLists
                case .professional: self.professionalTaskLists = taskLists
                }
            }
            
            // Cache the task lists
            cacheTaskLists(taskLists, for: kind)
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load \(kind.rawValue) task lists: \(error.localizedDescription)"
            }
        }
    }
    
    private func loadTasksForAccount(_ kind: GoogleAuthManager.AccountKind) async {
        do {
            let taskLists = try await fetchTaskLists(for: kind)
            
            await MainActor.run {
                switch kind {
                case .personal: self.personalTaskLists = taskLists
                case .professional: self.professionalTaskLists = taskLists
                }
            }
            
            // PARALLEL task loading for all lists
            await withTaskGroup(of: Void.self) { group in
                for taskList in taskLists {
                    group.addTask {
                        do {
                            let tasks = try await self.fetchTasks(for: kind, taskListId: taskList.id)
                            await MainActor.run {
                                switch kind {
                                case .personal: self.personalTasks[taskList.id] = tasks
                                case .professional: self.professionalTasks[taskList.id] = tasks
                                }
                            }
                        } catch {
                            await MainActor.run {
                                self.errorMessage = "Failed to load tasks for \(taskList.title): \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load \(kind.rawValue) tasks: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Task List Caching Methods
    private func getCachedTaskLists(for kind: GoogleAuthManager.AccountKind) -> [GoogleTaskList]? {
        guard let timestamp = taskListCacheTimestamps[kind],
              Date().timeIntervalSince(timestamp) < taskListCacheTimeout,
              let cached = cachedTaskLists[kind] else {
            return nil
        }
        return cached
    }
    
    private func cacheTaskLists(_ taskLists: [GoogleTaskList], for kind: GoogleAuthManager.AccountKind) {
        cachedTaskLists[kind] = taskLists
        taskListCacheTimestamps[kind] = Date()
    }
    
    /// Clears tasks and lists for the specified account kind (or all if nil)
    func clearTasks(for kind: GoogleAuthManager.AccountKind? = nil) {
        switch kind {
        case .some(.personal):
            personalTaskLists = []
            personalTasks = [:]
            clearCacheForAccount(.personal)
        case .some(.professional):
            professionalTaskLists = []
            professionalTasks = [:]
            clearCacheForAccount(.professional)
        case .none:
            personalTaskLists = []
            professionalTaskLists = []
            personalTasks = [:]
            professionalTasks = [:]
            cachedTasks.removeAll()
            cacheTimestamps.removeAll()
        }
    }
    
    // MARK: - Cache Helper Methods
    private func taskCacheKey(for kind: GoogleAuthManager.AccountKind, listId: String) -> String {
        return "\(kind.rawValue)_\(listId)"
    }
    
    private func getCachedTasks(for key: String) -> [GoogleTask]? {
        guard let timestamp = cacheTimestamps[key],
              Date().timeIntervalSince(timestamp) < cacheTimeout else {
            cachedTasks.removeValue(forKey: key)
            return nil
        }
        return cachedTasks[key]
    }
    
    private func cacheTasks(_ tasks: [GoogleTask], for key: String) {
        cachedTasks[key] = tasks
        cacheTimestamps[key] = Date()
    }
    
    private func clearCacheForAccount(_ kind: GoogleAuthManager.AccountKind) {
        let keysToRemove = cachedTasks.keys.filter { $0.hasPrefix(kind.rawValue) }
        for key in keysToRemove {
            cachedTasks.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
        }
        
        // Also clear filtered task caches for this account
        let filteredKeysToRemove = filteredTasksCache.keys.filter { $0.accountKind == kind.rawValue }
        for key in filteredKeysToRemove {
            filteredTasksCache.removeValue(forKey: key)
        }
    }
    
    private func clearAllFilteredCaches() {
        filteredTasksCache.removeAll()
    }
    
    
    private func fetchTaskLists(for kind: GoogleAuthManager.AccountKind) async throws -> [GoogleTaskList] {
        guard let accessToken = try await getAccessTokenThrows(for: kind) else {
            throw TasksError.notAuthenticated
        }
        
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TasksError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw TasksError.apiError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        
        let taskListsResponse = try decoder.decode(GoogleTaskListsResponse.self, from: data)
        
        // Log raw JSON response for visibility
        let _ = String(data: data, encoding: .utf8)
        
        // Log parsed summary (count, titles, ids)
        if let items = taskListsResponse.items {
            let _ = items.map { "\($0.title) (\($0.id))" }
        } else {
        }
        
        return taskListsResponse.items ?? []
    }
    
    private func fetchTasks(for kind: GoogleAuthManager.AccountKind, taskListId: String) async throws -> [GoogleTask] {
        let cacheKey = taskCacheKey(for: kind, listId: taskListId)
        
        // Check cache first
        if let cachedTasks = getCachedTasks(for: cacheKey) {
            return cachedTasks
        }
        
        // Fetch from API if not cached
        guard let accessToken = try await getAccessTokenThrows(for: kind) else {
            throw TasksError.notAuthenticated
        }
        
        // Fetch all pages of tasks
        var allTasks: [GoogleTask] = []
        var pageToken: String? = nil
        var pageCount = 0
        
        repeat {
            pageCount += 1
            
            // Build URL with optional pageToken
            var urlString = "https://tasks.googleapis.com/tasks/v1/lists/\(taskListId)/tasks?showCompleted=true&showHidden=true&maxResults=100"
            if let pageToken = pageToken {
                urlString += "&pageToken=\(pageToken)"
            }
            
            guard let url = URL(string: urlString) else {
                throw TasksError.invalidResponse
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TasksError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                throw TasksError.apiError(httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            decoder.dateDecodingStrategy = .formatted(dateFormatter)
            
            let tasksResponse = try decoder.decode(GoogleTasksResponse.self, from: data)
            
            // Add tasks from this page
            if let items = tasksResponse.items {
                allTasks.append(contentsOf: items)
            }
            
            // Check if there are more pages
            pageToken = tasksResponse.nextPageToken
            
            // Safety check to prevent infinite loops (max 50 pages = 5000 tasks)
            if pageCount > 50 {
                print("⚠️ WARNING: Reached maximum page limit (50 pages) for task list \(taskListId)")
                break
            }
        } while pageToken != nil
        
        
        // Cache the complete results
        cacheTasks(allTasks, for: cacheKey)
        
        return allTasks
    }
    
    private func getAccessTokenThrows(for kind: GoogleAuthManager.AccountKind) async throws -> String? {
        do {
            let token = try await authManager.getAccessToken(for: kind)
            return token
        } catch {
            throw TasksError.authError(error.localizedDescription)
        }
    }
    
    func toggleTaskCompletion(_ task: GoogleTask, in listId: String, for kind: GoogleAuthManager.AccountKind) async {
        let newStatus = task.isCompleted ? "needsAction" : "completed"
        
        // Google Tasks API expects RFC 3339 format in UTC
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let now = Date()
        let updatedTimestamp = formatter.string(from: now)
        
        // Set completion timestamp when marking as completed, clear when marking incomplete
        let completedTimestamp: String?
        if newStatus == "completed" {
            completedTimestamp = updatedTimestamp
        } else {
            completedTimestamp = nil
        }
        
        let updatedTask = GoogleTask(
            id: task.id,
            title: task.title,
            notes: task.notes,
            status: newStatus,
            due: task.due,
            completed: completedTimestamp,
            updated: updatedTimestamp
        )
        
        // Update the task first
        await updateTask(updatedTask, in: listId, for: kind)
        

    }
    
    func updateTask(_ task: GoogleTask, in listId: String, for kind: GoogleAuthManager.AccountKind) async {
        // OPTIMISTIC UPDATE: Update UI immediately for instant feedback
        let originalTask = await getOriginalTask(task.id, from: listId, for: kind)
        
        await MainActor.run {
            switch kind {
            case .personal:
                if var tasks = self.personalTasks[listId] {
                    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[index] = task
                        self.personalTasks[listId] = tasks
                    }
                }
            case .professional:
                if var tasks = self.professionalTasks[listId] {
                    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[index] = task
                        self.professionalTasks[listId] = tasks
                    }
                }
            }
        }
        
        // BACKGROUND SYNC: Update server in background
        Task {
            do {
                guard let accessToken = try await getAccessTokenThrows(for: kind) else {
                    throw TasksError.notAuthenticated
                }
                
                let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(listId)/tasks/\(task.id)")!
                var request = URLRequest(url: url)
                request.httpMethod = "PATCH"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                var requestBody: [String: Any] = [
                    "title": task.title,
                    "status": task.status,
                    "updated": task.updated as Any
                ]
                
                // Include completed timestamp if task is completed
                if let completed = task.completed {
                    requestBody["completed"] = completed
                } else {
                    // Explicitly clear completed timestamp on the server
                    requestBody["completed"] = NSNull()
                }
                
                if let notes = task.notes {
                    requestBody["notes"] = notes
                }
                
                if let due = task.due {
                    // Ensure due date is in RFC 3339 format
                    if due.count == 10 && due.contains("-") && !due.contains("T") {
                        requestBody["due"] = "\(due)T00:00:00.000Z"
                    } else {
                        requestBody["due"] = due
                    }
                } else {
                    // Explicitly clear due date on the server
                    requestBody["due"] = NSNull()
                }
                
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TasksError.invalidResponse
                }
                
                if httpResponse.statusCode != 200 {
                    throw TasksError.apiError(httpResponse.statusCode)
                }
                
                // Clear cache for this account to ensure fresh data on next load
                clearCacheForAccount(kind)
                
                // Reload tasks to get the latest state
                await loadTasks()
                
            } catch {
                // REVERT OPTIMISTIC UPDATE on error
                if let original = originalTask {
                    await MainActor.run {
                        switch kind {
                        case .personal:
                            if var tasks = self.personalTasks[listId] {
                                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                    tasks[index] = original
                                    self.personalTasks[listId] = tasks
                                }
                            }
                        case .professional:
                            if var tasks = self.professionalTasks[listId] {
                                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                    tasks[index] = original
                                    self.professionalTasks[listId] = tasks
                                }
                            }
                        }
                    }
                }
                await MainActor.run {
                    self.errorMessage = "Failed to update task: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Helper method to get original task for rollback
    private func getOriginalTask(_ taskId: String, from listId: String, for kind: GoogleAuthManager.AccountKind) async -> GoogleTask? {
        return await MainActor.run {
            switch kind {
            case .personal:
                return personalTasks[listId]?.first { $0.id == taskId }
            case .professional:
                return professionalTasks[listId]?.first { $0.id == taskId }
            }
        }
    }
    
    func deleteTask(_ task: GoogleTask, from listId: String, for kind: GoogleAuthManager.AccountKind) async {
        // OPTIMISTIC DELETE: Remove from UI immediately
        await MainActor.run {
            switch kind {
            case .personal:
                self.personalTasks[listId]?.removeAll { $0.id == task.id }
            case .professional:
                self.professionalTasks[listId]?.removeAll { $0.id == task.id }
            }
        }
        
        // BACKGROUND SYNC: Delete from server in background
        Task {
            do {
                try await deleteTaskFromServer(task, from: listId, for: kind)
            } catch {
                // REVERT OPTIMISTIC DELETE on error - restore the task
                await MainActor.run {
                    switch kind {
                    case .personal:
                        if self.personalTasks[listId] != nil {
                            self.personalTasks[listId]?.append(task)
                        } else {
                            self.personalTasks[listId] = [task]
                        }
                    case .professional:
                        if self.professionalTasks[listId] != nil {
                            self.professionalTasks[listId]?.append(task)
                        } else {
                            self.professionalTasks[listId] = [task]
                        }
                    }
                    self.errorMessage = "Failed to delete task: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deleteTaskFromServer(_ task: GoogleTask, from listId: String, for kind: GoogleAuthManager.AccountKind) async throws {
        print("🗑️ deleteTaskFromServer: Deleting task '\(task.title)' (ID: \(task.id)) from list \(listId)")
        
        guard let accessToken = try await getAccessTokenThrows(for: kind) else {
            print("❌ deleteTaskFromServer: No access token for \(kind)")
            throw TasksError.notAuthenticated
        }
        
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(listId)/tasks/\(task.id)")!
        print("🗑️ deleteTaskFromServer: URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ deleteTaskFromServer: Invalid response type")
            throw TasksError.invalidResponse
        }
        
        print("🗑️ deleteTaskFromServer: HTTP Status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 204 {
            if let errorData = String(data: data, encoding: .utf8) {
                print("❌ deleteTaskFromServer: Error response: \(errorData)")
            }
            print("❌ deleteTaskFromServer: API error with status \(httpResponse.statusCode)")
            throw TasksError.apiError(httpResponse.statusCode)
        }
        
        print("✅ deleteTaskFromServer: Success! Task deleted")
    }
    
    func moveTask(_ updatedTask: GoogleTask, from sourceListId: String, to targetListId: String, for kind: GoogleAuthManager.AccountKind) async {
        print("🔄 moveTask: Starting move operation")
        print("   - Task: '\(updatedTask.title)' (ID: \(updatedTask.id))")
        print("   - From: \(sourceListId) -> To: \(targetListId)")
        print("   - Account: \(kind)")
        
        // First, get the original task from local state to ensure we have the correct server ID
        let originalTask = await MainActor.run {
            switch kind {
            case .personal:
                return personalTasks[sourceListId]?.first { $0.id == updatedTask.id }
            case .professional:
                return professionalTasks[sourceListId]?.first { $0.id == updatedTask.id }
            }
        }
        
        // CRITICAL: We MUST find the original task in local state to get the correct server ID
        guard let taskToDelete = originalTask else {
            print("❌ moveTask: Cannot find original task in local state!")
            print("   - Task ID in updatedTask: \(updatedTask.id)")
            print("   - Source list: \(sourceListId)")
            await MainActor.run {
                self.errorMessage = "Cannot find original task to move"
            }
            return
        }
        
        print("✅ moveTask: Found original task with ID: \(taskToDelete.id)")
        
        // Check if this is a local UUID (not synced to server yet)
        let isLocalUUID = taskToDelete.id.count > 20 && taskToDelete.id.contains("-")
        if isLocalUUID {
            print("   ⚠️ WARNING: Task appears to be local UUID (not synced to server)")
            print("   - This task may not exist on the server yet")
            print("   - Will attempt to create in target and remove from local state only")
        }
        
        if taskToDelete.id != updatedTask.id {
            print("   ⚠️ WARNING: Task ID mismatch detected!")
            print("   - updatedTask.id: \(updatedTask.id)")
            print("   - originalTask.id: \(taskToDelete.id)")
            print("   - Using original task ID for deletion: \(taskToDelete.id)")
        }
        
        var newTask: GoogleTask?
        do {
            // First create the task in the target list (returns new task with server-assigned ID)
            print("🔄 moveTask: Step 1 - Creating task in target list...")
            newTask = try await createTaskOnServer(updatedTask, in: targetListId, for: kind)
            print("✅ moveTask: Step 1 - Success! New task ID: \(newTask?.id ?? "nil")")
            
            // Then delete from source list using original task ID (from server)
            print("🔄 moveTask: Step 2 - Deleting task from source list...")
            
            // Check if this is a local UUID - if so, skip server deletion
            let isLocalUUID = taskToDelete.id.count > 20 && taskToDelete.id.contains("-")
            if isLocalUUID {
                print("   - Skipping server deletion (local UUID - task not on server)")
            } else {
                try await deleteTaskFromServer(taskToDelete, from: sourceListId, for: kind)
                print("✅ moveTask: Step 2 - Success! Deleted from source list")
            }
            
            // Update local state using the new task (with correct server ID)
            guard let taskToAdd = newTask else { 
                print("❌ moveTask: No new task returned from server!")
                return 
            }
            
            print("🔄 moveTask: Step 3 - Updating local state...")
            await MainActor.run {
                // Remove from source list using original task ID (the one we deleted from server)
                let originalTaskId = taskToDelete.id
                switch kind {
                case .personal:
                    let beforeRemoveCount = self.personalTasks[sourceListId]?.count ?? 0
                    self.personalTasks[sourceListId]?.removeAll { $0.id == originalTaskId }
                    let afterRemoveCount = self.personalTasks[sourceListId]?.count ?? 0
                    print("   - Personal: Removed from source list (\(beforeRemoveCount) -> \(afterRemoveCount))")
                    
                    // Add to target list using new task (with server ID)
                    let beforeAddCount = self.personalTasks[targetListId]?.count ?? 0
                    if self.personalTasks[targetListId] != nil {
                        self.personalTasks[targetListId]?.append(taskToAdd)
                    } else {
                        self.personalTasks[targetListId] = [taskToAdd]
                    }
                    let afterAddCount = self.personalTasks[targetListId]?.count ?? 0
                    print("   - Personal: Added to target list (\(beforeAddCount) -> \(afterAddCount))")
                    
                case .professional:
                    let beforeRemoveCount = self.professionalTasks[sourceListId]?.count ?? 0
                    self.professionalTasks[sourceListId]?.removeAll { $0.id == originalTaskId }
                    let afterRemoveCount = self.professionalTasks[sourceListId]?.count ?? 0
                    print("   - Professional: Removed from source list (\(beforeRemoveCount) -> \(afterRemoveCount))")
                    
                    // Add to target list using new task (with server ID)
                    let beforeAddCount = self.professionalTasks[targetListId]?.count ?? 0
                    if self.professionalTasks[targetListId] != nil {
                        self.professionalTasks[targetListId]?.append(taskToAdd)
                    } else {
                        self.professionalTasks[targetListId] = [taskToAdd]
                    }
                    let afterAddCount = self.professionalTasks[targetListId]?.count ?? 0
                    print("   - Professional: Added to target list (\(beforeAddCount) -> \(afterAddCount))")
                }
                
                // Clear caches to ensure UI refreshes
                print("🔄 moveTask: Step 4 - Clearing caches...")
                self.clearCacheForAccount(kind)
                self.clearAllFilteredCaches()
                print("✅ moveTask: Step 4 - Caches cleared")
            }
            print("✅ moveTask: Complete! Task successfully moved")
            
        } catch {
            print("❌ moveTask: Error occurred: \(error.localizedDescription)")
            print("   - Error type: \(type(of: error))")
            
            // If deletion failed, clean up the task we created in the target list
            if let createdTask = newTask {
                print("🧹 moveTask: Cleaning up created task in target list...")
                do {
                    try await deleteTaskFromServer(createdTask, from: targetListId, for: kind)
                    print("✅ moveTask: Cleanup successful")
                } catch {
                    // Log cleanup error but don't throw - we already have the original error
                    print("⚠️ moveTask: Failed to clean up moved task after error: \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                self.errorMessage = "Failed to move task: \(error.localizedDescription)"
            }
        }
    }
    
    func crossAccountMoveTask(_ updatedTask: GoogleTask, from source: (GoogleAuthManager.AccountKind, String), to target: (GoogleAuthManager.AccountKind, String)) async {
        print("🔄 crossAccountMoveTask: Starting cross-account move operation")
        print("   - Task: '\(updatedTask.title)' (ID: \(updatedTask.id))")
        print("   - From: \(source.0)/\(source.1) -> To: \(target.0)/\(target.1)")
        
        // First, get the original task from local state to ensure we have the correct server ID
        let originalTask = await MainActor.run {
            switch source.0 {
            case .personal:
                return personalTasks[source.1]?.first { $0.id == updatedTask.id }
            case .professional:
                return professionalTasks[source.1]?.first { $0.id == updatedTask.id }
            }
        }
        
        // CRITICAL: We MUST find the original task in local state to get the correct server ID
        guard let taskToDelete = originalTask else {
            print("❌ crossAccountMoveTask: Cannot find original task in local state!")
            print("   - Task ID in updatedTask: \(updatedTask.id)")
            print("   - Source list: \(source.1)")
            await MainActor.run {
                self.errorMessage = "Cannot find original task to move"
            }
            return
        }
        
        print("✅ crossAccountMoveTask: Found original task with ID: \(taskToDelete.id)")
        
        // Check if this is a local UUID (not synced to server yet)
        let isLocalUUID = taskToDelete.id.count > 20 && taskToDelete.id.contains("-")
        if isLocalUUID {
            print("   ⚠️ WARNING: Task appears to be local UUID (not synced to server)")
            print("   - This task may not exist on the server yet")
            print("   - Will attempt to create in target and remove from local state only")
        }
        
        if taskToDelete.id != updatedTask.id {
            print("   ⚠️ WARNING: Task ID mismatch detected!")
            print("   - updatedTask.id: \(updatedTask.id)")
            print("   - originalTask.id: \(taskToDelete.id)")
            print("   - Using original task ID for deletion: \(taskToDelete.id)")
        }
        
        var newTask: GoogleTask?
        do {
            // First create the task in the target account (returns new task with server-assigned ID)
            print("🔄 crossAccountMoveTask: Step 1 - Creating task in target account...")
            newTask = try await createTaskOnServer(updatedTask, in: target.1, for: target.0)
            print("✅ crossAccountMoveTask: Step 1 - Success! New task ID: \(newTask?.id ?? "nil")")
            
            // Then delete from source account using original task ID (from server)
            print("🔄 crossAccountMoveTask: Step 2 - Deleting task from source account...")
            
            // Check if this is a local UUID - if so, skip server deletion
            let isLocalUUID = taskToDelete.id.count > 20 && taskToDelete.id.contains("-")
            if isLocalUUID {
                print("   - Skipping server deletion (local UUID - task not on server)")
            } else {
                try await deleteTaskFromServer(taskToDelete, from: source.1, for: source.0)
                print("✅ crossAccountMoveTask: Step 2 - Success! Deleted from source account")
            }
            
            // Update local state using the new task (with correct server ID)
            guard let taskToAdd = newTask else { 
                print("❌ crossAccountMoveTask: No new task returned from server!")
                return 
            }
            
            print("🔄 crossAccountMoveTask: Step 3 - Updating local state...")
            await MainActor.run {
                // Remove from source account using original task ID (the one we deleted from server)
                let originalTaskId = taskToDelete.id
                switch source.0 {
                case .personal:
                    let beforeRemoveCount = self.personalTasks[source.1]?.count ?? 0
                    self.personalTasks[source.1]?.removeAll { $0.id == originalTaskId }
                    let afterRemoveCount = self.personalTasks[source.1]?.count ?? 0
                    print("   - Personal: Removed from source list (\(beforeRemoveCount) -> \(afterRemoveCount))")
                case .professional:
                    let beforeRemoveCount = self.professionalTasks[source.1]?.count ?? 0
                    self.professionalTasks[source.1]?.removeAll { $0.id == originalTaskId }
                    let afterRemoveCount = self.professionalTasks[source.1]?.count ?? 0
                    print("   - Professional: Removed from source list (\(beforeRemoveCount) -> \(afterRemoveCount))")
                }
                
                // Add to target account using new task (with server ID)
                switch target.0 {
                case .personal:
                    let beforeAddCount = self.personalTasks[target.1]?.count ?? 0
                    if self.personalTasks[target.1] != nil {
                        self.personalTasks[target.1]?.append(taskToAdd)
                    } else {
                        self.personalTasks[target.1] = [taskToAdd]
                    }
                    let afterAddCount = self.personalTasks[target.1]?.count ?? 0
                    print("   - Personal: Added to target list (\(beforeAddCount) -> \(afterAddCount))")
                case .professional:
                    let beforeAddCount = self.professionalTasks[target.1]?.count ?? 0
                    if self.professionalTasks[target.1] != nil {
                        self.professionalTasks[target.1]?.append(taskToAdd)
                    } else {
                        self.professionalTasks[target.1] = [taskToAdd]
                    }
                    let afterAddCount = self.professionalTasks[target.1]?.count ?? 0
                    print("   - Professional: Added to target list (\(beforeAddCount) -> \(afterAddCount))")
                }
                
                // Clear caches to ensure UI refreshes
                print("🔄 crossAccountMoveTask: Step 4 - Clearing caches...")
                self.clearCacheForAccount(source.0)
                self.clearCacheForAccount(target.0)
                self.clearAllFilteredCaches()
                print("✅ crossAccountMoveTask: Step 4 - Caches cleared")
            }
            print("✅ crossAccountMoveTask: Complete! Task successfully moved across accounts")
            
        } catch {
            print("❌ crossAccountMoveTask: Error occurred: \(error.localizedDescription)")
            print("   - Error type: \(type(of: error))")
            
            // If deletion failed, clean up the task we created in the target account
            if let createdTask = newTask {
                print("🧹 crossAccountMoveTask: Cleaning up created task in target account...")
                do {
                    try await deleteTaskFromServer(createdTask, from: target.1, for: target.0)
                    print("✅ crossAccountMoveTask: Cleanup successful")
                } catch {
                    // Log cleanup error but don't throw - we already have the original error
                    print("⚠️ crossAccountMoveTask: Failed to clean up moved task after error: \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                self.errorMessage = "Failed to move task across accounts: \(error.localizedDescription)"
            }
        }
    }
    
    func createTaskOnServer(_ task: GoogleTask, in listId: String, for kind: GoogleAuthManager.AccountKind) async throws -> GoogleTask {
        print("📝 createTaskOnServer: Creating task '\(task.title)' in list \(listId)")
        
        guard let accessToken = try await getAccessTokenThrows(for: kind) else {
            print("❌ createTaskOnServer: No access token for \(kind)")
            throw TasksError.notAuthenticated
        }
        
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(listId)/tasks")!
        print("📝 createTaskOnServer: URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var requestBody: [String: Any] = [
            "title": task.title,
            "status": task.status
        ]
        
        if let notes = task.notes {
            requestBody["notes"] = notes
        }
        
        if let due = task.due {
            // Ensure due date is in RFC 3339 format
            if due.count == 10 && due.contains("-") && !due.contains("T") {
                requestBody["due"] = "\(due)T00:00:00.000Z"
            } else {
                requestBody["due"] = due
            }
        }
        
        print("📝 createTaskOnServer: Request body: \(requestBody)")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ createTaskOnServer: Invalid response type")
            throw TasksError.invalidResponse
        }
        
        print("📝 createTaskOnServer: HTTP Status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            if let errorData = String(data: data, encoding: .utf8) {
                print("❌ createTaskOnServer: Error response: \(errorData)")
            }
            print("❌ createTaskOnServer: API error with status \(httpResponse.statusCode)")
            throw TasksError.apiError(httpResponse.statusCode)
        }
        
        // Parse response to get the created task with server ID
        let createdTask = try JSONDecoder().decode(GoogleTask.self, from: data)
        print("✅ createTaskOnServer: Success! Created task with ID: \(createdTask.id)")
        return createdTask
    }
    
    func createTaskList(title: String, for kind: GoogleAuthManager.AccountKind) async -> String? {
        do {
            guard let accessToken = try await getAccessTokenThrows(for: kind) else {
                throw TasksError.notAuthenticated
            }
            
            let url = URL(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody: [String: Any] = ["title": title]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TasksError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                throw TasksError.apiError(httpResponse.statusCode)
            }
            
            let taskList = try JSONDecoder().decode(GoogleTaskList.self, from: data)
            
            // Update local state
            await MainActor.run {
                switch kind {
                case .personal:
                    self.personalTaskLists.append(taskList)
                    self.personalTasks[taskList.id] = []
                    // Save updated order
                    saveTaskListOrder(personalTaskLists.map { $0.id }, for: .personal)
                case .professional:
                    self.professionalTaskLists.append(taskList)
                    self.professionalTasks[taskList.id] = []
                    // Save updated order
                    saveTaskListOrder(professionalTaskLists.map { $0.id }, for: .professional)
                }
            }
            
            return taskList.id
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to create task list: \(error.localizedDescription)"
            }
            return nil
        }
    }
    
    func renameTaskList(listId: String, newTitle: String, for kind: GoogleAuthManager.AccountKind) async {
        do {
            guard let accessToken = try await getAccessTokenThrows(for: kind) else {
                throw TasksError.notAuthenticated
            }
            
            let url = URL(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists/\(listId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody: [String: Any] = ["title": newTitle]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TasksError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                throw TasksError.apiError(httpResponse.statusCode)
            }
            
            // Update local state
            await MainActor.run {
                switch kind {
                case .personal:
                    if let index = self.personalTaskLists.firstIndex(where: { $0.id == listId }) {
                        let updatedList = GoogleTaskList(id: listId, title: newTitle, updated: self.personalTaskLists[index].updated)
                        self.personalTaskLists[index] = updatedList
                    }
                case .professional:
                    if let index = self.professionalTaskLists.firstIndex(where: { $0.id == listId }) {
                        let updatedList = GoogleTaskList(id: listId, title: newTitle, updated: self.professionalTaskLists[index].updated)
                        self.professionalTaskLists[index] = updatedList
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to rename task list: \(error.localizedDescription)"
            }
        }
    }
    
    func createTask(
        title: String,
        notes: String?,
        dueDate: Date?,
        in listId: String,
        for kind: GoogleAuthManager.AccountKind,
        startTime: Date? = nil,
        endTime: Date? = nil,
        isAllDay: Bool = true
    ) async {
        
        let dueDateString: String?
        if let dueDate = dueDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dueDateString = formatter.string(from: dueDate)
            
        } else {
            dueDateString = nil
        }
        
        let task = GoogleTask(
            id: UUID().uuidString, // Temporary ID, will be overwritten by server
            title: title,
            notes: notes,
            status: "needsAction",
            due: dueDateString,
            completed: nil,
            updated: nil
        )
        
        // OPTIMISTIC CREATE: Add to UI immediately for instant feedback
        await MainActor.run {
            switch kind {
            case .personal:
                if personalTasks[listId] != nil {
                    personalTasks[listId]?.append(task)
                } else {
                    personalTasks[listId] = [task]
                }
            case .professional:
                if professionalTasks[listId] != nil {
                    professionalTasks[listId]?.append(task)
                } else {
                    professionalTasks[listId] = [task]
                }
            }
        }
        
        // BACKGROUND SYNC: Create on server in background
        Task {
            do {
                // Get the created task with real server ID
                let createdTask = try await createTaskOnServer(task, in: listId, for: kind)
                
                // Save time window if due date and times are provided
                if let dueDate = dueDate, let startTime = startTime, let endTime = endTime {
                    TaskTimeWindowManager.shared.saveTimeWindow(
                        taskId: createdTask.id,
                        startTime: startTime,
                        endTime: endTime,
                        isAllDay: isAllDay
                    )
                }
                
                // Replace temporary task with server task (has correct ID)
                await MainActor.run {
                    switch kind {
                    case .personal:
                        if var tasks = personalTasks[listId] {
                            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                // Replace temporary task with server task that has real ID
                                tasks[index] = createdTask
                                personalTasks[listId] = tasks
                            }
                        }
                    case .professional:
                        if var tasks = professionalTasks[listId] {
                            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                // Replace temporary task with server task that has real ID
                                tasks[index] = createdTask
                                professionalTasks[listId] = tasks
                            }
                        }
                    }
                }
            } catch {
                // REVERT OPTIMISTIC CREATE on error - remove the temporary task
                await MainActor.run {
                    switch kind {
                    case .personal:
                        personalTasks[listId]?.removeAll { $0.id == task.id }
                    case .professional:
                        professionalTasks[listId]?.removeAll { $0.id == task.id }
                    }
                    self.errorMessage = "Failed to create task: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func updateTaskListOrder(_ newOrder: [GoogleTaskList], for kind: GoogleAuthManager.AccountKind) async {
        
        await MainActor.run {
            switch kind {
            case .personal:
                self.personalTaskLists = newOrder
            case .professional:
                self.professionalTaskLists = newOrder
            }
        }
        

        // Save the order locally since Google Tasks API doesn't support task list ordering
        saveTaskListOrder(newOrder.map { $0.id }, for: kind)
    }

    private func saveTaskListOrder(_ order: [String], for kind: GoogleAuthManager.AccountKind) {
        // No-op: we now rely on the Google API's array order
    }

    private func loadTaskListOrder(for kind: GoogleAuthManager.AccountKind) -> [String]? {
        // No-op: no saved order used
        return nil
    }

    private func applySavedOrder(_ taskLists: [GoogleTaskList], for kind: GoogleAuthManager.AccountKind) -> [GoogleTaskList] {
        // No-op: keep API order
        return taskLists
    }
    
    func deleteAllCompletedTasks() async {
        do {
            // Delete from personal account if linked
            if authManager.isLinked(kind: .personal) {
                for (listId, tasks) in personalTasks {
                    let completedTasks = tasks.filter { $0.isCompleted }
                    for task in completedTasks {
                        try await deleteTaskFromServer(task, from: listId, for: .personal)
                    }
                }
            }
            
            // Delete from professional account if linked
            if authManager.isLinked(kind: .professional) {
                for (listId, tasks) in professionalTasks {
                    let completedTasks = tasks.filter { $0.isCompleted }
                    for task in completedTasks {
                        try await deleteTaskFromServer(task, from: listId, for: .professional)
                    }
                }
            }
            
            // Refresh tasks after deletion
            await loadTasks(forceClear: true)
        } catch {
            errorMessage = "Failed to delete completed tasks"
        }
    }
    
    func moveTaskList(_ listId: String, toAccount targetAccount: GoogleAuthManager.AccountKind) async {
        await MainActor.run {
            if let listIndex = personalTaskLists.firstIndex(where: { $0.id == listId }) {
                let taskList = personalTaskLists.remove(at: listIndex)
                professionalTaskLists.append(taskList)
                

                // Update orders for both accounts
                saveTaskListOrder(personalTaskLists.map { $0.id }, for: .personal)
                saveTaskListOrder(professionalTaskLists.map { $0.id }, for: .professional)
            } else if let listIndex = professionalTaskLists.firstIndex(where: { $0.id == listId }) {
                let taskList = professionalTaskLists.remove(at: listIndex)
                personalTaskLists.append(taskList)
                

                // Update orders for both accounts
                saveTaskListOrder(personalTaskLists.map { $0.id }, for: .personal)
                saveTaskListOrder(professionalTaskLists.map { $0.id }, for: .professional)
            }
        }
        // Here you would typically update the backend to reflect the account change
    }

    func deleteTaskList(listId: String, for kind: GoogleAuthManager.AccountKind) async {
        do {
            guard let accessToken = try await getAccessTokenThrows(for: kind) else {
                throw TasksError.notAuthenticated
            }

            let url = URL(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists/\(listId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TasksError.invalidResponse
            }

            if httpResponse.statusCode != 204 {
                throw TasksError.apiError(httpResponse.statusCode)
            }

            // Update local state
            await MainActor.run {
                switch kind {
                case .personal:
                    self.personalTaskLists.removeAll { $0.id == listId }
                    self.personalTasks.removeValue(forKey: listId)
                    // Save updated order
                    saveTaskListOrder(personalTaskLists.map { $0.id }, for: .personal)
                case .professional:
                    self.professionalTaskLists.removeAll { $0.id == listId }
                    self.professionalTasks.removeValue(forKey: listId)
                    // Save updated order
                    saveTaskListOrder(professionalTaskLists.map { $0.id }, for: .professional)
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to delete task list: \(error.localizedDescription)"
            }
        }
    }

    private func clearTaskListOrder(for kind: GoogleAuthManager.AccountKind) {
        let key = "taskListOrder_\(kind.rawValue)"
        UserDefaults.standard.removeObject(forKey: key)
    }
}

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

// MARK: - Tasks View
struct TasksView: View {
    @ObservedObject private var viewModel = DataManager.shared.tasksViewModel
    @ObservedObject private var calendarViewModel = DataManager.shared.calendarViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @ObservedObject private var navigationManager = NavigationManager.shared
    @State private var selectedFilter: TaskFilter = .day
    @State private var referenceDate: Date = Date()
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    
    // MARK: - Device-Aware Layout
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // Use an item-bound sheet selection to avoid first-click blank sheet
    struct TasksViewTaskSelection: Identifiable {
        let id = UUID()
        let task: GoogleTask
        let listId: String
        let accountKind: GoogleAuthManager.AccountKind
    }
    @State private var taskSheetSelection: TasksViewTaskSelection?
    @State private var showingAddItem = false
    // Personal/Professional task divider
    @State private var tasksPersonalWidth: CGFloat = 0
    @State private var isTasksDividerDragging = false
    @State private var showingTaskDetails = false
    @State private var showingNewTask = false
    @State private var showingAddEvent = false
    @State private var allSubfilter: AllTaskSubfilter = .all
    
    // MARK: - Filtered Tasks Caching
    @State private var cachedFilteredPersonalTasks: [String: [GoogleTask]] = [:]
    @State private var cachedFilteredProfessionalTasks: [String: [GoogleTask]] = [:]
    @State private var lastFilterState: String = "" // Tracks filter+date+prefs state
    
    // Navigation date picker state
    @State private var showingNavigationDatePicker = false
    @State private var selectedDateForNavigation = Date()
    
    // MARK: - Adaptive Layout Properties
    private var shouldUseStackedLayout: Bool {
        // Use stacked (vertical) layout on iPhone portrait for better space utilization
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    private var adaptiveSpacing: CGFloat {
        horizontalSizeClass == .compact ? 12 : 16
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 16
    }
    
    private var isCurrentToolbarPeriod: Bool {
        let cal = Calendar.mondayFirst
        switch selectedFilter {
        case .day:
            return cal.isDate(referenceDate, inSameDayAs: Date())
        case .week:
            if let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
               let end = cal.date(byAdding: .day, value: 6, to: start) {
                return referenceDate >= start && referenceDate <= end
            }
            return false
        case .month:
            return cal.isDate(referenceDate, equalTo: Date(), toGranularity: .month)
        case .year:
            return cal.isDate(referenceDate, equalTo: Date(), toGranularity: .year)
        case .all:
            return false
        }
    }
    
    // MARK: - Local Filtering (No API calls)
    private var filteredPersonalTasks: [String: [GoogleTask]] {
        logDebug("📋 Personal tasks loaded: \(viewModel.personalTasks.count) lists")
        return getCachedFilteredTasks(for: viewModel.personalTasks, accountKind: .personal)
    }
    
    private var filteredProfessionalTasks: [String: [GoogleTask]] {
        logDebug("📋 Professional tasks loaded: \(viewModel.professionalTasks.count) lists")
        return getCachedFilteredTasks(for: viewModel.professionalTasks, accountKind: .professional)
    }
    
    private func getCachedFilteredTasks(for tasksDict: [String: [GoogleTask]], accountKind: GoogleAuthManager.AccountKind) -> [String: [GoogleTask]] {
        // Generate cache key from current filter state
        let currentFilterState = "\(selectedFilter.rawValue)-\(allSubfilter.rawValue)-\(referenceDate.timeIntervalSince1970)-\(appPrefs.hideCompletedTasks)"
        
        // Check if we can use cached results
        let cacheIsValid = lastFilterState == currentFilterState
        let cachedResults = accountKind == .personal ? cachedFilteredPersonalTasks : cachedFilteredProfessionalTasks
        
        // Return cached results if valid and non-empty, or if input is empty
        if cacheIsValid && !cachedResults.isEmpty {
            return cachedResults
        }
        
        // Otherwise, compute filtered tasks
        let filtered = filterTasks(tasksDict)
        
        // Update cache
        DispatchQueue.main.async {
            self.lastFilterState = currentFilterState
            if accountKind == .personal {
                self.cachedFilteredPersonalTasks = filtered
            } else {
                self.cachedFilteredProfessionalTasks = filtered
            }
        }
        
        return filtered
    }
    
    // Direct filtering function that bypasses caching - like day views
    private func getDirectFilteredTasks(for tasksDict: [String: [GoogleTask]], accountKind: GoogleAuthManager.AccountKind) -> [String: [GoogleTask]] {
        let result = filterTasks(tasksDict)
        logDebug("🔍 Direct filtering result: \(result.count) lists")
        return result
    }
    
    private func filterTasks(_ tasksDict: [String: [GoogleTask]]) -> [String: [GoogleTask]] {
        return tasksDict.mapValues { tasks in
            filterTasksList(tasks)
        }
    }
    
    private func filterTasksList(_ tasks: [GoogleTask]) -> [GoogleTask] {
        let calendar = Calendar.mondayFirst
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        
        var filteredTasks = tasks
        
        // Debug logging
        logDebug("🔍 Filtering \(tasks.count) tasks with filter: \(selectedFilter.rawValue), subfilter: \(allSubfilter.rawValue), referenceDate: \(referenceDate)")
        
        // Apply subfilter when in "All"
        if selectedFilter == .all {
            filteredTasks = applyAllSubfilter(filteredTasks, calendar: calendar, startOfToday: startOfToday)
        } else {
            // Apply time-based filter
            filteredTasks = applyTimeBasedFilter(filteredTasks, calendar: calendar, now: now, startOfToday: startOfToday)
        }
        
        logDebug("🔍 Filtered to \(filteredTasks.count) tasks")
        
        return filteredTasks
    }
    
    private func applyAllSubfilter(_ tasks: [GoogleTask], calendar: Calendar, startOfToday: Date) -> [GoogleTask] {
        var filteredTasks = tasks
        
        switch allSubfilter {
        case .all:
            break
        case .hasDueDate:
            filteredTasks = filteredTasks.filter { $0.dueDate != nil }
        case .noDueDate:
            filteredTasks = filteredTasks.filter { $0.dueDate == nil }
        case .pastDue:
            filteredTasks = filteredTasks.filter { task in
                if let due = task.dueDate {
                    return calendar.startOfDay(for: due) < startOfToday && !task.isCompleted
                }
                return false
            }
        case .completed:
            filteredTasks = filteredTasks.filter { $0.isCompleted }
        }
        
        // Hide completed tasks if setting is enabled
        if appPrefs.hideCompletedTasks {
            filteredTasks = filteredTasks.filter { !$0.isCompleted }
        }
        
        return filteredTasks
    }
    
    private func applyTimeBasedFilter(_ tasks: [GoogleTask], calendar: Calendar, now: Date, startOfToday: Date) -> [GoogleTask] {
        return tasks.filter { task in
            if task.isCompleted {
                return matchesCompletionDate(task, calendar: calendar)
            } else {
                return matchesDueDate(task, calendar: calendar, now: now, startOfToday: startOfToday)
            }
        }
    }
    
    private func matchesCompletionDate(_ task: GoogleTask, calendar: Calendar) -> Bool {
        guard let completionDate = task.completionDate else { return false }
        
        switch selectedFilter {
        case .day:
            return calendar.isDate(completionDate, inSameDayAs: referenceDate)
        case .week:
            return calendar.isDate(completionDate, equalTo: referenceDate, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(completionDate, equalTo: referenceDate, toGranularity: .month)
        case .year:
            return calendar.isDate(completionDate, equalTo: referenceDate, toGranularity: .year)
        case .all:
            return true
        }
    }
    
    private func matchesDueDate(_ task: GoogleTask, calendar: Calendar, now: Date, startOfToday: Date) -> Bool {
        guard let dueDate = task.dueDate else { return false }
        
        switch selectedFilter {
        case .day:
            // Show task on due date OR, if viewing today, show overdue (relative to today)
            let isDueOnViewedDate = calendar.isDate(dueDate, inSameDayAs: referenceDate)
            let isViewingToday = calendar.isDate(referenceDate, inSameDayAs: now)
            let startOfDueDate = calendar.startOfDay(for: dueDate)
            let isOverdueRelativeToToday = startOfDueDate < startOfToday
            return isDueOnViewedDate || (isViewingToday && isOverdueRelativeToToday)
        case .week:
            return calendar.isDate(dueDate, equalTo: referenceDate, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(dueDate, equalTo: referenceDate, toGranularity: .month)
        case .year:
            return calendar.isDate(dueDate, equalTo: referenceDate, toGranularity: .year)
        case .all:
            return true
        }
    }
    
    // MARK: - Stacked Layout for Mobile Portrait
    private func stackedTasksView(geometry: GeometryProxy) -> some View {
        ScrollView {
            VStack(spacing: adaptiveSpacing) {
                // Personal Tasks Section
                if authManager.isLinked(kind: .personal) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Personal")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(appPrefs.personalColor)
                            .padding(.horizontal, adaptivePadding)
                        
                        TasksComponent(
                            taskLists: viewModel.personalTaskLists,
                            tasksDict: getDirectFilteredTasks(for: viewModel.personalTasks, accountKind: .personal),
                            accentColor: appPrefs.personalColor,
                            accountType: .personal,
                            onTaskToggle: { task, listId in
                                Task {
                                    await viewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .personal)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await viewModel.updateTaskListOrder(newOrder, for: .personal)
                                }
                            },
                            horizontalCards: false,
                            isSingleDayView: selectedFilter == .day
                        )
                    }
                }
                
                // Professional Tasks Section
                if authManager.isLinked(kind: .professional) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Professional")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(appPrefs.professionalColor)
                            .padding(.horizontal, adaptivePadding)
                        
                        TasksComponent(
                            taskLists: viewModel.professionalTaskLists,
                            tasksDict: getDirectFilteredTasks(for: viewModel.professionalTasks, accountKind: .professional),
                            accentColor: appPrefs.professionalColor,
                            accountType: .professional,
                            onTaskToggle: { task, listId in
                                Task {
                                    await viewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                                }
                            },
                            onTaskDetails: { task, listId in
                                taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .professional)
                            },
                            onListRename: { listId, newName in
                                Task {
                                    await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                                }
                            },
                            onOrderChanged: { newOrder in
                                Task {
                                    await viewModel.updateTaskListOrder(newOrder, for: .professional)
                                }
                            },
                            horizontalCards: false,
                            isSingleDayView: selectedFilter == .day
                        )
                    }
                }
            }
            .padding(.horizontal, adaptivePadding)
            .padding(.vertical, adaptivePadding)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                if authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional) {
                    mainContent(geometry: geometry)
                } else {
                    noAccountsView
                }
            }
            .onAppear {
                // Initialize screen-dependent values
                if tasksPersonalWidth == 0 {
                    tasksPersonalWidth = geometry.size.width * 0.5
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .sidebarToggleHidden()
        .onAppear {
            Task {
                await viewModel.loadTasks()
            }
        }
        .sheet(item: $taskSheetSelection) { selection in
            TaskDetailsView(
                task: selection.task,
                taskListId: selection.listId,
                accountKind: selection.accountKind,
                accentColor: selection.accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: viewModel.personalTaskLists,
                professionalTaskLists: viewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: viewModel,
                onSave: { updatedTask in
                    Task { await viewModel.updateTask(updatedTask, in: selection.listId, for: selection.accountKind) }
                },
                onDelete: {
                    Task { await viewModel.deleteTask(selection.task, from: selection.listId, for: selection.accountKind) }
                },
                onMove: { updatedTask, newListId in
                    Task { await viewModel.moveTask(updatedTask, from: selection.listId, to: newListId, for: selection.accountKind) }
                },
                onCrossAccountMove: { updatedTask, targetAccount, targetListId in
                    Task { await viewModel.crossAccountMoveTask(updatedTask, from: (selection.accountKind, selection.listId), to: (targetAccount, targetListId)) }
                }
            )
        }
        .sheet(isPresented: $showingNewTask) {
            // Use the same UI as Task Details for creating a task
            let personalLinked = authManager.isLinked(kind: .personal)
            let _ = authManager.isLinked(kind: .professional)
            let defaultAccount: GoogleAuthManager.AccountKind = selectedAccountKind ?? (personalLinked ? .personal : .professional)
            let defaultLists = defaultAccount == .personal ? viewModel.personalTaskLists : viewModel.professionalTaskLists
            let defaultListId = defaultLists.first?.id ?? ""
            let newTask = GoogleTask(
                id: UUID().uuidString,
                title: "",
                notes: nil,
                status: "needsAction",
                due: nil,
                completed: nil,
                updated: nil
            )
            TaskDetailsView(
                task: newTask,
                taskListId: defaultListId,
                accountKind: defaultAccount,
                accentColor: defaultAccount == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                personalTaskLists: viewModel.personalTaskLists,
                professionalTaskLists: viewModel.professionalTaskLists,
                appPrefs: appPrefs,
                viewModel: viewModel,
                onSave: { _ in },
                onDelete: {},
                onMove: { _, _ in },
                onCrossAccountMove: { _, _, _ in },
                isNew: true
            )
        }
        .sheet(isPresented: $showingNavigationDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDateForNavigation,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .overlay(alignment: .topTrailing) {
                    HStack {
                        Button("Cancel") {
                            showingNavigationDatePicker = false
                        }
                        .padding(.leading)
                        
                        Spacer()
                        
                        Button("Done") {
                            navigateToDate(selectedDateForNavigation)
                            showingNavigationDatePicker = false
                        }
                        .padding(.trailing)
                    }
                    .padding(.top, 8)
                }
            }
            .presentationDetents([.large])
        }
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            GlobalNavBar()
                .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingAddEvent) {
            // Launch event creation modal from Tasks view
            AddItemView(
                currentDate: referenceDate,
                tasksViewModel: viewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs,
                showEventOnly: true
            )
        }
        .onAppear {
            // Load tasks on-demand when TasksView appears (performance optimization)
            Task {
                await viewModel.loadTasksOnDemand()
            }
            
            // Sync with navigation manager state when view appears
            if navigationManager.showingAllTasks {
                selectedFilter = .all
            } else {
                switch navigationManager.currentInterval {
                case .day:
                    selectedFilter = .day
                case .week:
                    selectedFilter = .week
                case .month:
                    selectedFilter = .month
                case .year:
                    selectedFilter = .year
                }
            }
            referenceDate = navigationManager.currentDate
            
            // Listen for external requests to show Add Task so behavior matches Calendar
            NotificationCenter.default.addObserver(forName: Notification.Name("LPV3_ShowAddTask"), object: nil, queue: .main) { _ in
                showingNewTask = true
            }
            // Listen for request to switch to All
            NotificationCenter.default.addObserver(forName: Notification.Name("ShowAllTasksRequested"), object: nil, queue: .main) { _ in
                selectedFilter = .all
                allSubfilter = .all
                referenceDate = Date()
                navigationManager.showingAllTasks = true
                // Clear the current interval since "All Tasks" doesn't correspond to a specific time interval
                // This ensures other icons (D, W, M, Y) are properly unhighlighted
            }
            // Listen for request to set All tasks subfilter
            NotificationCenter.default.addObserver(forName: Notification.Name("SetAllTasksSubfilter"), object: nil, queue: .main) { notification in
                if let subfilter = notification.object as? AllTaskSubfilter {
                    allSubfilter = subfilter
                    logDebug("🔄 Subfilter set to: \(subfilter.rawValue)")
                }
            }
            // Listen for request to filter tasks to current day (when coming from All Tasks filter)
            NotificationCenter.default.addObserver(forName: Notification.Name("FilterTasksToCurrentDay"), object: nil, queue: .main) { _ in
                selectedFilter = .day
                referenceDate = Date()
                navigationManager.showingAllTasks = false
                // Clear cache to ensure fresh filtering
                cachedFilteredPersonalTasks.removeAll()
                cachedFilteredProfessionalTasks.removeAll()
                lastFilterState = ""
                logDebug("🔄 Filter changed to day for current day from All Tasks")
            }
            // Listen for request to filter tasks to current week (when coming from All Tasks filter)
            NotificationCenter.default.addObserver(forName: Notification.Name("FilterTasksToCurrentWeek"), object: nil, queue: .main) { _ in
                selectedFilter = .week
                referenceDate = Date()
                navigationManager.showingAllTasks = false
                // Clear cache to ensure fresh filtering
                cachedFilteredPersonalTasks.removeAll()
                cachedFilteredProfessionalTasks.removeAll()
                lastFilterState = ""
                logDebug("🔄 Filter changed to week for current week from All Tasks")
            }
        }
        .onChange(of: selectedFilter) { _, newValue in
            logDebug("🔄 Filter changed to: \(newValue.rawValue)")
            // Clear cache when filter changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: allSubfilter) { _, newValue in
            logDebug("🔄 Subfilter changed to: \(newValue.rawValue)")
            // Clear cache when subfilter changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: referenceDate) { _, newValue in
            logDebug("🔄 Reference date changed to: \(newValue)")
            // Clear cache when reference date changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: appPrefs.hideCompletedTasks) { _, newValue in
            logDebug("🔄 Hide completed tasks changed to: \(newValue)")
            // Clear cache when hide completed tasks setting changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: navigationManager.currentInterval) { _, newValue in
            logDebug("🔄 Navigation interval changed to: \(newValue)")
            // Update selectedFilter based on navigation interval
            switch newValue {
            case .day:
                selectedFilter = .day
            case .week:
                selectedFilter = .week
            case .month:
                selectedFilter = .month
            case .year:
                selectedFilter = .year
            }
            // Update reference date to current date when interval changes
            referenceDate = Date()
            // Clear cache when interval changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
        .onChange(of: navigationManager.currentDate) { _, newValue in
            logDebug("🔄 Navigation date changed to: \(newValue)")
            referenceDate = newValue
            // Clear cache when date changes
            cachedFilteredPersonalTasks.removeAll()
            cachedFilteredProfessionalTasks.removeAll()
            lastFilterState = ""
        }
    }
    
    private func mainContent(geometry: GeometryProxy) -> some View {
        Group {
            if shouldUseStackedLayout {
                // Mobile portrait: Full-width stacked layout
                stackedTasksView(geometry: geometry)
            } else if appPrefs.tasksLayoutHorizontal {
                // Horizontal cards layout
                horizontalTasksView
            } else {
                // Vertical layout
                verticalTasksView(geometry: geometry)
            }
        }
    }
    
    private var horizontalTasksView: some View {
        VStack(spacing: 0) {
            // Personal Tasks
            if authManager.isLinked(kind: .personal) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal")
                        .font(.headline)
                        .foregroundColor(allSubfilter == .all ? appPrefs.personalColor : .primary)
                        .padding(.horizontal, 12)
                    TasksComponent(
                        taskLists: viewModel.personalTaskLists,
                        tasksDict: getDirectFilteredTasks(for: viewModel.personalTasks, accountKind: .personal),
                        accentColor: appPrefs.personalColor,
                        accountType: .personal,
                        onTaskToggle: { task, listId in
                            Task {
                                await viewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                            }
                        },
                        onTaskDetails: { task, listId in
                            taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .personal)
                        },
                        onListRename: { listId, newName in
                            Task {
                                await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                            }
                        },
                        onOrderChanged: { newOrder in
                            Task {
                                await viewModel.updateTaskListOrder(newOrder, for: .personal)
                            }
                        },
                        horizontalCards: true,
                        isSingleDayView: selectedFilter == .day
                    )
                }
            }
            
            // Professional Tasks
            if authManager.isLinked(kind: .professional) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Professional")
                        .font(.headline)
                        .foregroundColor(allSubfilter == .all ? appPrefs.professionalColor : .primary)
                        .padding(.horizontal, 12)
                    TasksComponent(
                        taskLists: viewModel.professionalTaskLists,
                        tasksDict: getDirectFilteredTasks(for: viewModel.professionalTasks, accountKind: .professional),
                        accentColor: appPrefs.professionalColor,
                        accountType: .professional,
                        onTaskToggle: { task, listId in
                            Task {
                                await viewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                            }
                        },
                        onTaskDetails: { task, listId in
                            taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .professional)
                        },
                        onListRename: { listId, newName in
                            Task {
                                await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                            }
                        },
                        onOrderChanged: { newOrder in
                            Task {
                                await viewModel.updateTaskListOrder(newOrder, for: .professional)
                            }
                        },
                        horizontalCards: true,
                        isSingleDayView: selectedFilter == .day
                    )
                }
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, adaptivePadding)
    }
    
    private func verticalTasksView(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Personal Tasks Column
            if authManager.isLinked(kind: .personal) {
                TasksComponent(
                    taskLists: viewModel.personalTaskLists,
                    tasksDict: getDirectFilteredTasks(for: viewModel.personalTasks, accountKind: .personal),
                    accentColor: appPrefs.personalColor,
                    accountType: .personal,
                    onTaskToggle: { task, listId in
                        Task {
                            await viewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .personal)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .personal)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await viewModel.updateTaskListOrder(newOrder, for: .personal)
                        }
                    },
                    horizontalCards: false,
                    isSingleDayView: selectedFilter == .day
                )
                .frame(width: authManager.isLinked(kind: .professional) ? tasksPersonalWidth : geometry.size.width, alignment: .topLeading)
            }
            
            // Vertical divider (only show if both accounts are linked and not on mobile)
            if authManager.isLinked(kind: .personal) && authManager.isLinked(kind: .professional) && !shouldUseStackedLayout {
                tasksViewDivider(geometry: geometry)
            }
            
            // Professional Tasks Column
            if authManager.isLinked(kind: .professional) {
                TasksComponent(
                    taskLists: viewModel.professionalTaskLists,
                    tasksDict: getDirectFilteredTasks(for: viewModel.professionalTasks, accountKind: .professional),
                    accentColor: appPrefs.professionalColor,
                    accountType: .professional,
                    onTaskToggle: { task, listId in
                        Task {
                            await viewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                        }
                    },
                    onTaskDetails: { task, listId in
                        taskSheetSelection = TasksViewTaskSelection(task: task, listId: listId, accountKind: .professional)
                    },
                    onListRename: { listId, newName in
                        Task {
                            await viewModel.renameTaskList(listId: listId, newTitle: newName, for: .professional)
                        }
                    },
                    onOrderChanged: { newOrder in
                        Task {
                            await viewModel.updateTaskListOrder(newOrder, for: .professional)
                        }
                    },
                    horizontalCards: false,
                    isSingleDayView: selectedFilter == .day
                )
                .frame(width: authManager.isLinked(kind: .personal) ? (geometry.size.width - tasksPersonalWidth - 8) : geometry.size.width, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, adaptivePadding)
    }
    
    private var noAccountsView: some View {
        VStack(spacing: 16) {
            Button(action: { NavigationManager.shared.showSettings() }) {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Link Your Google Account")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Connect your Google account to view and manage your calendar events and tasks")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 40)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func tasksViewDivider(geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(isTasksDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 4)
            .overlay(
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(isTasksDividerDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isTasksDividerDragging = true
                        let newWidth = tasksPersonalWidth + value.translation.width
                        tasksPersonalWidth = max(200, min(geometry.size.width - 200, newWidth))
                    }
                    .onEnded { _ in
                        isTasksDividerDragging = false
                    }
            )
    }
    
    // Helper computed properties
    private var shouldShowDebugInfo: Bool {
        let hasLinkedAccounts = authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional)
        let hasNoTasks = totalTaskCount == 0
        let isNotLoading = !viewModel.isLoading
        return hasLinkedAccounts && hasNoTasks && isNotLoading
    }
    
    private var totalTaskCount: Int {
        let personalCount = viewModel.personalTasks.values.flatMap { $0 }.count
        let professionalCount = viewModel.professionalTasks.values.flatMap { $0 }.count
        return personalCount + professionalCount
    }
    
    // MARK: - Helper Methods
    
    private func isDueDateOverdue(dueDate: Date) -> Bool {
        let calendar = Calendar.mondayFirst
        let today = calendar.startOfDay(for: Date())
        return dueDate < today
    }
    
    // MARK: - Subtitle helper
    private func subtitleForFilter(_ filter: TaskFilter) -> String {
        let cal = Calendar.mondayFirst
        switch filter {
        case .all:
            // Show subfilter name if not "All"
            if allSubfilter != .all {
                return "All Tasks - \(allSubfilter.rawValue)"
            }
            return "All Tasks"
        case .day:
            // Standardized format: MON 12/25/24
            let dayOfWeek = DateFormatter.standardDayOfWeek.string(from: referenceDate).uppercased()
            let date = DateFormatter.standardDate.string(from: referenceDate)
            return "\(dayOfWeek) \(date)"
        case .week:
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: referenceDate)?.start,
                  let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
            // Standardized format: 12/25/24 - 12/31/24
            let startStr = DateFormatter.standardDate.string(from: weekStart)
            let endStr = DateFormatter.standardDate.string(from: weekEnd)
            return "\(startStr) - \(endStr)"
        case .month:
            // Updated format: January 2025
            return DateFormatter.standardMonthYear.string(from: referenceDate)
        case .year:
            // Standardized format: 2024
            let year = cal.component(.year, from: referenceDate)
            return "\(year)"
        }
    }
    
    private func navigateToDate(_ selectedDate: Date) {
        // Always navigate to day view of the selected date
        selectedFilter = .day
        referenceDate = selectedDate
        navigationManager.updateInterval(.day, date: selectedDate)
    }
    
    // MARK: - Step helper
    private func step(_ direction: Int) {
        switch selectedFilter {
        case .day:
            if let newDate = Calendar.mondayFirst.date(byAdding: .day, value: direction, to: referenceDate) {
                referenceDate = newDate
                navigationManager.updateInterval(.day, date: newDate)
            }
        case .week:
            if let newDate = Calendar.mondayFirst.date(byAdding: .weekOfYear, value: direction, to: referenceDate) {
                referenceDate = newDate
                navigationManager.updateInterval(.week, date: newDate)
            }
        case .month:
            if let newDate = Calendar.mondayFirst.date(byAdding: .month, value: direction, to: referenceDate) {
                referenceDate = newDate
                navigationManager.updateInterval(.month, date: newDate)
            }
        case .year:
            if let newDate = Calendar.mondayFirst.date(byAdding: .year, value: direction, to: referenceDate) {
                referenceDate = newDate
                navigationManager.updateInterval(.year, date: newDate)
            }
        case .all:
            break
        }
    }
    
    // MARK: - Show All Tasks
    private func showAllTasks() {
        // Set filter to show all tasks
        selectedFilter = .all
        allSubfilter = .all
        referenceDate = Date()
        navigationManager.updateInterval(.day, date: Date())
    }
}

// MARK: - Tasks Section View
struct TasksSectionView: View {
    let title: String
    let icon: String
    let accentColor: Color
    let isLinked: Bool
    let taskLists: [GoogleTaskList]
    let tasksDict: [String: [GoogleTask]]
    let accountKind: GoogleAuthManager.AccountKind
    let filter: TaskFilter
    let onTaskToggle: (GoogleTask, String) -> Void
    let onTaskDetails: (GoogleTask, String) -> Void
    let width: CGFloat
    
    private var isCurrentToolbarPeriod: Bool {
        let cal = Calendar.mondayFirst
        let refDate = NavigationManager.shared.currentDate
        switch filter {
        case .day:
            return cal.isDate(refDate, inSameDayAs: Date())
        case .week:
            if let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
               let end = cal.date(byAdding: .day, value: 6, to: start) {
                return refDate >= start && refDate <= end
            }
            return false
        case .month:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .month)
        case .year:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .year)
        case .all:
            return false
        }
    }

    private var isCurrentPeriod: Bool {
        let cal = Calendar.mondayFirst
        let refDate = NavigationManager.shared.currentDate
        switch filter {
        case .day:
            return cal.isDate(refDate, inSameDayAs: Date())
        case .week:
            if let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
               let end = cal.date(byAdding: .day, value: 6, to: start) {
                return refDate >= start && refDate <= end
            }
            return false
        case .month:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .month)
        case .year:
            return cal.isDate(refDate, equalTo: Date(), toGranularity: .year)
        case .all:
            return false
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            contentArea
        }
        .frame(width: width)
        .background(backgroundView)
    }
    
    private var sectionHeader: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(headerColor)
                .font(.title2)
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(headerColor)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(headerBackground)
    }
    
    private var headerColor: Color {
        isCurrentPeriod ? DateDisplayStyle.currentPeriodColor : accentColor
    }
    
    private var headerBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(headerColor.opacity(0.1))
    }
    
    private var contentArea: some View {
        Group {
            if isLinked {
                linkedContent
            } else {
                unlinkedContent
            }
        }
    }
    
    private var linkedContent: some View {
        Group {
            if taskLists.isEmpty {
                loadingView
            } else {
                taskListsGrid
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Loading tasks...")
                .foregroundColor(.secondary)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
    
    private var taskListsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(taskLists) { taskList in
                    taskListCard(for: taskList)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }
    
    private func taskListCard(for taskList: GoogleTaskList) -> some View {
        let filteredTasks = tasksDict[taskList.id] ?? []
        return Group {
            if !filteredTasks.isEmpty || filter == .all {
                TaskListCard(
                    taskList: taskList,
                    tasks: filteredTasks,
                    accountKind: accountKind,
                    accentColor: accentColor,
                    filter: filter,
                    onTaskToggle: { task in
                        onTaskToggle(task, taskList.id)
                    },
                    onTaskDetails: { task, listId in
                        onTaskDetails(task, listId)
                    }
                )
            }
        }
    }
    
    private var unlinkedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: unlinkedIcon)
                .font(.system(size: 50))
                .foregroundColor(accentColor.opacity(0.6))
            Text("Link \(title) Account")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(accentColor)
            Text("Connect your \(title.lowercased()) Google account to view and manage your calendar events and tasks")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .font(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
    
    private var unlinkedIcon: String {
        icon.replacingOccurrences(of: ".circle.fill", with: ".badge.plus")
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.systemBackground))
            .shadow(color: accentColor.opacity(0.2), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Task List Card Component
struct TaskListCard: View {
    let taskList: GoogleTaskList
    let tasks: [GoogleTask]
    let accountKind: GoogleAuthManager.AccountKind
    let accentColor: Color
    let filter: TaskFilter
    let onTaskToggle: (GoogleTask) -> Void
    let onTaskDetails: (GoogleTask, String) -> Void
    
    @State private var isExpanded = false
    
    private let maxVisibleTasks = 3
    private let collapsedHeight: CGFloat = 200 // Fixed height for collapsed state
    
    var completedTasks: Int {
        tasks.filter { $0.isCompleted }.count
    }
    
    var visibleTasks: [GoogleTask] {
        if isExpanded || tasks.count <= maxVisibleTasks {
            return tasks
        } else {
            return Array(tasks.prefix(maxVisibleTasks))
        }
    }
    
    var hasMoreTasks: Bool {
        tasks.count > maxVisibleTasks
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(taskList.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if tasks.isEmpty && filter != .all {
                        Text("No tasks for \(filter.rawValue.lowercased())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                
                Spacer()
                
                // Expand/Collapse button (only show when there are more than 3 tasks)
                if hasMoreTasks {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Task List Content
            VStack(alignment: .leading, spacing: 0) {
                if tasks.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.secondary)
                        Text("No tasks")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleTasks) { task in
                            TaskRow(
                                task: task, 
                                accentColor: accentColor, 
                                onToggle: {
                                    onTaskToggle(task)
                                },
                                onLongPress: {
                                    onTaskDetails(task, taskList.id)
                                }
                            )
                            
                            if task.id != visibleTasks.last?.id {
                                Divider()
                                    .opacity(0.5)
                            }
                        }
                    }
                    
                    // Show more tasks indicator
                    if hasMoreTasks && !isExpanded {
                        VStack(spacing: 8) {
                            Divider()
                                .opacity(0.5)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isExpanded = true
                                }
                            }) {
                                HStack {
                                    Text("Show \(tasks.count - maxVisibleTasks) more tasks")
                                        .font(.caption)
                                        .foregroundColor(accentColor)
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(accentColor)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(minHeight: isExpanded ? nil : collapsedHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Task Row Component
struct TaskRow: View {
    let task: GoogleTask
    let accentColor: Color
    let onToggle: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Completion Button
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(task.isCompleted ? accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Task Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.title3)
                        .foregroundColor(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted)
                    

                    
                    Spacer()
                }
                
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Due Date
            if let dueDate = task.dueDate {
                Text(DateFormatter.standardDate.string(from: dueDate))
                    .font(DateDisplayStyle.subtitleFont)
                    .foregroundColor(DateDisplayStyle.secondaryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isDueDateOverdue(dueDate: dueDate) ? Color.red.opacity(0.1) : Color(.systemGray6))
                    )
                    .foregroundColor(isDueDateOverdue(dueDate: dueDate) ? .red : .secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onLongPress() // Use the same callback for both tap and long press
        }
        .onLongPressGesture {
            onLongPress()
        }
    }
    
    private func isDueDateOverdue(dueDate: Date) -> Bool {
        let calendar = Calendar.mondayFirst
        let today = calendar.startOfDay(for: Date())
        return dueDate < today
    }
}

// MARK: - Task Details View
struct TaskDetailsView: View {
    let task: GoogleTask
    let taskListId: String
    let accountKind: GoogleAuthManager.AccountKind
    let accentColor: Color
    let personalTaskLists: [GoogleTaskList]
    let professionalTaskLists: [GoogleTaskList]
    let appPrefs: AppPreferences
    let viewModel: TasksViewModel
    let onSave: (GoogleTask) -> Void
    let onDelete: () -> Void
    let onMove: (GoogleTask, String) -> Void
    let onCrossAccountMove: (GoogleTask, GoogleAuthManager.AccountKind, String) -> Void
    let isNew: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle: String
    @State private var editedNotes: String
    @State private var editedDueDate: Date?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind
    @State private var selectedListId: String
    @State private var newListName = ""
    @State private var isCreatingNewList = false
    @State private var showingDeleteAlert = false
    @State private var showingDatePicker = false
    @State private var isSaving = false
    @State private var tempSelectedDate = Date()
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var isAllDay: Bool = true
    
    @ObservedObject private var timeWindowManager = TaskTimeWindowManager.shared
    
    // Track original due date to detect changes properly
    private let originalDueDate: Date?
    
    // Track original time window values to detect changes
    private let originalIsAllDay: Bool
    private let originalStartTime: Date
    private let originalEndTime: Date
    
    private let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    
    init(task: GoogleTask, taskListId: String, accountKind: GoogleAuthManager.AccountKind, accentColor: Color, personalTaskLists: [GoogleTaskList], professionalTaskLists: [GoogleTaskList], appPrefs: AppPreferences, viewModel: TasksViewModel, onSave: @escaping (GoogleTask) -> Void, onDelete: @escaping () -> Void, onMove: @escaping (GoogleTask, String) -> Void, onCrossAccountMove: @escaping (GoogleTask, GoogleAuthManager.AccountKind, String) -> Void, isNew: Bool = false) {
        self.task = task
        self.taskListId = taskListId
        self.accountKind = accountKind
        self.accentColor = accentColor
        self.personalTaskLists = personalTaskLists
        self.professionalTaskLists = professionalTaskLists
        self.appPrefs = appPrefs
        self.viewModel = viewModel
        self.onSave = onSave
        self.onDelete = onDelete
        self.onMove = onMove
        self.onCrossAccountMove = onCrossAccountMove
        self.isNew = isNew
        
        // Store original due date to detect changes properly
        self.originalDueDate = task.dueDate
        
        _editedTitle = State(initialValue: task.title)
        _editedNotes = State(initialValue: task.notes ?? "")
        // For new tasks, default due date to current day; for existing tasks, use the task's due date
        _editedDueDate = State(initialValue: isNew ? Calendar.current.startOfDay(for: Date()) : task.dueDate)
        _selectedAccountKind = State(initialValue: accountKind)
        _selectedListId = State(initialValue: taskListId)
        
        // Initialize time window state and store original values
        let calendar = Calendar.current
        if let existingTimeWindow = TaskTimeWindowManager.shared.getTimeWindow(for: task.id) {
            _isAllDay = State(initialValue: existingTimeWindow.isAllDay)
            _startTime = State(initialValue: existingTimeWindow.startTime)
            _endTime = State(initialValue: existingTimeWindow.endTime)
            
            // Store original values
            self.originalIsAllDay = existingTimeWindow.isAllDay
            self.originalStartTime = existingTimeWindow.startTime
            self.originalEndTime = existingTimeWindow.endTime
        } else {
            // No time window exists - default to all-day
            let defaultIsAllDay = true
            let defaultStartTime: Date
            let defaultEndTime: Date
            
            if let dueDate = task.dueDate {
                let startOfDay = calendar.startOfDay(for: dueDate)
                defaultStartTime = startOfDay
                defaultEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
            } else {
                // Default to today's start and end of day
                let today = Date()
                let startOfDay = calendar.startOfDay(for: today)
                defaultStartTime = startOfDay
                defaultEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? startOfDay
            }
            
            _isAllDay = State(initialValue: defaultIsAllDay)
            _startTime = State(initialValue: defaultStartTime)
            _endTime = State(initialValue: defaultEndTime)
            
            // Store original values (default values)
            self.originalIsAllDay = defaultIsAllDay
            self.originalStartTime = defaultStartTime
            self.originalEndTime = defaultEndTime
        }
    }
    
    var availableTaskLists: [GoogleTaskList] {
        selectedAccountKind == .personal ? personalTaskLists : professionalTaskLists
    }
    
    var currentTaskListName: String {
        availableTaskLists.first { $0.id == selectedListId }?.title ?? "Unknown List"
    }
    
    var currentAccentColor: Color {
        selectedAccountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor
    }
    
    var hasChanges: Bool {
        editedTitle != task.title ||
        editedNotes != (task.notes ?? "") ||
        editedDueDate != originalDueDate ||
        selectedAccountKind != accountKind ||
        selectedListId != taskListId ||
        isCreatingNewList ||
        isAllDay != originalIsAllDay ||
        !areTimesEqual(startTime, originalStartTime) ||
        !areTimesEqual(endTime, originalEndTime)
    }
    
    // Helper function to compare times (ignoring seconds and milliseconds)
    private func areTimesEqual(_ time1: Date, _ time2: Date) -> Bool {
        let calendar = Calendar.current
        let components1 = calendar.dateComponents([.hour, .minute], from: time1)
        let components2 = calendar.dateComponents([.hour, .minute], from: time2)
        return components1.hour == components2.hour && components1.minute == components2.minute
    }
    
    var canSave: Bool {
        !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        ((!isCreatingNewList && !selectedListId.isEmpty) || 
         (isCreatingNewList && !newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic Information Section
                Section("Basic Information") {
                    TextField("Add task title", text: $editedTitle, axis: .vertical)
                        .lineLimit(1...3)
                    
                    TextField("Add description (optional)", text: $editedNotes, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                // Account Section
                Section("Account") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Two rows: Personal and Professional, each with its own current list on the same line
                        ForEach([GoogleAuthManager.AccountKind.personal, .professional], id: \.self) { kind in
                            if GoogleAuthManager.shared.isLinked(kind: kind) {
                                let lists: [GoogleTaskList] = (kind == .personal) ? personalTaskLists : professionalTaskLists
                                let currentId: String = (selectedAccountKind == kind ? selectedListId : lists.first?.id) ?? lists.first?.id ?? ""
                                let currentTitle: String = lists.first(where: { $0.id == currentId })?.title ?? (lists.first?.title ?? "Select list")

                                HStack(spacing: 10) {
                                    Button {
                                        selectedAccountKind = kind
                                        if let first = lists.first { selectedListId = first.id }
                                        isCreatingNewList = false
                                        newListName = ""
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: selectedAccountKind == kind ? "largecircle.fill.circle" : "circle")
                                                .foregroundColor(selectedAccountKind == kind ? (kind == .personal ? appPrefs.personalColor : appPrefs.professionalColor) : .secondary)
                                            Text((kind == .personal ? "Personal" : "Professional") + ":")
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    // Place the list immediately after the account name and colon
                                    if selectedAccountKind == kind {
                                        Menu(currentTitle) {
                                            Button("Create new list") {
                                                selectedAccountKind = kind
                                                isCreatingNewList = true
                                                newListName = ""
                                            }
                                            ForEach(lists) { taskList in
                                                Button(taskList.title) {
                                                    selectedAccountKind = kind
                                                    selectedListId = taskList.id
                                                    isCreatingNewList = false
                                                }
                                            }
                                        }
                                    }

                                    Spacer(minLength: 8)
                                }
                            }
                        }

                        // Inline new list name input when requested
                        if isCreatingNewList {
                            HStack(spacing: 8) {
                                TextField("New list name", text: $newListName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Button("Create") {
                                    Task {
                                        if let newId = await viewModel.createTaskList(title: newListName.trimmingCharacters(in: .whitespacesAndNewlines), for: selectedAccountKind) {
                                            selectedListId = newId
                                            isCreatingNewList = false
                                            newListName = ""
                                        }
                                    }
                                }
                                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }
                
                // Due Date Section
                Section("Due Date") {
                    if let dueDate = editedDueDate {
                    // Show date with calendar icon and trash can
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.blue)
                        
                        Button(action: {
                            tempSelectedDate = dueDate
                            showingDatePicker = true
                        }) {
                            Text(dueDateFormatter.string(from: dueDate))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        Button(action: {
                            editedDueDate = nil
                            // Reset times when due date is removed
                            isAllDay = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // All-day toggle
                    Toggle(isOn: $isAllDay) {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.blue)
                            Text("All-day task")
                        }
                    }
                    .onChange(of: isAllDay) { oldValue, newValue in
                        if !newValue {
                            // When switching from all-day to timed, set default times to next nearest half hour
                            let calendar = Calendar.current
                            let startOfDay = calendar.startOfDay(for: dueDate)
                            let currentStartHour = calendar.component(.hour, from: startTime)
                            let currentStartMinute = calendar.component(.minute, from: startTime)
                            let currentEndHour = calendar.component(.hour, from: endTime)
                            
                            // Only set defaults if times are at start/end of day (indicating default all-day values)
                            if currentStartHour == 0 && currentEndHour == 23 && currentStartMinute == 0 {
                                // Calculate next nearest half hour
                                let now = Date()
                                let hour: Int
                                let minute: Int
                                
                                if calendar.isDate(dueDate, inSameDayAs: now) {
                                    // If due date is today, use current time
                                    let components = calendar.dateComponents([.hour, .minute], from: now)
                                    hour = components.hour ?? 9
                                    minute = components.minute ?? 0
                                } else {
                                    // If due date is in the future, default to 9:00 AM
                                    hour = 9
                                    minute = 0
                                }
                                
                                // Calculate next half hour
                                var nextHour = hour
                                var nextMinute: Int
                                
                                if minute < 30 {
                                    // Next half hour is :30 of current hour
                                    nextMinute = 30
                                } else {
                                    // Next half hour is :00 of next hour
                                    nextMinute = 0
                                    nextHour = (hour + 1) % 24
                                }
                                
                                // Set start time to next half hour on the due date
                                if let startTimeDate = calendar.date(bySettingHour: nextHour, minute: nextMinute, second: 0, of: dueDate) {
                                    startTime = startTimeDate
                                    
                                    // Set end time to 30 minutes after start time
                                    if let endTimeDate = calendar.date(byAdding: .minute, value: 30, to: startTimeDate) {
                                        endTime = endTimeDate
                                    } else {
                                        // Fallback: set to next hour if adding 30 minutes fails
                                        endTime = calendar.date(bySettingHour: (nextHour + 1) % 24, minute: nextMinute, second: 0, of: dueDate) ?? startOfDay
                                    }
                                } else {
                                    // Fallback: set to 9 AM if calculation fails
                                    startTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate) ?? startOfDay
                                    endTime = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: dueDate) ?? startOfDay
                                }
                            }
                        }
                    }
                    
                    // Start and End time pickers (only show if not all-day)
                    if !isAllDay {
                        DatePicker("Start Time", selection: $startTime, displayedComponents: [.hourAndMinute])
                            .onChange(of: dueDate) { oldValue, newValue in
                                // Update start time to match new due date
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.hour, .minute], from: startTime)
                                if let hour = components.hour, let minute = components.minute {
                                    startTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newValue) ?? newValue
                                }
                            }
                        
                        DatePicker("End Time", selection: $endTime, displayedComponents: [.hourAndMinute])
                            .onChange(of: dueDate) { oldValue, newValue in
                                // Update end time to match new due date
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.hour, .minute], from: endTime)
                                if let hour = components.hour, let minute = components.minute {
                                    endTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newValue) ?? newValue
                                }
                            }
                    }
                } else {
                    // Show placeholder button
                    Button(action: {
                        tempSelectedDate = Date() // Initialize to today's date
                        showingDatePicker = true
                    }) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                            Text("Add due date")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // Removed Task Status section per request
            }
            .navigationTitle(isNew ? "New Task" : "Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? (isNew ? "Creating..." : "Saving...") : (isNew ? "Create" : "Save")) {
                        saveTask()
                    }
                    .disabled(!canSave || (isNew ? false : !hasChanges) || isSaving)
                    .fontWeight(.semibold)
                    .foregroundColor((canSave && (isNew || hasChanges) && !isSaving) ? currentAccentColor : .secondary)
                    .opacity((canSave && (isNew || hasChanges) && !isSaving) ? 1.0 : 0.5)
                }
            }
            // Add Delete section at bottom for editing task
            .safeAreaInset(edge: .bottom) {
                if !isNew {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Text("Delete Task")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding()
                }
            }
        }
        .presentationDetents([.large, .height(isAllDay ? 600 : 750)])
        .presentationDragIndicator(.visible)
        .alert("Delete Task", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete '\(task.title)'? This action cannot be undone.")
        }
        .onAppear {
            // Load tasks on-demand when popup opens (performance optimization)
            Task {
                await viewModel.loadTasksOnDemand()
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Select Date",
                    selection: $tempSelectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.calendar, Calendar.mondayFirst)
                .navigationTitle("Due Date")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    // Initialize tempSelectedDate with current editedDueDate or today
                    tempSelectedDate = editedDueDate ?? Date()
                    // Update start and end times when due date changes
                    if let dueDate = editedDueDate {
                        let calendar = Calendar.current
                        // Keep the time but update the date
                        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                        
                        if let hour = startComponents.hour, let minute = startComponents.minute {
                            startTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? dueDate
                        } else {
                            startTime = calendar.startOfDay(for: dueDate)
                        }
                        
                        if let hour = endComponents.hour, let minute = endComponents.minute {
                            endTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? dueDate
                        } else {
                            endTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? dueDate
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            // Sync the selected date to editedDueDate
                            let oldDueDate = editedDueDate
                            editedDueDate = tempSelectedDate
                            
                            // Update start and end times to match new due date
                            if let newDueDate = editedDueDate {
                                let calendar = Calendar.current
                                if let oldDueDate = oldDueDate {
                                    // Transfer time components from old date to new date
                                    let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                                    let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                                    
                                    if let hour = startComponents.hour, let minute = startComponents.minute {
                                        startTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDueDate) ?? newDueDate
                                    } else {
                                        startTime = calendar.startOfDay(for: newDueDate)
                                    }
                                    
                                    if let hour = endComponents.hour, let minute = endComponents.minute {
                                        endTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDueDate) ?? newDueDate
                                    } else {
                                        endTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: newDueDate) ?? newDueDate
                                    }
                                } else {
                                    // New due date - set default times
                                    let startOfDay = calendar.startOfDay(for: newDueDate)
                                    startTime = startOfDay
                                    endTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: newDueDate) ?? startOfDay
                                }
                            }
                            
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }
    
    private func saveTask() {
        isSaving = true
        
        Task {
            let targetListId: String
            
            if isCreatingNewList {
                // Create new task list first
                guard let newListId = await viewModel.createTaskList(
                    title: newListName.trimmingCharacters(in: .whitespacesAndNewlines),
                    for: selectedAccountKind
                ) else {
                    await MainActor.run {
                        isSaving = false
                    }
                    return
                }
                targetListId = newListId
            } else {
                targetListId = selectedListId
            }
            
            // Prepare due date string
            let dueDateString: String?
            if let dueDate = editedDueDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                dueDateString = formatter.string(from: dueDate)
            } else {
                dueDateString = nil
            }
            
            let updatedTask = GoogleTask(
                id: task.id,
                title: editedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: editedNotes.isEmpty ? nil : editedNotes,
                status: task.status,
                due: dueDateString,
                completed: task.completed,
                updated: task.updated
            )
            
            if isNew {
                // Creation path
                // Prepare time window data if due date exists
                let finalStartTime: Date?
                let finalEndTime: Date?
                
                if let dueDate = editedDueDate {
                    let calendar = Calendar.current
                    let startOfDay = calendar.startOfDay(for: dueDate)
                    
                    if isAllDay {
                        finalStartTime = startOfDay
                        finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                    } else {
                        // Ensure times are on the due date
                        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                        
                        if let hour = startComponents.hour, let minute = startComponents.minute {
                            finalStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                        } else {
                            finalStartTime = startOfDay
                        }
                        
                        if let hour = endComponents.hour, let minute = endComponents.minute {
                            finalEndTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                        } else {
                            finalEndTime = startOfDay.addingTimeInterval(1800) // Default 30 minutes
                        }
                    }
                } else {
                    finalStartTime = nil
                    finalEndTime = nil
                }
                
                // Create task with time window parameters
                await viewModel.createTask(
                    title: updatedTask.title,
                    notes: updatedTask.notes,
                    dueDate: editedDueDate,
                    in: targetListId,
                    for: selectedAccountKind,
                    startTime: finalStartTime,
                    endTime: finalEndTime,
                    isAllDay: isAllDay
                )
                
                await MainActor.run {
                    dismiss()
                }
            } else {
                // Editing path (perform updates directly to ensure they complete)
                print("💾 TaskDetailsView: Editing path - determining operation type")
                print("   - selectedAccountKind: \(selectedAccountKind)")
                print("   - accountKind: \(accountKind)")
                print("   - targetListId: \(targetListId)")
                print("   - taskListId: \(taskListId)")
                
                if selectedAccountKind != accountKind {
                    print("💾 TaskDetailsView: Cross-account move detected")
                    await viewModel.crossAccountMoveTask(updatedTask, from: (accountKind, taskListId), to: (selectedAccountKind, targetListId))
                } else if targetListId != taskListId {
                    print("💾 TaskDetailsView: Same-account move detected")
                    await viewModel.moveTask(updatedTask, from: taskListId, to: targetListId, for: selectedAccountKind)
                } else {
                    print("💾 TaskDetailsView: In-place update detected")
                    await viewModel.updateTask(updatedTask, in: targetListId, for: selectedAccountKind)
                }
                
                // Save time window if due date exists
                if let dueDate = editedDueDate {
                    // Ensure start and end times are on the same day as due date
                    let calendar = Calendar.current
                    let startOfDay = calendar.startOfDay(for: dueDate)
                    
                    let finalStartTime: Date
                    let finalEndTime: Date
                    
                    if isAllDay {
                        finalStartTime = startOfDay
                        finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                    } else {
                        // Ensure times are on the due date
                        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
                        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
                        
                        if let hour = startComponents.hour, let minute = startComponents.minute {
                            finalStartTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                        } else {
                            finalStartTime = startOfDay
                        }
                        
                        if let hour = endComponents.hour, let minute = endComponents.minute {
                            finalEndTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dueDate) ?? startOfDay
                        } else {
                            finalEndTime = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? startOfDay
                        }
                    }
                    
                    TaskTimeWindowManager.shared.saveTimeWindow(
                        taskId: task.id,
                        startTime: finalStartTime,
                        endTime: finalEndTime,
                        isAllDay: isAllDay
                    )
                } else {
                    // Remove time window if due date is removed
                    TaskTimeWindowManager.shared.deleteTimeWindow(for: task.id)
                }
                
                // No need to reload all tasks - individual methods update local state
                await MainActor.run { dismiss() }
            }
        }
    }
}

#Preview {
    TasksView()
} 

