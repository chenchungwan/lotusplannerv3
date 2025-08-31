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
        print("📅 Due date: '\(due)' -> date part: '\(dateOnly)' -> \(parsedDate?.description ?? "nil")")
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
            print("📅 Completion: '\(completed)' UTC: \(utcDate) -> Local day: \(localFormatter.string(from: utcDate))")
            return utcDate
        }
        return nil
    }
}

struct GoogleTasksResponse: Codable {
    let items: [GoogleTask]?
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
    
    func loadTasks() async {
        isLoading = true
        errorMessage = ""
        
        // Load tasks and recurring tasks for both account types
        await withTaskGroup(of: Void.self) { group in
            if authManager.isLinked(kind: .personal) {
                group.addTask {
                    do {
                        let taskLists = try await self.fetchTaskLists(for: .personal)
                        
                        await MainActor.run {
                            // Apply saved order if available
                            let orderedTaskLists = self.applySavedOrder(taskLists, for: .personal)
                            self.personalTaskLists = orderedTaskLists
                        }
                        
                        // Load tasks for each task list
                        for taskList in taskLists {
                            let tasks = try await self.fetchTasks(for: .personal, taskListId: taskList.id)
                            
                            await MainActor.run {
                                self.personalTasks[taskList.id] = tasks
                            }
                        }
                        
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "Failed to load personal tasks: \(error.localizedDescription)"
                        }
                    }
                }
            }
            
            if authManager.isLinked(kind: .professional) {
                group.addTask {
                    do {
                        let taskLists = try await self.fetchTaskLists(for: .professional)
                        
                        await MainActor.run {
                            // Apply saved order if available
                            let orderedTaskLists = self.applySavedOrder(taskLists, for: .professional)
                            self.professionalTaskLists = orderedTaskLists
                        }
                        
                        // Load tasks for each task list
                        for taskList in taskLists {
                            let tasks = try await self.fetchTasks(for: .professional, taskListId: taskList.id)
                            
                            await MainActor.run {
                                self.professionalTasks[taskList.id] = tasks
                            }
                        }
                        
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "Failed to load professional tasks: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
        
        await MainActor.run {
            self.isLoading = false
        }
    }
    
    private func loadTasksForAccount(_ kind: GoogleAuthManager.AccountKind) async {
        print("🔄 Loading tasks for \(kind) account...")
        
        do {
            print("🔄 Fetching task lists for \(kind)...")
            let taskLists = try await fetchTaskLists(for: kind)
            print("✅ Fetched \(taskLists.count) task lists for \(kind)")
            
            await MainActor.run {
                switch kind {
                case .personal:
                    self.personalTaskLists = taskLists
                    print("📝 Updated personal task lists: \(taskLists.map { $0.title })")
                case .professional:
                    self.professionalTaskLists = taskLists
                    print("📝 Updated professional task lists: \(taskLists.map { $0.title })")
                }
            }
            
            // Fetch tasks for each task list
            for taskList in taskLists {
                print("🔄 Fetching tasks for list '\(taskList.title)' (ID: \(taskList.id))")
                let tasks = try await fetchTasks(for: kind, taskListId: taskList.id)
                print("✅ Fetched \(tasks.count) tasks for list '\(taskList.title)'")
                if !tasks.isEmpty {
                    print("  Task titles: \(tasks.map { $0.title })")
                }
                
                await MainActor.run {
                    switch kind {
                    case .personal:
                        self.personalTasks[taskList.id] = tasks
                        print("📝 Updated personal tasks for list '\(taskList.title)': \(tasks.count) tasks")
                    case .professional:
                        self.professionalTasks[taskList.id] = tasks
                        print("📝 Updated professional tasks for list '\(taskList.title)': \(tasks.count) tasks")
                    }
                }
            }
        } catch {
            print("❌ Failed to load \(kind) tasks: \(error)")
            
            if let tasksError = error as? TasksError {
                print("  TasksError details: \(tasksError)")
            }
            
            await MainActor.run {
                self.errorMessage = "Failed to load \(kind.rawValue) tasks: \(error.localizedDescription)"
                print("🚨 Set error message: '\(self.errorMessage)'")
            }
        }
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
        
        return taskListsResponse.items ?? []
    }
    
    private func fetchTasks(for kind: GoogleAuthManager.AccountKind, taskListId: String) async throws -> [GoogleTask] {
        guard let accessToken = try await getAccessTokenThrows(for: kind) else {
            throw TasksError.notAuthenticated
        }
        
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(taskListId)/tasks?showCompleted=true&showHidden=true")!
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
        let tasks = tasksResponse.items ?? []
        
        return tasks
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
        
        // Set completion timestamp when marking as completed, clear when marking incomplete
        let completedTimestamp: String?
        if newStatus == "completed" {
            // Google Tasks API expects RFC 3339 format in UTC
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            let now = Date()
            completedTimestamp = formatter.string(from: now)
            print("🔄 Task '\(task.title)' marked completed at: \(completedTimestamp ?? "nil")")
            
            // Debug: Show what day this will appear on
            let calendar = Calendar.current
            let localDayFormatter = DateFormatter()
            localDayFormatter.dateStyle = .full
            print("📅 Should appear on: \(localDayFormatter.string(from: now))")
        } else {
            completedTimestamp = nil
            print("🔄 Task '\(task.title)' marked incomplete")
        }
        
        let updatedTask = GoogleTask(
            id: task.id,
            title: task.title,
            notes: task.notes,
            status: newStatus,
            due: task.due,
            completed: completedTimestamp,
            updated: task.updated
        )
        
        // Update the task first
        await updateTask(updatedTask, in: listId, for: kind)
        

    }
    
    func updateTask(_ task: GoogleTask, in listId: String, for kind: GoogleAuthManager.AccountKind) async {
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
            
            // Update local state
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
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to update task: \(error.localizedDescription)"
            }
        }
    }
    
    func deleteTask(_ task: GoogleTask, from listId: String, for kind: GoogleAuthManager.AccountKind) async {
        do {
            try await deleteTaskFromServer(task, from: listId, for: kind)
            
            // Update local state
            await MainActor.run {
                switch kind {
                case .personal:
                    self.personalTasks[listId]?.removeAll { $0.id == task.id }
                case .professional:
                    self.professionalTasks[listId]?.removeAll { $0.id == task.id }
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to delete task: \(error.localizedDescription)"
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
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TasksError.invalidResponse
        }
        
        if httpResponse.statusCode != 204 {
            throw TasksError.apiError(httpResponse.statusCode)
        }
    }
    
    func moveTask(_ updatedTask: GoogleTask, from sourceListId: String, to targetListId: String, for kind: GoogleAuthManager.AccountKind) async {
        do {
            // First create the task in the target list
            try await createTaskOnServer(updatedTask, in: targetListId, for: kind)
            
            // Then delete from source list using original task ID
            try await deleteTaskFromServer(updatedTask, from: sourceListId, for: kind)
            
            // Update local state
            await MainActor.run {
                switch kind {
                case .personal:
                    // Remove from source list
                    self.personalTasks[sourceListId]?.removeAll { $0.id == updatedTask.id }
                    
                    // Add to target list
                    if self.personalTasks[targetListId] != nil {
                        self.personalTasks[targetListId]?.append(updatedTask)
                    } else {
                        self.personalTasks[targetListId] = [updatedTask]
                    }
                    
                case .professional:
                    // Remove from source list
                    self.professionalTasks[sourceListId]?.removeAll { $0.id == updatedTask.id }
                    
                    // Add to target list
                    if self.professionalTasks[targetListId] != nil {
                        self.professionalTasks[targetListId]?.append(updatedTask)
                    } else {
                        self.professionalTasks[targetListId] = [updatedTask]
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to move task: \(error.localizedDescription)"
            }
        }
    }
    
    func crossAccountMoveTask(_ updatedTask: GoogleTask, from source: (GoogleAuthManager.AccountKind, String), to target: (GoogleAuthManager.AccountKind, String)) async {
        do {
            // Create task in target account
            try await createTaskOnServer(updatedTask, in: target.1, for: target.0)
            
            // Delete from source account
            try await deleteTaskFromServer(updatedTask, from: source.1, for: source.0)
            
            // Update local state
            await MainActor.run {
                // Remove from source
                switch source.0 {
                case .personal:
                    self.personalTasks[source.1]?.removeAll { $0.id == updatedTask.id }
                case .professional:
                    self.professionalTasks[source.1]?.removeAll { $0.id == updatedTask.id }
                }
                
                // Add to target
                switch target.0 {
                case .personal:
                    if self.personalTasks[target.1] != nil {
                        self.personalTasks[target.1]?.append(updatedTask)
                    } else {
                        self.personalTasks[target.1] = [updatedTask]
                    }
                case .professional:
                    if self.professionalTasks[target.1] != nil {
                        self.professionalTasks[target.1]?.append(updatedTask)
                    } else {
                        self.professionalTasks[target.1] = [updatedTask]
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to move task across accounts: \(error.localizedDescription)"
            }
        }
    }
    
    func createTaskOnServer(_ task: GoogleTask, in listId: String, for kind: GoogleAuthManager.AccountKind) async throws {
        print("🌐 Creating task on server: '\(task.title)' in list '\(listId)'")
        
        guard let accessToken = try await getAccessTokenThrows(for: kind) else {
            print("❌ No access token available for \(kind)")
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
        
        print("📤 Request body: \(requestBody)")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw TasksError.invalidResponse
        }
        
        print("📥 Response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            print("❌ API error - Status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("   Response body: \(responseString)")
            }
            throw TasksError.apiError(httpResponse.statusCode)
        }
        
        print("✅ Task created successfully on server")
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
    
    func createTask(title: String, notes: String?, dueDate: Date?, in listId: String, for kind: GoogleAuthManager.AccountKind) async {
        print("🔄 Creating task: '\(title)' in list '\(listId)' for \(kind)")
        
        let dueDateString: String?
        if let dueDate = dueDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dueDateString = formatter.string(from: dueDate)
            print("   Due date: \(dueDateString ?? "nil")")
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
        
        do {
            try await createTaskOnServer(task, in: listId, for: kind)
            print("✅ Task created successfully, reloading tasks...")
            
            // Reload tasks to get the actual task from server with correct ID
            await loadTasks()
        } catch {
            print("❌ Failed to create task: \(error)")
            print("   Error type: \(type(of: error))")
            await MainActor.run {
                self.errorMessage = "Failed to create task: \(error.localizedDescription)"
            }
        }
    }
    
    func updateTaskListOrder(_ newOrder: [GoogleTaskList], for kind: GoogleAuthManager.AccountKind) async {
        print("Updating task list order for \(kind)")
        await MainActor.run {
            switch kind {
            case .personal:
                self.personalTaskLists = newOrder
            case .professional:
                self.professionalTaskLists = newOrder
            }
        }
        print("New order for \(kind): \(newOrder.map { $0.title })")

        // Save the order locally since Google Tasks API doesn't support task list ordering
        saveTaskListOrder(newOrder.map { $0.id }, for: kind)
    }

    private func saveTaskListOrder(_ order: [String], for kind: GoogleAuthManager.AccountKind) {
        let key = "taskListOrder_\(kind.rawValue)"
        UserDefaults.standard.set(order, forKey: key)
        print("Saved task list order for \(kind): \(order)")
    }

    private func loadTaskListOrder(for kind: GoogleAuthManager.AccountKind) -> [String]? {
        let key = "taskListOrder_\(kind.rawValue)"
        return UserDefaults.standard.stringArray(forKey: key)
    }

    private func applySavedOrder(_ taskLists: [GoogleTaskList], for kind: GoogleAuthManager.AccountKind) -> [GoogleTaskList] {
        guard let savedOrder = loadTaskListOrder(for: kind) else {
            // No saved order, return original order
            return taskLists
        }

        // Create a dictionary for quick lookup
        let taskListDict = Dictionary(uniqueKeysWithValues: taskLists.map { ($0.id, $0) })

        // Reorder based on saved order, keeping any new lists at the end
        var orderedLists: [GoogleTaskList] = []
        for listId in savedOrder {
            if let taskList = taskListDict[listId] {
                orderedLists.append(taskList)
            }
        }

        // Add any new task lists that weren't in the saved order
        for taskList in taskLists {
            if !orderedLists.contains(where: { $0.id == taskList.id }) {
                orderedLists.append(taskList)
            }
        }

        print("Applied saved order for \(kind): \(orderedLists.map { $0.title })")
        return orderedLists
    }
    
    func moveTaskList(_ listId: String, toAccount targetAccount: GoogleAuthManager.AccountKind) async {
        await MainActor.run {
            if let listIndex = personalTaskLists.firstIndex(where: { $0.id == listId }) {
                let taskList = personalTaskLists.remove(at: listIndex)
                professionalTaskLists.append(taskList)
                print("Moved task list \(taskList.title) to professional account")

                // Update orders for both accounts
                saveTaskListOrder(personalTaskLists.map { $0.id }, for: .personal)
                saveTaskListOrder(professionalTaskLists.map { $0.id }, for: .professional)
            } else if let listIndex = professionalTaskLists.firstIndex(where: { $0.id == listId }) {
                let taskList = professionalTaskLists.remove(at: listIndex)
                personalTaskLists.append(taskList)
                print("Moved task list \(taskList.title) to personal account")

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
        print("Cleared saved task list order for \(kind)")
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
    @State private var selectedFilter: TaskFilter = .all
    @State private var referenceDate: Date = Date()
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    @State private var showingAddItem = false
    // Personal/Professional task divider
    @State private var tasksPersonalWidth: CGFloat = UIScreen.main.bounds.width * 0.5
    @State private var isTasksDividerDragging = false
    @State private var showingTaskDetails = false
    @State private var showingNewTask = false
    @State private var showingAddEvent = false
    @State private var allSubfilter: AllTaskSubfilter = .all
    
    // Navigation date picker state
    @State private var showingNavigationDatePicker = false
    @State private var selectedDateForNavigation = Date()
    
    var body: some View {
        GeometryReader { geometry in
            if authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional) {
                HStack(spacing: 0) {
                    // Personal Tasks Column
                    if authManager.isLinked(kind: .personal) {
                        TasksComponent(
                            taskLists: viewModel.personalTaskLists,
                            tasksDict: filteredTasks(viewModel.personalTasks),
                            accentColor: appPrefs.personalColor,
                            accountType: .personal,
                            onTaskToggle: { task, listId in
                                Task {
                                    await viewModel.toggleTaskCompletion(task, in: listId, for: .personal)
                                }
                            },
                            onTaskDetails: { task, listId in
                                selectedTask = task
                                selectedTaskListId = listId
                                selectedAccountKind = .personal
                                showingTaskDetails = true
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
                            }
                        )
                        .frame(width: authManager.isLinked(kind: .professional) ? tasksPersonalWidth : geometry.size.width, alignment: .topLeading)
                    }
                    
                    // Vertical divider (only show if both accounts are linked)
                    if authManager.isLinked(kind: .personal) && authManager.isLinked(kind: .professional) {
                        tasksViewDivider
                    }
                    
                    // Professional Tasks Column
                    if authManager.isLinked(kind: .professional) {
                        TasksComponent(
                            taskLists: viewModel.professionalTaskLists,
                            tasksDict: filteredTasks(viewModel.professionalTasks),
                            accentColor: appPrefs.professionalColor,
                            accountType: .professional,
                            onTaskToggle: { task, listId in
                                Task {
                                    await viewModel.toggleTaskCompletion(task, in: listId, for: .professional)
                                }
                            },
                            onTaskDetails: { task, listId in
                                selectedTask = task
                                selectedTaskListId = listId
                                selectedAccountKind = .professional
                                showingTaskDetails = true
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
                            }
                        )
                        .frame(width: authManager.isLinked(kind: .personal) ? (geometry.size.width - tasksPersonalWidth - 8) : geometry.size.width, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, 0)
                .padding(.vertical, 16)
                
                // Debug overlay - only show when no tasks are visible
                if shouldShowDebugInfo {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Debug Info")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Text("Personal: \(authManager.isLinked(kind: .personal) ? "✓" : "✗") linked")
                                Text("Professional: \(authManager.isLinked(kind: .professional) ? "✓" : "✗") linked")
                                Text("Personal lists: \(viewModel.personalTaskLists.count)")
                                Text("Professional lists: \(viewModel.professionalTaskLists.count)")
                                Text("Total tasks: \(totalTaskCount)")
                                Text("Filter: \(selectedFilter.rawValue)")
                                Text("Loading: \(viewModel.isLoading ? "Yes" : "No")")
                                if !viewModel.errorMessage.isEmpty {
                                    Text("Error: \(viewModel.errorMessage)")
                                        .foregroundColor(.red)
                                }
                            }
                            .font(.caption2)
                            .padding(8)
                            .background(Color.black.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 80)
                    }
                }
            } else {
                // No accounts linked
                VStack(spacing: 24) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("Link Your Google Account")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Connect your Google account to view and manage your tasks")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Loading overlay
            if viewModel.isLoading {
                ProgressView("Loading tasks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
            }
        }
        .background(Color(.systemGroupedBackground))
        .sidebarToggleHidden()
        .onAppear {
            Task {
                await viewModel.loadTasks()
            }
        }
        .sheet(isPresented: $showingTaskDetails) {
            if let task = selectedTask, let listId = selectedTaskListId, let accountKind = selectedAccountKind {
                TaskDetailsView(
                    task: task,
                    taskListId: listId,
                    accountKind: accountKind,
                    accentColor: accountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor,
                    personalTaskLists: viewModel.personalTaskLists,
                    professionalTaskLists: viewModel.professionalTaskLists,
                    appPrefs: appPrefs,
                    viewModel: viewModel,
                    onSave: { updatedTask in
                        Task {
                            await viewModel.updateTask(updatedTask, in: listId, for: accountKind)
                        }
                    },
                    onDelete: {
                        Task {
                            await viewModel.deleteTask(task, from: listId, for: accountKind)
                        }
                    },
                    onMove: { updatedTask, targetListId in
                        Task {
                            await viewModel.moveTask(updatedTask, from: listId, to: targetListId, for: accountKind)
                        }
                    },
                    onCrossAccountMove: { updatedTask, targetAccountKind, targetListId in
                        Task {
                            await viewModel.crossAccountMoveTask(updatedTask, from: (accountKind, listId), to: (targetAccountKind, targetListId))
                        }
                    },
                    isNew: false
                )
            }
        }
        .sheet(isPresented: $showingNewTask) {
            // Use the same UI as Task Details for creating a task
            let personalLinked = authManager.isLinked(kind: .personal)
            let professionalLinked = authManager.isLinked(kind: .professional)
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
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingNavigationDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            navigateToDate(selectedDateForNavigation)
                            showingNavigationDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }

        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                HStack(spacing: 6) {
                    SharedNavigationToolbar()
                    
                    if selectedFilter == .all {
                        Text("All")
                            .font(.title2)
                            .fontWeight(.semibold)
                    } else {
                        Button(action: { step(-1) }) { Image(systemName: "chevron.left") }
                        Button(action: {
                            selectedDateForNavigation = referenceDate
                            showingNavigationDatePicker = true
                        }) {
                            Text(subtitleForFilter(selectedFilter))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                        Button(action: { step(1) }) { Image(systemName: "chevron.right") }
                    }
                }
            }

            ToolbarItemGroup(placement: .principal) { EmptyView() }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Filter Menu (ordered: Day, Week, Month, Year) + All dropdown
                    ForEach([TaskFilter.day, .week, .month, .year], id: \.self) { filter in
                        Button(action: {
                            selectedFilter = filter
                            referenceDate = Date() // reset reference when changing view
                            
                            // Sync with NavigationManager if possible
                            if let timelineInterval = filter.timelineInterval {
                                navigationManager.updateInterval(timelineInterval, date: Date())
                            }
                        }) {
                            Image(systemName: filter.sfSymbol)
                                .font(.body)
                                .foregroundColor(filter == selectedFilter ? .accentColor : .secondary)
                        }
                    }
                    // All dropdown menu
                    Menu {
                        Button("All") {
                            selectedFilter = .all
                            allSubfilter = .all
                        }
                        Button("Has Due Date") {
                            selectedFilter = .all
                            allSubfilter = .hasDueDate
                        }
                        Button("No Due Date") {
                            selectedFilter = .all
                            allSubfilter = .noDueDate
                        }
                        Button("Past Due") {
                            selectedFilter = .all
                            allSubfilter = .pastDue
                        }
                        Button("Completed") {
                            selectedFilter = .all
                            allSubfilter = .completed
                        }
                    } label: {
                        Image(systemName: TaskFilter.all.sfSymbol)
                            .font(.body)
                            .foregroundColor(selectedFilter == .all ? .accentColor : .secondary)
                    }
                    
                    // Toggle Hide Completed Tasks
                    Button(action: {
                        appPrefs.updateHideCompletedTasks(!appPrefs.hideCompletedTasks)
                    }) {
                        Image(systemName: appPrefs.hideCompletedTasks ? "eye.slash.circle" : "eye.circle")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    // Add menu: Event or Task
                    Menu {
                        Button("Event") {
                            showingAddEvent = true
                        }
                        Button("Task") {
                            showingNewTask = true
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .disabled(!authManager.isLinked(kind: .personal) && !authManager.isLinked(kind: .professional))
                }
            }
        }
        .sheet(isPresented: $showingAddEvent) {
            // Launch event creation modal from Tasks view
            AddItemView(
                currentDate: referenceDate,
                tasksViewModel: viewModel,
                calendarViewModel: calendarViewModel,
                appPrefs: appPrefs
            )
        }
        .onAppear {
            // Sync with NavigationManager's current interval when view appears
            selectedFilter = navigationManager.currentInterval.taskFilter
            referenceDate = navigationManager.currentDate
            // Listen for external requests to show Add Task so behavior matches Calendar
            NotificationCenter.default.addObserver(forName: Notification.Name("LPV3_ShowAddTask"), object: nil, queue: .main) { _ in
                showingNewTask = true
            }
        }
    }
    
    private var tasksViewDivider: some View {
        Rectangle()
            .fill(isTasksDividerDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 8)
            .overlay(
                Image(systemName: "line.3.vertical")
                    .font(.caption)
                    .foregroundColor(isTasksDividerDragging ? .white : .gray)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isTasksDividerDragging = true
                        let newWidth = tasksPersonalWidth + value.translation.width
                        tasksPersonalWidth = max(200, min(UIScreen.main.bounds.width - 200, newWidth))
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
    private func filteredTasks(_ tasksDict: [String: [GoogleTask]]) -> [String: [GoogleTask]] {
        let calendar = Calendar.mondayFirst // Use consistent calendar
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        
        return tasksDict.mapValues { tasks in
            var filteredTasks = tasks
            
            // Hide completed tasks if preference is on
            if appPrefs.hideCompletedTasks {
                filteredTasks = filteredTasks.filter { !$0.isCompleted }
            }
            
            // Apply subfilter when in "All"
            if selectedFilter == .all {
                switch allSubfilter {
                case .all:
                    break
                case .hasDueDate:
                    filteredTasks = filteredTasks.filter { $0.dueDate != nil }
                case .noDueDate:
                    filteredTasks = filteredTasks.filter { $0.dueDate == nil }
                case .pastDue:
                    let cal = Calendar.mondayFirst
                    let startOfToday = cal.startOfDay(for: Date())
                    filteredTasks = filteredTasks.filter { task in
                        if let due = task.dueDate {
                            return cal.startOfDay(for: due) < startOfToday && !task.isCompleted
                        }
                        return false
                    }
                case .completed:
                    filteredTasks = filteredTasks.filter { $0.isCompleted }
                }
            } else {
                // Then apply time-based filter if not "all"
                print("🔍 Filtering tasks for \(selectedFilter.rawValue) view on \(referenceDate)")
                filteredTasks = filteredTasks.filter { task in
                    // For completed tasks, check completion date
                    if task.isCompleted {
                        guard let completionDate = task.completionDate else { 
                            print("🐛 Completed task '\(task.title)' has no completion date")
                            return false 
                        }
                        let isMatch: Bool
                        switch selectedFilter {
                        case .day:
                            isMatch = calendar.isDate(completionDate, inSameDayAs: referenceDate)
                        case .week:
                            isMatch = calendar.isDate(completionDate, equalTo: referenceDate, toGranularity: .weekOfYear)
                        case .month:
                            isMatch = calendar.isDate(completionDate, equalTo: referenceDate, toGranularity: .month)
                        case .year:
                            isMatch = calendar.isDate(completionDate, equalTo: referenceDate, toGranularity: .year)
                        case .all:
                            isMatch = true
                        }
                        
                        if selectedFilter == .day && !isMatch {
                            let formatter = DateFormatter()
                            formatter.dateStyle = .short
                            formatter.timeStyle = .short
                            print("🐛 TasksView: Completed task '\(task.title)' completed at \(formatter.string(from: completionDate)) not showing on \(formatter.string(from: referenceDate))")
                            print("   Raw completed string: '\(task.completed ?? "nil")'")
                            print("   Parsed completion date: \(completionDate)")
                        }
                        
                        return isMatch
                    } else {
                        // For incomplete tasks, check due date
                        print("🔍 Processing incomplete task: '\(task.title)' due: '\(task.due ?? "nil")'")
                        guard let dueDate = task.dueDate else { 
                            print("🐛 Incomplete task '\(task.title)' has no due date")
                            return false 
                        }
                        let isMatch: Bool
                        switch selectedFilter {
                        case .day:
                            // Show task on due date OR if it's overdue (due date < start of reference date)
                            let startOfReferenceDate = calendar.startOfDay(for: referenceDate)
                            let startOfDueDate = calendar.startOfDay(for: dueDate)
                            isMatch = calendar.isDate(dueDate, inSameDayAs: referenceDate) || startOfDueDate < startOfReferenceDate
                        case .week:
                            isMatch = calendar.isDate(dueDate, equalTo: referenceDate, toGranularity: .weekOfYear)
                        case .month:
                            isMatch = calendar.isDate(dueDate, equalTo: referenceDate, toGranularity: .month)
                        case .year:
                            isMatch = calendar.isDate(dueDate, equalTo: referenceDate, toGranularity: .year)
                        case .all:
                            isMatch = true
                        }
                        
                        if selectedFilter == .day && !isMatch {
                            let formatter = DateFormatter()
                            formatter.dateStyle = .full
                            formatter.timeStyle = .none
                            let debugStartOfReferenceDate = calendar.startOfDay(for: referenceDate)
                            let debugStartOfDueDate = calendar.startOfDay(for: dueDate)
                            print("🐛 TasksView: Task '\(task.title)' due \(formatter.string(from: dueDate)) not showing on view date \(formatter.string(from: referenceDate))")
                            print("   Raw due string: '\(task.due ?? "nil")'")
                            print("   Parsed due date: \(dueDate)")
                            print("   Calendar comparison result: \(calendar.isDate(dueDate, inSameDayAs: referenceDate))")
                            print("   Overdue check: \(debugStartOfDueDate) < \(debugStartOfReferenceDate) = \(debugStartOfDueDate < debugStartOfReferenceDate)")
                            
                            // Show day components for debugging
                            let dueComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
                            let refComponents = calendar.dateComponents([.year, .month, .day], from: referenceDate)
                            print("   Due date components: \(dueComponents)")
                            print("   Reference components: \(refComponents)")
                        }
                        
                        if isMatch {
                            print("✅ Task '\(task.title)' matches filter criteria")
                        }
                        
                        return isMatch
                    }
                }
            }
            
            return filteredTasks
        }
    }
    
    private func isDueDateOverdue(dueDate: Date) -> Bool {
        let calendar = Calendar.mondayFirst
        let today = calendar.startOfDay(for: Date())
        return dueDate < today
    }
    
    // MARK: - Subtitle helper
    private func subtitleForFilter(_ filter: TaskFilter) -> String {
        let cal = Calendar.mondayFirst
        let now = Date()
        let formatter = DateFormatter()
        switch filter {
        case .all:
            return ""
        case .day:
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: referenceDate)
        case .week:
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: referenceDate)?.start,
                  let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: weekStart)
            let endStr = formatter.string(from: weekEnd)
            formatter.dateFormat = "yyyy"
            let yearStr = formatter.string(from: referenceDate)
            return "\(startStr) - \(endStr), \(yearStr)"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: referenceDate)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: referenceDate)
        }
    }
    
    private func navigateToDate(_ selectedDate: Date) {
        switch selectedFilter {
        case .day:
            // For day view, navigate directly to the selected date
            referenceDate = selectedDate
        case .week:
            // For week view, navigate to the week containing the selected date
            let calendar = Calendar.mondayFirst
            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start {
                referenceDate = weekStart
            } else {
                referenceDate = selectedDate
            }
        case .month:
            // For month view, navigate to the month containing the selected date
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            if let firstOfMonth = calendar.date(from: components) {
                referenceDate = firstOfMonth
            } else {
                referenceDate = selectedDate
            }
        case .year:
            // For year view, navigate to the year containing the selected date
            let calendar = Calendar.current
            let year = calendar.component(.year, from: selectedDate)
            if let firstOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) {
                referenceDate = firstOfYear
            } else {
                referenceDate = selectedDate
            }
        case .all:
            // For "all" view, don't change the reference date as it shows all tasks
            break
        }
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            HStack {
                Image(systemName: icon)
                    .foregroundColor(accentColor)
                    .font(.title2)
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(accentColor)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.1))
            )
            
            // Content Area
            if isLinked {
                if taskLists.isEmpty {
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
                } else {
                    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(taskLists) { taskList in
                                let filteredTasks = tasksDict[taskList.id] ?? []
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
                                        onTaskDetails: { task in
                                            onTaskDetails(task, taskList.id)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "\(icon.replacingOccurrences(of: ".circle.fill", with: ".badge.plus"))")
                        .font(.system(size: 50))
                        .foregroundColor(accentColor.opacity(0.6))
                    Text("Link \(title) Account")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(accentColor)
                    Text("Connect your \(title.lowercased()) Google account to view and manage your tasks")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .font(.body)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            }
        }
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: accentColor.opacity(0.2), radius: 12, x: 0, y: 6)
        )
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
    let onTaskDetails: (GoogleTask) -> Void
    
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
                                    onTaskDetails(task)
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
                Text(dueDate, style: .date)
                    .font(.caption)
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
    @State private var showingDatePicker = false
    @State private var showingDeleteAlert = false
    @State private var isSaving = false
    @State private var tempDueDate: Date = Date()
    
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
        
        _editedTitle = State(initialValue: task.title)
        _editedNotes = State(initialValue: task.notes ?? "")
        _editedDueDate = State(initialValue: task.dueDate)
        _selectedAccountKind = State(initialValue: accountKind)
        _selectedListId = State(initialValue: taskListId)
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
        editedDueDate != task.dueDate ||
        selectedAccountKind != accountKind ||
        selectedListId != taskListId ||
        isCreatingNewList
    }
    
    var canSave: Bool {
        !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        ((!isCreatingNewList && !selectedListId.isEmpty) || 
         (isCreatingNewList && !newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Title only (no section header, no label)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Task title", text: $editedTitle)
                        .font(.title3)
                }
                
                // Notes (no label)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Add description", text: $editedNotes, axis: .vertical)
                        .lineLimit(1...6)
                }
                
                // Account & Task List (no section title/subtitle)
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
                
                // Inline Due Date row (no section, no label)
                HStack(spacing: 12) {
                    Button(action: {
                        // Initialize temp picker date but do not change the actual due date yet
                        tempDueDate = editedDueDate ?? Date()
                        showingDatePicker = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .foregroundColor(accentColor)
                            if let dueDate = editedDueDate {
                                Text(dueDate, formatter: dueDateFormatter)
                                    .foregroundColor(.primary)
                            } else {
                                Text("Add due date")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if editedDueDate != nil {
                        Button(action: { editedDueDate = nil }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Removed Task Status section per request
                
                if !isNew {
                    Section {
                        Button("Delete Task") {
                            showingDeleteAlert = true
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
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
                }
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("Due Date", selection: $tempDueDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, Calendar.mondayFirst)
                .navigationTitle("Set Due Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingDatePicker = false
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            // Apply selected date to actual due date only on Done
                            editedDueDate = tempDueDate
                            showingDatePicker = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .frame(maxHeight: 400)
            .presentationDetents([.large])
        }
        .alert("Delete Task", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete '\(task.title)'? This action cannot be undone.")
        }
    }
    
    private func saveTask() {
        isSaving = true
        
        Task {
            do {
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
                    await viewModel.createTask(
                        title: updatedTask.title,
                        notes: updatedTask.notes,
                        dueDate: editedDueDate,
                        in: targetListId,
                        for: selectedAccountKind
                    )
                    await MainActor.run {
                        dismiss()
                    }
                } else {
                    // Editing path (perform updates directly to ensure they complete)
                    if selectedAccountKind != accountKind {
                        await viewModel.crossAccountMoveTask(updatedTask, from: (accountKind, taskListId), to: (selectedAccountKind, targetListId))
                    } else if targetListId != taskListId {
                        await viewModel.moveTask(updatedTask, from: taskListId, to: targetListId, for: selectedAccountKind)
                    } else {
                        await viewModel.updateTask(updatedTask, in: targetListId, for: selectedAccountKind)
                    }
                    // Reload to ensure UI reflects server state
                    await viewModel.loadTasks()
                    await MainActor.run { dismiss() }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    // Handle error (could show alert)
                    print("Failed to save task: \(error)")
                }
            }
        }
    }
}

#Preview {
    TasksView()
} 

