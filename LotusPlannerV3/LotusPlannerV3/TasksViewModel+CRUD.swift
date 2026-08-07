import Foundation

/// CRUD operations on `TasksViewModel`. Split out from the main file to
/// keep the loading + caching half (~450 lines) separately readable from
/// this ~900-line block of task/task-list mutations. All methods here
/// drive Google Tasks API calls + update the in-memory `account1Tasks` /
/// `account2Tasks` dicts; the loading half (in `TasksViewModel.swift`)
/// is responsible for fetch and cache invalidation.
extension TasksViewModel {

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
            case .account1:
                if account1Tasks[listId] != nil {
                    account1Tasks[listId]?.append(createdTask)
                } else {
                    account1Tasks[listId] = [createdTask]
                }
            case .account2:
                if account2Tasks[listId] != nil {
                    account2Tasks[listId]?.append(createdTask)
                } else {
                    account2Tasks[listId] = [createdTask]
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
            case .account1:
                if var tasks = self.account1Tasks[listId] {
                    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[index] = task
                        self.account1Tasks[listId] = tasks
                    }
                }
            case .account2:
                if var tasks = self.account2Tasks[listId] {
                    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[index] = task
                        self.account2Tasks[listId] = tasks
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
                
                await MainActor.run {
                    self.upsertTaskInCache(task, in: listId, for: kind)
                }
            } catch {
                // REVERT OPTIMISTIC UPDATE on error
                if let original = originalTask {
                    await MainActor.run {
                        switch kind {
                        case .account1:
                            if var tasks = self.account1Tasks[listId] {
                                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                    tasks[index] = original
                                    self.account1Tasks[listId] = tasks
                                }
                            }
                        case .account2:
                            if var tasks = self.account2Tasks[listId] {
                                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                    tasks[index] = original
                                    self.account2Tasks[listId] = tasks
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
            case .account1:
                return account1Tasks[listId]?.first { $0.id == taskId }
            case .account2:
                return account2Tasks[listId]?.first { $0.id == taskId }
            }
        }
    }
    
    func deleteTask(_ task: GoogleTask, from listId: String, for kind: GoogleAuthManager.AccountKind) async {
        // OPTIMISTIC DELETE: Remove from UI immediately
        await MainActor.run {
            switch kind {
            case .account1:
                self.account1Tasks[listId]?.removeAll { $0.id == task.id }
            case .account2:
                self.account2Tasks[listId]?.removeAll { $0.id == task.id }
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

                await MainActor.run {
                    self.removeTaskFromCache(taskId: task.id, from: listId, for: kind)
                }
            } catch {
                // REVERT OPTIMISTIC DELETE on error - restore the task
                await MainActor.run {
                    switch kind {
                    case .account1:
                        if self.account1Tasks[listId] != nil {
                            self.account1Tasks[listId]?.append(task)
                        } else {
                            self.account1Tasks[listId] = [task]
                        }
                    case .account2:
                        if self.account2Tasks[listId] != nil {
                            self.account2Tasks[listId]?.append(task)
                        } else {
                            self.account2Tasks[listId] = [task]
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

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TasksError.invalidResponse
        }

        if httpResponse.statusCode != 204 {
            throw TasksError.apiError(httpResponse.statusCode)
        }
    }
    
    func moveTask(_ updatedTask: GoogleTask, from sourceListId: String, to targetListId: String, for kind: GoogleAuthManager.AccountKind) async -> GoogleTask? {
        // First, get the original task from local state to ensure we have the correct server ID
        let originalTask = await MainActor.run {
            switch kind {
            case .account1:
                return account1Tasks[sourceListId]?.first { $0.id == updatedTask.id }
            case .account2:
                return account2Tasks[sourceListId]?.first { $0.id == updatedTask.id }
            }
        }

        // CRITICAL: We MUST find the original task in local state to get the correct server ID
        guard let taskToDelete = originalTask else {
            await MainActor.run {
                self.errorMessage = "Cannot find original task to move"
            }
            return nil
        }

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
                case .account1:
                    self.account1Tasks[sourceListId]?.removeAll { $0.id == originalTaskId }

                    // Add to target list using new task (with server ID)
                    if self.account1Tasks[targetListId] != nil {
                        self.account1Tasks[targetListId]?.append(taskToAdd)
                    } else {
                        self.account1Tasks[targetListId] = [taskToAdd]
                    }

                case .account2:
                    self.account2Tasks[sourceListId]?.removeAll { $0.id == originalTaskId }

                    // Add to target list using new task (with server ID)
                    if self.account2Tasks[targetListId] != nil {
                        self.account2Tasks[targetListId]?.append(taskToAdd)
                    } else {
                        self.account2Tasks[targetListId] = [taskToAdd]
                    }
                }

                self.moveTaskInCache(
                    originalTaskId: originalTaskId,
                    replacementTask: taskToAdd,
                    from: sourceListId,
                    to: targetListId,
                    sourceKind: kind,
                    targetKind: kind
                )

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
            case .account1:
                return account1Tasks[source.1]?.first { $0.id == updatedTask.id }
            case .account2:
                return account2Tasks[source.1]?.first { $0.id == updatedTask.id }
            }
        }

        // CRITICAL: We MUST find the original task in local state to get the correct server ID
        guard let taskToDelete = originalTask else {
            await MainActor.run {
                self.errorMessage = "Cannot find original task to move"
            }
            return nil
        }

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
                case .account1:
                    self.account1Tasks[source.1]?.removeAll { $0.id == originalTaskId }
                case .account2:
                    self.account2Tasks[source.1]?.removeAll { $0.id == originalTaskId }
                }

                // Add to target account using new task (with server ID)
                switch target.0 {
                case .account1:
                    if self.account1Tasks[target.1] != nil {
                        self.account1Tasks[target.1]?.append(taskToAdd)
                    } else {
                        self.account1Tasks[target.1] = [taskToAdd]
                    }
                case .account2:
                    if self.account2Tasks[target.1] != nil {
                        self.account2Tasks[target.1]?.append(taskToAdd)
                    } else {
                        self.account2Tasks[target.1] = [taskToAdd]
                    }
                }

                self.moveTaskInCache(
                    originalTaskId: originalTaskId,
                    replacementTask: taskToAdd,
                    from: source.1,
                    to: target.1,
                    sourceKind: source.0,
                    targetKind: target.0
                )

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
                case .account1:
                    self.account1TaskLists.append(taskList)
                    self.account1Tasks[taskList.id] = []
                    self.upsertTaskListInCache(taskList, for: .account1)
                    // Save updated order
                    saveTaskListOrder(account1TaskLists.map { $0.id }, for: .account1)
                case .account2:
                    self.account2TaskLists.append(taskList)
                    self.account2Tasks[taskList.id] = []
                    self.upsertTaskListInCache(taskList, for: .account2)
                    // Save updated order
                    saveTaskListOrder(account2TaskLists.map { $0.id }, for: .account2)
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
                case .account1:
                    if let index = self.account1TaskLists.firstIndex(where: { $0.id == listId }) {
                        let updatedList = GoogleTaskList(id: listId, title: newTitle, updated: self.account1TaskLists[index].updated)
                        self.account1TaskLists[index] = updatedList
                        self.upsertTaskListInCache(updatedList, for: .account1)
                    }
                case .account2:
                    if let index = self.account2TaskLists.firstIndex(where: { $0.id == listId }) {
                        let updatedList = GoogleTaskList(id: listId, title: newTitle, updated: self.account2TaskLists[index].updated)
                        self.account2TaskLists[index] = updatedList
                        self.upsertTaskListInCache(updatedList, for: .account2)
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
            case .account1:
                if account1Tasks[listId] != nil {
                    account1Tasks[listId]?.append(task)
                } else {
                    account1Tasks[listId] = [task]
                }
            case .account2:
                if account2Tasks[listId] != nil {
                    account2Tasks[listId]?.append(task)
                } else {
                    account2Tasks[listId] = [task]
                }
            }
        }
        
        // BACKGROUND SYNC: Create on server in background
        Task {
            do {
                // Get the created task with real server ID
                let createdTask = try await createTaskOnServer(task, in: listId, for: kind)
                
                // Save time window if due date and times are provided
                if dueDate != nil, let startTime = startTime, let endTime = endTime {
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
                    case .account1:
                        if var tasks = account1Tasks[listId] {
                            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                // Replace temporary task with server task that has real ID
                                tasks[index] = createdTask
                                account1Tasks[listId] = tasks
                                replaceTaskInCache(tempId: task.id, with: createdTask, in: listId, for: .account1)
                            }
                        }
                    case .account2:
                        if var tasks = account2Tasks[listId] {
                            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                // Replace temporary task with server task that has real ID
                                tasks[index] = createdTask
                                account2Tasks[listId] = tasks
                                replaceTaskInCache(tempId: task.id, with: createdTask, in: listId, for: .account2)
                            }
                        }
                    }
                    onServerCreated?(createdTask)
                }
            } catch {
                // REVERT OPTIMISTIC CREATE on error - remove the temporary task
                await MainActor.run {
                    switch kind {
                    case .account1:
                        account1Tasks[listId]?.removeAll { $0.id == task.id }
                        removeTaskFromCache(taskId: task.id, from: listId, for: .account1)
                    case .account2:
                        account2Tasks[listId]?.removeAll { $0.id == task.id }
                        removeTaskFromCache(taskId: task.id, from: listId, for: .account2)
                    }
                    self.errorMessage = "Failed to create task: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func updateTaskListOrder(_ newOrder: [GoogleTaskList], for kind: GoogleAuthManager.AccountKind) async {
        
        await MainActor.run {
            switch kind {
            case .account1:
                self.account1TaskLists = newOrder
            case .account2:
                self.account2TaskLists = newOrder
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
            // Delete from account 1 if linked
            if authManager.isLinked(kind: .account1) {
                for (listId, tasks) in account1Tasks {
                    let completedTasks = tasks.filter { $0.isCompleted }
                    for task in completedTasks {
                        try await deleteTaskFromServer(task, from: listId, for: .account1)
                    }
                }
            }
            
            // Delete from account 2 if linked
            if authManager.isLinked(kind: .account2) {
                for (listId, tasks) in account2Tasks {
                    let completedTasks = tasks.filter { $0.isCompleted }
                    for task in completedTasks {
                        try await deleteTaskFromServer(task, from: listId, for: .account2)
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
            if let listIndex = account1TaskLists.firstIndex(where: { $0.id == listId }) {
                let taskList = account1TaskLists.remove(at: listIndex)
                account2TaskLists.append(taskList)
                

                // Update orders for both accounts
                saveTaskListOrder(account1TaskLists.map { $0.id }, for: .account1)
                saveTaskListOrder(account2TaskLists.map { $0.id }, for: .account2)
            } else if let listIndex = account2TaskLists.firstIndex(where: { $0.id == listId }) {
                let taskList = account2TaskLists.remove(at: listIndex)
                account1TaskLists.append(taskList)
                

                // Update orders for both accounts
                saveTaskListOrder(account1TaskLists.map { $0.id }, for: .account1)
                saveTaskListOrder(account2TaskLists.map { $0.id }, for: .account2)
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
                case .account1:
                    self.account1TaskLists.removeAll { $0.id == listId }
                    self.account1Tasks.removeValue(forKey: listId)
                    self.removeTaskListFromCache(listId: listId, for: .account1)
                    // Save updated order
                    saveTaskListOrder(account1TaskLists.map { $0.id }, for: .account1)
                case .account2:
                    self.account2TaskLists.removeAll { $0.id == listId }
                    self.account2Tasks.removeValue(forKey: listId)
                    self.removeTaskListFromCache(listId: listId, for: .account2)
                    // Save updated order
                    saveTaskListOrder(account2TaskLists.map { $0.id }, for: .account2)
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
