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
    }
    
    private func migrateExistingCategories() {
        // Migration will be handled when Core Data model is updated
    }
    
    // MARK: - Save Context
    private func save() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
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
        workoutLog.userId = entry.userId
        workoutLog.createdAt = entry.createdAt
        
        save()
    }
    
    func loadWorkoutEntries() -> [WorkoutLogEntry] {
        let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutLog.date, ascending: false)]
        
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
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FoodLog.date, ascending: false)]
        
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
    
    // MARK: - Danger Zone: Delete All Logs
    func deleteAllLogs() {
        let deleteRequests: [NSFetchRequest<NSFetchRequestResult>] = [
            WeightLog.fetchRequest(),
            WorkoutLog.fetchRequest(),
            FoodLog.fetchRequest()
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