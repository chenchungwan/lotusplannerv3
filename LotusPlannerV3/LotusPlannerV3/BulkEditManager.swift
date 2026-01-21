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

    func bulkComplete(
        tasks: [GoogleTask],
        in listId: String,
        for accountKind: GoogleAuthManager.AccountKind,
        tasksVM: TasksViewModel,
        completion: @escaping (BulkEditUndoData) -> Void
    ) {
        let tasksToComplete = tasks.filter { state.selectedTaskIds.contains($0.id) && !$0.isCompleted }

        // Store pre-action state for undo
        let undoData = BulkEditUndoData(
            tasks: tasksToComplete,
            listId: listId,
            accountKind: accountKind,
            destinationListId: nil,
            destinationAccountKind: nil,
            originalDueDates: nil,
            originalTimeWindows: nil,
            count: tasksToComplete.count
        )

        Task {
            for task in tasksToComplete {
                await tasksVM.toggleTaskCompletion(task, in: listId, for: accountKind)
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
        let tasksToDelete = tasks.filter { state.selectedTaskIds.contains($0.id) }

        // Store pre-action state for undo (including time windows)
        var originalTimeWindows: [String: (startTime: Date, endTime: Date, isAllDay: Bool)?] = [:]
        for task in tasksToDelete {
            if let timeWindow = TaskTimeWindowManager.shared.getTimeWindow(for: task.id) {
                originalTimeWindows[task.id] = (startTime: timeWindow.startTime, endTime: timeWindow.endTime, isAllDay: timeWindow.isAllDay)
            } else {
                originalTimeWindows[task.id] = nil
            }
        }

        let undoData = BulkEditUndoData(
            tasks: tasksToDelete,
            listId: listId,
            accountKind: accountKind,
            destinationListId: nil,
            destinationAccountKind: nil,
            originalDueDates: nil,
            originalTimeWindows: originalTimeWindows,
            count: tasksToDelete.count
        )

        Task {
            for task in tasksToDelete {
                await tasksVM.deleteTask(task, from: listId, for: accountKind)
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
        let tasksToMove = tasks.filter { state.selectedTaskIds.contains($0.id) }

        // Store pre-action state for undo (including time windows)
        var originalTimeWindows: [String: (startTime: Date, endTime: Date, isAllDay: Bool)?] = [:]
        for task in tasksToMove {
            if let timeWindow = TaskTimeWindowManager.shared.getTimeWindow(for: task.id) {
                originalTimeWindows[task.id] = (startTime: timeWindow.startTime, endTime: timeWindow.endTime, isAllDay: timeWindow.isAllDay)
            } else {
                originalTimeWindows[task.id] = nil
            }
        }

        let undoData = BulkEditUndoData(
            tasks: tasksToMove,
            listId: sourceListId,
            accountKind: sourceAccountKind,
            destinationListId: destinationListId,
            destinationAccountKind: destinationAccountKind,
            originalDueDates: nil,
            originalTimeWindows: originalTimeWindows,
            count: tasksToMove.count
        )

        Task {
            for task in tasksToMove {
                // Delete from source list
                await tasksVM.deleteTask(task, from: sourceListId, for: sourceAccountKind)

                // Create in destination list
                await tasksVM.createTask(
                    title: task.title,
                    notes: task.notes,
                    dueDate: task.dueDate,
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
        let tasksToUpdate = tasks.filter { state.selectedTaskIds.contains($0.id) }

        // Store original due dates and time windows for undo
        var originalDueDates: [String: String?] = [:]
        var originalTimeWindows: [String: (startTime: Date, endTime: Date, isAllDay: Bool)?] = [:]
        for task in tasksToUpdate {
            originalDueDates[task.id] = task.due
            if let timeWindow = TaskTimeWindowManager.shared.getTimeWindow(for: task.id) {
                originalTimeWindows[task.id] = (startTime: timeWindow.startTime, endTime: timeWindow.endTime, isAllDay: timeWindow.isAllDay)
            } else {
                originalTimeWindows[task.id] = nil
            }
        }

        let undoData = BulkEditUndoData(
            tasks: tasksToUpdate,
            listId: listId,
            accountKind: accountKind,
            destinationListId: nil,
            destinationAccountKind: nil,
            originalDueDates: originalDueDates,
            originalTimeWindows: originalTimeWindows,
            count: tasksToUpdate.count
        )

        Task {
            // Format the due date string
            let dueDateString: String?
            if let dueDate = dueDate {
                let formatter = DateFormatter()
                if isAllDay {
                    formatter.dateFormat = "yyyy-MM-dd"
                } else {
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                    formatter.timeZone = TimeZone(identifier: "UTC")
                }
                formatter.locale = Locale(identifier: "en_US_POSIX")
                dueDateString = formatter.string(from: dueDate)
            } else {
                dueDateString = nil
            }

            // Update each task
            for task in tasksToUpdate {
                let updatedTask = GoogleTask(
                    id: task.id,
                    title: task.title,
                    notes: task.notes,
                    status: task.status,
                    due: dueDateString,
                    completed: task.completed,
                    updated: task.updated
                )

                await tasksVM.updateTask(updatedTask, in: listId, for: accountKind)

                // Save or delete time window
                if let dueDate = dueDate, !isAllDay, let start = startTime, let end = endTime {
                    TaskTimeWindowManager.shared.saveTimeWindow(
                        taskId: task.id,
                        startTime: start,
                        endTime: end,
                        isAllDay: false
                    )
                } else if isAllDay {
                    TaskTimeWindowManager.shared.deleteTimeWindow(for: task.id)
                }
            }

            await MainActor.run {
                state.reset()
                completion(undoData)
            }
        }
    }

    // MARK: - Undo Operations

    func undoComplete(data: BulkEditUndoData, tasksVM: TasksViewModel) {
        Task {
            // Get the current tasks from the list to find the completed versions
            let currentTasks: [GoogleTask]
            switch data.accountKind {
            case .personal:
                currentTasks = tasksVM.personalTasks[data.listId] ?? []
            case .professional:
                currentTasks = tasksVM.professionalTasks[data.listId] ?? []
            }

            // Toggle completion back to incomplete for each task
            for originalTask in data.tasks {
                // Find the current version of the task (which should be completed)
                if let completedTask = currentTasks.first(where: { $0.id == originalTask.id }) {
                    await tasksVM.toggleTaskCompletion(completedTask, in: data.listId, for: data.accountKind)
                }
            }
        }
    }

    func undoDelete(data: BulkEditUndoData, tasksVM: TasksViewModel) {
        Task {
            for task in data.tasks {
                await tasksVM.createTask(
                    title: task.title,
                    notes: task.notes,
                    dueDate: task.dueDate,
                    in: data.listId,
                    for: data.accountKind
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

                // Recreate in source list
                await tasksVM.createTask(
                    title: task.title,
                    notes: task.notes,
                    dueDate: task.dueDate,
                    in: data.listId,
                    for: data.accountKind
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

                let restoredTask = GoogleTask(
                    id: task.id,
                    title: task.title,
                    notes: task.notes,
                    status: task.status,
                    due: originalDue,
                    completed: task.completed,
                    updated: task.updated
                )

                await tasksVM.updateTask(restoredTask, in: data.listId, for: data.accountKind)

                // Restore time window if it existed
                if let originalTimeWindows = data.originalTimeWindows,
                   let timeWindowData = originalTimeWindows[task.id] {
                    if let timeWindow = timeWindowData {
                        TaskTimeWindowManager.shared.saveTimeWindow(
                            taskId: task.id,
                            startTime: timeWindow.startTime,
                            endTime: timeWindow.endTime,
                            isAllDay: timeWindow.isAllDay
                        )
                    } else {
                        TaskTimeWindowManager.shared.deleteTimeWindow(for: task.id)
                    }
                }
            }
        }
    }
}
