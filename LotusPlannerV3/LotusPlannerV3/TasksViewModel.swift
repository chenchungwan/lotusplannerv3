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
    
    let authManager = GoogleAuthManager.shared
    
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
    
    func clearCacheForAccount(_ kind: GoogleAuthManager.AccountKind) {
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
    
    func clearAllFilteredCaches() {
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
    
    func getAccessTokenThrows(for kind: GoogleAuthManager.AccountKind) async throws -> String? {
        do {
            let token = try await authManager.getAccessToken(for: kind)
            return token
        } catch {
            throw TasksError.authError(error.localizedDescription)
        }
    }
    
}
