import SwiftUI
import Foundation

// MARK: - Google Tasks Data Models
struct GoogleTaskList: Identifiable, Codable {
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.date(from: due)
    }
    
    var completionDate: Date? {
        guard let completed = completed else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.date(from: completed)
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
                            self.personalTaskLists = taskLists
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
                            self.professionalTaskLists = taskLists
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
        print("  Account linked status: \(authManager.isLinked(kind: kind))")
        print("  Account email: \(authManager.getEmail(for: kind))")
        
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
            print("  Error type: \(type(of: error))")
            print("  Error description: \(error.localizedDescription)")
            
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
        
        // Log raw API response
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("📋 RAW TASK LISTS API RESPONSE for \(kind):")
            print(rawResponse)
            print("--- END RAW RESPONSE ---")
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
        
        // Log raw API response
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("📝 RAW TASKS API RESPONSE for \(kind) list \(taskListId):")
            print(rawResponse)
            print("--- END RAW RESPONSE ---")
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
        let updatedTask = GoogleTask(
            id: task.id,
            title: task.title,
            notes: task.notes,
            status: newStatus,
            due: task.due,
            completed: task.completed,
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
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TasksError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw TasksError.apiError(httpResponse.statusCode)
        }
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
                case .professional:
                    self.professionalTaskLists.append(taskList)
                    self.professionalTasks[taskList.id] = []
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
    
    func createTask(title: String, notes: String?, dueDate: Date?, in listId: String, for kind: GoogleAuthManager.AccountKind) async {
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
        
        do {
            try await createTaskOnServer(task, in: listId, for: kind)
            
            // Reload tasks to get the actual task from server with correct ID
            await loadTasks()
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to create task: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Task Filter Enum
enum TaskFilter: String, CaseIterable {
    case all = "All"
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case thisYear = "This Year"
    
    var icon: String {
        switch self {
        case .all: return "line.horizontal.3.decrease.circle"
        case .today: return "calendar"
        case .thisWeek: return "calendar"
        case .thisMonth: return "calendar"
        case .thisYear: return "calendar"
        }
    }
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
    @StateObject private var viewModel = TasksViewModel()
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @ObservedObject private var appPrefs = AppPreferences.shared
    @State private var selectedFilter: TaskFilter = .all
    @State private var selectedTask: GoogleTask?
    @State private var selectedTaskListId: String?
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind?
    @State private var showingTaskDetails = false
    @State private var showingNewTask = false
    
    var body: some View {
        GeometryReader { geometry in
            if authManager.isLinked(kind: .personal) || authManager.isLinked(kind: .professional) {
                HStack(spacing: 24) {
                    // Personal Tasks Section
                    if authManager.isLinked(kind: .personal) {
                        TasksSectionView(
                            title: "Personal",
                            icon: "person.circle.fill",
                            accentColor: appPrefs.personalColor,
                            isLinked: authManager.isLinked(kind: .personal),
                            taskLists: viewModel.personalTaskLists,
                            tasksDict: filteredTasks(viewModel.personalTasks),
                            accountKind: .personal,
                            filter: selectedFilter,
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
                            width: authManager.isLinked(kind: .professional) ? 
                                (geometry.size.width - 48) / 2 : geometry.size.width - 24
                        )
                    }
                    
                    // Professional Tasks Section  
                    if authManager.isLinked(kind: .professional) {
                        TasksSectionView(
                            title: "Professional",
                            icon: "briefcase.circle.fill",
                            accentColor: appPrefs.professionalColor,
                            isLinked: authManager.isLinked(kind: .professional),
                            taskLists: viewModel.professionalTaskLists,
                            tasksDict: filteredTasks(viewModel.professionalTasks),
                            accountKind: .professional,
                            filter: selectedFilter,
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
                            width: authManager.isLinked(kind: .personal) ? 
                                (geometry.size.width - 48) / 2 : geometry.size.width - 24
                        )
                    }
                }
                .padding(.horizontal, 24)
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
                    }
                )
            }
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskView(
                viewModel: viewModel,
                authManager: authManager,
                appPrefs: appPrefs
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    // Filter Menu
                    Menu {
                        Picker("Filter", selection: $selectedFilter) {
                            ForEach(TaskFilter.allCases, id: \.self) { filter in
                                Label(filter.rawValue, systemImage: filter.icon)
                                    .tag(filter)
                            }
                        }
                    } label: {
                        Image(systemName: selectedFilter.icon)
                            .foregroundColor(.primary)
                    }
                    
                    // Add Task Menu
                    Menu {
                        if authManager.isLinked(kind: .personal) {
                            Button("Personal Task") {
                                selectedAccountKind = .personal
                                showingNewTask = true
                            }
                        }
                        if authManager.isLinked(kind: .professional) {
                            Button("Professional Task") {
                                selectedAccountKind = .professional
                                showingNewTask = true
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.primary)
                    }
                    .disabled(!authManager.isLinked(kind: .personal) && !authManager.isLinked(kind: .professional))
                }
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.automatic)
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
        let calendar = Calendar.mondayFirst
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        
        return tasksDict.mapValues { tasks in
            var filteredTasks = tasks
            
            // First, filter by hide completed tasks setting (disabled for now)
            // if hideCompletedTasks {
            //     filteredTasks = filteredTasks.filter { !$0.isCompleted }
            // }
            
            // Then apply time-based filter if not "all"
            if selectedFilter != .all {
                filteredTasks = filteredTasks.filter { task in
                    if task.isCompleted {
                        // For completed tasks, check if they were completed today/this week/etc.
                        // This requires checking the completion date, but for simplicity,
                        // we'll show all completed tasks when not filtering
                        return true
                    } else {
                        // For incomplete tasks, use due date logic
                        guard let dueDate = task.dueDate else { 
                            return false 
                        }
                        
                        // Check if task is overdue (due date is before today)
                        let isOverdue = dueDate < startOfToday
                        
                        switch selectedFilter {
                        case .all:
                            return true
                        case .today:
                            let isSameDay = calendar.isDate(dueDate, inSameDayAs: now)
                            return isOverdue || isSameDay
                        case .thisWeek:
                            let isSameWeek = calendar.isDate(dueDate, equalTo: now, toGranularity: .weekOfYear)
                            return isOverdue || isSameWeek
                        case .thisMonth:
                            let isSameMonth = calendar.isDate(dueDate, equalTo: now, toGranularity: .month)
                            return isOverdue || isSameMonth
                        case .thisYear:
                            let isSameYear = calendar.isDate(dueDate, equalTo: now, toGranularity: .year)
                            return isOverdue || isSameYear
                        }
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
                    ScrollView {
                        LazyVStack(spacing: 16) {
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
                    } else if !tasks.isEmpty {
                        Text("\(completedTasks)/\(tasks.count) completed")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
    
    private let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    
    init(task: GoogleTask, taskListId: String, accountKind: GoogleAuthManager.AccountKind, accentColor: Color, personalTaskLists: [GoogleTaskList], professionalTaskLists: [GoogleTaskList], appPrefs: AppPreferences, viewModel: TasksViewModel, onSave: @escaping (GoogleTask) -> Void, onDelete: @escaping () -> Void, onMove: @escaping (GoogleTask, String) -> Void, onCrossAccountMove: @escaping (GoogleTask, GoogleAuthManager.AccountKind, String) -> Void) {
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
                Section("Task Details") {
                    HStack {
                        Text("Title")
                        TextField("Task title", text: $editedTitle)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                        TextField("Add notes...", text: $editedNotes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                
                Section("Account & Task List") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Account Selection
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Account")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("Account", selection: $selectedAccountKind) {
                                HStack {
                                    Image(systemName: "person.circle.fill")
                                        .foregroundColor(appPrefs.personalColor)
                                    Text("Personal")
                                }.tag(GoogleAuthManager.AccountKind.personal)
                                
                                HStack {
                                    Image(systemName: "briefcase.circle.fill")
                                        .foregroundColor(appPrefs.professionalColor)
                                    Text("Professional")
                                }.tag(GoogleAuthManager.AccountKind.professional)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedAccountKind) { _, newAccount in
                                // When account changes, reset to first available list
                                if let firstList = availableTaskLists.first {
                                    selectedListId = firstList.id
                                }
                                // Reset new list creation state
                                isCreatingNewList = false
                                newListName = ""
                            }
                        }
                        
                        // Task List Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Move to List")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Create New List Option
                            HStack {
                                Button(action: {
                                    isCreatingNewList.toggle()
                                    if isCreatingNewList {
                                        selectedListId = taskListId // Keep original if creating new
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: isCreatingNewList ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isCreatingNewList ? currentAccentColor : .secondary)
                                        Text("Create new list")
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                Spacer()
                            }
                            
                            if isCreatingNewList {
                                TextField("New list name", text: $newListName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .padding(.leading, 28)
                            }
                            
                            // Existing Lists
                            if !isCreatingNewList && availableTaskLists.count > 1 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Current List: \(currentTaskListName)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 28)
                                    
                                    ForEach(availableTaskLists) { taskList in
                                        HStack {
                                            Button(action: {
                                                selectedListId = taskList.id
                                            }) {
                                                HStack {
                                                    Image(systemName: selectedListId == taskList.id ? "checkmark.circle.fill" : "circle")
                                                        .foregroundColor(selectedListId == taskList.id ? currentAccentColor : .secondary)
                                                    Text(taskList.title)
                                                    if taskList.id == taskListId {
                                                        Text("(current)")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            Spacer()
                                        }
                                        .padding(.leading, 28)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section("Due Date") {
                    HStack {
                        Text("Due Date")
                        Spacer()
                        if let dueDate = editedDueDate {
                            Text(dueDate, formatter: dueDateFormatter)
                                .foregroundColor(.secondary)
                        } else {
                            Text("None")
                                .foregroundColor(.secondary)
                        }
                        Button(action: {
                            showingDatePicker.toggle()
                        }) {
                            Image(systemName: "calendar")
                                .foregroundColor(accentColor)
                        }
                    }
                    
                    if editedDueDate != nil {
                        Button("Remove Due Date") {
                            editedDueDate = nil
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Section("Task Status") {
                    HStack {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(task.isCompleted ? accentColor : .secondary)
                        Text(task.isCompleted ? "Completed" : "Pending")
                            .foregroundColor(task.isCompleted ? .secondary : .primary)
                        Spacer()
                    }
                }
                
                Section {
                    Button("Delete Task") {
                        showingDeleteAlert = true
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        saveTask()
                    }
                    .disabled(!canSave || !hasChanges || isSaving)
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("Due Date", selection: Binding(
                    get: { editedDueDate ?? Date() },
                    set: { editedDueDate = $0 }
                ), displayedComponents: .date)
                .datePickerStyle(.wheel)
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
                            showingDatePicker = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
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
                
                await MainActor.run {
                    // Check if the task is being moved to a different account
                    if selectedAccountKind != accountKind {
                        // Cross-account move: delete from original account and create in new account
                        onCrossAccountMove(updatedTask, selectedAccountKind, targetListId)
                    } else if targetListId != taskListId {
                        // Same account, different list: use the move callback
                        onMove(updatedTask, targetListId)
                    } else {
                        // Same account, same list: just update the task
                        onSave(updatedTask)
                    }
                    
                    dismiss()
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

// MARK: - New Task View
struct NewTaskView: View {
    let viewModel: TasksViewModel
    let authManager: GoogleAuthManager
    let appPrefs: AppPreferences
    
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var selectedAccountKind: GoogleAuthManager.AccountKind = .personal
    @State private var selectedListId = ""
    @State private var newListName = ""
    @State private var isCreatingNewList = false
    @State private var dueDate: Date?
    @State private var showingDatePicker = false
    @State private var isCreating = false
    
    private var availableTaskLists: [GoogleTaskList] {
        selectedAccountKind == .personal ? viewModel.personalTaskLists : viewModel.professionalTaskLists
    }
    
    private var currentAccentColor: Color {
        selectedAccountKind == .personal ? appPrefs.personalColor : appPrefs.professionalColor
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        ((!isCreatingNewList && !selectedListId.isEmpty) || 
         (isCreatingNewList && !newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Task Details") {
                    TextField("Task title", text: $title)
                        .textFieldStyle(.plain)
                    
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                }
                
                Section("Account") {
                    HStack {
                        Text("Account")
                        Spacer()
                        Picker("Account", selection: $selectedAccountKind) {
                            if authManager.isLinked(kind: .personal) {
                                Text("Personal").tag(GoogleAuthManager.AccountKind.personal)
                            }
                            if authManager.isLinked(kind: .professional) {
                                Text("Professional").tag(GoogleAuthManager.AccountKind.professional)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section("List") {
                    HStack {
                        Button(action: {
                            isCreatingNewList.toggle()
                            if !isCreatingNewList && !availableTaskLists.isEmpty {
                                selectedListId = availableTaskLists.first?.id ?? ""
                            }
                        }) {
                            HStack {
                                Image(systemName: isCreatingNewList ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isCreatingNewList ? currentAccentColor : .secondary)
                                Text("Create new list")
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                    }
                    
                    if isCreatingNewList {
                        TextField("List name", text: $newListName)
                            .textFieldStyle(.plain)
                            .padding(.leading, 28)
                    }
                    
                    // Existing Lists
                    if !isCreatingNewList && !availableTaskLists.isEmpty {
                        ForEach(availableTaskLists) { taskList in
                            HStack {
                                Button(action: {
                                    selectedListId = taskList.id
                                }) {
                                    HStack {
                                        Image(systemName: selectedListId == taskList.id ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedListId == taskList.id ? currentAccentColor : .secondary)
                                        Text(taskList.title)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                Spacer()
                            }
                        }
                    }
                    
                    if !isCreatingNewList && availableTaskLists.isEmpty {
                        Text("No lists available. Create a new list above.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .padding(.leading, 28)
                    }
                }
                
                Section("Due Date") {
                    HStack {
                        Text("Due Date")
                        Spacer()
                        if let dueDate = dueDate {
                            Text(dueDate, style: .date)
                                .foregroundColor(.secondary)
                        } else {
                            Text("None")
                                .foregroundColor(.secondary)
                        }
                        Button(action: {
                            showingDatePicker.toggle()
                        }) {
                            Image(systemName: "calendar")
                                .foregroundColor(.accentColor)
                        }
                    }
                    
                    if dueDate != nil {
                        Button("Remove Due Date") {
                            dueDate = nil
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isCreating ? "Creating..." : "Create") {
                        createTask()
                    }
                    .disabled(!canSave || isCreating)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // Set default account and list
            if authManager.isLinked(kind: .personal) {
                selectedAccountKind = .personal
                if !viewModel.personalTaskLists.isEmpty {
                    selectedListId = viewModel.personalTaskLists.first?.id ?? ""
                    isCreatingNewList = false
                } else {
                    isCreatingNewList = true
                }
            } else if authManager.isLinked(kind: .professional) {
                selectedAccountKind = .professional
                if !viewModel.professionalTaskLists.isEmpty {
                    selectedListId = viewModel.professionalTaskLists.first?.id ?? ""
                    isCreatingNewList = false
                } else {
                    isCreatingNewList = true
                }
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("Due Date", selection: Binding(
                    get: { dueDate ?? Date() },
                    set: { dueDate = $0 }
                ), displayedComponents: .date)
                .datePickerStyle(.wheel)
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
                            showingDatePicker = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
    
    private func createTask() {
        isCreating = true
        
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
                            isCreating = false
                        }
                        return
                    }
                    targetListId = newListId
                } else {
                    targetListId = selectedListId
                }
                
                // Prepare due date string
                let dueDateString: String?
                if let dueDate = dueDate {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    formatter.timeZone = TimeZone.current
                    dueDateString = formatter.string(from: dueDate)
                } else {
                    dueDateString = nil
                }
                
                let newTask = GoogleTask(
                    id: UUID().uuidString, // Temporary ID
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: notes.isEmpty ? nil : notes,
                    status: "needsAction",
                    due: dueDateString,
                    completed: nil,
                    updated: nil
                )
                
                await viewModel.createTask(
                    title: newTask.title,
                    notes: newTask.notes,
                    dueDate: newTask.dueDate,
                    in: targetListId,
                    for: selectedAccountKind
                )
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    // Handle error (could show alert)
                    print("Failed to create task: \(error)")
                }
            }
        }
    }
}

#Preview {
    TasksView()
} 

