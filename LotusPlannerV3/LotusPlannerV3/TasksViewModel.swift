import SwiftUI
import Foundation

// MARK: - Tasks View Model
@MainActor
class TasksViewModel: ObservableObject {
    enum CacheRefreshPolicy {
        case freshEnough
        case forceRefresh
    }

    /// Shared instance. App-wide views observe the same model so a task
    /// edit anywhere updates every surface (tasks list, calendar, custom
    /// day view). `DataManager` previously owned this object; promotion
    /// to a singleton lets views reference it directly without going
    /// through DataManager indirection.
    static let shared = TasksViewModel()

    @Published var account1TaskLists: [GoogleTaskList] = []
    @Published var account2TaskLists: [GoogleTaskList] = []
    @Published var account1Tasks: [String: [GoogleTask]] = [:] { // taskListId: [tasks]
        didSet { rebuildTasksCache(for: .account1) }
    }
    @Published var account2Tasks: [String: [GoogleTask]] = [:] {
        didSet { rebuildTasksCache(for: .account2) }
    }
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var loadingStatusMessage = ""
    @Published var lastSuccessfulFetch: [GoogleAuthManager.AccountKind: Date] = [:]
    @Published var lastFetchError: [GoogleAuthManager.AccountKind: String] = [:]
    
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
    private var account1TasksByDay: [Date: [String: [GoogleTask]]] = [:]
    private var account2TasksByDay: [Date: [String: [GoogleTask]]] = [:]
    
    func tasksForDay(_ date: Date, kind: GoogleAuthManager.AccountKind) -> [String: [GoogleTask]] {
        let key = normalizedDay(date)
        switch kind {
        case .account1:
            return account1TasksByDay[key] ?? [:]
        case .account2:
            return account2TasksByDay[key] ?? [:]
        }
    }
    
    func loadTasks(forceClear: Bool = false) async {
        await loadTasks(policy: forceClear ? .forceRefresh : .freshEnough)
    }

    func loadTasks(policy: CacheRefreshPolicy) async {
        isLoading = true
        errorMessage = ""
        loadingStatusMessage = "Loading tasks..."
        
        // Force refresh is reserved for explicit user/account sync actions.
        if policy == .forceRefresh {
            clearCacheForAccount(.account1)
            clearCacheForAccount(.account2)
            clearTaskListCache(for: .account1)
            clearTaskListCache(for: .account2)
        }
        
        // Load tasks for both account types in parallel
        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .account1) {
                group.addTask {
                    await self.loadTasksForAccount(.account1)
                }
            }
            
