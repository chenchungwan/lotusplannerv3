import SwiftUI
import Foundation

// MARK: - Tasks View Model
@MainActor
class TasksViewModel: ObservableObject {
    /// Shared instance. App-wide views observe the same model so a task
    /// edit anywhere updates every surface (tasks list, calendar, custom
    /// day view). `DataManager` previously owned this object; promotion
    /// to a singleton lets views reference it directly without going
    /// through DataManager indirection.
    static let shared = TasksViewModel()

    @Published var personalTaskLists: [GoogleTaskList] = []
    @Published var professionalTaskLists: [GoogleTaskList] = []
    @Published var personalTasks: [String: [GoogleTask]] = [:] { // taskListId: [tasks]
        didSet { rebuildTasksCache(for: .personal) }
    }
    @Published var professionalTasks: [String: [GoogleTask]] = [:] {
        didSet { rebuildTasksCache(for: .professional) }
    }
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
    private var personalTasksByDay: [Date: [String: [GoogleTask]]] = [:]
    private var professionalTasksByDay: [Date: [String: [GoogleTask]]] = [:]
    
    func tasksForDay(_ date: Date, kind: GoogleAuthManager.AccountKind) -> [String: [GoogleTask]] {
        let key = normalizedDay(date)
        switch kind {
        case .personal:
            return personalTasksByDay[key] ?? [:]
        case .professional:
            return professionalTasksByDay[key] ?? [:]
        }
    }
    
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

            // Clean up time windows for all-day tasks after loading
            await MainActor.run {
                let allTasks: [GoogleTask] = taskLists.flatMap { taskList in
                    switch kind {
                    case .personal: return self.personalTasks[taskList.id] ?? []
                    case .professional: return self.professionalTasks[taskList.id] ?? []
                    }
                }
                TaskTimeWindowManager.shared.cleanupTimeWindowsForAllDayTasks(tasks: allTasks)
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
    
    private func rebuildTasksCache(for kind: GoogleAuthManager.AccountKind) {
        switch kind {
        case .personal:
            personalTasksByDay = buildDayCache(from: personalTasks)
        case .professional:
            professionalTasksByDay = buildDayCache(from: professionalTasks)
        }
    }
    
    private func buildDayCache(from tasksDict: [String: [GoogleTask]]) -> [Date: [String: [GoogleTask]]] {
        var map: [Date: [String: [GoogleTask]]] = [:]
        for (listId, tasks) in tasksDict {
            for task in tasks {
                guard let day = relevantDate(for: task) else { continue }
                var lists = map[day] ?? [:]
                var dayTasks = lists[listId] ?? []
                dayTasks.append(task)
                lists[listId] = dayTasks
                map[day] = lists
            }
        }
        for key in map.keys {
            var lists = map[key] ?? [:]
            for (listId, tasks) in lists {
                lists[listId] = tasks.sorted(by: taskSortComparator)
            }
            map[key] = lists
        }
        return map
    }
    
    private func taskSortComparator(_ lhs: GoogleTask, _ rhs: GoogleTask) -> Bool {
        let lhsDate = lhs.dueDate ?? lhs.completionDate ?? Date.distantFuture
        let rhsDate = rhs.dueDate ?? rhs.completionDate ?? Date.distantFuture
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        // Sort by priority (P0 highest first, no priority goes last)
        let lhsPriority = lhs.priority?.sortOrder ?? Int.max
        let rhsPriority = rhs.priority?.sortOrder ?? Int.max
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return (lhs.updated ?? "") > (rhs.updated ?? "")
    }
    
    private func relevantDate(for task: GoogleTask) -> Date? {
        if task.isCompleted, let completion = task.completionDate {
            return normalizedDay(completion)
        }
        if let due = task.dueDate {
            return normalizedDay(due)
        }
        return nil
    }
    
    private func normalizedDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
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
        let wasCompleted = task.isCompleted
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

        // If this transition completed the task, give RecurrenceManager a
        // chance to spawn the next instance. The manager no-ops when the
        // task has no recurrence rule, so this is cheap for most tasks.
        if !wasCompleted && newStatus == "completed" {
            await RecurrenceManager.shared.handleTaskCompleted(
                updatedTask,
                listId: listId,
                account: kind,
                tasksVM: self
            )
        }
    }

    /// Used by `RecurrenceManager` to create the next instance of a recurring
    /// task series. Unlike `createTask`, this awaits the server response so
    /// the new task's id is available immediately for re-keying the rule.
    func spawnRecurringInstance(
        title: String,
        notes: String?,
        dueDate: Date?,
        in listId: String,
        for kind: GoogleAuthManager.AccountKind
    ) async throws -> GoogleTask {
        let dueString: String?
        if let dueDate = dueDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            dueString = formatter.string(from: dueDate)
        } else {
            dueString = nil
        }

        let stub = GoogleTask(
            id: UUID().uuidString,
            title: title,
            notes: notes,
            status: "needsAction",
            due: dueString,
            completed: nil,
            updated: nil
        )

