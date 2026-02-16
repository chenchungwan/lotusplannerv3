import Foundation
import CoreData
import SwiftUI

class CoreDataManager: ObservableObject {
    static let shared = CoreDataManager()
    
    private let persistenceController = PersistenceController.shared
    
    private var context: NSManagedObjectContext {
        persistenceController.container.viewContext
    }
    
    private init() {
        // Migrate any existing categories to have display order
        migrateExistingCategories()
        // One-time migration from legacy UserDefaults / iCloud KVS to Core Data
        migrateLegacyStorageIfNeeded()
        // Migrate userId field to use "icloud-user" for all logs
        migrateLogUserIds()
    }
    
    private func migrateExistingCategories() {
        // Migration will be handled when Core Data model is updated
    }
    
    // MARK: - Save Context
    private func save() {
        if context.hasChanges {
            do {
                try context.save()

                // Force the parent context (if any) to save as well
                if let parentContext = context.parent {
                    try parentContext.save()
                }
            } catch {
                devLog("❌ CoreDataManager: Failed to save context: \(error.localizedDescription)", level: .error, category: .sync)
            }
        }
    }
    
    // MARK: - Weight Logs
    func saveWeightEntry(_ entry: WeightLogEntry) {
        let weightLog = WeightLog(context: context)
        weightLog.id = entry.id
        weightLog.date = entry.date
        weightLog.time = entry.time
        weightLog.timestamp = entry.timestamp // Keep for backward compatibility
        weightLog.weight = entry.weight
        weightLog.unit = entry.unit.rawValue
        weightLog.userId = entry.userId
        
        save()
    }
    
