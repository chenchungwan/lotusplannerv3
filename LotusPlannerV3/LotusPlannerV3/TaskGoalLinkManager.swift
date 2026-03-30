import Foundation
import CoreData

/// Manager for task-to-goal links stored in Core Data with CloudKit sync.
/// Provides reverse lookup: given a task ID, find all linked goal IDs.
@MainActor
class TaskGoalLinkManager: ObservableObject {
    static let shared = TaskGoalLinkManager()

    /// In-memory cache: taskId -> [goalId]
    @Published private(set) var linksByTask: [String: [UUID]] = [:]

    private let context = PersistenceController.shared.container.viewContext

    private init() {
        loadLinks()
        setupiCloudSync()
    }

    // MARK: - Load

    func loadLinks() {
        let request: NSFetchRequest<TaskGoalLink> = TaskGoalLink.fetchRequest()
        do {
            let entities = try context.fetch(request)
            var map: [String: [UUID]] = [:]
            for entity in entities {
                guard let taskId = entity.taskId,
                      let goalIdStr = entity.goalId,
                      let goalId = UUID(uuidString: goalIdStr) else { continue }
                map[taskId, default: []].append(goalId)
            }
            linksByTask = map
        } catch {
            devLog("TaskGoalLinkManager: Failed to load links: \(error)", level: .error, category: .goals)
        }
    }

    // MARK: - Query

    func goalIds(for taskId: String) -> [UUID] {
        linksByTask[taskId] ?? []
    }

    func isLinked(taskId: String, goalId: UUID) -> Bool {
        linksByTask[taskId]?.contains(goalId) ?? false
    }

    // MARK: - Link / Unlink

    func link(taskId: String, goalId: UUID) {
        guard !isLinked(taskId: taskId, goalId: goalId) else { return }

        let entity = TaskGoalLink(context: context)
        entity.id = UUID().uuidString
        entity.taskId = taskId
        entity.goalId = goalId.uuidString
        entity.userId = "icloud-user"
        entity.createdAt = Date()
        saveContext()

        linksByTask[taskId, default: []].append(goalId)
    }

    func unlink(taskId: String, goalId: UUID) {
        let request: NSFetchRequest<TaskGoalLink> = TaskGoalLink.fetchRequest()
        request.predicate = NSPredicate(format: "taskId == %@ AND goalId == %@", taskId, goalId.uuidString)
        do {
            let entities = try context.fetch(request)
            entities.forEach(context.delete)
            saveContext()

            linksByTask[taskId]?.removeAll { $0 == goalId }
            if linksByTask[taskId]?.isEmpty == true {
                linksByTask.removeValue(forKey: taskId)
            }
        } catch {
            devLog("TaskGoalLinkManager: Failed to unlink: \(error)", level: .error, category: .goals)
        }
    }

    func unlinkAllForTask(_ taskId: String) {
        let request: NSFetchRequest<TaskGoalLink> = TaskGoalLink.fetchRequest()
        request.predicate = NSPredicate(format: "taskId == %@", taskId)
        do {
            let entities = try context.fetch(request)
            entities.forEach(context.delete)
            saveContext()
            linksByTask.removeValue(forKey: taskId)
        } catch {
            devLog("TaskGoalLinkManager: Failed to unlink all for task: \(error)", level: .error, category: .goals)
        }
    }

    func unlinkAllForGoal(_ goalId: UUID) {
        let request: NSFetchRequest<TaskGoalLink> = TaskGoalLink.fetchRequest()
        request.predicate = NSPredicate(format: "goalId == %@", goalId.uuidString)
        do {
            let entities = try context.fetch(request)
            entities.forEach(context.delete)
            saveContext()

            // Remove from cache
            for taskId in linksByTask.keys {
                linksByTask[taskId]?.removeAll { $0 == goalId }
                if linksByTask[taskId]?.isEmpty == true {
                    linksByTask.removeValue(forKey: taskId)
                }
            }
        } catch {
            devLog("TaskGoalLinkManager: Failed to unlink all for goal: \(error)", level: .error, category: .goals)
        }
    }

    /// Syncs links from GoalData.linkedTasks to Core Data.
    /// Call after a goal is saved/updated to ensure the link table stays in sync.
    func syncLinksFromGoal(_ goal: GoalData) {
        let goalId = goal.id
        let currentTaskIds = Set(goal.linkedTasks.map { $0.taskId })

        // Get existing links for this goal
        let existingTaskIds = Set(linksByTask.filter { $0.value.contains(goalId) }.keys)

        // Add new links
        for taskId in currentTaskIds where !existingTaskIds.contains(taskId) {
            link(taskId: taskId, goalId: goalId)
        }

        // Remove stale links
        for taskId in existingTaskIds where !currentTaskIds.contains(taskId) {
            unlink(taskId: taskId, goalId: goalId)
        }
    }

    // MARK: - Private

    private func saveContext() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            devLog("TaskGoalLinkManager: Failed to save: \(error)", level: .error, category: .goals)
        }
    }

    private func setupiCloudSync() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadLinks()
            }
        }
    }
}
