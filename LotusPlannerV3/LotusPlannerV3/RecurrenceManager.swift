//
//  RecurrenceManager.swift
//  LotusPlannerV3
//
//  App-side recurrence layer for Google Tasks. The Google Tasks API does not
//  expose recurrence metadata, so this file owns the rules entirely on the
//  app side: each rule is keyed by the *current* Google Task ID of the
//  active instance in the series. When that instance is completed, the
//  manager creates the next instance via `TasksViewModel`, then re-keys the
//  rule under the new task's id.
//
//  Storage uses the same JSON-in-UserDefaults + iCloud KVS pattern as
//  `CustomDayViewLibrary` so rules sync between devices without any new
//  Core Data entity.
//

import Foundation
import SwiftUI

// MARK: - Frequency

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    /// Singular unit for an "Every N <unit>" stepper label.
    var unitName: String {
        switch self {
        case .daily: return "day"
        case .weekly: return "week"
        case .monthly: return "month"
        case .yearly: return "year"
        }
    }
}

// MARK: - Rule

struct RecurrenceRule: Codable, Equatable {
    /// Stable id for the entire repeating series. Survives across instances
    /// even though `currentTaskId` is rewritten on each spawn.
    let seriesId: UUID
    /// Google Task id of the most recently created instance. The
    /// `RecurrenceLibrary` is keyed by this so lookups by task id are O(1).
    var currentTaskId: String
    /// "personal" or "professional" — matches `GoogleAuthManager.AccountKind.rawValue`.
    var accountKind: String
    var listId: String
    var frequency: RecurrenceFrequency
    /// Every N <frequency.unitName>s. Always >= 1.
    var interval: Int
    /// If non-nil, the series ends on or before this date.
    var endDate: Date?
    /// If non-nil, the series spawns at most this many instances total.
    var endCount: Int?
    /// How many instances have been spawned so far (not counting the original).
    var occurrencesSpawned: Int
    /// Wall-clock time the most recent successor was spawned. Used to
    /// short-circuit double-spawn when both completion-handler and
    /// catch-up-sweep fire for the same completion.
    var lastSpawnedDate: Date?
    var createdAt: Date
    var updatedAt: Date

    var accountKindEnum: GoogleAuthManager.AccountKind {
        accountKind == "professional" ? .professional : .personal
    }
}

// MARK: - Library (JSON store)

/// Dictionary of recurrence rules keyed by current Google Task id. Persisted
/// as JSON in UserDefaults (local cache) and NSUbiquitousKeyValueStore
/// (cross-device iCloud sync) — same pattern as `CustomDayViewLibrary`.
struct RecurrenceLibrary: Codable {
    static let userDefaultsKey = "taskRecurrenceLibrary.v1"
    static let didChangeNotification = Notification.Name("TaskRecurrenceLibraryDidChange")

    var rules: [String: RecurrenceRule]

    static func empty() -> RecurrenceLibrary {
        RecurrenceLibrary(rules: [:])
    }

    static func load() -> RecurrenceLibrary {
        let kvs = NSUbiquitousKeyValueStore.default
        if let data = kvs.data(forKey: userDefaultsKey),
           let lib = try? JSONDecoder().decode(RecurrenceLibrary.self, from: data) {
            return lib
        }
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let lib = try? JSONDecoder().decode(RecurrenceLibrary.self, from: data) {
            return lib
        }
        return .empty()
    }

