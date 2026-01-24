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
                devLog("💾 CoreDataManager: Saving \(context.insertedObjects.count) new, \(context.updatedObjects.count) updated, \(context.deletedObjects.count) deleted objects")
                try context.save()
                devLog("✅ CoreDataManager: Context save successful")
                
                // Force the parent context (if any) to save as well
                if let parentContext = context.parent {
                    devLog("💾 CoreDataManager: Saving parent context...")
                    try parentContext.save()
                    devLog("✅ CoreDataManager: Parent context saved")
                }
                
            } catch {
                devLog("❌ CoreDataManager: SAVE FAILED: \(error)")
                devLog("❌ CoreDataManager: Error details: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    devLog("❌ CoreDataManager: Domain: \(nsError.domain), Code: \(nsError.code)")
                    if let detailedErrors = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] {
                        for detailedError in detailedErrors {
                            devLog("❌ CoreDataManager: Detailed error: \(detailedError)")
                        }
                    }
                }
            }
        } else {
            devLog("💾 CoreDataManager: No changes to save")
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
        workoutLog.userId = entry.userId
        workoutLog.createdAt = entry.createdAt
        
        save()
    }
    
    func loadWorkoutEntries() -> [WorkoutLogEntry] {
        let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutLog.createdAt, ascending: false)]
        
        do {
            let logs = try context.fetch(request)
            return logs.compactMap { log in
                guard let id = log.id,
                      let date = log.date,
                      let name = log.name,
                      let userId = log.userId,
                      let createdAt = log.createdAt else { return nil }
                
                return WorkoutLogEntry(
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
        devLog("💾 CoreDataManager: saveTaskTimeWindow called for taskId: \(timeWindow.taskId)")
        devLog("💾   startTime: \(timeWindow.startTime), endTime: \(timeWindow.endTime), isAllDay: \(timeWindow.isAllDay)")
        
        // Check if a time window already exists for this task ID
        let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        request.predicate = NSPredicate(format: "taskId == %@", timeWindow.taskId)
        
        devLog("💾   Searching for existing TaskTimeWindow with taskId: \(timeWindow.taskId)")
        
        let existingWindow: TaskTimeWindow
        do {
            let results = try context.fetch(request)
            devLog("💾   Found \(results.count) existing TaskTimeWindow(s) for this taskId")
            
            if let existing = results.first {
                devLog("💾   Updating existing TaskTimeWindow (id: \(existing.id ?? "nil"))")
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
                    devLog("⚠️   Found \(results.count - 1) duplicate(s)! Deleting them...")
                    for duplicate in results.dropFirst() {
                        context.delete(duplicate)
                        devLog("💾   Deleted duplicate with id: \(duplicate.id ?? "nil")")
                    }
                }
        } else {
                devLog("💾   Creating new TaskTimeWindow...")
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
            devLog("❌ CoreDataManager: Failed to fetch existing TaskTimeWindow: \(error)")
            // Fallback to creating new
            devLog("💾   Creating new TaskTimeWindow as fallback...")
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
        
        devLog("💾   Calling save()...")
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
        devLog("📖 CoreDataManager: loadAllTaskTimeWindows called for userId: \(userId ?? "nil")")
        
        let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TaskTimeWindow.createdAt, ascending: false)]
        
        if let userId = userId {
            request.predicate = NSPredicate(format: "userId == %@", userId)
        }
        
        do {
            let windows = try context.fetch(request)
            devLog("📖 CoreDataManager: Fetched \(windows.count) TaskTimeWindow objects from Core Data")
            
            let result: [TaskTimeWindowData] = windows.compactMap { window in
                guard let id = window.id,
                      let taskId = window.taskId,
                      let startTime = window.startTime,
                      let endTime = window.endTime,
                      let userId = window.userId,
                      let createdAt = window.createdAt,
                      let updatedAt = window.updatedAt else {
                    devLog("⚠️ CoreDataManager: Skipping invalid TaskTimeWindow (missing required fields)")
                    return nil
                }
                
                devLog("📖   - TaskTimeWindow: taskId=\(taskId), startTime=\(startTime), endTime=\(endTime)")
                
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
            
            devLog("📖 CoreDataManager: Returning \(result.count) valid TaskTimeWindow objects")
            return result
        } catch {
            devLog("❌ CoreDataManager: Failed to fetch TaskTimeWindow objects: \(error)")
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
        devLog("🧹 CoreDataManager: Starting duplicate TaskTimeWindow cleanup...")
        
        let request: NSFetchRequest<TaskTimeWindow> = TaskTimeWindow.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TaskTimeWindow.taskId, ascending: true)]
        
        do {
            let allWindows = try context.fetch(request)
            devLog("🧹   Total TaskTimeWindow entries: \(allWindows.count)")
            
            // Group by taskId
            var taskIdToWindows: [String: [TaskTimeWindow]] = [:]
            for window in allWindows {
                guard let taskId = window.taskId else { continue }
                taskIdToWindows[taskId, default: []].append(window)
            }
            
            var duplicatesDeleted = 0
            var migratedCount = 0
            
            // For each taskId, keep only the most recent and delete the rest
            for (taskId, windows) in taskIdToWindows {
                if windows.count > 1 {
                    devLog("🧹   Found \(windows.count) duplicates for taskId: \(taskId)")
                    
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
                        devLog("🧹     Deleting duplicate: startTime=\(duplicate.startTime ?? Date())")
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
                devLog("🧹   Deleted \(duplicatesDeleted) duplicate entries")
                devLog("🧹   Migrated \(migratedCount) entries to unified userId")
                save()
                devLog("✅ CoreDataManager: Duplicate cleanup and migration completed!")
            } else {
                devLog("✅ CoreDataManager: No duplicates found, database is clean!")
            }
            
        } catch {
            devLog("❌ CoreDataManager: Failed to cleanup duplicates: \(error)")
        }
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