    func loadWeightEntries() -> [WeightLogEntry] {
        let request: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WeightLog.timestamp, ascending: false)]
        
        do {
            let logs = try context.fetch(request)
            return logs.compactMap { log in
                guard let id = log.id,
                      let unitString = log.unit,
                      let unit = WeightUnit(rawValue: unitString),
                      let userId = log.userId else { return nil }
                
                // Use new date/time fields if available, otherwise fall back to timestamp
                let date = log.date ?? log.timestamp ?? Date()
                let time = log.time ?? log.timestamp ?? Date()
                
                return WeightLogEntry(
                    id: id,
                    date: date,
                    time: time,
                    weight: log.weight,
                    unit: unit,
                    userId: userId
                )
            }
        } catch {
            return []
        }
    }
    
    func deleteWeightEntry(_ entry: WeightLogEntry) {
        let request: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)
        
        do {
            let logs = try context.fetch(request)
            logs.forEach(context.delete)
            save()
        } catch {
        }
    }
    
    // MARK: - Workout Logs
    func saveWorkoutEntry(_ entry: WorkoutLogEntry) {
        let workoutLog = WorkoutLog(context: context)
        workoutLog.id = entry.id
        workoutLog.date = entry.date
        workoutLog.name = entry.name
        workoutLog.workoutType = entry.workoutTypeRaw
        workoutLog.userId = entry.userId
        workoutLog.createdAt = entry.createdAt

        save()
    }

    func loadWorkoutEntries() -> [WorkoutLogEntry] {
        let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutLog.createdAt, ascending: false)]

        do {
            let logs = try context.fetch(request)

            // Deduplicate: group by id, keep the version with workoutType set (or most recent)
            var seenIds: [String: WorkoutLog] = [:]
            var duplicatesToDelete: [WorkoutLog] = []

            for log in logs {
                guard let id = log.id else { continue }
                if let existing = seenIds[id] {
                    // Decide which to keep: prefer the one with workoutType populated
                    let existingHasType = existing.workoutType != nil && !(existing.workoutType ?? "").isEmpty
                    let newHasType = log.workoutType != nil && !(log.workoutType ?? "").isEmpty

                    if newHasType && !existingHasType {
                        // New one is better — delete the existing, keep new
                        duplicatesToDelete.append(existing)
                        seenIds[id] = log
                    } else {
                        // Keep existing — delete the new duplicate
                        duplicatesToDelete.append(log)
                    }
                } else {
                    seenIds[id] = log
                }
            }

            // Delete duplicates from Core Data
            if !duplicatesToDelete.isEmpty {
                devLog("🧹 CoreDataManager: Removing \(duplicatesToDelete.count) duplicate workout entries", level: .info, category: .sync)
                for dup in duplicatesToDelete {
                    context.delete(dup)
                }
                save()
            }

            // Build result from deduplicated set
            return seenIds.values.compactMap { log in
                guard let id = log.id,
                      let date = log.date,
                      let userId = log.userId,
                      let createdAt = log.createdAt else { return nil }

                return WorkoutLogEntry(
                    id: id,
                    date: date,
                    name: log.name ?? "",
                    workoutTypeRaw: log.workoutType,
                    userId: userId,
                    createdAt: createdAt
                )
            }.sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }
    
    func updateWorkoutEntry(_ entry: WorkoutLogEntry) {
        let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)

        do {
            let logs = try context.fetch(request)
            if let existing = logs.first {
                existing.date = entry.date
                existing.name = entry.name
                existing.workoutType = entry.workoutTypeRaw
                save()
            } else {
                // Record not found — create it
                saveWorkoutEntry(entry)
            }
        } catch {
            devLog("❌ CoreDataManager: Failed to update workout entry: \(error.localizedDescription)", level: .error, category: .sync)
        }
    }

    func deleteWorkoutEntry(_ entry: WorkoutLogEntry) {
        let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)

        do {
            let logs = try context.fetch(request)
            logs.forEach(context.delete)
            save()
        } catch {
        }
    }

    // MARK: - Food Logs
    func saveFoodEntry(_ entry: FoodLogEntry) {
        let foodLog = FoodLog(context: context)
        foodLog.id = entry.id
        foodLog.date = entry.date
        foodLog.name = entry.name
        foodLog.userId = entry.userId
        foodLog.createdAt = entry.createdAt
        
        save()
    }
    
    func loadFoodEntries() -> [FoodLogEntry] {
        let request: NSFetchRequest<FoodLog> = FoodLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FoodLog.createdAt, ascending: false)]
        
        do {
            let logs = try context.fetch(request)
            return logs.compactMap { log in
                guard let id = log.id,
                      let date = log.date,
                      let name = log.name,
                      let userId = log.userId,
                      let createdAt = log.createdAt else { return nil }
                
                return FoodLogEntry(
                    id: id,
                    date: date,
                    name: name,
                    userId: userId,
                    createdAt: createdAt
                )
            }
        } catch {
            return []
        }
    }
    
    func deleteFoodEntry(_ entry: FoodLogEntry) {
        let request: NSFetchRequest<FoodLog> = FoodLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)

        do {
            let logs = try context.fetch(request)
            logs.forEach(context.delete)
            save()
        } catch {
        }
    }

    // MARK: - Water Logs
    func saveWaterEntry(_ entry: WaterLogEntry) {
        let waterLog = WaterLog(context: context)
        waterLog.id = entry.id
        waterLog.date = entry.date
        waterLog.cupsConsumed = Int16(entry.cupsConsumed)
        waterLog.userId = entry.userId
        waterLog.createdAt = entry.createdAt
        waterLog.updatedAt = entry.updatedAt

        save()
    }

    func loadWaterEntries() -> [WaterLogEntry] {
        let request: NSFetchRequest<WaterLog> = WaterLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WaterLog.date, ascending: false)]

        do {
            let logs = try context.fetch(request)
            return logs.compactMap { log in
                guard let id = log.id,
                      let date = log.date,
                      let userId = log.userId,
                      let createdAt = log.createdAt,
                      let updatedAt = log.updatedAt else { return nil }

                return WaterLogEntry(
                    id: id,
                    date: date,
                    cupsConsumed: Int(log.cupsConsumed),
                    userId: userId,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            }
        } catch {
            return []
        }
    }

    func updateWaterEntry(_ entry: WaterLogEntry) {
        let request: NSFetchRequest<WaterLog> = WaterLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)

        do {
            let logs = try context.fetch(request)
            if let log = logs.first {
                log.date = entry.date
                log.cupsConsumed = Int16(entry.cupsConsumed)
                log.updatedAt = Date()
                save()
            }
        } catch {
        }
    }

    func deleteWaterEntry(_ entry: WaterLogEntry) {
        let request: NSFetchRequest<WaterLog> = WaterLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)

        do {
            let logs = try context.fetch(request)
            logs.forEach(context.delete)
            save()
        } catch {
        }
    }

    // MARK: - Sleep Logs
    func saveSleepEntry(_ entry: SleepLogEntry) {
        let sleepLog = SleepLog(context: context)
        sleepLog.id = entry.id
        sleepLog.date = entry.date
        sleepLog.wakeUpTime = entry.wakeUpTime
        sleepLog.bedTime = entry.bedTime
        sleepLog.userId = entry.userId
        sleepLog.createdAt = entry.createdAt
        sleepLog.updatedAt = entry.updatedAt

        save()
    }

    func loadSleepEntries() -> [SleepLogEntry] {
        let request: NSFetchRequest<SleepLog> = SleepLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SleepLog.date, ascending: false)]

        do {
            let logs = try context.fetch(request)
            return logs.compactMap { log in
                guard let id = log.id,
                      let date = log.date,
                      let userId = log.userId,
                      let createdAt = log.createdAt,
                      let updatedAt = log.updatedAt else { return nil }

                return SleepLogEntry(
                    id: id,
                    date: date,
                    wakeUpTime: log.wakeUpTime,
                    bedTime: log.bedTime,
                    userId: userId,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            }
        } catch {
            return []
        }
    }

    func updateSleepEntry(_ entry: SleepLogEntry) {
        let request: NSFetchRequest<SleepLog> = SleepLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)

        do {
            let logs = try context.fetch(request)
            if let log = logs.first {
                log.date = entry.date
                log.wakeUpTime = entry.wakeUpTime
                log.bedTime = entry.bedTime
                log.updatedAt = Date()
                save()
            }
        } catch {
        }
    }

    func deleteSleepEntry(_ entry: SleepLogEntry) {
        let request: NSFetchRequest<SleepLog> = SleepLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entry.id)

        do {
            let logs = try context.fetch(request)
            logs.forEach(context.delete)
            save()
        } catch {
        }
    }

    // MARK: - Danger Zone: Delete All Logs
    func deleteAllLogs() {
        let deleteRequests: [NSFetchRequest<NSFetchRequestResult>] = [
            WeightLog.fetchRequest(),
            WorkoutLog.fetchRequest(),
            FoodLog.fetchRequest(),
            WaterLog.fetchRequest(),
            SleepLog.fetchRequest(),
        ]
        do {
            for request in deleteRequests {
                let batchDelete = NSBatchDeleteRequest(fetchRequest: request)
                try context.execute(batchDelete)
            }
            save()
        } catch {
        }
    }
    
    // MARK: - Legacy Migration (UserDefaults / iCloud KVS -> Core Data)
    private let legacyMigrationFlagKey = "coreDataLegacyMigrationDone"
    private func migrateLegacyStorageIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: legacyMigrationFlagKey) == false else { return }
        
        // Attempt to load legacy arrays from UserDefaults first
        let decoder = JSONDecoder()
        if let weightData = defaults.data(forKey: "weightEntries"),
           let legacyWeights = try? decoder.decode([WeightLogEntry].self, from: weightData) {
            for entry in legacyWeights { saveWeightEntry(entry) }
        }
        if let workoutData = defaults.data(forKey: "workoutEntries"),
           let legacyWorkouts = try? decoder.decode([WorkoutLogEntry].self, from: workoutData) {
            for entry in legacyWorkouts { saveWorkoutEntry(entry) }
        }
        if let foodData = defaults.data(forKey: "foodEntries"),
           let legacyFoods = try? decoder.decode([FoodLogEntry].self, from: foodData) {
            for entry in legacyFoods { saveFoodEntry(entry) }
        }
        
        // Also try iCloud KVS if present
        let kvs = NSUbiquitousKeyValueStore.default
        if let weightData = kvs.data(forKey: "weightEntries"),
           let legacyWeights = try? decoder.decode([WeightLogEntry].self, from: weightData) {
            for entry in legacyWeights { saveWeightEntry(entry) }
        }
        if let workoutData = kvs.data(forKey: "workoutEntries"),
           let legacyWorkouts = try? decoder.decode([WorkoutLogEntry].self, from: workoutData) {
            for entry in legacyWorkouts { saveWorkoutEntry(entry) }
        }
        if let foodData = kvs.data(forKey: "foodEntries"),
           let legacyFoods = try? decoder.decode([FoodLogEntry].self, from: foodData) {
            for entry in legacyFoods { saveFoodEntry(entry) }
        }
        
        defaults.set(true, forKey: legacyMigrationFlagKey)
    }

    // MARK: - UserId Migration (email -> "icloud-user")
    private let userIdMigrationFlagKey = "coreDataUserIdMigrationDone"
    private func migrateLogUserIds() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: userIdMigrationFlagKey) == false else { return }

        devLog("🔄 CoreDataManager: Starting userId migration to 'icloud-user'...")

        var totalMigrated = 0

        // Migrate WeightLog entries
        let weightRequest: NSFetchRequest<WeightLog> = WeightLog.fetchRequest()
        weightRequest.predicate = NSPredicate(format: "userId != %@", "icloud-user")
        if let weightLogs = try? context.fetch(weightRequest) {
            for log in weightLogs {
                log.userId = "icloud-user"
                totalMigrated += 1
            }
            devLog("  ✅ Migrated \(weightLogs.count) WeightLog entries")
        }

        // Migrate WorkoutLog entries
        let workoutRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        workoutRequest.predicate = NSPredicate(format: "userId != %@", "icloud-user")
        if let workoutLogs = try? context.fetch(workoutRequest) {
            for log in workoutLogs {
                log.userId = "icloud-user"
                totalMigrated += 1
            }
            devLog("  ✅ Migrated \(workoutLogs.count) WorkoutLog entries")
        }

        // Migrate FoodLog entries
        let foodRequest: NSFetchRequest<FoodLog> = FoodLog.fetchRequest()
        foodRequest.predicate = NSPredicate(format: "userId != %@", "icloud-user")
        if let foodLogs = try? context.fetch(foodRequest) {
            for log in foodLogs {
                log.userId = "icloud-user"
                totalMigrated += 1
            }
            devLog("  ✅ Migrated \(foodLogs.count) FoodLog entries")
        }

        // Migrate WaterLog entries
        let waterRequest: NSFetchRequest<WaterLog> = WaterLog.fetchRequest()
        waterRequest.predicate = NSPredicate(format: "userId != %@", "icloud-user")
        if let waterLogs = try? context.fetch(waterRequest) {
            for log in waterLogs {
                log.userId = "icloud-user"
                totalMigrated += 1
            }
            devLog("  ✅ Migrated \(waterLogs.count) WaterLog entries")
        }

        // Migrate SleepLog entries
        let sleepRequest: NSFetchRequest<SleepLog> = SleepLog.fetchRequest()
        sleepRequest.predicate = NSPredicate(format: "userId != %@", "icloud-user")
        if let sleepLogs = try? context.fetch(sleepRequest) {
            for log in sleepLogs {
                log.userId = "icloud-user"
                totalMigrated += 1
            }
            devLog("  ✅ Migrated \(sleepLogs.count) SleepLog entries")
        }

        // Migrate CustomLogItem entries
        let customItemRequest: NSFetchRequest<CustomLogItem> = CustomLogItem.fetchRequest()
        customItemRequest.predicate = NSPredicate(format: "userId != %@", "icloud-user")
        if let customItems = try? context.fetch(customItemRequest) {
            for item in customItems {
                item.userId = "icloud-user"
                totalMigrated += 1
            }
            devLog("  ✅ Migrated \(customItems.count) CustomLogItem entries")
        }

        // Migrate CustomLogEntry entries
        let customEntryRequest: NSFetchRequest<CustomLogEntry> = CustomLogEntry.fetchRequest()
        customEntryRequest.predicate = NSPredicate(format: "userId != %@", "icloud-user")
        if let customEntries = try? context.fetch(customEntryRequest) {
            for entry in customEntries {
                entry.userId = "icloud-user"
                totalMigrated += 1
            }
            devLog("  ✅ Migrated \(customEntries.count) CustomLogEntry entries")
        }

        // Save changes
        if context.hasChanges {
            do {
                try context.save()
                devLog("✅ CoreDataManager: UserId migration complete! Migrated \(totalMigrated) total entries")
            } catch {
                devLog("❌ CoreDataManager: UserId migration save failed: \(error)")
            }
        } else {
            devLog("✅ CoreDataManager: UserId migration complete! No entries needed migration")
        }

        defaults.set(true, forKey: userIdMigrationFlagKey)
    }

    // MARK: - Task Time Windows
    func saveTaskTimeWindow(_ timeWindow: TaskTimeWindowData) {
        // Check if a time window already exists for this task ID
        let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        request.predicate = NSPredicate(format: "taskId == %@", timeWindow.taskId)

        let existingWindow: TaskTimeWindow
        do {
            let results = try context.fetch(request)

            if let existing = results.first {
            existingWindow = existing
            // Update existing
            existingWindow.taskId = timeWindow.taskId
            existingWindow.startTime = timeWindow.startTime
            existingWindow.endTime = timeWindow.endTime
            existingWindow.isAllDay = timeWindow.isAllDay
            existingWindow.userId = timeWindow.userId
            existingWindow.updatedAt = Date()

                // Delete any duplicate entries (keep only the one we're updating)
                if results.count > 1 {
                    for duplicate in results.dropFirst() {
                        context.delete(duplicate)
                    }
                }
        } else {
            // Create new
                existingWindow = TaskTimeWindow(context: context)
                existingWindow.id = timeWindow.id
                existingWindow.taskId = timeWindow.taskId
                existingWindow.startTime = timeWindow.startTime
                existingWindow.endTime = timeWindow.endTime
                existingWindow.isAllDay = timeWindow.isAllDay
                existingWindow.userId = timeWindow.userId
                existingWindow.createdAt = timeWindow.createdAt
                existingWindow.updatedAt = timeWindow.updatedAt
            }
        } catch {
            // Fallback to creating new
            existingWindow = TaskTimeWindow(context: context)
            existingWindow.id = timeWindow.id
            existingWindow.taskId = timeWindow.taskId
            existingWindow.startTime = timeWindow.startTime
            existingWindow.endTime = timeWindow.endTime
            existingWindow.isAllDay = timeWindow.isAllDay
            existingWindow.userId = timeWindow.userId
            existingWindow.createdAt = timeWindow.createdAt
            existingWindow.updatedAt = timeWindow.updatedAt
        }

        save()
    }
    
    func loadTaskTimeWindow(for taskId: String) -> TaskTimeWindowData? {
        let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        request.predicate = NSPredicate(format: "taskId == %@", taskId)
        request.fetchLimit = 1
        
        do {
            let windows = try context.fetch(request)
            guard let window = windows.first,
                  let id = window.id,
                  let taskId = window.taskId,
                  let startTime = window.startTime,
                  let endTime = window.endTime,
                  let userId = window.userId,
                  let createdAt = window.createdAt,
                  let updatedAt = window.updatedAt else {
                return nil
            }
            
            return TaskTimeWindowData(
                id: id,
                taskId: taskId,
                startTime: startTime,
                endTime: endTime,
                isAllDay: window.isAllDay,
                userId: userId,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        } catch {
            return nil
        }
    }
    
    func loadAllTaskTimeWindows(for userId: String? = nil) -> [TaskTimeWindowData] {
        let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TaskTimeWindow.createdAt, ascending: false)]

        if let userId = userId {
            request.predicate = NSPredicate(format: "userId == %@", userId)
        }

        do {
            let windows = try context.fetch(request)

            let result: [TaskTimeWindowData] = windows.compactMap { window in
                guard let id = window.id,
                      let taskId = window.taskId,
                      let startTime = window.startTime,
                      let endTime = window.endTime,
                      let userId = window.userId,
                      let createdAt = window.createdAt,
                      let updatedAt = window.updatedAt else {
                    return nil
                }

                return TaskTimeWindowData(
                    id: id,
                    taskId: taskId,
                    startTime: startTime,
                    endTime: endTime,
                    isAllDay: window.isAllDay,
                    userId: userId,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            }

            return result
        } catch {
            return []
        }
    }
    
    func deleteTaskTimeWindow(for taskId: String) {
        let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        request.predicate = NSPredicate(format: "taskId == %@", taskId)
        
        do {
            let windows = try context.fetch(request)
            windows.forEach(context.delete)
            save()
        } catch {
        }
    }
    
    // MARK: - Cleanup Duplicates
    /// Remove duplicate TaskTimeWindow entries, keeping only the most recently updated one for each taskId
    func cleanupDuplicateTaskTimeWindows() {
        let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TaskTimeWindow.taskId, ascending: true)]

        do {
            let allWindows = try context.fetch(request)

            // Group by taskId
            var taskIdToWindows: [String: [TaskTimeWindow]] = [:]
            for window in allWindows {
                guard let taskId = window.taskId else { continue }
                taskIdToWindows[taskId, default: []].append(window)
            }

            var duplicatesDeleted = 0
            var migratedCount = 0

            // For each taskId, keep only the most recent and delete the rest
            for (_, windows) in taskIdToWindows {
                if windows.count > 1 {
                    // Sort by updatedAt, most recent first
                    let sorted = windows.sorted { w1, w2 in
                        let date1 = w1.updatedAt ?? w1.createdAt ?? Date.distantPast
                        let date2 = w2.updatedAt ?? w2.createdAt ?? Date.distantPast
                        return date1 > date2
                    }

                    // Keep the first (most recent), migrate userId to "icloud-user"
                    if let keeper = sorted.first {
                        keeper.userId = "icloud-user"
                        migratedCount += 1
                    }

                    // Delete the rest
                    for duplicate in sorted.dropFirst() {
                        context.delete(duplicate)
                        duplicatesDeleted += 1
                    }
                } else if let singleWindow = windows.first {
                    // No duplicates, but migrate userId to "icloud-user" for consistency
                    singleWindow.userId = "icloud-user"
                    migratedCount += 1
                }
            }

            if duplicatesDeleted > 0 || migratedCount > 0 {
                save()
            }
        } catch { }
    }
    
    func deleteTaskTimeWindow(_ timeWindow: TaskTimeWindowData) {
        deleteTaskTimeWindow(for: timeWindow.taskId)
    }
}

// MARK: - Extensions for WeightLogEntry
extension WeightLogEntry {
    init(id: String, date: Date, time: Date, weight: Double, unit: WeightUnit, userId: String) {
        self.id = id
        self.date = date
        self.time = time
        self.weight = weight
        self.unit = unit
        self.userId = userId
    }
}

// MARK: - Extensions for WorkoutLogEntry
extension WorkoutLogEntry {
    init(id: String, date: Date, name: String, userId: String, createdAt: Date) {
        self.id = id
        self.date = date
        self.name = name
        self.workoutTypeRaw = nil
        self.userId = userId
        self.createdAt = createdAt
    }
}

// MARK: - Extensions for FoodLogEntry
extension FoodLogEntry {
    init(id: String, date: Date, name: String, userId: String, createdAt: Date) {
        self.id = id
        self.date = date
        self.name = name
        self.userId = userId
        self.createdAt = createdAt
    }
} 