    static func save(_ library: RecurrenceLibrary) {
        guard let data = try? JSONEncoder().encode(library) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
        NSUbiquitousKeyValueStore.default.set(data, forKey: userDefaultsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Mirrors remote KVS changes to the local cache. Call once at launch.
    @MainActor
    static func startSync() {
        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()

        if kvs.data(forKey: userDefaultsKey) == nil,
           let localData = UserDefaults.standard.data(forKey: userDefaultsKey) {
            kvs.set(localData, forKey: userDefaultsKey)
            kvs.synchronize()
        }

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { notification in
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard changedKeys.isEmpty || changedKeys.contains(userDefaultsKey) else { return }
            if let data = kvs.data(forKey: userDefaultsKey) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}

// MARK: - Manager

@MainActor
final class RecurrenceManager: ObservableObject {
    static let shared = RecurrenceManager()

    @Published private(set) var library: RecurrenceLibrary = .empty()

    private init() {
        library = RecurrenceLibrary.load()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryChangedExternally),
            name: RecurrenceLibrary.didChangeNotification,
            object: nil
        )
    }

    @objc private func libraryChangedExternally() {
        library = RecurrenceLibrary.load()
    }

    // MARK: CRUD

    func rule(for taskId: String) -> RecurrenceRule? {
        library.rules[taskId]
    }

    func hasRule(for taskId: String) -> Bool {
        library.rules[taskId] != nil
    }

    /// Upsert a rule for the given task id. Caller is responsible for
    /// constructing a `RecurrenceRule` with the correct `currentTaskId`,
    /// `listId`, and `accountKind`.
    func setRule(_ rule: RecurrenceRule) {
        var lib = library
        var updated = rule
        updated.updatedAt = Date()
        lib.rules[rule.currentTaskId] = updated
        library = lib
        RecurrenceLibrary.save(lib)
    }

    func deleteRule(for taskId: String) {
        guard library.rules[taskId] != nil else { return }
        var lib = library
        lib.rules.removeValue(forKey: taskId)
        library = lib
        RecurrenceLibrary.save(lib)
    }

    // MARK: Spawning

    /// Called from `TasksViewModel.toggleTaskCompletion` when a task
    /// transitions to the completed state. If the task has a recurrence
    /// rule, this creates the next instance on Google Tasks and re-keys the
    /// rule under the new task id.
    func handleTaskCompleted(
        _ task: GoogleTask,
        listId: String,
        account: GoogleAuthManager.AccountKind,
        tasksVM: TasksViewModel
    ) async {
        guard let rule = rule(for: task.id) else { return }

        // Anti-double-spawn: if we've already spawned for this completion
        // (e.g. completion handler ran, then a catch-up sweep saw the same
        // completed task), skip.
        if let lastSpawn = rule.lastSpawnedDate,
           let completed = task.completionDate,
           lastSpawn >= completed {
            return
        }

        let occurrencesAfterSpawn = rule.occurrencesSpawned + 1
        if let maxOccurrences = rule.endCount, occurrencesAfterSpawn > maxOccurrences {
            deleteRule(for: task.id)
            return
        }

        let baseDate = task.dueDate ?? Date()
        guard let nextDate = nextDueDate(after: baseDate, rule: rule) else {
            deleteRule(for: task.id)
            return
        }

        if let endDate = rule.endDate, Calendar.current.startOfDay(for: nextDate) > Calendar.current.startOfDay(for: endDate) {
            deleteRule(for: task.id)
            return
        }

        do {
            let newTask = try await tasksVM.spawnRecurringInstance(
                title: task.title,
                notes: task.userNotes,
                dueDate: nextDate,
                in: rule.listId,
                for: account
            )

            // Re-key the rule under the new task id; carry forward the
            // series id, frequency, interval, end conditions.
            var updated = rule
            updated.currentTaskId = newTask.id
            updated.lastSpawnedDate = Date()
            updated.occurrencesSpawned = occurrencesAfterSpawn
            updated.updatedAt = Date()

            var lib = library
            lib.rules.removeValue(forKey: task.id)
            lib.rules[newTask.id] = updated
            library = lib
            RecurrenceLibrary.save(lib)
        } catch {
            // Network failure — leave the rule in place. The next completion
            // toggle or app-launch catch-up sweep will retry.
        }
    }

    /// Called once after `tasksVM` has loaded its tasks. Walks every rule and
    /// spawns successors for any whose current instance is already marked
    /// completed (e.g. user completed it directly in tasks.google.com while
    /// the app was offline).
    func catchUpMissedInstances(tasksVM: TasksViewModel) async {
        let snapshot = library.rules
        let allTasks: [(GoogleTask, String, GoogleAuthManager.AccountKind)] =
            tasksVM.personalTasks.flatMap { listId, tasks in tasks.map { ($0, listId, GoogleAuthManager.AccountKind.personal) } }
            + tasksVM.professionalTasks.flatMap { listId, tasks in tasks.map { ($0, listId, GoogleAuthManager.AccountKind.professional) } }

        for (taskId, _) in snapshot {
            guard let entry = allTasks.first(where: { $0.0.id == taskId }) else { continue }
            let (task, listId, account) = entry
            if task.isCompleted {
                await handleTaskCompleted(task, listId: listId, account: account, tasksVM: tasksVM)
            }
        }
    }

    // MARK: Date math

    private func nextDueDate(after base: Date, rule: RecurrenceRule) -> Date? {
        let calendar = Calendar.current
        let interval = max(1, rule.interval)
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: base)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: interval, to: base)
        case .monthly:
            return calendar.date(byAdding: .month, value: interval, to: base)
        case .yearly:
            return calendar.date(byAdding: .year, value: interval, to: base)
        }
    }
}
