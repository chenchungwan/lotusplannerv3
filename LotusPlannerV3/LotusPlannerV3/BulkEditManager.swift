//
//  BulkEditManager.swift
//  LotusPlannerV3
//
//  Shared business logic for bulk edit operations
//

import Foundation
import SwiftUI

@MainActor
class BulkEditManager: ObservableObject {
    @Published var state = BulkEditState()

    // MARK: - Bulk Operations

    // MARK: - Multi-list/account bulk operations (for TasksView)

    func bulkComplete(
        tasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)],
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        let tasksToComplete = tasks.filter { state.selectedTaskIds.contains($0.task.id) && !$0.task.isCompleted }

        // Store pre-action state for undo (use first task's list/account for undo data)
        guard let firstTask = tasksToComplete.first else { return }

        // Create mapping of task IDs to their list/account
        var taskListMapping: [String: (listId: String, accountKind: GoogleAuthManager.AccountKind)] = [:]
        for taskInfo in tasksToComplete {
            taskListMapping[taskInfo.task.id] = (listId: taskInfo.listId, accountKind: taskInfo.accountKind)
        }

        let undoData = BulkEditUndoData(
            tasks: tasksToComplete.map { $0.task },
            listId: firstTask.listId,
            accountKind: firstTask.accountKind,
            destinationListId: nil,
            destinationAccountKind: nil,
            originalDueDates: nil,
            originalTimeWindows: nil,
            originalPriorities: nil,
            taskListMapping: taskListMapping,
            count: tasksToComplete.count
        )

        Task {
            for taskInfo in tasksToComplete {
                await tasksVM.toggleTaskCompletion(taskInfo.task, in: taskInfo.listId, for: taskInfo.accountKind)
            }

            await MainActor.run {
                state.reset()
                completion(undoData)
            }
        }
    }

    // MARK: - Single-list/account bulk operations (for ListsView)

    func bulkComplete(
        tasks: [GoogleTask],
        in listId: String,
        for accountKind: GoogleAuthManager.AccountKind,
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        // For single-list operations, all tasks are from the same list, so taskListMapping is not needed
        let tasksWithInfo = tasks.map { (task: $0, listId: listId, accountKind: accountKind) }
        bulkComplete(tasks: tasksWithInfo, tasksVM: tasksVM, completion: completion)
    }

    func bulkDelete(
        tasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)],
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        let tasksToDelete = tasks.filter { state.selectedTaskIds.contains($0.task.id) }

        // Store pre-action state for undo (including time windows)
        var originalTimeWindows: [String: (startTime: Date, endTime: Date, isAllDay: Bool)?] = [:]
        var taskListMapping: [String: (listId: String, accountKind: GoogleAuthManager.AccountKind)] = [:]
        for taskInfo in tasksToDelete {
            if let timeWindow = TaskTimeWindowManager.shared.getTimeWindow(for: taskInfo.task.id) {
                originalTimeWindows[taskInfo.task.id] = (startTime: timeWindow.startTime, endTime: timeWindow.endTime, isAllDay: timeWindow.isAllDay)
            } else {
                originalTimeWindows[taskInfo.task.id] = nil
            }
            taskListMapping[taskInfo.task.id] = (listId: taskInfo.listId, accountKind: taskInfo.accountKind)
        }

        guard let firstTask = tasksToDelete.first else { return }
        let undoData = BulkEditUndoData(
            tasks: tasksToDelete.map { $0.task },
            listId: firstTask.listId,
            accountKind: firstTask.accountKind,
            destinationListId: nil,
            destinationAccountKind: nil,
            originalDueDates: nil,
            originalTimeWindows: originalTimeWindows,
            originalPriorities: nil,
            taskListMapping: taskListMapping,
            count: tasksToDelete.count
        )

        Task {
            for taskInfo in tasksToDelete {
                await tasksVM.deleteTask(taskInfo.task, from: taskInfo.listId, for: taskInfo.accountKind)
            }

            await MainActor.run {
                state.reset()
                completion(undoData)
            }
        }
    }

    func bulkDelete(
        tasks: [GoogleTask],
        in listId: String,
        for accountKind: GoogleAuthManager.AccountKind,
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        let tasksWithInfo = tasks.map { (task: $0, listId: listId, accountKind: accountKind) }
        bulkDelete(tasks: tasksWithInfo, tasksVM: tasksVM, completion: completion)
    }

    func bulkMove(
        tasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)],
        to destinationListId: String,
        destinationAccountKind: GoogleAuthManager.AccountKind,
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        let tasksToMove = tasks.filter { state.selectedTaskIds.contains($0.task.id) }

        // Store pre-action state for undo (including time windows)
        var originalTimeWindows: [String: (startTime: Date, endTime: Date, isAllDay: Bool)?] = [:]
        var taskListMapping: [String: (listId: String, accountKind: GoogleAuthManager.AccountKind)] = [:]
        for taskInfo in tasksToMove {
            if let timeWindow = TaskTimeWindowManager.shared.getTimeWindow(for: taskInfo.task.id) {
                originalTimeWindows[taskInfo.task.id] = (startTime: timeWindow.startTime, endTime: timeWindow.endTime, isAllDay: timeWindow.isAllDay)
            } else {
                originalTimeWindows[taskInfo.task.id] = nil
            }
            taskListMapping[taskInfo.task.id] = (listId: taskInfo.listId, accountKind: taskInfo.accountKind)
        }

        guard let firstTask = tasksToMove.first else { return }
        let undoData = BulkEditUndoData(
            tasks: tasksToMove.map { $0.task },
            listId: firstTask.listId,
            accountKind: firstTask.accountKind,
            destinationListId: destinationListId,
            destinationAccountKind: destinationAccountKind,
            originalDueDates: nil,
            originalTimeWindows: originalTimeWindows,
            originalPriorities: nil,
            taskListMapping: taskListMapping,
            count: tasksToMove.count
        )

        Task {
            for taskInfo in tasksToMove {
                // Delete from source list (using each task's original list/account)
                await tasksVM.deleteTask(taskInfo.task, from: taskInfo.listId, for: taskInfo.accountKind)

                // Create in destination list
                await tasksVM.createTask(
                    title: taskInfo.task.title,
                    notes: taskInfo.task.notes,
                    dueDate: taskInfo.task.dueDate,
                    in: destinationListId,
                    for: destinationAccountKind
                )
            }

            await MainActor.run {
                state.reset()
                completion(undoData)
            }
        }
    }

    func bulkMove(
        tasks: [GoogleTask],
        from sourceListId: String,
        sourceAccountKind: GoogleAuthManager.AccountKind,
        to destinationListId: String,
        destinationAccountKind: GoogleAuthManager.AccountKind,
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        let tasksWithInfo = tasks.map { (task: $0, listId: sourceListId, accountKind: sourceAccountKind) }
        bulkMove(tasks: tasksWithInfo, to: destinationListId, destinationAccountKind: destinationAccountKind, tasksVM: tasksVM, completion: completion)
    }

    func bulkUpdateDueDate(
        tasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)],
        dueDate: Date?,
        isAllDay: Bool,
        startTime: Date?,
        endTime: Date?,
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        let tasksToUpdate = tasks.filter { state.selectedTaskIds.contains($0.task.id) }

        // Store original due dates and time windows for undo
        var originalDueDates: [String: String?] = [:]
        var originalTimeWindows: [String: (startTime: Date, endTime: Date, isAllDay: Bool)?] = [:]
        var taskListMapping: [String: (listId: String, accountKind: GoogleAuthManager.AccountKind)] = [:]
        for taskInfo in tasksToUpdate {
            originalDueDates[taskInfo.task.id] = taskInfo.task.due
            if let timeWindow = TaskTimeWindowManager.shared.getTimeWindow(for: taskInfo.task.id) {
                originalTimeWindows[taskInfo.task.id] = (startTime: timeWindow.startTime, endTime: timeWindow.endTime, isAllDay: timeWindow.isAllDay)
            } else {
                originalTimeWindows[taskInfo.task.id] = nil
            }
            taskListMapping[taskInfo.task.id] = (listId: taskInfo.listId, accountKind: taskInfo.accountKind)
        }

        guard let firstTask = tasksToUpdate.first else { return }
        let undoData = BulkEditUndoData(
            tasks: tasksToUpdate.map { $0.task },
            listId: firstTask.listId,
            accountKind: firstTask.accountKind,
            destinationListId: nil,
            destinationAccountKind: nil,
            originalDueDates: originalDueDates,
            originalTimeWindows: originalTimeWindows,
            originalPriorities: nil,
            taskListMapping: taskListMapping,
            count: tasksToUpdate.count
        )

        Task {
            // Format the due date string
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

            // Update each task (using each task's own list/account)
            for taskInfo in tasksToUpdate {
                let updatedTask = GoogleTask(
                    id: taskInfo.task.id,
                    title: taskInfo.task.title,
                    notes: taskInfo.task.notes,
                    status: taskInfo.task.status,
                    due: dueDateString,
                    completed: taskInfo.task.completed,
                    updated: taskInfo.task.updated
                )

                await tasksVM.updateTask(updatedTask, in: taskInfo.listId, for: taskInfo.accountKind)

                // Save or delete time window
                if let dueDate = dueDate, !isAllDay, let start = startTime, let end = endTime {
                    // Save time window for timed tasks
                    TaskTimeWindowManager.shared.saveTimeWindow(
                        taskId: taskInfo.task.id,
                        startTime: start,
                        endTime: end,
                        isAllDay: false
                    )
                } else {
                    // Delete time window if all-day or no due date
                    TaskTimeWindowManager.shared.deleteTimeWindow(for: taskInfo.task.id)
                }
            }

            await MainActor.run {
                state.reset()
                completion(undoData)
            }
        }
    }

    func bulkUpdateDueDate(
        tasks: [GoogleTask],
        in listId: String,
        for accountKind: GoogleAuthManager.AccountKind,
        dueDate: Date?,
        isAllDay: Bool,
        startTime: Date?,
        endTime: Date?,
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        let tasksWithInfo = tasks.map { (task: $0, listId: listId, accountKind: accountKind) }
        bulkUpdateDueDate(tasks: tasksWithInfo, dueDate: dueDate, isAllDay: isAllDay, startTime: startTime, endTime: endTime, tasksVM: tasksVM, completion: completion)
    }

    func bulkUpdatePriority(
        tasks: [(task: GoogleTask, listId: String, accountKind: GoogleAuthManager.AccountKind)],
        priority: TaskPriorityData?,
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        let tasksToUpdate = tasks.filter { state.selectedTaskIds.contains($0.task.id) }

        // Store original priorities for undo
        var originalPriorities: [String: TaskPriorityData?] = [:]
        var taskListMapping: [String: (listId: String, accountKind: GoogleAuthManager.AccountKind)] = [:]
        for taskInfo in tasksToUpdate {
            originalPriorities[taskInfo.task.id] = taskInfo.task.priority
            taskListMapping[taskInfo.task.id] = (listId: taskInfo.listId, accountKind: taskInfo.accountKind)
        }

        guard let firstTask = tasksToUpdate.first else { return }
        let undoData = BulkEditUndoData(
            tasks: tasksToUpdate.map { $0.task },
            listId: firstTask.listId,
            accountKind: firstTask.accountKind,
            destinationListId: nil,
            destinationAccountKind: nil,
            originalDueDates: nil,
            originalTimeWindows: nil,
            originalPriorities: originalPriorities,
            taskListMapping: taskListMapping,
            count: tasksToUpdate.count
        )

        Task {
            // Update each task with new priority
            for taskInfo in tasksToUpdate {
                let updatedTask = taskInfo.task.withPriority(priority)
                await tasksVM.updateTask(updatedTask, in: taskInfo.listId, for: taskInfo.accountKind)
            }

            await MainActor.run {
                state.reset()
                completion(undoData)
            }
        }
    }

    func bulkUpdatePriority(
        tasks: [GoogleTask],
        in listId: String,
        for accountKind: GoogleAuthManager.AccountKind,
        priority: TaskPriorityData?,
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        let tasksWithInfo = tasks.map { (task: $0, listId: listId, accountKind: accountKind) }
        bulkUpdatePriority(tasks: tasksWithInfo, priority: priority, tasksVM: tasksVM, completion: completion)
    }

    // MARK: - Undo Operations

    func undoComplete(data: BulkEditUndoData, tasksVM: TasksViewModel) {
        Task {
            // Toggle completion back to incomplete for each task
            for originalTask in data.tasks {
                // Get the list/account for this specific task
                let listId: String
                let accountKind: GoogleAuthManager.AccountKind

                if let mapping = data.taskListMapping?[originalTask.id] {
                    listId = mapping.listId
                    accountKind = mapping.accountKind
                } else {
                    // Fallback to primary list/account for backward compatibility
                    listId = data.listId
                    accountKind = data.accountKind
                }

                // Get the current tasks from the appropriate list
                let currentTasks: [GoogleTask]
                switch accountKind {
                case .personal:
                    currentTasks = tasksVM.personalTasks[listId] ?? []
                case .professional:
                    currentTasks = tasksVM.professionalTasks[listId] ?? []
                }

                // Find the current version of the task (which should be completed)
                if let completedTask = currentTasks.first(where: { $0.id == originalTask.id }) {
                    await tasksVM.toggleTaskCompletion(completedTask, in: listId, for: accountKind)
                }
            }
        }
    }

    func undoDelete(data: BulkEditUndoData, tasksVM: TasksViewModel) {
        Task {
            for task in data.tasks {
                // Get the list/account for this specific task
                let listId: String
                let accountKind: GoogleAuthManager.AccountKind

                if let mapping = data.taskListMapping?[task.id] {
                    listId = mapping.listId
                    accountKind = mapping.accountKind
                } else {
                    // Fallback to primary list/account for backward compatibility
                    listId = data.listId
                    accountKind = data.accountKind
                }

                await tasksVM.createTask(
                    title: task.title,
                    notes: task.notes,
                    dueDate: task.dueDate,
                    in: listId,
                    for: accountKind
                )

                // Restore time window if it existed
                if let originalTimeWindows = data.originalTimeWindows,
                   let timeWindowData = originalTimeWindows[task.id],
                   let timeWindow = timeWindowData {
                    TaskTimeWindowManager.shared.saveTimeWindow(
                        taskId: task.id,
                        startTime: timeWindow.startTime,
                        endTime: timeWindow.endTime,
                        isAllDay: timeWindow.isAllDay
                    )
                }
            }
        }
    }

    func undoMove(data: BulkEditUndoData, tasksVM: TasksViewModel) {
        guard let destinationListId = data.destinationListId,
              let destinationAccountKind = data.destinationAccountKind else {
            return
        }

        Task {
            for task in data.tasks {
                // Get the original list/account for this specific task
                let originalListId: String
                let originalAccountKind: GoogleAuthManager.AccountKind

                if let mapping = data.taskListMapping?[task.id] {
                    originalListId = mapping.listId
                    originalAccountKind = mapping.accountKind
                } else {
                    // Fallback to primary list/account for backward compatibility
                    originalListId = data.listId
                    originalAccountKind = data.accountKind
                }

                // Delete from destination list
                let destinationTasks: [GoogleTask]
                switch destinationAccountKind {
                case .personal:
                    destinationTasks = tasksVM.personalTasks[destinationListId] ?? []
                case .professional:
                    destinationTasks = tasksVM.professionalTasks[destinationListId] ?? []
                }

                if let movedTask = destinationTasks.first(where: { $0.title == task.title }) {
                    await tasksVM.deleteTask(movedTask, from: destinationListId, for: destinationAccountKind)
                }

                // Recreate in original source list
                await tasksVM.createTask(
                    title: task.title,
                    notes: task.notes,
                    dueDate: task.dueDate,
                    in: originalListId,
                    for: originalAccountKind
                )

                // Restore time window if it existed
                if let originalTimeWindows = data.originalTimeWindows,
                   let timeWindowData = originalTimeWindows[task.id],
                   let timeWindow = timeWindowData {
                    TaskTimeWindowManager.shared.saveTimeWindow(
                        taskId: task.id,
                        startTime: timeWindow.startTime,
                        endTime: timeWindow.endTime,
                        isAllDay: timeWindow.isAllDay
                    )
                }
            }
        }
    }

    func undoUpdateDueDate(data: BulkEditUndoData, tasksVM: TasksViewModel) {
        guard let originalDueDates = data.originalDueDates else { return }

        Task {
            for task in data.tasks {
                guard let originalDue = originalDueDates[task.id] else { continue }

                // Get the list/account for this specific task
                let listId: String
                let accountKind: GoogleAuthManager.AccountKind

                if let mapping = data.taskListMapping?[task.id] {
                    listId = mapping.listId
                    accountKind = mapping.accountKind
                } else {
                    // Fallback to primary list/account for backward compatibility
                    listId = data.listId
                    accountKind = data.accountKind
                }

                let restoredTask = GoogleTask(
                    id: task.id,
                    title: task.title,
                    notes: task.notes,
                    status: task.status,
                    due: originalDue,
                    completed: task.completed,
                    updated: task.updated
                )

                await tasksVM.updateTask(restoredTask, in: listId, for: accountKind)

                // Restore time window if it existed, or delete if it didn't
                if let originalTimeWindows = data.originalTimeWindows {
                    // Check if we have stored info about this task's time window
                    if originalTimeWindows.keys.contains(task.id) {
                        // Key exists, check if there was a time window
                        if let timeWindow = originalTimeWindows[task.id], let window = timeWindow {
                            // Restore the original time window
                            TaskTimeWindowManager.shared.saveTimeWindow(
                                taskId: task.id,
                                startTime: window.startTime,
                                endTime: window.endTime,
                                isAllDay: window.isAllDay
                            )
                        } else {
                            // Task had no time window originally, delete any existing one
                            TaskTimeWindowManager.shared.deleteTimeWindow(for: task.id)
                        }
                    }
                }
            }
        }
    }

    func undoUpdatePriority(data: BulkEditUndoData, tasksVM: TasksViewModel) {
        guard let originalPriorities = data.originalPriorities else { return }

        Task {
            for task in data.tasks {
                // Get the list/account for this specific task
                let listId: String
                let accountKind: GoogleAuthManager.AccountKind

                if let mapping = data.taskListMapping?[task.id] {
                    listId = mapping.listId
                    accountKind = mapping.accountKind
                } else {
                    // Fallback to primary list/account for backward compatibility
                    listId = data.listId
                    accountKind = data.accountKind
                }

                // Get current task version from tasksVM
                let currentTasks: [GoogleTask]
                switch accountKind {
                case .personal:
                    currentTasks = tasksVM.personalTasks[listId] ?? []
                case .professional:
                    currentTasks = tasksVM.professionalTasks[listId] ?? []
                }

                // Find current version of the task
                guard let currentTask = currentTasks.first(where: { $0.id == task.id }) else { continue }

                // Restore original priority (which may be nil)
                let originalPriority = originalPriorities[task.id] ?? nil
                let restoredTask = currentTask.withPriority(originalPriority)

                await tasksVM.updateTask(restoredTask, in: listId, for: accountKind)
            }
        }
    }
}