            if authManager.isLinked(kind: .account2) {
                group.addTask {
                    await self.loadTasksForAccount(.account2)
                }
            }
        }
        
        await MainActor.run {
            self.loadingStatusMessage = ""
            self.isLoading = false
        }
    }
    
    /// Fast method to load only task lists (for popup initialization)
    func loadTaskListsOnly() async {
        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .account1) {
                group.addTask {
                    await self.loadTaskListsForAccount(.account1)
                }
            }
            
            if authManager.isLinked(kind: .account2) {
                group.addTask {
                    await self.loadTaskListsForAccount(.account2)
                }
            }
        }
    }
    
    /// Load tasks on-demand when popup is opened (performance optimization)
    func loadTasksOnDemand() async {
        // Only load if we don't already have tasks loaded
        let hasAccount1Tasks = !account1Tasks.isEmpty
        let hasAccount2Tasks = !account2Tasks.isEmpty
        
        if !hasAccount1Tasks || !hasAccount2Tasks {
            await loadTasks()
        }
    }
    
    /// Check if tasks are already loaded to avoid unnecessary API calls
    var hasTasksLoaded: Bool {
        return !account1Tasks.isEmpty || !account2Tasks.isEmpty
    }
    
    private func loadTaskListsForAccount(_ kind: GoogleAuthManager.AccountKind) async {
        loadingStatusMessage = "Loading task lists for \(kind.displayName)..."
        // Check cache first
        if let cachedLists = getCachedTaskLists(for: kind) {
            await MainActor.run {
                switch kind {
                case .account1: self.account1TaskLists = cachedLists
                case .account2: self.account2TaskLists = cachedLists
                }
            }
            return
        }
        
        do {
            let taskLists = try await fetchTaskLists(for: kind)
            
            await MainActor.run {
                switch kind {
                case .account1: self.account1TaskLists = taskLists
                case .account2: self.account2TaskLists = taskLists
                }
            }
            
            // Cache the task lists
            cacheTaskLists(taskLists, for: kind)
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load task lists for \(kind.displayName): \(error.localizedDescription)"
                self.lastFetchError[kind] = error.localizedDescription
            }
        }
    }
    
    private func loadTasksForAccount(_ kind: GoogleAuthManager.AccountKind) async {
        loadingStatusMessage = "Loading tasks for \(kind.displayName)..."
        do {
            let taskLists: [GoogleTaskList]
            if let cachedLists = getCachedTaskLists(for: kind) {
                taskLists = cachedLists
            } else {
                taskLists = try await fetchTaskLists(for: kind)
                cacheTaskLists(taskLists, for: kind)
            }

            var loadedTasksByList: [String: [GoogleTask]] = [:]
            var listLoadErrors: [String] = []

            // Load all lists in parallel, then publish once to avoid repeatedly
            // rebuilding day caches and invalidating every observing view.
            await withTaskGroup(of: (listId: String, tasks: [GoogleTask]?, errorMessage: String?).self) { group in
                for taskList in taskLists {
                    group.addTask {
                        do {
                            let tasks = try await self.fetchTasks(for: kind, taskListId: taskList.id)
                            return (taskList.id, tasks, nil)
                        } catch {
                            return (taskList.id, nil, "Failed to load tasks for \(taskList.title): \(error.localizedDescription)")
                        }
                    }
                }

                for await result in group {
                    if let tasks = result.tasks {
                        loadedTasksByList[result.listId] = tasks
                    }
                    if let errorMessage = result.errorMessage {
                        listLoadErrors.append(errorMessage)
                    }
                }
            }

            switch kind {
            case .account1:
                account1TaskLists = taskLists
                account1Tasks = loadedTasksByList
            case .account2:
                account2TaskLists = taskLists
                account2Tasks = loadedTasksByList
            }

            if let firstError = listLoadErrors.first {
                errorMessage = firstError
                lastFetchError[kind] = firstError
            } else {
                lastFetchError.removeValue(forKey: kind)
                lastSuccessfulFetch[kind] = Date()
            }

            let allTasks = loadedTasksByList.values.flatMap { $0 }
            TaskTimeWindowManager.shared.cleanupTimeWindowsForAllDayTasks(tasks: allTasks)
        } catch {
            errorMessage = "Failed to load tasks for \(kind.displayName): \(error.localizedDescription)"
            lastFetchError[kind] = error.localizedDescription
        }
    }

    /// Status text for the Diagnostics screen. The caller labels the row with
    /// the account's user-chosen name, so this omits it.
    func qualitySummary(for kind: GoogleAuthManager.AccountKind) -> String {
        if let error = lastFetchError[kind] {
            return "Failed: \(error)"
        }
        if let lastFetch = lastSuccessfulFetch[kind] {
            return "Loaded \(lastFetch.formatted(date: .omitted, time: .shortened))"
        }
        return authManager.isLinked(kind: kind) ? "Not loaded yet" : "Not linked"
    }

    func newestCacheAgeDescription() -> String {
        guard let newest = cacheTimestamps.values.max() else { return "No cached tasks" }
        return CalendarViewModel.relativeAgeDescription(since: newest)
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

    private func clearTaskListCache(for kind: GoogleAuthManager.AccountKind) {
        cachedTaskLists.removeValue(forKey: kind)
        taskListCacheTimestamps.removeValue(forKey: kind)
    }
    
    /// Clears tasks and lists for the specified account kind (or all if nil)
    func clearTasks(for kind: GoogleAuthManager.AccountKind? = nil) {
        switch kind {
        case .some(.account1):
            account1TaskLists = []
            account1Tasks = [:]
            clearCacheForAccount(.account1)
        case .some(.account2):
            account2TaskLists = []
            account2Tasks = [:]
            clearCacheForAccount(.account2)
        case .none:
            account1TaskLists = []
            account2TaskLists = []
            account1Tasks = [:]
            account2Tasks = [:]
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

    func upsertTaskInCache(_ task: GoogleTask, in listId: String, for kind: GoogleAuthManager.AccountKind) {
        let key = taskCacheKey(for: kind, listId: listId)
        guard var tasks = cachedTasks[key] else { return }

        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }

        cacheTasks(tasks, for: key)
        clearFilteredCache(for: kind)
    }

    func replaceTaskInCache(tempId: String, with task: GoogleTask, in listId: String, for kind: GoogleAuthManager.AccountKind) {
        let key = taskCacheKey(for: kind, listId: listId)
        guard var tasks = cachedTasks[key] else { return }

        if let index = tasks.firstIndex(where: { $0.id == tempId }) {
            tasks[index] = task
        } else if !tasks.contains(where: { $0.id == task.id }) {
            tasks.append(task)
        }

        cacheTasks(tasks, for: key)
        clearFilteredCache(for: kind)
    }

    func removeTaskFromCache(taskId: String, from listId: String, for kind: GoogleAuthManager.AccountKind) {
        let key = taskCacheKey(for: kind, listId: listId)
        guard var tasks = cachedTasks[key] else { return }

        tasks.removeAll { $0.id == taskId }
        cacheTasks(tasks, for: key)
        clearFilteredCache(for: kind)
    }

    func moveTaskInCache(
        originalTaskId: String,
        replacementTask: GoogleTask,
        from sourceListId: String,
        to targetListId: String,
        sourceKind: GoogleAuthManager.AccountKind,
        targetKind: GoogleAuthManager.AccountKind
    ) {
        removeTaskFromCache(taskId: originalTaskId, from: sourceListId, for: sourceKind)
        upsertTaskInCache(replacementTask, in: targetListId, for: targetKind)
    }

    func upsertTaskListInCache(_ taskList: GoogleTaskList, for kind: GoogleAuthManager.AccountKind) {
        var lists = cachedTaskLists[kind] ?? []

        if let index = lists.firstIndex(where: { $0.id == taskList.id }) {
            lists[index] = taskList
        } else {
            lists.append(taskList)
        }

        cacheTaskLists(lists, for: kind)
    }

    func removeTaskListFromCache(listId: String, for kind: GoogleAuthManager.AccountKind) {
        if var lists = cachedTaskLists[kind] {
            lists.removeAll { $0.id == listId }
            cacheTaskLists(lists, for: kind)
        }

        let key = taskCacheKey(for: kind, listId: listId)
        cachedTasks.removeValue(forKey: key)
        cacheTimestamps.removeValue(forKey: key)
        clearFilteredCache(for: kind)
    }
    
    func clearCacheForAccount(_ kind: GoogleAuthManager.AccountKind) {
        let keysToRemove = cachedTasks.keys.filter { $0.hasPrefix(kind.rawValue) }
        for key in keysToRemove {
            cachedTasks.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
        }
        
        clearFilteredCache(for: kind)
    }
    
    func clearAllFilteredCaches() {
        filteredTasksCache.removeAll()
    }

    private func clearFilteredCache(for kind: GoogleAuthManager.AccountKind) {
        let filteredKeysToRemove = filteredTasksCache.keys.filter { $0.accountKind == kind.rawValue }
        for key in filteredKeysToRemove {
            filteredTasksCache.removeValue(forKey: key)
        }
    }
    
    private func rebuildTasksCache(for kind: GoogleAuthManager.AccountKind) {
        switch kind {
        case .account1:
            account1TasksByDay = buildDayCache(from: account1Tasks)
        case .account2:
            account2TasksByDay = buildDayCache(from: account2Tasks)
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