        let createdTask = try await createTaskOnServer(stub, in: listId, for: kind)

        await MainActor.run {
            switch kind {
            case .personal:
                if personalTasks[listId] != nil {
                    personalTasks[listId]?.append(createdTask)
                } else {
                    personalTasks[listId] = [createdTask]
                }
            case .professional:
                if professionalTasks[listId] != nil {
                    professionalTasks[listId]?.append(createdTask)
                } else {
                    professionalTasks[listId] = [createdTask]
                }
            }
        }

        return createdTask
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

            // Update cached title/list in any linked goals
            GoalsManager.shared.refreshLinkedTaskInfo(taskId: task.id, newTitle: task.title, newListId: listId)
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
                } else {
                    // Explicitly clear notes field on the server
                    requestBody["notes"] = NSNull()
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
            // Also delete the time window for this task
            TaskTimeWindowManager.shared.deleteTimeWindow(for: task.id)
            // Remove from any linked goals
            GoalsManager.shared.removeLinkedTask(taskId: task.id)
        }

        // BACKGROUND SYNC: Delete from server in background
        Task {
            do {
                try await deleteTaskFromServer(task, from: listId, for: kind)

                // Clear cache after successful deletion to prevent deleted tasks from reappearing
                await MainActor.run {
                    self.clearCacheForAccount(kind)
                    self.clearAllFilteredCaches()
                }
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
                // Note: We don't restore the time window on error - if deletion fails,
                // the task will be treated as all-day (no time window)
            }
        }
    }
    
    private func deleteTaskFromServer(_ task: GoogleTask, from listId: String, for kind: GoogleAuthManager.AccountKind) async throws {
        guard let accessToken = try await getAccessTokenThrows(for: kind) else {
            throw TasksError.notAuthenticated
        }

        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(listId)/tasks/\(task.id)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TasksError.invalidResponse
        }

        if httpResponse.statusCode != 204 {
            if let errorData = String(data: data, encoding: .utf8) {
            }
            throw TasksError.apiError(httpResponse.statusCode)
        }
    }
    
    func moveTask(_ updatedTask: GoogleTask, from sourceListId: String, to targetListId: String, for kind: GoogleAuthManager.AccountKind) async -> GoogleTask? {
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
            await MainActor.run {
                self.errorMessage = "Cannot find original task to move"
            }
            return nil
        }

        // Check if this is a local UUID (not synced to server yet)
        let isLocalUUID = taskToDelete.id.count > 20 && taskToDelete.id.contains("-")

        var newTask: GoogleTask?
        do {
            // First create the task in the target list (returns new task with server-assigned ID)
            newTask = try await createTaskOnServer(updatedTask, in: targetListId, for: kind)

            // Then delete from source list using original task ID (from server)
            // Check if this is a local UUID - if so, skip server deletion
            let isLocalUUID = taskToDelete.id.count > 20 && taskToDelete.id.contains("-")
            if isLocalUUID {
            } else {
                try await deleteTaskFromServer(taskToDelete, from: sourceListId, for: kind)
            }

            // Update local state using the new task (with correct server ID)
            guard let taskToAdd = newTask else {
                return nil
            }

            await MainActor.run {
                // Remove from source list using original task ID (the one we deleted from server)
                let originalTaskId = taskToDelete.id
                switch kind {
                case .personal:
                    let beforeRemoveCount = self.personalTasks[sourceListId]?.count ?? 0
                    self.personalTasks[sourceListId]?.removeAll { $0.id == originalTaskId }
                    let afterRemoveCount = self.personalTasks[sourceListId]?.count ?? 0

                    // Add to target list using new task (with server ID)
                    let beforeAddCount = self.personalTasks[targetListId]?.count ?? 0
                    if self.personalTasks[targetListId] != nil {
                        self.personalTasks[targetListId]?.append(taskToAdd)
                    } else {
                        self.personalTasks[targetListId] = [taskToAdd]
                    }
                    let afterAddCount = self.personalTasks[targetListId]?.count ?? 0

                case .professional:
                    let beforeRemoveCount = self.professionalTasks[sourceListId]?.count ?? 0
                    self.professionalTasks[sourceListId]?.removeAll { $0.id == originalTaskId }
                    let afterRemoveCount = self.professionalTasks[sourceListId]?.count ?? 0

                    // Add to target list using new task (with server ID)
                    let beforeAddCount = self.professionalTasks[targetListId]?.count ?? 0
                    if self.professionalTasks[targetListId] != nil {
                        self.professionalTasks[targetListId]?.append(taskToAdd)
                    } else {
                        self.professionalTasks[targetListId] = [taskToAdd]
                    }
                    let afterAddCount = self.professionalTasks[targetListId]?.count ?? 0
                }

                // Clear caches to ensure UI refreshes
                self.clearCacheForAccount(kind)
                self.clearAllFilteredCaches()

                // Update goal links to point to the new task ID/list
                GoalsManager.shared.updateLinkedTask(
                    oldTaskId: originalTaskId,
                    oldListId: sourceListId,
                    newTaskId: taskToAdd.id,
                    newListId: targetListId,
                    newAccountKind: kind
                )
            }

            // Return the new task so caller can transfer time window
            return taskToAdd

        } catch {
            // If deletion failed, clean up the task we created in the target list
            if let createdTask = newTask {
                do {
                    try await deleteTaskFromServer(createdTask, from: targetListId, for: kind)
                } catch { }
            }

            await MainActor.run {
                self.errorMessage = "Failed to move task: \(error.localizedDescription)"
            }
            return nil
        }
    }

    func crossAccountMoveTask(_ updatedTask: GoogleTask, from source: (GoogleAuthManager.AccountKind, String), to target: (GoogleAuthManager.AccountKind, String)) async -> GoogleTask? {
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
            await MainActor.run {
                self.errorMessage = "Cannot find original task to move"
            }
            return nil
        }

        // Check if this is a local UUID (not synced to server yet)
        let isLocalUUID = taskToDelete.id.count > 20 && taskToDelete.id.contains("-")

        var newTask: GoogleTask?
        do {
            // First create the task in the target account (returns new task with server-assigned ID)
            newTask = try await createTaskOnServer(updatedTask, in: target.1, for: target.0)

            // Then delete from source account using original task ID (from server)
            // Check if this is a local UUID - if so, skip server deletion
            let isLocalUUID = taskToDelete.id.count > 20 && taskToDelete.id.contains("-")
            if isLocalUUID {
            } else {
                try await deleteTaskFromServer(taskToDelete, from: source.1, for: source.0)
            }

            // Update local state using the new task (with correct server ID)
            guard let taskToAdd = newTask else {
                return nil
            }

            await MainActor.run {
                // Remove from source account using original task ID (the one we deleted from server)
                let originalTaskId = taskToDelete.id
                switch source.0 {
                case .personal:
                    let beforeRemoveCount = self.personalTasks[source.1]?.count ?? 0
                    self.personalTasks[source.1]?.removeAll { $0.id == originalTaskId }
                    let afterRemoveCount = self.personalTasks[source.1]?.count ?? 0
                case .professional:
                    let beforeRemoveCount = self.professionalTasks[source.1]?.count ?? 0
                    self.professionalTasks[source.1]?.removeAll { $0.id == originalTaskId }
                    let afterRemoveCount = self.professionalTasks[source.1]?.count ?? 0
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
                case .professional:
                    let beforeAddCount = self.professionalTasks[target.1]?.count ?? 0
                    if self.professionalTasks[target.1] != nil {
                        self.professionalTasks[target.1]?.append(taskToAdd)
                    } else {
                        self.professionalTasks[target.1] = [taskToAdd]
                    }
                    let afterAddCount = self.professionalTasks[target.1]?.count ?? 0
                }

                // Clear caches to ensure UI refreshes
                self.clearCacheForAccount(source.0)
                self.clearCacheForAccount(target.0)
                self.clearAllFilteredCaches()

                // Update goal links to point to the new task ID/list/account
                GoalsManager.shared.updateLinkedTask(
                    oldTaskId: originalTaskId,
                    oldListId: source.1,
                    newTaskId: taskToAdd.id,
                    newListId: target.1,
                    newAccountKind: target.0
                )
            }

            // Return the new task so caller can transfer time window
            return taskToAdd

        } catch {
            // If deletion failed, clean up the task we created in the target account
            if let createdTask = newTask {
                do {
                    try await deleteTaskFromServer(createdTask, from: target.1, for: target.0)
                } catch { }
            }

            await MainActor.run {
                self.errorMessage = "Failed to move task across accounts: \(error.localizedDescription)"
            }
            return nil
        }
    }
    
    func createTaskOnServer(_ task: GoogleTask, in listId: String, for kind: GoogleAuthManager.AccountKind) async throws -> GoogleTask {
        guard let accessToken = try await getAccessTokenThrows(for: kind) else {
            throw TasksError.notAuthenticated
        }

        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(listId)/tasks")!

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

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TasksError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorData = String(data: data, encoding: .utf8) {
            }
            throw TasksError.apiError(httpResponse.statusCode)
        }

        // Parse response to get the created task with server ID
        let createdTask = try JSONDecoder().decode(GoogleTask.self, from: data)
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
        isAllDay: Bool = true,
        status: String = "needsAction",
        completed: String? = nil,
        onServerCreated: ((GoogleTask) -> Void)? = nil
    ) async {
        
        let dueDateString: String?
        if let dueDate = dueDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current  // Use local timezone for all-day dates
            dueDateString = formatter.string(from: dueDate)

        } else {
            dueDateString = nil
        }
        
        let task = GoogleTask(
            id: UUID().uuidString, // Temporary ID, will be overwritten by server
            title: title,
            notes: notes,
            status: status,
            due: dueDateString,
            completed: completed,
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
                    onServerCreated?(createdTask)
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
